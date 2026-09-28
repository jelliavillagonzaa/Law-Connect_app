#!/usr/bin/env node

const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');

async function deleteCollection(db, collectionPath, batchSize = 500) {
  const collectionRef = db.collection(collectionPath);
  while (true) {
    const snapshot = await collectionRef.limit(batchSize).get();
    if (snapshot.empty) break;
    const batch = db.batch();
    const docs = snapshot.docs;
    for (const doc of docs) {
      // delete subcollections recursively
      const subcols = await doc.ref.listCollections();
      for (const sub of subcols) {
        await deleteCollection(db, sub.path, batchSize);
      }
      batch.delete(doc.ref);
    }
    await batch.commit();
    console.log(`Deleted ${docs.length} documents from ${collectionPath}`);
  }
}

async function main() {
  const args = process.argv.slice(2);
  let keyPath = null;
  let collection = null;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if ((a === '--key' || a === '-k') && args[i + 1]) {
      keyPath = args[i + 1];
      i++;
    } else if ((a === '--collection' || a === '-c') && args[i + 1]) {
      collection = args[i + 1];
      i++;
    }
  }

  if (!keyPath || !collection) {
    console.error('Usage: node delete_court_email_queue.js --key path/to/serviceAccount.json --collection collection_name');
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
    console.log('Starting recursive delete of collection:', collection);
    await deleteCollection(db, collection);
    console.log('Collection delete completed:', collection);
    process.exit(0);
  } catch (e) {
    console.error('Error deleting collection:', e);
    process.exit(1);
  }
}

main();
