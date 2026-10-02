@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
rem ============================================
rem  PositionAssistant one-click APK build
rem  Output: client\build\app\outputs\flutter-apk\<artifact>.apk
rem  Usage: double-click, or run scripts\build-apk.bat [debug|with-quota]
rem ============================================

set "ROOT=%~dp0.."
set "CLIENT=%ROOT%\client"
set "FLUTTER=%ROOT%\.tooling\flutter\bin\flutter.bat"
set "QUOTA_SERVICE_URL=https://quota.yexl.top"
set "BUNDLE_QUOTA_DATA=false"
set "ARTIFACT_NAME=持仓助手.apk"

if /i "%~1"=="debug" set "MODE=debug"
if /i "%~1"=="with-quota" (
    set "MODE=release"
    set "BUNDLE_QUOTA_DATA=true"
    set "ARTIFACT_NAME=持仓助手-带额度.apk"
)
if not defined MODE set "MODE=release"

if not exist "%FLUTTER%" (
    echo [ERROR] Flutter SDK not found: %FLUTTER%
    exit /b 1
)

if /i "%BUNDLE_QUOTA_DATA%"=="true" (
    echo [0/3] sync latest quota data ...
    node "%ROOT%\scripts\sync-quota-data.js"
    if errorlevel 1 (
        echo [ERROR] quota data sync failed
        exit /b 1
    )
)

echo [1/3] flutter build apk --%MODE% --target-platform android-arm64 with quota service %QUOTA_SERVICE_URL% ...
pushd "%CLIENT%"
call "%FLUTTER%" build apk --%MODE% --target-platform android-arm64 --dart-define=QUOTA_SERVICE_URL=%QUOTA_SERVICE_URL% --dart-define=BUNDLE_QUOTA_DATA=%BUNDLE_QUOTA_DATA%
set "BUILD_EXIT=!ERRORLEVEL!"
popd
if /i "%BUNDLE_QUOTA_DATA%"=="true" (
    node "%ROOT%\scripts\sync-quota-data.js" --clear-seed
    if errorlevel 1 echo [WARN] failed to clear temporary bundled quota seed
)
if not "!BUILD_EXIT!"=="0" (
    echo [ERROR] build failed
    exit /b !BUILD_EXIT!
)

echo [2/3] rename output APK ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\rename-apk.ps1" -Mode %MODE% -Name "%ARTIFACT_NAME%"
if errorlevel 1 exit /b 1

echo done!
endlocal
