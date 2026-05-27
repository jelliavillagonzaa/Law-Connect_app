# Court email ingest (Cloud Functions)

Server-side automation: an HTTP webhook (and/or Gmail Pub/Sub) receives court email payloads, extracts text from the **email body** (subject + text/plain + stripped HTML) and also extracts text from **PDF** and **image attachments** (PDF text via `pdf-parse`; image OCR via OpenAI vision when `OPENAI_API_KEY` is set), parses hearing fields (rules + optional OpenAI), then either **creates** a `calendar_events` hearing (same shape as the Flutter app) or **queues** a row in `court_email_queue` for review.

**Calendar UI is unchanged** — events appear on the existing staff calendar stream.

## Deploy

1. **Install & build**
   ```bash
   cd functions
   npm install
   npm run build
   ```

2. **Secret (required)** — shared with your email forwarder (Power Automate, Zapier, custom server):
   ```bash
   firebase functions:secrets:set INGEST_SECRET
   ```

3. **Firestore config (required)** — create document `app_settings` / **`email_ingest`** (see `firestore/email_ingest.template.json` for a starter JSON):
   | Field | Type | Description |
   |--------|------|-------------|
   | `automationUserId` | string | **Firebase Auth UID** of a real user (e.g. a “Court bot” staff account). Used as `createdBy` on `calendar_events` and for notification copy. |
   | `pythonOcrUrl` | string (optional) | Base URL of your Python OCR service (PDF/images). Required for attachment OCR. |
   | `imapHost` | string (optional) | IMAP host; if omitted, uses deploy param `GMAIL_IMAP_HOST` (default `imap.gmail.com`). |
   | `imapMailboxes` | string[] **or** comma-separated string (optional) | Folders to poll, e.g. `["INBOX","[Gmail]/Spam"]`. Aliases: `gmailImapMailboxes`, `GMAIL_IMAP_MAILBOXES`. If omitted, uses deploy param `GMAIL_IMAP_MAILBOXES` or built-in default. |
   | `defaultAttorneyId` | string (optional) | Used when no case match sets an attorney. |
   | `autoCreateMinConfidence` | `"high"` \| `"medium"` | Default `high`: only auto-schedule when date **and** attorney are resolved. |
   | `allowedFromDomains` | string[] (optional) | If non-empty, `from` must contain one of these substrings (lowercase). |

   **Secrets (not in Firestore)** — still required for IMAP login:
   ```bash
   firebase functions:secrets:set GMAIL_IMAP_USER
   firebase functions:secrets:set GMAIL_IMAP_PASSWORD
   ```

4. **Optional LLM** (server-only key) — either:
   - Set param when deploying:  
     `firebase deploy --only functions --params OPENAI_API_KEY=sk-...`  
     (or use `.env` / GCP console env var `OPENAI_API_KEY` on the function)

5. **Deploy function**
   ```bash
   firebase deploy --only functions:courtEmailIngest
   ```

6. **URL** — after deploy, use the HTTPS URL shown for `courtEmailIngest` (e.g. `https://us-central1-PROJECT.cloudfunctions.net/courtEmailIngest`).

## Webhook contract

`POST` with header:

```http
X-Ingest-Secret: <same as INGEST_SECRET>
Content-Type: application/json
```

JSON body:

```json
{
  "messageId": "optional-provider-id",
  "from": "notices@court.example",
  "to": "hearings@yourfirm.com",
  "subject": "Hearing notice",
  "text": "Plain text body",
  "html": "<optional html>",
  "attachments": [
    {
      "filename": "order.pdf",
      "contentType": "application/pdf",
      "dataBase64": "<base64>"
    }
  ]
}
```

Note: `attachments` are optional, but when provided:
- PDF text is extracted server-side.
- Images are OCRed with OpenAI vision (if `OPENAI_API_KEY` is configured).

You may put the secret in the body instead: `"ingestSecret": "..."` (header preferred).

