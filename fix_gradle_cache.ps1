# Script to fix Gradle cache corruption issue
Write-Host "Stopping all Java/Gradle processes..."
taskkill /F /IM java.exe /T 2>&1 | Out-Null
taskkill /F /IM gradle.exe /T 2>&1 | Out-Null

Write-Host "Removing corrupted Gradle cache..."
$cacheDir = "$env:USERPROFILE\.gradle\caches"
if (Test-Path $cacheDir) {
    Remove-Item -Recurse -Force $cacheDir -ErrorAction SilentlyContinue
    Write-Host "Cache removed"
}

Write-Host "Cleaning Flutter project..."
flutter clean

Write-Host "Rebuilding..."
flutter build apk --debug

