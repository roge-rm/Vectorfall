#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export ANDROID_ADB_SERVER_PORT=5052
godot=tools/godot/Godot_v4.7.2-stable_linux.x86_64
templates=tools/godot/editor_data/export_templates/4.7.2.stable
if [[ ! -f "$templates/web_nothreads_release.zip" ]]; then
	echo "Install the Godot 4.7.2 Web export template." >&2
	exit 1
fi
mkdir -p "$(readlink -m build/web)"
touch build/.gdignore
"$godot" --headless --path . --import
"$godot" --headless --path . --export-release Web "$PWD/build/web/index.html"
