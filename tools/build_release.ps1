$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
Set-Location $taskRoot
$taskBundledJdk = Get-ChildItem "$taskRoot/.tooling/java" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($taskBundledJdk) { $env:JAVA_HOME = $taskBundledJdk.FullName }
if (Test-Path "$taskRoot/.tooling/android-sdk") { $env:ANDROID_HOME = "$taskRoot/.tooling/android-sdk" }
if (-not (Test-Path "$taskRoot/android/key.properties")) { throw 'Missing android/key.properties and release keystore. Preserve the original signing key for updates.' }
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
New-Item -ItemType Directory -Force release | Out-Null
Copy-Item -LiteralPath build/app/outputs/flutter-apk/app-release.apk -Destination release/Track-Ta-v1.5.0.apk
$taskHash = Get-FileHash release/Track-Ta-v1.5.0.apk -Algorithm SHA256
"$($taskHash.Hash)  Track-Ta-v1.5.0.apk" | Set-Content -LiteralPath release/SHA256.txt -Encoding ascii
$taskHash | Format-List
