# Email → AI → Law Connect notifications

You can **forward or send court mail (with PDF) to your staff Gmail** instead of opening the app to upload. The backend already polls that inbox, OCRs attachments, extracts hearing info, and writes to `court_email_queue`.

## What this project does now

1. **IMAP poll** (`imapCourtEmailIngest`, every 5 minutes) signs into the mailbox configured by secrets `GMAIL_IMAP_USER` / `GMAIL_IMAP_PASSWORD` (use an [App Password](https://support.google.com/accounts/answer/185833) if 2FA is on).
2. **Pipeline** (`courtEmailPipeline`) runs rules + optional OpenAI, matches cases, and may create calendar events.
3. **Alerts** (new): when a row is created in `court_email_queue`, Cloud Function **`onCourtEmailQueueNotify`**:
   - Adds documents to `notifications` for each recipient (in-app bell).
   - Sends **FCM** to users who have `fcmToken` on their `users/{uid}` document.

Recipients are deduplicated from:

- `assignedTo` (matched attorney)
- `clientId` (matched client user, if any)
- `defaultAttorneyId` and `automationUserId` from `app_settings/email_ingest`
- **All staff** in `users` with `role == "staff"` and `assignedAttorneyId` equal to any of: `assignedTo`, `defaultAttorneyId`, or `automationUserId` (so staff see the same court-email alerts as their attorney)
- `notifyUserIds` (optional array of Firebase Auth UIDs) for extra staff/attorneys

## Troubleshooting: “I sent email but got no notification”

1. **The mail must land in the inbox that IMAP uses** — not only a display name like “Staff”. The **To** address must be the same Gmail as secret `GMAIL_IMAP_USER` (e.g. `apaostaff@gmail.com`). Sending from your phone to yourself in another mailbox will not be picked up by that poll.
2. **Firestore `app_settings/email_ingest`** — set at least **`automationUserId`** *or* **`defaultAttorneyId`** (or add **`notifyUserIds`**) so the notification function has UIDs to write to. If all of those are empty and the case does not match an attorney, **no push** is sent.
3. **`fcmToken`** — the recipient user must have opened the app while logged in so `users/{uid}.fcmToken` exists.
4. **Deploy** — after code changes, run `firebase deploy --only functions` so `imapCourtEmailIngest`, `onCourtEmailQueueNotify`, etc. are live.
5. **Timing** — scheduled IMAP runs about **every 5 minutes**; wait after sending, or call the manual HTTP trigger with `X-Ingest-Secret` if you configured it.
6. **Check Firestore** — if `court_email_queue` gets a new document but you still see no notification, check Cloud Logging for `courtEmailNotify: no recipient UIDs` or FCM errors.

## Pointing it at `apaostaff@gmail.com`

1. Deploy functions: `firebase deploy --only functions` (from `functions/` after `npm run build`).
2. Set secrets so **IMAP user is that Gmail address**:
   - `GMAIL_IMAP_USER` = `apaostaff@gmail.com`
   - `GMAIL_IMAP_PASSWORD` = Gmail app password (not your normal password).
3. In Firestore document **`app_settings/email_ingest`**, set at least:
   - `automationUserId`: Firebase Auth UID of the staff user that “owns” automation (must match a real `users/{uid}` doc for notifications).
   - `defaultAttorneyId` (optional): fallback attorney UID when the case cannot be matched.
   - `allowedFromDomains` (optional): restrict which senders are processed; **empty array = allow all** (see `firestoreResolve.ts`).
   - `pythonOcrUrl` (optional): URL of your deployed Python OCR agent for heavy PDFs.

## App side

- Users must **log in once** so `fcmToken` is saved on `users/{uid}` (already done in `auth_service.dart`).
- **`onNotificationRequestSend`** processes the existing Flutter pattern of writing to `notification_requests` and sends FCM.

## Flow (summary)

```text
Mail app → apaostaff@gmail.com (+ PDF)
    → IMAP poll (5 min)
    → OCR / extract / queue
    → Firestore `court_email_queue` + `notifications` + FCM
    → User opens Law Connect → bell shows unread; optional push if token present
```
