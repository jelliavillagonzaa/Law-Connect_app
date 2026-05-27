# Run Supabase CLI: prefers local binary (.tools/supabase), else npx with isolated cache.
#
#   .\scripts\supabase-cli.ps1 login
#   .\scripts\supabase-cli.ps1 link --project-ref YOUR_REF
#
# If `supabase` is not found, run first:
#   .\scripts\install-supabase-cli-windows.ps1

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$localExe = Join-Path $repoRoot ".tools\supabase\supabase.exe"

if (Test-Path $localExe) {
  & $localExe @args
  exit $LASTEXITCODE
}

Write-Host "Local CLI not found. Run: .\scripts\install-supabase-cli-windows.ps1" -ForegroundColor Yellow
Write-Host "Falling back to npx (may hit EBUSY on some PCs)..." -ForegroundColor Yellow

$localNpmCache = Join-Path $repoRoot ".npm-supabase-cli"
New-Item -ItemType Directory -Force -Path $localNpmCache | Out-Null
$env:npm_config_cache = $localNpmCache

npx --yes supabase@latest @args
