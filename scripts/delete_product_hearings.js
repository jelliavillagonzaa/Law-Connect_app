/**
 * Delete non-court hearings (product emails, "Court order" placeholder).
 *
 *   node scripts/delete_product_hearings.js
 *   node scripts/delete_product_hearings.js --dry-run
 */
const { initializeApp, applicationDefault, cert, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');

function blobOf(data) {
  return [
    data.caseNo,
    data.caseTitle,
    data.summary,
    data.fullText,
    data.message,
    data.clientName,
    data.subject,
  ]
    .map((v) => String(v ?? '').toLowerCase())
    .join('\n');
}

function isPlaceholderCaseNo(cn) {
  const s = String(cn ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
  return (
    !s ||
    s === 'court order' ||
    s === 'court hearing' ||
    s === 'hearing' ||
    s === 'order' ||
    s === 'n/a' ||
    s === 'na' ||
    s === 'none' ||
    s === 'unknown' ||
    s === 'test'
  );
}

function isProductJunk(data) {
  const blob = blobOf(data);
  const markers = [
    'cursor.com',
    'cursor.sh',
    'cursor team',
    'anysphere',
    'browser layout editor',
    'browser-based layout editor',
    'writing and fixing code faster',
    'try debug mode',
    'changelog/2-2',
    'dear developer',
    'firebase.google.com',
  ];
  if (markers.some((m) => blob.includes(m))) return true;
  if (isPlaceholderCaseNo(data.caseNo) && !blob.includes('regional trial court')) {
    return true;
  }
  return false;
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  if (!getApps().length) {
    const keyPath = path.join(__dirname, '..', 'serviceAccount.json');
    if (fs.existsSync(keyPath)) {
      initializeApp({
        credential: cert(require(keyPath)),
        projectId: 'jurislink-app',
      });
    } else {
      initializeApp({
        credential: applicationDefault(),
        projectId: 'jurislink-app',
      });
    }
  }
  const db = getFirestore();

  const hearings = await db.collection('hearings').get();
  const junkIds = [];
  let deletedHearings = 0;
  let deletedNotes = 0;
  let batch = db.batch();
  let ops = 0;

  const commitIfNeeded = async (force = false) => {
    if (!ops) return;
    if (!force && ops < 400) return;
    if (!dryRun) await batch.commit();
    batch = db.batch();
    ops = 0;
  };

  for (const doc of hearings.docs) {
    const data = doc.data() || {};
    if (!isProductJunk(data)) continue;
    junkIds.push(doc.id);
    console.log(dryRun ? 'DRY hearing' : 'DELETE hearing', doc.id, data.caseNo);
    if (!dryRun) {
      batch.delete(doc.ref);
      ops += 1;
      await commitIfNeeded();
    }
    deletedHearings += 1;
  }

  for (const hid of junkIds) {
    const snap = await db
      .collection('notifications')
      .where('hearingDocId', '==', hid)
      .get();
    for (const doc of snap.docs) {
      console.log(dryRun ? 'DRY notification' : 'DELETE notification', doc.id);
      if (!dryRun) {
        batch.delete(doc.ref);
        ops += 1;
        await commitIfNeeded();
      }
      deletedNotes += 1;
    }
  }

  const titleSnap = await db
    .collection('notifications')
    .where('title', '==', 'Court hearing / order — Court order')
    .get();
  for (const doc of titleSnap.docs) {
    console.log(dryRun ? 'DRY notification' : 'DELETE notification', doc.id);
    if (!dryRun) {
      batch.delete(doc.ref);
      ops += 1;
      await commitIfNeeded();
    }
    deletedNotes += 1;
  }

  if (!dryRun) await commitIfNeeded(true);
  console.log(
    dryRun
      ? `Dry run: ${deletedHearings} hearings, ${deletedNotes} notifications`
      : `Deleted ${deletedHearings} hearings, ${deletedNotes} notifications`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
