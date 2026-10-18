#!/bin/bash
# Сборка Luau CLI (luau), Luau.Analyze (luau-analyze) и Luau.Compile (luau-compile) из исходников.
# Нужна для: (1) запуска юнит-тестов чистой логики, (2) статического анализа Luau.
# Сеть: github.com (git clone) + pypi.org (pip install cmake) — единственные разрешённые хосты.
set -x
SRC=${SRC_DIR:-/tmp/luau}
VENV=${VENV_DIR:-/tmp/venv}

python3 -m venv "$VENV" || exit 1
"$VENV"/bin/pip install --quiet --upgrade pip || true
"$VENV"/bin/pip install --quiet cmake ninja || exit 1
export PATH="$VENV/bin:$PATH"
cmake --version || exit 1

if [ ! -d "$SRC" ]; then
  git clone --depth 1 https://github.com/luau-lang/luau.git "$SRC" || exit 1
fi

cd "$SRC" || exit 1
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DLUAU_BUILD_CLI=ON -DLUAU_BUILD_ANALYZE=ON 2>&1 | tail -5 || exit 1
cmake --build build --target Luau.Repl.CLI Luau.Analyze.CLI Luau.Compile.CLI -j "$(nproc)" 2>&1 | tail -25 || exit 1
ls -la "$SRC"/build/luau "$SRC"/build/luau-analyze "$SRC"/build/luau-compile || exit 1
echo "BUILD_LUAU_OK"
