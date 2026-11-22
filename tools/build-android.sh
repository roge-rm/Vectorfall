#!/usr/bin/env bash
# Builds a debug APK signed with the Android debug key, into build/ and then
# copied to the drop folder.
#
#   tools/build-android.sh             the phone build (arm64 and 32-bit arm)
#   tools/build-android.sh --emulator  the emulator build (x86_64)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION=4.7.2
GODOT="tools/godot/Godot_v${VERSION}-stable_linux.x86_64"
TEMPLATES="tools/godot/editor_data/export_templates/${VERSION}.stable"
BUILD="$PWD/build"
PRESET="Android"
APK="$BUILD/vectorfall-debug.apk"
if [ "${1:-}" = "--emulator" ]; then
	PRESET="Android emulator"
	APK="$BUILD/vectorfall-emulator-debug.apk"
fi
DROP=/srv/downloads/temp/debug/vectorfall
ADB="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools/adb"
# Our own adb server (see ~/.claude/resources.md), so the Godot export never
# starts or stops the shared one on 5037. It's left running, so start it
# detached with only the standard files open: an inherited heavy lock would
# keep the build slot taken after this ends.
export ANDROID_ADB_SERVER_PORT=5052
(
	for fd in /proc/$BASHPID/fd/*; do
		fd=${fd##*/}
		if [ "$fd" -gt 2 ]; then eval "exec $fd>&-"; fi
	done
	exec setsid "$ADB" start-server
) >/dev/null 2>&1 < /dev/null || true

if [ ! -x "$GODOT" ] || [ ! -f "$TEMPLATES/android_debug.apk" ]; then
	echo "Godot $VERSION or its export templates aren't in tools/godot. See README.md." >&2
	exit 1
fi

mkdir -p "$BUILD"
touch "$BUILD/.gdignore"
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$HOME/.android/debug.keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android

if [[ "$PRESET" == Android ]]; then
	tools/prepare-android.sh . "$TEMPLATES"
fi

"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . --export-debug "$PRESET" "$APK"
ls -l "$APK"

if [ -d "$DROP" ]; then
	cp "$APK" "$DROP/"
	echo "Copied to $DROP/$(basename "$APK")"
fi
