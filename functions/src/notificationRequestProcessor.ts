import * as admin from "firebase-admin";
import type { QueryDocumentSnapshot } from "firebase-admin/firestore";
import type { FirestoreEvent } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

function fcmTokensFromUserDoc(
  data: Record<string, unknown> | undefined,
): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const add = (raw: unknown) => {
    if (typeof raw !== "string" || raw.length <= 20 || seen.has(raw)) return;
    seen.add(raw);
    out.push(raw);
  };
  if (!data) return out;
  const map = data.fcmTokens;
  let web = "";
  if (map && typeof map === "object") {
    const record = map as Record<string, unknown>;
    if (typeof record.web === "string") web = record.web;
    for (const [key, value] of Object.entries(record)) {
      if (key === "web") continue;
      add(value);
    }
  }
  if (typeof data.fcmToken === "string" && data.fcmToken !== web) {
    add(data.fcmToken);
  }
  return out.filter((token) => token !== web);
}

async function isWebsiteToken(
  db: admin.firestore.Firestore,
  token: string,
): Promise<boolean> {
  const hit = await db
    .collection("users")
    .where("fcmTokens.web", "==", token)
    .limit(1)
    .get();
  return !hit.empty;
}

/** Chat and court hearings must show on the website. Other types stay quiet. */
function webPushForType(
  type: string | undefined,
  title: string,
  body: string,
): { notification: { title?: string; body?: string; silent: boolean }; fcmOptions?: { link: string } } {
  const visible = type === "new_message" || (type ?? "").startsWith("hearing");
  if (!visible) {
    return { notification: { silent: true } };
  }
  return {
    notification: { title, body, silent: false },
    ...(type === "new_message" ? { fcmOptions: { link: "/" } } : {}),
  };
}

/** Same notary or hearing event replaces a second card on one phone. */
function androidTrayTag(data: Record<string, string>): string | undefined {
  const type = data.type || "";
  const requestId = data.requestId || "";
  if (type.startsWith("notary") && requestId) {
    return `${type}:${requestId}`.slice(0, 64);
  }
  const hearingId = data.hearingDocId || "";
  if (type.includes("hearing") && hearingId) {
    return hearingId.slice(0, 64);
  }
  return undefined;
}

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
    const found = fcmTokensFromUserDoc(u.data() as Record<string, unknown> | undefined);
    if (found.length) token = found[0];
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

  if (await isWebsiteToken(db, token)) {
    await ref.update({
      status: "skipped",
      error: "Website push is off",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  const data = stringifyData(
    d.data as Record<string, unknown> | undefined,
  );

  // Hearing FCM is owned by hearingNotifications. Skip a second card when
  // that handler already delivered (or is mid-send after Flutter raced).
  const hearingId = (data.hearingDocId || "").trim();
  const typeLower = (data.type || "").toLowerCase();
  if (hearingId && typeLower.includes("hearing")) {
    try {
      const hearingSnap = await db.collection("hearings").doc(hearingId).get();
      const hd = hearingSnap.data() ?? {};
      if (
        hd.fcmDeliveredAt != null ||
        hd.fcmMobileDeliveredAt != null
      ) {
        await ref.update({
          status: "skipped",
          error: "Hearing push already delivered",
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }
    } catch (e) {
      logger.warn("notificationRequest: hearing dedupe check failed", {
        hearingId,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  const notaryTag = androidTrayTag(data);

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data,
      android: {
        priority: "high" as const,
        ...(notaryTag ? {collapseKey: notaryTag} : {}),
        notification: {
          sound: "default",
          channelId: "high_importance_channel",
          defaultSound: true,
          ...(notaryTag ? {tag: notaryTag} : {}),
        },
      },
      apns: {
        payload: {
          aps: { sound: "default", badge: 1 },
        },
      },
      webpush: webPushForType(data.type, title, body),
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
