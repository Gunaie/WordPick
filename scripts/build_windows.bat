@echo off
cd /d "e:\Trae\English"
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set LOG=.screenshots\wbuild.log
echo [START] %DATE% %TIME% > %LOG%
call "E:\flutter_sdk\flutter\bin\flutter.bat" --no-version-check build windows --debug >> %LOG% 2>&1
echo [EXITCODE] %ERRORLEVEL% >> %LOG%
echo [END] %DATE% %TIME% >> %LOG%
