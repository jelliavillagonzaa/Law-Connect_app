# Build Flutter web and deploy to Firebase Hosting (project: jurislink-app).
# Prerequisites: flutter, firebase CLI, and `firebase login` completed once.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "Building Flutter web (release)..." -ForegroundColor Cyan
flutter build web --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Deploying to Firebase Hosting..." -ForegroundColor Cyan
firebase deploy --only hosting
exit $LASTEXITCODE
