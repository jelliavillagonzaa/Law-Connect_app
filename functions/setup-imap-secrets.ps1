# Law Connect — enable Gmail IMAP polling for court email ingest (Cloud Functions).
# Run from PowerShell in the project root (c:\law_connect4) after: npm install -g firebase-tools
#
# Prerequisites:
# - Firebase project selected: firebase use <your-project-id>
# - Blaze plan (scheduled functions require it)
# - Gmail: 2-Step Verification + App Password (https://support.google.com/accounts/answer/185833)

Write-Host ""
Write-Host "=== Law Connect IMAP setup ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1) Set secrets (you will be prompted to paste values):" -ForegroundColor Yellow
Write-Host "   firebase functions:secrets:set GMAIL_IMAP_USER"
Write-Host "      -> full Gmail address that receives court mail, e.g. apaostaff@gmail.com"
Write-Host ""
Write-Host "   firebase functions:secrets:set GMAIL_IMAP_PASSWORD"
Write-Host "      -> 16-character Gmail App Password (not your normal password)"
Write-Host ""
Write-Host "   firebase functions:secrets:set INGEST_SECRET"
Write-Host "      -> random string; required for courtEmailIngest webhook and imapCourtEmailManual POST"
Write-Host ""
Write-Host "2) Firestore: create collection app_settings, document email_ingest"
Write-Host "   Copy fields from firestore/email_ingest.template.json (replace automationUserId with a real Auth UID)."
Write-Host ""
Write-Host "3) Deploy functions:" -ForegroundColor Yellow
Write-Host "   cd functions"
Write-Host "   npm install"
Write-Host "   npm run build"
Write-Host "   cd .."
Write-Host "   firebase deploy --only functions"
Write-Host ""
Write-Host "4) IMAP runs every 5 min (imapCourtEmailIngest). Test sooner:" -ForegroundColor Yellow
Write-Host "   POST to imapCourtEmailManual URL with header X-Ingest-Secret: <your INGEST_SECRET>"
Write-Host ""

$run = Read-Host "Run firebase functions:secrets:set GMAIL_IMAP_USER now? (y/N)"
if ($run -eq "y" -or $run -eq "Y") {
  firebase functions:secrets:set GMAIL_IMAP_USER
}
$run2 = Read-Host "Run firebase functions:secrets:set GMAIL_IMAP_PASSWORD now? (y/N)"
if ($run2 -eq "y" -or $run2 -eq "Y") {
  firebase functions:secrets:set GMAIL_IMAP_PASSWORD
}
$run3 = Read-Host "Run firebase functions:secrets:set INGEST_SECRET now? (y/N)"
if ($run3 -eq "y" -or $run3 -eq "Y") {
  firebase functions:secrets:set INGEST_SECRET
}

Write-Host ""
Write-Host "Done. Deploy with: firebase deploy --only functions" -ForegroundColor Green
Write-Host ""
