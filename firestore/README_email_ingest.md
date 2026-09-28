# Firestore: `app_settings` / `email_ingest`

Used by **n8n → `courtEmailIngest`** (not IMAP).

1. Open **Firebase Console → Firestore**.
2. Collection **`app_settings`**, document ID **`email_ingest`**.
3. Fields from **`email_ingest.template.json`**:
   - **`automationUserId`**: Firebase Auth UID of the staff/bot user.
   - **`defaultAttorneyId`** (optional): fallback attorney UID.
   - **`notifyUserIds`** (optional): extra UIDs to notify.

IMAP / Python OCR is removed. Court mail comes from n8n posting to `courtEmailIngest`.
