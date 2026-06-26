# Fix Android login: "Requests from this Android client application ... are blocked"
# Web works without this; Android requires YOUR debug SHA-1 in Firebase + Google Cloud.
#
# Run from repo root:  .\scripts\fix_mobile_firebase.ps1
# You must be signed into the Google account that OWNS the jurislink-app Firebase project.

$ErrorActionPreference = "Stop"
$project = "jurislink-app"
$projectNumber = "969711743833"
$androidKeyId = "b8decc18-b47c-45b0-8965-dec694f97294"
$package = "com.example.jurislink_app"
$appId = "1:969711743833:android:12db52dbd2114b941e1248"
$debugKeystore = Join-Path $env:USERPROFILE ".android\debug.keystore"

function Get-KeystoreSha($label) {
  if (-not (Test-Path $debugKeystore)) {
    Write-Host "  $label keystore not found at $debugKeystore" -ForegroundColor Red
    return $null
  }
  $out = & keytool -list -v -keystore $debugKeystore -alias androiddebugkey -storepass android -keypass android 2>&1
  $sha1Line = $out | Select-String -Pattern "SHA1:\s*(.+)" | Select-Object -First 1
  $sha256Line = $out | Select-String -Pattern "SHA256:\s*(.+)" | Select-Object -First 1
  if (-not $sha1Line) { return $null }
  $sha1 = ($sha1Line.Matches[0].Groups[1].Value -replace ":", "").ToLower()
  $sha256 = if ($sha256Line) { ($sha256Line.Matches[0].Groups[1].Value -replace ":", "").ToLower() } else { "" }
  return @{ Sha1 = $sha1; Sha256 = $sha256; Sha1Display = $sha1Line.Matches[0].Groups[1].Value.Trim() }
}

Write-Host ""
Write-Host "=== Android Firebase login fix (jurislink-app) ===" -ForegroundColor Cyan
Write-Host ""

$fp = Get-KeystoreSha "Debug"
if (-not $fp) {
  Write-Host "Could not read debug.keystore. Install Java/keytool and run Flutter once to create it." -ForegroundColor Red
  exit 1
}

Write-Host "This PC debug certificate:" -ForegroundColor Yellow
Write-Host "  SHA-1:   $($fp.Sha1Display)"
Write-Host "  Package: $package"
Write-Host ""

# Check whether firebase CLI can see the project (correct Google account).
$canUseCli = $false
try {
  $projects = firebase projects:list --json 2>$null | ConvertFrom-Json
  $canUseCli = $null -ne ($projects.result | Where-Object { $_.projectId -eq $project })
} catch {
  $canUseCli = $false
}

if (-not $canUseCli) {
  Write-Host "Firebase CLI is NOT signed into the owner of '$project'." -ForegroundColor Yellow
  Write-Host "Your CLI only sees other projects. Use the Gmail that created jurislink-app:" -ForegroundColor Yellow
  Write-Host "  firebase login" -ForegroundColor White
  Write-Host "  (pick the account that owns jurislink-app, not your personal/other Gmail)" -ForegroundColor White
  Write-Host ""
  Write-Host "Then do these steps MANUALLY in the browser:" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "1) Firebase Console - add fingerprint" -ForegroundColor Green
  Write-Host "   https://console.firebase.google.com/project/$project/settings/general"
  Write-Host "   Your apps -> Android ($package) -> Add fingerprint"
  Write-Host "   Paste SHA-1: $($fp.Sha1Display)"
  if ($fp.Sha256) {
    Write-Host "   Also add SHA-256 from keytool output above."
  }
  Write-Host "   Download google-services.json -> replace android/app/google-services.json"
  Write-Host ""
  Write-Host "2) Google Cloud - allow this PC on the Android API key" -ForegroundColor Green
  Write-Host "   https://console.cloud.google.com/apis/credentials?project=$project"
  Write-Host "   Open key ending in ... (Android key for Firebase)"
  Write-Host "   Application restrictions -> Android apps -> Add item"
  Write-Host "   Package: $package"
  Write-Host "   SHA-1:   $($fp.Sha1Display)"
  Write-Host "   Save. (If still blocked, set restrictions to None temporarily to confirm.)"
  Write-Host ""
  Write-Host "3) Rebuild on device" -ForegroundColor Green
  Write-Host "   Uninstall app from phone, then: flutter clean && flutter run"
  Write-Host ""
  exit 0
}

Write-Host "Registering SHA-1 on Firebase Android app..." -ForegroundColor Cyan
firebase apps:android:sha:create $appId $fp.Sha1 --project $project

if (Get-Command gcloud -ErrorAction SilentlyContinue) {
  Write-Host "Allowing package + SHA on Google Cloud Android API key..." -ForegroundColor Cyan
  gcloud services api-keys update `
    "projects/$projectNumber/locations/global/keys/$androidKeyId" `
    "--allowed-application=sha1_fingerprint=$($fp.Sha1),package_name=$package" `
    --project $project
} else {
  Write-Host "gcloud not installed - add SHA-1 to API key manually:" -ForegroundColor Yellow
  Write-Host "  https://console.cloud.google.com/apis/credentials?project=$project"
  Write-Host "  Package: $package  SHA-1: $($fp.Sha1Display)"
}

Write-Host ""
Write-Host "Re-download google-services.json from Firebase and replace android/app/google-services.json" -ForegroundColor Yellow
Write-Host "Then: uninstall app on phone, flutter clean, flutter run" -ForegroundColor Green
Write-Host ""
