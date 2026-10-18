#!/bin/bash
# Тесты чистой логики игры «СТАЯ» на настоящем интерпретаторе Luau.
#
# Что делает:
#   1. Собирает "песочницу" build/luasandbox/: копирует src/shared и tests,
#      переписывая Roblox-пути require(script.Parent.X) на require("./X")
#      (в CLI Luau относительные require'ы резолвятся от CWD, а не от файла).
#   2. Прогоняет юнит-тесты: luau run.luau
#   3. Гоняет статический анализ luau-analyze по песочнице (реальные типы модулей).
#
# Требуется LUAU_BIN (по умолчанию /tmp/luau/build/luau) — см. tools/build_luau.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUAU_BIN="${LUAU_BIN:-/tmp/luau/build/luau}"
ANALYZE_BIN="${ANALYZE_BIN:-/tmp/luau/build/luau-analyze}"
SANDBOX="$ROOT/build/luasandbox"

if [ ! -x "$LUAU_BIN" ]; then
  echo "НЕ НАЙДЕН интерпретатор Luau: $LUAU_BIN" >&2
  echo "Соберите его: bash tools/build_luau.sh" >&2
  exit 2
fi

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

# Копируем модули и переписываем пути require.
copy_with_rewrite() {
  local src="$1" dst="$2"
  for f in "$src"/*.luau; do
    [ -e "$f" ] || continue
    sed -E \
      -e 's/require\(script\.Parent\.([A-Za-z0-9_]+)\)/require(".\/\1")/g' \
      -e 's/require\(ReplicatedStorage\.FlockShared\.([A-Za-z0-9_]+)\)/require(".\/\1")/g' \
      "$f" > "$dst/$(basename "$f")"
  done
}

copy_with_rewrite "$ROOT/src/shared" "$SANDBOX"
copy_with_rewrite "$ROOT/tests" "$SANDBOX"

echo "== Юнит-тесты (luau $LUAU_BIN) =="
cd "$SANDBOX"
"$LUAU_BIN" run.luau

if [ -x "$ANALYZE_BIN" ]; then
  echo ""
  echo "== Статический анализ (luau-analyze) =="
  ANALYZE_OUT="$("$ANALYZE_BIN" --formatter=plain "$SANDBOX"/*.luau 2>&1 || true)"
  echo "$ANALYZE_OUT"
  if echo "$ANALYZE_OUT" | grep -qE "TypeError|SyntaxError|UnknownSymbol|UnknownType|UnknownGlobal"; then
    echo "!! luau-analyze нашёл проблемы в типах — см. вывод выше" >&2
    exit 1
  fi
  echo "luau-analyze: ошибок нет"
else
  echo ""
  echo "!! luau-analyze не найден ($ANALYZE_BIN) — статический анализ пропущен" >&2
fi
