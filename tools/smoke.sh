#!/bin/bash
# Smoke-тест клиентского и серверного слоя против мока Roblox API.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUAU_BIN="${LUAU_BIN:-/tmp/luau/build/luau}"
SANDBOX="$("$ROOT/tools/prepare_sandbox.sh" | tail -1)"
if [ ! -x "$LUAU_BIN" ]; then echo "Нет интерпретатора Luau" >&2; exit 2; fi
cd "$SANDBOX" && "$LUAU_BIN" client_smoke.luau
