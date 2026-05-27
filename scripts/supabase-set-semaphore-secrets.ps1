# Set Semaphore SMS secrets on Supabase (Philippines).
# Usage:
#   .\scripts\supabase-set-semaphore-secrets.ps1 -ApiKey "YOUR_SEMAPHORE_API_KEY"
# Optional sender name (max 11 chars):
#   .\scripts\supabase-set-semaphore-secrets.ps1 -ApiKey "..." -SenderName "LawConnect"

param(
  [Parameter(Mandatory = $true)]
  [string]$ApiKey,
  [string]$SenderName = "",
  [string]$ProjectRef = "upevoqkiufiqgyfrepfg",
  [string]$FirebaseProjectId = "jurislink-app"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$cli = Join-Path $repoRoot "scripts\supabase-cli.ps1"
if (-not (Test-Path $cli)) {
  throw "Missing scripts\supabase-cli.ps1"
}

Write-Host "Setting Supabase secrets for project $ProjectRef ..." -ForegroundColor Cyan
& $cli secrets set --project-ref $ProjectRef "SEMAPHORE_API_KEY=$ApiKey" "FIREBASE_PROJECT_ID=$FirebaseProjectId"
if ($SenderName.Trim().Length -gt 0) {
  & $cli secrets set --project-ref $ProjectRef "SEMAPHORE_SENDER_NAME=$SenderName"
}

Write-Host "Deploying send-sms Edge Function ..." -ForegroundColor Cyan
& $cli functions deploy send-sms --project-ref $ProjectRef

Write-Host "Done. Restart Flutter app and test OTP SMS." -ForegroundColor Green
