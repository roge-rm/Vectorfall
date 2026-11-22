#!/usr/bin/env bash
# Exports the Linux desktop build with the game packed into the executable.
#
#   tools/build-linux.sh            debug build, build/desktop/skifrei.x86_64
#   tools/build-linux.sh --release  release build, build/desktop/release/skifrei.x86_64
#   add --arch arm64 for an ARM build
#   add --run to start it in a window on DISPLAY=:0 afterwards
set -euo pipefail

cd "$(dirname "$0")/.."
# Our own adb port (see ~/.claude/resources.md), in case Godot runs adb: it
# must never start the shared server on 5037.
export ANDROID_ADB_SERVER_PORT=5052
VERSION=4.7.2
GODOT="tools/godot/Godot_v${VERSION}-stable_linux.x86_64"
TEMPLATES="tools/godot/editor_data/export_templates/${VERSION}.stable"
MODE=debug
RUN=0
ARCH=x86_64
while [[ $# -gt 0 ]]; do
	case "$1" in
		--release) MODE=release ;;
		--run) RUN=1 ;;
		--arch)
			case "${2:-}" in
				amd64) ARCH=x86_64 ;;
				arm64) ARCH=arm64 ;;
				*) echo "Choose --arch amd64 or --arch arm64." >&2; exit 1 ;;
			esac
			shift ;;
		*) echo "Unknown option $1" >&2; exit 1 ;;
	esac
	shift
done
PRESET=Linux
if [[ "$ARCH" == arm64 ]]; then PRESET="Linux arm64"; fi

if [ ! -x "$GODOT" ] || [ ! -f "$TEMPLATES/linux_${MODE}.$ARCH" ]; then
	echo "Install Godot $VERSION and the Linux $ARCH $MODE export template in tools/godot." >&2
	exit 1
fi

# build/desktop is a link to the scratch disk, whose folder may be gone.
mkdir -p "$(readlink -m build/desktop)"
touch build/.gdignore
OUT="$PWD/build/desktop/skifrei.$ARCH"
if [ "$MODE" = release ]; then
	mkdir -p build/desktop/release
	OUT="$PWD/build/desktop/release/skifrei.$ARCH"
fi

"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . "--export-$MODE" "$PRESET" "$OUT"
ls -l "$OUT"

if [ "$RUN" = 1 ]; then
	if [[ "$ARCH" == arm64 ]]; then
		DISPLAY="${DISPLAY:-:0}" exec "$OUT" --rendering-driver opengl3_es --windowed
	fi
	DISPLAY="${DISPLAY:-:0}" exec "$OUT" --windowed
fi
