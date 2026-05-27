# SMS Setup — Law Connect (Philippines)

The app sends SMS for **OTP codes**, welcome messages, and admin notifications.

## Choose ONE provider

### Option A — Semaphore (recommended for Philippines)

1. Create account: https://semaphore.co
2. Get your **API key** from the dashboard.
3. Load credits (SMS cost per message).

**Supabase Edge (fastest for the Flutter app):**

```powershell
cd c:\law_connect4
supabase link --project-ref upevoqkiufiqgyfrepfg
supabase secrets set SEMAPHORE_API_KEY=your_api_key_here
supabase secrets set FIREBASE_PROJECT_ID=jurislink-app
supabase functions deploy send-sms
```

**Firebase Cloud Function (backup queue):**

```powershell
firebase functions:config:set semaphore.api_key="your_api_key_here"
# Or for v2 params (already in code):
firebase functions:secrets:set TWILIO_ACCOUNT_SID
# Set env in Firebase console → Functions → onSmsRequestSend:
#   SEMAPHORE_API_KEY = your_api_key
firebase deploy --only functions:onSmsRequestSend,firestore:indexes
```

### Option B — Twilio (international)

```powershell
supabase secrets set TWILIO_ACCOUNT_SID=ACxxxx
supabase secrets set TWILIO_AUTH_TOKEN=xxxx
supabase secrets set TWILIO_FROM_NUMBER=+1xxxxxxxxxx
supabase secrets set FIREBASE_PROJECT_ID=jurislink-app
supabase functions deploy send-sms
```

Also set the same Twilio values as Firebase secrets and deploy `onSmsRequestSend`.

### Option C — Android phone gateway (no Twilio/Semaphore bill)

See `docs/SMS_WORKER.md` — run `sms-worker` on a PC with an SMS gateway app on your phone.

## Deploy Firestore index (required for sms-worker)

```powershell
firebase deploy --only firestore:indexes
```

## Test

1. Hot restart the Flutter app (Supabase must be configured in `lib/supabase/supabase_local_overrides.dart`).
2. Sign up with a real PH mobile number (`09XXXXXXXXX`).
3. Check Firestore → `sms_requests` — status should become `sent` within a few seconds.
4. If status stays `pending`, the server is not deployed or API key is missing.
5. If status is `failed`, read the `error` field on the document.

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| `pending` forever | Deploy `onSmsRequestSend` or run `sms-worker` |
| `Missing Twilio secrets` | Set Semaphore **or** Twilio (see above) |
| Supabase 500 on send-sms | Run `supabase secrets set` and `supabase functions deploy send-sms` |
| OTP email works, SMS no | SMS provider not configured — not an app bug |
