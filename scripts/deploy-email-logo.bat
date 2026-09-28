@echo off
setlocal
cd /d "%~dp0.."

echo Copying email logo assets to web\ ...
copy /Y "assets\launcher_icon.png" "web\email-logo.png" >nul
copy /Y "assets\launcher_icon.png" "web\logo.png" >nul

echo Building Flutter web ...
call flutter build web
if errorlevel 1 exit /b 1

echo Deploying Firebase Hosting ...
call npx.cmd --yes firebase-tools deploy --only hosting --project jurislink-app
if errorlevel 1 (
  echo.
  echo Deploy failed. Run first: npx.cmd firebase-tools login
  exit /b 1
)

echo.
echo === Logo URLs (open in browser to verify) ===
echo   https://jurislink-app.web.app/email-logo.png
echo.
echo === IMPORTANT: Fix EmailJS template (one time) ===
echo Open scripts\emailjs-otp-template.html
echo Copy ALL content into EmailJS ^> One-Time Password ^> Content ^> Save
echo.
echo The logo URL is hardcoded (NOT cid:logo.png, NOT empty {{logo_url}}).
echo.
pause
