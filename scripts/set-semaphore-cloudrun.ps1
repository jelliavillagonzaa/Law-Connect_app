# Set Semaphore API key on SMS + hearing Cloud Functions.
# Usage:
#   .\scripts\set-semaphore-cloudrun.ps1 -ApiKey "YOUR_SEMAPHORE_API_KEY"
# Optional approved sender (max 11 chars):
#   .\scripts\set-semaphore-cloudrun.ps1 -ApiKey "..." -SenderName "LAWCONNECT"
#
# Preferred (also updates functions/.env.jurislink-app at deploy):
#   Put the key in functions/.env.jurislink-app then:
#   firebase deploy --only functions:onHearingActivityCreated,functions:onHearingActivityUpdated,functions:hearingReminderScheduler,functions:sendSemaphoreSms,functions:onSmsRequestSend

param(
  [Parameter(Mandatory = $true)]
  [string]$ApiKey,
  [string]$SenderName = "LAWCONNECT",
  [string]$ProjectId = "jurislink-app",
  [string]$Region = "us-central1",
  [string[]]$Services = @(
    "onsmsrequestsend",
    "sendsemaphoresms",
    "onhearingactivitycreated",
    "onhearingactivityupdated",
    "hearingreminderscheduler"
  )
)

$ErrorActionPreference = "Stop"

$gcloud = Get-Command gcloud -ErrorAction SilentlyContinue
if (-not $gcloud) {
  throw "gcloud is not in PATH. Set SEMAPHORE_API_KEY in functions/.env.jurislink-app and run firebase deploy --only functions:onHearingActivityCreated,functions:onHearingActivityUpdated,functions:hearingReminderScheduler,functions:sendSemaphoreSms,functions:onSmsRequestSend"
}

$vars = "SEMAPHORE_API_KEY=$ApiKey"
if ($SenderName.Trim().Length -gt 0) {
  $vars += ",SEMAPHORE_SENDER_NAME=$($SenderName.Trim())"
}

foreach ($Service in $Services) {
  Write-Host "Updating Cloud Run service $Service ..." -ForegroundColor Cyan
  gcloud run services update $Service `
    --region=$Region `
    --project=$ProjectId `
    --update-env-vars=$vars
}

Write-Host "Done. Next hearing SMS should also arrive from sender LAWCONNECT (Semaphore), not PhilSMS only." -ForegroundColor Green
