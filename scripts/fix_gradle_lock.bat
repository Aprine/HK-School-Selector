@echo off
setlocal

echo [1/6] Switching to project root...
cd /d "%~dp0\.." || (
  echo Failed to switch to project root.
  exit /b 1
)

echo [2/6] Stopping Gradle daemons...
if exist "android\gradlew.bat" (
  call "android\gradlew.bat" --stop
) else (
  echo gradlew.bat not found, skipping Gradle daemon stop.
)

echo [3/6] Killing possible lock owners...
taskkill /F /IM java.exe >nul 2>&1
taskkill /F /IM javaw.exe >nul 2>&1
taskkill /F /IM gradle.exe >nul 2>&1

echo [4/6] Removing Gradle lock files...
if exist "android\.gradle\noVersion\buildLogic.lock" del /F /Q "android\.gradle\noVersion\buildLogic.lock"
if exist "android\.gradle\noVersion\buildLogic\buildLogic.lock" del /F /Q "android\.gradle\noVersion\buildLogic\buildLogic.lock"

echo [5/6] Running flutter clean...
call flutter clean
if errorlevel 1 (
  echo flutter clean failed.
  exit /b 1
)

echo [6/6] Running flutter pub get...
call flutter pub get
if errorlevel 1 (
  echo flutter pub get failed.
  exit /b 1
)

echo.
echo Done. Gradle lock cleanup completed.
echo Try running: flutter run -d chrome
endlocal
