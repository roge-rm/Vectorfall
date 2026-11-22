#!/usr/bin/env bash
# Installs the Android Gradle template and adds the Duo panel to it.
set -euo pipefail

project=$(cd "${1:-$(dirname "$0")/..}" && pwd)
source_dir=$(cd "$(dirname "$0")" && pwd)
templates="${2:-$source_dir/godot/editor_data/export_templates/4.7.2.stable}"
archive="$templates/android_source.zip"
android="$project/android"
build="$android/build"

if [[ ! -f "$archive" || ! -f "$templates/version.txt" ]]; then
    printf 'Install the Godot Android source export template in %s.\n' "$templates" >&2
    exit 1
fi

version=$(cat "$templates/version.txt")
if [[ ! -f "$build/gradlew" || ! -f "$android/.build_version" ]] ||
        [[ $(cat "$android/.build_version") != "$version" ]]; then
    mkdir -p "$build"
    unzip -oq "$archive" -d "$build"
    printf '%s\n' "$version" > "$android/.build_version"
fi

chmod +x "$build/gradlew"
touch "$build/.gdignore"
# Clear the previous panel from an Android template already prepared for 0.15.0.
manifest="$build/src/main/AndroidManifest.xml"
old_plugin=org.godotengine.plugin.v2.VectorfallDuo
if grep -Fq "$old_plugin" "$manifest"; then
    sed -i '/android:name="org\.godotengine\.plugin\.v2\.VectorfallDuo"/d; /android:value="com\.rm\.vectorfall\.android\.VectorfallDuo"/d' "$manifest"
fi
rm -f "$build/src/main/java/com/rm/vectorfall/android/VectorfallDuo.java" \
    "$build/src/main/res/drawable-nodpi"/vectorfall_duo_*.png

install -D -m 0644 "$source_dir/android/SkifreiDuo.java" \
    "$build/src/main/java/com/rm/skifrei/android/SkifreiDuo.java"

for shot in ski-jet flag-jet-escape tank-ambush bomber-strike turret-defence; do
    install -D -m 0644 "$source_dir/../docs/images/$shot.png" \
        "$build/src/main/res/drawable-nodpi/skifrei_duo_${shot//-/_}.png"
done

name=org.godotengine.plugin.v2.SkifreiDuo
if ! grep -Fq "$name" "$manifest"; then
    sed -i '/<\/application>/i\        <meta-data android:name="org.godotengine.plugin.v2.SkifreiDuo"\n            android:value="com.rm.skifrei.android.SkifreiDuo" />' "$manifest"
fi
