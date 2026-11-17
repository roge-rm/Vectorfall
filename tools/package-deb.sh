#!/usr/bin/env bash
# Exports the release Linux build and packs it into
# build/desktop/vectorfall_V_amd64.deb, for Debian trixie on amd64. V is
# version/name in export_presets.cfg. The game goes in /usr/lib/vectorfall,
# a launcher in /usr/games, with a menu entry and the icon.
#
#   tools/package-deb.sh
set -euo pipefail

cd "$(dirname "$0")/.."
V=$(sed -n 's/^version\/name="\(.*\)"/\1/p' export_presets.cfg | head -n 1)
SRC=tools/desktop
tools/build-linux.sh --release
BUILD=$PWD/build/desktop
stage=$BUILD/deb-amd64
rm -rf "$stage"
install -d -m 755 "$stage/usr/lib/vectorfall" "$stage/usr/games" "$stage/usr/share/applications" \
	"$stage/usr/share/icons/hicolor/scalable/apps" "$stage/usr/share/icons/hicolor/256x256/apps" \
	"$stage/usr/share/doc/vectorfall" "$stage/DEBIAN"
install -m 755 "$BUILD/release/vectorfall.x86_64" "$stage/usr/lib/vectorfall/vectorfall"
install -m 755 $SRC/launcher "$stage/usr/games/vectorfall"
install -m 644 $SRC/vectorfall.desktop "$stage/usr/share/applications/vectorfall.desktop"
install -m 644 art/icon.svg "$stage/usr/share/icons/hicolor/scalable/apps/vectorfall.svg"
convert -background none art/icon.svg -resize 256x256 "$stage/usr/share/icons/hicolor/256x256/apps/vectorfall.png" 2> /dev/null
chmod 644 "$stage/usr/share/icons/hicolor/256x256/apps/vectorfall.png"
install -m 644 LICENSE "$stage/usr/share/doc/vectorfall/copyright"
kb=$(du -sk --exclude=DEBIAN "$stage" | cut -f1)
sed "s/@VERSION@/$V/; s/@SIZE@/$kb/" $SRC/control > "$stage/DEBIAN/control"
DEB="$BUILD/vectorfall_${V}_amd64.deb"
dpkg-deb --root-owner-group -Zxz --build "$stage" "$DEB" > /dev/null
rm -rf "$stage"
ls -l "$DEB"
