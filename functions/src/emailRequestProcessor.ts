import * as admin from "firebase-admin";
import type { QueryDocumentSnapshot } from "firebase-admin/firestore";
import type { FirestoreEvent } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as nodemailer from "nodemailer";

/**
 * Optional SMTP (set deploy params or env): SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM.
 * If SMTP_HOST is empty, requests are marked skipped_config.
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
): Promise<void> {
  const snap = event.data;
  if (!snap?.exists) return;

  const ref = snap.ref;
  const d = snap.data() as Record<string, unknown>;
  const status = String(d.status || "");
  if (status && status !== "pending") return;

  const to = String(d.to || "").trim();
  const subject = String(d.subject || "Law Connect").trim();
  const text = String(d.text || "").trim();

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
