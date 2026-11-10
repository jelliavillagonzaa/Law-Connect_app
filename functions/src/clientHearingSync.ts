import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import {
  buildNotificationBody,
  clientProfileMatchesHearingClientName,
  deliverHearingNotification,
  extractOrderStructuredFields,
  hearingAtFromDoc,
  isHearingInactiveForReminders,
  isImportedCourtRow,
  isJunkHearingDoc,
  upsertReminderJobs,
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
      ? `Court Hearing Notice — ${cn}`
      : `Court Hearing Notice — ${caseTitle}`;
  }
  const act = asString(d.activityType) || "message";
  if (act === "schedule") return `Hearing scheduled — ${caseTitle}`;
  if (act === "update") return `Hearing updated — ${caseTitle}`;
  return `Hearing message — ${caseTitle}`;
}

async function fetchRecentHearingDocs(
  db: admin.firestore.Firestore,
  limitN: number,
): Promise<admin.firestore.QueryDocumentSnapshot[]> {
  const byId = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  try {
    const ordered = await db
      .collection("hearings")
      .orderBy("createdAt", "desc")
      .limit(limitN)
      .get();
    for (const doc of ordered.docs) byId.set(doc.id, doc);
  } catch (e) {
    logger.warn("syncClientHearingInbox: orderBy createdAt failed, using limit", {
      err: e instanceof Error ? e.message : String(e),
    });
  }
  try {
    const unordered = await db.collection("hearings").limit(limitN).get();
    for (const doc of unordered.docs) byId.set(doc.id, doc);
  } catch (e) {
    logger.warn("syncClientHearingInbox: unordered hearings limit failed", {
      err: e instanceof Error ? e.message : String(e),
    });
  }
  return [...byId.values()];
}

/**
 * Admin backfill: match hearings & involved cases by client profile name,
 * write `hearing_inapp_*` / `case_involved_*` rows, and tag hearing docs.
 */
