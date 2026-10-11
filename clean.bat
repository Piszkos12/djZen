@echo off
rem djZen clean script - removes all build output (bin\, lib\, backup\)

setlocal
cd /d "%~dp0"

for %%D in (bin lib backup) do (
  if exist "%%D" rmdir /s /q "%%D"
)
if exist djZen.res del /q djZen.res

echo Cleaned.
exit /b 0
