@echo off
setlocal EnableExtensions

rem Change only this line after uploading updater.ps1 and manifest.json to GitHub.
set "RAW_BASE_URL=https://raw.githubusercontent.com/kurochi96/Minecraft_mod_updater/main"

set "APP_DIR=%APPDATA%\.swagsquad_updater"
set "UPDATER_PS1=%APP_DIR%\updater.ps1"
set "MANIFEST_JSON=%APP_DIR%\manifest.json"

if not exist "%APP_DIR%" mkdir "%APP_DIR%"

echo.
echo SwagSquad MOD updater preparing...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $base=$env:RAW_BASE_URL.TrimEnd('/'); if ($base -like 'https://example.com/*') { throw 'RAW_BASE_URL is not set.' }; Invoke-WebRequest -Uri ($base + '/updater.ps1') -OutFile $env:UPDATER_PS1 -UseBasicParsing; Invoke-WebRequest -Uri ($base + '/manifest.json') -OutFile $env:MANIFEST_JSON -UseBasicParsing"

if errorlevel 1 (
  echo.
  echo [ERROR] Failed to download updater.ps1 or manifest.json.
  echo Check RAW_BASE_URL in upload.bat.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPDATER_PS1%" -ManifestPath "%MANIFEST_JSON%"

echo.
pause
endlocal
