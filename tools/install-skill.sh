#!/bin/bash
# Скилл «Пимп» (WF36) — в ~/.claude/skills/pimp симлинком на репозиторий.
# Симлинк, а не копия: правка skills/pimp/SKILL.md видна Claude сразу, и в чужих
# чатах не живёт устаревший текст. Идемпотентно: уже стоит — ничего не делает.
# Запускать руками: bash tools/install-skill.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/skills/pimp"
DST="$HOME/.claude/skills/pimp"

say() { printf '· %s\n' "$*"; }
fail() { printf '\n✗ %s\n' "$*" >&2; exit 1; }

[ -f "$SRC/SKILL.md" ] || fail "нет $SRC/SKILL.md — ставить нечего."

if [ -L "$DST" ]; then
  now="$(readlink "$DST")"
  if [ "$now" = "$SRC" ]; then
    say "скилл уже стоит: $DST → $SRC"
    exit 0
  fi
  say "перевешиваю старый симлинк ($now)"
  rm -f "$DST"
elif [ -e "$DST" ]; then
  fail "$DST — не симлинк, а настоящая папка или файл. Разберись руками: убери её и повтори."
fi

mkdir -p "$(dirname "$DST")"
ln -s "$SRC" "$DST"
say "скилл «Пимп» поставлен: $DST → $SRC"
say "проверка: python3 $ROOT/tools/pimp.py projects"
