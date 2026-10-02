@echo off
setlocal
cd /d "%~dp0"
where dotnet >nul 2>nul
if errorlevel 1 (
  echo [ERROR] dotnet not found. Install .NET 8 SDK first:
  echo         winget install Microsoft.DotNet.SDK.8
  pause
  exit /b 1
)
echo Building Elta.Windows (Release)...
dotnet build "src\Elta.Windows\Elta.Windows.csproj" -c Release %*
if errorlevel 1 (
  echo.
  echo [FAILED] Build error. Snapshot the red text and report back. Do NOT edit blindly.
  pause
)
exit /b %errorlevel%
