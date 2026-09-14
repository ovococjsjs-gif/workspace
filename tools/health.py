#!/usr/bin/env python3
"""Быстрая диагностика workspace. Без зависимостей, без сервера, без сети по умолчанию.

Печатает несколько строк: ветка/HEAD, чистоту дерева, объём файлов, скорость git-команд,
действие глобального `-diff`. Никогда не печатает накопительный patch, не чинит ref/index,
не делает fetch/commit/push и не трогает историю. Сеть — только при явном --remote.

  python3 tools/health.py
  python3 tools/health.py --remote --require-clean
"""
import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRANCH = 'arena/01a09a1c-workspace'
STARTUP = ('AGENTS.md', 'NOW.md', 'ABOUT.md', '.gitignore', '.gitattributes')
PROBLEMS = []


def git(*args, timeout=25):
    r = subprocess.run(('git', '--no-optional-locks') + args, cwd=ROOT,
                       capture_output=True, timeout=timeout)
    if r.returncode != 0:
        PROBLEMS.append(f'git {" ".join(args)} -> код {r.returncode}: '
                        f'{r.stderr.decode("utf-8", "replace").strip()[:200]}')
    return r.stdout.decode('utf-8', 'replace')


def measured(*args):
    t = time.perf_counter()
    out = git(*args)
    return out, time.perf_counter() - t


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--remote', action='store_true', help='сверить remote (нужна сеть)')
    p.add_argument('--require-clean', action='store_true', help='требовать чистое дерево')
    a = p.parse_args()

    branch = git('branch', '--show-current').strip()
    head = git('rev-parse', '--short', 'HEAD').strip()
    status, t_status = measured('status', '--porcelain')
    dirty = [l for l in status.splitlines() if l.strip()]

    numstat, t_diff = measured('diff', '--no-ext-diff', '--numstat', 'HEAD')
    text_rows = [r for r in numstat.splitlines() if not r.startswith('-\t-\t')]
    if text_rows:
        PROBLEMS.append('Есть текстовые строки в numstat — глобальный -diff не сработал')
    attr = git('check-attr', 'diff', '--', '__future_file__.md').strip()
    if not attr.endswith('diff: unset'):
        PROBLEMS.append(f'-diff не действует на будущие файлы: {attr!r}')

    tracked = [l for l in git('ls-files').splitlines() if l.strip()]
    total = sum((ROOT / f).stat().st_size for f in tracked if (ROOT / f).is_file())
    disk = shutil.disk_usage(ROOT)

    if branch != BRANCH:
        PROBLEMS.append(f'ветка {branch!r}, ожидается {BRANCH!r}')
    if a.require_clean and dirty:
        PROBLEMS.append(f'дерево не чистое: {len(dirty)} записей')

    print(f'ветка/HEAD : {branch} @ {head}')
    print(f'дерево     : {"чисто" if not dirty else str(len(dirty)) + " незакоммиченных записей"}'
          f'  (status за {t_status * 1000:.1f} мс)')
    print(f'файлы      : {len(tracked)} отслеживаемых, {total / 1024:.1f} КБ')
    print(f'дифф       : {len(numstat.splitlines())} изменённых путей, '
          f'{len(text_rows)} текстовых строк  (за {t_diff * 1000:.1f} мс)')
    print(f'-diff      : {"действует, включая будущие файлы" if not PROBLEMS or "diff: unset" in attr else attr}')
    print(f'диск       : свободно {disk.free / 2**30:.1f} ГБ')
    print(f'входные    : ' + ', '.join(f'{f}={(ROOT / f).stat().st_size}'
                                       for f in STARTUP if (ROOT / f).is_file()))

    if a.remote:
        url = git('config', '--get', 'remote.origin.url').strip()
        ls = git('ls-remote', 'origin', f'refs/heads/{BRANCH}').strip()
        local = git('rev-parse', 'HEAD').strip()
        ok = ls.startswith(local)
        print(f'remote     : {url or "не задан"} -> {"совпадает с HEAD" if ok else "НЕ совпадает"}')
        if not ok:
            PROBLEMS.append('remote != HEAD: работа не опубликована или ветка разошлась')

    if PROBLEMS:
        print('\nПРОБЛЕМЫ:')
        for x in PROBLEMS:
            print('  - ' + x)
        return 1
    print('\nвсё в норме')
    return 0


if __name__ == '__main__':
    sys.exit(main())
