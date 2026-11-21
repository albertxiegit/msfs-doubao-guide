@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo 正在测试无线电音效，请听声音...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "doubao-ptt.ps1" -TestSound
echo.
echo 测试结束，按任意键关闭。
pause >nul
