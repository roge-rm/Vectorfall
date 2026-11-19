#!/usr/bin/env bash
# Builds the route graph links for each map and saves them under maps/. Run it
# after changing a map's ground, points or route settings; a map falls back to
# building its links at load, with a warning, until you do.
set -euo pipefail

cd "$(dirname "$0")/.."
export ANDROID_ADB_SERVER_PORT=5052
GODOT="tools/godot/Godot_v4.7.2-stable_linux.x86_64"
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . -s tools/bake_routes.gd 2>&1 | grep -v "^Godot Engine"
rm -f core.[0-9]*
