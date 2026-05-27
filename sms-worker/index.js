import admin from "firebase-admin";

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "";
const GATEWAY_URL = (process.env.SMS_GATEWAY_URL || "").trim();
const GATEWAY_TOKEN = (process.env.SMS_GATEWAY_TOKEN || "").trim(); // optional
const POLL_MS = Number(process.env.SMS_WORKER_POLL_MS || "2000");
const BATCH_SIZE = Number(process.env.SMS_WORKER_BATCH || "5");
const WORKER_ID =
  (process.env.SMS_WORKER_ID || "").trim() ||
  `worker_${Math.random().toString(16).slice(2)}`;

if (!GATEWAY_URL) {
  console.error("Missing env SMS_GATEWAY_URL");
  process.exit(1);
}

function nowIso() {
  return new Date().toISOString();
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function normalizePhoneE164Ph(input) {
  let s = String(input || "").trim();
  if (!s) return s;
  s = s.replace(/[\s\-\(\)]/g, "");
  if (s.startsWith("+")) return s;
  if (s.startsWith("09") && s.length === 11) return `+63${s.slice(1)}`;
  if (s.startsWith("9") && s.length === 10) return `+63${s}`;
  if (s.startsWith("63") && s.length >= 12) return `+${s}`;
  return s;
}

async function sendViaGateway({ to, body }) {
  const payload = {
    to,
    message: body,
  };

  const headers = {
    "Content-Type": "application/json",
  };
  if (GATEWAY_TOKEN) {
    headers["Authorization"] = `Bearer ${GATEWAY_TOKEN}`;
  }

  const res = await fetch(GATEWAY_URL, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });

  const text = await res.text().catch(() => "");
  if (!res.ok) {
    throw new Error(`Gateway ${res.status}: ${text || res.statusText}`);
  }

  // If gateway returns JSON, keep it for debugging
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { raw: text, json };
}

async function claimOne(db, docRef) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(docRef);
    if (!snap.exists) return { ok: false, reason: "missing" };
    const d = snap.data() || {};
    if (d.status !== "pending") return { ok: false, reason: "not_pending" };
    tx.update(docRef, {
      status: "processing",
      workerId: WORKER_ID,
      processingAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true, data: d };
  });
}

async function processPending(db) {
  const qs = await db
    .collection("sms_requests")
    .where("status", "==", "pending")
    .orderBy("createdAt", "asc")
    .limit(BATCH_SIZE)
    .get();

  if (qs.empty) return 0;

  let processed = 0;
  for (const doc of qs.docs) {
    const ref = doc.ref;

    const claim = await claimOne(db, ref);
    if (!claim.ok) continue;

    const d = claim.data || {};
    const to = normalizePhoneE164Ph(d.to);
    const body = String(d.body || "").trim();

    if (!to || !to.startsWith("+")) {
      await ref.update({
        status: "failed",
        error: "Invalid phone; must be E.164 (e.g. +639XXXXXXXXX).",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      processed += 1;
      continue;
    }
    if (!body) {
      await ref.update({
        status: "failed",
        error: "Empty body",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      processed += 1;
      continue;
    }

    try {
      const result = await sendViaGateway({ to, body });
      await ref.update({
        status: "sent",
        provider: "android_gateway",
        providerResponse: result.json || result.raw || null,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      await ref.update({
        status: "failed",
        error: e instanceof Error ? e.message : String(e),
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    processed += 1;
  }

  return processed;
}

async function main() {
  // Uses GOOGLE_APPLICATION_CREDENTIALS by default.
  admin.initializeApp(
    PROJECT_ID ? { projectId: PROJECT_ID } : undefined,
  );
  const db = admin.firestore();

  console.log(`[${nowIso()}] SMS Worker started: ${WORKER_ID}`);
  console.log(`Gateway URL: ${GATEWAY_URL}`);
  console.log(`Poll: ${POLL_MS}ms, batch: ${BATCH_SIZE}`);

  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      const n = await processPending(db);
      if (n > 0) {
        console.log(`[${nowIso()}] processed ${n}`);
      }
    } catch (e) {
      console.error(`[${nowIso()}] error`, e);
    }
    await sleep(POLL_MS);
  }
}

main().catch((e) => {
  console.error("fatal", e);
  process.exit(1);
});

