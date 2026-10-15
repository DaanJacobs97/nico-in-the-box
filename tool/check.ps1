# Runs every check CI runs (except the web build): format, analyze, and all
# five test suites. Use before every pull request.
#
#   powershell -ExecutionPolicy Bypass -File tool/check.ps1        # check only
#   powershell -ExecutionPolicy Bypass -File tool/check.ps1 -Fix   # format first
#
# Formats explicit folders: `dart format .` crashes on caster/build on Windows.
param([switch]$Fix)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$sources = @(
  'lib', 'test', 'integration_test', 'tool',
  'packages/nico_shared/lib', 'packages/nico_shared/test',
  'packages/nico_native/lib', 'packages/nico_native/test',
  'caster/lib', 'caster/test', 'web_client/lib', 'web_client/test'
)
$failed = @()

function Step([string]$name, [scriptblock]$block) {
  Write-Host "== $name" -ForegroundColor Cyan
  & $block
  if ($LASTEXITCODE -ne 0) { $script:failed += $name; Write-Host "   FAILED" -ForegroundColor Red }
}

if ($Fix) { Step 'format (fix)' { dart format $sources } }
Step 'format check' { dart format --output=none --set-exit-if-changed $sources }
Step 'analyze' { flutter analyze }

$suites = @('.', 'packages/nico_shared', 'packages/nico_native', 'caster', 'web_client')
foreach ($suite in $suites) {
  Step "test $suite" {
    Push-Location $suite
    try { flutter test } finally { Pop-Location }
  }
}

if ($failed.Count -gt 0) {
  Write-Host "`nFailed: $($failed -join ', ')" -ForegroundColor Red
  exit 1
}
Write-Host "`nAll checks passed." -ForegroundColor Green
