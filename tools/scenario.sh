#!/bin/bash
# Прогон сценария пилота: bash tools/scenario.sh [calm|reckless|zigzag]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUAU_BIN="${LUAU_BIN:-/tmp/luau/build/luau}"
SANDBOX="$("$ROOT/tools/prepare_sandbox.sh" | tail -1)"
sed -e "s/__MODE__/${1:-calm}/g" -e "s/__SECONDS__/${2:-90}/g" "$ROOT/tools/scenario.luau" > "$SANDBOX/scenario.luau"
cd "$SANDBOX" && "$LUAU_BIN" scenario.luau
