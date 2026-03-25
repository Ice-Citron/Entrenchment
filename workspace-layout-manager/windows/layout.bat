@echo off
REM Workspace Layout Manager - Windows launcher
REM Usage: layout save <name> / layout restore <name> / layout list / etc.
powershell -ExecutionPolicy Bypass -File "%~dp0layout.ps1" %*
