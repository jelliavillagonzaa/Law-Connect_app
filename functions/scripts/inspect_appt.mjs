import admin from "firebase-admin";
import { readFileSync } from "fs";

const sa = JSON.parse(readFileSync("c:/law_connect4new/serviceAccount.json", "utf8"));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

async function checkAppts() {
  const snap = await db.collection("appointments").get();
  console.log("Total appointments:", snap.size);
  for (const doc of snap.docs) {
    const d = doc.data();
    const str = JSON.stringify(d);
    if (str.includes("meathsjambo") || str.includes("2pm nlng") || d.status === "pending") {
      console.log("\n--- APPOINTMENT ID:", doc.id, "---");
      console.log("status:", d.status);
      console.log("clientName:", d.clientName);
      console.log("appointmentDateTime:", d.appointmentDateTime?.toDate ? d.appointmentDateTime.toDate() : d.appointmentDateTime);
      console.log("notes:", d.notes);
      console.log("requestId:", d.requestId);
      console.log("attorneyId:", d.attorneyId);
      console.log("clientId:", d.clientId);
    }
  }
}

checkAppts().catch(console.error);
