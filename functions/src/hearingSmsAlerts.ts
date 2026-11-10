import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { sendPhilSms, normalizePhilSmsRecipient } from "./philsmsClient";
import { sendViaSemaphore } from "./semaphoreClient";
import {
  resolveClientUidsByExactHearingName,
  type HearingDoc,
} from "./hearingNotifications";

export type PhilSmsHearingCfg = {
  apiToken: string;
  senderId: string;
  /** Attorney default numbers (PHILSMS_ALERT_PHONES). */
  alertPhones: string[];
  /** Staff default numbers; defaults to alertPhones when unset. */
  staffAlertPhones: string[];
  /** When true, SMS only to firm defaults + exact-name clients (no UID blast). */
  firmPhonesOnly?: boolean;
};

export type SemaphoreHearingCfg = {
  apiKey: string;
  senderName: string;
};

/** One SMS per unique firm number; Attorney + Staff on same line → "Attorney/Staff". */
export function firmSmsTargets(
  cfg: PhilSmsHearingCfg,
): Array<{ phone: string; roleLabel: string }> {
  const byNormalized = new Map<
    string,
    { phone: string; roles: Set<string> }
  >();
  const add = (phone: string, role: string): void => {
    const normalized = normalizePhilSmsRecipient(phone);
    if (normalized.length < 11) return;
    let entry = byNormalized.get(normalized);
    if (!entry) {
      entry = { phone, roles: new Set() };
      byNormalized.set(normalized, entry);
    }
    entry.roles.add(role);
  };
  for (const phone of cfg.alertPhones) add(phone, "Attorney");
  for (const phone of cfg.staffAlertPhones) add(phone, "Staff");
  return [...byNormalized.values()].map(({ phone, roles }) => ({
    phone,
    roleLabel: [...roles].sort().join("/"),
  }));
}

const SMS_BRAND = "LAWCONNECT HEARING REMINDER";
const MAX_SMS_LENGTH = 1200;

const HEARING_DIGEST_FIELD_KEYS = [
  "caseNo",
  "caseTitle",
  "clientName",
  "courtBranch",
  "documentType",
  "fullText",
  "hearingDate",
  "hearingTime",
  "judgeName",
  "location",
  "summary",
  "hearingDateTime",
] as const;

function asString(v: unknown): string {
  return v === undefined || v === null ? "" : String(v).trim();
}

function tsField(value: unknown): string {
  if (
    value &&
    typeof value === "object" &&
    "seconds" in (value as Record<string, unknown>)
  ) {
    return String((value as admin.firestore.Timestamp).seconds);
  }
  return value?.toString() ?? "";
}

function hearingRow(data: HearingDoc & Record<string, unknown>): Record<string, unknown> {
  return data as Record<string, unknown>;
}

/** Mirrors Flutter [PhilSmsHearingAlertConfig.isSmsEligibleHearing]. */
export function isSmsEligibleHearing(data: HearingDoc & Record<string, unknown>): boolean {
  const row = hearingRow(data);
  const caseNo = asString(row.caseNo);
  if (!caseNo) return false;
  const fullText = asString(row.fullText);
  const summary = asString(row.summary);
  const hearingDate = asString(row.hearingDate);
  return Boolean(fullText || summary || hearingDate);
}

/** Mirrors Flutter digest — new content → new SMS (deduped on hearing doc). */
export function hearingSmsDigest(
  hearingDocId: string,
  data: HearingDoc & Record<string, unknown>,
): string {
  const row = hearingRow(data);
  const parts: string[] = [hearingDocId];
  for (const key of HEARING_DIGEST_FIELD_KEYS) {
    const v = row[key];
    if (key === "hearingDateTime") {
      parts.push(tsField(v));
    } else {
      parts.push(asString(v));
    }
  }
  return parts.join("|");
}

function caseLabel(data: HearingDoc & Record<string, unknown>): string {
  const row = hearingRow(data);
  const caseNo = asString(row.caseNo);
  const caseTitle = asString(row.caseTitle);
  if (caseNo && caseTitle) return `${caseNo} - ${caseTitle}`;
  return caseNo || caseTitle;
}

