# Force SMS via Twilio only (clears Semaphore on Cloud Run so Twilio is used).
# Requires Firebase secrets: TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER
#
#   firebase functions:secrets:set TWILIO_ACCOUNT_SID
#   firebase functions:secrets:set TWILIO_AUTH_TOKEN
#   firebase functions:secrets:set TWILIO_FROM_NUMBER
#   firebase deploy --only functions:onSmsRequestSend
#   .\scripts\use-twilio-only.ps1

$ErrorActionPreference = "Stop"

Write-Host "Removing SEMAPHORE_API_KEY from onsmsrequestsend (Twilio will be used)..." -ForegroundColor Cyan
gcloud run services update onsmsrequestsend `
  --region=us-central1 `
  --project=jurislink-app `
  --remove-env-vars=SEMAPHORE_API_KEY,SEMAPHORE_SENDER_NAME

Write-Host "Done. Test OTP signup. Firestore provider should be 'twilio'." -ForegroundColor Green
