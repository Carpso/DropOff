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

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location "$root\app"

# Your standing rule: ALWAYS `flutter clean` before building so artifacts
# are never stale.
Write-Host '== flutter clean (clears the build cache) =='
flutter clean
Write-Host '== flutter pub get =='
flutter pub get

if (-not $SkipAnalyze) {
  Write-Host '== flutter analyze =='
  flutter analyze
  Write-Host '== flutter test =='
  flutter test
}

$apiUrl = '--dart-define=DROPOFF_API_URL=https://dropoff-api.godfreymoseskalambo.workers.dev'

# Default: rebuild everything
$doApk = $Apk -or -not ($Apk -or $Aab -or $Web)
$doAab = $Aab -or -not ($Apk -or $Aab -or $Web)
$doWeb = $Web -or -not ($Apk -or $Aab -or $Web)

if ($doApk) {
  Write-Host '== build APK =='
  flutter build apk --release $apiUrl
}
if ($doAab) {
  Write-Host '== build AAB =='
  flutter build appbundle --release $apiUrl
}
if ($doWeb) {
  Write-Host '== build web =='
  flutter build web --release $apiUrl
}

# Copy fresh artifacts into dist/ (the source of truth for uploads).
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
if ($doApk) {
  $src = 'build/app/outputs/flutter-apk/DropOff.apk'
  if (Test-Path $src) { Copy-Item $src (Join-Path $dist 'DropOff-release.apk') -Force; Copy-Item $src (Join-Path $dist $env:APK_NAME) -Force }
  Write-Host "APK: $src"
}
if ($doAab) {
  $src = 'build/app/outputs/bundle/release/app-release.aab'
  if (Test-Path $src) { Copy-Item $src (Join-Path $dist 'DropOff-release.aab') -Force }
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
