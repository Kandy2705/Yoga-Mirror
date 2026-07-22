@echo off
setlocal enabledelayedexpansion
where flutter >nul 2>nul
if errorlevel 1 (
  echo Khong tim thay Flutter SDK trong PATH.
  exit /b 1
)

set "TMP_PROJECT=%TEMP%\yoga_mirror_rive_demo_%RANDOM%%RANDOM%"
flutter create --platforms=android,ios --org com.yogamirror --project-name yoga_mirror_rive_demo "%TMP_PROJECT%"
if errorlevel 1 exit /b 1

if exist android rmdir /s /q android
if exist ios rmdir /s /q ios
xcopy /e /i /q "%TMP_PROJECT%\android" android >nul
xcopy /e /i /q "%TMP_PROJECT%\ios" ios >nul
rmdir /s /q "%TMP_PROJECT%"
flutter pub get
if errorlevel 1 exit /b 1

echo.
echo Xong. Ket noi dien thoai roi chay: flutter run
