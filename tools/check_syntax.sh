#!/bin/bash
# Синтаксическая проверка всех Luau-файлов игры настоящим компилятором Luau.
# luau-compile разбирает файл и компилирует в байткод: ловит синтаксические ошибки.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILE_BIN="${COMPILE_BIN:-/tmp/luau/build/luau-compile}"

if [ ! -x "$COMPILE_BIN" ]; then
  echo "НЕ НАЙДЕН luau-compile: $COMPILE_BIN" >&2
  echo "Соберите его: bash tools/build_luau.sh" >&2
  exit 2
fi

FAILED=0
for f in "$ROOT"/src/*/*.luau "$ROOT"/tests/*.luau; do
  OUT="$("$COMPILE_BIN" "$f" 2>&1 >/dev/null)"
  if [ -n "$OUT" ]; then
    echo "### $f"
    echo "$OUT"
    FAILED=1
  fi
done

if [ "$FAILED" -eq 0 ]; then
  echo "Синтаксис: ошибок нет ($(ls "$ROOT"/src/*/*.luau "$ROOT"/tests/*.luau | wc -l) файлов)"
else
  echo "Синтаксис: есть ошибки" >&2
fi
exit $FAILED
