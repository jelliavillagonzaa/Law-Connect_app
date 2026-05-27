import * as admin from "firebase-admin";
import type { DocumentSnapshot, QueryDocumentSnapshot } from "firebase-admin/firestore";
import type { Change, FirestoreEvent } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import {
  sendHearingSmsAlerts,
  sendHearingReminderPhilSms,
  type PhilSmsHearingCfg,
} from "./hearingSmsAlerts";

export type HearingReminderKind = "d5" | "d3" | "d1" | "day_noon" | "h10" | "m5";

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

export function isImportedCourtRow(d: HearingDoc): boolean {
  return asString(d.caseNo).length > 0 && asString(d.fullText).length > 0;
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

/** 9:00 AM Philippines (UTC+8, no DST) on the calendar day of [hearingAt] in that offset. */
function sameDayMorningPhilippines(hearingAt: Date): Date {
  const offsetMs = 8 * 60 * 60 * 1000;
  const wall = hearingAt.getTime() + offsetMs;
  const w = new Date(wall);
  const y = w.getUTCFullYear();
  const mo = w.getUTCMonth();
  const da = w.getUTCDate();
  // 09:00 in UTC+8 == 01:00 UTC
  return new Date(Date.UTC(y, mo, da, 1, 0, 0));
}

/** 9:00 AM Philippines on the calendar day before the hearing date. */
function dayBeforeMorningPhilippines(hearingAt: Date): Date {
  const offsetMs = 8 * 60 * 60 * 1000;
  const wall = hearingAt.getTime() + offsetMs;
  const w = new Date(wall);
  const y = w.getUTCFullYear();
  const mo = w.getUTCMonth();
  const da = w.getUTCDate();
  return new Date(Date.UTC(y, mo, da - 1, 1, 0, 0));
}

function reminderSchedule(hearingAt: Date, now: Date): Array<{ kind: HearingReminderKind; at: Date }> {
  const h = hearingAt.getTime();
  const nowMs = now.getTime();
  const out: Array<{ kind: HearingReminderKind; at: Date }> = [];

  const d5 = new Date(h - 5 * 24 * 60 * 60 * 1000);
  const d3 = new Date(h - 3 * 24 * 60 * 60 * 1000);
  const d1 = dayBeforeMorningPhilippines(hearingAt);
  const dayMorning = sameDayMorningPhilippines(hearingAt);
  const h10 = new Date(h - 10 * 60 * 60 * 1000);
  const m5 = new Date(h - 5 * 60 * 1000);

  const pairs: Array<{ kind: HearingReminderKind; at: Date }> = [
    { kind: "d5", at: d5 },
    { kind: "d3", at: d3 },
    { kind: "d1", at: d1 },
    { kind: "day_noon", at: dayMorning },
    { kind: "h10", at: h10 },
    { kind: "m5", at: m5 },
  ];

  for (const p of pairs) {
    const tt = p.at.getTime();
    if (tt > nowMs && tt < h) out.push(p);
  }
  return out;
}

function reminderTitle(kind: HearingReminderKind, caseLabel: string): string {
  switch (kind) {
    case "d5":
      return `Hearing in 5 days — ${caseLabel}`;
    case "d3":
      return `Hearing in 3 days — ${caseLabel}`;
    case "d1":
      return `Hearing tomorrow — ${caseLabel}`;
    case "day_noon":
      return `Hearing today (morning reminder) — ${caseLabel}`;
    case "h10":
      return `Hearing in 10 hours — ${caseLabel}`;
    case "m5":
      return `Hearing in 5 minutes — ${caseLabel}`;
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

/**
 * SMS / exact client match: `fullName`/`name` OR `firstName`+`lastName` (middleName ignored).
 */
export function clientSignUpMatchesHearingName(
  data: Record<string, unknown>,
  hearingClientName: string,
): boolean {
  const cn = hearingClientName.trim();
  if (!cn) return false;

  for (const field of ["fullName", "name", "displayName"] as const) {
    const stored = asString(data[field]);
    if (stored && clientNameExactMatch(stored, cn)) return true;
  }

  const hearingParts = parseFirstLastFromHearingName(cn);
  if (!hearingParts) return false;

  const signUpFirst = normNamePart(asString(data.firstName));
  const signUpLast = normNamePart(asString(data.lastName));
  if (!signUpFirst || !signUpLast) return false;

  return (
    signUpFirst === normNamePart(hearingParts.first) &&
    signUpLast === normNamePart(hearingParts.last)
  );
}

/** Same logic as Flutter `_namesPartialMatchForClient` (e.g. profile "Joren L. Limpahan" vs hearing "Joren Limpahan"). */
function namesPartialMatchForClient(stored: string, hearingClientName: string): boolean {
  if (namesMatchForClient(stored, hearingClientName)) return true;
  const words = hearingClientName
    .toLowerCase()
    .split(/\s+/)
    .filter((w) => w.length >= 3);
  if (words.length < 2) return false;
  const storedLower = stored.toLowerCase();
  return words.every((w) => storedLower.includes(w));
}

export function clientInboxTitleFromHearing(d: HearingDoc, caseTitle: string): string {
  if (isImportedCourtRow(d)) {
    const cn = asString(d.caseNo);
    return cn ? `New notice court hearings — ${cn}` : "New notice court hearings";
  }
  return `New notice court hearings — ${caseTitle}`;
}

/** Resolve client user IDs from `hearings.clientName` (e.g. court OCR defendant name). */
export async function resolveClientUidsByHearingName(
  db: admin.firestore.Firestore,
  clientName: string,
): Promise<string[]> {
  const cn = clientName.trim();
  if (!cn) return [];

  const matched = new Set<string>();
  const nameKeys = clientNameQueryVariants(cn);
  const fields = ["fullName", "name", "displayName"] as const;

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

  if (!matched.size) {
    try {
      const cq = await db.collection("users").where("role", "==", "client").limit(200).get();
      for (const u of cq.docs) {
        const data = u.data() as Record<string, unknown>;
        for (const field of fields) {
          const stored = asString(data[field]);
          if (stored && namesPartialMatchForClient(stored, cn)) {
            matched.add(u.id);
            break;
          }
        }
      }
    } catch (e) {
      logger.warn("hearingNotify: client role scan failed", {
        err: e instanceof Error ? e.message : String(e),
      });
    }
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
  const nameKeys = clientNameQueryVariants(cn);
  const fields = ["fullName", "name", "displayName"] as const;

  const tryAdd = (data: Record<string, unknown>, uid: string): void => {
    if (asString(data.role).toLowerCase() !== "client") return;
    if (clientSignUpMatchesHearingName(data, cn)) matched.add(uid);
  };

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

  const hearingParts = parseFirstLastFromHearingName(cn);
  if (hearingParts) {
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

  if (!matched.size) {
    try {
      const cq = await db.collection("users").where("role", "==", "client").limit(300).get();
      for (const u of cq.docs) {
        tryAdd(u.data() as Record<string, unknown>, u.id);
      }
    } catch (e) {
      logger.warn("hearingSms: exact client scan failed", {
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  return [...matched];
}

/** Court import with no `cases` match — notify firm + matched client by name. */
async function addFirmRecipientsForUnmatchedImport(
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

  for (const role of ["attorney", "staff", "admin"]) {
    try {
      const q = await db.collection("users").where("role", "==", role).limit(80).get();
      for (const doc of q.docs) recipients.add(doc.id);
    } catch {
      /* ignore */
    }
  }
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

async function loadFcmTokens(
  db: admin.firestore.Firestore,
  uids: string[],
): Promise<Map<string, string>> {
  const tokenByUid = new Map<string, string>();
  await Promise.all(
    uids.map(async (uid) => {
      try {
        const u = await db.collection("users").doc(uid).get();
        const t = u.data()?.fcmToken;
        if (typeof t === "string" && t.length > 20) tokenByUid.set(uid, t);
      } catch {
        /* ignore */
      }
    }),
  );
  return tokenByUid;
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
  } = params;

  if (!recipients.length) {
    logger.warn("hearingNotify: no recipients", { caseId, hearingDocId });
    return;
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const caseTitle =
    asString(data["caseTitle"]) || asString(data["caseNo"]) || "Hearing";
  const roleByUid = new Map<string, string>();
  await Promise.all(
    recipients.map(async (uid) => {
      try {
        const u = await db.collection("users").doc(uid).get();
        roleByUid.set(uid, asString(u.data()?.role).toLowerCase());
      } catch {
        roleByUid.set(uid, "");
      }
    }),
  );

  const batch = db.batch();
  for (const uid of recipients) {
    const nid = hearingNotificationDocId({
      notificationType,
      hearingDocId,
      uid,
      reminderKind: reminderKind ?? undefined,
      updateNonce,
    });
    const nref = db.collection("notifications").doc(nid);
    const existing = await nref.get();
    const wasRead =
      existing.exists &&
      (existing.data()?.isRead === true || existing.data()?.readAt != null);

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
      hearingDocId,
      hearingReminderKind: reminderKind ?? null,
    };
    if (isClient) row.clientId = uid;
    if (wasRead) {
      row.isRead = true;
    } else if (!existing.exists) {
      row.isRead = false;
      row.createdAt = now;
    }
    batch.set(nref, row, { merge: true });
  }
  await batch.commit();

  if (inAppOnly) return;

  const tokenByUid = await loadFcmTokens(db, recipients);
  const messaging = admin.messaging();
  const seenTokens = new Set<string>();
  const dataStrings = stringifyData(data);

  for (const uid of recipients) {
    const token = tokenByUid.get(uid);
    if (!token || seenTokens.has(token)) continue;
    seenTokens.add(token);
    try {
      await messaging.send({
        token,
        notification: { title, body: body.length > 240 ? `${body.slice(0, 237)}...` : body },
        data: {
          ...dataStrings,
          type: notificationType,
          caseId,
          hearingDocId,
        },
        android: { priority: "high" as const },
        apns: {
          payload: {
            aps: { sound: "default", badge: 1 },
          },
        },
      });
    } catch (e) {
      logger.warn("hearingNotify: FCM failed", {
        uid,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  for (const uid of recipients) {
    const to = await resolveUserEmail(uid);
    if (!to) continue;
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
  }
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
}): Promise<void> {
  const { db, hearingDocId, caseId, hearingAt, recipients, snapshot } = params;
  const now = new Date();
  const rows = reminderSchedule(hearingAt, now);
  if (!rows.length) return;

  const batch = db.batch();
  for (const uid of recipients) {
    for (const { kind, at } of rows) {
      const jobId = `${hearingDocId}_${kind}_${uid}`.replace(/[/\\]/g, "_");
      const ref = db.collection("hearing_reminder_jobs").doc(jobId);
      batch.set(
        ref,
        {
          hearingDocId,
          caseId,
          targetUserId: uid,
          reminderKind: kind,
          scheduledFor: admin.firestore.Timestamp.fromDate(at),
          status: "pending",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          snapshot,
        },
        { merge: true },
      );
    }
  }
  await batch.commit();
}

export async function cancelPendingReminderJobs(
  db: admin.firestore.Firestore,
  hearingDocId: string,
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
  ];
  for (const k of keys) {
    if (asString(d0[k] as unknown) !== asString(d1[k] as unknown)) return true;
  }
  const t0 = hearingAtFromDoc(d0)?.getTime() ?? null;
  const t1 = hearingAtFromDoc(d1)?.getTime() ?? null;
  return t0 !== t1;
}

export async function handleHearingDocumentCreated(
  event: FirestoreEvent<QueryDocumentSnapshot | undefined, { hearingId: string }>,
  philSms?: PhilSmsHearingCfg,
): Promise<void> {
  const snap = event.data;
  if (!snap?.exists) return;

  const hearingDocId = event.params.hearingId;
  const d = snap.data() as HearingDoc;
  const db = admin.firestore();

  const resolved = await resolveCaseForHearing(db, d);
  const extras = extractExtraUids(d);
  const recipients = new Set<string>();

  if (resolved) {
    const { uids } = await collectCaseParticipantUids(db, resolved.caseId);
    for (const u of uids) recipients.add(u);
  }
  for (const u of extras) recipients.add(u);

  for (const uid of await resolveClientUidsByHearingName(db, asString(d.clientName))) {
    recipients.add(uid);
  }

  if (!recipients.size) {
    await addFirmRecipientsForUnmatchedImport(db, recipients, d);
  }

  if (isCourtHearingForStaffAlert(d)) {
    await addAllActiveStaff(db, recipients);
  }

  const list = [...recipients];

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

  if (philSms?.apiToken.trim()) {
    try {
      await sendHearingSmsAlerts({
        db,
        hearingDocId,
        hearingData: snap.data() as HearingDoc & Record<string, unknown>,
        recipientUserIds: list,
        title,
        body,
        cfg: philSms,
      });
    } catch (e) {
      logger.warn("hearingSms: create handler failed", {
        hearingDocId,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  if (!list.length) {
    logger.warn("hearingNotify: no recipients (case, clientName, or firm fallback)", {
      hearingDocId,
      caseNo: asString(d.caseNo),
      clientName: asString(d.clientName),
    });
    return;
  }

  await deliverHearingNotification({
    db,
    caseId,
    hearingDocId,
    recipients: list,
    title,
    body,
    notificationType: "hearing_activity",
    reminderKind: null,
    hearingDoc: d,
    data: {
      activityType: activity,
      caseNo: asString(d.caseNo),
      clientName: asString(d.clientName),
      courtBranch: asString(d.courtBranch),
      caseTitle,
      fullText: asString(d.fullText),
    },
  });

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
  if (ht) {
    await upsertReminderJobs({
      db,
      hearingDocId,
      caseId: resolved?.caseId || hearingDocId,
      hearingAt: ht,
      recipients: list,
      snapshot: snapshotFromHearing(d, caseTitle),
    });
  }
}

export async function handleHearingDocumentUpdated(
  event: FirestoreEvent<
    Change<DocumentSnapshot> | undefined,
    { hearingId: string }
  >,
  philSms?: PhilSmsHearingCfg,
): Promise<void> {
  const change = event.data;
  if (!change?.after.exists) return;
  const hearingDocId = event.params.hearingId;

  const d0 = (change.before.exists ? change.before.data() : {}) as HearingDoc;
  const d1 = change.after.data() as HearingDoc;

  if (!hearingChangedMeaningfully(d0, d1)) return;

  const db = admin.firestore();
  const resolved = await resolveCaseForHearing(db, d1);
  const extras = extractExtraUids(d1);
  const recipients = new Set<string>();
  if (resolved) {
    const { uids } = await collectCaseParticipantUids(db, resolved.caseId);
    for (const u of uids) recipients.add(u);
  }
  for (const u of extras) recipients.add(u);

  for (const uid of await resolveClientUidsByHearingName(db, asString(d1.clientName))) {
    recipients.add(uid);
  }

  if (!recipients.size) {
    await addFirmRecipientsForUnmatchedImport(db, recipients, d1);
  }

  if (isCourtHearingForStaffAlert(d1)) {
    await addAllActiveStaff(db, recipients);
  }

  const list = [...recipients];

  const caseTitle = resolved?.caseTitle || asString(d1.caseTitle) || asString(d1.caseNo) || "Hearing";
  const caseId = resolved?.caseId || "";

  const title = `Hearing record updated — ${caseTitle}`;
  const body = buildNotificationBody(d1, {
    caseId: caseId || hearingDocId,
    caseTitle,
  });

  if (philSms?.apiToken.trim()) {
    try {
      await sendHearingSmsAlerts({
        db,
        hearingDocId,
        hearingData: change.after.data() as HearingDoc & Record<string, unknown>,
        recipientUserIds: list,
        title,
        body,
        cfg: philSms,
      });
    } catch (e) {
      logger.warn("hearingSms: update handler failed", {
        hearingDocId,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  if (!list.length) return;

  await deliverHearingNotification({
    db,
    caseId,
    hearingDocId,
    recipients: list,
    title,
    body,
    notificationType: "hearing_activity_update",
    reminderKind: null,
    updateNonce: String(change.after.updateTime?.toMillis?.() ?? Date.now()),
    data: {
      activityType: asString(d1.activityType) || "update",
      caseNo: asString(d1.caseNo),
      clientName: asString(d1.clientName),
      courtBranch: asString(d1.courtBranch),
      caseTitle,
    },
  });

  const t0 = hearingAtFromDoc(d0)?.getTime() ?? null;
  const t1 = hearingAtFromDoc(d1)?.getTime() ?? null;
  const ht = hearingAtFromDoc(d1);

  if (t0 !== t1) {
    await cancelPendingReminderJobs(db, hearingDocId);
    if (ht) {
      await upsertReminderJobs({
        db,
        hearingDocId,
        caseId: resolved?.caseId || hearingDocId,
        hearingAt: ht,
        recipients: list,
        snapshot: snapshotFromHearing(d1, caseTitle),
      });
    }
  }
}

export async function processDueHearingReminderJobs(
  db: admin.firestore.Firestore,
  philSms?: PhilSmsHearingCfg,
): Promise<void> {
  const now = admin.firestore.Timestamp.now();
  const q = await db
    .collection("hearing_reminder_jobs")
    .where("status", "==", "pending")
    .where("scheduledFor", "<=", now)
    .orderBy("scheduledFor", "asc")
    .limit(200)
    .get();

  if (q.empty) return;

  for (const doc of q.docs) {
    const j = doc.data() as {
      caseId?: string;
      hearingDocId?: string;
      targetUserId?: string;
      reminderKind?: HearingReminderKind;
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
    const kind = j.reminderKind;
    if (!caseId || !hearingDocId || !uid || !kind) {
      await doc.ref.update({
        status: "failed",
        error: "missing fields",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      continue;
    }

    const snap = j.snapshot || {};
    const caseLabel = asString(snap.caseTitle) || caseId;
    const title = reminderTitle(kind, caseLabel);
    const hearingSnap = await db.collection("hearings").doc(hearingDocId).get();
    const hd = (hearingSnap.data() || {}) as HearingDoc;
    const body = buildNotificationBody(hd, { caseId, caseTitle: caseLabel });

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
          caseNo: asString(snap.caseNo),
        },
      });

      if (philSms?.apiToken.trim()) {
        await sendHearingReminderPhilSms({
          db,
          hearingDocId,
          hearingData: hd as HearingDoc & Record<string, unknown>,
          reminderKind: kind,
          reminderTitle: title,
          cfg: philSms,
        });
      }

      await doc.ref.update({
        status: "sent",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
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
