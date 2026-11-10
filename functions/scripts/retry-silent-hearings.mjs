/**
 * Retry push + SMS for hearings claimed/created but never delivered.
 * Usage: node scripts/retry-silent-hearings.mjs [hoursBack=6]
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
const SEM_KEY =
  process.env.SEMAPHORE_API_KEY || "52ea8dd46c8931879502f3978589888a";

async function notifyOne(db, hearingId, d, recipients) {
  if (d.philsmsLastSentAt == null) {
    await db.collection("hearings").doc(hearingId).set(
      {
        philsmsIntakeSent: admin.firestore.FieldValue.delete(),
        philsmsIntakeClaimedAt: admin.firestore.FieldValue.delete(),
      },
      { merge: true },
    );
  }

  const fields = hearingFieldsForSms(d);
  const caseLabel = fields.caseNo || "Court order";
  const title = fields.hearingDate
    ? `Court hearing / order — ${caseLabel} · ${fields.hearingDate}`
    : `Court hearing / order — ${caseLabel}`;
  const body = buildHearingSmsText(fields);

  const needPush = d.fcmDeliveredAt == null && d.fcmMobileDeliveredAt == null;
  if (needPush) {
    await deliverHearingNotification({
      db,
      caseId: "",
      hearingDocId: hearingId,
      recipients,
      title,
      body,
      notificationType: "hearing_activity",
      reminderKind: null,
      hearingDoc: d,
      data: {
        activityType: "court_import",
        source: d.source || "n8n",
        caseNo: fields.caseNo,
        clientName: fields.clientName,
        courtBranch: fields.location,
        caseTitle: fields.caseTitle,
        location: fields.location,
        hearingDate: fields.hearingDate,
        hearingTime: fields.hearingTime,
      },
    });
  }

  if (d.philsmsLastSentAt == null) {
    await sendHearingSmsAlerts({
      db,
      hearingDocId: hearingId,
      hearingData: d,
      recipientUserIds: recipients,
      title,
      body,
      cfg: {
        apiToken: PHILSMS_TOKEN,
        senderId: "PhilSMS",
        alertPhones: ["09351914214"],
        staffAlertPhones: ["09351914214"],
        firmPhonesOnly: true,
      },
      semaphore: { apiKey: SEM_KEY, senderName: "LAWCONNECT" },
    });
  }

  const after = (await db.collection("hearings").doc(hearingId).get()).data();
  return {
    id: hearingId,
    caseNo: d.caseNo,
    fcm: !!after?.fcmDeliveredAt,
    fcmN: after?.fcmSuccessCount ?? null,
    sms: !!after?.philsmsLastSentAt,
  };
}

async function main() {
  const hours = Number(process.argv[2] || 8);
  const db = admin.firestore();
  const since = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - hours * 60 * 60 * 1000),
  );
  const snap = await db
    .collection("hearings")
    .where("createdAt", ">=", since)
    .orderBy("createdAt", "desc")
    .limit(40)
    .get();

  const silent = snap.docs.filter((doc) => {
    const d = doc.data();
    return d.fcmDeliveredAt == null || d.philsmsLastSentAt == null;
  });
  console.log(`found ${snap.size} recent, ${silent.length} silent (last ${hours}h)`);

  const users = await db.collection("users").where("role", "==", "attorney").limit(20).get();
  const staff = await db.collection("users").where("role", "==", "staff").limit(40).get();
  const recipients = [];
  for (const u of [...users.docs, ...staff.docs]) {
    if (u.data()?.isActive === false) continue;
    recipients.push(u.id);
  }

  for (const doc of silent) {
    try {
      const result = await notifyOne(db, doc.id, doc.data(), recipients);
      console.log("retried", JSON.stringify(result));
      await new Promise((r) => setTimeout(r, 800));
    } catch (e) {
      console.error("fail", doc.id, e instanceof Error ? e.message : e);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
