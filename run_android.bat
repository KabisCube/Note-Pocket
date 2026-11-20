@echo off
cd /d "%~dp0"
set "JAVA_HOME=%~dp0.tools\java\jdk-17.0.20.1+1"
set "ANDROID_HOME=%~dp0.tools\sdk"
set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"

set "DEVICE_ID="
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices') do (
	if "%%b"=="device" if not defined DEVICE_ID set "DEVICE_ID=%%a"
)

if not defined DEVICE_ID (
	echo No Android device found. Connect the phone with USB debugging enabled.
	pause
	exit /b 1
)

call flutter run -d %DEVICE_ID%
pause
