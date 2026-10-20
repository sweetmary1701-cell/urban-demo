@echo off
setlocal
title 苏州智慧交通可视化大屏 - 停止

echo 正在停止大屏服务...

for %%P in (8000 5173) do for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%%P " ^| findstr LISTENING') do taskkill /F /T /PID %%a >nul 2>&1

echo.
echo 已停止前后端服务。
timeout /t 3 /nobreak >nul