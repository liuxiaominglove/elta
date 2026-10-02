@echo off
setlocal
echo ===== ELTA: opencode config diagnostic =====
echo.
echo [1] where is opencode / version:
where.exe opencode
opencode --version
echo.
echo [2] USERPROFILE:
echo   %USERPROFILE%
echo.
echo [3] Config dir (should exist):
dir "%USERPROFILE%\.config\opencode"
echo.
echo [4] Commands dir (should contain tdd.md, tdd-plan.md, ...):
dir "%USERPROFILE%\.config\opencode\commands"
echo.
echo [5] Key file check:
if exist "%USERPROFILE%\.config\opencode\commands\tdd.md" (echo   tdd.md: FOUND) else (echo   tdd.md: MISSING)
echo.
echo [6] Other possible config locations:
if exist "%APPDATA%\opencode"          echo   %APPDATA%\opencode  EXISTS
if exist "%LOCALAPPDATA%\opencode"     echo   %LOCALAPPDATA%\opencode  EXISTS
if exist "%USERPROFILE%\.config\opencode\opencode.jsonc" echo   opencode.jsonc: FOUND
echo.
echo [7] If opencode version is 2.x, it is the NEW package (@opencode/cli),
echo     not the 1.x package (opencode-ai). Config layout may differ.
echo.
echo Copy ALL text above and send it back.
pause
endlocal
