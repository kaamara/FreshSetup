@echo off
rem FreshSetup - uruchamia aplikacje. Poprosi o uprawnienia administratora (UAC).
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0FreshSetup.ps1"
