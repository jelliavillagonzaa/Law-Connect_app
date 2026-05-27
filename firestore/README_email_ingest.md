# Firestore: `app_settings` / `email_ingest`

1. Open **Firebase Console → Firestore**.
2. Collection **`app_settings`**, document ID **`email_ingest`** (create if missing).
3. Add the fields from **`email_ingest.template.json`** in this folder.
   - Replace `REPLACE_WITH_FIREBASE_AUTH_UID` with a real user’s Firebase Auth UID.
   - Optional **`notifyUserIds`**: array of Firebase Auth UIDs to always notify when `court_email_queue` gets a row (e.g. extra staff).
   - Replace `pythonOcrUrl` with your deployed Python OCR base URL (no trailing slash), or remove the field if unused.

**`imapMailboxes`** can be:

- An **array** of strings: `["INBOX", "[Gmail]/Spam"]`
- Or a **single string** (comma-separated): `"INBOX,[Gmail]/Spam"`

Aliases also supported: `gmailImapMailboxes`, `GMAIL_IMAP_MAILBOXES`.

**`imapHost`** alias: `GMAIL_IMAP_HOST`.

Login credentials stay in **Firebase secrets** (`GMAIL_IMAP_USER`, `GMAIL_IMAP_PASSWORD`), not in Firestore.
