import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import {
  normalizePhoneE164,
  sendSmsWithConfiguredProviders,
} from "./smsProviders";

/**
 * Callable from Flutter (web-safe). Server talks to Semaphore — no browser CORS.
 * PhilSMS is not used here.
 */
export async function handleSendSemaphoreSms(
  request: CallableRequest,
  cfg: { apiKey: string; senderName: string },
): Promise<{
  ok: boolean;
  provider: string;
  providerMessageId: string;
}> {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Login required to send SMS.");
  }
  const apiKey = cfg.apiKey.trim();
  if (!apiKey) {
    throw new HttpsError(
      "failed-precondition",
      "SEMAPHORE_API_KEY is not set on sendSemaphoreSms.",
    );
  }

  const data = (request.data ?? {}) as Record<string, unknown>;
  const to = normalizePhoneE164(String(data.to ?? ""));
  const body = String(data.body ?? "").trim();
  const otpCode = String(data.otpCode ?? "").trim();

  if (!to) {
    throw new HttpsError(
      "invalid-argument",
      "Phone must be a valid PH number (09XXXXXXXXX or +63…).",
    );
  }
  if (!body) {
    throw new HttpsError("invalid-argument", "Message body is required.");
  }

  try {
    const result = await sendSmsWithConfiguredProviders(
      {
        twilioAccountSid: "",
        twilioAuthToken: "",
        twilioFromNumber: "",
        semaphoreApiKey: apiKey,
        semaphoreSenderName: cfg.senderName.trim() || "LAWCONNECT",
      },
      to,
      body,
      otpCode ? { otpCode } : undefined,
    );
    return {
      ok: true,
      provider: result.provider,
      providerMessageId: result.providerMessageId,
    };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    throw new HttpsError("internal", msg.slice(0, 400));
  }
}
