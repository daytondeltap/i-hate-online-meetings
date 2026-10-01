@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0source\Build-ihatemeetings.ps1"
set ERR=%ERRORLEVEL%
echo.
if %ERR% EQU 0 (
  echo Build completed successfully.
  echo Output: %~dp0ihatemeetings.exe
) else (
  echo Build failed with exit code %ERR%.
)
pause
exit /b %ERR%
