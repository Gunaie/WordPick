@echo off
setlocal

rem ==========================================================
rem  English Study - web preview in Edge (fast local testing)
rem  Usage: double-click, then use the console keys:
rem    r = hot reload (after code changes)
rem    R = hot restart
rem    q = quit
rem  Build artifacts go to %TEMP%, NOT to the workspace build\,
rem  because the editor file watcher recycles build\ files.
rem ==========================================================

set "FLUTTER_BUILD_DIR=%LOCALAPPDATA%\Temp\flutter_web_build"
set "PUB_CACHE=%LOCALAPPDATA%\Temp\pub-cache"
set "JAVA_HOME=D:\Javadevelop\jdk-17.0.20.1+1"

cd /d "E:\Trae\English"

echo.
echo Starting Edge preview on http://localhost:8091 ...
echo (first start takes about a minute)
echo.

call "E:\flutter_sdk\flutter\bin\flutter.bat" run -d edge --web-port 8091 --no-pub

echo.
echo Flutter run exited.
pause
