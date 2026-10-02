@echo off
setlocal
chcp 65001 >nul
set "SRC=%~dp0opencode-config-from-mac"
set "DST=%USERPROFILE%\.config\opencode"

echo ============================================
echo   Install opencode config  (ELTA Windows)
echo ============================================
echo.

if not exist "%SRC%\commands" (
  echo [ERROR] Cannot find the config folder:
  echo         "%SRC%"
  echo Run THIS .bat from the USB root, next to "opencode-config-from-mac".
  pause
  exit /b 1
)

if not exist "%DST%" mkdir "%DST%"

echo Copying config into:
echo   %DST%
xcopy "%SRC%\*" "%DST%\" /E /I /Y /H /K >nul
if errorlevel 1 (
  echo.
  echo [ERROR] Copy failed. Try running this .bat as Administrator.
  pause
  exit /b 1
)

echo.
echo Done!  Config installed to:
echo   %DST%
echo.
echo Now start opencode and use:   /tdd     /tdd-plan
echo   - DeepSeek key: keep the one you already have (no action).
echo   - npm install: NOT needed unless you use NLPM plugins.
echo.
pause
endlocal
