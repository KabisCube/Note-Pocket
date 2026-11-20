@echo off
cd /d "%~dp0.."
set "BUILD_FOLDER=build\windows\x64\runner\Release"
set "OUTPUT_FOLDER=dist\NotePocket-windows"

call flutter build windows --release
if errorlevel 1 (
	echo Build failed.
	pause
	exit /b 1
)

if exist "%OUTPUT_FOLDER%" rmdir /s /q "%OUTPUT_FOLDER%"
xcopy /e /i /q "%BUILD_FOLDER%" "%OUTPUT_FOLDER%" >nul

echo.
echo Built %OUTPUT_FOLDER%\note_pocket.exe
explorer "%OUTPUT_FOLDER%"
pause
