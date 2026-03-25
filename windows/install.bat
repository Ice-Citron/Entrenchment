@echo off
REM Workspace Layout Manager - Windows Installer
REM Copies layout.bat and layout.ps1 to a directory on your PATH

echo Installing Workspace Layout Manager...

set INSTALL_DIR=%USERPROFILE%\.local\bin
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

copy "%~dp0layout.ps1" "%INSTALL_DIR%\layout.ps1"
copy "%~dp0layout.bat" "%INSTALL_DIR%\layout.bat"

REM Create config directory
if not exist "%USERPROFILE%\.config\workspace-layouts" mkdir "%USERPROFILE%\.config\workspace-layouts"

REM Check if INSTALL_DIR is on PATH
echo %PATH% | findstr /i "%INSTALL_DIR%" >nul
if errorlevel 1 (
    echo.
    echo NOTE: %INSTALL_DIR% is not on your PATH.
    echo To add it, run this in PowerShell as admin:
    echo   [Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";%INSTALL_DIR%", "User")
    echo.
    echo Or add it manually: Settings ^> System ^> About ^> Advanced ^> Environment Variables
)

echo.
echo Installed! You can now use:
echo   layout save my-setup -Description "My workspace"
echo   layout restore my-setup
echo   layout list
echo.
echo Layouts are saved to: %USERPROFILE%\.config\workspace-layouts\
echo Both macOS and Windows layouts are stored in the same folder.
pause
