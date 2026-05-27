import { logger } from "firebase-functions";

export type PhilSmsClientConfig = {
  apiToken: string;
  senderId: string;
};

/** https://dashboard.philsms.com/developers */
const API_BASE = "https://dashboard.philsms.com/api/v3";

/** PhilSMS returns HTTP 403 for some Unicode (e.g. em-dash). Keep plain ASCII. */
export function sanitizePhilSmsMessage(text: string): string {
  return text
    .replace(/\u2014/g, "-")
    .replace(/\u2013/g, "-")
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201C\u201D]/g, '"')
    .replace(/\u2026/g, "...");
}

/** 09XXXXXXXXX / +639… → digits without + (PhilSMS recipient). */
export function normalizePhilSmsRecipient(input: string): string {
  let s = String(input || "")
    .trim()
    .replace(/[\s\-()]/g, "");
  if (!s) return s;
  if (s.startsWith("+")) s = s.slice(1);
  if (s.startsWith("09") && (s.length === 10 || s.length === 11)) {
    return `63${s.slice(1)}`;
  }
  if (s.startsWith("9") && s.length === 10) return `63${s}`;
  if (s.startsWith("63")) return s;
  return s;
}

export async function sendPhilSms(
  cfg: PhilSmsClientConfig,
  to: string,
  message: string,
): Promise<{ ok: boolean; error?: string }> {
  const token = cfg.apiToken.trim();
  if (!token) {
    return { ok: false, error: "PHILSMS_API_TOKEN not set" };
  }

  const recipient = normalizePhilSmsRecipient(to);
  const body = sanitizePhilSmsMessage(message.trim());
  if (recipient.length < 11 || !body) {
    return { ok: false, error: "Invalid phone or empty message" };
  }

  const payload = {
    recipient,
    sender_id: cfg.senderId.trim() || "PhilSMS",
    type: "plain",
    message: body.length > 1000 ? body.slice(0, 1000) : body,
  };

  try {
    const res = await fetch(`${API_BASE}/sms/send`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const text = await res.text();
    if (!res.ok) {
      logger.warn("PhilSMS HTTP error", {
        status: res.status,
        body: text.slice(0, 280),
        toSuffix: recipient.slice(-4),
      });
      return { ok: false, error: `HTTP ${res.status}: ${text.slice(0, 200)}` };
    }

    if (text) {
      try {
        const decoded = JSON.parse(text) as Record<string, unknown>;
        const status = String(decoded.status || "").toLowerCase();
        if (status === "error" || status === "failed") {
          const msg = String(decoded.message || decoded.error || text);
          logger.warn("PhilSMS API error", { msg, toSuffix: recipient.slice(-4) });
          return { ok: false, error: msg };
        }
      } catch {
        /* non-JSON success */
      }
    }

    logger.info("PhilSMS sent", { toSuffix: recipient.slice(-4) });
    return { ok: true };
  } catch (e) {
    const err = e instanceof Error ? e.message : String(e);
    logger.warn("PhilSMS request failed", { err });
    return { ok: false, error: err };
  }
}
