import admin from "firebase-admin";
import { readFileSync } from "fs";

const sa = JSON.parse(readFileSync("c:/law_connect4new/serviceAccount.json", "utf8"));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const CLEAN_COURT_ORDER = `REPUBLIC OF THE PHILIPPINES
REGIONAL TRIAL COURT
NATIONAL CAPITAL JUDICIAL REGION
QUEZON CITY, BRANCH 45
PEOPLE OF THE PHILIPPINES, Criminal Case No. Q-26-45871
Plaintiff, For: QUALIFIED THEFT
-versus-
JOREN LIMPAHAN,
Defendant.
ORDER
Before this Court is the scheduled hearing of the above-entitled case for arraignment and pre-trial conference.
After considering the records of the case and the appearance of the parties, the Court hereby sets the
continuation of the proceedings on May 14 , 2026 at 8:00 AM o’clock in the morning at the Session Hall of this
Court, Regional Trial Court, Branch 45, Quezon City.
The accused is hereby directed to appear before this Court on the said date and time. Failure to appear without
valid justification shall constrain the Court to take appropriate legal action pursuant to the Rules of Court.
The prosecution and defense counsel are likewise ordered to submit their respective pre-trial briefs at least three
(3) days before the scheduled hearing.
SO ORDERED.
Quezon City, Philippines, this 12th day of May 2026.
______________________________
HON. MARIA TERESA V. RAMOS
Presiding Judge
NOTICE
TO:
ATTY. APAO
Counsel for the Defense

GREETINGS:
Please take notice that the hearing of the above-entitled case has been scheduled on May 14 , 2026 at 8:00 AM
before the Regional Trial Court, Branch 45, Quezon City.
You are hereby required to appear and assist your client accordingly.
Quezon City, Philippines.
______________________________
HALL OF JUSTICE`;

const CLEAN_MESSAGE = `Case No.: Q-26-45871
Case title: PEOPLE OF THE PHILIPPINES vs. JOREN LIMPAHAN
Involved Party: Joren Limpahan
Court / Branch: Regional Trial Court, Branch 45, Quezon City
Hearing date: May 14, 2026
Hearing time: 8:00 AM
Location: Regional Trial Court, Branch 45, Quezon City
Summary: Scheduled hearing of the above-entitled case for arraignment and pre-trial conference.

Order / notice:
${CLEAN_COURT_ORDER}`;

async function repairFirestore() {
  console.log("=== 1. CREATING/REPAIRING HEARING xSNXAeEuP9FOIlaIOlKu ===");
  const hearingRef = db.collection("hearings").doc("xSNXAeEuP9FOIlaIOlKu");
  await hearingRef.set(
    {
      caseNo: "Q-26-45871",
      caseTitle: "PEOPLE OF THE PHILIPPINES vs. JOREN LIMPAHAN",
      clientName: "Joren Limpahan",
      location: "Regional Trial Court, Branch 45, Quezon City",
      courtBranch: "Branch 45",
      court: "Regional Trial Court, Branch 45, Quezon City",
      hearingDate: "May 14, 2026",
      hearingTime: "8:00 AM",
      fullText: CLEAN_COURT_ORDER,
      summary: "Scheduled hearing of the above-entitled case for arraignment and pre-trial conference.",
      activityType: "court_import",
      involvedClientIds: ["AGnXu9OXYceeJMJTm6V7e27Yeeh2"],
      matchedClientIds: ["AGnXu9OXYceeJMJTm6V7e27Yeeh2"],
      ownerClientId: "AGnXu9OXYceeJMJTm6V7e27Yeeh2",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log("Hearing doc restored and saved successfully.");

  console.log("=== 2. REPAIRING ALL NOTIFICATIONS LINKED TO xSNXAeEuP9FOIlaIOlKu ===");
  const notifsSnap = await db.collection("notifications").get();
  let repairedCount = 0;
  for (const doc of notifsSnap.docs) {
    if (doc.id.includes("xSNXAeEuP9FOIlaIOlKu")) {
      console.log("Repairing notification:", doc.id);
      await doc.ref.set(
        {
          caseNo: "Q-26-45871",
          caseTitle: "PEOPLE OF THE PHILIPPINES vs. JOREN LIMPAHAN",
          clientName: "Joren Limpahan",
          location: "Regional Trial Court, Branch 45, Quezon City",
          courtBranch: "Branch 45",
          hearingDate: "May 14, 2026",
          hearingTime: "8:00 AM",
          fullText: CLEAN_COURT_ORDER,
          summary: "Scheduled hearing of the above-entitled case for arraignment and pre-trial conference.",
          message: CLEAN_MESSAGE,
          title: "Court Hearing Notice — Q-26-45871",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      repairedCount++;
    }
  }
  console.log(`Successfully repaired ${repairedCount} notifications.`);

  console.log("=== 3. VERIFYING NOTIFICATION FOR USER AGnXu9OXYceeJMJTm6V7e27Yeeh2 ===");
  const userNotif = await db
    .collection("notifications")
    .doc("hearing_inapp_xSNXAeEuP9FOIlaIOlKu_AGnXu9OXYceeJMJTm6V7e27Yeeh2")
    .get();
  if (userNotif.exists) {
    const d = userNotif.data();
    console.log({
      caseNo: d.caseNo,
      caseTitle: d.caseTitle,
      clientName: d.clientName,
      location: d.location,
      courtBranch: d.courtBranch,
      hearingDate: d.hearingDate,
      hearingTime: d.hearingTime,
      fullTextLen: (d.fullText || "").length,
      fullTextHead: (d.fullText || "").slice(0, 100),
    });
  }
}

repairFirestore().catch(console.error);
