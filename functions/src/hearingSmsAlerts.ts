import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { sendPhilSms, normalizePhilSmsRecipient } from "./philsmsClient";
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

const SMS_BRAND = "JurisLink Hearing";

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
  "updatedAt",
  "createdAt",
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
    if (key === "updatedAt" || key === "createdAt" || key === "hearingDateTime") {
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

function hearingLocation(data: HearingDoc & Record<string, unknown>): string {
  const row = hearingRow(data);
  return asString(row.location) || asString(row.courtBranch) || "";
}

function hearingFieldsForSms(data: HearingDoc & Record<string, unknown>): {
  caseNo: string;
  caseTitle: string;
  clientName: string;
  hearingDate: string;
  hearingTime: string;
  location: string;
} {
  const row = hearingRow(data);
  return {
    caseNo: asString(row.caseNo),
    caseTitle: asString(row.caseTitle),
    clientName: asString(row.clientName),
    hearingDate: asString(row.hearingDate),
    hearingTime: asString(row.hearingTime),
    location: hearingLocation(data),
  };
}

/** Firestore fields only — no generated title/summary. */
export function buildHearingSmsText(params: {
  roleLabel?: string;
  caseNo?: string;
  caseTitle?: string;
  clientName?: string;
  hearingDate?: string;
  hearingTime?: string;
  location?: string;
  /** e.g. "Reminder: Hearing tomorrow" (day-before SMS). */
  reminderNote?: string;
}): string {
  const parts: string[] = [SMS_BRAND];
  const note = params.reminderNote?.trim();
  if (note) parts.push(note);
  const role = params.roleLabel?.trim();
  if (role) parts.push(`Role: ${role}`);
  const caseNo = params.caseNo?.trim() ?? "";
  const caseTitle = params.caseTitle?.trim() ?? "";
  if (caseNo) parts.push(caseNo);
  if (caseTitle) parts.push(caseTitle);
  const clientName = params.clientName?.trim() ?? "";
  if (clientName) parts.push(`Client: ${clientName}`);
  const loc = params.location?.trim() ?? "";
  if (loc) {
    parts.push(loc.length > 90 ? `Location: ${loc.slice(0, 87)}...` : `Location: ${loc}`);
  }
  const date = params.hearingDate?.trim() ?? "";
  const time = params.hearingTime?.trim() ?? "";
  if (date) parts.push(`Date: ${date}`);
  if (time) parts.push(`Time: ${time}`);
  let text = parts.join(" - ");
  if (text.length > 480) text = `${text.slice(0, 477)}...`;
  return text;
}

function hearingScheduleFields(
  data: HearingDoc & Record<string, unknown>,
): { hearingDate: string; hearingTime: string } {
  const row = hearingRow(data);
  return {
    hearingDate: asString(row.hearingDate),
    hearingTime: asString(row.hearingTime),
  };
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
  cfg: PhilSmsHearingCfg,
): Promise<string | null> {
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) return null;
    const data = snap.data() ?? {};
    const role = asString(data.role).toLowerCase();
    const profilePhone = asString(data.phoneNumber || data.phone);

    if (role === "client") {
      return profilePhone || null;
    }
    if (role === "attorney" || role === "staff" || role.includes("paralegal")) {
      const firmDefault =
        role === "attorney"
          ? cfg.alertPhones[0] || cfg.staffAlertPhones[0]
          : cfg.staffAlertPhones[0] || cfg.alertPhones[0];
      return profilePhone || firmDefault || null;
    }
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
 * Server-side PhilSMS when `hearings` is written (n8n / court ingest / app).
 * PhilSMS only — no Semaphore.
 */
export async function sendHearingSmsAlerts(params: {
  db: admin.firestore.Firestore;
  hearingDocId: string;
  hearingData: HearingDoc & Record<string, unknown>;
  recipientUserIds: string[];
  title: string;
  body: string;
  cfg: PhilSmsHearingCfg;
}): Promise<void> {
  const { db, hearingDocId, hearingData, recipientUserIds, title, body, cfg } =
    params;

  if (!cfg.apiToken.trim()) {
    logger.info("hearingSms: skipped (PHILSMS_API_TOKEN not configured)");
    return;
  }
  if (!isSmsEligibleHearing(hearingData)) {
    logger.info("hearingSms: skipped (hearing not SMS-eligible)", { hearingDocId });
    return;
  }

  const digest = hearingSmsDigest(hearingDocId, hearingData);
  const hearingRef = db.collection("hearings").doc(hearingDocId);

  const existing = await hearingRef.get();
  const lastDigest = asString(existing.data()?.philsmsLastDigest);
  if (lastDigest && lastDigest === digest) {
    logger.info("hearingSms: skipped (already sent for this digest)", { hearingDocId });
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

    const smsText = buildHearingSmsText({ ...smsBase, roleLabel });
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
  };

  for (const phone of cfg.alertPhones) {
    await trySend(phone, "firm_alert", "Attorney");
  }

  const hearingClientName = asString(hearingRow(hearingData).clientName);
  const exactClientUids = await resolveClientUidsByExactHearingName(
    db,
    hearingClientName,
  );
  for (const uid of exactClientUids) {
    const phone = await resolvePhoneForUser(db, uid, cfg);
    if (phone) {
      await trySend(phone, `client_exact_${uid}`, "Client");
    } else {
      logger.warn("hearingSms: matched client has no phone", {
        hearingDocId,
        uid,
        clientName: hearingClientName,
      });
    }
  }
  if (hearingClientName && !exactClientUids.length) {
    logger.info("hearingSms: no client with exact sign-up name match", {
      hearingDocId,
      clientName: hearingClientName,
    });
  }

  if (!cfg.firmPhonesOnly) {
    const clientSet = new Set(exactClientUids);
    for (const uid of recipientUserIds) {
      if (clientSet.has(uid)) continue;
      const phone = await resolvePhoneForUser(db, uid, cfg);
      if (!phone) continue;
      const roleLabel = await resolveRoleLabelForUser(db, uid);
      await trySend(phone, `uid_${uid}`, roleLabel);
    }
  }

  if (anyOk) {
    await hearingRef.set(
      {
        philsmsLastDigest: digest,
        philsmsLastSentAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    logger.info("hearingSms: delivered", {
      hearingDocId,
      phoneCount: phonesSent.size,
    });
  } else if (phonesSent.size > 0) {
    logger.warn("hearingSms: no SMS delivered (check PhilSMS credits / cloud API access)", {
      hearingDocId,
    });
  } else {
    logger.warn("hearingSms: no valid phones", { hearingDocId });
  }
}

/** Pre-hearing reminder SMS (tomorrow / 5d / 3d / etc.) — firm alert phones. */
export async function sendHearingReminderPhilSms(params: {
  db: admin.firestore.Firestore;
  hearingDocId: string;
  hearingData: HearingDoc & Record<string, unknown>;
  reminderKind: string;
  reminderTitle: string;
  cfg: PhilSmsHearingCfg;
}): Promise<void> {
  const { db, hearingDocId, hearingData, reminderKind, cfg } = params;
  if (!cfg.apiToken.trim()) return;

  /** PhilSMS: day before (d1) + morning of hearing day (day_noon) — separate SMS each. */
  const reminderNote =
    reminderKind === "d1"
      ? "Reminder: Hearing tomorrow"
      : reminderKind === "day_noon"
        ? "Reminder: Hearing today"
        : "";
  if (!reminderNote) return;

  const hearingRef = db.collection("hearings").doc(hearingDocId);
  const existing = await hearingRef.get();
  const sentMap =
    (existing.data()?.philsmsRemindersSent as Record<string, boolean> | undefined) ??
    {};
  if (sentMap[reminderKind]) {
    logger.info("hearingSms: reminder already sent", { hearingDocId, reminderKind });
    return;
  }

  const smsBase = {
    ...hearingFieldsForSms(hearingData),
    reminderNote,
  };

  const philCfg = { apiToken: cfg.apiToken, senderId: cfg.senderId };
  let anyOk = false;

  const tryReminderSend = async (
    phone: string,
    logLabel: string,
    roleLabel: string,
  ): Promise<void> => {
    const normalized = normalizePhilSmsRecipient(phone);
    if (normalized.length < 11) return;
    const smsText = buildHearingSmsText({ ...smsBase, roleLabel });
    const result = await sendPhilSms(philCfg, phone, smsText);
    if (result.ok) {
      anyOk = true;
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
  };

  for (const { phone, roleLabel } of firmSmsTargets(cfg)) {
    await tryReminderSend(phone, "firm_alert", roleLabel);
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

  if (anyOk) {
    await hearingRef.set(
      {
        philsmsRemindersSent: { ...sentMap, [reminderKind]: true },
      },
      { merge: true },
    );
  }
}