export async function syncClientHearingInboxForUid(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<{ hearingsMatched: number; notificationsWritten: number }> {
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "User not found");
  }
  const profile = (userSnap.data() ?? {}) as Record<string, unknown>;
  const role = asString(profile.role).toLowerCase();
  if (role !== "client") {
    throw new HttpsError("permission-denied", "Only clients can sync hearing inbox");
  }

  const nameVariants = new Set<string>();
  for (const field of ["fullName", "name", "displayName"]) {
    const v = asString(profile[field]);
    if (v) {
      for (const nm of clientNameQueryVariants(v)) nameVariants.add(nm);
      const words = v.split(/\s+/).filter(Boolean);
      if (words.length >= 3) {
        for (const nm of clientNameQueryVariants(`${words[0]} ${words[words.length - 1]}`)) {
          nameVariants.add(nm);
        }
      }
    }
  }
  const first = asString(profile.firstName).trim();
  const last = asString(profile.lastName).trim();
  if (first && last) {
    for (const nm of clientNameQueryVariants(`${first} ${last}`)) {
      nameVariants.add(nm);
    }
  }

  const seenHearingIds = new Set<string>();
  let notificationsWritten = 0;

  const ingestHearing = async (
    hearingId: string,
    d: HearingDoc & Record<string, unknown>,
    isRealHearingDoc = true,
  ) => {
    if (seenHearingIds.has(hearingId)) return;
    seenHearingIds.add(hearingId);
    if (isJunkHearingDoc(d)) return;

    const extracted = extractOrderStructuredFields(d);
    const effCaseNo = extracted.caseNo || asString(d.caseNo);
    const effCaseTitle =
      extracted.caseTitle || asString(d.caseTitle) || effCaseNo || "Hearing";
    const effClientName = extracted.clientName || asString(d.clientName);
    const effCourtBranch = extracted.courtBranch || asString(d.courtBranch);
    const effLocation =
      extracted.location || asString(d.location) || effCourtBranch;
    const effHearingDate = extracted.hearingDate || asString(d.hearingDate);
    const effHearingTime = extracted.hearingTime || asString(d.hearingTime);

    const enrichedDoc: HearingDoc & Record<string, unknown> = {
      ...d,
      ...(effCaseNo ? { caseNo: effCaseNo } : {}),
      ...(effCaseTitle ? { caseTitle: effCaseTitle } : {}),
      ...(effClientName ? { clientName: effClientName } : {}),
      ...(effCourtBranch ? { courtBranch: effCourtBranch } : {}),
      ...(effLocation ? { location: effLocation } : {}),
      ...(effHearingDate ? { hearingDate: effHearingDate } : {}),
      ...(effHearingTime ? { hearingTime: effHearingTime } : {}),
      ...(extracted.involvedPartyNames.length
        ? { involvedPartyNames: extracted.involvedPartyNames }
        : {}),
    };

    const title = hearingTitle(enrichedDoc, effCaseTitle);
    const body = buildNotificationBody(enrichedDoc, {
      caseId: asString(d.caseId) || hearingId,
      caseTitle: effCaseTitle,
    });

    try {
      await deliverHearingNotification({
        db,
        caseId: asString(d.caseId),
        hearingDocId: hearingId,
        recipients: [uid],
        clientRecipientIds: [uid],
        title,
        body,
        notificationType: "hearing_activity",
        reminderKind: null,
        hearingDoc: enrichedDoc,
        inAppOnly: true,
        data: {
          activityType: asString(d.activityType) || "court_notice",
          caseNo: effCaseNo,
          clientName: effClientName,
          courtBranch: effCourtBranch,
          location: effLocation,
          hearingDate: effHearingDate,
          hearingTime: effHearingTime,
          caseTitle: effCaseTitle,
          fullText: asString(d.fullText),
          source: asString(d.source),
        },
      });
      notificationsWritten++;
    } catch (e) {
      logger.warn("syncClientHearingInbox: deliver failed", {
        hearingId,
        err: e instanceof Error ? e.message : String(e),
      });
    }

    if (isRealHearingDoc) {
      try {
        const link: Record<string, unknown> = {
          matchedClientIds: admin.firestore.FieldValue.arrayUnion(uid),
          involvedClientIds: admin.firestore.FieldValue.arrayUnion(uid),
        };
        if (extracted.involvedPartyNames.length) {
          link.involvedPartyNames = admin.firestore.FieldValue.arrayUnion(
            ...extracted.involvedPartyNames,
          );
        }
        if (!asString(d.ownerClientId)) {
          link.ownerClientId = uid;
        }
        await db.collection("hearings").doc(hearingId).set(link, { merge: true });
      } catch (e) {
        logger.warn("syncClientHearingInbox: hearing link merge failed", {
          hearingId,
          err: e instanceof Error ? e.message : String(e),
        });
      }

      try {
        const ht = hearingAtFromDoc(enrichedDoc);
        if (
          ht &&
          ht.getTime() > Date.now() - 12 * 60 * 60 * 1000 &&
          !isHearingInactiveForReminders(enrichedDoc)
        ) {
          await upsertReminderJobs({
            db,
            hearingDocId: hearingId,
            caseId: asString(d.caseId) || hearingId,
            hearingAt: ht,
            recipients: [uid],
            snapshot: {
              senderName:
                asString(d.senderName) || effClientName || "Court notice",
              message: isImportedCourtRow(enrichedDoc)
                ? [effCaseNo, effLocation].filter(Boolean).join(" — ")
                : asString(d.message),
              caseTitle: effCaseTitle,
              activityType:
                asString(d.activityType) ||
                (isImportedCourtRow(enrichedDoc) ? "court_import" : "message"),
              caseNo: effCaseNo,
              clientName: effClientName,
              courtBranch: effCourtBranch || effLocation,
            },
            pruneUnlistedRecipients: false,
          });
        }
      } catch (e) {
        logger.warn("syncClientHearingInbox: reminder schedule failed", {
          hearingId,
          err: e instanceof Error ? e.message : String(e),
        });
      }
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
        await ingestHearing(doc.id, doc.data() as HearingDoc & Record<string, unknown>);
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
        await ingestHearing(doc.id, doc.data() as HearingDoc & Record<string, unknown>);
      }
    } catch (e) {
      logger.warn("syncClientHearingInbox: clientName query failed", {
        nm,
        err: e instanceof Error ? e.message : String(e),
      });
    }
  }

  try {
    const matchedCases = new Map<string, admin.firestore.QueryDocumentSnapshot>();
    const ownCases = await db
      .collection("cases")
      .where("clientId", "==", uid)
      .limit(50)
      .get();
    for (const c of ownCases.docs) matchedCases.set(c.id, c);

    const recentCases = await db.collection("cases").limit(150).get();
    for (const c of recentCases.docs) {
      if (matchedCases.has(c.id)) continue;
      const cd = c.data() as Record<string, unknown>;
      if (cd.isArchived === true) continue;
      if (asString(cd.status).toLowerCase() === "under_review") continue;
      const partyBlob = [
        asString(cd.clientName),
        asString(cd.clientFullName),
        asString(cd.opposingParty),
      ]
        .filter(Boolean)
        .join(", ");
      if (
        clientProfileMatchesHearingClientName(profile, partyBlob, {
          caseTitle: asString(cd.caseTitle),
        })
      ) {
        matchedCases.set(c.id, c);
      }
    }

    for (const c of matchedCases.values()) {
      const m = c.data() as Record<string, unknown>;
      if (m.isArchived === true || asString(m.status).toLowerCase() === "under_review") {
        continue;
      }
      try {
        const byCaseId = await db
          .collection("hearings")
          .where("caseId", "==", c.id)
          .limit(20)
          .get();
        for (const h of byCaseId.docs) {
          await ingestHearing(h.id, h.data() as HearingDoc & Record<string, unknown>);
        }
      } catch {
        /* ignore */
      }

      for (const field of [
        "caseNumber",
        "caseNo",
        "docketNumber",
        "criminalCaseNo",
      ]) {
        const cn = asString(m[field]);
        if (!cn) continue;
        const parsedNum = /^\d+$/.test(cn) ? Number(cn) : null;
        const queryVals: Array<string | number> =
          parsedNum !== null && Number.isSafeInteger(parsedNum)
            ? [cn, parsedNum]
            : [cn];
        for (const qv of queryVals) {
          try {
            const hq = await db
              .collection("hearings")
              .where("caseNo", "==", qv)
              .limit(20)
              .get();
            for (const h of hq.docs) {
              await ingestHearing(h.id, h.data() as HearingDoc & Record<string, unknown>);
            }
          } catch {
            /* ignore per caseNo */
          }
        }
      }

      // Ensure a case involvement notification exists if client has none for this case yet.
      const caseTitle = asString(m.caseTitle);
      const caseNo = asString(m.caseNumber) || asString(m.caseNo);
      if (caseTitle) {
        const caseNotifId = `case_involved_${c.id}_${uid}`;
        try {
          const existingCaseNotif = await db
            .collection("notifications")
            .doc(caseNotifId)
            .get();
          if (!existingCaseNotif.exists) {
            const anyForCase = await db
              .collection("notifications")
              .where("userId", "==", uid)
              .limit(60)
              .get();
            const alreadyNotified = anyForCase.docs.some(
              (n) => asString(n.data().caseId) === c.id,
            );
            if (!alreadyNotified) {
              await db.collection("notifications").doc(caseNotifId).set(
                {
                  userId: uid,
                  clientId: uid,
                  type: "case_involved",
                  caseId: c.id,
                  ...(caseNo ? { caseNo } : {}),
                  caseTitle,
                  title: caseNo
                      ? `Case Notice — ${caseNo}`
                      : `Case Notice — ${caseTitle}`,
                  summary: `You are listed as an involved party in "${caseTitle}".`,
                  message: `Your name is recorded on case "${caseTitle}"${
                    caseNo ? ` (Case No. ${caseNo})` : ""
                  }. Coordinate with your legal counsel for updates and schedules.`,
                  isRead: false,
                  createdAt:
                      m.updatedAt ?? m.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true },
              );
              notificationsWritten++;
            }
          }
        } catch {
          /* ignore */
        }
      }
    }
  } catch (e) {
    logger.warn("syncClientHearingInbox: cases scan failed", {
      err: e instanceof Error ? e.message : String(e),
    });
  }

  try {
    const docs = await fetchRecentHearingDocs(db, 150);
    for (const doc of docs) {
      const d = doc.data() as HearingDoc & Record<string, unknown>;
      const cn = [
        asString(d.clientName),
        Array.isArray(d.involvedPartyNames) ? d.involvedPartyNames.join(", ") : "",
      ]
        .filter(Boolean)
        .join(", ");
      if (
        clientProfileMatchesHearingClientName(profile, cn, {
          caseTitle: asString(d.caseTitle),
          fullText: asString(d.fullText),
        })
      ) {
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
