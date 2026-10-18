#!/bin/bash
# Перегенерация логов проверок в docs/evidence/.
#
# Каждый лог — это вывод конкретной команды проекта, поэтому по логу можно
# проверить утверждение отчёта без запуска чего-либо.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/evidence"
mkdir -p "$OUT"

FAILED=0

run_log() {
	local name="$1"
	shift
	echo "== $name"
	if "$@" >"$OUT/$name.log" 2>&1; then
		echo "   ok (лог: docs/evidence/$name.log)"
	else
		echo "   FAIL (лог: docs/evidence/$name.log)"
		FAILED=1
	fi
}

run_log run_tests bash "$ROOT/tools/run_tests.sh"
run_log check_syntax bash "$ROOT/tools/check_syntax.sh"
run_log smoke bash "$ROOT/tools/smoke.sh"
run_log probe bash "$ROOT/tools/probe.sh"
run_log scenario_calm bash "$ROOT/tools/scenario.sh" calm 90
run_log scenario_booster bash "$ROOT/tools/scenario.sh" booster 90
run_log scenario_nervous bash "$ROOT/tools/scenario.sh" nervous 150
run_log scenario_calm_5min bash "$ROOT/tools/scenario.sh" calm 300
run_log scenario_reckless bash "$ROOT/tools/scenario.sh" reckless 90
run_log rojo_build bash "$ROOT/tools/rojo_build.sh"
run_log verify bash "$ROOT/tools/verify.sh"

echo ""
if [ "$FAILED" -eq 0 ]; then
	echo "ВСЕ ЛОГИ ПЕРЕГЕНЕРИРОВАНЫ УСПЕШНО"
else
	echo "ЕСТЬ ПРОВАЛЫ (см. логи)"
fi
exit "$FAILED"
