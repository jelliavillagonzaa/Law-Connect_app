# Email → Law Connect notifications

Court mail is ingested by **n8n**, not IMAP.

```text
n8n (Gmail / AI)
    → POST courtEmailIngest (X-Ingest-Secret)
    → Firestore `hearings` + `court_email_queue` (source: n8n)
    → in-app hearing notifications
```

## Setup

1. Deploy `courtEmailIngest`.
2. In n8n, POST to  
   `https://us-central1-jurislink-app.cloudfunctions.net/courtEmailIngest`  
   with header `X-Ingest-Secret` matching Firebase secret `INGEST_SECRET`.
3. Firestore `app_settings/email_ingest`: set `automationUserId` and optionally `defaultAttorneyId`.

IMAP poll, Gmail app passwords, and Python OCR are **not used**.

## Troubleshooting

- **401** — n8n secret does not match `INGEST_SECRET`.
- **No new Firestore docs** — n8n is not hitting this URL, or look at `source == n8n` (not `imap_inbox_…`).
- **200 skipped** — payload was empty or treated as promo; a `skipped` queue row is still written.
