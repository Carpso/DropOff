# DropOff release builder — always cleans the build cache first so
# fresh builds are never stale. Usage (from repo root):
#   powershell -File tools/build_release.ps1          # analyze + test + apk + aab + web
#   powershell -File tools/build_release.ps1 -Apk     # apk only
#   powershell -File tools/build_release.ps1 -Aab     # aab only
#   powershell -File tools/build_release.ps1 -Web     # web only
#   powershell -File tools/build_release.ps1 -SkipAnalyze  # skip analyze/test
param(
  [switch]$Apk,
  [switch]$Aab,
  [switch]$Web,
  [switch]$SkipAnalyze
)

# Flutter writes gradle warnings to stderr; with 'Stop' they abort the build
# before artifacts are copied (silently killing dist/). Keep going and check
# exit codes explicitly below.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location "$root\app"

# Your standing rule: ALWAYS `flutter clean` before building so artifacts
# are never stale.
Write-Host '== flutter clean (clears the build cache) =='
flutter clean
Write-Host '== flutter pub get =='
flutter pub get
if ($LASTEXITCODE -ne 0) {
  Write-Host '!! pub.dev unreachable — falling back to --offline (using the pub cache)'
  flutter pub get --offline
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed (online and offline)' }
}

if (-not $SkipAnalyze) {
  Write-Host '== flutter analyze =='
  flutter analyze
  Write-Host '== flutter test =='
  flutter test
}

# Custom domain shared by ALL share links + API (owner 2026-11-18). This used
# to hardcode the old workers.dev host, which silently overrode the app's new
# default — every "0.5.47" build still pointed at the old blocked host.
$apiUrl = '--dart-define=DROPOFF_API_URL=https://api.carpsosolutions.store'

# Default: rebuild everything
$doApk = $Apk -or -not ($Apk -or $Aab -or $Web)
$doAab = $Aab -or -not ($Apk -or $Aab -or $Web)
$doWeb = $Web -or -not ($Apk -or $Aab -or $Web)

if ($doApk) {
  Write-Host '== build APK =='
  flutter build apk --release $apiUrl
  if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
}
if ($doAab) {
  Write-Host '== build AAB =='
  flutter build appbundle --release $apiUrl
  if ($LASTEXITCODE -ne 0) { throw 'AAB build failed' }
}
if ($doWeb) {
  Write-Host '== build web =='
  flutter build web --release $apiUrl
  # Web is a secondary target (the recipient portal): never let a web-only
  # compile failure abort APK/AAB copies for Play.
  if ($LASTEXITCODE -ne 0) { Write-Host '!! web build failed - APK/AAB still copied' }
}

# Copy fresh artifacts into dist/ (the source of truth for uploads).
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
# Versioned artifact names straight from pubspec (0.5.1+12 -> DropOff-0.5.1-release.*)
$pubspec = Get-Content (Join-Path $root 'app\pubspec.yaml')
$ver = (($pubspec | Select-String '^version:\s*(\S+)\+(\d+)').Matches[0].Groups[1].Value)
$env:APK_NAME = "DropOff-$ver-release.apk"
Write-Host "== artifacts from version $ver =="
if ($doApk) {
  $src = 'build/app/outputs/flutter-apk/DropOff.apk'
  if (-not (Test-Path $src)) { $src = 'build/app/outputs/flutter-apk/app-release.apk' }
  if (Test-Path $src) {
    Copy-Item $src (Join-Path $dist 'DropOff-release.apk') -Force
    Copy-Item $src (Join-Path $dist $env:APK_NAME) -Force
  } else { Write-Host "!! APK missing: $src" }
  Write-Host "APK: $src"
}
if ($doAab) {
  $src = 'build/app/outputs/bundle/release/app-release.aab'
  if (Test-Path $src) {
    Copy-Item $src (Join-Path $dist 'DropOff-release.aab') -Force
    Copy-Item $src (Join-Path $dist "DropOff-$ver-release.aab") -Force
  }
  Write-Host "AAB: $src"
}
if ($doWeb) {
  $webDist = Join-Path $dist 'web'
  if (Test-Path $webDist) { Remove-Item $webDist -Recurse -Force }
  Copy-Item 'build/web' $webDist -Recurse -Force
  $size = (Get-ChildItem -Recurse $webDist | Measure-Object Length -Sum).Sum / 1MB
  Write-Host "web bundle: $webDist ($([math]::Round($size, 1)) MB)"
}
Write-Host '== done =='
