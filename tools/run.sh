#!/usr/bin/env bash
# Runs the game straight from the source with the bundled Godot, in a window,
# without exporting. Extra arguments go to Godot, like --quit-after 300.
set -euo pipefail

cd "$(dirname "$0")/.."
DISPLAY="${DISPLAY:-:0}" exec tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . --windowed "$@"