### Microsoft Graph (subscription validation)

`GET` with query `?validationToken=...` returns the token as **plain text** (required once when creating a subscription). Delivering parsed email to this same URL still requires you to transform Graph’s payload into the JSON shape above (recommended: **Logic Apps / Power Automate**).

### Gmail (automatic via IMAP)

This repo uses **IMAP polling** (scheduled Cloud Function) instead of Gmail API + Pub/Sub.

1. Enable **2-Step Verification** on the Google account and create a Gmail **App Password** for IMAP.
2. Set Firebase Functions secrets:
   ```bash
   firebase functions:secrets:set GMAIL_IMAP_USER
   firebase functions:secrets:set GMAIL_IMAP_PASSWORD
   ```
   (Use the full Gmail address and the 16-character app password.)
3. Optional: set `GMAIL_IMAP_HOST` / `GMAIL_IMAP_MAILBOXES` when deploying — **or** put the same values in Firestore `email_ingest` as **`imapHost`** and **`imapMailboxes`** (Firestore wins when set).
4. Create/update **`app_settings/email_ingest`** in Firestore (see `firestore/email_ingest.template.json`): at minimum **`automationUserId`**; add **`pythonOcrUrl`**, **`imapHost`**, **`imapMailboxes`** as needed.
5. Deploy:
   ```bash
   firebase deploy --only functions
   ```
6. The scheduled function **`imapCourtEmailIngest`** runs every **5 minutes**, fetches **unread** messages from **INBOX** and **Spam** (Gmail IMAP folder **`[Gmail]/Spam`**), runs PDF/image OCR via your `pythonOcrUrl`, then marks messages **read** after successful OCR (same behavior as before). It writes to `court_email_queue` (with `source` like `imap_poll_inbox` / `imap_poll_spam`) and may auto-create calendar events per settings.

   Override folders with Firestore **`imapMailboxes`** or deploy param **`GMAIL_IMAP_MAILBOXES`** (comma-separated), e.g. `INBOX,[Gmail]/Spam` (default).

**Manual test trigger** (optional): `POST` to **`imapCourtEmailManual`** with header `X-Ingest-Secret: <INGEST_SECRET>` to run one poll immediately.

## Behavior

1. Concatenates `subject`, `text`, stripped `html` plus extracted text from PDF attachments (server-side) and OCR text from image attachments (OpenAI vision when configured).
2. **Rules** extraction (`extractRules.ts`) — aligned with app heuristics.
3. If `OPENAI_API_KEY` is set, **merges** JSON fields from `gpt-4o-mini`.
4. Resolves **case** (first 200 `cases` docs — tune for production) and **attorney** (`case.attorneyId` or `defaultAttorneyId`).
5. **Confidence**
   - `high`: hearing date + attorney  
   - `medium`: date, no attorney  
   - `low`: no date  
6. **Auto-create** when `autoCreateMinConfidence` allows and confidence is sufficient **and** `assignedTo` and `hearingDateTime` are set — writes:
   - `calendar_events`
   - `notifications` (attorney + staff + automation user, same pattern as app)
   - `calendar_event_reminders` / `hearing_notifications` when applicable
   - `activity_logs`, `system_logs`
7. Otherwise appends **`court_email_queue`** with `status: pending_review` and the parsed fields.

## Firestore: `court_email_queue` documents

Staff/attorney/admin may **read** (see `firestore.rules`). Only the **Admin SDK** (this function) can write — add a small review screen in the app later if desired.

## Security

- Rotate `INGEST_SECRET` if leaked.
- Use `allowedFromDomains` to restrict senders.
- Do **not** put OpenAI keys in the Flutter app; only in function config / GCP.

## Local emulator

```bash
cd functions && npm run build
firebase emulators:start --only functions
```

Call `http://localhost:5001/<project>/us-central1/courtEmailIngest` with the secret header (set secret for emulator per Firebase docs).
