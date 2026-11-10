/**
 * One-shot: deliver push + SMS for hearings that were claimed but never sent.
 * Usage: node scripts/retry-latest-hearing-notify.mjs [hearingId]
 */
import admin from "firebase-admin";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { createRequire } from "module";

const require = createRequire(import.meta.url);
const __dirname = dirname(fileURLToPath(import.meta.url));
const sa = JSON.parse(
  readFileSync(join(__dirname, "../../serviceAccount.json"), "utf8"),
);
admin.initializeApp({ credential: admin.credential.cert(sa) });

const {
  deliverHearingNotification,
} = require("../lib/hearingNotifications.js");
const {
  sendHearingSmsAlerts,
  hearingFieldsForSms,
  buildHearingSmsText,
} = require("../lib/hearingSmsAlerts.js");

const PHILSMS_TOKEN =
  process.env.PHILSMS_API_TOKEN ||
  "3121|EcLePG3aVbu2YUoc6nxNVONdIW1BFThS1CN9ZxBqf680e780";

async function main() {
  const db = admin.firestore();
  const argId = process.argv[2];
  let hearingId = argId;
  let snap;
  if (hearingId) {
    snap = await db.collection("hearings").doc(hearingId).get();
  } else {
    const q = await db
      .collection("hearings")
      .orderBy("createdAt", "desc")
      .limit(1)
      .get();
    snap = q.docs[0];
    hearingId = snap?.id;
  }
  if (!snap?.exists) {
    console.error("hearing not found");
    process.exit(1);
  }
  const d = snap.data();
  console.log("retry", hearingId, d.caseNo, {
    fcmDeliveredAt: !!d.fcmDeliveredAt,
    philsmsLastSentAt: !!d.philsmsLastSentAt,
    fcmPushClaimedAt: !!d.fcmPushClaimedAt,
  });

  // Allow SMS claim again if prior claim never finished.
  if (d.philsmsLastSentAt == null) {
    await db.collection("hearings").doc(hearingId).set(
      {
        philsmsIntakeSent: admin.firestore.FieldValue.delete(),
        philsmsIntakeClaimedAt: admin.firestore.FieldValue.delete(),
      },
      { merge: true },
    );
  }

  const users = await db.collection("users").where("role", "==", "attorney").limit(20).get();
  const staff = await db.collection("users").where("role", "==", "staff").limit(40).get();
  const recipients = new Set();
  for (const u of [...users.docs, ...staff.docs]) {
    if (u.data()?.isActive === false) continue;
    recipients.add(u.id);
  }

  const fields = hearingFieldsForSms(d);
  const caseLabel = fields.caseNo || "Court order";
  const title = fields.hearingDate
    ? `Court hearing / order — ${caseLabel} · ${fields.hearingDate}`
    : `Court hearing / order — ${caseLabel}`;
  const body = buildHearingSmsText(fields);

  await deliverHearingNotification({
    db,
    caseId: "",
    hearingDocId: hearingId,
    recipients: [...recipients],
    title,
    body,
    notificationType: "hearing_activity",
    reminderKind: null,
    hearingDoc: d,
    data: {
      activityType: "court_import",
      source: "n8n",
      caseNo: fields.caseNo,
      clientName: fields.clientName,
      courtBranch: fields.location,
      caseTitle: fields.caseTitle,
      location: fields.location,
      hearingDate: fields.hearingDate,
      hearingTime: fields.hearingTime,
    },
  });
  console.log("push/in-app done, recipients", recipients.size);

  await sendHearingSmsAlerts({
    db,
    hearingDocId: hearingId,
    hearingData: d,
    recipientUserIds: [...recipients],
    title,
    body,
    cfg: {
      apiToken: PHILSMS_TOKEN,
      senderId: "PhilSMS",
      alertPhones: ["09351914214"],
      staffAlertPhones: ["09351914214"],
      firmPhonesOnly: true,
    },
    semaphore: {
      apiKey: process.env.SEMAPHORE_API_KEY || "52ea8dd46c8931879502f3978589888a",
      senderName: "LAWCONNECT",
    },
  });

  const after = (await db.collection("hearings").doc(hearingId).get()).data();
  console.log("after", {
    fcmDeliveredAt: !!after.fcmDeliveredAt,
    fcmSuccessCount: after.fcmSuccessCount ?? null,
    philsmsLastSentAt: !!after.philsmsLastSentAt,
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
