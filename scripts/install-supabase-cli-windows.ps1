# Download official Supabase CLI into this repo (no Scoop, no npm global, no npx).
# Run once from repo root:
#   .\scripts\install-supabase-cli-windows.ps1
# Then:
#   .\scripts\supabase-cli.ps1 login

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installDir = Join-Path $repoRoot ".tools\supabase"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

$isArm64 =
  ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") -or
  ($env:PROCESSOR_ARCHITEW6432 -eq "ARM64")
$assetName = if ($isArm64) { "supabase_windows_arm64.tar.gz" } else { "supabase_windows_amd64.tar.gz" }

Write-Host "Fetching latest Supabase CLI release from GitHub..."
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/supabase/cli/releases/latest" -Headers @{
  "User-Agent" = "LawConnect-InstallScript"
}
$asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
if (-not $asset) {
  throw "Could not find asset $assetName in latest release."
}

$url = $asset.browser_download_url
$tempTgz = Join-Path ([System.IO.Path]::GetTempPath()) "supabase-cli-$($release.tag_name).tar.gz"

Write-Host "Downloading $($asset.name) ..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $tempTgz -UseBasicParsing

# Replace existing binary
Get-ChildItem -Path $installDir -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

Write-Host "Extracting to $installDir ..."
# Windows 10+ includes tar.exe
tar -xzf $tempTgz -C $installDir
Remove-Item -Force $tempTgz -ErrorAction SilentlyContinue

$exe = Join-Path $installDir "supabase.exe"
if (-not (Test-Path $exe)) {
  # Some archives nest one level
  $nested = Get-ChildItem -Path $installDir -Filter "supabase.exe" -Recurse | Select-Object -First 1
  if ($nested) {
    Copy-Item -Force $nested.FullName $exe
  }
}

if (-not (Test-Path $exe)) {
  throw "supabase.exe not found after extract. Check $installDir"
}

Write-Host "OK: $exe"
& $exe --version
Write-Host ""
Write-Host "Next: .\scripts\supabase-cli.ps1 login"
