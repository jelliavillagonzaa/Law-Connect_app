import admin from "firebase-admin";
import { readFileSync } from "fs";

const sa = JSON.parse(readFileSync("c:/law_connect4new/serviceAccount.json", "utf8"));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

async function inspect() {
  console.log("=== HEARINGS WITH Q-26-45871 ===");
  const hearingsSnap = await db.collection("hearings")
    .where("caseNo", "==", "Q-26-45871")
    .get();
  console.log(`Found ${hearingsSnap.size} hearing docs`);
  for (const doc of hearingsSnap.docs) {
    console.log("HEARING DOC ID:", doc.id);
    const d = doc.data();
    console.log("caseNo:", d.caseNo);
    console.log("caseTitle:", d.caseTitle);
    console.log("clientName:", d.clientName);
    console.log("involvedPartyNames:", d.involvedPartyNames);
    console.log("involvedClientIds:", d.involvedClientIds);
    console.log("matchedClientIds:", d.matchedClientIds);
    console.log("location:", d.location);
    console.log("courtBranch:", d.courtBranch);
    console.log("hearingDate:", d.hearingDate);
    console.log("hearingTime:", d.hearingTime);
    console.log("summary:", d.summary);
    console.log("fullText length:", (d.fullText || "").length);
    console.log("fullText snippet:\n", (d.fullText || "").slice(0, 500));
    console.log("message snippet:\n", (d.message || "").slice(0, 500));
    console.log("-----------------------------------------");
  }

  console.log("=== ALL RECENT HEARINGS ===");
  const allHearings = await db.collection("hearings").orderBy("createdAt", "desc").limit(5).get();
  for (const doc of allHearings.docs) {
    const d = doc.data();
    console.log("ID:", doc.id, "caseNo:", d.caseNo, "clientName:", d.clientName, "location:", d.location, "courtBranch:", d.courtBranch);
    console.log("fullText snippet:\n", (d.fullText || "").slice(0, 300));
  }

  console.log("=== NOTIFICATIONS WITH Q-26-45871 ===");
  const notifSnap = await db.collection("notifications")
    .where("caseNo", "==", "Q-26-45871")
    .get();
  console.log(`Found ${notifSnap.size} notification docs`);
  for (const doc of notifSnap.docs) {
    console.log("NOTIF DOC ID:", doc.id);
    const d = doc.data();
    console.log("userId:", d.userId);
    console.log("clientId:", d.clientId);
    console.log("title:", d.title);
    console.log("hearingDocId:", d.hearingDocId);
    console.log("location:", d.location);
    console.log("courtBranch:", d.courtBranch);
    console.log("fullText length:", (d.fullText || "").length);
    console.log("fullText snippet:\n", (d.fullText || "").slice(0, 300));
    console.log("-----------------------------------------");
  }

  console.log("=== SEARCH USERS FOR JOREN ===");
  const usersSnap = await db.collection("users").get();
  for (const u of usersSnap.docs) {
    const ud = u.data();
    const name = `${ud.firstName || ""} ${ud.lastName || ""} ${ud.fullName || ""} ${ud.name || ""}`.toLowerCase();
    if (name.includes("joren") || name.includes("limpahan")) {
      console.log("USER:", u.id, ud.role, {
        firstName: ud.firstName,
        lastName: ud.lastName,
        fullName: ud.fullName,
        displayName: ud.displayName,
        email: ud.email,
        phone: ud.phoneNumber || ud.phone || ud.contactNumber,
      });
    }
  }
}

inspect().catch(console.error);
