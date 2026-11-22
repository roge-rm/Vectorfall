#!/usr/bin/env bash
# Exports the release Linux build and packs it into
# build/desktop/vectorfall_V_ARCH.deb, for Debian Trixie. V is
# version/name in export_presets.cfg. The game goes in /usr/lib/vectorfall,
# a launcher in /usr/games, with a menu entry and the icon.
#
#   tools/package-deb.sh [--arch amd64|arm64]
set -euo pipefail

cd "$(dirname "$0")/.."
DEB_ARCH=amd64
if [[ $# -gt 0 ]]; then
	if [[ $# -ne 2 || "$1" != --arch ]]; then
		echo "Usage: $0 [--arch amd64|arm64]" >&2
		exit 1
	fi
	DEB_ARCH=$2
fi
case "$DEB_ARCH" in
	amd64) BINARY_ARCH=x86_64; RENDERING_DRIVER=; EXTRA_DEPS= ;;
	arm64) BINARY_ARCH=arm64; RENDERING_DRIVER="--rendering-driver opengl3_es"; EXTRA_DEPS=", libgles2" ;;
	*) echo "Choose --arch amd64 or --arch arm64." >&2; exit 1 ;;
esac
V=$(sed -n 's/^version\/name="\(.*\)"/\1/p' export_presets.cfg | head -n 1)
SRC=tools/desktop
tools/build-linux.sh --release --arch "$DEB_ARCH"
BUILD=$PWD/build/desktop
stage=$(mktemp -d "$BUILD/deb-$DEB_ARCH.XXXXXX")
trap 'rm -r -- "$stage"' EXIT
chmod 755 "$stage"
install -d -m 755 "$stage/usr/lib/vectorfall" "$stage/usr/games" "$stage/usr/share/applications" \
	"$stage/usr/share/icons/hicolor/scalable/apps" "$stage/usr/share/icons/hicolor/256x256/apps" \
	"$stage/usr/share/doc/vectorfall" "$stage/DEBIAN"
install -m 755 "$BUILD/release/vectorfall.$BINARY_ARCH" "$stage/usr/lib/vectorfall/vectorfall"
sed "s/@RENDERING_DRIVER@/$RENDERING_DRIVER/" "$SRC/launcher" > "$stage/usr/games/vectorfall"
chmod 755 "$stage/usr/games/vectorfall"
install -m 644 $SRC/vectorfall.desktop "$stage/usr/share/applications/vectorfall.desktop"
install -m 644 art/icon.svg "$stage/usr/share/icons/hicolor/scalable/apps/vectorfall.svg"
convert -background none art/icon.svg -resize 256x256 "$stage/usr/share/icons/hicolor/256x256/apps/vectorfall.png" 2> /dev/null
chmod 644 "$stage/usr/share/icons/hicolor/256x256/apps/vectorfall.png"
install -m 644 LICENSE "$stage/usr/share/doc/vectorfall/copyright"
kb=$(du -sk --exclude=DEBIAN "$stage" | cut -f1)
sed "s/@VERSION@/$V/; s/@SIZE@/$kb/; s/@ARCH@/$DEB_ARCH/; s/@EXTRA_DEPS@/$EXTRA_DEPS/" "$SRC/control" > "$stage/DEBIAN/control"
DEB="$BUILD/vectorfall_${V}_$DEB_ARCH.deb"
dpkg-deb --root-owner-group -Zxz --build "$stage" "$DEB" > /dev/null
ls -l "$DEB"
