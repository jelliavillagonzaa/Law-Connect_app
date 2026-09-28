import * as admin from "firebase-admin";
import type { DocumentSnapshot, QueryDocumentSnapshot, QuerySnapshot } from "firebase-admin/firestore";
import type { Change, FirestoreEvent } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import {
  sendHearingSmsAlerts,
  sendHearingReminderPhilSms,
  buildHearingSmsText,
  hearingFieldsForSms,
  type PhilSmsHearingCfg,
  type SemaphoreHearingCfg,
} from "./hearingSmsAlerts";
import {
  isOutOfSystemCourtNoticeTitle,
  isOutOfSystemPumpedNoticeText,
} from "./outOfSystemNotice";

export type HearingReminderKind = "d5" | "d2" | "hearing_day";
export const ACTIVE_HEARING_REMINDER_KINDS: readonly HearingReminderKind[] = [
  "d5",
  "d2",
  "hearing_day",
];
/** Old queued kinds — cancel; do not send. */
export const OBSOLETE_HEARING_REMINDER_KINDS: readonly string[] = [
  "d1",
  "d3",
  "d7",
  "day_noon",
  "h10",
  "m5",
  "same_day",
];
/** Jobs older than this are skipped instead of sending a late SMS. */
export const HEARING_REMINDER_LATE_GRACE_MS = 15 * 60 * 1000;

/** App “activity” rows + imported court rows (caseNo / fullText). */
export type HearingDoc = {
  caseId?: string | null;
  caseNo?: string | null;
  clientName?: string | null;
  courtBranch?: string | null;
  fullText?: string | null;
  senderId?: string | null;
  senderName?: string | null;
  activityType?: string | null;
  message?: string | null;
  hearingDateTime?: admin.firestore.Timestamp | null;
  caseTitle?: string | null;
  title?: string | null;
  uploadedBy?: string | null;
  createdBy?: string | null;
  handledBy?: string | null;
  staffUid?: string | null;
  attorneyUid?: string | null;
  notifyUserIds?: unknown;
  /** IANA zone for parsing dates in fullText (default Asia/Manila) */
  timeZone?: string | null;
  /** Set by Flutter in-app fan-out so deployed Functions skip duplicate sends */
  clientFanoutComplete?: admin.firestore.Timestamp | null;
  location?: string | null;
  hearingDate?: string | null;
  hearingTime?: string | null;
  status?: string | null;
  cancelled?: boolean | null;
  isCancelled?: boolean | null;
};

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

function asString(v: unknown): string {
  return v === undefined || v === null ? "" : String(v).trim();
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

/**
 * Parses e.g. "June 25, 2026 at 9:00" / "**June 25, 2026 at 9:00**" from court orders.
 * Uses +08:00 (Philippines) when no AM/PM; adjusts when AM/PM present.
 */
function parseHearingDateTimeFromFullText(
  fullText: string,
  timeZoneOffset: string,
): Date | null {
  const t = fullText.replace(/\*+/g, " ").replace(/\s+/g, " ");
  const re =
    /\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s*(\d{4})\s+at\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(A\.?M\.?|P\.?M\.?)?/i;
  const m = t.match(re);
  if (!m) return null;
  const monKey = m[1].toLowerCase();
  const mon = MONTHS[monKey];
  if (mon === undefined) return null;
  const day = parseInt(m[2], 10);
  const year = parseInt(m[3], 10);
  let hour = parseInt(m[4], 10);
  const minute = parseInt(m[5], 10);
  const ampmRaw = m[7] ? m[7].replace(/\./g, "").toUpperCase() : "";
  const ampm = ampmRaw.startsWith("P") ? "PM" : ampmRaw.startsWith("A") ? "AM" : "";

  if (ampm === "PM" && hour < 12) hour += 12;
  if (ampm === "AM" && hour === 12) hour = 0;

  const mm = pad2(mon + 1);
  const dd = pad2(day);
  const hh = pad2(hour);
  const minStr = pad2(minute);
  const iso = `${year}-${mm}-${dd}T${hh}:${minStr}:00${timeZoneOffset}`;
  const d = new Date(iso);
  return isNaN(d.getTime()) ? null : d;
}

function hearingTimeZoneOffset(d: HearingDoc): string {
  const z = asString(d.timeZone).toUpperCase();
  if (z === "UTC" || z === "ETC/UTC") return "Z";
  return "+08:00";
}

function extractTimeForParse(timeStr: string): string {
  const m = timeStr.match(/(\d{1,2}):(\d{2})/);
  if (!m) return "9:00 AM";
  const hour = parseInt(m[1], 10);
  const min = m[2];
  const lower = timeStr.toLowerCase();
  let ampm = "AM";
  if (lower.includes("pm") || lower.includes("afternoon") || lower.includes("evening")) {
    ampm = "PM";
  } else if (lower.includes("am") || lower.includes("morning")) {
    ampm = "AM";
  } else if (hour >= 1 && hour <= 11) {
    ampm = "AM";
  }
  return `${hour}:${min} ${ampm}`;
}

function hearingAtFromDoc(d: HearingDoc): Date | null {
  const t = d.hearingDateTime;
  if (t && typeof (t as admin.firestore.Timestamp).toDate === "function") {
    const dt = (t as admin.firestore.Timestamp).toDate();
    if (!isNaN(dt.getTime())) return dt;
  }
  const row = d as Record<string, unknown>;
  const hearingDate = asString(row.hearingDate);
  const hearingTime = asString(row.hearingTime);
  if (hearingDate) {
    const combined = hearingTime
      ? `${hearingDate} at ${extractTimeForParse(hearingTime)}`
      : hearingDate;
    const parsed = parseHearingDateTimeFromFullText(
      combined,
      hearingTimeZoneOffset(d),
    );
    if (parsed) return parsed;
  }
  const ft = asString(d.fullText);
  if (ft) {
    const parsed = parseHearingDateTimeFromFullText(ft, hearingTimeZoneOffset(d));
    if (parsed) return parsed;
  }
  return null;
}

function caseDigitKey(caseNo: string): string {
  const matches = caseNo.match(/\d{2,}/g);
  if (!matches?.length) return "";
  return matches[matches.length - 1];
}

function docCreatedMs(data: Record<string, unknown>): number {
  const c = data.createdAt;
  if (c && typeof (c as admin.firestore.Timestamp).toMillis === "function") {
    return (c as admin.firestore.Timestamp).toMillis();
  }
  if (typeof c === "string") {
    const ms = Date.parse(c);
    return Number.isNaN(ms) ? 0 : ms;
  }
  return 0;
}

/** True when an earlier hearing already covers this case and hearing time. */
async function laterDuplicateOfExistingHearing(
  db: admin.firestore.Firestore,
  hearingDocId: string,
  d: HearingDoc,
): Promise<boolean> {
  const caseNo = asString(d.caseNo).trim();
  const key = caseDigitKey(caseNo);
  const at = hearingAtFromDoc(d);
  if (!key || !at || isPlaceholderCaseNo(caseNo)) return false;

  let snap: QuerySnapshot;
  try {
    snap = await db.collection("hearings").where("caseNo", "==", caseNo).limit(8).get();
  } catch (e) {
    logger.warn("hearingNotify duplicate lookup failed", {
      hearingDocId,
      err: e instanceof Error ? e.message : String(e),
    });
    return false;
  }

  const mine = docCreatedMs(d as Record<string, unknown>);
  for (const doc of snap.docs) {
    if (doc.id === hearingDocId) continue;
    const other = doc.data() as HearingDoc & Record<string, unknown>;
    if (caseDigitKey(asString(other.caseNo)) !== key) continue;
    const otherAt = hearingAtFromDoc(other);
    if (!otherAt || Math.abs(otherAt.getTime() - at.getTime()) > 60 * 1000) continue;
    const otherCreated = docCreatedMs(other);
    if (otherCreated > 0 && (mine === 0 || otherCreated < mine)) return true;
    if (otherCreated === mine && doc.id < hearingDocId) return true;
  }
  return false;
}

/** One in-app notice + one SMS set per case number and hearing time. */
async function claimPrimaryHearingNotice(
  db: admin.firestore.Firestore,
  hearingDocId: string,
  d: HearingDoc,
): Promise<boolean> {
  const caseNo = asString(d.caseNo).trim();
  const key = caseDigitKey(caseNo);
  const at = hearingAtFromDoc(d);
  if (!key || !at || isPlaceholderCaseNo(caseNo)) return true;
  const ref = db.collection("hearing_notice_locks").doc(`${key}_${at.getTime()}`);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, {
          hearingDocId,
          caseNo,
          hearingAtMs: at.getTime(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      }
      return asString(snap.data()?.hearingDocId) === hearingDocId;
    });
  } catch (e) {
    logger.warn("hearingNotify lock failed", {
      hearingDocId,
      err: e instanceof Error ? e.message : String(e),
    });
    return true;
  }
}

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
    s === "unknown" ||
    s === "test"
  );
}

function isProductOrDevEmailBlob(blob: string): boolean {
  const t = blob.toLowerCase();
  return [
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
  ].some((m) => t.includes(m));
}

export function isImportedCourtRow(d: HearingDoc): boolean {
  const cn = asString(d.caseNo);
  if (isPlaceholderCaseNo(cn)) return false;
  return cn.length > 0 && asString(d.fullText).length > 0;
}

function isGibberishToken(raw: string): boolean {
  if (/\d/.test(raw)) return false;
  const s = raw.toLowerCase().replace(/[^a-z]/g, "");
  if (s.length < 8) return false;
  if (/(hearing|court|trial|arraignment|mediation|conference)/.test(s)) {
    return false;
  }
  if (/(.)\1{2,}/.test(s)) return true;
  if (/(.{2,5})\1/.test(s)) return true;
  if (!/[aeiou]/.test(s)) return true;
  if (/[^aeiou]{4,}/.test(s)) return true;
  return false;
}

function hearingSource(d: HearingDoc): string {
  return asString((d as Record<string, unknown>).source).toLowerCase();
}

