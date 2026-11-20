@echo off
rem Импортирует ассеты (нужно один раз после клонирования) и запускает игру из исходников.
rem Godot ищется рядом с проектом (godot.exe) или в PATH, либо задается через GODOT_BIN.
rem Опциональный аргумент: --opengl (запуск на OpenGL/Compatibility, если Vulkan не поддерживается)
setlocal
cd /d "%~dp0"

set "GODOT=%GODOT_BIN%"
if "%GODOT%"=="" if exist "%~dp0godot.exe" set "GODOT=%~dp0godot.exe"
if "%GODOT%"=="" set "GODOT=godot"

set "EXTRA_ARGS="
if "%~1"=="--opengl" set "EXTRA_ARGS=--rendering-method gl_compatibility --rendering-driver opengl3"

"%GODOT%" --headless --path . --import
if errorlevel 1 (
    echo.
    echo Import failed. Make sure Godot 4.7.x is installed and available as "godot" in PATH,
    echo or put godot.exe next to project.godot.
    pause
    exit /b 1
)

"%GODOT%" --path . %EXTRA_ARGS%
