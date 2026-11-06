$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskVersion = '1.2.0'
Set-Location $taskRoot
if (-not (Test-Path -LiteralPath release/Track-Ta-v1.5.0.apk)) { throw 'Build the Android USB companion first.' }
python -m PyInstaller --noconfirm --onedir --windowed --name TrackTa-Windows --distpath release/windows-build --workpath build/windows-companion --specpath build/windows-companion --icon "$taskRoot/web/icons/Icon-512.png" --add-data "$taskRoot/assets/seed.json;assets" --add-binary "$taskRoot/.tooling/android-sdk/platform-tools/adb.exe;usb" --add-binary "$taskRoot/.tooling/android-sdk/platform-tools/AdbWinApi.dll;usb" --add-binary "$taskRoot/.tooling/android-sdk/platform-tools/AdbWinUsbApi.dll;usb" --exclude-module PySide6.QtWebEngineCore --exclude-module PySide6.QtWebEngineWidgets --exclude-module PySide6.QtQml --exclude-module PySide6.QtQuick --exclude-module PySide6.QtQuickWidgets --exclude-module numpy --exclude-module matplotlib --exclude-module tkinter desktop/app.py
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
$taskPackage = Join-Path $taskRoot 'release/windows-build/TrackTa-Windows'
# Qt uses the unversioned ICU API provided by Windows 10/11. Dependency
# discovery can collect a different ICU from PATH with versioned exports;
# shipping that DLL makes QtGui fail before the application opens.
$taskIcu = Join-Path $taskPackage '_internal/icuuc.dll'
if (Test-Path -LiteralPath $taskIcu) { Remove-Item -LiteralPath $taskIcu }
Copy-Item -LiteralPath release/Track-Ta-v1.5.0.apk -Destination $taskPackage
Copy-Item -LiteralPath desktop/HUONG-DAN-WINDOWS.txt -Destination $taskPackage
$taskNotice = Join-Path $taskRoot '.tooling/android-sdk/platform-tools/NOTICE.txt'
if (Test-Path -LiteralPath $taskNotice) { Copy-Item -LiteralPath $taskNotice -Destination (Join-Path $taskPackage 'ANDROID-USB-NOTICE.txt') }
foreach ($taskPlatform in @('offscreen', 'windows')) {
    $taskCheckDir = Join-Path $taskRoot "build/windows-companion/check-$taskPlatform"
    $taskArguments = @('--self-test', ('"{0}"' -f $taskCheckDir))
    if ($taskPlatform -eq 'windows') { $taskArguments += '--native-window' }
    $taskProcess = Start-Process -FilePath (Join-Path $taskPackage 'TrackTa-Windows.exe') -ArgumentList $taskArguments -WindowStyle Hidden -PassThru
    if (-not $taskProcess.WaitForExit(30000)) {
        Stop-Process -Id $taskProcess.Id -Force
        throw "Packaged application did not finish the $taskPlatform check. No ZIP was published."
    }
    if ($taskProcess.ExitCode -ne 0) { throw "Packaged application failed the $taskPlatform check. No ZIP was published." }
    $taskReport = Get-Content -LiteralPath (Join-Path $taskCheckDir 'deployment-check.json') -Raw | ConvertFrom-Json
    if (-not $taskReport.ok -or $taskReport.platform -ne $taskPlatform) { throw 'Invalid packaged application check.' }
}
$taskZip = Join-Path $taskRoot "release/TrackTa-Windows-v$taskVersion.zip"
Compress-Archive -LiteralPath $taskPackage -DestinationPath $taskZip -Force
$taskHashes = Get-FileHash -LiteralPath $taskZip,(Join-Path $taskRoot 'release/Track-Ta-v1.5.0.apk') -Algorithm SHA256
$taskHashes | ForEach-Object { '{0}  {1}' -f $_.Hash,(Split-Path $_.Path -Leaf) } | Set-Content -LiteralPath release/SHA256-USB.txt -Encoding ascii
$taskHashes | Select-Object Algorithm,Hash,Path
