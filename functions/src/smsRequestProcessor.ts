import * as admin from "firebase-admin";
import type { QueryDocumentSnapshot } from "firebase-admin/firestore";
import type { FirestoreEvent } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import {
  normalizePhoneE164,
  sendSmsWithConfiguredProviders,
  type SmsProviderConfig,
} from "./smsProviders";

/**
 * App queues rows in `sms_requests` with status pending.
 * Sends via Semaphore (PH) or Twilio and marks the doc sent (or failed).
 */
export async function handleSmsRequestCreated(
  event: FirestoreEvent<
    QueryDocumentSnapshot | undefined,
    { docId: string }
  >,
  cfg: SmsProviderConfig,
): Promise<void> {
  const snap = event.data;
  if (!snap?.exists) return;

  const ref = snap.ref;
  const d = snap.data() as Record<string, unknown>;
  const status = String(d.status || "");
  if (status && status !== "pending") return;

  const toRaw = typeof d.to === "string" ? d.to : "";
  const body = String(d.body || "");
  const meta =
    d.meta && typeof d.meta === "object"
      ? (d.meta as Record<string, unknown>)
      : {};
  const otpCode =
    meta.type === "otp" && typeof meta.code === "string"
      ? meta.code.trim()
      : undefined;
  const to = normalizePhoneE164(toRaw);

  if (!to) {
    await ref.update({
      status: "failed",
      error: "Invalid phone number; must be E.164 format (e.g. +639XXXXXXXXX).",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.warn("smsRequest: invalid phone", {
      docId: event.params.docId,
      toRaw,
    });
    return;
  }

  if (!body.trim()) {
    await ref.update({
      status: "failed",
      error: "Empty body",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.warn("smsRequest: empty body", { docId: event.params.docId });
    return;
  }

  try {
    const result = await sendSmsWithConfiguredProviders(cfg, to, body, {
      otpCode,
    });
    await ref.update({
      status: "sent",
      provider: result.provider,
      providerMessageId: result.providerMessageId,
      ...(result.providerNetworkStatus
        ? {providerNetworkStatus: result.providerNetworkStatus}
        : {}),
      ...(result.providerRawResponse
        ? {providerRawResponse: result.providerRawResponse}
        : {}),
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info("smsRequest: sent", {
      docId: event.params.docId,
      provider: result.provider,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await ref.update({
      status: "failed",
      error: msg,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.warn("smsRequest: send failed", {
      docId: event.params.docId,
      msg,
    });
  }
}
