# One-time fixes for Android login (DEVELOPER_ERROR / API key).
# Run from repo root. Requires gcloud logged in with access to jurislink-app.

$ErrorActionPreference = "Stop"
$project = "jurislink-app"
$projectNumber = "969711743833"
$androidKeyId = "b8decc18-b47c-45b0-8965-dec694f97294"
$package = "com.example.jurislink_app"
$sha1 = "073308dba8e38f9397e6f76815797af260770c04"
$appId = "1:969711743833:android:12db52dbd2114b941e1248"
$appCheckDebugToken = "c4e8a1f2-6d3b-4f9e-a7c2-010203040506"

Write-Host "Registering SHA-1 on Firebase Android app..." -ForegroundColor Cyan
firebase apps:android:sha:create $appId $sha1 --project $project

Write-Host "Allowing package + SHA on Google Cloud Android API key..." -ForegroundColor Cyan
gcloud services api-keys update `
  "projects/$projectNumber/locations/global/keys/$androidKeyId" `
  "--allowed-application=sha1_fingerprint=$sha1,package_name=$package" `
  --project $project

Write-Host ""
Write-Host "App Check debug token (add in Firebase Console if login still fails):" -ForegroundColor Yellow
Write-Host "  $appCheckDebugToken"
Write-Host "  https://console.firebase.google.com/project/$project/appcheck"
Write-Host ""
Write-Host "Then: uninstall app on phone, flutter clean, flutter run" -ForegroundColor Green
