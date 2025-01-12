@echo off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
) else (
    pwsh -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
)
