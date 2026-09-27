@echo off
setlocal
cd /d "%~dp0"
echo =========================================================
echo   ELTA Windows B1 - build and run
echo   (screenshot selection test; global hotkey: Ctrl+T)
echo =========================================================
echo.

where dotnet >nul 2>nul
if errorlevel 1 goto nodotnet

echo Building... first run may take 1-5 minutes and needs internet.
echo.
dotnet run --project "src\Elta.Windows\Elta.Windows.csproj" -c Release
if errorlevel 1 goto buildfail

echo.
echo App exited normally.
pause
exit /b 0

:nodotnet
echo [ERROR] dotnet not found. Please install .NET 8 SDK first.
echo Or run:  winget install Microsoft.DotNet.SDK.8
pause
exit /b 1

:buildfail
echo.
echo [FAILED] Build or run error.
echo Please FULL-SCREEN SNAPSHOT the red error text and report back.
echo Do NOT edit the code yourself.
pause
exit /b 1
