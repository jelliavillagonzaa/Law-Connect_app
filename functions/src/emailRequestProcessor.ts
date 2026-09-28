import * as admin from "firebase-admin";
import type { QueryDocumentSnapshot } from "firebase-admin/firestore";
import type { FirestoreEvent } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as nodemailer from "nodemailer";

export type EmailJsConfig = {
  serviceId: string;
  templateId: string;
  publicKey: string;
};

/**
 * Optional SMTP (set deploy params or env): SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM.
 * If SMTP_HOST is empty, OTP requests are sent through EmailJS instead.
 */
export async function handleEmailRequestCreated(
  event: FirestoreEvent<
    QueryDocumentSnapshot | undefined,
    { docId: string }
  >,
  smtpConfig: {
    host: string;
    port: number;
    user: string;
    pass: string;
    from: string;
  },
  emailjsConfig?: EmailJsConfig,
): Promise<void> {
  const snap = event.data;
  if (!snap?.exists) return;

  const ref = snap.ref;
  const d = snap.data() as Record<string, unknown>;
  const status = String(d.status || "");
  if (status && status !== "pending") return;

  const to = String(d.to || d.email || "").trim();
  const subject = String(d.subject || "Law Connect").trim();
  const text = String(d.text || "").trim();
  const otp = extractOtp(d);
  const isOtp = String(d.type || "") === "otp" || otp.length === 6;

  if (!to || !to.includes("@")) {
    await ref.update({
      status: "failed",
      error: "Invalid to",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  const host = smtpConfig.host.trim();
  if (!host) {
    if (isOtp && emailjsConfig?.publicKey && emailjsConfig.serviceId) {
      const result = await sendViaEmailJs({
        to,
        otp,
        name: String(d.name || "User"),
        config: emailjsConfig,
      });
      if (result.ok) {
        await ref.update({
          status: "sent",
          provider: "emailjs",
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        logger.info("emailRequest: sent via EmailJS", { docId: event.params.docId });
        return;
      }
      await ref.update({
        status: "failed",
        error: result.body || `EmailJS ${result.status}`,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.warn("emailRequest: EmailJS failed", {
        docId: event.params.docId,
        status: result.status,
        body: result.body,
      });
      return;
    }
    await ref.update({
      status: "skipped_config",
      error: "SMTP_HOST not configured",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info("emailRequest: skipped (no SMTP_HOST)", { docId: event.params.docId });
    return;
  }

  try {
    const transporter = nodemailer.createTransport({
      host,
      port: smtpConfig.port || 587,
      secure: smtpConfig.port === 465,
      auth:
        smtpConfig.user && smtpConfig.pass
          ? { user: smtpConfig.user, pass: smtpConfig.pass }
          : undefined,
    });

    await transporter.sendMail({
      from: smtpConfig.from || smtpConfig.user || "noreply@lawconnect.local",
      to,
      subject,
      text,
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
    logger.warn("emailRequest: send failed", { docId: event.params.docId, msg });
  }
}

function extractOtp(d: Record<string, unknown>): string {
  const direct = String(d.otp || d.passcode || d.code || "").trim();
  if (/^\d{6}$/.test(direct)) return direct;
  const text = String(d.text || "");
  const match = text.match(/\b(\d{6})\b/);
  return match ? match[1] : "";
}

async function sendViaEmailJs(opts: {
  to: string;
  otp: string;
  name: string;
  config: EmailJsConfig;
}): Promise<{ ok: boolean; status: number; body: string }> {
  const expires = new Date(Date.now() + 15 * 60 * 1000);
  const time = expires.toLocaleString("en-US", { timeZone: "Asia/Manila" });
  const payload = {
    lib_version: "4.0.0",
    service_id: opts.config.serviceId,
    template_id: opts.config.templateId,
    user_id: opts.config.publicKey,
    template_params: {
      email: opts.to,
      to_email: opts.to,
      user_email: opts.to,
      passcode: opts.otp,
      otp: opts.otp,
      code: opts.otp,
      to_name: opts.name,
      name: opts.name,
      time,
      logo_url: "https://jurislink-app.web.app/email-logo.png",
    },
  };

  const res = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      origin: "http://localhost",
    },
    body: JSON.stringify(payload),
  });
  const body = await res.text();
  return { ok: res.ok, status: res.status, body };
}
