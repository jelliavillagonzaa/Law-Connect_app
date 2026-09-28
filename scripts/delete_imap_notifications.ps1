param(
  [string]$ServiceKeyPath = "./serviceAccount.json",
  [switch]$DryRun
)

$fullKey = Resolve-Path $ServiceKeyPath -ErrorAction SilentlyContinue
if (-not $fullKey) {
  $inputPath = Read-Host "Service account key not found at $ServiceKeyPath. Enter service account JSON path (or press Enter to cancel)"
  if (-not $inputPath) { Write-Host "Cancelled."; exit 1 }
  $fullKey = Resolve-Path $inputPath -ErrorAction SilentlyContinue
  if (-not $fullKey) { Write-Host "File not found: $inputPath"; exit 1 }
}

Write-Host "Using service account:" $fullKey

if (-not (Test-Path node_modules\firebase-admin)) {
  Write-Host "Installing dependencies (firebase-admin)..."
  npm install firebase-admin --no-audit --no-fund
}

$script = Join-Path (Resolve-Path .).Path "scripts\delete_imap_notifications.js"
$args = @("--key", $fullKey)
if ($DryRun) { $args += "--dry-run" }

node $script @args
exit $LASTEXITCODE
