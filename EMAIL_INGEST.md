# Court email ingest (n8n → Cloud Functions)

n8n POSTs classified court mail to **`courtEmailIngest`**. The function writes `hearings` and `court_email_queue` (`source: "n8n"`).

**IMAP mailbox polling and OCR are removed.** Do not look for `imap_inbox_…` documents.

> **Google Calendar in n8n does not notify Law Connect.**  
> Use HTTP → `courtEmailIngest` (see [docs/N8N_LAWCONNECT_SETUP.md](docs/N8N_LAWCONNECT_SETUP.md)).

## Deploy

```bash
cd functions
npm install
npm run build
firebase functions:secrets:set INGEST_SECRET
firebase deploy --only functions:courtEmailIngest
```

URL: `https://us-central1-jurislink-app.cloudfunctions.net/courtEmailIngest`

## n8n HTTP node

- Method: **POST**
- Header: `X-Ingest-Secret: <INGEST_SECRET>`
  (or query `ingestSecret`, or JSON `ingestSecret`)
- JSON body, for example:

```json
{
  "subject": "Hearing notice",
  "text": "Plain text / OCR text from n8n",
  "caseNo": "optional",
  "clientName": "optional",
  "hearingDate": "optional",
  "hearingTime": "optional",
  "courtBranch": "optional"
}
```

`GET` on the same URL returns `{ "ok": true, "service": "courtEmailIngest" }`.

## Firestore

- **`hearings`** — `source: "n8n"` (main)
- **`court_email_queue`** — `source: "n8n"` (random ID, not `imap_inbox_…`)

Staff/attorney/admin may read `court_email_queue` (see `firestore.rules`). Writes are Admin SDK only.

## Local emulator

```bash
cd functions && npm run build
firebase emulators:start --only functions
```

`POST http://localhost:5001/jurislink-app/us-central1/courtEmailIngest` with the secret header.
