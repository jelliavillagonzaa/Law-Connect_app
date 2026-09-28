/**
 * Delete leftover IMAP rows in court_email_queue (imap_inbox_* / imap_poll_*).
 * Keeps n8n documents. IMAP ingest is disabled.
 *
 *   node scripts/delete_imap_inbox_queue.js
 *   node scripts/delete_imap_inbox_queue.js --dry-run
 */
const { initializeApp, applicationDefault, getApps } = require('firebase-admin/app');
const { getFirestore, FieldPath } = require('firebase-admin/firestore');

function isImapQueueDoc(id, data) {
  const source = String(data.source ?? '').toLowerCase();
  if (id.toLowerCase().startsWith('imap_inbox_')) return true;
  if (id.toLowerCase().startsWith('imap_')) return true;
  if (source.startsWith('imap')) return true;
  if (source.includes('imap_poll')) return true;
  return false;
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  if (!getApps().length) {
    initializeApp({
      credential: applicationDefault(),
      projectId: 'jurislink-app',
    });
  }
  const db = getFirestore();
  const col = db.collection('court_email_queue');

  let deleted = 0;
  let kept = 0;
  let last = null;

  for (;;) {
    let q = col.orderBy(FieldPath.documentId()).limit(400);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    const batch = db.batch();
    let batchCount = 0;
    for (const doc of snap.docs) {
      last = doc;
      if (!isImapQueueDoc(doc.id, doc.data() || {})) {
        kept += 1;
        continue;
      }
      if (dryRun) {
        console.log('DRY', doc.id);
        deleted += 1;
        continue;
      }
      batch.delete(doc.ref);
      batchCount += 1;
      deleted += 1;
    }
    if (!dryRun && batchCount) await batch.commit();
    if (snap.size < 400) break;
  }

  console.log(
    dryRun
      ? `Dry run: would delete ${deleted} IMAP queue docs, keep ${kept}`
      : `Deleted ${deleted} IMAP queue docs, kept ${kept} others`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
