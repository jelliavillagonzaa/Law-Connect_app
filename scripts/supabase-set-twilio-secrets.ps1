# Sets all Twilio + Firebase secrets for Edge Function send-sms in ONE command.
# (PowerShell treats each line after Enter as a new command unless you use backticks.)
#
# Example:
#   .\scripts\supabase-set-twilio-secrets.ps1 `
#     -TwilioAccountSid "ACxxxxxxxx" `
#     -TwilioAuthToken "your_token" `
#     -TwilioFromNumber "+12603087830"
#
# Or one line:
#   .\scripts\supabase-set-twilio-secrets.ps1 -TwilioAccountSid "ACxx" -TwilioAuthToken "xx" -TwilioFromNumber "+12603087830"

param(
  [Parameter(Mandatory = $true)][string]$TwilioAccountSid,
  [Parameter(Mandatory = $true)][string]$TwilioAuthToken,
  [Parameter(Mandatory = $true)][string]$TwilioFromNumber,
  [string]$FirebaseProjectId = "jurislink-app"
)

$ErrorActionPreference = "Stop"
$cli = Join-Path $PSScriptRoot "supabase-cli.ps1"

function Normalize-Single([string]$value, [string]$label) {
  $v = $value.Trim()
  $half = [int]($v.Length / 2)
  if ($half -gt 0 -and $v.Substring(0, $half) -eq $v.Substring($half)) {
    Write-Host "  $label was duplicated — using first half only." -ForegroundColor Yellow
    $v = $v.Substring(0, $half)
  }
  return $v
}

$TwilioAccountSid = Normalize-Single $TwilioAccountSid "TWILIO_ACCOUNT_SID"
$TwilioAuthToken = Normalize-Single $TwilioAuthToken "TWILIO_AUTH_TOKEN"
$TwilioFromNumber = Normalize-Single $TwilioFromNumber "TWILIO_FROM_NUMBER"

if (-not $TwilioAccountSid.StartsWith("AC")) {
  throw "TWILIO_ACCOUNT_SID must start with AC"
}
if (-not $TwilioFromNumber.StartsWith("+")) {
  throw "TWILIO_FROM_NUMBER must be E.164 (start with +)"
}

& $cli secrets set `
  "TWILIO_ACCOUNT_SID=$TwilioAccountSid" `
  "TWILIO_AUTH_TOKEN=$TwilioAuthToken" `
  "TWILIO_FROM_NUMBER=$TwilioFromNumber" `
  "FIREBASE_PROJECT_ID=$FirebaseProjectId"

Write-Host "Done. Deploy with: .\scripts\supabase-cli.ps1 functions deploy send-sms"
