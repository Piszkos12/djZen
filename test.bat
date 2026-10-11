@echo off
rem djZen unit tests - builds and runs tests\djZenTests
rem Override the Lazarus location with the LAZARUS_DIR environment variable.

setlocal
cd /d "%~dp0"

if "%LAZARUS_DIR%"=="" set "LAZARUS_DIR=D:\lazarus"
set "LAZBUILD=%LAZARUS_DIR%\lazbuild.exe"
if not exist "%LAZBUILD%" (
  echo [ERROR] lazbuild not found: "%LAZBUILD%"
  echo         Set LAZARUS_DIR to your Lazarus installation folder.
  exit /b 1
)

"%LAZBUILD%" -B tests\djZenTests.lpi >nul
if errorlevel 1 (
  echo [ERROR] Test build failed. Run: "%LAZBUILD%" tests\djZenTests.lpi
  exit /b 1
)

bin\tests\djZenTests.exe
exit /b %errorlevel%
