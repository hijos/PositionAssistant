@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
rem ============================================
rem  PositionAssistant one-click APK build
rem  Output: client\build\app\outputs\flutter-apk\持仓助手.apk
rem  Usage: double-click, or run scripts\build-apk.bat [debug]
rem ============================================

set "ROOT=%~dp0.."
set "CLIENT=%ROOT%\client"
set "FLUTTER=%ROOT%\.tooling\flutter\bin\flutter.bat"
set "QUOTA_SERVICE_URL=http://192.168.31.143:4100"

if /i "%~1"=="debug" (set "MODE=debug") else (set "MODE=release")

if not exist "%FLUTTER%" (
    echo [ERROR] Flutter SDK not found: %FLUTTER%
    exit /b 1
)

echo [1/2] flutter build apk --%MODE% with quota service %QUOTA_SERVICE_URL% ...
pushd "%CLIENT%"
call "%FLUTTER%" build apk --%MODE% --dart-define=QUOTA_SERVICE_URL=%QUOTA_SERVICE_URL%
if errorlevel 1 (
    popd
    echo [ERROR] build failed
    exit /b 1
)
popd

echo [2/2] rename output APK ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\rename-apk.ps1" -Mode %MODE%
if errorlevel 1 exit /b 1

echo done!
endlocal
