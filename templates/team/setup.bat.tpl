@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "SSH_DIR=%USERPROFILE%\.ssh\ai-south-hack"
set "KEY_NAME=${team_id}-key"
set "MAIN_CONFIG=%USERPROFILE%\.ssh\config"
set "INCLUDE_LINE=Include ~/.ssh/ai-south-hack/ssh-config"

echo =^> Creating directory %SSH_DIR%
if not exist "%USERPROFILE%\.ssh" md "%USERPROFILE%\.ssh"
if not exist "%SSH_DIR%"          md "%SSH_DIR%"

echo =^> Copying keys
copy /y "%SCRIPT_DIR%%KEY_NAME%"     "%SSH_DIR%\%KEY_NAME%"     > nul || goto :error
copy /y "%SCRIPT_DIR%%KEY_NAME%.pub" "%SSH_DIR%\%KEY_NAME%.pub" > nul || goto :error
copy /y "%SCRIPT_DIR%ssh-config"     "%SSH_DIR%\ssh-config"     > nul || goto :error

echo =^> Setting key permissions
icacls "%SSH_DIR%\%KEY_NAME%" /inheritance:r /grant:r "%USERNAME%:F" > nul 2>&1

echo =^> Updating SSH config
if not exist "%MAIN_CONFIG%" (
    (echo !INCLUDE_LINE!) > "%MAIN_CONFIG%"
    echo    Added.
) else (
    findstr /i /c:"ai-south-hack" "%MAIN_CONFIG%" > nul 2>&1
    if !errorlevel! == 0 (
        echo    (already present, skipping)
    ) else (
        set "TMP=%TEMP%\ssh_cfg_%RANDOM%.tmp"
        (echo !INCLUDE_LINE!)   > "!TMP!"
        (echo.)                >> "!TMP!"
        type "%MAIN_CONFIG%"  >> "!TMP!"
        copy /y "!TMP!" "%MAIN_CONFIG%" > nul
        del "!TMP!"
        echo    Added.
    )
)

echo =^> Testing connection...
ssh -o ConnectTimeout=10 -o BatchMode=yes ${team_id} echo OK > nul 2>&1
if !errorlevel! == 0 (
    echo.
    echo   [OK] All done^^! Connect with:
    echo.
    echo       ssh ${team_id}
    echo.
) else (
    echo.
    echo   [!] Keys installed. Connection test failed - VM may not be ready yet.
    echo       Try later:
    echo.
    echo       ssh ${team_id}
    echo.
)

pause
exit /b 0

:error
echo.
echo   [ERROR] Failed to copy files. Make sure you run this from the team folder.
echo.
pause
exit /b 1
