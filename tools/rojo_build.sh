#!/usr/bin/env bash
# Сборка проекта через Rojo — проверка, что манифест default.project.json
# корректен и все файлы попадают в place-файл.
#
# Rojo ставится отдельно: https://rojo.space/ (или npm-пакет `rojo`).
# Если rojo не найден — скрипт честно сообщает об этом и завершается с кодом 0:
# сборка не обязательна для проверок логики, но её наличие в логах — хороший
# аргумент, что структура проекта валидна.
set -u

cd "$(dirname "$0")/.." || exit 1

ROJO_BIN="${ROJO_BIN:-}"
if [ -z "$ROJO_BIN" ]; then
	if command -v rojo >/dev/null 2>&1; then
		ROJO_BIN="$(command -v rojo)"
	elif [ -x "/tmp/rojopkg/node_modules/.bin/rojo" ]; then
		ROJO_BIN="/tmp/rojopkg/node_modules/.bin/rojo"
	else
		echo "rojo не найден — сборка place-файла пропущена."
		echo "Установите Rojo (https://rojo.space/) или выполните:"
		echo "  npm install --prefix /tmp/rojopkg rojo@1.0.3-rojo7.7.0-rc.1"
		echo "и повторите: ROJO_BIN=/tmp/rojopkg/node_modules/.bin/rojo bash tools/rojo_build.sh"
		exit 0
	fi
fi

OUT="${1:-/tmp/flock.rbxlx}"
echo "# tools/rojo_build.sh — $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "# rojo: $ROJO_BIN ($("$ROJO_BIN" --version 2>/dev/null))"
echo "# выходной файл: $OUT"

if ! "$ROJO_BIN" build default.project.json -o "$OUT"; then
	echo "СБОРКА ROJO ПРОВАЛЕНА"
	exit 1
fi

SIZE=$(wc -c < "$OUT")
echo "Сборка успешна: $OUT ($SIZE байт)"

# Проверяем, что в place-файле ожидаемые контейнеры.
for name in FlockShared FlockServer FlockClient Config Game Flock Views HUD Audio Input World; do
	if grep -q "<string name=\"Name\">$name</string>" "$OUT"; then
		echo "  ok   $name на месте"
	else
		echo "  FAIL $name не найден в place-файле"
		exit 1
	fi
done

echo "СТРУКТУРА PLACE-ФАЙЛА КОРРЕКТНА"
