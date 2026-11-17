#!/usr/bin/env bash
# Runs every headless test, and exits with an error if any of them fail or
# crash. --fixed-fps lets them run as fast as they can instead of in real
# time, with physics still stepping 1/60 s at a time. Each one gets ten
# minutes, so a test that hangs fails instead of holding everything up.
set -uo pipefail

cd "$(dirname "$0")/.."
GODOT="tools/godot/Godot_v4.7.2-stable_linux.x86_64"
"$GODOT" --headless --path . --import > /dev/null 2>&1

status=0
for test in "-s tests/jetpack_test.gd" "-s tests/ski_test.gd" "-s tests/command_test.gd" "-s tests/main_scene_test.gd"; do
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
