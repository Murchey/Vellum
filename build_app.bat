@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Build ABI-split Release APKs for Vellum and rename them for GitHub Release.
rem Output: build\app\outputs\flutter-apk\Vellum-V<version>-<abi>.apk

cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Flutter SDK was not found on PATH.
  exit /b 1
)

if not exist pubspec.yaml (
  echo [ERROR] pubspec.yaml was not found in %CD%.
  exit /b 1
)

for /f "tokens=2 delims=:" %%V in ('findstr /r /c:"^version:" pubspec.yaml') do set "RAW_VERSION=%%V"
for /f "tokens=1 delims=+ " %%V in ("!RAW_VERSION!") do set "VERSION=%%V"
if "!VERSION!"=="" (
  echo [ERROR] Could not read the version from pubspec.yaml.
  exit /b 1
)

echo.
echo === Building ABI-split Release APKs for Vellum V!VERSION! ===
call flutter build apk --release --split-per-abi
if errorlevel 1 (
  echo [ERROR] Release APK build failed.
  exit /b 1
)

set "OUT=build\app\outputs\flutter-apk"
for %%A in (armeabi-v7a arm64-v8a x86_64) do (
  set "SOURCE=!OUT!\app-%%A-release.apk"
  set "TARGET=!OUT!\Vellum-V!VERSION!-%%A.apk"
  if not exist "!SOURCE!" (
    echo [ERROR] Expected build artifact is missing: !SOURCE!
    exit /b 1
  )
  if exist "!TARGET!" del /q "!TARGET!"
  move /y "!SOURCE!" "!TARGET!" >nul
  if errorlevel 1 (
    echo [ERROR] Failed to rename %%A APK.
    exit /b 1
  )
)

echo.
echo === Renamed outputs ===
for %%F in ("%OUT%\Vellum-V!VERSION!-*.apk") do (
  if exist "%%~fF" (
    echo %%~nxF  %%~zF bytes
    certutil -hashfile "%%~fF" SHA256 | findstr /r /v "^$ SHA256"
  )
)

echo.
echo [OK] ABI-split Release APKs are ready in:
echo %CD%\%OUT%
exit /b 0
