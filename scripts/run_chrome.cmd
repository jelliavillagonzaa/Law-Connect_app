@echo off
cd /d "%~dp0\.."
set "REAL="
if defined FLUTTER_ROOT if exist "%FLUTTER_ROOT%\bin\flutter.bat" set "REAL=%FLUTTER_ROOT%\bin\flutter.bat"
if not defined REAL if exist "C:\flutter\bin\flutter.bat" set "REAL=C:\flutter\bin\flutter.bat"
if not defined REAL (
  echo Flutter SDK not found. Expected C:\flutter\bin\flutter.bat
  exit /b 1
)
echo Starting Chrome (web hot reload OFF, expression eval OFF).
echo Press R once after code changes. Do not press r. Do not close the Chrome tab.
"%REAL%" run -d chrome --no-web-resources-cdn --no-web-experimental-hot-reload --no-web-enable-expression-evaluation
exit /b %ERRORLEVEL%
