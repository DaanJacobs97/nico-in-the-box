# Builds the Windows release zips of the app and the Caster.
#
#   powershell -ExecutionPolicy Bypass -File tool/release/package_windows.ps1
#
# Output in build/release/: NicoInTheBox-<version>-windows.zip and
# NicoCaster-<version>-windows.zip, each holding one folder with the .exe.
# The version comes from pubspec.yaml. Used by .github/workflows/release.yml
# and runnable locally for a dry run.
param([switch]$SkipWebClient)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out = Join-Path $root 'build\release'
New-Item -ItemType Directory -Force $out | Out-Null

$version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value
Write-Host "Packaging version $version for Windows"

# The host app serves the browser client, so it must be built first.
if (-not $SkipWebClient) {
  & (Join-Path $root 'tool\build_web_client.ps1')
}

# Flutter's Windows build needs the Visual C++ runtime. Many PCs have it
# installed, but not all, so it ships next to the .exe (Microsoft allows
# redistributing these files).
$runtime = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')

function Package([string]$project, [string]$name) {
  Push-Location $project
  try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed in $project" }
  } finally {
    Pop-Location
  }
  $release = Join-Path $project 'build\windows\x64\runner\Release'
  foreach ($dll in $runtime) {
    Copy-Item (Join-Path $env:SystemRoot "System32\$dll") $release -Force
  }
  # Zip the folder itself, so unzipping gives one tidy folder.
  $stage = Join-Path $env:TEMP "nico-release-$name"
  Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
  New-Item -ItemType Directory $stage | Out-Null
  Copy-Item -Recurse $release (Join-Path $stage $name)
  $zip = Join-Path $out "$name-$version-windows.zip"
  Remove-Item $zip -ErrorAction SilentlyContinue
  Compress-Archive -Path (Join-Path $stage $name) -DestinationPath $zip
  Remove-Item -Recurse -Force $stage
  Write-Host "Wrote $zip"
}

Package $root 'NicoInTheBox'
Package (Join-Path $root 'caster') 'NicoCaster'
