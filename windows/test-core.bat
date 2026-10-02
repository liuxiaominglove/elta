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
echo Running Core tests...
dotnet test "tests\Elta.Core.Tests\Elta.Core.Tests.csproj" %*
set RC=%errorlevel%
if not "%RC%"=="0" pause
exit /b %RC%
