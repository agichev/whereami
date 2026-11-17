@echo off
rem Импортирует ассеты (нужно один раз после клонирования) и запускает игру из исходников.
rem Godot ищется рядом с проектом (godot.exe) или в PATH, либо задается через GODOT_BIN.
setlocal
cd /d "%~dp0"

set "GODOT=%GODOT_BIN%"
if "%GODOT%"=="" if exist "%~dp0godot.exe" set "GODOT=%~dp0godot.exe"
if "%GODOT%"=="" set "GODOT=godot"

"%GODOT%" --headless --path . --import
if errorlevel 1 (
    echo.
    echo Import failed. Make sure Godot 4.7.x is installed and available as "godot" in PATH,
    echo or put godot.exe next to project.godot.
    pause
    exit /b 1
)

"%GODOT%" --path .
