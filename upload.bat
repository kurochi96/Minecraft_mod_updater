@echo off
setlocal EnableExtensions
chcp 65001 >nul

rem ============================================================
rem SwagSquad Minecraft MOD Updater
rem
rem 使い始める前に、下の RAW_BASE_URL だけ差し替えてください。
rem GitHub の raw URL 例:
rem set "RAW_BASE_URL=https://raw.githubusercontent.com/USER/REPO/main"
rem ============================================================
set "RAW_BASE_URL=https://example.com/YOUR_GITHUB_RAW_BASE_URL"

set "APP_DIR=%APPDATA%\.swagsquad_updater"
set "UPDATER_PS1=%APP_DIR%\updater.ps1"
set "MANIFEST_JSON=%APP_DIR%\manifest.json"

if not exist "%APP_DIR%" mkdir "%APP_DIR%"

echo.
echo SwagSquad MOD updater を準備しています...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "$base='%RAW_BASE_URL%'.TrimEnd('/');" ^
  "if ($base -like 'https://example.com/*') { throw 'upload.bat の RAW_BASE_URL が未設定です。GitHub の raw URL に差し替えてください。' }" ^
  "Invoke-WebRequest -Uri ($base + '/updater.ps1') -OutFile '%UPDATER_PS1%' -UseBasicParsing;" ^
  "Invoke-WebRequest -Uri ($base + '/manifest.json') -OutFile '%MANIFEST_JSON%' -UseBasicParsing;"

if errorlevel 1 (
  echo.
  echo [エラー] updater.ps1 または manifest.json の取得に失敗しました。
  echo upload.bat の RAW_BASE_URL が正しいか確認してください。
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPDATER_PS1%" -ManifestPath "%MANIFEST_JSON%"

echo.
pause
endlocal
