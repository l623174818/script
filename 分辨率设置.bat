@echo off
title 分辨率设置
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Set-Resolution.ps1"
if errorlevel 1 (
    echo.
    echo 按任意键退出...
    pause >nul
)
