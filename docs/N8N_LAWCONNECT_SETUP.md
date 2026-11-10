# n8n → Law Connect (calendar + push)

Law Connect does **not** read Google Calendar.  
Court mail must write a **`hearings`** document (via **`courtEmailIngest`**), then:

- **App calendar** shows the hearing overlay  
- **Push + SMS** go to attorney / staff / matched clients  

## Problem you hit

| n8n node | Result |
|----------|--------|
| **Create a calendar event** (Google) | Event in Google Calendar only — **no** Law Connect push/calendar |
| **HTTP → courtEmailIngest** or Firestore `hearings` | App calendar + push |

## Fix in n8n (do this)

1. Open workflow **Gmail Read Test** (or your court-mail flow).
2. **Disable or delete** the **Create a calendar event** node (Google Calendar).
3. After **Message a model** (AI), add / keep an **HTTP Request** node:

| Setting | Value |
|---------|--------|
| Method | `POST` |
| URL | `https://us-central1-jurislink-app.cloudfunctions.net/courtEmailIngest` |
| Header | `X-Ingest-Secret` = your `INGEST_SECRET` |
| Body | JSON (see below) |

4. Connect: **Message a model** → **HTTP Request (ingest)** → **Mark a message as read**.
5. Keep **Create a document (Firestore)** only if it writes collection **`hearings`** with `hearingDate` / `caseNo` / `fullText`. Prefer **HTTP ingest** (one path).
6. Workflow **Published / Active**.
7. Deploy functions if not yet:  
   `firebase deploy --only functions:courtEmailIngest,functions:onHearingActivityCreated`

## JSON body example

Map fields from the AI / OCR nodes:

```json
{
  "subject": "{{ $json.subject }}",
  "text": "{{ $json.fullText || $json.text || $json.ocrText }}",
  "caseNo": "{{ $json.caseNo }}",
  "caseTitle": "{{ $json.caseTitle }}",
  "clientName": "{{ $json.clientName }}",
  "hearingDate": "{{ $json.hearingDate }}",
  "hearingTime": "{{ $json.hearingTime }}",
  "courtBranch": "{{ $json.courtBranch || $json.location }}"
}
```

Adjust expressions to match your **Edit Fields** / AI output keys.  
`hearingDate` should look like `October 28, 2026` so the push shows **Date:** first.

## Who gets push

After ingest (with staff included):

- Active **attorney** users  
- Active **staff** (e.g. `apaostaff@gmail.com`)  
- Active **admin**  
- Matched **clients** (by party name)

Staff must be logged into the **Law Connect app** once (FCM token) and have a phone on profile for SMS.

## Test

1. Send any Gmail → monitored inbox (**Gmail account 4** / `apaostaff@…`).
2. n8n **Executions** → HTTP ingest node = **200** `{ ok: true, hearingId: "…" }`.
3. Firebase → `hearings` → new doc with `hearingDate`.
4. App → Calendar (hearing day) + push tray with **Date:** line.

## Do not

- Rely on Google Calendar for Law Connect reminders  
- Filter Gmail Trigger with `from:` (blocks other senders)  
- Expect push if only Calendar node succeeded  
