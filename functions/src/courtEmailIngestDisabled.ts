/**
 * IMAP mailbox poll stays off. n8n writes `hearings` directly (2 PM process).
 * These stubs only block leftover "New court notice" queue spam — they do not
 * delete Firestore rows.
 */
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { isOutOfSystemPumpedNotice } from "./outOfSystemNotice";

const DISABLED_MSG =
  "Court email / IMAP ingest is disabled for Law Connect.";

/** Idle — do not poll Gmail and do not purge queue/hearings. */
export const imapCourtEmailIngest = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "UTC",
    region: "us-central1",
    memory: "128MiB",
    timeoutSeconds: 30,
  },
  async () => {
    logger.info("imapCourtEmailIngest: idle (n8n writes hearings)");
  },
);

export const imapCourtEmailManual = onRequest(
  { region: "us-central1", memory: "128MiB" },
  (_req, res) => {
    res.status(410).json({ ok: false, error: DISABLED_MSG });
  },
);

/**
 * Renamed from processCourtEmailQueue — that name was still a callable in
 * production, and Firebase blocks callable → scheduled in place. Idle stub only.
 */
export const processCourtEmailQueueIdle = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "UTC",
    region: "us-central1",
    memory: "128MiB",
  },
  async () => {
    logger.info("processCourtEmailQueueIdle: idle (hearings written by n8n)");
  },
);

/** Do not turn queue rows into "New court notice" FCM. */
export const onCourtEmailQueueNotify = onDocumentCreated(
  {
    document: "court_email_queue/{docId}",
    region: "us-central1",
    memory: "128MiB",
  },
  async () => {
    logger.info("onCourtEmailQueueNotify: disabled (no notifications sent)");
  },
);

function isCourtEmailIngestNotification(
  data: Record<string, unknown>,
): boolean {
  if (isOutOfSystemPumpedNotice(data)) return true;

  const type = String(data.type ?? "").toLowerCase();
  if (type === "hearing_activity" || type === "hearing_activity_update") {
    return false;
  }
  if (type === "court_email_ingest") return true;
  if (type.startsWith("court_") && !type.includes("hearing")) return true;

  const queueDocId = String(data.queueDocId ?? data.queuedDocId ?? "");
  if (queueDocId.toLowerCase().includes("imap")) return true;

  return false;
}

export const onCourtEmailNotificationSuppress = onDocumentCreated(
  {
    document: "notifications/{docId}",
    region: "us-central1",
    memory: "128MiB",
  },
  async (event) => {
    const data = event.data?.data() as Record<string, unknown> | undefined;
    if (!data || !isCourtEmailIngestNotification(data)) return;
    await event.data!.ref.delete();
    logger.info("onCourtEmailNotificationSuppress: deleted", {
      id: event.params.docId,
    });
  },
);
