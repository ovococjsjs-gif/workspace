#!/bin/bash
# Единая точка проверки проекта «СТАЯ».
#
# Запускает всё, что можно проверить без Roblox Studio, и печатает сводку:
#   1. юнит-тесты чистой логики          (tools/run_tests.sh)
#   2. синтаксис всех файлов             (tools/check_syntax.sh)
#   3. smoke-тест клиента/сервера        (часть run_tests.sh)
#   4. headless-прогон забега            (tools/probe.sh)
#   5. сценарные прогоны баланса        (tools/scenario.sh)
#   6. сборка place-файла через Rojo    (tools/rojo_build.sh, если rojo есть)
#
# Код возврата: 0 — всё зелёное, 1 — есть провалы.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0
SUMMARY=""

run_step() {
  local name="$1"
  shift
  echo ""
  echo "############################################################"
  echo "# $name"
  echo "############################################################"
  if "$@"; then
    SUMMARY="$SUMMARY
  OK   $name"
  else
    FAILED=1
    SUMMARY="$SUMMARY
  FAIL $name"
  fi
}

run_step "Юнит-тесты + анализатор" bash "$ROOT/tools/run_tests.sh"
run_step "Синтаксис всех файлов" bash "$ROOT/tools/check_syntax.sh"
run_step "Headless-прогон забега" bash "$ROOT/tools/probe.sh"
run_step "Сценарий: спокойный пилот" bash "$ROOT/tools/scenario.sh" calm 90
run_step "Сценарий: пилот с рывками" bash "$ROOT/tools/scenario.sh" booster 90
run_step "Сценарий: средний пилот" bash "$ROOT/tools/scenario.sh" medium 90
run_step "Сценарий: паникующий пилот" bash "$ROOT/tools/scenario.sh" reckless 90
run_step "Сборка через Rojo" bash "$ROOT/tools/rojo_build.sh"

echo ""
echo "############################################################"
echo "# ИТОГ"
echo "############################################################"
echo "$SUMMARY"
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ"
else
  echo "ЕСТЬ ПРОВАЛЫ (см. выше)"
fi
exit "$FAILED"
