@echo off
setlocal EnableExtensions
set "TMPFILE=%TEMP%\lc_flutter_hook_%RANDOM%.txt"
more > "%TMPFILE%"

findstr /I /C:"run_chrome" "%TMPFILE%" >nul
if not errorlevel 1 (
  echo {"permission":"allow"}
  del /q "%TMPFILE%" >nul 2>&1
  exit /b 0
)

findstr /I /C:"flutter_safe.cmd" "%TMPFILE%" >nul
if not errorlevel 1 (
  echo {"permission":"allow"}
  del /q "%TMPFILE%" >nul 2>&1
  exit /b 0
)

findstr /I /C:"no-web-experimental-hot-reload" "%TMPFILE%" >nul
if not errorlevel 1 (
  echo {"permission":"allow"}
  del /q "%TMPFILE%" >nul 2>&1
  exit /b 0
)

findstr /I /C:"flutter" "%TMPFILE%" | findstr /I /C:" run" >nul
if not errorlevel 1 (
  echo {"permission":"deny","user_message":"Use .\\scripts\\run_chrome.cmd. Bare flutter run breaks Chrome.","agent_message":"Do not start bare flutter run. Use scripts/run_chrome.cmd or add --no-web-experimental-hot-reload --no-web-enable-expression-evaluation --no-web-resources-cdn. Never start flutter run from a background agent shell."}
  del /q "%TMPFILE%" >nul 2>&1
  exit /b 0
)

echo {"permission":"allow"}
del /q "%TMPFILE%" >nul 2>&1
exit /b 0
