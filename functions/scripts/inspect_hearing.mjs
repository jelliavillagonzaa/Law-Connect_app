import admin from "firebase-admin";
import { readFileSync } from "fs";

const sa = JSON.parse(readFileSync("c:/law_connect4new/serviceAccount.json", "utf8"));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

async function inspectDoc() {
  const notifDoc = await db.collection("notifications").doc("hearing_inapp_xSNXAeEuP9FOIlaIOlKu_AGnXu9OXYceeJMJTm6V7e27Yeeh2").get();
  console.log("=== NOTIF DOC hearing_inapp_xSNXAeEuP9FOIlaIOlKu_AGnXu9OXYceeJMJTm6V7e27Yeeh2 ===");
  const nd = notifDoc.data();
  if (nd) {
    for (const [k, v] of Object.entries(nd)) {
      if (typeof v === "string" && v.length > 300) {
        console.log(`${k} (length ${v.length}):\n${v.slice(0, 1000)}...\n`);
      } else {
        console.log(`${k}:`, v);
      }
    }
  }

  console.log("\n=== ALL HEARINGS IN DB ===");
  const hearings = await db.collection("hearings").get();
  console.log("Count:", hearings.size);
  for (const h of hearings.docs) {
    const d = h.data();
    console.log("HEARING ID:", h.id, "caseNo:", d.caseNo, "client:", d.clientName, "location:", d.location, "courtBranch:", d.courtBranch);
    if (d.fullText) {
      console.log("fullText (length " + d.fullText.length + "):\n" + d.fullText.slice(0, 600) + "\n");
    }
  }
}

inspectDoc().catch(console.error);
