@echo off
setlocal
title Apple Music status for Discord - Uninstall
set "DEST=%APPDATA%\AppleMusicRPC"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

echo.
echo  Removing Apple Music status for Discord...

powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.ProcessId -ne $PID -and $_.CommandLine -like '*AppleMusicRPC.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

if exist "%STARTUP%\AppleMusicRPC.vbs" del /f /q "%STARTUP%\AppleMusicRPC.vbs"
if exist "%DEST%" rmdir /s /q "%DEST%"

echo  Done. It's fully removed and your Discord status is cleared.
echo.
pause
