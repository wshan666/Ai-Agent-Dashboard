@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo [Agent Dashboard] One-click start and health check
echo Project: %CD%
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js was not found in PATH.
  echo Install Node.js first, then run this file again.
  pause
  exit /b 1
)

where npm >nul 2>nul
if errorlevel 1 (
  echo [ERROR] npm was not found in PATH.
  pause
  exit /b 1
)

if not exist node_modules (
  echo [INFO] node_modules not found. Installing dependencies...
  npm install
  if errorlevel 1 (
    echo [ERROR] npm install failed.
    pause
    exit /b 1
  )
)

for /f %%P in ('node -e "try{console.log((require('./config.json').server||{}).port||3456)}catch(e){console.log(3456)}"') do set PORT=%%P
set URL=http://127.0.0.1:%PORT%

echo [INFO] Checking %URL% ...
for /f %%S in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "try{(Invoke-WebRequest -Uri '%URL%/api/config' -UseBasicParsing -TimeoutSec 2).StatusCode}catch{0}"') do set STATUS=%%S

if "%STATUS%"=="200" (
  echo [OK] Server is already running.
) else (
  echo [INFO] Starting server in a minimized window...
  start "Agent Dashboard Server" /min cmd /c "node server.js >> server.log 2>&1"
  echo [INFO] Waiting for server health check...
  for /L %%I in (1,1,20) do (
    timeout /t 1 /nobreak >nul
    for /f %%S in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "try{(Invoke-WebRequest -Uri '%URL%/api/config' -UseBasicParsing -TimeoutSec 2).StatusCode}catch{0}"') do set STATUS=%%S
    if "!STATUS!"=="200" goto healthy
  )
  echo [ERROR] Server did not become healthy. Last log lines:
  powershell -NoProfile -ExecutionPolicy Bypass -Command "if(Test-Path 'server.log'){Get-Content 'server.log' -Tail 30}"
  pause
  exit /b 1
)

:healthy
echo [OK] Dashboard is ready: %URL%
start "" "%URL%"
echo.
echo Close this window when you are done checking the startup result.
pause
