@echo off
rem djZen build script - builds both versions:
rem   bin\dev\   debug info, runtime checks, heaptrc
rem   bin\prod\  optimized, stripped
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

call :build Dev  dev  || exit /b 1
call :build Prod prod || exit /b 1

echo.
echo Build finished.
exit /b 0

rem ---------------------------------------------------------------
rem :build <LazarusBuildMode> <output subfolder>
:build
echo.
echo === Building %1 ===
"%LAZBUILD%" --build-mode=%1 -B djZen.lpi
if errorlevel 1 (
  echo [ERROR] %1 build failed.
  exit /b 1
)

set "OUT=bin\%2"
for %%D in (apps profiles) do (
  if exist "%OUT%\%%D" rmdir /s /q "%OUT%\%%D"
  xcopy /e /i /q /y "%%D" "%OUT%\%%D" >nul
  if exist "%OUT%\%%D\.gitkeep" del /q "%OUT%\%%D\.gitkeep"
)
copy /y LICENSE "%OUT%\" >nul
copy /y README.md "%OUT%\" >nul
copy /y CHANGELOG.md "%OUT%\" >nul
echo %1 -^> %OUT%\djZen.exe
exit /b 0
