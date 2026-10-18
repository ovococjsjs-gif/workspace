#!/bin/bash
# Диагностический прогон игрового цикла (headless, без Roblox).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUAU_BIN="${LUAU_BIN:-/tmp/luau/build/luau}"
SANDBOX="$ROOT/build/luasandbox"
if [ ! -x "$LUAU_BIN" ]; then echo "Нет интерпретатора Luau" >&2; exit 2; fi
SANDBOX="$("$ROOT/tools/prepare_sandbox.sh" | tail -1)"
cp "$ROOT/tools/probe.luau" "$SANDBOX/probe.luau"
cd "$SANDBOX" && "$LUAU_BIN" probe.luau
