# SMS notifications (Twilio) — Law Connect

This repo uses a **Firestore queue → Cloud Function** pattern for SMS, similar to `notification_requests` (FCM).

## How it works

1. App (or admin tooling) writes a document to **`sms_requests`**:
   - `to`: phone number in **E.164** format (example PH: `+639XXXXXXXXX`)
   - `body`: SMS content
   - `status`: `"pending"`
   - `createdBy`: Firebase Auth UID of the requester
2. Cloud Function **`onSmsRequestSend`** triggers on create and sends SMS through **Twilio**.
3. Function updates the request doc to:
   - `status`: `"sent"` or `"failed"`
   - `error` (when failed)
   - `providerMessageId` (when sent)

## Setup (required)

### 1) Twilio account
- Create a Twilio account
- Buy/configure an SMS-capable phone number (the **From** number)

### 2) Set Firebase Functions secrets

Run these from your project root:

```bash
firebase functions:secrets:set TWILIO_ACCOUNT_SID
firebase functions:secrets:set TWILIO_AUTH_TOKEN
firebase functions:secrets:set TWILIO_FROM_NUMBER
```

Notes:
- `TWILIO_FROM_NUMBER` must be in E.164 format (example: `+1...` or `+63...`).

### 3) Deploy

```bash
cd functions
npm install
npm run build
cd ..
firebase deploy --only functions,firestore:indexes
```

## Test quickly

After deploy, run the app while logged in, then create a test document in Firestore:

Collection: `sms_requests`

```json
{
  "to": "+639XXXXXXXXX",
  "body": "Test SMS from Law Connect",
  "status": "pending",
  "createdBy": "<YOUR_LOGGED_IN_UID>"
}
```

You should see the function update that doc to `sent` or `failed`.

