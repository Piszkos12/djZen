@echo off
rem djZen release script - builds dev + prod, runs the unit tests and packs
rem bin\prod into dist\djZen-win64.zip, ready to attach to a GitHub Release.
rem The download links in README.md and docs\index.html point to the
rem versioned asset (releases/download/vX.Y.Z/djZen-win64.zip): update the
rem version there for every release.

setlocal
cd /d "%~dp0"

call "%~dp0build.bat" || exit /b 1

echo.
echo === Running unit tests ===
call "%~dp0tests.bat" >nul
if errorlevel 1 (
  echo [ERROR] Unit tests failed - no release. Run tests.bat for details.
  exit /b 1
)
echo Tests passed.

if not exist dist mkdir dist
set "ZIP=dist\djZen-win64.zip"
if exist "%ZIP%" del /q "%ZIP%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\make-zip.ps1" ^
  -Source "%~dp0bin\prod" -Destination "%~dp0%ZIP%" -Root djZen
if errorlevel 1 (
  echo [ERROR] Creating %ZIP% failed.
  exit /b 1
)

echo.
echo Release package: %ZIP%
echo Next: create a GitHub Release with a version tag (e.g. v0.1.1) and attach this file.
exit /b 0
