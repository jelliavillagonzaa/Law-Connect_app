param(
  [string]$ServiceKeyPath = "./serviceAccount.json",
  [string]$Collection = "court_email_queue"
)

$fullKey = Resolve-Path $ServiceKeyPath -ErrorAction SilentlyContinue
if (-not $fullKey) {
  $inputPath = Read-Host "Service account key not found at $ServiceKeyPath. Enter service account JSON path (or press Enter to cancel)"
  if (-not $inputPath) { Write-Host "Cancelled."; exit 1 }
  $fullKey = Resolve-Path $inputPath -ErrorAction SilentlyContinue
  if (-not $fullKey) { Write-Host "File not found: $inputPath"; exit 1 }
}

Write-Host "Using service account:" $fullKey

# Ensure node dependencies are installed
if (-not (Test-Path node_modules\firebase-admin)) {
  Write-Host "Installing dependencies (firebase-admin)..."
  npm install firebase-admin --no-audit --no-fund
}

$script = Join-Path (Resolve-Path .).Path "scripts\delete_court_email_queue.js"
node $script --key $fullKey --collection $Collection
$exit = $LASTEXITCODE
if ($exit -eq 0) { Write-Host "Collection deleted successfully." } else { Write-Host "Script exited with code $exit" }
exit $exit
