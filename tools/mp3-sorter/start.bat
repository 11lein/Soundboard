@echo off
rem Doppelklick-Starter fuer den MP3 Sorter (Windows).
cd /d "%~dp0"
set "ELECTRON_RUN_AS_NODE="

where npm >nul 2>nul
if errorlevel 1 (
  echo Node.js/npm ist nicht installiert. Bitte von https://nodejs.org installieren.
  pause
  exit /b 1
)

if not exist node_modules (
  echo Installiere Abhaengigkeiten ^(einmalig^)...
  call npm install || (echo npm install fehlgeschlagen. & pause & exit /b 1)
)

call npm start
