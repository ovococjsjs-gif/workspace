#!/usr/bin/env bash
# Подгружает исходник книги и архив прежней сессии в scratch/ (вне git).
set -e
cd "$(git rev-parse --show-toplevel)"; mkdir -p scratch
[ -d scratch/shards-source ] || git clone -q --depth 1 https://github.com/ovococjsjs-gif/shardsoftheabyss.git scratch/shards-source
[ -d scratch/old-workspace ] || git clone -q -b arena/01a08101-workspace https://github.com/Riyozaki/workspace.git scratch/old-workspace
echo "ok: scratch/shards-source/editor-2026-09  scratch/old-workspace/projects/shards-of-the-abyss"
