# Script to manually download and install Gradle 8.13
Write-Host "=== Manual Gradle Download Script ===" -ForegroundColor Green
Write-Host ""

$gradleVersion = "8.13"
$gradleUrl = "https://services.gradle.org/distributions/gradle-$gradleVersion-all.zip"
$gradleUserHome = "$env:USERPROFILE\.gradle"
$wrapperDists = "$gradleUserHome\wrapper\dists"

# Calculate the expected hash directory name
# Gradle wrapper uses SHA-256 hash of the distribution URL
$urlBytes = [System.Text.Encoding]::UTF8.GetBytes($gradleUrl)
$sha256 = [System.Security.Cryptography.SHA256]::Create().ComputeHash($urlBytes)
$hash = ($sha256 | ForEach-Object { $_.ToString("x2") }) -join ""
$hashDir = $hash.Substring(0, 8)
$gradleDistDir = Join-Path $wrapperDists "gradle-$gradleVersion-all\$hashDir"

Write-Host "Gradle Version: $gradleVersion" -ForegroundColor Cyan
Write-Host "Download URL: $gradleUrl" -ForegroundColor Cyan
Write-Host "Target Directory: $gradleDistDir" -ForegroundColor Cyan
Write-Host ""

# Check if already downloaded
$existingGradlePath = Join-Path $gradleDistDir "gradle-$gradleVersion"
if (Test-Path $existingGradlePath) {
    Write-Host "✓ Gradle $gradleVersion already exists at:" -ForegroundColor Green
    Write-Host "  $existingGradlePath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You can now try: flutter run" -ForegroundColor Yellow
    exit 0
}

# Create directory
Write-Host "[1/4] Creating target directory..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $gradleDistDir | Out-Null
Write-Host "  ✓ Directory created" -ForegroundColor Green

# Download Gradle
Write-Host "[2/4] Downloading Gradle $gradleVersion..." -ForegroundColor Yellow
Write-Host "  This may take several minutes depending on your connection..." -ForegroundColor Cyan

$zipPath = Join-Path $gradleDistDir "gradle-$gradleVersion-all.zip"

try {
    # Try downloading with Invoke-WebRequest with extended timeout
    $ProgressPreference = 'SilentlyContinue'
    $ErrorActionPreference = 'Stop'
    
    Write-Host "  Attempting download from primary source..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $gradleUrl -OutFile $zipPath -TimeoutSec 300 -UseBasicParsing
    
    Write-Host "  ✓ Download completed!" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Download failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternative download methods:" -ForegroundColor Yellow
    Write-Host "  1. Manual download:" -ForegroundColor White
    Write-Host "     URL: $gradleUrl" -ForegroundColor Cyan
    Write-Host "     Save to: $zipPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. Try alternative mirrors:" -ForegroundColor White
    Write-Host "     - https://downloads.gradle.org/distributions/gradle-$gradleVersion-all.zip" -ForegroundColor Cyan
    Write-Host "     - https://mirrors.cloud.tencent.com/gradle/gradle-$gradleVersion-all.zip" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  3. After downloading, extract the ZIP to:" -ForegroundColor White
    Write-Host "     $gradleDistDir" -ForegroundColor Cyan
    Write-Host "     The extracted folder should be named: gradle-$gradleVersion" -ForegroundColor White
    Write-Host ""
    exit 1
}

# Extract Gradle
Write-Host "[3/4] Extracting Gradle..." -ForegroundColor Yellow
try {
    Expand-Archive -Path $zipPath -DestinationPath $gradleDistDir -Force
    Write-Host "  ✓ Extraction completed!" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Extraction failed: $_" -ForegroundColor Red
    Write-Host "  Please manually extract $zipPath to $gradleDistDir" -ForegroundColor Yellow
    exit 1
}

# Verify installation
Write-Host "[4/4] Verifying installation..." -ForegroundColor Yellow
$gradleHome = Join-Path $gradleDistDir "gradle-$gradleVersion"
$gradleBatPath = Join-Path $gradleHome "bin\gradle.bat"
if (Test-Path $gradleBatPath) {
    Write-Host "  ✓ Gradle installed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== Installation Complete ===" -ForegroundColor Green
    Write-Host "Gradle location: $gradleHome" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You can now try: flutter run" -ForegroundColor Yellow
} else {
    Write-Host "  ✗ Installation verification failed" -ForegroundColor Red
    $expectedPath = Join-Path $gradleHome "bin\gradle.bat"
    Write-Host "  Expected: $expectedPath" -ForegroundColor Yellow
    exit 1
}

