# Comprehensive script to fix Gradle connection issues with offline fallback
Write-Host "=== Gradle Connection Fix (with Offline Support) ===" -ForegroundColor Green
Write-Host ""

# Step 1: Stop Gradle daemons
Write-Host "[1/5] Stopping Gradle daemons..." -ForegroundColor Yellow
$gradlewPath = Join-Path $PSScriptRoot "android\gradlew.bat"
if (Test-Path $gradlewPath) {
    & $gradlewPath --stop 2>&1 | Out-Null
    Start-Sleep -Seconds 2
}
Get-Process java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
Write-Host "  ✓ Processes stopped" -ForegroundColor Green

# Step 2: Check if Gradle is already installed
Write-Host "[2/5] Checking for existing Gradle installation..." -ForegroundColor Yellow
$gradleVersion = "8.13"
$gradleUserHome = "$env:USERPROFILE\.gradle"
$wrapperDists = "$gradleUserHome\wrapper\dists"

# Find existing Gradle 8.13 installation
$existingGradle = Get-ChildItem $wrapperDists -Directory -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -like "gradle-$gradleVersion-all*" } | 
    Select-Object -First 1

if ($existingGradle) {
    $gradleBin = Get-ChildItem "$($existingGradle.FullName)\gradle-$gradleVersion\bin\gradle.bat" -ErrorAction SilentlyContinue
    if ($gradleBin) {
        Write-Host "  ✓ Gradle $gradleVersion found at: $($gradleBin.DirectoryName)" -ForegroundColor Green
        Write-Host ""
        Write-Host "Gradle is already installed. Trying to build..." -ForegroundColor Cyan
        Write-Host ""
        flutter run
        exit $LASTEXITCODE
    }
}

Write-Host "  ⚠ Gradle $gradleVersion not found" -ForegroundColor Yellow

# Step 3: Try to download Gradle
Write-Host "[3/5] Attempting to download Gradle..." -ForegroundColor Yellow
Write-Host "  Running download script..." -ForegroundColor Cyan
& "$PSScriptRoot\download_gradle_manual.ps1"
$downloadSuccess = $LASTEXITCODE -eq 0

if (-not $downloadSuccess) {
    Write-Host ""
    Write-Host "[4/5] Download failed. Setting up offline installation guide..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "=== MANUAL INSTALLATION REQUIRED ===" -ForegroundColor Red
    Write-Host ""
    Write-Host "Since automatic download failed, please follow these steps:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Download Gradle manually from one of these sources:" -ForegroundColor White
    Write-Host "   Primary: https://services.gradle.org/distributions/gradle-8.13-all.zip" -ForegroundColor Cyan
    Write-Host "   Mirror 1: https://downloads.gradle.org/distributions/gradle-8.13-all.zip" -ForegroundColor Cyan
    Write-Host "   Mirror 2: https://mirrors.cloud.tencent.com/gradle/gradle-8.13-all.zip" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. Extract the ZIP file to:" -ForegroundColor White
    Write-Host "   $wrapperDists\gradle-8.13-all\[hash]\gradle-8.13" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Note: The [hash] folder will be created automatically when you extract." -ForegroundColor Yellow
    Write-Host "   You can extract to a temp folder first, then copy the 'gradle-8.13' folder" -ForegroundColor Yellow
    Write-Host "   to the location above (create the hash folder manually if needed)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "3. After extraction, run this script again or try: flutter run" -ForegroundColor White
    Write-Host ""
    Write-Host "Alternative: Use a different network (VPN, mobile hotspot, etc.)" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Step 4: Clean Flutter build
Write-Host "[4/5] Cleaning Flutter build..." -ForegroundColor Yellow
flutter clean 2>&1 | Out-Null
Write-Host "  ✓ Clean completed" -ForegroundColor Green

# Step 5: Try building
Write-Host "[5/5] Attempting to build..." -ForegroundColor Yellow
Write-Host ""
flutter run

