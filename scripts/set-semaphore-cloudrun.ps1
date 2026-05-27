# Set Semaphore API key on the SMS Cloud Function (required for PH SMS delivery).
# Usage:
#   .\scripts\set-semaphore-cloudrun.ps1 -ApiKey "YOUR_SEMAPHORE_API_KEY"
# Optional approved sender (max 11 chars):
#   .\scripts\set-semaphore-cloudrun.ps1 -ApiKey "..." -SenderName "LawConnect"

param(
  [Parameter(Mandatory = $true)]
  [string]$ApiKey,
  [string]$SenderName = "",
  [string]$ProjectId = "jurislink-app",
  [string]$Region = "us-central1",
  [string]$Service = "onsmsrequestsend"
)

$ErrorActionPreference = "Stop"

$vars = "SEMAPHORE_API_KEY=$ApiKey"
if ($SenderName.Trim().Length -gt 0) {
  $vars += ",SEMAPHORE_SENDER_NAME=$($SenderName.Trim())"
}

Write-Host "Updating Cloud Run service $Service ..." -ForegroundColor Cyan
gcloud run services update $Service `
  --region=$Region `
  --project=$ProjectId `
  --update-env-vars=$vars

Write-Host "Done. Test signup OTP and check Firestore sms_requests (status=sent, providerMessageId=number)." -ForegroundColor Green