function isN8nOrCourtImport(d: HearingDoc): boolean {
  const source = hearingSource(d);
  const activity = asString(d.activityType).toLowerCase();
  return (
    source === "n8n" ||
    source.includes("n8n") ||
    activity === "court_import" ||
    isImportedCourtRow(d)
  );
}

function timestampFromUnknown(v: unknown): admin.firestore.Timestamp | null {
  if (v instanceof admin.firestore.Timestamp) return v;
  if (typeof v === "string" && v.trim()) {
    const d = new Date(v);
    if (!Number.isNaN(d.getTime())) return admin.firestore.Timestamp.fromDate(d);
  }
  return null;
}

/** Test mash / promo rows must never fan out in-app, FCM, or SMS. */
export function isJunkHearingDoc(d: HearingDoc): boolean {
  const blob = [
    asString(d.title),
    asString(d.caseTitle),
    asString(d.message),
    asString(d.fullText),
    asString(d.activityType),
    asString(d.clientName),
  ]
    .join(" ")
    .toLowerCase();
  const compact = blob.replace(/[^a-z0-9]+/g, " ");
  if (
    isOutOfSystemPumpedNoticeText(blob) ||
    isOutOfSystemCourtNoticeTitle(asString(d.caseTitle) || asString(d.title)) ||
    blob.includes("blasttv") ||
    blob.includes("voucher code") ||
    blob.includes("hearing (eating)") ||
    compact.includes("ai hearing eating") ||
    compact.includes("hearing eating") ||
    isProductOrDevEmailBlob(blob)
  ) {
    return true;
  }
  if (isPlaceholderCaseNo(asString(d.caseNo)) && !isImportedCourtRow(d)) {
    return true;
  }
  // Real n8n court imports still deliver.
  if (isN8nOrCourtImport(d)) return false;
  const title = asString(d.caseTitle) || asString(d.message);
  const message = asString(d.message);
  if (isGibberishPhrase(title) || isGibberishPhrase(message)) return true;
  return false;
}

function isGibberishPhrase(raw: string): boolean {
  const title = raw.trim();
  if (!title) return false;
  const words = title.split(/[^a-zA-Z0-9]+/).filter(Boolean);
  const stop = /^(hearing|scheduled|updated|message|notice|court|order|event|reminder)$/i;
  if (words.length === 1 && isGibberishToken(words[0])) return true;
  const significant = words.filter((w) => w.length >= 8 && !stop.test(w));
  return significant.length > 0 && significant.every(isGibberishToken);
}

function isCourtHearingForStaffAlert(d: HearingDoc): boolean {
  if (isImportedCourtRow(d)) return true;
  const cn = asString(d.caseNo);
  if (!cn) return false;
  if (asString(d.courtBranch)) return true;
  const act = asString(d.activityType).toLowerCase();
  if (act.includes("court") || act.includes("import")) return true;
  if (asString(d.message) || asString(d.fullText)) return true;
  return false;
}

function extractExtraUids(d: HearingDoc): string[] {
  const raw = d as Record<string, unknown>;
  const out = new Set<string>();
  const singles = ["senderId", "uploadedBy", "createdBy", "handledBy", "staffUid", "attorneyUid"];
  for (const k of singles) {
    const v = raw[k];
    if (typeof v === "string" && v.length > 8) out.add(v.trim());
  }
  const arr = raw.notifyUserIds;
  if (Array.isArray(arr)) {
    for (const x of arr) {
      if (typeof x === "string" && x.length > 8) out.add(x.trim());
    }
  }
  return [...out];
}

function hearingRowStatus(d: HearingDoc): string {
  return asString((d as Record<string, unknown>).status).toLowerCase();
}

/** Existing hearing/case statuses that must not receive future hearing reminders. */
export function isHearingInactiveForReminders(
  d: HearingDoc & Record<string, unknown>,
): boolean {
  if (d.cancelled === true || d.isCancelled === true) return true;
  const status = hearingRowStatus(d);
  if (
    status === "cancelled" ||
    status === "canceled" ||
    status === "completed" ||
    status === "declined" ||
    status === "closed"
  ) {
    return true;
  }
  const activity = asString(d.activityType).toLowerCase();
  if (
    activity === "cancelled" ||
    activity === "canceled" ||
    activity === "completed"
  ) {
    return true;
  }
  return false;
}

function caseStatusBlocksReminders(status: string, isArchived?: unknown): boolean {
  const s = status.toLowerCase().trim();
  if (
    s === "cancelled" ||
    s === "canceled" ||
    s === "completed" ||
    s === "declined"
  ) {
    return true;
  }
  return isArchived === true;
}

export function isActiveHearingReminderKind(
  kind: string,
): kind is HearingReminderKind {
  return (
    kind === "d5" || kind === "d2" || kind === "hearing_day"
  );
}

export function expectedReminderAt(
  hearingAt: Date,
  kind: HearingReminderKind,
): Date {
  const h = hearingAt.getTime();
  if (kind === "d5") return new Date(h - 5 * 24 * 60 * 60 * 1000);
  if (kind === "d2") return new Date(h - 2 * 24 * 60 * 60 * 1000);
  return new Date(h);
}

/**
 * Reminders fire at the actual hearing clock time, in the hearing timezone
 * already represented by [hearingAt].
 *
 * Example: 28 Oct 2026 8:30 AM → 23 Oct 8:30 AM, 26 Oct 8:30 AM, 28 Oct 8:30 AM.
 * Past slots are omitted (no late 5-day send when the hearing is tomorrow).
 */
export function reminderSchedule(
  hearingAt: Date,
  now: Date,
): Array<{ kind: HearingReminderKind; at: Date }> {
  const nowMs = now.getTime();
  const out: Array<{ kind: HearingReminderKind; at: Date }> = [];
  for (const kind of ACTIVE_HEARING_REMINDER_KINDS) {
    const at = expectedReminderAt(hearingAt, kind);
    if (at.getTime() > nowMs) out.push({ kind, at });
  }
  return out;
}

function reminderTitle(kind: HearingReminderKind, caseLabel: string): string {
  switch (kind) {
    case "d5":
      return `Hearing in 5 days — ${caseLabel}`;
    case "d2":
      return `Hearing in 2 days — ${caseLabel}`;
    case "hearing_day":
      return `Hearing today — ${caseLabel}`;
    default:
      return `Hearing reminder — ${caseLabel}`;
  }
}

function caseNumberVariants(raw: string): string[] {
  const t = raw.trim();
  if (!t) return [];
  const out = new Set<string>([t, t.toUpperCase(), t.toLowerCase()]);
  const collapsed = t.replace(/\s+/g, "");
  if (collapsed) out.add(collapsed);
  const prefixes = [
    "Civil Case No.",
    "Civil Case No",
    "CRM. No.",
    "Criminal Case No.",
    "Case No.",
    "Case No",
  ];
  const tl = t.toLowerCase();
  for (const p of prefixes) {
    if (t.length > p.length && tl.startsWith(p.toLowerCase())) {
      out.add(t.substring(p.length).trim());
    }
  }
  return [...out].filter((s) => s.length > 0);
}

function alnumLower(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]/g, "");
}

