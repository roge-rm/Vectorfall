#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export ANDROID_ADB_SERVER_PORT=5052
godot=tools/godot/Godot_v4.7.2-stable_linux.x86_64
mkdir -p build
touch build/.gdignore
check_dir=$(mktemp -d "$PWD/build/online-check.XXXXXX")
server_pid=
cleanup() {
	local result=$?
	if [[ -n "$server_pid" ]]; then
		kill "$server_pid" 2>/dev/null || true
		wait "$server_pid" 2>/dev/null || true
	fi
	if [[ "$result" -ne 0 ]]; then
		tail -40 "$check_dir"/*.log >&2 || true
	fi
	rm -r -- "$check_dir"
}
trap cleanup EXIT

read -r VECTORFALL_GAME_PORT VECTORFALL_DISCOVERY_PORT VECTORFALL_WS_PORT < <(
	python3 - <<'PY'
import socket

ports = [socket.socket(socket.AF_INET, kind)
         for kind in (socket.SOCK_DGRAM, socket.SOCK_DGRAM, socket.SOCK_STREAM)]
for port in ports:
    port.bind(("127.0.0.1", 0))
print(*(port.getsockname()[1] for port in ports))
PY
)
export VECTORFALL_GAME_PORT VECTORFALL_DISCOVERY_PORT VECTORFALL_WS_PORT
export VECTORFALL_TEAM_SIZE=16 VECTORFALL_MAP=test VECTORFALL_STATUS_DIR="$check_dir"
export VECTORFALL_DISCOVERY=1
export XDG_DATA_HOME="$check_dir/data"

"$godot" --headless --path . --import > "$check_dir/import.log" 2>&1
if grep -q 'SCRIPT ERROR' "$check_dir/import.log"; then exit 1; fi
"$godot" --headless --path . res://scenes/server.tscn > "$check_dir/server.log" 2>&1 &
server_pid=$!
for attempt in {1..100}; do
	[[ -s "$check_dir/status.json" ]] && break
	kill -0 "$server_pid"
	sleep .1
done
[[ -s "$check_dir/status.json" ]]
timeout 45 "$godot" --headless --path . -s tests/online_match_test.gd | tee "$check_dir/client.log"
if grep -q 'SCRIPT ERROR' "$check_dir/server.log"; then exit 1; fi
