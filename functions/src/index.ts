/**
 * Law Connect — hearing notifications, SMS, email queue, client sync, and
 * online payments (Xendit).
 */
import { setGlobalOptions } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, onRequest } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { handleNotificationRequestCreated } from "./notificationRequestProcessor";
import { handleEmailRequestCreated } from "./emailRequestProcessor";
import {
  handleHearingDocumentCreated,
  handleHearingDocumentUpdated,
  processDueHearingReminderJobs,
} from "./hearingNotifications";
import { handleSmsRequestCreated } from "./smsRequestProcessor";
import { handleSendSemaphoreSms } from "./sendSemaphoreSms";
import { syncClientHearingInbox } from "./clientHearingSync";
import {
  handlePaymentCheckoutRequest,
  handleXenditWebhook,
  XenditConfig,
} from "./xendit";
import { courtEmailIngest } from "./n8nHearingIngest";
import {
  imapCourtEmailIngest,
  imapCourtEmailManual,
  onCourtEmailNotificationSuppress,
  onCourtEmailQueueNotify,
  processCourtEmailQueue,
} from "./courtEmailIngestDisabled";

/** Optional SMTP for `email_requests` (hearing + other queued mail). */
const smtpHostParam = defineString("SMTP_HOST", { default: "" });
const smtpPortParam = defineString("SMTP_PORT", { default: "587" });
const smtpUserParam = defineString("SMTP_USER", { default: "" });
const smtpPassParam = defineString("SMTP_PASS", { default: "" });
const smtpFromParam = defineString("SMTP_FROM", { default: "" });

/** EmailJS for signup OTP when SMTP is not configured. */
const emailjsServiceIdParam = defineString("EMAILJS_SERVICE_ID", {
  default: "service_55uzrrn",
});
const emailjsTemplateIdParam = defineString("EMAILJS_TEMPLATE_ID", {
  default: "template_h3geajd",
});
const emailjsPublicKeyParam = defineString("EMAILJS_PUBLIC_KEY", {
  default: "5hqM06GrxyJLvL7fM",
});

const semaphoreApiKeyParam = defineString("SEMAPHORE_API_KEY", { default: "" });
const semaphoreSenderNameParam = defineString("SEMAPHORE_SENDER_NAME", {
  default: "LAWCONNECT",
});

/**
 * PhilSMS token is a Secret Manager secret on the live hearing functions.
 * Using defineString as well overlaps that secret and Cloud Run rejects deploy
 * with: "Secret environment variable overlaps non secret environment variable".
 */
const philsmsApiTokenParam = defineSecret("PHILSMS_API_TOKEN");
const philsmsSenderIdParam = defineString("PHILSMS_SENDER_ID", {
  default: "PhilSMS",
});
const philsmsAlertPhonesParam = defineString("PHILSMS_ALERT_PHONES", {
  default: "09351914214",
});
const philsmsStaffAlertPhonesParam = defineString("PHILSMS_STAFF_ALERT_PHONES", {
  default: "",
});
const philsmsFirmPhonesOnlyParam = defineString("PHILSMS_FIRM_PHONES_ONLY", {
  default: "true",
});

/** Xendit — optional params so `courtEmailIngest` can deploy without Secret Manager. */
const xenditSecretKeyParam = defineString("XENDIT_SECRET_KEY", { default: "" });
const xenditWebhookTokenParam = defineString("XENDIT_WEBHOOK_TOKEN", {
  default: "",
});
const xenditSuccessUrlParam = defineString("XENDIT_SUCCESS_URL", {
  default: "https://jurislink-app.web.app/payment-success.html",
});
const xenditCancelUrlParam = defineString("XENDIT_CANCEL_URL", {
  default: "https://jurislink-app.web.app/payment-cancel.html",
});

function xenditCfg(): XenditConfig {
  return {
    secretKey: xenditSecretKeyParam.value().trim(),
    webhookToken: xenditWebhookTokenParam.value().trim(),
    successUrl: xenditSuccessUrlParam.value().trim(),
    cancelUrl: xenditCancelUrlParam.value().trim(),
  };
}

function parsePhoneList(raw: string): string[] {
  return raw
    .split(",")
    .map((p) => p.trim())
    .filter(Boolean);
}

function hearingPhilSmsCfg(): {
  apiToken: string;
  senderId: string;
  alertPhones: string[];
  staffAlertPhones: string[];
  firmPhonesOnly: boolean;
} {
  const firmOnlyRaw = philsmsFirmPhonesOnlyParam.value().trim().toLowerCase();
  const alertPhones = parsePhoneList(philsmsAlertPhonesParam.value());
  const staffRaw = philsmsStaffAlertPhonesParam.value().trim();
  const staffAlertPhones = staffRaw ? parsePhoneList(staffRaw) : alertPhones;
  return {
    apiToken: philsmsApiTokenParam.value().trim(),
    senderId: philsmsSenderIdParam.value().trim() || "PhilSMS",
    alertPhones,
    staffAlertPhones,
    firmPhonesOnly: firmOnlyRaw !== "false" && firmOnlyRaw !== "0",
  };
}

function hearingSemaphoreCfg(): {
  apiKey: string;
  senderName: string;
} {
  return {
    apiKey: semaphoreApiKeyParam.value().trim(),
    senderName: semaphoreSenderNameParam.value().trim() || "LAWCONNECT",
  };
}

