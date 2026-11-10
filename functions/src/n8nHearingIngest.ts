/**
 * n8n / AI automation webhook → Firestore `hearings` stamp.
 * Rejects promotional mail; writes structured court-order fields + full text.
 */
import * as logger from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";
import * as admin from "firebase-admin";
import {
  buildNotificationBody,
  deliverHearingNotification,
  resolveClientUidsByHearingName,
  splitHearingPartyNames,
  type HearingDoc,
} from "./hearingNotifications";
import { sendHearingSmsAlerts } from "./hearingSmsAlerts";
import { isOutOfSystemPumpedNoticeText } from "./outOfSystemNotice";

const ingestSecret = defineSecret("INGEST_SECRET");
const ingestSecretParam = defineString("INGEST_SECRET_FALLBACK", {
  default: "",
});
/** Same secret as onHearingActivityCreated — n8n must SMS in-request (CPU freezes after HTTP). */
const philsmsApiTokenParam = defineSecret("PHILSMS_API_TOKEN");
const philsmsSenderIdParam = defineString("PHILSMS_SENDER_ID", {
  default: "PhilSMS",
});
const philsmsAlertPhonesParam = defineString("PHILSMS_ALERT_PHONES", {
  default: "09351914214",
});
const philsmsStaffAlertPhonesParam = defineString("PHILSMS_STAFF_ALERT_PHONES", {
  default: "",
});
const philsmsFirmPhonesOnlyParam = defineString("PHILSMS_FIRM_PHONES_ONLY", {
  default: "true",
});
const semaphoreApiKeyParam = defineString("SEMAPHORE_API_KEY", { default: "" });
const semaphoreSenderNameParam = defineString("SEMAPHORE_SENDER_NAME", {
  default: "LAWCONNECT",
});

function parsePhoneList(raw: string): string[] {
  return raw
    .split(",")
    .map((p) => p.trim())
    .filter(Boolean);
}

function asString(v: unknown): string {
  if (v === undefined || v === null) return "";
  if (typeof v === "string") return v.trim();
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (v instanceof Date) return v.toISOString();
  if (Array.isArray(v)) {
    for (const item of v) {
      const s = asString(item);
      if (s) return s;
    }
    return "";
  }
  if (typeof v === "object") {
    // n8n / AI nodes sometimes send { value: "June 15, 2024" } or
    // { date: "...", formatted: "..." } â€” never store "[object Object]".
    const rec = v as Record<string, unknown>;
    for (const key of ["value", "text", "formatted", "display", "date", "start", "label", "name"]) {
      const s = asString(rec[key]);
      if (s) return s;
    }
    return "";
  }
  return "";
}

function stripHtml(raw: string): string {
  return raw
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+\n/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

function pickString(body: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const v = asString(body[key]);
    if (v) return v;
  }
  return "";
}

function coerceRecord(input: unknown): Record<string, unknown> {
  if (input == null) return {};
  if (typeof input === "string") {
    const t = input.trim();
    if (
      (t.startsWith("{") && t.endsWith("}")) ||
      (t.startsWith("[") && t.endsWith("]"))
    ) {
      try {
        return coerceRecord(JSON.parse(t));
      } catch {
        return t ? { text: t } : {};
      }
    }
    return t ? { text: t } : {};
  }
  if (Array.isArray(input)) {
    const first =
      input.find((x) => x && typeof x === "object") ?? input[0];
    return coerceRecord(first);
  }
  if (typeof input === "object") {
    return input as Record<string, unknown>;
  }
  return {};
}

function flattenGmail(raw: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...raw };
  const snippet = asString(raw.snippet);
  if (snippet && !asString(out.text)) out.text = snippet;

  const payload = coerceRecord(raw.payload);
  const headers = payload.headers;
  if (Array.isArray(headers)) {
    for (const h of headers) {
      const rec = coerceRecord(h);
      const name = asString(rec.name).toLowerCase();
      const value = asString(rec.value);
      if (!value) continue;
      if (name === "subject" && !asString(out.subject)) out.subject = value;
      if (name === "from" && !asString(out.from)) out.from = value;
    }
  }
  const bodyData = asString(coerceRecord(payload.body).data);
  if (bodyData && !asString(out.text)) {
    try {
      out.text = Buffer.from(bodyData, "base64").toString("utf8");
    } catch {
      // ignore malformed Gmail bodies
    }
  }
  return out;
}

