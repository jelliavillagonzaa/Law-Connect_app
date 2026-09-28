# Stable Chrome debug session.
# Never use plain `flutter run` + `r` (hot reload) on web — that drops the VM
# (getVM: (-32000) Service connection disposed). Press R to hot restart.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "Starting Chrome with experimental web hot reload disabled. Press R (not r) after code changes." -ForegroundColor DarkCyan
$flutter = "C:\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) { $flutter = "flutter" }
& $flutter run -d chrome --no-web-resources-cdn --no-web-experimental-hot-reload --no-web-enable-expression-evaluation
exit $LASTEXITCODE
