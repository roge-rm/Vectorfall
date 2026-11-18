#!/usr/bin/env bash
# Plays a headless match of bots only, faster than real time, and writes a
# JSON report to build/bot-reports/.
#
#   tools/bot-match.sh                          8 bots a team, seed 1, 5 minutes, Ochre Fold
#   tools/bot-match.sh --bots 4 --seed 7 --minutes 2
#   tools/bot-match.sh --map test               on the test map
set -euo pipefail

cd "$(dirname "$0")/.."
# Our own adb port (see ~/.claude/resources.md), in case Godot runs adb: it
# must never start the shared server on 5037.
export ANDROID_ADB_SERVER_PORT=5052
GODOT="tools/godot/Godot_v4.7.2-stable_linux.x86_64"
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
# --fixed-fps steps physics 1/60 s each frame with no waiting, so it runs as
# fast as it can.
"$GODOT" --headless --fixed-fps 60 --path . res://tools/bot_match/bot_match.tscn -- "$@" 2>&1 | grep -v "^Godot Engine"
rm -f core.[0-9]*