function normalizeWhitespace(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

function clientNameQueryVariants(raw: string): string[] {
  const t = normalizeWhitespace(raw);
  if (!t) return [];
  const out = new Set<string>([t, t.toUpperCase(), t.toLowerCase()]);
  const titled = t
    .split(" ")
    .map((w) => (w.length ? w[0].toUpperCase() + w.slice(1).toLowerCase() : w))
    .join(" ");
  out.add(titled);
  return [...out].filter((s) => s.length > 0);
}

const PARTY_SKIP = new Set([
  "namely",
  "heirs",
  "of",
  "the",
  "and",
  "sps",
  "spouses",
  "et",
  "al",
  "vs",
  "versus",
  "plaintiff",
  "defendant",
  "petitioner",
  "respondent",
]);

/** Split OCR / court `clientName` blobs into individual party names. */
export function splitHearingPartyNames(raw: string): string[] {
  let s = normalizeWhitespace(raw);
  if (!s) return [];

  const extras: string[] = [];
  s = s.replace(
    /\bSPS\.?\s+([A-Za-z][A-Za-z.\-]*)\s*&\s*([A-Za-z][A-Za-z.\-]*(?:\s+[A-Za-z][A-Za-z.\-]*)*)/gi,
    (_m, first: string, rest: string) => {
      const f = String(first || "").trim();
      const r = String(rest || "").trim();
      const last = r.split(/\s+/).filter(Boolean).pop() || r;
      if (f && last) extras.push(`${f} ${last}`);
      if (r) extras.push(r);
      return `, ${r}, `;
    },
  );
  s = s.replace(/\bSPS\.?\s*/gi, " ").replace(/\bHEIRS OF\s+/gi, " ");

  const out: string[] = [];
  const add = (p0: string) => {
    let p = p0.replace(/\s+/g, " ").trim();
    p = p.replace(/^and\s+/i, "").replace(/[.,;:]+$/g, "").trim();
    if (p.length < 4) return;
    if (PARTY_SKIP.has(p.toLowerCase())) return;
    if (out.some((e) => e.toLowerCase() === p.toLowerCase())) return;
    out.push(p);
  };
  for (const p of s.split(/\s*(?:,|;|\/|\band\b|&)\s*/i)) add(p);
  for (const p of extras) add(p);
  return out;
}

function significantNameWords(raw: string): string[] {
  return normalizeWhitespace(raw)
    .toLowerCase()
    .split(/\s+/)
    .map((w) => w.replace(/[^a-z0-9]/g, ""))
    .filter((w) => w.length >= 3 && !PARTY_SKIP.has(w));
}

function partyMatchesStoredName(stored: string, party: string): boolean {
  if (namesMatchForClient(stored, party)) return true;
  const storedNorm = normalizeWhitespace(stored);
  const partyNorm = normalizeWhitespace(party);
  if (storedNorm.toLowerCase() === partyNorm.toLowerCase()) return true;
  const storedWords = significantNameWords(stored);
  const partyWords = significantNameWords(party);
  const storedLower = storedNorm.toLowerCase();
  const partyLower = partyNorm.toLowerCase();
  if (partyWords.length >= 2 && partyWords.every((w) => storedLower.includes(w))) {
    return true;
  }
  if (storedWords.length >= 2 && storedWords.every((w) => partyLower.includes(w))) {
    return true;
  }
  if (
    partyWords.length >= 2 &&
    storedWords.length >= 2 &&
    partyWords[0] === storedWords[0] &&
    partyWords[partyWords.length - 1] === storedWords[storedWords.length - 1]
  ) {
    return true;
  }
  return false;
}

function namesMatchForClient(stored: string, hearingClientName: string): boolean {
  const a = alnumLower(stored);
  const b = alnumLower(hearingClientName);
  if (a.length < 3 || b.length < 3) return false;
  return a === b;
}

/** Sign-up name must match `hearings.clientName` exactly (ignore case / extra spaces). */
export function clientNameExactMatch(
  stored: string,
  hearingClientName: string,
): boolean {
  const a = normalizeWhitespace(stored).toLowerCase();
  const b = normalizeWhitespace(hearingClientName).toLowerCase();
  if (!a || !b) return false;
  return a === b;
}

function normNamePart(s: string): string {
  return normalizeWhitespace(s).toLowerCase();
}

/**
 * From court `clientName`: first word = first name, last word = last name (middle ignored).
 * "Jerome Castillo" or "Jerome L. Castillo" → { first: Jerome, last: Castillo }
 */
export function parseFirstLastFromHearingName(
  hearingClientName: string,
): { first: string; last: string } | null {
  const parts = normalizeWhitespace(hearingClientName).split(" ").filter(Boolean);
  if (parts.length < 2) return null;
  if (parts.length === 2) {
    return { first: parts[0], last: parts[1] };
  }
  return { first: parts[0], last: parts[parts.length - 1] };
}

/** Profile vs court client field — matches ANY named party, not the whole comma blob. */
export function namesPartialMatchForClient(
  stored: string,
  hearingClientName: string,
): boolean {
  if (partyMatchesStoredName(stored, hearingClientName)) return true;
  for (const party of splitHearingPartyNames(hearingClientName)) {
    if (partyMatchesStoredName(stored, party)) return true;
  }
  return false;
}

export function clientProfileMatchesHearingClientName(
  data: Record<string, unknown> | undefined,
  hearingClientName: string,
): boolean {
  if (!data || !hearingClientName.trim()) return false;
  for (const field of ["fullName", "name", "displayName"] as const) {
    const stored = asString(data[field]);
    if (stored && namesPartialMatchForClient(stored, hearingClientName)) {
      return true;
    }
  }
  const first = asString(data.firstName);
  const last = asString(data.lastName);
  if (first && last && namesPartialMatchForClient(`${first} ${last}`, hearingClientName)) {
    return true;
  }
  return false;
}

/**
 * SMS / exact client match: `fullName`/`name` OR `firstName`+`lastName` (middleName ignored).
 */
export function clientSignUpMatchesHearingName(
  data: Record<string, unknown>,
  hearingClientName: string,
): boolean {
  const cn = hearingClientName.trim();
  if (!cn) return false;

  const parties = splitHearingPartyNames(cn);
  const candidates = parties.length ? parties : [cn];

  for (const party of candidates) {
    for (const field of ["fullName", "name", "displayName"] as const) {
      const stored = asString(data[field]);
      if (stored && clientNameExactMatch(stored, party)) return true;
    }

    const hearingParts = parseFirstLastFromHearingName(party);
    if (!hearingParts) continue;

    const signUpFirst = normNamePart(asString(data.firstName));
    const signUpLast = normNamePart(asString(data.lastName));
    if (!signUpFirst || !signUpLast) continue;

    if (
      signUpFirst === normNamePart(hearingParts.first) &&
      signUpLast === normNamePart(hearingParts.last)
    ) {
      return true;
    }
  }
  return false;
}

export function clientInboxTitleFromHearing(d: HearingDoc, caseTitle: string): string {
  if (isImportedCourtRow(d)) {
    const cn = asString(d.caseNo);
    return cn ? `New notice court hearings — ${cn}` : "New notice court hearings";
  }
  return `New notice court hearings — ${caseTitle}`;
}

/** Resolve client user IDs from `hearings.clientName` (each named party). */
export async function resolveClientUidsByHearingName(
  db: admin.firestore.Firestore,
  clientName: string,
  opts?: { scanAllClients?: boolean },
): Promise<string[]> {
  const cn = clientName.trim();
  if (!cn) return [];

  const matched = new Set<string>();
  const parties = splitHearingPartyNames(cn);
  const queryNames = (parties.length ? parties : [cn]).slice(0, 12);
  const fields = ["fullName", "name", "displayName"] as const;

  for (const party of queryNames) {
    const nameKeys = clientNameQueryVariants(party).slice(0, 4);
    for (const field of fields) {
      for (const nm of nameKeys) {
        try {
          const uq = await db.collection("users").where(field, "==", nm).limit(15).get();
          for (const u of uq.docs) {
            const role = String(u.data()?.role || "").toLowerCase();
            if (role === "client") matched.add(u.id);
          }
        } catch {
          /* index / field */
        }
      }
    }
  }

  if (opts?.scanAllClients === false) {
    return [...matched];
  }

  try {
    const cq = await db.collection("users").where("role", "==", "client").limit(250).get();
    for (const u of cq.docs) {
      if (matched.has(u.id)) continue;
      const data = u.data() as Record<string, unknown>;
      if (clientProfileMatchesHearingClientName(data, cn)) {
        matched.add(u.id);
      }
    }
  } catch (e) {
    logger.warn("hearingNotify: client role scan failed", {
      err: e instanceof Error ? e.message : String(e),
    });
  }

  return [...matched];
}

/**
 * Clients for PhilSMS — sign-up match via fullName OR firstName+lastName (no middleName).
 */
export async function resolveClientUidsByExactHearingName(
  db: admin.firestore.Firestore,
  clientName: string,
): Promise<string[]> {
  const cn = clientName.trim();
  if (!cn) return [];

  const matched = new Set<string>();
  const parties = splitHearingPartyNames(cn);
  const queryNames = (parties.length ? parties : [cn]).slice(0, 12);
  const fields = ["fullName", "name", "displayName"] as const;

  const tryAdd = (data: Record<string, unknown>, uid: string): void => {
    if (asString(data.role).toLowerCase() !== "client") return;
    if (clientSignUpMatchesHearingName(data, cn)) matched.add(uid);
  };

  for (const party of queryNames) {
    const nameKeys = clientNameQueryVariants(party).slice(0, 6);
    for (const field of fields) {
      for (const nm of nameKeys) {
        try {
          const uq = await db.collection("users").where(field, "==", nm).limit(15).get();
          for (const u of uq.docs) {
            tryAdd(u.data() as Record<string, unknown>, u.id);
          }
        } catch {
          /* index / field */
        }
      }
    }

    const hearingParts = parseFirstLastFromHearingName(party);
    if (!hearingParts) continue;
    const firstKeys = clientNameQueryVariants(hearingParts.first);
    const lastKeys = clientNameQueryVariants(hearingParts.last);
    for (const first of firstKeys) {
      for (const last of lastKeys) {
        try {
          const uq = await db
            .collection("users")
            .where("role", "==", "client")
            .where("firstName", "==", first)
            .where("lastName", "==", last)
            .limit(15)
            .get();
          for (const u of uq.docs) {
            tryAdd(u.data() as Record<string, unknown>, u.id);
          }
        } catch {
          /* composite index may be missing — scan below */
        }
      }
    }
  }

  try {
    const cq = await db.collection("users").where("role", "==", "client").limit(300).get();
    for (const u of cq.docs) {
      if (matched.has(u.id)) continue;
      tryAdd(u.data() as Record<string, unknown>, u.id);
    }
  } catch (e) {
    logger.warn("hearingSms: exact client scan failed", {
      err: e instanceof Error ? e.message : String(e),
    });
  }

  return [...matched];
}

/** Matched client + their assigned attorney/staff — not the whole firm. */
async function addAssignedRecipientsForUnmatchedImport(
  db: admin.firestore.Firestore,
  recipients: Set<string>,
  d: HearingDoc,
): Promise<void> {
  if (!isImportedCourtRow(d)) return;

  for (const uid of await resolveClientUidsByHearingName(db, asString(d.clientName))) {
    recipients.add(uid);
    try {
      const u = await db.collection("users").doc(uid).get();
      const att = asString(u.data()?.assignedAttorneyId);
      if (att) {
        recipients.add(att);
        const staffSnap = await db
          .collection("users")
          .where("assignedAttorneyId", "==", att)
          .where("role", "==", "staff")
          .limit(50)
          .get();
        for (const s of staffSnap.docs) recipients.add(s.id);
      }
    } catch {
      /* ignore */
    }
  }
}

/** Court import with no `cases` match — notify firm + matched client by name. */
async function addFirmRecipientsForUnmatchedImport(
  db: admin.firestore.Firestore,
  recipients: Set<string>,
  d: HearingDoc,
): Promise<void> {
  if (!isImportedCourtRow(d)) return;

  await addAssignedRecipientsForUnmatchedImport(db, recipients, d);

  for (const role of ["attorney", "staff", "admin"]) {
    try {
      const q = await db.collection("users").where("role", "==", role).limit(80).get();
      for (const doc of q.docs) recipients.add(doc.id);
    } catch {
      /* ignore */
    }
  }
}

/**
 * Timed SMS/push audience: case attorney + assigned staff + matched client.
 * Not every staff in the firm (that is what exploded 1 hearing → ~20 jobs).
 */
async function collectCoreHearingRecipients(
  db: admin.firestore.Firestore,
  d: HearingDoc,
): Promise<{
  resolved: { caseId: string; caseTitle: string } | null;
  uids: string[];
}> {
  const resolved = await resolveCaseForHearing(db, d);
  const recipients = new Set<string>();
  if (resolved) {
    const { uids } = await collectCaseParticipantUids(db, resolved.caseId);
    for (const u of uids) recipients.add(u);
  }
  for (const u of extractExtraUids(d)) recipients.add(u);
  for (const uid of await resolveClientUidsByHearingName(db, asString(d.clientName))) {
    recipients.add(uid);
  }
  if (!recipients.size) {
    await addAssignedRecipientsForUnmatchedImport(db, recipients, d);
  }
  return { resolved, uids: [...recipients] };
}

/** All active staff receive court-import hearing alerts (not only assigned paralegals). */
async function addAllActiveStaff(
  db: admin.firestore.Firestore,
  recipients: Set<string>,
): Promise<void> {
  try {
    const q = await db.collection("users").where("role", "==", "staff").limit(100).get();
    for (const doc of q.docs) {
      if (doc.data()?.isActive === false) continue;
      recipients.add(doc.id);
    }
  } catch (e) {
    logger.warn("hearingNotify: addAllActiveStaff failed", {
      err: e instanceof Error ? e.message : String(e),
    });
  }
}

/** Active attorneys receive the same court-import popup + SMS as staff. */
async function addAllActiveAttorneys(
  db: admin.firestore.Firestore,
  recipients: Set<string>,
): Promise<void> {
  try {
    const q = await db.collection("users").where("role", "==", "attorney").limit(40).get();
    for (const doc of q.docs) {
      if (doc.data()?.isActive === false) continue;
      recipients.add(doc.id);
    }
  } catch (e) {
    logger.warn("hearingNotify: addAllActiveAttorneys failed", {
      err: e instanceof Error ? e.message : String(e),
    });
  }
}

/** Matches imported court `caseNo` to `cases` fields / titles / fullText (OCR spacing, dashes). */
function textContainsCaseReference(haystack: string, caseRef: string): boolean {
  const needle = caseRef.trim();
  if (needle.length < 4) return false;
  const h0 = haystack.trim();
  if (!h0) return false;
  const h = h0
    .replace(/–/g, "-")
    .replace(/—/g, "-")
    .replace(/\s+/g, " ")
    .toLowerCase();
  const n = needle
    .replace(/–/g, "-")
    .replace(/—/g, "-")
    .replace(/\s+/g, " ")
    .toLowerCase();
  if (h.includes(n)) return true;
  const hc = alnumLower(h0);
  const nc = alnumLower(needle);
  return nc.length >= 4 && hc.includes(nc);
}

function fieldMatchesCaseReference(fieldValue: unknown, caseNo: string): boolean {
  const v = asString(fieldValue);
  if (!v) return false;
  if (v === caseNo) return true;
  if (textContainsCaseReference(v, caseNo)) return true;
  const av = alnumLower(v);
  const an = alnumLower(caseNo);
  return an.length >= 4 && (av === an || av.includes(an) || an.includes(av));
}

function caseMapMatchesHearing(m: Record<string, unknown>, caseNo: string, d: HearingDoc): boolean {
  const fields = ["caseNumber", "caseNo", "docketNumber", "criminalCaseNo"] as const;
  for (const f of fields) {
    if (fieldMatchesCaseReference(m[f], caseNo)) return true;
  }
  const title = asString(m.caseTitle);
  if (textContainsCaseReference(title, caseNo)) return true;
  const ft = asString(d.fullText);
  if (ft) {
    for (const f of fields) {
      const fv = asString(m[f]);
      if (fv.length >= 6 && textContainsCaseReference(ft, fv)) return true;
    }
    if (textContainsCaseReference(ft, caseNo)) return true;
  }
  return false;
}

async function collectCaseParticipantUids(
  db: admin.firestore.Firestore,
  caseId: string,
): Promise<{ uids: string[]; caseTitle: string }> {
  const snap = await db.collection("cases").doc(caseId).get();
  if (!snap.exists) return { uids: [], caseTitle: "" };
  const c = snap.data() as Record<string, unknown>;
  const uids = new Set<string>();
  if (c.clientId) uids.add(String(c.clientId));
  if (c.attorneyId) uids.add(String(c.attorneyId));
  if (c.staffId) uids.add(String(c.staffId));
  const sa = c.staffAssigned;
  if (Array.isArray(sa)) {
    for (const id of sa) {
      if (id) uids.add(String(id));
    }
  }

  const attorneyId = c.attorneyId ? String(c.attorneyId).trim() : "";
  if (attorneyId) {
    try {
      const staffSnap = await db
        .collection("users")
        .where("assignedAttorneyId", "==", attorneyId)
        .limit(100)
        .get();
      for (const doc of staffSnap.docs) {
        const r = String(doc.data()?.role || "").toLowerCase();
        if (r === "staff") uids.add(doc.id);
      }
    } catch (e) {
      logger.warn("hearingNotify: staff query failed", {
        caseId,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  const caseTitle = asString(c.caseTitle) || "Case";
  return { uids: [...uids], caseTitle };
}

async function findCaseByCaseReference(
  db: admin.firestore.Firestore,
  caseNo: string,
  clientName: string,
): Promise<{ caseId: string; caseTitle: string } | null> {
  const n = caseNo.trim();
  if (!n) return null;

  const variants = caseNumberVariants(n);
  const fields = ["caseNumber", "caseNo", "docketNumber", "criminalCaseNo"] as const;
  for (const f of fields) {
    for (const v of variants) {
      try {
        const q = await db.collection("cases").where(f, "==", v).limit(5).get();
        if (!q.empty) {
          const doc = q.docs[0];
          return { caseId: doc.id, caseTitle: asString(doc.data().caseTitle) || n };
        }
      } catch {
        /* field missing on index or type */
      }
    }
  }

  const nameKeys = new Set<string>();
  const cn = clientName.trim();
  if (cn) {
    nameKeys.add(cn);
    nameKeys.add(cn.replace(/\s+/g, " ").trim());
  }
  for (const nameNorm of nameKeys) {
    if (!nameNorm) continue;
    for (const nameField of ["name", "fullName", "displayName"] as const) {
      try {
        const usersSnap = await db
          .collection("users")
          .where(nameField, "==", nameNorm)
          .limit(25)
          .get();
        for (const udoc of usersSnap.docs) {
          const role = String(udoc.data()?.role || "").toLowerCase();
          if (role !== "client") continue;
          const cq = await db.collection("cases").where("clientId", "==", udoc.id).limit(50).get();
          for (const cdoc of cq.docs) {
            const title = String(cdoc.data()?.caseTitle || "");
            if (textContainsCaseReference(title, n)) {
              return { caseId: cdoc.id, caseTitle: asString(cdoc.data()?.caseTitle) || n };
            }
          }
        }
      } catch (e) {
        logger.warn("hearingNotify: clientName case lookup failed", {
          nameField,
          err: e instanceof Error ? e.message : String(e),
        });
      }
    }
  }

  try {
    const prefix = await db
      .collection("cases")
      .where("caseTitle", ">=", n)
      .where("caseTitle", "<=", `${n}\uf8ff`)
      .limit(5)
      .get();
    if (!prefix.empty) {
      const doc = prefix.docs[0];
      return { caseId: doc.id, caseTitle: asString(doc.data().caseTitle) || n };
    }
  } catch {
    /* ignore */
  }

  return null;
}

/** When global caseNo lookup fails, match against cases under the uploader's attorney (import flow). */
async function findCaseByUploaderAttorney(
  db: admin.firestore.Firestore,
  d: HearingDoc,
  caseNo: string,
): Promise<{ caseId: string; caseTitle: string } | null> {
  const n = caseNo.trim();
  if (!n) return null;
  const uploader =
    asString(d.uploadedBy) ||
    asString(d.createdBy) ||
    asString(d.senderId) ||
    asString(d.attorneyUid);
  if (!uploader) return null;
  try {
    const udoc = await db.collection("users").doc(uploader).get();
    if (!udoc.exists) return null;
    const ud = udoc.data() as Record<string, unknown>;
    const role = String(ud.role || "").toLowerCase();
    let attorneyId = "";
    if (role === "attorney") attorneyId = uploader;
    else if (role === "staff") attorneyId = asString(ud.assignedAttorneyId);
    if (!attorneyId) return null;
    const cq = await db.collection("cases").where("attorneyId", "==", attorneyId).limit(500).get();
    for (const cdoc of cq.docs) {
      const data = cdoc.data() as Record<string, unknown>;
      if (caseMapMatchesHearing(data, n, d)) {
        return { caseId: cdoc.id, caseTitle: asString(data.caseTitle) || n };
      }
    }
  } catch (e) {
    logger.warn("hearingNotify: uploader attorney case scan failed", {
      err: e instanceof Error ? e.message : String(e),
    });
  }
  return null;
}

async function resolveCaseForHearing(
  db: admin.firestore.Firestore,
  d: HearingDoc,
): Promise<{ caseId: string; caseTitle: string } | null> {
  const explicit = asString(d.caseId);
  if (explicit) {
    const snap = await db.collection("cases").doc(explicit).get();
    if (snap.exists) {
      return {
        caseId: explicit,
        caseTitle: asString(snap.data()?.caseTitle) || explicit,
      };
    }
  }

  const caseNo = asString(d.caseNo);
  if (caseNo) {
    let found = await findCaseByCaseReference(db, caseNo, asString(d.clientName));
    if (found) return found;
    found = await findCaseByUploaderAttorney(db, d, caseNo);
    if (found) return found;
  }

  return null;
}

async function resolveUserEmail(uid: string): Promise<string | null> {
  try {
    const rec = await admin.auth().getUser(uid);
    if (rec.email && rec.emailVerified) return rec.email;
    if (rec.email) return rec.email;
  } catch {
    /* ignore */
  }
  return null;
}

export function buildNotificationBody(
  d: HearingDoc,
  resolved: { caseId: string; caseTitle: string },
): string {
  const lines: string[] = [];

  if (isImportedCourtRow(d)) {
    const cn = asString(d.caseNo);
    if (cn) lines.push(`Case No.: ${cn}`);
    const cl = asString(d.clientName);
    if (cl) lines.push(`Client: ${cl}`);
    const br = asString(d.courtBranch);
    if (br) lines.push(`Court / Branch: ${br}`);
    const ft = asString(d.fullText);
    if (ft) {
      const excerpt = ft.length > 3500 ? `${ft.slice(0, 3497)}...` : ft;
      lines.push("", "Order / notice:", excerpt);
    }
    let body = lines.filter(Boolean).join("\n");
    if (body.length > 1800) body = `${body.slice(0, 1797)}...`;
    return body;
  } else {
    const sender = asString(d.senderName) || "Staff";
    const msg = asString(d.message) || "(no message)";
    lines.push(msg, "", `From: ${sender}`);
  }

  const ht = hearingAtFromDoc(d);
  if (ht) lines.push("", `Hearing date/time: ${ht.toISOString()}`);

  lines.push("", `Matter: ${resolved.caseTitle}`);
  lines.push(`Case record ID: ${resolved.caseId}`);

  let body = lines.filter(Boolean).join("\n");
  if (body.length > 1800) body = `${body.slice(0, 1797)}...`;
  return body;
}

const HEARING_MONTH =
  "(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)";

/** Date the order sets ("reset the pre-trial on October 28"), not the signing date. */
function nextSetHearingLabel(d: HearingDoc): string {
  const blobs = [asString(d.fullText), asString(d.message), asString(d.hearingTime)];
  const re = new RegExp(
    `(?:reset|set|schedul\\w*|next hearing)\\b[^\\n.]{0,80}?\\bon\\s+${HEARING_MONTH}\\.?\\s+(\\d{1,2}),?\\s+(\\d{4})`,
    "i",
  );
  for (const blob of blobs) {
    if (!blob) continue;
    const m = re.exec(blob);
    if (!m) continue;
    const window = blob.slice(m.index + m[0].length, Math.min(blob.length, m.index + m[0].length + 48));
    const clock = /(\d{1,2})(?::(\d{2}))?/.exec(window);
    let time = "";
    if (clock) {
      let hour = Number(clock[1]);
      const minute = clock[2] ?? "00";
      const lower = window.toLowerCase();
      const afternoon = lower.includes("pm") || lower.includes("afternoon") || lower.includes("evening");
      const morning = lower.includes("am") || lower.includes("morning");
      if (afternoon && hour < 12) hour += 12;
      if (morning && hour === 12) hour = 0;
      const h12 = hour % 12 === 0 ? 12 : hour % 12;
      const ap = hour >= 12 ? "PM" : "AM";
      time = `${h12}:${minute.padStart(2, "0")} ${ap}`;
    }
    const kind = /pre-?\s*trial/i.test(blob)
      ? "Pre-trial"
      : /arraignment/i.test(blob)
        ? "Arraignment"
        : /mediation/i.test(blob)
          ? "Mediation"
          : "Hearing";
    return [kind, `${m[1]} ${m[2]}, ${m[3]}`, time].filter(Boolean).join(" ");
  }
  const date = asString(d.hearingDate);
  const time = asString(d.hearingTime);
  return [date, time].filter(Boolean).join(", ");
}

/**
 * Locked hearing push body. Do not shorten or reorder:
 * Case No. / Client / Court / Branch, then Order / notice with the case
 * title and "{branch} · Hearing {Month D, YYYY}".
 */
function buildHearingPushBody(d: HearingDoc, fallback: string): string {
  const caseNo = asString(d.caseNo);
  const client = asString(d.clientName);
  const branch = asString(d.courtBranch);
  const caseTitle = asString(d.caseTitle);
  let when = nextSetHearingLabel(d).replace(
    /\s+\d{1,2}:\d{2}\s*(?:AM|PM)\b/i,
    "",
  ).trim();
  if (when && !/^(hearing|pre-trial|arraignment|mediation)\b/i.test(when)) {
    when = `Hearing ${when}`;
  }
  const whenLine = [branch, when].filter(Boolean).join(" · ");

  const lines: string[] = [];
  if (caseNo) lines.push(`Case No.: ${caseNo}`);
  if (client) lines.push(`Client: ${client}`);
  if (branch) lines.push(`Court / Branch: ${branch}`);
  if (caseTitle || whenLine) {
    lines.push("", "Order / notice:");
    if (caseTitle) lines.push(caseTitle);
    if (whenLine) lines.push(whenLine);
  }
  const out = lines.join("\n").trim();
  if (out) return out.length > 900 ? `${out.slice(0, 897)}...` : out;
  return fallback.trim();
}

function stringifyData(raw: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (v === undefined || v === null) continue;
    out[k] = typeof v === "string" ? v : JSON.stringify(v);
  }
  return out;
}

/** Stable IDs align with Flutter `HearingNotificationFanoutService` (`hearing_inapp_*`) so CF + client merge cleanly. */
function hearingNotificationDocId(params: {
  notificationType: string;
  hearingDocId: string;
  uid: string;
  reminderKind?: HearingReminderKind | null;
  /** Disambiguate multiple update deliveries for the same user. */
  updateNonce?: string;
}): string {
  const { notificationType, hearingDocId, uid, reminderKind, updateNonce } = params;
  const safeHid = hearingDocId.replace(/[/\\]/g, "_");
  const safeUid = uid.replace(/[/\\]/g, "_");
  if (reminderKind) {
    return `hearing_reminder_${reminderKind}_${safeHid}_${safeUid}`;
  }
  if (notificationType === "hearing_activity") {
    return `hearing_inapp_${safeHid}_${safeUid}`;
  }
  if (notificationType === "hearing_activity_update") {
    const n = (updateNonce || `${Date.now()}`).replace(/[/\\]/g, "_");
    return `hearing_inapp_upd_${safeHid}_${safeUid}_${n}`;
  }
  if (notificationType.startsWith("hearing_reminder_")) {
    const k = notificationType.slice("hearing_reminder_".length);
    return `hearing_reminder_${k}_${safeHid}_${safeUid}`;
  }
  return `hearing_misc_${safeHid}_${safeUid}_${Date.now()}`;
}

/**
 * In-app + push + email queue for all recipients (including sender / uploader).
 */
export async function deliverHearingNotification(params: {
  db: admin.firestore.Firestore;
  caseId: string;
  hearingDocId: string;
  recipients: string[];
  title: string;
  body: string;
  notificationType: string;
  reminderKind?: HearingReminderKind | null;
  data: Record<string, unknown>;
  /** Source hearing row (used for client-specific inbox titles). */
  hearingDoc?: HearingDoc | null;
  /** Firestore doc id suffix for update notifications (one row per meaningful update). */
  updateNonce?: string;
  /** When true, only write `notifications` rows (no FCM / email queue). */
  inAppOnly?: boolean;
  /** Known client UIDs — skips per-user role lookups when provided. */
  clientRecipientIds?: string[];
}): Promise<void> {
  const {
    db,
    caseId,
    hearingDocId,
    recipients,
    title,
    body,
    notificationType,
    reminderKind,
    data,
    hearingDoc,
    updateNonce,
    inAppOnly = false,
    clientRecipientIds,
  } = params;

  if (!recipients.length) {
    logger.warn("hearingNotify: no recipients", { caseId, hearingDocId });
    return;
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const caseTitle =
    asString(data["caseTitle"]) || asString(data["caseNo"]) || "Hearing";
  const knownClients = new Set(clientRecipientIds ?? []);
  const userByUid = new Map<string, Record<string, unknown>>();
  await Promise.all(
    recipients.map(async (uid) => {
      try {
        const u = await db.collection("users").doc(uid).get();
        userByUid.set(uid, (u.data() ?? {}) as Record<string, unknown>);
      } catch {
        userByUid.set(uid, {});
      }
    }),
  );
  const roleByUid = new Map<string, string>();
  for (const uid of recipients) {
    const stored = asString(userByUid.get(uid)?.role).toLowerCase();
    roleByUid.set(
      uid,
      knownClients.has(uid) ? "client" : stored,
    );
  }

  if (!inAppOnly) {
    const messaging = admin.messaging();
    const seenTokens = new Set<string>();
    const pushBody = buildHearingPushBody(hearingDoc ?? {}, body);
    const { fullText: _omitFullText, ...pushData } = data;
    const dataStrings = stringifyData({
      ...pushData,
      type: notificationType,
      caseId,
      hearingDocId,
    });
    const tokens: string[] = [];
    for (const uid of recipients) {
      const token = userByUid.get(uid)?.fcmToken;
      if (typeof token !== "string" || token.length <= 20 || seenTokens.has(token)) {
        continue;
      }
      seenTokens.add(token);
      tokens.push(token);
    }
    if (tokens.length) {
      try {
        const result = await messaging.sendEachForMulticast({
          tokens,
          notification: { title, body: pushBody },
          data: dataStrings,
          android: {
            priority: "high" as const,
            notification: {
              title,
              body: pushBody,
              sound: "default",
              channelId: "high_importance_channel",
              defaultSound: true,
              visibility: "public",
            },
          },
          apns: {
            payload: {
              aps: { sound: "default", badge: 1, alert: { title, body: pushBody } },
            },
          },
          webpush: {
            notification: {
              title,
              body: pushBody,
              silent: false,
            },
          },
        });
        if (result.failureCount) {
          logger.warn("hearingNotify: FCM multicast partial fail", {
            failureCount: result.failureCount,
            successCount: result.successCount,
          });
        }
      } catch (e) {
        logger.warn("hearingNotify: FCM failed", {
          err: e instanceof Error ? e.message : String(e),
        });
      }
    }
  }

  const batch = db.batch();
  const existingByUid = new Map<string, { exists: boolean; wasRead: boolean }>();
  if (!inAppOnly) {
    await Promise.all(
      recipients.map(async (uid) => {
        const nid = hearingNotificationDocId({
          notificationType,
          hearingDocId,
          uid,
          reminderKind: reminderKind ?? undefined,
          updateNonce,
        });
        try {
          const existing = await db.collection("notifications").doc(nid).get();
          existingByUid.set(uid, {
            exists: existing.exists,
            wasRead:
              existing.exists &&
              (existing.data()?.isRead === true || existing.data()?.readAt != null),
          });
        } catch {
          existingByUid.set(uid, { exists: false, wasRead: false });
        }
      }),
    );
  }
  for (const uid of recipients) {
    const nid = hearingNotificationDocId({
      notificationType,
      hearingDocId,
      uid,
      reminderKind: reminderKind ?? undefined,
      updateNonce,
    });
    const nref = db.collection("notifications").doc(nid);
    const prior = existingByUid.get(uid);
    const wasRead = prior?.wasRead === true;
    const existingExists = prior?.exists === true;

    const isClient = roleByUid.get(uid) === "client";
    const rowTitle =
      isClient && notificationType === "hearing_activity"
        ? hearingDoc
          ? clientInboxTitleFromHearing(hearingDoc, caseTitle)
          : asString(data["caseNo"])
            ? `New notice court hearings — ${asString(data["caseNo"])}`
            : `New notice court hearings — ${caseTitle}`
        : title;
    const row: Record<string, unknown> = {
      userId: uid,
      type: notificationType,
      title: rowTitle,
      message: body,
      caseId: caseId || null,
      caseNo: asString(data["caseNo"]) || null,
      clientName: asString(data["clientName"]) || null,
      courtBranch: asString(data["courtBranch"]) || null,
      caseTitle: asString(data["caseTitle"]) || null,
      fullText: asString(data["fullText"]) || asString(hearingDoc?.fullText) || null,
      location: asString(data["location"]) || asString(data["courtBranch"]) || null,
      hearingDate: asString(data["hearingDate"]) || null,
      hearingTime: asString(data["hearingTime"]) || null,
      hearingDocId,
      hearingReminderKind: reminderKind ?? null,
    };
    const src = asString(data["source"]);
    if (src) row.source = src;
    if (isClient) row.clientId = uid;
    if (roleByUid.get(uid) === "attorney") row.attorneyId = uid;
    if (wasRead) {
      row.isRead = true;
    } else if (!existingExists) {
      row.isRead = false;
      row.createdAt = now;
    }
    batch.set(nref, row, { merge: true });
  }
  await batch.commit();

  if (inAppOnly) return;

  await Promise.all(
    recipients.map(async (uid) => {
      const to = await resolveUserEmail(uid);
      if (!to) return;
      await db.collection("email_requests").add({
        to,
        subject: title,
        text: body,
        status: "pending",
        userId: uid,
        caseId: caseId || null,
        hearingDocId,
        notificationType,
        createdAt: now,
      });
    }),
  );
}

async function upsertReminderJobs(params: {
  db: admin.firestore.Firestore;
  hearingDocId: string;
  caseId: string;
  hearingAt: Date;
  recipients: string[];
  snapshot: {
    senderName: string;
    message: string;
    caseTitle: string;
    activityType: string;
    caseNo: string;
    clientName: string;
    courtBranch: string;
  };
  /** Cancel pending jobs for people who should not get timed reminders. */
  pruneUnlistedRecipients?: boolean;
}): Promise<void> {
  const {
    db,
    hearingDocId,
    caseId,
    hearingAt,
    recipients,
    snapshot,
    pruneUnlistedRecipients = false,
  } = params;
  const now = new Date();
  const rows = reminderSchedule(hearingAt, now);
  const hearingAtMs = hearingAt.getTime();
  const allowed = new Set(recipients.filter((u) => u.length > 0));

  const existingSnap = await db
    .collection("hearing_reminder_jobs")
    .where("hearingDocId", "==", hearingDocId)
    .get();
  const alreadySent = new Set<string>();
  const existingPending = new Map<
    string,
    { hearingAtMs?: number; reminderKind?: string; targetUserId?: string }
  >();
  const batch = db.batch();
  let writes = 0;

  for (const doc of existingSnap.docs) {
    const d = doc.data() as {
      status?: string;
      hearingAtMs?: number;
      reminderKind?: string;
      targetUserId?: string;
    };
    const kind = asString(d.reminderKind);
    const uid = asString(d.targetUserId);
    if (
      d.status === "sent" &&
      d.hearingAtMs === hearingAtMs &&
      kind &&
      uid
    ) {
      alreadySent.add(`${kind}_${uid}`);
    }
    if (d.status !== "pending") continue;
    const obsolete = !isActiveHearingReminderKind(kind);
    const extra = pruneUnlistedRecipients && uid.length > 0 && !allowed.has(uid);
    if (obsolete || extra) {
      batch.update(doc.ref, {
        status: "cancelled",
        error: obsolete ? "obsolete_kind" : "not_a_recipient",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      writes += 1;
      continue;
    }
    existingPending.set(doc.id, d);
  }

  if (!rows.length || !allowed.size) {
    if (writes) await batch.commit();
    return;
  }

  for (const uid of allowed) {
    for (const { kind, at } of rows) {
      if (alreadySent.has(`${kind}_${uid}`)) continue;
      const jobId = `${hearingDocId}_${kind}_${uid}`.replace(/[/\\]/g, "_");
      const existing = existingPending.get(jobId);
      if (
        existing &&
        existing.hearingAtMs === hearingAtMs &&
        asString(existing.reminderKind) === kind &&
        asString(existing.targetUserId) === uid
      ) {
        continue;
      }
      const ref = db.collection("hearing_reminder_jobs").doc(jobId);
      batch.set(
        ref,
        {
          hearingDocId,
          caseId,
          targetUserId: uid,
          reminderKind: kind,
          scheduledFor: admin.firestore.Timestamp.fromDate(at),
          hearingAtMs,
          status: "pending",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          snapshot,
        },
        { merge: true },
      );
      writes += 1;
    }
  }
  if (writes) await batch.commit();
}

async function cancelObsoletePendingReminderJobs(
  db: admin.firestore.Firestore,
  hearingDocId: string,
): Promise<void> {
  const q = await db
    .collection("hearing_reminder_jobs")
    .where("hearingDocId", "==", hearingDocId)
    .where("status", "==", "pending")
    .get();
  if (q.empty) return;
  const batch = db.batch();
  let n = 0;
  for (const doc of q.docs) {
    const kind = asString(doc.data().reminderKind);
    if (isActiveHearingReminderKind(kind)) continue;
    batch.update(doc.ref, {
      status: "cancelled",
      error: "obsolete_kind",
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    n += 1;
  }
  if (n) await batch.commit();
}

async function resetHearingReminderSentFlags(
  db: admin.firestore.Firestore,
  hearingDocId: string,
  hearingAt: Date | null,
): Promise<void> {
  await db.collection("hearings").doc(hearingDocId).set(
    {
      fiveDayReminderSent: false,
      twoDayReminderSent: false,
      hearingDayReminderSent: false,
      philsmsRemindersSent: {
        d5: false,
        d2: false,
        hearing_day: false,
        d1: false,
        d3: false,
        day_noon: false,
        h10: false,
        m5: false,
      },
      hearingReminderAtMs: hearingAt ? hearingAt.getTime() : null,
    },
    { merge: true },
  );
}

async function relatedCaseBlocksReminders(
  db: admin.firestore.Firestore,
  hearing: HearingDoc,
): Promise<boolean> {
  const caseId = asString(hearing.caseId);
  if (!caseId) return false;
  try {
    const snap = await db.collection("cases").doc(caseId).get();
    if (!snap.exists) return false;
    const data = snap.data() ?? {};
    return caseStatusBlocksReminders(
      asString(data.status),
      data.isArchived,
    );
  } catch {
    return false;
  }
}

export async function cancelPendingReminderJobs(
  db: admin.firestore.Firestore,
  hearingDocId: string,
  reason = "cancelled",
): Promise<void> {
  const q = await db
    .collection("hearing_reminder_jobs")
    .where("hearingDocId", "==", hearingDocId)
    .where("status", "==", "pending")
    .get();

  const batch = db.batch();
  for (const doc of q.docs) {
    batch.update(doc.ref, {
      status: "cancelled",
      error: reason,
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  if (!q.empty) await batch.commit();
}

function snapshotFromHearing(d: HearingDoc, caseTitle: string) {
  return {
    senderName: asString(d.senderName) || asString(d.clientName) || "Court notice",
    message: isImportedCourtRow(d)
      ? `${asString(d.caseNo)} — ${asString(d.courtBranch)}`
      : asString(d.message),
    caseTitle,
    activityType: asString(d.activityType) || (isImportedCourtRow(d) ? "court_import" : "message"),
    caseNo: asString(d.caseNo),
    clientName: asString(d.clientName),
    courtBranch: asString(d.courtBranch),
  };
}

function hearingChangedMeaningfully(d0: HearingDoc, d1: HearingDoc): boolean {
  const keys: (keyof HearingDoc)[] = [
    "caseId",
    "caseNo",
    "clientName",
    "courtBranch",
    "fullText",
    "message",
    "activityType",
    "hearingDateTime",
    "senderName",
    "hearingDate",
    "hearingTime",
    "location",
    "status",
  ];
  for (const k of keys) {
    if (asString(d0[k] as unknown) !== asString(d1[k] as unknown)) return true;
  }
  const cancelled0 =
    (d0 as Record<string, unknown>).cancelled === true ||
    (d0 as Record<string, unknown>).isCancelled === true;
  const cancelled1 =
    (d1 as Record<string, unknown>).cancelled === true ||
    (d1 as Record<string, unknown>).isCancelled === true;
  if (cancelled0 !== cancelled1) return true;
  const t0 = hearingAtFromDoc(d0)?.getTime() ?? null;
  const t1 = hearingAtFromDoc(d1)?.getTime() ?? null;
  return t0 !== t1;
}

async function stampHearingInboxFields(
  snap: QueryDocumentSnapshot,
  d: HearingDoc,
  hearingDocId: string,
): Promise<void> {
  try {
    const raw = snap.data() as Record<string, unknown>;
    const patch: Record<string, unknown> = {};
    const created = timestampFromUnknown(raw.createdAt);
    if (!created) {
      patch.createdAt = admin.firestore.FieldValue.serverTimestamp();
    } else if (typeof raw.createdAt === "string") {
      patch.createdAt = created;
    }
    if (!asString(raw.updatedAt)) {
      patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    if (!hearingSource(d) && isImportedCourtRow(d)) patch.source = "n8n";
    if (!asString(d.activityType) && isImportedCourtRow(d)) {
      patch.activityType = "court_import";
    }
    if (Object.keys(patch).length) {
      await snap.ref.set(patch, { merge: true });
    }
  } catch (e) {
    logger.warn("hearingNotify inbox stamp skipped", {
      hearingDocId,
      err: e instanceof Error ? e.message : String(e),
    });
  }
}

export async function handleHearingDocumentCreated(
  event: FirestoreEvent<QueryDocumentSnapshot | undefined, { hearingId: string }>,
  philSms?: PhilSmsHearingCfg,
  semaphore?: SemaphoreHearingCfg,
): Promise<void> {
  const snap = event.data;
  if (!snap?.exists) return;

  const hearingDocId = event.params.hearingId;
  const d = snap.data() as HearingDoc;
  if (isJunkHearingDoc(d)) {
    logger.info("hearingNotify skipped junk hearing", { hearingDocId });
    return;
  }
  const db = admin.firestore();

  // Stamp after the push is queued so createdAt / source writes do not delay FCM.
  const stampTask = stampHearingInboxFields(snap, d, hearingDocId);

  const duplicateCase =
    (await laterDuplicateOfExistingHearing(db, hearingDocId, d)) ||
    !(await claimPrimaryHearingNotice(db, hearingDocId, d));
  if (duplicateCase) {
    logger.info("hearingNotify duplicate case still sends notice", {
      hearingDocId,
      caseNo: asString(d.caseNo),
    });
  }

  const courtAlert = isCourtHearingForStaffAlert(d);
  const corePromise = collectCoreHearingRecipients(db, d);
  const firmPromise = (async () => {
    const found = new Set<string>();
    await addFirmRecipientsForUnmatchedImport(db, found, d);
    return found;
  })();
  const firmWidePromise = courtAlert
    ? (async () => {
        const found = new Set<string>();
        await Promise.all([
          addAllActiveStaff(db, found),
          addAllActiveAttorneys(db, found),
        ]);
        return found;
      })()
    : Promise.resolve(new Set<string>());

  const { resolved, uids: reminderUids } = await corePromise;
  const coreRecipients = new Set<string>(reminderUids);

  const caseTitle = resolved?.caseTitle || asString(d.caseTitle) || asString(d.caseNo) || "Hearing";
  const caseId = resolved?.caseId || "";

  const activity = asString(d.activityType) || (isImportedCourtRow(d) ? "court_notice" : "message");
  const title = isImportedCourtRow(d)
    ? `Court hearing / order — ${asString(d.caseNo) || caseTitle}`
    : activity === "schedule"
      ? `Hearing scheduled — ${caseTitle}`
      : activity === "update"
        ? `Hearing updated — ${caseTitle}`
        : `Hearing message — ${caseTitle}`;

  const body = buildNotificationBody(d, {
    caseId: caseId || hearingDocId,
    caseTitle,
  });

  const noticeData = {
    activityType: activity,
    caseNo: asString(d.caseNo),
    clientName: asString(d.clientName),
    courtBranch: asString(d.courtBranch),
    caseTitle,
    fullText: asString(d.fullText),
    location: asString(d.location) || asString(d.courtBranch),
    hearingDate: asString(d.hearingDate),
    hearingTime: asString(d.hearingTime),
  };

  const sent = new Set<string>();
  const pushTo = async (recipients: string[]) => {
    const pending = recipients.filter((uid) => uid && !sent.has(uid));
    if (!pending.length) return;
    for (const uid of pending) sent.add(uid);
    await deliverHearingNotification({
      db,
      caseId,
      hearingDocId,
      recipients: pending,
      title,
      body,
      notificationType: "hearing_activity",
      reminderKind: null,
      hearingDoc: d,
      data: noticeData,
    });
  };

  // Attorney, client, and uploader first — do not wait for the firm-wide scan.
  if (coreRecipients.size) {
    await pushTo([...coreRecipients]);
  }

  const [firmRecipients, firmWideRecipients] = await Promise.all([
    firmPromise,
    firmWidePromise,
  ]);
  const extras = new Set<string>();
  if (!coreRecipients.size) {
    for (const uid of firmRecipients) extras.add(uid);
  }
  for (const uid of firmWideRecipients) {
    if (!coreRecipients.has(uid)) extras.add(uid);
  }
  if (extras.size) {
    await pushTo([...extras]);
  }

  const list = [...sent];
  await stampTask;

  if (!list.length) {
    logger.warn("hearingNotify: no recipients (case, clientName, or firm fallback)", {
      hearingDocId,
      caseNo: asString(d.caseNo),
      clientName: asString(d.clientName),
    });
    return;
  }

  if (philSms?.apiToken.trim() || semaphore?.apiKey.trim()) {
    try {
      await sendHearingSmsAlerts({
        db,
        hearingDocId,
        hearingData: snap.data() as HearingDoc & Record<string, unknown>,
        recipientUserIds: list,
        title,
        body,
        cfg: philSms ?? {
          apiToken: "",
          senderId: "PhilSMS",
          alertPhones: [],
          staffAlertPhones: [],
        },
        semaphore,
      });
    } catch (e) {
      logger.warn("hearingSms: create handler failed", {
        hearingDocId,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  const clientUids = await resolveClientUidsByHearingName(db, asString(d.clientName));
  if (clientUids.length) {
    try {
      await db
        .collection("hearings")
        .doc(hearingDocId)
        .set(
          {
            involvedClientIds: admin.firestore.FieldValue.arrayUnion(...clientUids),
            matchedClientIds: admin.firestore.FieldValue.arrayUnion(...clientUids),
            ...(splitHearingPartyNames(asString(d.clientName)).length
              ? {
                  involvedPartyNames: admin.firestore.FieldValue.arrayUnion(
                    ...splitHearingPartyNames(asString(d.clientName)),
                  ),
                }
              : {}),
          },
          { merge: true },
        );
    } catch (e) {
      logger.warn("hearingNotify: involvedClientIds merge failed", {
        hearingDocId,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  const ht = hearingAtFromDoc(d);
  if (
    !duplicateCase &&
    ht &&
    !isHearingInactiveForReminders(d as HearingDoc & Record<string, unknown>) &&
    !(await relatedCaseBlocksReminders(db, d))
  ) {
    await upsertReminderJobs({
      db,
      hearingDocId,
      caseId: resolved?.caseId || hearingDocId,
      hearingAt: ht,
      recipients: reminderUids,
      snapshot: snapshotFromHearing(d, caseTitle),
      pruneUnlistedRecipients: true,
    });
  }
}

export async function handleHearingDocumentUpdated(
  event: FirestoreEvent<
    Change<DocumentSnapshot> | undefined,
    { hearingId: string }
  >,
  _philSms?: PhilSmsHearingCfg,
  _semaphore?: SemaphoreHearingCfg,
): Promise<void> {
  const change = event.data;
  if (!change?.after.exists) return;
  const hearingDocId = event.params.hearingId;

  const d0 = (change.before.exists ? change.before.data() : {}) as HearingDoc;
  const d1 = change.after.data() as HearingDoc;
  if (isJunkHearingDoc(d1)) {
    logger.info("hearingNotify skipped junk hearing update", { hearingDocId });
    return;
  }

  if (!hearingChangedMeaningfully(d0, d1)) return;

  const db = admin.firestore();
  if (await laterDuplicateOfExistingHearing(db, hearingDocId, d1)) {
    logger.info("hearingNotify update skipped duplicate case", {
      hearingDocId,
      caseNo: asString(d1.caseNo),
    });
    await cancelPendingReminderJobs(db, hearingDocId, "duplicate_hearing");
    return;
  }

  const { resolved, uids: reminderUids } = await collectCoreHearingRecipients(db, d1);
  const caseTitle = resolved?.caseTitle || asString(d1.caseTitle) || asString(d1.caseNo) || "Hearing";

  // Hearing already lives in `hearings/{id}`. Skip extra
  // "Hearing record updated" inbox / SMS / push on document edits.
  const t0 = hearingAtFromDoc(d0)?.getTime() ?? null;
  const t1 = hearingAtFromDoc(d1)?.getTime() ?? null;
  const ht = hearingAtFromDoc(d1);
  const inactive =
    isHearingInactiveForReminders(d1 as HearingDoc & Record<string, unknown>) ||
    (await relatedCaseBlocksReminders(db, d1));

  if (inactive) {
    await cancelPendingReminderJobs(db, hearingDocId);
  } else if (t0 !== t1) {
    await cancelPendingReminderJobs(db, hearingDocId);
    await resetHearingReminderSentFlags(db, hearingDocId, ht);
    if (ht) {
      await upsertReminderJobs({
        db,
        hearingDocId,
        caseId: resolved?.caseId || hearingDocId,
        hearingAt: ht,
        recipients: reminderUids,
        snapshot: snapshotFromHearing(d1, caseTitle),
        pruneUnlistedRecipients: true,
      });
    }
  } else if (ht) {
    await cancelObsoletePendingReminderJobs(db, hearingDocId);
    await upsertReminderJobs({
      db,
      hearingDocId,
      caseId: resolved?.caseId || hearingDocId,
      hearingAt: ht,
      recipients: reminderUids,
      snapshot: snapshotFromHearing(d1, caseTitle),
      pruneUnlistedRecipients: true,
    });
  }

  const clientUids = await resolveClientUidsByHearingName(db, asString(d1.clientName));
  if (clientUids.length) {
    try {
      const parties = splitHearingPartyNames(asString(d1.clientName));
      await db.collection("hearings").doc(hearingDocId).set(
        {
          involvedClientIds: admin.firestore.FieldValue.arrayUnion(...clientUids),
          matchedClientIds: admin.firestore.FieldValue.arrayUnion(...clientUids),
          ...(parties.length
            ? { involvedPartyNames: admin.firestore.FieldValue.arrayUnion(...parties) }
            : {}),
        },
        { merge: true },
      );
    } catch (e) {
      logger.warn("hearingNotify: update involvedClientIds merge failed", {
        hearingDocId,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }
}

async function pruneStaleHearingReminderJobs(
  db: admin.firestore.Firestore,
): Promise<void> {
  const pending = await db
    .collection("hearing_reminder_jobs")
    .where("status", "==", "pending")
    .limit(400)
    .get();
  if (pending.empty) return;

  const byHearing = new Map<string, typeof pending.docs>();
  const batch = db.batch();
  let cancels = 0;
  const hearingsNeedingRebuild = new Set<string>();

  for (const doc of pending.docs) {
    const hid = asString(doc.data().hearingDocId);
    const kind = asString(doc.data().reminderKind);
    if (!hid) continue;
    const list = byHearing.get(hid) ?? [];
    list.push(doc);
    byHearing.set(hid, list);
    if (!isActiveHearingReminderKind(kind)) {
      batch.update(doc.ref, {
        status: "cancelled",
        error: "obsolete_kind",
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      cancels += 1;
      hearingsNeedingRebuild.add(hid);
    }
  }
  if (cancels) await batch.commit();

  for (const [hid, docs] of byHearing) {
    const uids = new Set(
      docs.map((d) => asString(d.data().targetUserId)).filter((id) => id.length > 0),
    );
    if (uids.size > 8) hearingsNeedingRebuild.add(hid);
  }

  let rebuilt = 0;
  for (const hid of hearingsNeedingRebuild) {
    if (rebuilt >= 10) break;
    try {
      const hearingSnap = await db.collection("hearings").doc(hid).get();
      if (!hearingSnap.exists) {
        await cancelPendingReminderJobs(db, hid);
        rebuilt += 1;
        continue;
      }
      const hd = (hearingSnap.data() || {}) as HearingDoc & Record<string, unknown>;
      const ht = hearingAtFromDoc(hd);
      if (
        !ht ||
        isHearingInactiveForReminders(hd) ||
        (await relatedCaseBlocksReminders(db, hd))
      ) {
        await cancelPendingReminderJobs(db, hid);
        rebuilt += 1;
        continue;
      }
      const { resolved, uids } = await collectCoreHearingRecipients(db, hd);
      const caseTitle =
        resolved?.caseTitle || asString(hd.caseTitle) || asString(hd.caseNo) || hid;
      await upsertReminderJobs({
        db,
        hearingDocId: hid,
        caseId: resolved?.caseId || hid,
        hearingAt: ht,
        recipients: uids,
        snapshot: snapshotFromHearing(hd, caseTitle),
        pruneUnlistedRecipients: true,
      });
      rebuilt += 1;
    } catch (e) {
      logger.warn("hearingReminder prune failed", {
        hearingDocId: hid,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }
}

export async function processDueHearingReminderJobs(
  db: admin.firestore.Firestore,
  philSms?: PhilSmsHearingCfg,
  semaphore?: SemaphoreHearingCfg,
): Promise<void> {
  await pruneStaleHearingReminderJobs(db);

  const now = admin.firestore.Timestamp.now();
  const nowMs = now.toMillis();
  const q = await db
    .collection("hearing_reminder_jobs")
    .where("status", "==", "pending")
    .where("scheduledFor", "<=", now)
    .orderBy("scheduledFor", "asc")
    .limit(200)
    .get();

  if (q.empty) return;

  const skipHearingIds = new Set<string>();
  const allowedByHearing = new Map<string, Set<string>>();

  for (const doc of q.docs) {
    const j = doc.data() as {
      caseId?: string;
      hearingDocId?: string;
      targetUserId?: string;
      reminderKind?: string;
      hearingAtMs?: number;
      scheduledFor?: admin.firestore.Timestamp;
      snapshot?: {
        senderName?: string;
        message?: string;
        caseTitle?: string;
        activityType?: string;
        caseNo?: string;
        clientName?: string;
        courtBranch?: string;
      };
    };

    const caseId = asString(j.caseId);
    const hearingDocId = asString(j.hearingDocId);
    const uid = asString(j.targetUserId);
    const kindRaw = asString(j.reminderKind);
    if (hearingDocId && skipHearingIds.has(hearingDocId)) {
      continue;
    }
    if (!caseId || !hearingDocId || !uid || !kindRaw) {
      await doc.ref.update({
        status: "failed",
        error: "missing fields",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }

    if (!isActiveHearingReminderKind(kindRaw)) {
      await doc.ref.update({
        status: "cancelled",
        error: "obsolete_kind",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }
    const kind: HearingReminderKind = kindRaw;

    const scheduled = j.scheduledFor?.toDate?.();
    if (
      scheduled &&
      nowMs - scheduled.getTime() > HEARING_REMINDER_LATE_GRACE_MS
    ) {
      await doc.ref.update({
        status: "skipped_late",
        error: "reminder window already passed",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info("hearingReminderJob skipped late", {
        docId: doc.id,
        kind,
        hearingDocId,
      });
      continue;
    }

    const snap = j.snapshot || {};
    const caseLabel = asString(snap.caseTitle) || caseId;
    const title = reminderTitle(kind, caseLabel);
    const hearingSnap = await db.collection("hearings").doc(hearingDocId).get();
    if (!hearingSnap.exists) {
      await doc.ref.update({
        status: "cancelled",
        error: "hearing_missing",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }
    const hd = (hearingSnap.data() || {}) as HearingDoc & Record<string, unknown>;

    if (await laterDuplicateOfExistingHearing(db, hearingDocId, hd)) {
      await cancelPendingReminderJobs(db, hearingDocId, "duplicate_hearing");
      logger.info("hearingReminderJob skipped duplicate hearing", {
        docId: doc.id,
        hearingDocId,
      });
      continue;
    }

    if (isHearingInactiveForReminders(hd)) {
      skipHearingIds.add(hearingDocId);
      await cancelPendingReminderJobs(db, hearingDocId);
      await doc.ref.update({
        status: "cancelled",
        error: "hearing_inactive",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }
    if (await relatedCaseBlocksReminders(db, hd)) {
      skipHearingIds.add(hearingDocId);
      await cancelPendingReminderJobs(db, hearingDocId);
      await doc.ref.update({
        status: "cancelled",
        error: "case_inactive",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }

    let allowed = allowedByHearing.get(hearingDocId);
    if (!allowed) {
      const core = await collectCoreHearingRecipients(db, hd);
      allowed = new Set(core.uids);
      allowedByHearing.set(hearingDocId, allowed);
    }
    if (!allowed.has(uid)) {
      await doc.ref.update({
        status: "cancelled",
        error: "not_a_recipient",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }

    const liveHearingAt = hearingAtFromDoc(hd);
    if (!liveHearingAt) {
      await doc.ref.update({
        status: "cancelled",
        error: "hearing_time_missing",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }
    const expected = expectedReminderAt(liveHearingAt, kind);
    const scheduledMs = scheduled?.getTime() ?? expected.getTime();
    const jobHearingAtMs =
      typeof j.hearingAtMs === "number" ? j.hearingAtMs : null;
    const liveMs = liveHearingAt.getTime();
    const staleSchedule =
      Math.abs(expected.getTime() - scheduledMs) > 60 * 1000 ||
      (jobHearingAtMs != null && Math.abs(jobHearingAtMs - liveMs) > 60 * 1000);
    if (staleSchedule) {
      await doc.ref.update({
        status: "cancelled",
        error: "stale_schedule",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info("hearingReminderJob skipped stale", {
        docId: doc.id,
        kind,
        hearingDocId,
      });
      continue;
    }

    const smsFields = hearingFieldsForSms(hd);
    const body = buildHearingSmsText({
      ...smsFields,
      reminderKind: kind,
    });

    try {
      await deliverHearingNotification({
        db,
        caseId,
        hearingDocId,
        recipients: [uid],
        title,
        body,
        notificationType: `hearing_reminder_${kind}`,
        reminderKind: kind,
        data: {
          reminderKind: kind,
          senderName: asString(snap.senderName),
          caseTitle: caseLabel,
          caseNo: asString(snap.caseNo) || smsFields.caseNo,
          clientName: smsFields.clientName,
          courtBranch: smsFields.location,
          location: smsFields.location,
          hearingDate: smsFields.hearingDate,
          hearingTime: smsFields.hearingTime,
        },
      });

      if (philSms?.apiToken.trim() || semaphore?.apiKey.trim()) {
        await sendHearingReminderPhilSms({
          db,
          hearingDocId,
          hearingData: hd,
          reminderKind: kind,
          reminderTitle: title,
          cfg: philSms ?? {
            apiToken: "",
            senderId: "PhilSMS",
            alertPhones: [],
            staffAlertPhones: [],
          },
          semaphore,
        });
      }

      await doc.ref.update({
        status: "sent",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await upsertReminderJobs({
        db,
        hearingDocId,
        caseId: caseId || hearingDocId,
        hearingAt: liveHearingAt,
        recipients: [uid],
        snapshot: snapshotFromHearing(hd, caseLabel),
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      await doc.ref.update({
        status: "failed",
        error: msg,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.warn("hearingReminderJob failed", { docId: doc.id, msg });
    }
  }
}
