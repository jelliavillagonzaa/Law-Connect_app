import * as admin from "firebase-admin";
import type { QueryDocumentSnapshot } from "firebase-admin/firestore";
import type { FirestoreEvent } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

function stringifyData(
  raw: Record<string, unknown> | undefined,
): Record<string, string> {
  if (!raw || typeof raw !== "object") return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (v === undefined || v === null) continue;
    out[k] = typeof v === "string" ? v : JSON.stringify(v);
  }
  return out;
}

/**
 * Flutter queues rows in `notification_requests` with status pending.
 * Sends FCM and marks the doc sent (or failed).
 */
export async function handleNotificationRequestCreated(
  event: FirestoreEvent<
    QueryDocumentSnapshot | undefined,
    { docId: string }
  >,
): Promise<void> {
  const snap = event.data;
  if (!snap?.exists) return;

  const ref = snap.ref;
  const d = snap.data() as Record<string, unknown>;
  const status = String(d.status || "");
  if (status && status !== "pending") return;

  const db = admin.firestore();
  let token =
    typeof d.fcmToken === "string" && d.fcmToken.length > 20
      ? d.fcmToken
      : null;

  if (!token && typeof d.userId === "string" && d.userId) {
    const u = await db.collection("users").doc(d.userId).get();
    const t = u.data()?.fcmToken;
    if (typeof t === "string" && t.length > 20) token = t;
  }

  const title = String(d.title || "Law Connect");
  const body = String(d.body || "");

  if (!token) {
    await ref.update({
      status: "failed",
      error: "No FCM token",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.warn("notificationRequest: no token", { docId: event.params.docId });
    return;
  }

  const data = stringifyData(
    d.data as Record<string, unknown> | undefined,
  );

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data,
      android: { priority: "high" as const },
    });
    await ref.update({
      status: "sent",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await ref.update({
      status: "failed",
      error: msg,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.warn("notificationRequest: send failed", {
      docId: event.params.docId,
      msg,
    });
  }
}
