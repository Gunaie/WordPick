@echo off
setlocal

rem ==========================================================
rem  English Study - one-click release APK builder
rem  Usage: double-click this file
rem  Note: builds inside %TEMP% on purpose. Building in the
rem        workspace fails because the editor file watcher
rem        recycles build\ artifacts mid-compile.
rem ==========================================================

rem ---------- environment (this run only) ----------
set "JAVA_HOME=D:\Javadevelop\jdk-17.0.20.1+1"
set "ANDROID_HOME=E:\Android\Sdk"
set "ANDROID_SDK_ROOT=E:\Android\Sdk"
set "GRADLE_USER_HOME=%LOCALAPPDATA%\Temp\gradle-home"
rem Use an isolated pub cache: the jni/sqlite3 plugins write .cxx build
rem intermediates inside their package dir, and the default
rem %LOCALAPPDATA%\Pub is not always writable.
set "PUB_CACHE=%LOCALAPPDATA%\Temp\pub-cache"

rem ---------- paths ----------
set "SRC=E:\Trae\English"
set "DST=%LOCALAPPDATA%\Temp\english_build"
set "FLUTTER=E:\flutter_sdk\flutter\bin\flutter.bat"
set "OUT=E:\APK"

set "PAUSE_AT_END=1"
if /I "%~1"=="nopause" set "PAUSE_AT_END=0"

echo.
echo [1/4] Syncing sources to %DST% ...
rem Copy only what an Android build needs. windows/macos/ios/linux are skipped
rem because flutter pub get would create plugin symlinks for them, which
rem requires Windows Developer Mode.
robocopy "%SRC%" "%DST%" /MIR /XD build .gradle .git .dart_tool windows macos ios linux /NFL /NDL /NJH /NP /R:1 /W:1 >nul
if %ERRORLEVEL% GEQ 8 (
  echo [ERROR] Source sync failed, robocopy exit code %ERRORLEVEL%
  goto :fail
)

echo [2/4] Building release APK (obfuscated, first run about 3 min) ...
pushd "%DST%"
rem arm64 only keeps the APK small; drop --target-platform to ship 32-bit too.
rem 混淆 + 符号剥离只提高反编译成本，不是安全边界；symbols 留在临时目录，不入库。
set "SYMBOLS=%LOCALAPPDATA%\Temp\english_symbols"
rem 需要云同步时，先在本机设置 SYNC_ENV_ID / SYNC_API_KEY / SYNC_USER_ID 再运行
set "SYNC_DEFINES="
if not "%SYNC_ENV_ID%"=="" set "SYNC_DEFINES=--dart-define=SYNC_ENABLED=true --dart-define=SYNC_ENV_ID=%SYNC_ENV_ID% --dart-define=SYNC_API_KEY=%SYNC_API_KEY% --dart-define=SYNC_USER_ID=%SYNC_USER_ID%"
call "%FLUTTER%" build apk --release --target-platform android-arm64 --android-skip-build-dependency-validation --obfuscate --split-debug-info="%SYMBOLS%" %SYNC_DEFINES%
if errorlevel 1 (
  popd
  echo.
  echo [ERROR] Build failed - see the Flutter/Gradle output above
  goto :fail
)
popd

echo [3/4] Copying APK to %OUT% ...
if not exist "%OUT%" mkdir "%OUT%"
copy /Y "%DST%\build\app\outputs\flutter-apk\app-release.apk" "%OUT%\app-release.apk" >nul
if errorlevel 1 (
  echo [ERROR] Copy failed - no APK was produced
  goto :fail
)

echo [4/4] Done
for %%F in ("%OUT%\app-release.apk") do echo      file: %%~fF  ^(%%~zF bytes^)
echo      symbols: %SYMBOLS%  ^(排查崩溃用，勿公开^)
echo.
echo Next: copy app-release.apk to your phone and tap it to install.
echo.
echo.

if "%PAUSE_AT_END%"=="1" (
  explorer "%OUT%"
  pause
)
exit /b 0

:fail
echo.
if "%PAUSE_AT_END%"=="1" pause
exit /b 1
