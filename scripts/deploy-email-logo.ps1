# Publishes web/logo.png to Firebase Hosting so EmailJS can load it.
# Requires: flutter, npx (Node.js), and `firebase login` once.

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "Copying assets/logo.png -> web/logo.png ..."
Copy-Item -Path "assets/logo.png" -Destination "web/logo.png" -Force

Write-Host "Building Flutter web (includes web/logo.png) ..."
flutter build web

Write-Host "Deploying Firebase Hosting ..."
npx --yes firebase-tools deploy --only hosting --project jurislink-app

Write-Host ""
Write-Host "Logo URL for EmailJS:"
Write-Host "  https://jurislink-app.web.app/logo.png"
Write-Host ""
Write-Host "EmailJS img tag:"
Write-Host '  <a href="https://jurislink-app.web.app/"><img style="height:48px;vertical-align:middle" height="48" src="https://jurislink-app.web.app/logo.png" alt="Law Connect logo" /></a>'
