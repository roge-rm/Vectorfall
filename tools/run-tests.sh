#!/usr/bin/env bash
# Runs every headless test, or the ones named (tools/run-tests.sh menu_test
# sound_test), and exits with an error if any of them fail or
# crash. --fixed-fps lets them run as fast as they can instead of in real
# time, with physics still stepping 1/60 s at a time. Each one gets ten
# minutes, so a test that hangs fails instead of holding everything up.
set -uo pipefail

cd "$(dirname "$0")/.."
# Our own adb port (see ~/.claude/resources.md), in case Godot runs adb: it
# must never start the shared server on 5037.
export ANDROID_ADB_SERVER_PORT=5052
GODOT="tools/godot/Godot_v4.7.2-stable_linux.x86_64"
"$GODOT" --headless --path . --import > /dev/null 2>&1

tests=()
for name in "$@"; do
	tests+=("-s tests/${name%.gd}.gd")
done
status=0
if [ ${#tests[@]} -eq 0 ]; then tests=("-s tests/jetpack_test.gd" "-s tests/ski_test.gd" "-s tests/command_test.gd" "-s tests/weapon_test.gd" "-s tests/armour_test.gd" "-s tests/throw_test.gd" "-s tests/pack_test.gd" "-s tests/station_test.gd" "-s tests/base_power_test.gd" "-s tests/deploy_test.gd" "-s tests/vehicle_test.gd" "-s tests/vehicle_bots_test.gd" "-s tests/force_field_test.gd" "-s tests/flag_test.gd" "-s tests/map_test.gd" "-s tests/terrain_test.gd" "-s tests/ochre_fold_test.gd" "-s tests/route_test.gd" "-s tests/perception_test.gd" "-s tests/bot_move_test.gd" "-s tests/bot_fight_test.gd" "-s tests/commander_test.gd" "-s tests/orders_test.gd" "-s tests/main_scene_test.gd" "-s tests/menu_test.gd" "-s tests/sound_test.gd"); fi
for test in "${tests[@]}"; do
	echo "== $test"
	# shellcheck disable=SC2086
	out=$(timeout 600 "$GODOT" --headless --fixed-fps 60 --path . $test 2>&1)
	code=$?
	echo "$out" | grep -E "^  (ok|FAIL)|passed|failed|ERROR"
	if [ $code -ne 0 ]; then
		echo "   that test exited with an error"
		status=1
	fi
	# A script error doesn't always stop a test, so count it as a failure.
	if echo "$out" | grep -q "SCRIPT ERROR"; then
		status=1
	fi
done
rm -f core.[0-9]*
exit $status
