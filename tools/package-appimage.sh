#!/usr/bin/env bash
# Packages the x86-64 Linux release as a single AppImage.
set -euo pipefail

cd "$(dirname "$0")/.."
version=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
tools/build-linux.sh --release
build="$PWD/build/desktop"
stage=$(mktemp -d "$build/appimage.XXXXXX")
trap 'rm -r -- "$stage"' EXIT
appdir="$stage/Skifrei.AppDir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/doc/skifrei" "$stage/tmp"

tool="$stage/appimagetool.AppImage"
runtime="$stage/runtime-x86_64"
curl --fail --location --retry 3 -o "$tool" \
    https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
curl --fail --location --retry 3 -o "$runtime" \
    https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64
printf '%s  %s\n' \
    ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0 "$tool" \
    2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d "$runtime" | sha256sum --check
chmod +x "$tool"

install -m 755 "$build/release/skifrei.x86_64" "$appdir/usr/bin/skifrei"
install -m 644 tools/desktop/skifrei.desktop "$appdir/"
install -m 644 art/icon.png "$appdir/skifrei.png"
install -m 644 LICENSE "$appdir/usr/share/doc/skifrei/copyright"
cat > "$appdir/AppRun" <<'RUN'
#!/bin/sh
appdir=$(dirname "$(readlink -f "$0")")
exec "$appdir/usr/bin/skifrei" "$@"
RUN
chmod 755 "$appdir/AppRun"

name="skifrei-$version-x86_64.AppImage"
TMPDIR="$stage/tmp" APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 \
    "$tool" --no-appstream --comp zstd --runtime-file "$runtime" "$appdir" "$stage/$name"
mv "$stage/$name" "$build/$name"
ls -l "$build/$name"
