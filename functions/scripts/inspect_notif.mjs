import admin from "firebase-admin";
import { readFileSync } from "fs";

const sa = JSON.parse(readFileSync("c:/law_connect4new/serviceAccount.json", "utf8"));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

async function inspectDoc() {
  const notifDoc = await db.collection("notifications").doc("hearing_inapp_xSNXAeEuP9FOIlaIOlKu_AGnXu9OXYceeJMJTm6V7e27Yeeh2").get();
  console.log("=== NOTIF DOC DATA ===");
  const nd = notifDoc.data();
  console.log("Keys:", Object.keys(nd));
  console.log("location:", nd.location);
  console.log("courtBranch:", nd.courtBranch);
  console.log("hearingDocId:", nd.hearingDocId);
  console.log("caseNo:", nd.caseNo);
  console.log("caseTitle:", nd.caseTitle);
  console.log("clientName:", nd.clientName);
  console.log("hearingDate:", nd.hearingDate);
  console.log("hearingTime:", nd.hearingTime);
  console.log("summary:", nd.summary);
  console.log("fullText length:", nd.fullText?.length);
  console.log("fullText:\n", nd.fullText);
  console.log("message length:", nd.message?.length);
  console.log("message:\n", nd.message);
}

inspectDoc().catch(console.error);
