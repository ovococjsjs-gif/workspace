#!/bin/bash
# Готовит "песочницу" для интерпретатора Luau:
#   build/luasandbox/ = src/shared + tests, где Roblox-пути require(script.Parent.X)
#   переписаны в require("./X") (в CLI Luau относительные require'ы резолвятся от CWD).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$ROOT/build/luasandbox"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

copy_with_rewrite() {
  local src="$1" dst="$2"
  for f in "$src"/*.luau; do
    [ -e "$f" ] || continue
    sed -E \
      -e 's/require\(script\.Parent\.([A-Za-z0-9_]+)\)/require(".\/\1")/g' \
      -e 's/require\(ReplicatedStorage\.FlockShared\.([A-Za-z0-9_]+)\)/require(".\/\1")/g' \
      -e 's/require\(Shared\.([A-Za-z0-9_]+)\)/require(".\/\1")/g' \
      "$f" > "$dst/$(basename "$f")"
  done
}

copy_with_rewrite "$ROOT/src/shared" "$SANDBOX"
copy_with_rewrite "$ROOT/tests" "$SANDBOX"
echo "$SANDBOX"