setGlobalOptions({ maxInstances: 10, region: "us-central1" });

if (!admin.apps.length) {
  admin.initializeApp();
}

/** Flutter `notification_requests` queue → send FCM. */
export const onNotificationRequestSend = onDocumentCreated(
  {
    document: "notification_requests/{docId}",
    region: "us-central1",
    memory: "256MiB",
  },
  handleNotificationRequestCreated,
);

/** Hearing activity doc → in-app + FCM + email queue + PhilSMS + scheduled reminders. */
export const onHearingActivityCreated = onDocumentCreated(
  {
    document: "hearings/{hearingId}",
    region: "us-central1",
    memory: "512MiB",
    secrets: [philsmsApiTokenParam],
  },
  async (event) => {
    await handleHearingDocumentCreated(
      event,
      hearingPhilSmsCfg(),
      hearingSemaphoreCfg(),
    );
  },
);

export const onHearingActivityUpdated = onDocumentUpdated(
  {
    document: "hearings/{hearingId}",
    region: "us-central1",
    memory: "512MiB",
    secrets: [philsmsApiTokenParam],
  },
  async (event) => {
    await handleHearingDocumentUpdated(
      event,
      hearingPhilSmsCfg(),
      hearingSemaphoreCfg(),
    );
  },
);

/** Queued outbound email (written by Cloud Functions; optional SMTP params). */
export const onEmailRequestSend = onDocumentCreated(
  {
    document: "email_requests/{docId}",
    region: "us-central1",
    memory: "256MiB",
  },
  async (event) => {
    await handleEmailRequestCreated(
      event,
      {
        host: smtpHostParam.value(),
        port: parseInt(smtpPortParam.value(), 10) || 587,
        user: smtpUserParam.value(),
        pass: smtpPassParam.value(),
        from: smtpFromParam.value(),
      },
      {
        serviceId: emailjsServiceIdParam.value().trim(),
        templateId: emailjsTemplateIdParam.value().trim(),
        publicKey: emailjsPublicKeyParam.value().trim(),
      },
    );
  },
);

/** Sends due rows in `hearing_reminder_jobs` (5d / 2d / hearing day) + prunes obsolete d1 copies. */
export const hearingReminderScheduler = onSchedule(
  {
    schedule: "every 2 minutes",
    timeZone: "UTC",
    region: "us-central1",
    memory: "256MiB",
    secrets: [philsmsApiTokenParam],
  },
  async () => {
    const db = admin.firestore();
    await processDueHearingReminderJobs(
      db,
      hearingPhilSmsCfg(),
      hearingSemaphoreCfg(),
    );
  },
);

/** Flutter web/app → Semaphore SMS (avoids browser CORS to api.semaphore.co). */
export const sendSemaphoreSms = onCall(
  {
    region: "us-central1",
    memory: "256MiB",
    cors: true,
  },
  async (request) => {
    return handleSendSemaphoreSms(request, {
      apiKey: semaphoreApiKeyParam.value().trim(),
      senderName: semaphoreSenderNameParam.value().trim() || "LAWCONNECT",
    });
  },
);

/** Flutter `sms_requests` queue → PhilSMS, then Semaphore. */
export const onSmsRequestSend = onDocumentCreated(
  {
    document: "sms_requests/{docId}",
    region: "us-central1",
    memory: "256MiB",
    secrets: [philsmsApiTokenParam],
  },
  async (event) => {
    await handleSmsRequestCreated(event, {
      twilioAccountSid: "",
      twilioAuthToken: "",
      twilioFromNumber: "",
      semaphoreApiKey: semaphoreApiKeyParam.value().trim(),
      semaphoreSenderName: semaphoreSenderNameParam.value().trim(),
      philsmsApiToken: philsmsApiTokenParam.value().trim(),
      philsmsSenderId: philsmsSenderIdParam.value().trim() || "PhilSMS",
    });
  },
);

/** Client inbox: backfill hearing_inapp notifications + matchedClientIds on hearings. */
export { syncClientHearingInbox };

/**
 * Flutter `payment_checkout_requests` queue → create a real Xendit Invoice
 * and return the hosted GCash/bank payment URL.
 */
export const onPaymentCheckoutRequested = onDocumentCreated(
  {
    document: "payment_checkout_requests/{docId}",
    region: "us-central1",
    memory: "256MiB",
  },
  async (event) => {
    await handlePaymentCheckoutRequest(event, xenditCfg());
  },
);

/**
 * Xendit webhook → confirms a real charge, then updates the invoice balance
 * and marks the payment successful. Register this URL in the Xendit dashboard
 * (Settings → Webhooks → Invoices paid).
 */
export const xenditWebhook = onRequest(
  {
    region: "us-central1",
    memory: "256MiB",
  },
  async (req, res) => {
    await handleXenditWebhook(req, res, xenditCfg());
  },
);

/** IMAP poll off. n8n writes `hearings`; onHearingActivityCreated fans out SMS. */
export {
  courtEmailIngest,
  imapCourtEmailIngest,
  imapCourtEmailManual,
  onCourtEmailNotificationSuppress,
  onCourtEmailQueueNotify,
  processCourtEmailQueue,
};