/** n8n often wraps OpenAI/Gmail fields in data/output/json or sends an array. */
function flattenBody(body: Record<string, unknown>): Record<string, unknown> {
  let out = flattenGmail(body);
  const wrapperKeys = [
    "data",
    "output",
    "json",
    "result",
    "items",
    "hearing",
    "fields",
    "parsed",
    "analysis",
    "body",
    "payload",
  ];
  for (const key of wrapperKeys) {
    if (!(key in out)) continue;
    const nested = flattenGmail(coerceRecord(out[key]));
    if (Object.keys(nested).length) {
      out = { ...out, ...nested };
    }
  }
  for (const key of ["text", "content", "message", "ocrText", "output"]) {
    const v = out[key];
    if (typeof v !== "string") continue;
    const t = v.trim();
    if (!t.startsWith("{") && !t.startsWith("[")) continue;
    const nested = flattenGmail(coerceRecord(t));
    if (
      pickString(nested, ["caseNo", "case_no", "caseNumber", "fullText"]) ||
      pickString(nested, ["hearingDate", "clientName", "client"]) ||
      pickString(nested, ["subject", "text", "snippet"])
    ) {
      out = { ...out, ...nested };
    }
  }
  return out;
}

function expectedSecret(): string {
  try {
    const fromSecret = ingestSecret.value().trim();
    if (fromSecret) return fromSecret;
  } catch (e) {
    logger.warn("INGEST_SECRET secret unavailable", {
      err: e instanceof Error ? e.message : String(e),
    });
  }
  try {
    const fromParam = ingestSecretParam.value().trim();
    if (fromParam) return fromParam;
  } catch {
    // ignore
  }
  return asString(process.env.INGEST_SECRET);
}

function providedSecret(req: {
  get: (name: string) => string | undefined;
  query?: Record<string, unknown>;
  body?: unknown;
}): string {
  const headerNames = [
    "x-ingest-secret",
    "ingest-secret",
    "x-api-key",
    "authorization",
  ];
  for (const name of headerNames) {
    const raw = asString(req.get(name));
    if (!raw) continue;
    if (/^bearer\s+/i.test(raw)) return raw.replace(/^bearer\s+/i, "").trim();
    return raw;
  }
  const q = req.query ?? {};
  const fromQuery =
    asString(q.ingestSecret) ||
    asString(q.ingest_secret) ||
    asString(q.secret);
  if (fromQuery) return fromQuery;

  const body = coerceRecord(req.body);
  return pickString(body, ["ingestSecret", "ingest_secret", "secret"]);
}

function secretMatches(req: {
  get: (name: string) => string | undefined;
  query?: Record<string, unknown>;
  body?: unknown;
}): boolean {
  const expected = expectedSecret();
  if (!expected) return false;
  const provided = providedSecret(req);
  return Boolean(provided) && provided === expected;
}

const MONTHS: Record<string, number> = {
  january: 0,
  february: 1,
  march: 2,
  april: 3,
  may: 4,
  june: 5,
  july: 6,
  august: 7,
  september: 8,
  october: 9,
  november: 10,
  december: 11,
};

function isPlaceholderCaseNo(cn: string): boolean {
  const s = cn.trim().toLowerCase().replace(/\s+/g, " ");
  return (
    !s ||
    s === "court order" ||
    s === "court hearing" ||
    s === "hearing" ||
    s === "order" ||
    s === "n/a" ||
    s === "na" ||
    s === "none" ||
    s === "unknown"
  );
}

function isProductOrDevEmailBlob(blob: string): boolean {
  const t = blob.toLowerCase();
  const markers = [
    "cursor.com",
    "cursor.sh",
    "cursor team",
    "anysphere",
    "browser layout editor",
    "browser-based layout editor",
    "debug mode",
    "changelog/2-2",
    "writing and fixing code faster",
    "try debug mode",
    "firebase.google.com",
    "cloud.google.com",
    "github.com",
    "gitlab.com",
    "vercel.com",
    "netlify.com",
    "dear developer",
  ];
  return markers.some((m) => t.includes(m));
}

function isEatingTestHearing(
  subject: string,
  text: string,
  raw: Record<string, unknown>,
): boolean {
  const extra = pickString(raw, [
    "title",
    "caseTitle",
    "clientName",
    "hearingPurpose",
    "activityType",
    "summary",
  ]);
  const t = `${subject}\n${text}\n${extra}`.toLowerCase();
  const compact = t.replace(/[^a-z0-9]+/g, " ");
  if (
    t.includes("[ai hearing (eating)]") ||
    t.includes("hearing (eating)") ||
    compact.includes("ai hearing eating") ||
    compact.includes("hearing eating")
  ) {
    return true;
  }
  return /\beating\b/.test(t) && !isCourtOrderText(t);
}

