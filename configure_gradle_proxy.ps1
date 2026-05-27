# Script to configure Gradle proxy settings
Write-Host "=== Gradle Proxy Configuration ===" -ForegroundColor Green
Write-Host ""

$gradleProps = "android\gradle.properties"

# Check for system proxy
$proxy = [System.Net.WebRequest]::GetSystemWebProxy()
$proxyUrl = $proxy.GetProxy("https://services.gradle.org")

if ($proxyUrl -ne "https://services.gradle.org") {
    Write-Host "System proxy detected: $proxyUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Do you want to configure Gradle to use this proxy? (Y/N)" -ForegroundColor Cyan
    $response = Read-Host
    
    if ($response -eq "Y" -or $response -eq "y") {
        $proxyUri = [System.Uri]$proxyUrl
        $proxyHost = $proxyUri.Host
        $proxyPort = $proxyUri.Port
        
        Write-Host ""
        Write-Host "Adding proxy configuration to gradle.properties..." -ForegroundColor Yellow
        
        $proxyConfig = @"

# Proxy configuration
systemProp.http.proxyHost=$proxyHost
systemProp.http.proxyPort=$proxyPort
systemProp.https.proxyHost=$proxyHost
systemProp.https.proxyPort=$proxyPort
"@
        
        Add-Content -Path $gradleProps -Value $proxyConfig
        Write-Host "  ✓ Proxy configuration added" -ForegroundColor Green
    }
} else {
    Write-Host "No system proxy detected" -ForegroundColor Green
    Write-Host ""
    Write-Host "If you're behind a firewall/proxy, you can manually add to gradle.properties:" -ForegroundColor Yellow
    Write-Host "  systemProp.http.proxyHost=your.proxy.host" -ForegroundColor Cyan
    Write-Host "  systemProp.http.proxyPort=8080" -ForegroundColor Cyan
    Write-Host "  systemProp.https.proxyHost=your.proxy.host" -ForegroundColor Cyan
    Write-Host "  systemProp.https.proxyPort=8080" -ForegroundColor Cyan
}

Write-Host ""

