# SMS Worker (Android gateway) — Law Connect

Use this when you **cannot** use Twilio / Firebase Secrets (Blaze).  
This is a **PC worker** that watches Firestore `sms_requests` and sends SMS through an **Android phone** running an SMS gateway app.

## Architecture

```text
Law Connect App -> Firestore sms_requests (pending)
  -> SMS Worker (PC) polls + claims docs
  -> Android SMS Gateway HTTP API
  -> Phone sends real SMS (SIM load)
  -> Worker updates Firestore: sent/failed
```

## 1) Install dependencies

From project root:

```bash
cd sms-worker
npm install
```

## 2) Create a Firebase service account (for the worker)

Firebase Console → Project settings → Service accounts → **Generate new private key**.

Save the JSON file somewhere safe, for example:

```text
C:\law_connect4\secrets\serviceAccount.json
```

## 3) Pick an Android SMS gateway app

Requirements:
- Provides an **HTTP endpoint** you can call from your PC
- Can run in background (disable battery optimization)
- Supports an API token/key (optional but recommended)

## 4) Run the worker

Open PowerShell, then set env vars and run:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\law_connect4\secrets\serviceAccount.json"
$env:FIREBASE_PROJECT_ID="jurislink-app"
$env:SMS_GATEWAY_URL="http://<PHONE-IP>:<PORT>/send"
$env:SMS_GATEWAY_TOKEN=""  # optional
$env:SMS_WORKER_POLL_MS="2000"
$env:SMS_WORKER_BATCH="5"
cd C:\law_connect4\sms-worker
npm start
```

## 5) Test

Create a Firestore doc:

Collection: `sms_requests`

```json
{
  "to": "09XXXXXXXXX",
  "body": "Test SMS from Law Connect",
  "status": "pending",
  "createdBy": "<ANY_UID>"
}
```

The worker will normalize PH numbers:
- `09XXXXXXXXX` -> `+639XXXXXXXXX`

Then it will update the document to `sent` or `failed`.

## Security note

Service account keys give admin access. Keep them private and do not commit them.

