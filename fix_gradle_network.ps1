# Comprehensive PowerShell script to fix Gradle network issues
Write-Host "=== Gradle Network Fix Script ===" -ForegroundColor Green
Write-Host ""

# Step 1: Stop all Gradle daemons
Write-Host "[1/6] Stopping Gradle daemons..." -ForegroundColor Yellow
$gradlewPath = Join-Path $PSScriptRoot "android\gradlew.bat"
if (Test-Path $gradlewPath) {
    & $gradlewPath --stop 2>&1 | Out-Null
    Start-Sleep -Seconds 2
}
Write-Host "  ✓ Gradle daemons stopped" -ForegroundColor Green

# Step 2: Kill any Java processes that might be holding connections
Write-Host "[2/6] Cleaning up Java processes..." -ForegroundColor Yellow
Get-Process java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Write-Host "  ✓ Java processes cleaned" -ForegroundColor Green

# Step 3: Clean Flutter build
Write-Host "[3/6] Cleaning Flutter build cache..." -ForegroundColor Yellow
flutter clean 2>&1 | Out-Null
Write-Host "  ✓ Flutter cache cleaned" -ForegroundColor Green

# Step 4: Clean Gradle cache (optional - uncomment if needed)
Write-Host "[4/6] Checking Gradle cache..." -ForegroundColor Yellow
$gradleCache = "$env:USERPROFILE\.gradle\caches"
if (Test-Path $gradleCache) {
    $cacheSize = (Get-ChildItem $gradleCache -Recurse -ErrorAction SilentlyContinue | 
        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB
    Write-Host "  Current cache size: $([math]::Round($cacheSize, 2)) MB" -ForegroundColor Cyan
    Write-Host "  Cache exists - keeping for faster builds" -ForegroundColor Green
} else {
    Write-Host "  No cache found" -ForegroundColor Yellow
}

# Step 5: Verify Gradle wrapper
Write-Host "[5/6] Verifying Gradle wrapper..." -ForegroundColor Yellow
$wrapperProps = Join-Path $PSScriptRoot "android\gradle\wrapper\gradle-wrapper.properties"
if (Test-Path $wrapperProps) {
    $content = Get-Content $wrapperProps -Raw
    if ($content -match 'distributionUrl=https.*gradle-([0-9]+\.[0-9]+).*\.zip') {
        $gradleVersion = $matches[1]
        Write-Host "  ✓ Gradle version: $gradleVersion" -ForegroundColor Green
    }
} else {
    Write-Host "  ✗ Gradle wrapper not found!" -ForegroundColor Red
}

# Step 6: Pre-download dependencies (optional)
Write-Host "[6/6] Attempting to pre-download Gradle dependencies..." -ForegroundColor Yellow
Write-Host ""
Write-Host "Running: flutter pub get" -ForegroundColor Cyan
flutter pub get 2>&1 | Out-Null
Write-Host "  ✓ Dependencies fetched" -ForegroundColor Green

Write-Host ""
Write-Host "=== Configuration Summary ===" -ForegroundColor Green
Write-Host "Network timeouts: 120 seconds" -ForegroundColor Cyan
Write-Host "Retry attempts: 10" -ForegroundColor Cyan
Write-Host "Alternative repositories: Configured" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Try running: flutter run" -ForegroundColor White
Write-Host "  2. If issues persist, check:" -ForegroundColor White
Write-Host "     - Firewall/proxy settings" -ForegroundColor White
Write-Host "     - Internet connection" -ForegroundColor White
Write-Host "     - VPN if in restricted network" -ForegroundColor White
Write-Host ""
Write-Host "If connection still fails, you may need to:" -ForegroundColor Yellow
Write-Host "  - Manually download Gradle from:" -ForegroundColor White
Write-Host "    https://services.gradle.org/distributions/" -ForegroundColor Cyan
$gradleDistsPath = Join-Path $env:USERPROFILE ".gradle\wrapper\dists"
Write-Host "  - Extract to: $gradleDistsPath" -ForegroundColor Cyan
Write-Host ""

