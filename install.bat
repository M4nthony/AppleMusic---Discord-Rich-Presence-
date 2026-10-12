@echo off
setlocal
title Apple Music status for Discord - Install
set "DEST=%APPDATA%\AppleMusicRPC"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

echo.
echo  ==============================================
echo   Apple Music status for Discord - Install
echo  ==============================================
echo.

if not exist "%~dp0AppleMusicRPC.ps1" (
    echo  AppleMusicRPC.ps1 must be in the same folder as this file.
    echo  Unzip everything first, then run install.bat again.
    echo.
    pause
    exit /b 1
)

echo  You need a Discord Application ID. Get one free here:
echo    https://discord.com/developers/applications
echo    New Application - name it "Apple Music" - copy the Application ID
echo.
set "OLDID="
if exist "%DEST%\config.json" for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "(Get-Content -LiteralPath '%DEST%\config.json' -Raw | ConvertFrom-Json).appId"`) do set "OLDID=%%i"
if defined OLDID (
    echo  Already set up with ID %OLDID%. Just press Enter to keep it, or paste a new one.
    echo.
)
set "APPID="
set /p "APPID= Paste your Application ID and press Enter: "
if "%APPID%"=="" set "APPID=%OLDID%"
if "%APPID%"=="" (
    echo  No ID entered. Nothing was installed.
    pause
    exit /b 1
)

echo.
echo  Installing...

rem Stop an older copy if it's running
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.ProcessId -ne $PID -and $_.CommandLine -like '*AppleMusicRPC.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

if not exist "%DEST%" mkdir "%DEST%"
copy /y "%~dp0AppleMusicRPC.ps1" "%DEST%\AppleMusicRPC.ps1" >nul

powershell -NoProfile -Command "Unblock-File -LiteralPath '%DEST%\AppleMusicRPC.ps1' -ErrorAction SilentlyContinue; @{ appId = '%APPID%'.Trim(); showPaused = $false; showButton = $true } | ConvertTo-Json | Set-Content -LiteralPath '%DEST%\config.json' -Encoding UTF8"

rem Small launcher that starts it hidden, and a copy in Startup so it runs with Windows
> "%DEST%\start-hidden.vbs" echo CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%DEST%\AppleMusicRPC.ps1""", 0, False
copy /y "%DEST%\start-hidden.vbs" "%STARTUP%\AppleMusicRPC.vbs" >nul

wscript.exe "%DEST%\start-hidden.vbs"

echo.
echo  Done! It's now running in the background and will start with Windows.
echo  Play a song in Apple Music and check your Discord profile.
echo.
echo  If it doesn't show: Discord - User Settings - Activity Privacy -
echo  turn ON "Share your detected activities with others".
echo.
pause
