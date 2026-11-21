@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo 启动豆包对讲机...
echo 按住 F10 说话，松开自动发送
echo 关闭此窗口即可退出
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "doubao-ptt.ps1" -HotKey F10
pause
