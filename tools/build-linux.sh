#!/usr/bin/env bash
# Exports the Linux desktop build, x86_64 only, with the game packed into the
# one file.
#
#   tools/build-linux.sh            debug build, build/desktop/vectorfall.x86_64
#   tools/build-linux.sh --release  release build, build/desktop/release/vectorfall.x86_64
#   add --run to start it in a window on DISPLAY=:0 afterwards
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION=4.7.2
GODOT="tools/godot/Godot_v${VERSION}-stable_linux.x86_64"
TEMPLATES="tools/godot/editor_data/export_templates/${VERSION}.stable"
MODE=debug
RUN=0
for arg in "$@"; do
	case "$arg" in
		--release) MODE=release ;;
		--run) RUN=1 ;;
		*) echo "Unknown option $arg" >&2; exit 1 ;;
	esac
done

if [ ! -x "$GODOT" ] || [ ! -f "$TEMPLATES/linux_${MODE}.x86_64" ]; then
	echo "Godot $VERSION or its Linux export templates aren't in tools/godot. See README.md." >&2
	exit 1
fi

# build/desktop is a link to the scratch disk, whose folder may be gone.
mkdir -p "$(readlink -m build/desktop)"
touch build/.gdignore
OUT="$PWD/build/desktop/vectorfall.x86_64"
if [ "$MODE" = release ]; then
	mkdir -p build/desktop/release
	OUT="$PWD/build/desktop/release/vectorfall.x86_64"
fi

"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
"$GODOT" --headless --path . "--export-$MODE" Linux "$OUT"
ls -l "$OUT"

if [ "$RUN" = 1 ]; then
	DISPLAY="${DISPLAY:-:0}" exec "$OUT" --windowed
fi
