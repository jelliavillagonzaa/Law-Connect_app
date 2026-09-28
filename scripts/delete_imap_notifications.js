#!/usr/bin/env node
/**
 * Delete Firestore notifications created by IMAP / court email ingest.
 *
 * Usage:
 *   node scripts/delete_imap_notifications.js --key path/to/serviceAccount.json
 *   node scripts/delete_imap_notifications.js --key path/to/serviceAccount.json --dry-run
 */

const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getFirestore, FieldPath } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');

function isImapNotification(data) {
  const type = String(data.type ?? '').toLowerCase();
  const title = String(data.title ?? '').toLowerCase().trim();
  const hearingDocId = String(data.hearingDocId ?? '').trim();
  const queueDocId = String(
    data.queueDocId ?? data.queuedDocId ?? '',
  ).toLowerCase();

  if (queueDocId.includes('imap')) return true;
  if (type === 'court_email_ingest') return true;
  if (type.startsWith('court_') && !type.includes('hearing')) return true;

  if (
    hearingDocId === '' &&
    (title === 'new court notice' ||
      (title.startsWith('new court notice') &&
        !title.includes('court hearings')))
  ) {
    return true;
  }

  return false;
}

async function deleteImapNotifications(db, { dryRun = false, batchSize = 450 } = {}) {
  const collectionRef = db.collection('notifications');
  let lastDoc = null;
  let scanned = 0;
  let matched = 0;
  let deleted = 0;

  while (true) {
    let query = collectionRef.orderBy(FieldPath.documentId()).limit(batchSize);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const toDelete = [];
    for (const doc of snapshot.docs) {
      scanned += 1;
      if (!isImapNotification(doc.data())) continue;
      matched += 1;
      toDelete.push(doc.ref);
    }

    if (!dryRun && toDelete.length > 0) {
      const batch = db.batch();
      for (const ref of toDelete) batch.delete(ref);
      await batch.commit();
      deleted += toDelete.length;
      console.log(`Deleted ${toDelete.length} (total deleted: ${deleted})`);
    } else if (dryRun && toDelete.length > 0) {
      deleted += toDelete.length;
      for (const ref of toDelete) {
        console.log(`[dry-run] would delete: ${ref.id}`);
      }
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < batchSize) break;
  }

  return { scanned, matched, deleted, dryRun };
}

async function main() {
  const args = process.argv.slice(2);
  let keyPath = null;
  let dryRun = false;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if ((a === '--key' || a === '-k') && args[i + 1]) {
      keyPath = args[i + 1];
      i++;
    } else if (a === '--dry-run') {
      dryRun = true;
    }
  }

  if (!keyPath) {
    console.error(
      'Usage: node delete_imap_notifications.js --key path/to/serviceAccount.json [--dry-run]',
    );
    process.exit(1);
  }

  keyPath = path.resolve(keyPath);
  if (!fs.existsSync(keyPath)) {
    console.error('Service account key not found at', keyPath);
    process.exit(1);
  }

  const serviceAccount = require(keyPath);
  if (getApps().length === 0) {
    initializeApp({ credential: cert(serviceAccount) });
  }
  const db = getFirestore();

  try {
    console.log(
      dryRun
        ? 'Dry run — scanning notifications for IMAP / court_email_ingest rows...'
        : 'Deleting IMAP / court_email_ingest notifications...',
    );
    const result = await deleteImapNotifications(db, { dryRun });
    console.log(
      `Done. Scanned ${result.scanned}, matched ${result.matched}, ${
        dryRun ? 'would delete' : 'deleted'
      } ${result.deleted}.`,
    );
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(1);
  }
}

main();
