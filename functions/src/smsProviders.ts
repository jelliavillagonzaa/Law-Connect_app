import twilio from "twilio";
import {
  sendViaSemaphore,
  sendViaSemaphoreOtp,
} from "./semaphoreClient";

export function normalizePhoneE164(raw: string): string | null {
  let t = String(raw || "").trim();
  if (!t) return null;
  if (t.startsWith("+") && t.length >= 10) return t;
  t = t.replace(/[\s\-()]/g, "");
  if (t.startsWith("09") && t.length === 11) {
    return "+63" + t.substring(1);
  }
  if (t.startsWith("9") && t.length === 10) {
    return "+63" + t;
  }
  if (t.startsWith("63") && t.length >= 12) {
    return "+" + t;
  }
  return null;
}

export async function sendViaTwilio(opts: {
  accountSid: string;
  authToken: string;
  from: string;
  to: string;
  body: string;
}): Promise<{ providerMessageId: string }> {
  const client = twilio(opts.accountSid, opts.authToken);
  const res = await client.messages.create({
    from: opts.from,
    to: opts.to,
    body: opts.body.trim().slice(0, 1500),
  });
  return { providerMessageId: res.sid };
}

export type SmsProviderConfig = {
  twilioAccountSid: string;
  twilioAuthToken: string;
  twilioFromNumber: string;
  semaphoreApiKey: string;
  semaphoreSenderName: string;
};

export type SmsSendOptions = {
  /** When set, uses Semaphore /api/v4/otp (recommended for signup OTP). */
  otpCode?: string;
};

async function sendViaTwilioIfConfigured(
  cfg: SmsProviderConfig,
  to: string,
  body: string,
): Promise<{
  provider: string;
  providerMessageId: string;
} | null> {
  const accountSid = cfg.twilioAccountSid.trim();
  const authToken = cfg.twilioAuthToken.trim();
  const from = cfg.twilioFromNumber.trim();
  if (!accountSid || !authToken || !from) return null;
  const r = await sendViaTwilio({ accountSid, authToken, from, to, body });
  return { provider: "twilio", providerMessageId: r.providerMessageId };
}

/**
 * Sends SMS via Semaphore when SEMAPHORE_API_KEY is set (Philippines).
 * Twilio is only used when Semaphore is not configured — never as fallback.
 */
export async function sendSmsWithConfiguredProviders(
  cfg: SmsProviderConfig,
  to: string,
  body: string,
  opts?: SmsSendOptions,
): Promise<{
  provider: string;
  providerMessageId: string;
  providerNetworkStatus?: string;
  providerRawResponse?: string;
}> {
  const semKey = cfg.semaphoreApiKey.trim();
  if (semKey) {
    const otpCode = opts?.otpCode?.trim();
    try {
      if (otpCode) {
        const r = await sendViaSemaphoreOtp({
          apiKey: semKey,
          to,
          body,
          code: otpCode,
          senderName: cfg.semaphoreSenderName,
        });
        return {
          provider: "semaphore_otp",
          providerMessageId: r.providerMessageId,
          providerNetworkStatus: r.networkStatus,
          providerRawResponse: r.rawResponse,
        };
      }
      const r = await sendViaSemaphore({
        apiKey: semKey,
        to,
        body,
        senderName: cfg.semaphoreSenderName,
      });
      return {
        provider: "semaphore",
        providerMessageId: r.providerMessageId,
        providerNetworkStatus: r.networkStatus,
        providerRawResponse: r.rawResponse,
      };
    } catch (semErr) {
      const msg = semErr instanceof Error ? semErr.message : String(semErr);
      throw new Error(
        `Semaphore SMS failed: ${msg}. Add credits at https://semaphore.co — Twilio is not used when SEMAPHORE_API_KEY is set.`,
      );
    }
  }

  const twilio = await sendViaTwilioIfConfigured(cfg, to, body);
  if (twilio) return twilio;

  throw new Error(
    "No SMS provider configured. Set SEMAPHORE_API_KEY (recommended for PH) in functions/.env.jurislink-app and deploy onSmsRequestSend.",
  );
}
