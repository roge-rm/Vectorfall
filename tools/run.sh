#!/usr/bin/env bash
# Runs the game straight from the source with the bundled Godot, in a window,
# without exporting. Extra arguments go to Godot, like --quit-after 300.
set -euo pipefail

cd "$(dirname "$0")/.."
# Our own adb port (see ~/.claude/resources.md), in case Godot runs adb: it
# must never start the shared server on 5037.
export ANDROID_ADB_SERVER_PORT=5052
DISPLAY="${DISPLAY:-:0}" exec tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . --windowed "$@"
