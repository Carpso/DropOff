# DropOff release builder — always cleans the build cache first so
# fresh builds are never stale. Usage (from repo root):
#   powershell -File tools/build_release.ps1          # analyze + test + apk + aab + web
#   powershell -File tools/build_release.ps1 -Apk     # apk only
#   powershell -File tools/build_release.ps1 -Aab     # aab only
#   powershell -File tools/build_release.ps1 -Web     # web only
param(
  [switch]$Apk,
  [switch]$Aab,
  [switch]$Web,
  [switch]$NoAnalyze
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location "$root\app"

Write-Host '== flutter clean (clears the build cache) =='
flutter clean
Write-Host '== flutter pub get =='
flutter pub get

if (-not $NoAnalyze) {
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
  Write-Host "web bundle: app/build/web ($('~' + ([math]::Round((Get-ChildItem -Recurse build/web | Measure-Object Length -Sum).Sum / 1MB, 1)) + ' MB')"
}

if ($doApk) { Write-Host "APK: $root\app\build\app\outputs\flutter-apk\DropOff.apk" }
if ($doAab) { Write-Host "AAB: $root\app\build\app\outputs\bundle\release\app-release.aab" }
Write-Host '== done =='
