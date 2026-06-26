/**
 * Law Connect — hearing notifications, SMS, email queue, client sync, and
 * online payments (Xendit).
 */
import { setGlobalOptions } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onRequest } from "firebase-functions/v2/https";
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
import { syncClientHearingInbox } from "./clientHearingSync";
import {
  handlePaymentCheckoutRequest,
  handleXenditWebhook,
  XenditConfig,
} from "./xendit";

/** Optional SMTP for `email_requests` (hearing + other queued mail). */
const smtpHostParam = defineString("SMTP_HOST", { default: "" });
const smtpPortParam = defineString("SMTP_PORT", { default: "587" });
const smtpUserParam = defineString("SMTP_USER", { default: "" });
const smtpPassParam = defineString("SMTP_PASS", { default: "" });
const smtpFromParam = defineString("SMTP_FROM", { default: "" });

const semaphoreApiKeyParam = defineString("SEMAPHORE_API_KEY", { default: "" });
const semaphoreSenderNameParam = defineString("SEMAPHORE_SENDER_NAME", {
  default: "",
});

/** PhilSMS for `hearings` create/update. */
const philsmsApiTokenSecret = defineSecret("PHILSMS_API_TOKEN");
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

/** Xendit real payments (GCash, Maya, card, online banking). */
const xenditSecretKey = defineSecret("XENDIT_SECRET_KEY");
const xenditWebhookToken = defineSecret("XENDIT_WEBHOOK_TOKEN");
const xenditSuccessUrlParam = defineString("XENDIT_SUCCESS_URL", {
  default: "https://jurislink-app.web.app/payment-success.html",
});
const xenditCancelUrlParam = defineString("XENDIT_CANCEL_URL", {
  default: "https://jurislink-app.web.app/payment-cancel.html",
});

function xenditCfg(): XenditConfig {
  return {
    secretKey: xenditSecretKey.value().trim(),
    webhookToken: xenditWebhookToken.value().trim(),
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
    apiToken: philsmsApiTokenSecret.value().trim(),
    senderId: philsmsSenderIdParam.value().trim() || "PhilSMS",
    alertPhones,
    staffAlertPhones,
    firmPhonesOnly: firmOnlyRaw !== "false" && firmOnlyRaw !== "0",
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
    secrets: [philsmsApiTokenSecret],
  },
  async (event) => {
    await handleHearingDocumentCreated(event, hearingPhilSmsCfg());
  },
);

export const onHearingActivityUpdated = onDocumentUpdated(
  {
    document: "hearings/{hearingId}",
    region: "us-central1",
    memory: "512MiB",
    secrets: [philsmsApiTokenSecret],
  },
  async (event) => {
    await handleHearingDocumentUpdated(event, hearingPhilSmsCfg());
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
    await handleEmailRequestCreated(event, {
      host: smtpHostParam.value(),
      port: parseInt(smtpPortParam.value(), 10) || 587,
      user: smtpUserParam.value(),
      pass: smtpPassParam.value(),
      from: smtpFromParam.value(),
    });
  },
);

/** Sends due rows in `hearing_reminder_jobs` (5d / 3d / 1d / day / 10h / 5m) + PhilSMS. */
export const hearingReminderScheduler = onSchedule(
  {
    schedule: "every 2 minutes",
    timeZone: "UTC",
    region: "us-central1",
    memory: "256MiB",
    secrets: [philsmsApiTokenSecret],
  },
  async () => {
    const db = admin.firestore();
    await processDueHearingReminderJobs(db, hearingPhilSmsCfg());
  },
);

/** Flutter `sms_requests` queue → send SMS via Semaphore (Philippines). */
export const onSmsRequestSend = onDocumentCreated(
  {
    document: "sms_requests/{docId}",
    region: "us-central1",
    memory: "256MiB",
  },
  async (event) => {
    await handleSmsRequestCreated(event, {
      twilioAccountSid: "",
      twilioAuthToken: "",
      twilioFromNumber: "",
      semaphoreApiKey: semaphoreApiKeyParam.value().trim(),
      semaphoreSenderName: semaphoreSenderNameParam.value().trim(),
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
    secrets: [xenditSecretKey, xenditWebhookToken],
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
    secrets: [xenditSecretKey, xenditWebhookToken],
  },
  async (req, res) => {
    await handleXenditWebhook(req, res, xenditCfg());
  },
);
