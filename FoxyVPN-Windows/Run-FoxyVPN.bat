@echo off
title FoxyVPN Launcher
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0FoxyVPN-Control.ps1"
