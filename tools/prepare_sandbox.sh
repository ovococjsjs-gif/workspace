#!/bin/bash
# Готовит "песочницу" для интерпретатора Luau:
#   build/luasandbox/ = src/shared + src/client + src/server + tests + tools,
#   где Roblox-пути require(script.Parent.X) переписаны в require("./X")
#   (в CLI Luau относительные require'ы резолвятся от CWD).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$ROOT/build/luasandbox"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

# Заголовок для клиентских/серверных файлов: подставляет мок Roblox-глобалов.
# (В CLI каждый require-модуль имеет свою копию глобалов, поэтому алиасы
#  объявляются локально в каждом файле.)
MOCK_HEADER='-- Мок Roblox API (инструмент tools/smoke.sh).
local __mock = require("./roblox_mock")
local game = __mock.env.game
local workspace = __mock.env.workspace
local Instance = __mock.env.Instance
local Vector3 = __mock.env.Vector3
local CFrame = __mock.env.CFrame
local UDim2 = __mock.env.UDim2
local UDim = __mock.env.UDim
local Color3 = __mock.env.Color3
local Enum = __mock.env.Enum
local TweenInfo = __mock.env.TweenInfo
local NumberSequence = __mock.env.NumberSequence
local ColorSequence = __mock.env.ColorSequence
local ColorSequenceKeypoint = __mock.env.ColorSequenceKeypoint
local NumberSequenceKeypoint = __mock.env.NumberSequenceKeypoint
local task = __mock.env.task
'

copy_with_rewrite() {
  local src="$1" dst="$2" header="$3" prefix="$4"
  [ -d "$src" ] || return 0
  for f in "$src"/*.luau; do
    [ -e "$f" ] || continue
    # Убираем суффиксы .client/.server, чтобы require("./Input") совпадал с именем.
    local base
    base="$(basename "$f" .luau)"
    base="${base%.client}"
    base="${base%.server}"
    if [ "$prefix" = "server" ] && [ "$base" = "Main" ]; then
      base="MainServer"
    fi
    base="$base.luau"
    if [ -n "$header" ]; then
      printf '%s' "$header" > "$dst/$base"
    fi
    sed -E \
      -e 's/require\(script\.Parent\.([A-Za-z0-9_]+)\)/require(".\/\1")/g' \
      -e 's/require\(ReplicatedStorage\.FlockShared\.([A-Za-z0-9_]+)\)/require(".\/\1")/g' \
      -e 's/require\(Shared\.([A-Za-z0-9_]+)\)/require(".\/\1")/g' \
      "$f" >> "$dst/$base"
    # Серверный скрипт в Roblox ничего не возвращает, но require в CLI
    # требует ровно одно значение — добавляем заглушку в песочнице.
    if [ "$prefix" = "server" ]; then
      printf '\nreturn {}\n' >> "$dst/$base"
    fi
  done
}

copy_with_rewrite "$ROOT/src/shared" "$SANDBOX" "" shared
copy_with_rewrite "$ROOT/src/client" "$SANDBOX" "$MOCK_HEADER" client
copy_with_rewrite "$ROOT/src/server" "$SANDBOX" "$MOCK_HEADER" server
copy_with_rewrite "$ROOT/tests" "$SANDBOX" "" tests
copy_with_rewrite "$ROOT/tools" "$SANDBOX" "" tools
# Инструменты: снимаем .luau, чтобы require("./probe") работал одинаково.
for f in "$ROOT/tools"/*.luau; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .luau)"
  cp "$f" "$SANDBOX/$base.luau"
done
echo "$SANDBOX"
