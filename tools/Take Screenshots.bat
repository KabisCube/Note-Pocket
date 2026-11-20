@echo off
cd /d "%~dp0.."
call flutter test --update-goldens "tools/screenshots/screenshots_test.dart"
echo.
echo Screenshots are in docs\screenshots
pause