export function formatSmsRole(role: string): string {
  const r = role.toLowerCase().trim();
  if (r === "attorney") return "Attorney";
  if (r === "staff" || r.includes("paralegal")) return "Staff";
  if (r === "client") return "Client";
  if (r === "admin") return "Admin";
  return "Firm";
}

export function isBareLocation(raw?: string | null): boolean {
  if (!raw) return true;
  const t = raw.trim();
  if (!t) return true;
  if (/^(?:branch\s*\d*|\d+)[\s,.]*$/i.test(t)) return true;
  const hasSeparator =
    t.includes("-") || t.includes("–") || t.includes("—") || t.includes(",");
  const hasDetails =
    /\b(city|province|hall of justice|rtc|mtc|mtcc|municipal|regional|court|judicial)\b/i.test(
      t,
    );
  return !hasSeparator && !hasDetails;
}

export function extractLocationFromOrderText(text: string, fallback = ""): string {
  // 1. Check for full branch with city/suffix: e.g. "BRANCH 12 - OROQUIETA CITY" or "BRANCH 12, OROQUIETA CITY"
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

  // 2. Check for city before branch, e.g. "QUEZON CITY, BRANCH 45"
  const cityBeforeBranch = text.match(
    /([A-Za-z\s.]+City|[A-Za-z\s.]+Province)\s*[,–—-]\s*branch\s*(\d+)/i,
  );
  if (cityBeforeBranch) {
    const cityPre = cityBeforeBranch[1].trim();
    const branchNum = cityBeforeBranch[2].trim();
    return `Branch ${branchNum} - ${cityPre}`;
  }

  const branch = text.match(/branch\s*(\d+)(?:\s*[-–—]\s*([A-Za-z .]+))?/i);
  const rtc = text.match(
    /((?:regional|municipal|metropolitan)\s+trial\s+court[^\n,]{0,80})/i,
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
  if (!city) {
    const cityMatch = text.match(
      /\b([A-Za-z\s.]+City|Hall of Justice[^\r\n,]*)/i,
    );
    if (cityMatch) {
      city = cityMatch[1].replace(/[.,\s]+$/, "").trim();
    }
  }

  const parts: string[] = [];
  if (branch) parts.push(`Branch ${branch[1]}`);
  if (rtc) {
    let court = rtc[1].replace(/\s+/g, " ").trim();
    if (region && !court.toLowerCase().includes("judicial")) {
      court = `${court}, ${region[1]}`;
    }
    if (city && !court.toLowerCase().includes(city.toLowerCase())) {
      court = `${court}, ${city}`;
    }
    parts.push(court);
  } else if (city) {
    parts.push(city);
  }

  if (parts.length >= 2) {
    return parts.join(" — ");
  }
  if (parts.length === 1 && !isBareLocation(parts[0])) {
    return parts[0];
  }
  if (branch && city) {
    return `Branch ${branch[1]} - ${city}`;
  }
  if (fallback && !isBareLocation(fallback)) return fallback;
  if (parts.length) return parts[0];
  return fallback;
}

export function resolveVenueForDisplay(data: Record<string, unknown>): string {
  let loc = asString(data.location).trim();
  let court = asString(data.courtBranch).trim();
  if (!loc) loc = asString(data.venue).trim();
  if (!court) {
    court = asString(data.court).trim() || asString(data.court_branch).trim();
  }

  if (isBareLocation(loc) && !isBareLocation(court)) loc = court;
  if (isBareLocation(court) && !isBareLocation(loc)) court = loc;

  if (isBareLocation(loc) || isBareLocation(court)) {
    const blob = [
      asString(data.fullText),
      asString(data.orderText),
      asString(data.message),
      asString(data.summary),
    ]
      .filter(Boolean)
      .join("\n")
      .trim();
    if (blob) {
      const extracted = extractLocationFromOrderText(blob, loc || court);
      if (extracted && !isBareLocation(extracted)) {
        if (isBareLocation(loc)) loc = extracted;
        if (isBareLocation(court)) court = extracted;
      }
    }
  }

  if (!loc) return court;
  if (!court) return loc;
  const ll = loc.toLowerCase();
  const cl = court.toLowerCase();
  if (ll.includes(cl) || cl.includes(ll)) {
    return loc.length >= court.length ? loc : court;
  }
  return `${court} — ${loc}`;
}

export function hearingLocation(data: HearingDoc & Record<string, unknown>): string {
  const row = hearingRow(data);
  const venue = resolveVenueForDisplay(row as Record<string, unknown>);
  if (venue && !isBareLocation(venue)) return venue;
  const direct = asString(row.location) || asString(row.courtBranch) || "";
  return venue || direct;
}

function stripEmailsFromParty(raw: string): string {
  return raw
    .replace(/[\w.+-]+@,?\s*[\w.-]+\.\w{2,}/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function extractHearingDateFromOrderText(text: string): string {
  const reset = text.match(
    /(?:reset|set|schedul\w*|next hearing)\b[^\n.]{0,80}?\bon\s+(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)\.?\s+(\d{1,2})\s*,?\s+(\d{4})/i,
  );
  if (reset) {
    return `${reset[1]} ${reset[2]}, ${reset[3]}`;
  }
  const m = text.match(
    /(?:on\s+)?(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})\s*,?\s+(\d{4})/i,
  );
  if (!m) return "";
  return `${m[1]} ${m[2]}, ${m[3]}`;
}

export function extractHearingTimeFromOrderText(text: string): string {
  const clock = text.match(
    /(\d{1,2}:\d{2})\s*(?:o['']?clock\s+)?(?:in the morning|in the afternoon|a\.?m\.?|p\.?m\.?)/i,
  );
  if (clock) return clock[0].replace(/\s+/g, " ").trim();
  const at = text.match(/at\s+(\d{1,2}:\d{2}\s*(?:a\.?m\.?|p\.?m\.?)?)/i);
  return (at?.[1] ?? "").trim();
}

export function hearingFieldsForSms(data: HearingDoc & Record<string, unknown>): {
  caseNo: string;
  caseTitle: string;
  clientName: string;
  hearingDate: string;
  hearingTime: string;
  location: string;
} {
  const row = hearingRow(data);
  const blob = [
    asString(row.fullText),
    asString(row.message),
    asString(row.summary),
  ]
    .filter(Boolean)
    .join("\n");
  let hearingDate = asString(row.hearingDate);
  let hearingTime = asString(row.hearingTime);
  if (!hearingDate && blob) {
    hearingDate = extractHearingDateFromOrderText(blob);
  }
  if (!hearingTime && blob) {
    hearingTime = extractHearingTimeFromOrderText(blob);
  }
  return {
    caseNo: asString(row.caseNo),
    caseTitle: stripEmailsFromParty(asString(row.caseTitle)),
    clientName: stripEmailsFromParty(asString(row.clientName)),
    hearingDate,
    hearingTime,
    location: hearingLocation(data),
  };
}

export function formatHearingSmsTime(raw: string): string {
  const t = raw.trim();
  if (!t) return "";
  const clock = t.match(/(\d{1,2}):(\d{2})(?::\d{2})?/);
  if (!clock) return t;
  let hour = parseInt(clock[1], 10);
  const minute = clock[2];
  if (Number.isNaN(hour)) return t;
  const lower = t.toLowerCase();
  const explicitPm =
    /p\.?m\.?/.test(lower) ||
    /\bpm\b/.test(lower) ||
    lower.includes("afternoon") ||
    lower.includes("evening");
  const explicitAm =
    /a\.?m\.?/.test(lower) ||
    /\bam\b/.test(lower) ||
    lower.includes("morning");
  if (hour > 12) return `${hour - 12}:${minute} PM`;
  if (hour === 0) return `12:${minute} AM`;
  if (explicitPm) return `${hour}:${minute} PM`;
  if (explicitAm) return `${hour}:${minute} AM`;
  if (hour === 12) return `12:${minute} PM`;
  if (hour >= 1 && hour <= 11) return `${hour}:${minute} AM`;
  return `${hour}:${minute}`;
}

export function formatHearingSmsLocation(raw: string): string {
  const t = raw.trim();
  if (!t) return "";
  return t.replace(/\bbranch\b/gi, "Branch");
}

export function formatHearingSmsCaseNumber(raw: string): string {
  let t = raw.trim();
  if (!t) return "";
  t = t.replace(/^(?:civil\s+)?(?:case\s*(?:no\.?|#|number)?\s*)/i, "").trim();
  t = t.replace(/^#\s*/, "");
  if (!t) return "";
  return `Case #${t}`;
}

export function hearingSmsCaptionLines(caseTitle: string, clientName = ""): string[] {
  const title = caseTitle.trim();
  const client = clientName.trim();
  if (!title) return client ? [client] : [];
  const vs = /\s+(?:vs\.?|versus)\s+/i;
  const match = vs.exec(title);
  if (!match || match.index === undefined) {
    const lines = [title];
    if (client && !title.toLowerCase().includes(client.toLowerCase())) {
      lines.push(client);
    }
    return lines;
  }
  const left = title.slice(0, match.index).trim();
  const right = title.slice(match.index + match[0].length).trim();
  const lines: string[] = [];
  if (left) lines.push(left);
  lines.push("vs.");
  if (right) lines.push(right);
  return lines;
}

function etAlCaseTitle(caseTitle: string): string {
  const vs = /\s+(?:vs\.?|versus)\s+/i;
  const match = vs.exec(caseTitle);
  if (!match || match.index === undefined) return caseTitle;
  const right = caseTitle.slice(match.index + match[0].length).trim();
  if (right.toLowerCase().includes("et al")) return caseTitle;
  const firstParty = right.split(/\s*,\s*/)[0]?.trim() ?? "";
  if (!firstParty) return caseTitle;
  return `${caseTitle.slice(0, match.index + match[0].length)}${firstParty}, et al.`;
}

function reminderCopy(kind: string): { leadIn: string; closing: string } | null {
  const k = kind.trim().toLowerCase();
  if (k === "d5") {
    return {
      leadIn: "Your hearing is in 5 days.",
      closing: "Please prepare for your scheduled hearing.",
    };
  }
  if (k === "d2") {
    return {
      leadIn: "Your hearing is in 2 days.",
      closing: "Please be reminded of your upcoming hearing.",
    };
  }
  if (k === "hearing_day" || k === "day_noon") {
    return {
      leadIn: "Your hearing is today.",
      closing: "Please be reminded of your hearing today.",
    };
  }
  return null;
}

/** Clean legal hearing reminder. Does not invent case facts. */
export function buildHearingSmsText(params: {
  roleLabel?: string;
  caseNo?: string;
  caseTitle?: string;
  clientName?: string;
  hearingDate?: string;
  hearingTime?: string;
  location?: string;
  /** @deprecated Prefer [reminderKind]. */
  reminderNote?: string;
  reminderKind?: string | null;
}): string {
  const kind = (params.reminderKind ?? "").trim().toLowerCase();
  const copy = reminderCopy(kind);
  const lines: string[] = [SMS_BRAND, ""];
  if (copy) {
    lines.push(copy.leadIn, "");
  }

  const caseLine = formatHearingSmsCaseNumber(params.caseNo ?? "");
  if (caseLine) lines.push(caseLine);

  // Date/time/location first so push trays and short SMS previews keep them.
  const date = (params.hearingDate ?? "").trim();
  if (date) lines.push(`Date: ${date}`);
  const time = formatHearingSmsTime(params.hearingTime ?? "");
  if (time) lines.push(`Time: ${time}`);
  const loc = formatHearingSmsLocation(params.location ?? "");
  if (loc) lines.push(`Location: ${loc}`);

  const caption = hearingSmsCaptionLines(
    params.caseTitle ?? "",
    params.clientName ?? "",
  );
  if (caption.length) {
    lines.push("");
    lines.push(...caption);
  }

  lines.push("");
  lines.push(copy?.closing ?? "Please be reminded of your scheduled hearing.");

  let text = lines.join("\n").trim();
  if (text.length > MAX_SMS_LENGTH) {
    const shortened = etAlCaseTitle(params.caseTitle ?? "");
    if (shortened !== (params.caseTitle ?? "")) {
      return buildHearingSmsText({ ...params, caseTitle: shortened });
    }
  }
  if (text.length > MAX_SMS_LENGTH) {
    text = `${text.slice(0, MAX_SMS_LENGTH - 3)}...`;
  }
  return text;
}

async function resolveRoleLabelForUser(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<string> {
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) return "Firm";
    return formatSmsRole(asString(snap.data()?.role));
  } catch {
    return "Firm";
  }
}

async function resolvePhoneForUser(
  db: admin.firestore.Firestore,
  uid: string,
  _cfg: PhilSmsHearingCfg,
): Promise<string | null> {
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) return null;
    const data = snap.data() ?? {};
    const profilePhone = asString(
      data.phoneNumber ||
      data.phone ||
      data.contactNumber ||
      data.mobileNumber ||
      data.contact,
    );
    return profilePhone || null;
  } catch (e) {
    logger.warn("hearingSms: phone lookup failed", {
      uid,
      err: e instanceof Error ? e.message : String(e),
    });
    return null;
  }
}

/**
 * Server-side hearing SMS: PhilSMS (unchanged) plus Semaphore when configured.
 */
export async function sendHearingSmsAlerts(params: {
  db: admin.firestore.Firestore;
  hearingDocId: string;
  hearingData: HearingDoc & Record<string, unknown>;
  recipientUserIds: string[];
  title: string;
  body: string;
  cfg: PhilSmsHearingCfg;
  semaphore?: SemaphoreHearingCfg;
}): Promise<void> {
  const { db, hearingDocId, hearingData, recipientUserIds, title, body, cfg } =
    params;
  const semaphore = params.semaphore;

  if (!cfg.apiToken.trim() && !semaphore?.apiKey.trim()) {
    logger.info("hearingSms: skipped (no PhilSMS token and no Semaphore key)");
    return;
  }
  if (!isSmsEligibleHearing(hearingData)) {
    logger.info("hearingSms: skipped (hearing not SMS-eligible)", { hearingDocId });
    return;
  }

  const digest = hearingSmsDigest(hearingDocId, hearingData);
  const hearingRef = db.collection("hearings").doc(hearingDocId);

  const claimed = await db.runTransaction(async (t) => {
    const snap = await t.get(hearingRef);
    const existing = snap.data() ?? {};
    if (
      existing.philsmsIntakeSent === true ||
      existing.philsmsLastSentAt != null
    ) {
      return false;
    }
    const lastDigest = asString(existing.philsmsLastDigest);
    if (lastDigest && lastDigest === digest) {
      return false;
    }
    t.set(
      hearingRef,
      {
        philsmsIntakeSent: true,
        philsmsIntakeClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return true;
  });
  if (!claimed) {
    logger.info("hearingSms: skipped (intake already sent)", { hearingDocId });
    return;
  }

  const fields = hearingFieldsForSms(hearingData);
  const smsBase = { ...fields };

  const philCfg = { apiToken: cfg.apiToken, senderId: cfg.senderId };
  const phonesSent = new Set<string>();
  let anyOk = false;

  const trySend = async (
    phone: string,
    logLabel: string,
    roleLabel: string,
  ): Promise<void> => {
    const normalized = normalizePhilSmsRecipient(phone);
    if (normalized.length < 11) {
      logger.warn("hearingSms: invalid phone", { label: logLabel, phone });
      return;
    }
    if (phonesSent.has(normalized)) return;
    phonesSent.add(normalized);

    const smsText = buildHearingSmsText(smsBase);
    if (cfg.apiToken.trim()) {
      const result = await sendPhilSms(philCfg, phone, smsText);
      if (result.ok) {
        anyOk = true;
        logger.info("hearingSms: PhilSMS ok", {
          label: logLabel,
          role: roleLabel,
          toSuffix: normalized.slice(-4),
        });
      } else {
        logger.warn("hearingSms: PhilSMS failed", {
          label: logLabel,
          role: roleLabel,
          toSuffix: normalized.slice(-4),
          error: result.error,
        });
      }
    }
    if (semaphore?.apiKey.trim()) {
      try {
        await sendViaSemaphore({
          apiKey: semaphore.apiKey,
          to: phone,
          body: smsText,
          senderName: semaphore.senderName,
        });
        anyOk = true;
        logger.info("hearingSms: Semaphore ok", {
          label: logLabel,
          role: roleLabel,
          toSuffix: normalized.slice(-4),
        });
      } catch (e) {
        logger.warn("hearingSms: Semaphore failed", {
          label: logLabel,
          role: roleLabel,
          toSuffix: normalized.slice(-4),
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }
  };

  // Sequential + short gap so back-to-back hearings do not trip provider
  // rate limits (PhilSMS "exceeded sending limit") while Semaphore still runs.
  const queue: Array<() => Promise<void>> = [];
  for (const target of firmSmsTargets(cfg)) {
    queue.push(() => trySend(target.phone, "firm_default", target.roleLabel));
  }

  const rowData = hearingRow(hearingData);
  const hearingClientName = asString(rowData.clientName);
  const caseTitle = asString(rowData.caseTitle);
  const fullText = asString(rowData.fullText);

  const exactClientUids = await resolveClientUidsByExactHearingName(
    db,
    hearingClientName,
    { caseTitle, fullText },
  );

  const allInvolvedClientUids = new Set<string>(exactClientUids);
  for (const key of ["involvedClientIds", "matchedClientIds"]) {
    const arr = rowData[key];
    if (Array.isArray(arr)) {
      for (const uid of arr) {
        if (typeof uid === "string" && uid) allInvolvedClientUids.add(uid);
      }
    }
  }
  const ownerId = asString(rowData.ownerClientId);
  if (ownerId) allInvolvedClientUids.add(ownerId);

  // Check any recipients who are role == 'client'
  for (const uid of recipientUserIds) {
    if (!allInvolvedClientUids.has(uid)) {
      try {
        const snap = await db.collection("users").doc(uid).get();
        if (snap.exists && asString(snap.data()?.role).toLowerCase() === "client") {
          allInvolvedClientUids.add(uid);
        }
      } catch {
        /* skip */
      }
    }
  }

  const clientPhones = await Promise.all(
    [...allInvolvedClientUids].map(async (uid) => ({
      uid,
      phone: await resolvePhoneForUser(db, uid, cfg),
    })),
  );
  for (const row of clientPhones) {
    if (row.phone) {
      const phone = row.phone;
      const uid = row.uid;
      queue.push(() => trySend(phone, `client_${uid}`, "Client"));
    } else {
      logger.warn("hearingSms: matched client has no phone", {
        hearingDocId,
        uid: row.uid,
        clientName: hearingClientName,
      });
    }
  }
  if (hearingClientName && !allInvolvedClientUids.size) {
    logger.info("hearingSms: no client with exact sign-up name match", {
      hearingDocId,
      clientName: hearingClientName,
    });
  }

  const clientSet = new Set(allInvolvedClientUids);
  const firmRows = await Promise.all(
    recipientUserIds
      .filter((uid) => !clientSet.has(uid))
      .map(async (uid) => {
        const roleLabel = await resolveRoleLabelForUser(db, uid);
        const phone = await resolvePhoneForUser(db, uid, cfg);
        return { uid, roleLabel, phone };
      }),
  );
  for (const row of firmRows) {
    const isFirm =
      row.roleLabel === "Attorney" ||
      row.roleLabel === "Staff" ||
      row.roleLabel === "Admin";
    // firmPhonesOnly skips extra clients. Attorney and staff still get the
    // same SMS as the push, using the phone on their user profile.
    if (cfg.firmPhonesOnly && !isFirm) continue;
    if (!row.phone) {
      logger.warn("hearingSms: push recipient has no phone", {
        hearingDocId,
        uid: row.uid,
        role: row.roleLabel,
      });
      continue;
    }
    const phone = row.phone;
    const uid = row.uid;
    const roleLabel = row.roleLabel;
    queue.push(() => trySend(phone, `uid_${uid}`, roleLabel));
  }
  for (let i = 0; i < queue.length; i++) {
    await queue[i]();
    if (i < queue.length - 1) {
      await new Promise((r) => setTimeout(r, 350));
    }
  }

  if (anyOk) {
    await hearingRef.set(
      {
        philsmsIntakeSent: true,
        philsmsLastDigest: digest,
        philsmsLastSentAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    logger.info("hearingSms: delivered", {
      hearingDocId,
      phoneCount: phonesSent.size,
    });
  } else {
    await hearingRef.set(
      {
        philsmsIntakeSent: admin.firestore.FieldValue.delete(),
        philsmsIntakeClaimedAt: admin.firestore.FieldValue.delete(),
      },
      { merge: true },
    );
    if (phonesSent.size > 0) {
      logger.warn("hearingSms: no SMS delivered (check PhilSMS credits / cloud API access)", {
        hearingDocId,
      });
    } else {
      logger.warn("hearingSms: no valid phones", { hearingDocId });
    }
  }
}

function reminderSentFlag(kind: string): "fiveDayReminderSent" | "twoDayReminderSent" | "hearingDayReminderSent" | null {
  const k = kind.trim().toLowerCase();
  if (k === "d5") return "fiveDayReminderSent";
  if (k === "d2") return "twoDayReminderSent";
  if (k === "hearing_day" || k === "day_noon") return "hearingDayReminderSent";
  return null;
}

export function isActiveHearingSmsReminderKind(kind: string): boolean {
  const k = kind.trim().toLowerCase();
  return k === "d5" || k === "d2" || k === "hearing_day";
}

export type ReminderPhoneState = { phil?: boolean; sem?: boolean };

/** True when every configured provider already delivered to this number. */
export function reminderProviderComplete(
  state: ReminderPhoneState | undefined,
  wantPhil: boolean,
  wantSem: boolean,
): boolean {
  if (!wantPhil && !wantSem) return true;
  if (!state) return false;
  if (wantPhil && state.phil !== true) return false;
  if (wantSem && state.sem !== true) return false;
  return true;
}

/**
 * Hearings marked sent before per-phone tracking have no ledger.
 * Those stay locked so a scheduler rerun does not text everyone again.
 * A ledger entry lets a new profile number still receive that reminder.
 */
export function reminderLegacyLocked(
  ledger: Record<string, ReminderPhoneState>,
  sentFlag: boolean,
): boolean {
  return sentFlag && Object.keys(ledger).length === 0;
}

function reminderPhoneLedger(
  data: Record<string, unknown>,
  kind: string,
): Record<string, ReminderPhoneState> {
  const root = data.philsmsReminderPhones;
  if (!root || typeof root !== "object") return {};
  const row = (root as Record<string, unknown>)[kind];
  if (!row || typeof row !== "object") return {};
  const out: Record<string, ReminderPhoneState> = {};
  for (const [phone, state] of Object.entries(row as Record<string, unknown>)) {
    if (!state || typeof state !== "object") continue;
    const s = state as Record<string, unknown>;
    const next: ReminderPhoneState = {};
    if (s.phil === true) next.phil = true;
    if (s.sem === true) next.sem = true;
    if (next.phil || next.sem) out[phone] = next;
  }
  return out;
}

/** Pre-hearing reminder SMS (5 days / 2 days / hearing day) — PhilSMS + Semaphore. */
export async function sendHearingReminderPhilSms(params: {
  db: admin.firestore.Firestore;
  hearingDocId: string;
  hearingData: HearingDoc & Record<string, unknown>;
  reminderKind: string;
  reminderTitle: string;
  cfg: PhilSmsHearingCfg;
  semaphore?: SemaphoreHearingCfg;
}): Promise<void> {
  const { db, hearingDocId, hearingData, reminderKind, cfg } = params;
  const semaphore = params.semaphore;
  if (!cfg.apiToken.trim() && !semaphore?.apiKey.trim()) return;
  if (!isActiveHearingSmsReminderKind(reminderKind)) {
    logger.info("hearingSms: skipped obsolete reminder kind", {
      hearingDocId,
      reminderKind,
    });
    return;
  }

  const hearingRef = db.collection("hearings").doc(hearingDocId);
  const existing = await hearingRef.get();
  const existingData = existing.data() ?? {};
  const sentMap =
    (existingData.philsmsRemindersSent as Record<string, boolean> | undefined) ??
    {};
  const flag = reminderSentFlag(reminderKind);
  const wantPhil = Boolean(cfg.apiToken.trim());
  const wantSem = Boolean(semaphore?.apiKey.trim());
  const ledger = reminderPhoneLedger(existingData, reminderKind);
  const alreadySent =
    sentMap[reminderKind] === true ||
    (flag != null && existingData[flag] === true);
  if (reminderLegacyLocked(ledger, alreadySent)) {
    logger.info("hearingSms: reminder already sent", { hearingDocId, reminderKind });
    return;
  }

  const smsBase = {
    ...hearingFieldsForSms(hearingData),
    reminderKind,
  };

  const philCfg = { apiToken: cfg.apiToken, senderId: cfg.senderId };
  let anyOk = false;
  let ledgerDirty = false;

  const tryReminderSend = async (
    phone: string,
    logLabel: string,
    roleLabel: string,
  ): Promise<void> => {
    const normalized = normalizePhilSmsRecipient(phone);
    if (normalized.length < 11) return;
    const prior = ledger[normalized] ?? {};
    if (reminderProviderComplete(prior, wantPhil, wantSem)) return;
    const smsText = buildHearingSmsText(smsBase);
    const next: ReminderPhoneState = { ...prior };
    if (wantPhil && next.phil !== true) {
      const result = await sendPhilSms(philCfg, phone, smsText);
      if (result.ok) {
        next.phil = true;
        anyOk = true;
        ledgerDirty = true;
        logger.info("hearingSms: reminder sent", {
          hearingDocId,
          reminderKind,
          label: logLabel,
          role: roleLabel,
          toSuffix: normalized.slice(-4),
        });
      } else {
        logger.warn("hearingSms: reminder failed", {
          hearingDocId,
          reminderKind,
          label: logLabel,
          role: roleLabel,
          error: result.error,
        });
      }
    }
    if (wantSem && next.sem !== true) {
      try {
        await sendViaSemaphore({
          apiKey: semaphore!.apiKey,
          to: phone,
          body: smsText,
          senderName: semaphore!.senderName,
        });
        next.sem = true;
        anyOk = true;
        ledgerDirty = true;
        logger.info("hearingSms: Semaphore reminder sent", {
          hearingDocId,
          reminderKind,
          label: logLabel,
          role: roleLabel,
          toSuffix: normalized.slice(-4),
        });
      } catch (e) {
        logger.warn("hearingSms: Semaphore reminder failed", {
          hearingDocId,
          reminderKind,
          label: logLabel,
          role: roleLabel,
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }
    if (next.phil || next.sem) {
      ledger[normalized] = next;
    }
  };

  for (const target of firmSmsTargets(cfg)) {
    await tryReminderSend(target.phone, "firm_default", target.roleLabel);
  }

  for (const role of ["attorney", "staff"] as const) {
    try {
      const q = await db
        .collection("users")
        .where("role", "==", role)
        .limit(80)
        .get();
      for (const doc of q.docs) {
        if (doc.data()?.isActive === false) continue;
        const phone = await resolvePhoneForUser(db, doc.id, cfg);
        if (!phone) continue;
        await tryReminderSend(
          phone,
          `firm_${doc.id}`,
          role === "attorney" ? "Attorney" : "Staff",
        );
      }
    } catch (e) {
      logger.warn("hearingSms: reminder firm lookup failed", {
        hearingDocId,
        role,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  const hearingClientName = asString(hearingRow(hearingData).clientName);
  const exactClientUids = await resolveClientUidsByExactHearingName(
    db,
    hearingClientName,
  );
  for (const uid of exactClientUids) {
    const phone = await resolvePhoneForUser(db, uid, cfg);
    if (phone) await tryReminderSend(phone, `client_exact_${uid}`, "Client");
  }

  if (anyOk || ledgerDirty) {
    const previousLedger =
      existingData.philsmsReminderPhones &&
      typeof existingData.philsmsReminderPhones === "object"
        ? { ...(existingData.philsmsReminderPhones as Record<string, unknown>) }
        : {};
    const patch: Record<string, unknown> = {
      philsmsReminderPhones: { ...previousLedger, [reminderKind]: ledger },
    };
    if (anyOk) {
      patch.philsmsRemindersSent = { ...sentMap, [reminderKind]: true };
      if (flag) patch[flag] = true;
    }
    await hearingRef.set(patch, { merge: true });
  }
}
