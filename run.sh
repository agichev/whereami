#!/usr/bin/env bash
# Импортирует ассеты (нужно один раз после клонирования) и запускает игру из исходников.
# Godot ищется в PATH, рядом с проектом (./godot или ./godot.exe) или в $GODOT_BIN.
set -e
cd "$(dirname "$0")"

GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
    if [ -x "./godot" ]; then
        GODOT="./godot"
    elif [ -x "./godot.exe" ]; then
        GODOT="./godot.exe"
    else
        GODOT="godot"
    fi
fi

"$GODOT" --headless --path . --import
exec "$GODOT" --path .
