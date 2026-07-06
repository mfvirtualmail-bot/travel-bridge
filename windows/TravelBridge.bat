@echo off
rem Double-click launcher for the TravelBridge companion app.
rem Runs the PowerShell app with no console window.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0TravelBridge.ps1"
