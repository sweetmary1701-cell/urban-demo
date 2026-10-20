@echo off
setlocal enabledelayedexpansion
title 苏州智慧交通可视化大屏 - 启动器

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

if not exist "%ROOT%\.venv\Scripts\python.exe" goto NOVENV

echo ============================================================
echo   苏州智慧交通可视化大屏
echo   项目目录：%ROOT%
echo ============================================================
echo.
echo 服务依赖顺序：PostgreSQL -^> GeoServer -^> FastAPI / Vite
echo.

set "PGWASDOWN=0"

echo [1/5] 检查 PostgreSQL 数据库服务（:5432）...
netstat -ano | findstr ":5432 " | findstr LISTENING >nul
if not errorlevel 1 goto PGUP
set "PGWASDOWN=1"
echo       未运行，正在启动服务...
net start postgresql-x64-18 >nul 2>&1
set /a P=0
:WAITPG
set /a P+=1
netstat -ano | findstr ":5432 " | findstr LISTENING >nul
if not errorlevel 1 goto PGUP
if %P% GEQ 20 goto PGFAIL
timeout /t 3 /nobreak >nul
goto WAITPG

:PGUP
echo       数据库已就绪

echo [2/5] 检查 GeoServer 地图服务（:8086）...
if "%PGWASDOWN%"=="1" goto GSRESTART
netstat -ano | findstr ":8086 " | findstr LISTENING >nul
if not errorlevel 1 goto GSUP
echo       未运行，正在启动服务（约需 40 秒）...
net start GeoServer >nul 2>&1
goto WAITGS

:GSRESTART
echo       数据库刚从停机中恢复，重启 GeoServer 以重建数据库连接...
net stop GeoServer >nul 2>&1
timeout /t 6 /nobreak >nul
net start GeoServer >nul 2>&1

:WAITGS
set /a G=0
:WAITGS2
set /a G+=1
netstat -ano | findstr ":8086 " | findstr LISTENING >nul
if not errorlevel 1 goto GSUP
if %G% GEQ 25 goto GSFAIL
timeout /t 3 /nobreak >nul
goto WAITGS2

:GSUP
echo       地图服务已就绪

echo [3/5] 启动后端 API 服务（FastAPI :8000）...
netstat -ano | findstr ":8000 " | findstr LISTENING >nul
if not errorlevel 1 goto APIUP
start "traffic-backend" /min /d "%ROOT%" cmd /c ""%ROOT%\.venv\Scripts\python.exe" -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000"

:APIUP
echo [4/5] 启动前端开发服务器（Vite :5173）...
netstat -ano | findstr ":5173 " | findstr LISTENING >nul
if not errorlevel 1 goto WEBUP
start "traffic-frontend" /min /d "%ROOT%\frontend" cmd /c "npm run dev"

:WEBUP
echo [5/5] 等待服务就绪...
set /a N=0
:WAITAPI
set /a N+=1
curl.exe -s --fail -o nul --max-time 3 http://127.0.0.1:8000/api/health >nul 2>&1
if not errorlevel 1 goto APIOK
if %N% GEQ 25 goto APIFAIL
timeout /t 3 /nobreak >nul
goto WAITAPI

:APIOK
echo       后端已就绪
set /a M=0
:WAITWEB
set /a M+=1
curl.exe -s --fail -o nul --max-time 3 http://127.0.0.1:5173/ >nul 2>&1
if not errorlevel 1 goto WEBOK
if %M% GEQ 25 goto WEBFAIL
timeout /t 3 /nobreak >nul
goto WAITWEB

:WEBOK
echo       前端已就绪
echo.
echo   正在打开浏览器：http://127.0.0.1:5173/
start "" http://127.0.0.1:5173/
echo.
echo ------------------------------------------------------------
echo   大屏地址：   http://127.0.0.1:5173/
echo   GeoServer：  http://localhost:8086/geoserver/web/   账号 admin / geoserver
echo   业务接口：   http://127.0.0.1:8000/docs
echo   停止服务：   双击 停止大屏.bat
echo ------------------------------------------------------------
goto END

:PGFAIL
echo.
echo [警告] PostgreSQL 未能在 60 秒内就绪。
echo        查看日志：E:\Program Files\PostgreSQL\18\data\log\
goto END

:GSFAIL
echo.
echo [警告] GeoServer 未能在 75 秒内就绪。
echo        查看日志：E:\Program Data\geoserver\logs\geoserver.log
goto END

:APIFAIL
echo.
echo [警告] 后端未能在 75 秒内就绪。
echo        查看日志：backend\uvicorn.err.log
echo        常见原因：PostgreSQL 没起来，后端连不上数据库就会直接退出。
goto END

:WEBFAIL
echo.
echo [警告] 前端未能在 75 秒内就绪。
echo        查看日志：frontend\vite.out.log
goto END

:END
echo.
echo 提示：若页面提示加载失败，等几秒后按 Ctrl+Shift+R 刷新即可。
pause
exit /b 0

:NOVENV
echo [错误] 找不到 Python 虚拟环境：%ROOT%\.venv
echo        请确认项目目录完整。
echo.
pause
exit /b 1