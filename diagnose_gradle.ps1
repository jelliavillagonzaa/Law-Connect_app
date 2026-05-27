# Diagnostic script for Gradle network issues
Write-Host "=== Gradle Network Diagnostics ===" -ForegroundColor Green
Write-Host ""

# Check internet connectivity
Write-Host "[1] Testing internet connectivity..." -ForegroundColor Yellow
try {
    $response = Test-NetConnection -ComputerName "services.gradle.org" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($response) {
        Write-Host "  ✓ Can reach services.gradle.org" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Cannot reach services.gradle.org" -ForegroundColor Red
        Write-Host "    Check firewall/proxy settings" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ✗ Connection test failed: $_" -ForegroundColor Red
}

# Check Gradle installation
Write-Host "[2] Checking Gradle installation..." -ForegroundColor Yellow
$gradleHome = "$env:USERPROFILE\.gradle"
if (Test-Path $gradleHome) {
    Write-Host "  ✓ Gradle home exists: $gradleHome" -ForegroundColor Green
    
    $wrapperDists = "$gradleHome\wrapper\dists"
    if (Test-Path $wrapperDists) {
        $dists = Get-ChildItem $wrapperDists -Directory -ErrorAction SilentlyContinue
        if ($dists) {
            Write-Host "  ✓ Found Gradle distributions:" -ForegroundColor Green
            foreach ($dist in $dists) {
                Write-Host "    - $($dist.Name)" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  ⚠ No Gradle distributions found" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  ✗ Gradle home not found" -ForegroundColor Red
}

# Check proxy settings
Write-Host "[3] Checking proxy settings..." -ForegroundColor Yellow
$proxy = [System.Net.WebRequest]::GetSystemWebProxy()
$proxyUrl = $proxy.GetProxy("https://services.gradle.org")
if ($proxyUrl -eq "https://services.gradle.org") {
    Write-Host "  ✓ No proxy configured" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Proxy detected: $proxyUrl" -ForegroundColor Yellow
    Write-Host "    You may need to configure Gradle to use this proxy" -ForegroundColor Yellow
}

# Check Java
Write-Host "[4] Checking Java installation..." -ForegroundColor Yellow
try {
    $javaVersion = java -version 2>&1 | Select-Object -First 1
    Write-Host "  ✓ Java found: $javaVersion" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Java not found in PATH" -ForegroundColor Red
}

# Check Gradle wrapper
Write-Host "[5] Checking Gradle wrapper..." -ForegroundColor Yellow
$wrapperProps = "android\gradle\wrapper\gradle-wrapper.properties"
if (Test-Path $wrapperProps) {
    $content = Get-Content $wrapperProps
    $distUrl = $content | Where-Object { $_ -match "distributionUrl" }
    if ($distUrl) {
        Write-Host "  ✓ Wrapper configured: $distUrl" -ForegroundColor Green
    }
} else {
    Write-Host "  ✗ Wrapper properties not found" -ForegroundColor Red
}

# Check gradle.properties
Write-Host "[6] Checking Gradle properties..." -ForegroundColor Yellow
$gradleProps = "android\gradle.properties"
if (Test-Path $gradleProps) {
    $content = Get-Content $gradleProps
    $hasTimeouts = $content | Where-Object { $_ -match "timeout" -or $_ -match "Timeout" }
    if ($hasTimeouts) {
        Write-Host "  ✓ Network timeouts configured" -ForegroundColor Green
        $hasTimeouts | ForEach-Object { Write-Host "    $_" -ForegroundColor Cyan }
    } else {
        Write-Host "  ⚠ No timeout settings found" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ✗ gradle.properties not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Recommendations ===" -ForegroundColor Green
Write-Host "If connection issues persist:" -ForegroundColor Yellow
Write-Host "  1. Run: .\fix_gradle_network.ps1" -ForegroundColor White
Write-Host "  2. Check firewall/antivirus settings" -ForegroundColor White
Write-Host "  3. Try using a VPN" -ForegroundColor White
Write-Host "  4. Manually download Gradle distribution" -ForegroundColor White
Write-Host ""

