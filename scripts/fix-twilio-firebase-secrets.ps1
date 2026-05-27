# Fix corrupted Firebase/GCP Twilio secrets and force Twilio-only on Cloud Run.
#
# Common mistakes this fixes:
#   - TWILIO_ACCOUNT_SID set to placeholder (dddd...) instead of AC...
#   - TWILIO_AUTH_TOKEN or TWILIO_FROM_NUMBER pasted twice (duplicated string)
#
# Usage:
#   .\scripts\fix-twilio-firebase-secrets.ps1 `
#     -TwilioAccountSid "ACxxxxxxxx" `
#     -TwilioAuthToken "your_token" `
#     -TwilioFromNumber "+12603087830"
#
# Then test signup OTP; Firestore sms_requests should show provider=twilio.

param(
  [Parameter(Mandatory = $true)][string]$TwilioAccountSid,
  [Parameter(Mandatory = $true)][string]$TwilioAuthToken,
  [Parameter(Mandatory = $true)][string]$TwilioFromNumber,
  [string]$GcpProject = "jurislink-app"
)

$ErrorActionPreference = "Stop"

function Normalize-Single([string]$value, [string]$label) {
  $v = $value.Trim()
  $half = [int]($v.Length / 2)
  if ($half -gt 0 -and $v.Substring(0, $half) -eq $v.Substring($half)) {
    Write-Host "  $label was duplicated — using first half only." -ForegroundColor Yellow
    $v = $v.Substring(0, $half)
  }
  return $v
}

$sid = Normalize-Single $TwilioAccountSid "TWILIO_ACCOUNT_SID"
$tok = Normalize-Single $TwilioAuthToken "TWILIO_AUTH_TOKEN"
$from = Normalize-Single $TwilioFromNumber "TWILIO_FROM_NUMBER"

if (-not $sid.StartsWith("AC")) {
  throw "TWILIO_ACCOUNT_SID must start with AC (got: $($sid.Substring(0, [Math]::Min(6, $sid.Length)))...)"
}
if ($sid.Length -ne 34) {
  throw "TWILIO_ACCOUNT_SID should be 34 characters (got $($sid.Length))"
}
if (-not $from.StartsWith("+")) {
  throw "TWILIO_FROM_NUMBER must be E.164 (start with +)"
}
if ($tok.Length -lt 32) {
  throw "TWILIO_AUTH_TOKEN looks too short ($($tok.Length) chars)"
}

Write-Host "Verifying Twilio API..." -ForegroundColor Cyan
$pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${sid}:${tok}"))
try {
  $acc = Invoke-RestMethod -Uri "https://api.twilio.com/2010-04-01/Accounts/$sid.json" `
    -Headers @{ Authorization = "Basic $pair" }
  Write-Host "  OK: $($acc.friendly_name) ($($acc.status))" -ForegroundColor Green
} catch {
  throw "Twilio rejected credentials. Check Account SID and Auth Token in Twilio Console."
}

Write-Host "Updating GCP secrets..." -ForegroundColor Cyan
gcloud config set project $GcpProject | Out-Null
$sid | gcloud secrets versions add TWILIO_ACCOUNT_SID --data-file=- | Out-Null
$tok | gcloud secrets versions add TWILIO_AUTH_TOKEN --data-file=- | Out-Null
$from | gcloud secrets versions add TWILIO_FROM_NUMBER --data-file=- | Out-Null
Write-Host "  Secrets version 2+ created." -ForegroundColor Green

Write-Host "Removing Semaphore from Cloud Run (Twilio only)..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "use-twilio-only.ps1")

Write-Host "Deploying onSmsRequestSend..." -ForegroundColor Cyan
Push-Location (Split-Path -Parent $PSScriptRoot)
firebase deploy --only functions:onSmsRequestSend
Pop-Location

Write-Host ""
Write-Host "Done. Trial accounts can only SMS verified numbers." -ForegroundColor Cyan
Write-Host "Verify your PH mobile at: https://console.twilio.com/us1/develop/phone-numbers/manage/verified" -ForegroundColor Cyan
Write-Host "Enable Philippines: Messaging -> Settings -> Geo permissions" -ForegroundColor Cyan
