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

function hearingLocation(data: HearingDoc & Record<string, unknown>): string {
  const row = hearingRow(data);
  return asString(row.location) || asString(row.courtBranch) || "";
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
  return {
    caseNo: asString(row.caseNo),
    caseTitle: asString(row.caseTitle),
    clientName: asString(row.clientName),
    hearingDate: asString(row.hearingDate),
    hearingTime: asString(row.hearingTime),
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
  lines.push(
    ...hearingSmsCaptionLines(params.caseTitle ?? "", params.clientName ?? ""),
  );

  if (copy) {
    lines.push("");
  } else {
    lines.push("", "Hearing Details:");
  }

  const date = (params.hearingDate ?? "").trim();
  if (date) lines.push(`Date: ${date}`);
  const time = formatHearingSmsTime(params.hearingTime ?? "");
  if (time) lines.push(`Time: ${time}`);
  const loc = formatHearingSmsLocation(params.location ?? "");
  if (loc) lines.push(`Location: ${loc}`);

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
    const profilePhone = asString(data.phoneNumber || data.phone);
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

  const clientSet = new Set(exactClientUids);
  for (const uid of recipientUserIds) {
    if (clientSet.has(uid)) continue;
    const roleLabel = await resolveRoleLabelForUser(db, uid);
    const isFirm =
      roleLabel === "Attorney" ||
      roleLabel === "Staff" ||
      roleLabel === "Admin";
    // firmPhonesOnly skips extra clients. Attorney and staff still get the
    // same SMS as the push, using the phone on their user profile.
    if (cfg.firmPhonesOnly && !isFirm) continue;
    const phone = await resolvePhoneForUser(db, uid, cfg);
    if (!phone) {
      logger.warn("hearingSms: push recipient has no phone", {
        hearingDocId,
        uid,
        role: roleLabel,
      });
      continue;
    }
    await trySend(phone, `uid_${uid}`, roleLabel);
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
  if (sentMap[reminderKind] || (flag && existingData[flag] === true)) {
    logger.info("hearingSms: reminder already sent", { hearingDocId, reminderKind });
    return;
  }

  const smsBase = {
    ...hearingFieldsForSms(hearingData),
    reminderKind,
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
    const smsText = buildHearingSmsText(smsBase);
    if (cfg.apiToken.trim()) {
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
  };

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

  if (anyOk) {
    const patch: Record<string, unknown> = {
      philsmsRemindersSent: { ...sentMap, [reminderKind]: true },
    };
    if (flag) patch[flag] = true;
    await hearingRef.set(patch, { merge: true });
  }
}