function isPromotionalJunk(
  subject: string,
  text: string,
  raw: Record<string, unknown>,
): boolean {
  if (isEatingTestHearing(subject, text, raw)) return true;
  const blob = `${subject}\n${text}`;
  if (isOutOfSystemPumpedNoticeText(blob)) return true;
  if (isProductOrDevEmailBlob(blob)) return true;
  if (isCourtOrderText(blob)) return false;
  if (hasStructuredHearingFields(raw)) return false;
  const t = `${subject}\n${text}`.toLowerCase();
  const markers = [
    "blasttv",
    "voucher code",
    "voucher redemption",
    "enjoy your 30-day",
    "netflix",
    "spotify",
    "[ai hearing (eating)]",
    "hearing (eating)",
    "payment receipt",
    "your order has shipped",
    "limited time offer",
    "your order has been delivered",
    "order has been delivered",
    "thanks for shopping",
    "ollama",
    "canva",
    "google account data",
  ];
  if (markers.some((m) => t.includes(m))) return true;
  if (t.includes("eating") && !isCourtOrderText(t)) return true;
  if (isGibberishNoticeText(subject) && !isCourtOrderText(t)) {
    return true;
  }
  return false;
}

function hasStructuredHearingFields(raw: Record<string, unknown>): boolean {
  const caseNo = pickString(raw, [
    "caseNo",
    "caseNumber",
    "case_no",
    "case_number",
    "docketNo",
    "docket_no",
  ]);
  return Boolean(
    (caseNo && !isPlaceholderCaseNo(caseNo) ? caseNo : "") ||
    pickString(raw, ["clientName", "client", "party", "parties"]) ||
    pickString(raw, ["hearingDate", "hearing_date", "date"]) ||
    pickString(raw, ["courtBranch", "court", "branch", "location"]) ||
    pickString(raw, ["hearingTime", "hearing_time", "time"]),
  );
}

function isGibberishNoticeText(raw: string): boolean {
  const t = raw.trim();
  if (!t) return false;
  const words = t.split(/[^a-zA-Z0-9]+/).filter(Boolean);
  if (words.length === 1) return isGibberishToken(words[0]);
  const significant = words.filter(
    (w) => w.length >= 8 && !/^(hearing|scheduled|updated|message|notice|court|order)$/i.test(w),
  );
  return significant.length > 0 && significant.every(isGibberishToken);
}

function isGibberishToken(raw: string): boolean {
  if (/\d/.test(raw)) return false;
  const s = raw.toLowerCase().replace(/[^a-z]/g, "");
  if (s.length < 8) return false;
  if (/(hearing|court|trial|arraignment)/.test(s)) return false;
  if (/(.)\1{2,}/.test(s)) return true;
  if (/(.{2,5})\1/.test(s)) return true;
  if (!/[aeiou]/.test(s)) return true;
  if (/[^aeiou]{4,}/.test(s)) return true;
  return false;
}

function isCourtOrderText(text: string): boolean {
  const t = text.toLowerCase();
  if (!t.trim()) return false;
  const signals = [
    "wherefore",
    "so ordered",
    "regional trial court",
    "people of the philippines",
    "in open court",
    "spec. case",
    "special civil",
    "versus",
    " vs.",
    " vs ",
    "reset the hearing",
    "hearing of this case",
    "court of",
    "branch ",
  ];
  const hits = signals.filter((s) => t.includes(s)).length;
  if (hits >= 2) return true;
  if (t.includes("case no") && (t.includes("hearing") || t.includes("court"))) {
    return true;
  }
  return false;
}

