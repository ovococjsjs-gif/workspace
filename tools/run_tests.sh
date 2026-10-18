#!/bin/bash
# Тесты чистой логики игры «СТАЯ» на настоящем интерпретаторе Luau.
#
# Что делает:
#   1. Собирает "песочницу" build/luasandbox/: копирует src/shared, src/client,
#      src/server, tests и tools, переписывая Roblox-пути require(script.Parent.X)
#      на require("./X") (в CLI Luau относительные require'ы резолвятся от CWD,
#      а не от файла).
#   2. Прогоняет юнит-тесты чистой логики: luau run.luau
#   3. Гоняет статический анализ luau-analyze по чистой логике и тестам.
#      (Клиент/сервер не анализируются: в CLI нет Roblox-типов Part/Vector3/...,
#      поэтому анализатор выдавал бы ложные "Unknown type". Их покрывает
#      smoke-тест — см. tools/smoke.sh.)
#   4. Прогоняет smoke-тест клиентского и серверного слоя против мока Roblox API.
#
# Требуется LUAU_BIN (по умолчанию /tmp/luau/build/luau) — см. tools/build_luau.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LUAU_BIN="${LUAU_BIN:-/tmp/luau/build/luau}"
ANALYZE_BIN="${ANALYZE_BIN:-/tmp/luau/build/luau-analyze}"

if [ ! -x "$LUAU_BIN" ]; then
  echo "НЕ НАЙДЕН интерпретатор Luau: $LUAU_BIN" >&2
  echo "Соберите его: bash tools/build_luau.sh" >&2
  exit 2
fi

SANDBOX="$("$ROOT/tools/prepare_sandbox.sh")"

echo "== Юнит-тесты (luau $LUAU_BIN) =="
cd "$SANDBOX"
"$LUAU_BIN" run.luau

echo ""
echo "== Smoke-тест клиента/сервера (мок Roblox API) =="
"$LUAU_BIN" client_smoke.luau

if [ -x "$ANALYZE_BIN" ]; then
  echo ""
  echo "== Статический анализ (luau-analyze, чистая логика + тесты) =="
  # Клиентские и серверные файлы исключены: им нужны Roblox-типы.
  ANALYZE_FILES=()
  for f in "$SANDBOX"/*.luau; do
    base="$(basename "$f")"
    case "$base" in
      Audio.luau|HUD.luau|Input.luau|Main.luau|MainServer.luau|Views.luau|World.luau|roblox_mock.luau|client_smoke.luau|probe.luau|scenario.luau)
        continue
        ;;
    esac
    ANALYZE_FILES+=("$f")
  done
  ANALYZE_OUT="$("$ANALYZE_BIN" --formatter=plain "${ANALYZE_FILES[@]}" 2>&1 || true)"
  echo "$ANALYZE_OUT"
  if echo "$ANALYZE_OUT" | grep -qE "TypeError|SyntaxError|UnknownSymbol|UnknownType|UnknownGlobal"; then
    echo "!! luau-analyze нашёл проблемы в типах — см. вывод выше" >&2
    exit 1
  fi
  echo "luau-analyze: ошибок нет"

  # Клиент и сервер тоже анализируются — в песочнице им подставлены
  # заглушки Roblox-типов (см. tools/prepare_sandbox.sh).
  # Два известных ограничения песочницы, которые фильтруются:
  #   * "Unknown type 'Enum.*'" — локаль-значение `Enum` перекрывает тип-алиас;
  #   * LocalUnused/ImportUnused — шум от заголовка мока и GUI-меток,
  #     которые используются через Parent, а не через переменную.
  echo ""
  echo "== Статический анализ клиента и сервера (luau-analyze) =="
  CLIENT_FILES=()
  for name in Audio HUD Input Main MainServer Views World; do
    CLIENT_FILES+=("$SANDBOX/$name.luau")
  done
  CLIENT_OUT="$("$ANALYZE_BIN" --formatter=plain "${CLIENT_FILES[@]}" 2>&1 || true)"
  CLIENT_FILTERED="$(echo "$CLIENT_OUT" | grep -vE 'LocalUnused|ImportUnused' | grep -vE 'Unknown type .Enum\.' || true)"
  if [ -n "$CLIENT_FILTERED" ]; then
    echo "$CLIENT_FILTERED"
    echo "!! luau-analyze нашёл проблемы в клиенте/сервере — см. вывод выше" >&2
    exit 1
  fi
  echo "luau-analyze (клиент/сервер): ошибок нет"
else
  echo ""
  echo "!! luau-analyze не найден ($ANALYZE_BIN) — статический анализ пропущен" >&2
fi
