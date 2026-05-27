import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import {
  buildNotificationBody,
  deliverHearingNotification,
  isImportedCourtRow,
  resolveClientUidsByHearingName,
  type HearingDoc,
} from "./hearingNotifications";

function asString(v: unknown): string {
  return v === undefined || v === null ? "" : String(v).trim();
}

function clientNameQueryVariants(raw: string): string[] {
  const t = raw.trim();
  if (!t) return [];
  const out = new Set<string>([t, t.toUpperCase(), t.toLowerCase()]);
  const titled = t
    .split(" ")
    .map((w) => (w.length ? w[0].toUpperCase() + w.slice(1).toLowerCase() : w))
    .join(" ");
  out.add(titled);
  return [...out].filter((s) => s.length > 0);
}

function hearingTitle(d: HearingDoc, caseTitle: string): string {
  if (isImportedCourtRow(d)) {
    const cn = asString(d.caseNo);
    return cn
      ? `New notice court hearings — ${cn}`
      : `New notice court hearings — ${caseTitle}`;
  }
  const act = asString(d.activityType) || "message";
  if (act === "schedule") return `Hearing scheduled — ${caseTitle}`;
  if (act === "update") return `Hearing updated — ${caseTitle}`;
  return `Hearing message — ${caseTitle}`;
}

async function fetchRecentHearings(
  db: admin.firestore.Firestore,
  limitN: number,
): Promise<admin.firestore.QuerySnapshot> {
  try {
    return await db
      .collection("hearings")
      .orderBy("createdAt", "desc")
      .limit(limitN)
      .get();
  } catch (e) {
    logger.warn("syncClientHearingInbox: orderBy createdAt failed, using limit", {
      err: e instanceof Error ? e.message : String(e),
    });
    return db.collection("hearings").limit(limitN).get();
  }
}

/**
 * Admin backfill: match hearings by clientName, write `hearing_inapp_*` rows, tag hearing docs.
 * Clients cannot always read imported `hearings` rows directly (rules / exact name match).
 */
export async function syncClientHearingInboxForUid(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<{ hearingsMatched: number; notificationsWritten: number }> {
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "User not found");
  }
  const role = asString(userSnap.data()?.role).toLowerCase();
  if (role !== "client") {
    throw new HttpsError("permission-denied", "Only clients can sync hearing inbox");
  }

  const nameVariants = new Set<string>();
  for (const field of ["fullName", "name", "displayName"]) {
    const v = asString(userSnap.data()?.[field]);
    if (v) {
      for (const nm of clientNameQueryVariants(v)) nameVariants.add(nm);
    }
  }

  const seenHearingIds = new Set<string>();
  let notificationsWritten = 0;

  const ingestHearing = async (hearingId: string, d: HearingDoc) => {
    if (!seenHearingIds.add(hearingId)) return;
    const caseTitle =
      asString(d.caseTitle) || asString(d.caseNo) || "Hearing";
    const title = hearingTitle(d, caseTitle);
    const body = buildNotificationBody(d, {
      caseId: asString(d.caseId) || hearingId,
      caseTitle,
    });

    try {
      await deliverHearingNotification({
        db,
        caseId: asString(d.caseId),
        hearingDocId: hearingId,
        recipients: [uid],
        title,
        body,
        notificationType: "hearing_activity",
        reminderKind: null,
        hearingDoc: d,
        inAppOnly: true,
        data: {
          activityType: asString(d.activityType) || "court_notice",
          caseNo: asString(d.caseNo),
          clientName: asString(d.clientName),
          courtBranch: asString(d.courtBranch),
          caseTitle,
          fullText: asString(d.fullText),
        },
      });
      notificationsWritten++;
    } catch (e) {
      logger.warn("syncClientHearingInbox: deliver failed", {
        hearingId,
        err: e instanceof Error ? e.message : String(e),
      });
    }

    try {
      const link: Record<string, unknown> = {
        matchedClientIds: admin.firestore.FieldValue.arrayUnion(uid),
        involvedClientIds: admin.firestore.FieldValue.arrayUnion(uid),
        ownerClientId: uid,
      };
      await db.collection("hearings").doc(hearingId).set(link, { merge: true });
    } catch (e) {
      logger.warn("syncClientHearingInbox: hearing link merge failed", {
        hearingId,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  };

  const linkQueries = [
    db
      .collection("hearings")
      .where("involvedClientIds", "array-contains", uid)
      .limit(50)
      .get(),
    db
      .collection("hearings")
      .where("matchedClientIds", "array-contains", uid)
      .limit(50)
      .get(),
    db.collection("hearings").where("ownerClientId", "==", uid).limit(50).get(),
  ];

  for (const q of linkQueries) {
    try {
      const snap = await q;
      for (const doc of snap.docs) {
        await ingestHearing(doc.id, doc.data() as HearingDoc);
      }
    } catch (e) {
      logger.warn("syncClientHearingInbox: link query failed", {
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  for (const nm of nameVariants) {
    try {
      const q = await db
        .collection("hearings")
        .where("clientName", "==", nm)
        .limit(50)
        .get();
      for (const doc of q.docs) {
        await ingestHearing(doc.id, doc.data() as HearingDoc);
      }
    } catch (e) {
      logger.warn("syncClientHearingInbox: clientName query failed", {
        nm,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  try {
    const cases = await db
      .collection("cases")
      .where("clientId", "==", uid)
      .limit(40)
      .get();
    for (const c of cases.docs) {
      try {
        const byCaseId = await db
          .collection("hearings")
          .where("caseId", "==", c.id)
          .limit(20)
          .get();
        for (const h of byCaseId.docs) {
          await ingestHearing(h.id, h.data() as HearingDoc);
        }
      } catch {
        /* ignore */
      }

      const m = c.data() as Record<string, unknown>;
      for (const field of [
        "caseNumber",
        "caseNo",
        "docketNumber",
        "criminalCaseNo",
      ]) {
        const cn = asString(m[field]);
        if (!cn) continue;
        try {
          const hq = await db
            .collection("hearings")
            .where("caseNo", "==", cn)
            .limit(20)
            .get();
          for (const h of hq.docs) {
            await ingestHearing(h.id, h.data() as HearingDoc);
          }
        } catch {
          /* ignore per caseNo */
        }
      }
    }
  } catch (e) {
    logger.warn("syncClientHearingInbox: cases scan failed", {
      err: e instanceof Error ? e.message : String(e),
    });
  }

  try {
    const snap = await fetchRecentHearings(db, 120);
    for (const doc of snap.docs) {
      const d = doc.data() as HearingDoc;
      const cn = asString(d.clientName);
      if (!cn) continue;
      const uids = await resolveClientUidsByHearingName(db, cn);
      if (uids.includes(uid)) {
        await ingestHearing(doc.id, d);
      }
    }
  } catch (e) {
    logger.warn("syncClientHearingInbox: recent hearings scan failed", {
      err: e instanceof Error ? e.message : String(e),
    });
  }

  return {
    hearingsMatched: seenHearingIds.size,
    notificationsWritten,
  };
}

export const syncClientHearingInbox = onCall(
  {
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (request) => {
    try {
      const uid = request.auth?.uid;
      if (!uid) {
        throw new HttpsError("unauthenticated", "Login required");
      }
      const db = admin.firestore();
      return await syncClientHearingInboxForUid(db, uid);
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("syncClientHearingInbox unhandled", e);
      const msg = e instanceof Error ? e.message : String(e);
      throw new HttpsError("internal", msg || "syncClientHearingInbox failed");
    }
  },
);