function cleanCaseDocketNo(raw: string): string {
  if (!raw) return "";
  const t = raw.trim();
  const stripped = t.replace(
    /^(?:civil|criminal|special(?:\s+proceedings)?|spec\.?\s*proc\.?|spec\.?)?\s*case\s*(?:no\.?|#)?\s*[:\-]?\s*/i,
    "",
  ).trim();
  return stripped || t;
}

function extractCaseNo(text: string, fallback: string): string {
  const patterns = [
    /((?:spec(?:ial)?\.?\s*case\s*no\.?\s*)[A-Za-z0-9\-_/]+)/i,
    /(civil\s*case\s*no\.?\s*[A-Za-z0-9\-_/]+)/i,
    /(criminal\s*case\s*no\.?\s*[A-Za-z0-9\-_/]+)/i,
    /case\s*(?:no\.?|number|#)\s*[:\s]*([A-Za-z0-9\-_/]+)/i,
  ];
  for (const re of patterns) {
    const m = text.match(re);
    if (m?.[1]) {
      const clean = cleanCaseDocketNo(m[1].replace(/\s+/g, " ").trim());
      if (clean) return clean;
    }
  }
  return cleanCaseDocketNo(fallback);
}

function extractCaseTitle(text: string): string {
  // Line-based Philippine court caption matching:
  const lines = text
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
  const vsIdx = lines.findIndex(
    (l) =>
      /^[-–—]?\s*(?:versus|vs\.?)\s*[-–—]?$/i.test(l) ||
      /[-–—]\s*versus\s*[-–—]/i.test(l),
  );
  if (vsIdx !== -1) {
    const plaintiffLines: string[] = [];
    for (let i = vsIdx - 1; i >= 0; i--) {
      const line = lines[i];
      if (
        /^(?:Republic|REGIONAL|MUNICIPAL|10th|\d+(?:st|nd|rd|th)\s+Judicial|BRANCH|Email|Contact)/i.test(
          line,
        )
      ) {
        break;
      }
      if (/^Plaintiffs?,?$/i.test(line)) continue;
      plaintiffLines.unshift(line);
    }
    const plaintiff = plaintiffLines.join(" ");
    const mainPlaintiff = plaintiff
      .split(/,\s*Namely:/i)[0]
      .split(/Namely:/i)[0]
      .trim();

    const defLines: string[] = [];
    for (let i = vsIdx + 1; i < lines.length; i++) {
      const line = lines[i];
      if (/^(?:Civil|Criminal|Special|Spec\.?)\s*Case/i.test(line)) continue;
      if (/^\d{3,}/.test(line)) continue;
      if (
        /^(?:For\s*:|Recovery of|Ownership|Possession|Damages|Injunction)/i.test(
          line,
        )
      ) {
        continue;
      }
      if (/^[xX]\s*[-–—]+\s*[xX]$/.test(line) || /^ORDER$/i.test(line)) break;
      if (/Defendants?,?\.?$/i.test(line)) {
        const cleaned = line.replace(/,?\s*Defendants?,?\.?$/i, "").trim();
        if (cleaned) defLines.push(cleaned);
        break;
      }
      defLines.push(line);
    }
    let defendants = defLines
      .join(" ")
      .replace(/\s+/g, " ")
      .replace(/,?\s*Defendants?,?\.?$/i, "")
      .trim();
    while (defendants.endsWith(",")) {
      defendants = defendants.slice(0, -1).trim();
    }
    if (mainPlaintiff.length >= 3 && defendants.length >= 3) {
      return `${mainPlaintiff} vs. ${defendants}`;
    }
  }

  const vs = text.match(
    /([A-Z][A-Za-z0-9.,'’&\-\s]{3,80}?)\s+(?:vs\.?|versus)\s+([A-Z][A-Za-z0-9.,'’&\-\s]{3,120})/,
  );
  if (vs) {
    return `${vs[1].trim()} vs. ${vs[2].trim().replace(/[.,;]+$/, "")}`;
  }
  return "";
}

function extractClient(text: string, caseTitle: string, fallback: string): string {
  const fb = normalizeWhitespace(fallback);
  const vsParts = caseTitle.split(/\s+vs\.?\s+/i);
  const vsRight = vsParts.length > 1 ? vsParts[1].trim() : "";

  const representsDefendants =
    /(?:appeared\s+in\s+court\s+for|counsel\s+for)\s+(?:the\s+)?(?:answering\s+)?defendants/i.test(
      text,
    );
  if ((representsDefendants || vsRight) && vsRight.length > 3) {
    return vsRight;
  }

  const hasManyParties =
    /[,;&]|\band\b/i.test(fb) || splitHearingPartyNames(fb).length > 1;
  if (hasManyParties && !fb.toLowerCase().startsWith("heirs of")) return fb;

  const vsLeft = vsParts.length ? vsParts[0].trim() : "";
  const petitioner = text.match(
    /(?:petitioner|plaintiff|applicant)\s*[:\-]\s*([^\n]{3,400})/i,
  );
  const petitionerText = petitioner?.[1]?.trim() ?? "";
  const richest = [fb, petitionerText, vsLeft]
    .filter((s) => s.length > 0)
    .sort((a, b) => {
      const pa = splitHearingPartyNames(a).length;
      const pb = splitHearingPartyNames(b).length;
      if (pb !== pa) return pb - pa;
      return b.length - a.length;
    })[0];
  return richest || fb;
}

function normalizeWhitespace(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

function extractHearingDate(text: string): string {
  const m = text.match(
    /(?:on\s+)?(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})\s*,?\s+(\d{4})/i,
  );
  if (!m) return "";
  return `${m[1]} ${m[2]}, ${m[3]}`;
}

function extractHearingTime(text: string): string {
  const clock = text.match(
    /(\d{1,2}:\d{2})\s*(?:o['’]?clock\s+)?(?:in the morning|in the afternoon|a\.?m\.?|p\.?m\.?)/i,
  );
  if (clock) return clock[0].replace(/\s+/g, " ").trim();
  const at = text.match(/at\s+(\d{1,2}:\d{2}\s*(?:a\.?m\.?|p\.?m\.?)?)/i);
  return at?.[1]?.trim() ?? "";
}

function extractLocation(text: string, fallback: string): string {
  const branchFull = text.match(
    /branch\s*(\d+)(?:\s*[-–—]\s*([^\r\n]+)|,\s*([^\r\n]+))/i,
  );
  if (branchFull) {
    const branchNum = branchFull[1];
    let city = (branchFull[2] || branchFull[3] || "").trim();
    city = city.replace(/[\r\n]+/g, " ").replace(/[.,\s]+$/, "").trim();
    if (city) {
      return `Branch ${branchNum} - ${city}`;
    }
  }
  const branch = text.match(/branch\s*(\d+)(?:\s*[-–—]\s*([A-Za-z .]+))?/i);
  const rtc = text.match(
    /((?:regional|municipal|metropolitan)\s+trial\s+court[^\n,]{0,80}(?:,\s*[A-Za-z .]+)?)/i,
  );
  const region = text.match(/(\d+(?:st|nd|rd|th)\s+judicial region)/i);

  let city = (branch?.[2] || "").trim();
  if (!city) {
    const nextLineCity = text.match(
      /branch\s*\d+\s*[\r\n]+\s*([A-Za-z\s.]+City|[A-Za-z\s.]+Province|Hall of Justice[^\r\n]*)/i,
    );
    if (nextLineCity) {
      city = nextLineCity[1].replace(/[.,\s]+$/, "").trim();
    }
  }

  if (branch && rtc) {
    let court = rtc[1].replace(/\s+/g, " ").trim();
    if (region && !court.toLowerCase().includes("judicial")) {
      court = `${court}, ${region[1]}`;
    }
    if (city && !court.toLowerCase().includes(city.toLowerCase())) {
      court = `${court}, ${city}`;
    }
    return `Branch ${branch[1]} — ${court}`;
  }
  if (branch && city) {
    return `Branch ${branch[1]} - ${city}`;
  }
  if (rtc) return rtc[1].replace(/\s+/g, " ").trim();
  if (branch) {
    if (fallback && !/^(?:branch\s*\d+|\d+)$/i.test(fallback.trim())) {
      return fallback;
    }
    return `Branch ${branch[1]}`;
  }
  return fallback;
}

function cleanOrderSummaryText(text: string): string {
  let s = text.replace(/\s+/g, " ").trim();
  s = s.replace(/\s+,/g, ",");
  s = s.replace(/\s+\./g, ".");
  // Strip trailing incomplete time markers or dangling prepositions like " a...", " on", " at"
  s = s.replace(/\s+(?:a|p)\.{0,3}$/i, "");
  s = s.replace(/\s+(?:on|at|for|the|and|or|in)\s*\.{0,3}$/i, "");
  s = s.replace(/[,;:\s–—]+$/, "").trim();
  if (s && !/[.!?]$/.test(s)) s = `${s}.`;
  if (s && s[0].toLowerCase() === s[0]) {
    s = s[0].toUpperCase() + s.slice(1);
  }
  return s;
}

function extractSummary(text: string): string {
  const start = text.search(/WHEREFORE\b/i);
  if (start >= 0) {
    let chunk = text.slice(start);
    const stop = chunk.search(/\b(?:SO ORDERED|Page\s+\d+)\b/i);
    if (stop > 15) chunk = chunk.slice(0, stop);
    chunk = cleanOrderSummaryText(chunk);
    const max = 420;
    if (chunk.length > max) {
      const dot = chunk.lastIndexOf(".", max);
      if (dot >= 40) chunk = chunk.slice(0, dot + 1).trim();
    }
    return cleanOrderSummaryText(chunk);
  }
  const reset = text.match(
    /(?:hearing\s+of\s+the\s+above-entitled\s+case|the\s+continuation\s+of\s+(?:the\s+)?proceedings|the\s+court\s+hereby\s+sets|reset|set|scheduled)[\s\S]{10,400}?(?:morning|afternoon|a\.?m\.?|p\.?m\.?|o['’]?clock)/i,
  );
  if (reset) {
    let s = reset[0];
    const rest = text.slice(reset.index!);
    const sentenceEnd = rest.match(/^[\s\S]+?\.\s+/);
    if (sentenceEnd && sentenceEnd[0].length <= 420) {
      s = sentenceEnd[0];
    }
    return cleanOrderSummaryText(s);
  }
  const clean = cleanOrderSummaryText(text);
  if (clean.length > 280) {
    const dot = clean.lastIndexOf(".", 280);
    if (dot >= 50) return clean.slice(0, dot + 1).trim();
    return `${clean.slice(0, 277)}…`;
  }
  return clean;
}

function parseHearingTimestamp(dateStr: string, timeStr: string): admin.firestore.Timestamp | null {
  if (!dateStr) return null;
  const dm = dateStr.match(
    /(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})/i,
  );
  if (!dm) {
    const d = new Date(dateStr);
    return Number.isNaN(d.getTime())
      ? null
      : admin.firestore.Timestamp.fromDate(d);
  }
  const month = MONTHS[dm[1].toLowerCase()];
  const day = parseInt(dm[2], 10);
  const year = parseInt(dm[3], 10);
  let hour = 9;
  let minute = 0;
  const tm = timeStr.match(/(\d{1,2}):(\d{2})/);
  if (tm) {
    hour = parseInt(tm[1], 10);
    minute = parseInt(tm[2], 10);
    const afternoon =
      /p\.?m\.?|afternoon/i.test(timeStr) ||
      /in the afternoon/i.test(timeStr);
    if (afternoon && hour < 12) hour += 12;
    if (/a\.?m\.?|morning/i.test(timeStr) && hour === 12) hour = 0;
  }
  return admin.firestore.Timestamp.fromDate(
    new Date(year, month, day, hour, minute),
  );
}

async function fanOutHearingInbox(params: {
  db: admin.firestore.Firestore;
  hearingRef: admin.firestore.DocumentReference;
  hearingPayload: Record<string, unknown>;
  caseId: string;
  caseTitle: string;
  clientName: string;
  courtBranch: string;
  location: string;
  hearingDate: string;
  hearingTime: string;
  orderText: string;
  attorneyUid: string;
}): Promise<void> {
  const {
    db,
    hearingRef,
    hearingPayload,
    caseId,
    caseTitle,
    clientName,
    courtBranch,
    location,
    hearingDate,
    hearingTime,
    orderText,
  } = params;
  let attorneyUid = params.attorneyUid;

  try {
    const settings = await Promise.race([
      db.collection("app_settings").doc("email_ingest").get(),
      new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error("settings timeout")), 1500);
      }),
    ]);
    const cfg = settings.data() ?? {};
    if (!attorneyUid) attorneyUid = asString(cfg.defaultAttorneyId);
    const automationUserId = asString(cfg.automationUserId);
    const patch: Record<string, unknown> = {};
    if (attorneyUid && !hearingPayload.attorneyUid) {
      patch.attorneyUid = attorneyUid;
      patch.notifyUserIds = [attorneyUid];
    }
    if (automationUserId) {
      patch.uploadedBy = automationUserId;
      patch.createdBy = automationUserId;
    }
    if (Object.keys(patch).length) {
      await hearingRef.set(patch, { merge: true });
    }
  } catch (e) {
    logger.warn("n8n hearing ingest settings skipped", {
      err: e instanceof Error ? e.message : String(e),
    });
  }

  const recipients = new Set<string>();
  const clientUids: string[] = [];
  if (attorneyUid) recipients.add(attorneyUid);
  try {
    const [attorneys, staff, admins, matchedClients] = await Promise.all([
      db.collection("users").where("role", "==", "attorney").limit(40).get(),
      db.collection("users").where("role", "==", "staff").limit(40).get(),
      db.collection("users").where("role", "==", "admin").limit(15).get(),
      resolveClientUidsByHearingName(db, clientName, {
        scanAllClients: true,
        caseTitle,
        fullText: orderText,
      }),
    ]);
    for (const d of attorneys.docs) {
      if (d.data()?.isActive === false) continue;
      recipients.add(d.id);
    }
    for (const d of staff.docs) {
      if (d.data()?.isActive === false) continue;
      recipients.add(d.id);
    }
    for (const d of admins.docs) {
      if (d.data()?.isActive === false) continue;
      recipients.add(d.id);
    }
    for (const uid of matchedClients) {
      recipients.add(uid);
      clientUids.push(uid);
    }
    if (clientUids.length) {
      await hearingRef.set(
        {
          involvedClientIds: admin.firestore.FieldValue.arrayUnion(...clientUids),
          matchedClientIds: admin.firestore.FieldValue.arrayUnion(...clientUids),
        },
        { merge: true },
      );
    }
  } catch (e) {
    logger.warn("n8n hearing ingest recipient fanout skipped", {
      err: e instanceof Error ? e.message : String(e),
    });
  }

  if (recipients.size) {
    try {
      const hearingDoc = hearingPayload as HearingDoc;
      const caseLabel = asString(hearingPayload.caseNo) || "Court order";
      const dateLabel = (hearingDate || "").trim();
      const title = dateLabel
        ? `Court hearing / order — ${caseLabel} · ${dateLabel}`
        : `Court hearing / order — ${caseLabel}`;
      const body = buildNotificationBody(hearingDoc, {
        caseId: caseId || hearingRef.id,
        caseTitle: caseTitle || asString(hearingPayload.caseNo) || "Hearing",
      });
      // Inbox only here. Do NOT claim fcmPushClaimedAt — that left zombie
      // claims when FCM failed and silenced onHearingActivityCreated.
      // Phone push + SMS are owned by onHearingActivityCreated (every hearing).
      await deliverHearingNotification({
        db,
        caseId: caseId || "",
        hearingDocId: hearingRef.id,
        recipients: [...recipients],
        title,
        body,
        notificationType: "hearing_activity",
        reminderKind: null,
        hearingDoc,
        inAppOnly: true,
        clientRecipientIds: clientUids,
        data: {
          activityType: "court_import",
          source: "n8n",
          caseNo: asString(hearingPayload.caseNo),
          clientName,
          courtBranch: courtBranch || "",
          caseTitle: caseTitle || "",
          fullText: orderText,
          location: location || courtBranch || "",
          hearingDate: hearingDate || "",
          hearingTime: hearingTime || "",
        },
      });

      // SMS in this HTTP request as well (CF also tries; per-doc claim dedupes).
      const alertPhones = parsePhoneList(philsmsAlertPhonesParam.value());
      const staffRaw = philsmsStaffAlertPhonesParam.value().trim();
      const staffAlertPhones = staffRaw
        ? parsePhoneList(staffRaw)
        : alertPhones;
      const firmOnlyRaw = philsmsFirmPhonesOnlyParam.value().trim().toLowerCase();
      try {
        await sendHearingSmsAlerts({
          db,
          hearingDocId: hearingRef.id,
          hearingData: hearingPayload as HearingDoc & Record<string, unknown>,
          recipientUserIds: [...recipients],
          title,
          body,
          cfg: {
            apiToken: philsmsApiTokenParam.value().trim(),
            senderId: philsmsSenderIdParam.value().trim() || "PhilSMS",
            alertPhones,
            staffAlertPhones,
            firmPhonesOnly: firmOnlyRaw !== "false" && firmOnlyRaw !== "0",
          },
          semaphore: {
            apiKey: semaphoreApiKeyParam.value().trim(),
            senderName:
              semaphoreSenderNameParam.value().trim() || "LAWCONNECT",
          },
        });
      } catch (smsErr) {
        logger.warn("n8n hearing ingest SMS skipped", {
          hearingId: hearingRef.id,
          err: smsErr instanceof Error ? smsErr.message : String(smsErr),
        });
      }
    } catch (e) {
      logger.warn("n8n hearing ingest inbox write skipped", {
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }
}

export const courtEmailIngest = onRequest(
  {
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 60,
    secrets: [ingestSecret, philsmsApiTokenParam],
    cors: true,
    invoker: "public",
  },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method === "GET") {
      const token = asString(req.query?.validationToken);
      if (token) {
        res.status(200).send(token);
        return;
      }
      res.status(200).json({
        ok: true,
        service: "courtEmailIngest",
        hint: "POST JSON from n8n with header X-Ingest-Secret",
      });
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ ok: false, error: "POST required" });
      return;
    }
    if (!expectedSecret()) {
      res.status(500).json({
        ok: false,
        error: "INGEST_SECRET is not configured on the function",
      });
      return;
    }
    if (!secretMatches(req)) {
      res.status(401).json({
        ok: false,
        error: "Invalid ingest secret",
        hint: "Send header X-Ingest-Secret, query ingestSecret, or JSON ingestSecret",
      });
      return;
    }

    const raw = flattenBody(coerceRecord(req.body));

    const subject = pickString(raw, [
      "subject",
      "title",
      "emailSubject",
      "Subject",
    ]);
    const text = stripHtml(
      pickString(raw, [
        "fullText",
        "orderText",
        "ocrText",
        "ocr_text",
        "ocr",
        "extractedText",
        "extracted_text",
        "pdfText",
        "pdf_text",
        "text",
        "content",
        "body",
        "html",
        "message",
        "description",
        "markdown",
        "rawText",
        "snippet",
      ]),
    );
    const blob = [text, subject].filter(Boolean).join("\n\n").trim();
    const db = admin.firestore();

    const skipIngest = async (reason: string) => {
      logger.info("n8n hearing ingest skipped", { subject, reason });
      let queueId = "";
      try {
        const queueRef = await db.collection("court_email_queue").add({
          status: "skipped",
          source: "n8n",
          reason,
          subject: subject || null,
          snippet: blob ? blob.slice(0, 1500) : null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        queueId = queueRef.id;
      } catch (e) {
        logger.warn("n8n hearing ingest skip-queue write failed", {
          err: e instanceof Error ? e.message : String(e),
        });
      }
      res.status(200).json({
        ok: true,
        skipped: true,
        reason,
        queueId,
        collection: "court_email_queue",
      });
    };

    if (isPromotionalJunk(subject, blob, raw)) {
      await skipIngest("not_court_hearing");
      return;
    }

    if (!blob && !hasStructuredHearingFields(raw)) {
      await skipIngest("empty_payload");
      return;
    }

    const orderText = isCourtOrderText(text) ? text : blob;
    let caseNo = pickString(raw, [
      "caseNo",
      "caseNumber",
      "case_no",
      "case_number",
      "docketNo",
      "docket_no",
      "docketNumber",
    ]);
    caseNo = extractCaseNo(orderText, caseNo);
    if (isPlaceholderCaseNo(caseNo)) caseNo = "";
    if (!caseNo && orderText) {
      caseNo = extractCaseNo(orderText, "") || pickString(raw, ["caseNo", "caseNumber", "case_no"]) || "Court Notice";
    }
    if (!orderText && !caseNo) {
      await skipIngest("empty_payload");
      return;
    }

    let caseTitle = pickString(raw, ["caseTitle", "case_title"]);
    if (!caseTitle || !caseTitle.includes(" vs.")) {
      const resolved = extractCaseTitle(orderText);
      if (resolved && resolved.includes(" vs.")) {
        caseTitle = resolved;
      }
    }

    const parties = pickString(raw, [
      "clientName",
      "client_name",
      "client",
      "party",
      "parties",
      "petitioner",
    ]);
    const clientName = extractClient(orderText, caseTitle, parties);

    let courtBranch = pickString(raw, ["courtBranch", "court", "branch"]);
    let location = extractLocation(orderText, courtBranch);
    if (location && location.includes(" - ")) {
      const parts = location.split(/\s*[-–—]\s*/);
      if (parts.length > 1 && /branch/i.test(parts[0])) {
        if (!courtBranch) courtBranch = parts[0].trim();
        location = parts[1].trim();
        location = location
          .split(" ")
          .map((w) => (w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : ""))
          .join(" ");
      }
    }
    if (!courtBranch && location) courtBranch = location;

    let hearingDate = pickString(raw, [
      "hearingDate",
      "hearing_date",
      "dateOfHearing",
    ]);
    if (!hearingDate) hearingDate = extractHearingDate(orderText);
    let hearingTime = pickString(raw, [
      "hearingTime",
      "hearing_time",
      "timeOfHearing",
    ]);
    if (!hearingTime) hearingTime = extractHearingTime(orderText);

    const summary =
      pickString(raw, ["summary"]) || extractSummary(orderText);
    const caseId = pickString(raw, ["caseId", "case_id"]);
    let attorneyUid = pickString(raw, [
      "attorneyId",
      "attorneyUid",
      "assignedTo",
    ]);

    try {
      const hearingRef = db.collection("hearings").doc();
      const hearingDateTime = parseHearingTimestamp(
        hearingDate,
        hearingTime,
      );

      const hearingPayload: Record<string, unknown> = {
        caseNo: caseNo || "",
        fullText: orderText,
        message: orderText,
        summary,
        activityType: "court_import",
        source: pickString(raw, ["source"]) || "n8n",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ingestedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (caseTitle) hearingPayload.caseTitle = caseTitle;
      if (clientName) hearingPayload.clientName = clientName;
      const partyNames = splitHearingPartyNames(clientName);
      if (partyNames.length) hearingPayload.involvedPartyNames = partyNames;
      if (courtBranch) hearingPayload.courtBranch = courtBranch;
      if (location) hearingPayload.location = location;
      if (hearingDate) hearingPayload.hearingDate = hearingDate;
      if (hearingTime) hearingPayload.hearingTime = hearingTime;
      if (caseId) hearingPayload.caseId = caseId;
      if (attorneyUid) {
        hearingPayload.attorneyUid = attorneyUid;
        hearingPayload.notifyUserIds = [attorneyUid];
      }
      if (hearingDateTime) hearingPayload.hearingDateTime = hearingDateTime;

      await hearingRef.set(hearingPayload);

      let queueId = "";
      try {
        const queueRef = await db.collection("court_email_queue").add({
          status: "ingested",
          source: "n8n",
          hearingId: hearingRef.id,
          caseNo: hearingPayload.caseNo,
          caseTitle: caseTitle || null,
          clientName: clientName || null,
          courtBranch: courtBranch || null,
          hearingDate: hearingDate || null,
          hearingTime: hearingTime || null,
          subject: subject || null,
          snippet: blob ? blob.slice(0, 1500) : null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        queueId = queueRef.id;
      } catch (e) {
        logger.warn("n8n hearing ingest queue write skipped", {
          err: e instanceof Error ? e.message : String(e),
        });
      }

      // Cloud Run freezes CPU after the HTTP response — fan-out MUST happen first
      // or `notifications` never get written and the app looks empty.
      await fanOutHearingInbox({
        db,
        hearingRef,
        hearingPayload,
        caseId,
        caseTitle,
        clientName,
        courtBranch,
        location,
        hearingDate,
        hearingTime,
        orderText,
        attorneyUid,
      });

      logger.info("n8n hearing ingest accepted", {
        hearingId: hearingRef.id,
        queueId,
        caseNo: hearingPayload.caseNo,
      });

      res.status(200).json({
        ok: true,
        hearingId: hearingRef.id,
        queueId: queueId || hearingRef.id,
        collection: "hearings",
      });
    } catch (e) {
      logger.error("n8n hearing ingest failed", {
        err: e instanceof Error ? e.message : String(e),
      });
      if (!res.headersSent) {
        res.status(500).json({ ok: false, error: "Failed to write Firestore" });
      }
    }
  },
);
