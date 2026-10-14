# Builds the browser player client and packs it into the host app's assets.
#
#   powershell -ExecutionPolicy Bypass -File tool/build_web_client.ps1
#
# Output: assets/generated/web_client.zip (git-ignored). Run this before
# building the host app; without it, the app still works but browser join
# shows a "not included in this build" page.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$client = Join-Path $root 'web_client'
$out = Join-Path $root 'assets\generated\web_client.zip'

Push-Location $client
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
  # Served from /play/ by the host; no CDN so it works on an offline LAN.
  flutter build web --release --base-href /play/ --no-web-resources-cdn --no-wasm-dry-run
  if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }
} finally {
  Pop-Location
}

$web = Join-Path $client 'build\web'
# This is a dart2js + CanvasKit build: browsers load either canvaskit/ (full)
# or canvaskit/chromium/. The skwasm/wimp/webparagraph engines are only used by
# --wasm builds or opt-in flags, and .symbols files are debug-only.
$skip = '^(canvaskit/(skwasm|skwasm_heavy|wimp)\.|canvaskit/webparagraph/)|\.symbols$|^\.last_build_id$'

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
if (Test-Path $out) { Remove-Item $out }
$zip = [IO.Compression.ZipFile]::Open($out, 'Create')
try {
  foreach ($file in Get-ChildItem -Recurse -File $web) {
    # Forward slashes: these become URL paths on the host.
    $name = $file.FullName.Substring($web.Length + 1).Replace('\', '/')
    if ($name -match $skip) { continue }
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $zip, $file.FullName, $name, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
} finally {
  $zip.Dispose()
}
'{0} ({1:N1} MB)' -f $out, ((Get-Item $out).Length / 1MB)
