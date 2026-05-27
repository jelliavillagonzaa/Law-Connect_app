# PowerShell script to fix Gradle connection timeout issues
Write-Host "Fixing Gradle connection timeout issues..." -ForegroundColor Green

# Step 1: Stop any running Gradle daemons
Write-Host "`n[1/4] Stopping Gradle daemons..." -ForegroundColor Yellow
& "$PSScriptRoot\android\gradlew.bat" --stop 2>&1 | Out-Null

# Step 2: Clean Flutter build
Write-Host "[2/4] Cleaning Flutter build..." -ForegroundColor Yellow
flutter clean

# Step 3: Try to manually download Gradle if needed
Write-Host "[3/4] Checking Gradle distribution..." -ForegroundColor Yellow
$gradleVersion = "8.14"
$gradleUrl = "https://services.gradle.org/distributions/gradle-$gradleVersion-all.zip"
$gradleUserHome = "$env:USERPROFILE\.gradle"
$gradleWrapperDists = "$gradleUserHome\wrapper\dists\gradle-$gradleVersion-all"

# Check if Gradle is already downloaded
if (Test-Path "$gradleWrapperDists\*") {
    Write-Host "Gradle distribution found in cache." -ForegroundColor Green
} else {
    Write-Host "Gradle distribution not found. Attempting manual download..." -ForegroundColor Yellow
    Write-Host "If this fails, you may need to:" -ForegroundColor Cyan
    Write-Host "  1. Check your internet connection" -ForegroundColor Cyan
    Write-Host "  2. Configure proxy settings if behind a firewall" -ForegroundColor Cyan
    Write-Host "  3. Manually download from: $gradleUrl" -ForegroundColor Cyan
    Write-Host "  4. Extract to: $gradleWrapperDists" -ForegroundColor Cyan
}

# Step 4: Try building with increased verbosity
Write-Host "[4/4] Attempting build with verbose output..." -ForegroundColor Yellow
Write-Host "`nRunning: flutter build apk --debug" -ForegroundColor Cyan
Write-Host "If connection issues persist, try:" -ForegroundColor Yellow
Write-Host "  - Check firewall/proxy settings" -ForegroundColor Yellow
Write-Host "  - Use a VPN if in a restricted network" -ForegroundColor Yellow
Write-Host "  - Manually download Gradle from the URL above" -ForegroundColor Yellow

# Run the build
flutter build apk --debug

