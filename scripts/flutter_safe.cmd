@echo off
setlocal
set "REAL="
if defined FLUTTER_ROOT if exist "%FLUTTER_ROOT%\bin\flutter.bat" set "REAL=%FLUTTER_ROOT%\bin\flutter.bat"
if not defined REAL if exist "C:\flutter\bin\flutter.bat" set "REAL=C:\flutter\bin\flutter.bat"
if not defined REAL (
  echo Flutter SDK not found. Expected C:\flutter\bin\flutter.bat
  exit /b 1
)

if /I "%~1"=="run" (
  echo(%*| findstr /I /C:"web-experimental-hot-reload" >nul
  if errorlevel 1 (
    echo [Law Connect] Chrome hot reload OFF. After edits press R once. Never press r.
    "%REAL%" %* --no-web-experimental-hot-reload --no-web-enable-expression-evaluation --no-web-resources-cdn
    exit /b %ERRORLEVEL%
  )
)

"%REAL%" %*
exit /b %ERRORLEVEL%
