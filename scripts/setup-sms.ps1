# Law Connect — SMS setup helper (Semaphore or Twilio)
# Run from project root: .\scripts\setup-sms.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

Write-Host "=== Law Connect SMS Setup ===" -ForegroundColor Cyan
Write-Host ""

$useSemaphore = Read-Host "Use Semaphore for Philippines? (Y/n)"
if ($useSemaphore -eq "" -or $useSemaphore -eq "Y" -or $useSemaphore -eq "y") {
    $apiKey = Read-Host "Enter SEMAPHORE_API_KEY"
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Host "No API key entered. Exiting." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nDeploying Supabase send-sms with Semaphore..." -ForegroundColor Yellow
    supabase secrets set "SEMAPHORE_API_KEY=$apiKey" --project-ref upevoqkiufiqgyfrepfg
    supabase secrets set "FIREBASE_PROJECT_ID=jurislink-app" --project-ref upevoqkiufiqgyfrepfg
    supabase functions deploy send-sms --project-ref upevoqkiufiqgyfrepfg

    Write-Host "`nSet Firebase Function env (Console → Functions → onSmsRequestSend → Environment):" -ForegroundColor Yellow
    Write-Host "  SEMAPHORE_API_KEY = $apiKey"
    Write-Host ""
    Write-Host "Then run: firebase deploy --only functions:onSmsRequestSend,firestore:indexes" -ForegroundColor Green
} else {
    Write-Host "Twilio setup — run manually:" -ForegroundColor Yellow
    Write-Host "  supabase secrets set TWILIO_ACCOUNT_SID=..."
    Write-Host "  supabase secrets set TWILIO_AUTH_TOKEN=..."
    Write-Host "  supabase secrets set TWILIO_FROM_NUMBER=+..."
    Write-Host "  supabase functions deploy send-sms"
    Write-Host "  firebase functions:secrets:set TWILIO_*"
    Write-Host "  firebase deploy --only functions:onSmsRequestSend,firestore:indexes"
}

Write-Host "`nDone. Restart the Flutter app and test signup OTP SMS." -ForegroundColor Cyan
