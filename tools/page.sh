#!/bin/bash
# Страница по файлам-разделам (WF248 П3): claude-patch/page/NNN-*.js ⇄ claude-patch/inject.js.
# Раздел = файл: каждый файл, кроме 000-head.js, начинается своим маркером «  // ---- <номер>. …» и других маркеров
# не держит; порядок файлов (имя, LC_ALL=C) = порядок разделов — не переставлять (TDZ). inject.js — их склейка (cat).
# Использование: tools/page.sh build [--version wfN-x-M] | check | split [--force] | where <строка> | live [шаг]
#   build   — page/ → inject.js (+ node --check); --version — сперва метка VERSION в 000-head.js (только гейт);
#   check   — склейка page/ побайтно == inject.js, иначе 1 (сторож tools/test.sh, tools/bundle.sh, tests/load.mjs);
#   split   — обратно: inject.js → page/ по тем же маркерам. Для правок, пришедших в inject.js (слияние старой ветки,
#             горячая правка живой страницы, ветка с Мака Элвиса). Новый маркер — новый файл NNN-new.js (имя после
#             номера переименовать, номер оставить), пропавший маркер — файл удаляется. Незакоммиченные правки page/
#             при расхождении — отказ (--force — перезаписать);
#   where   — строка inject.js (из стека ошибки) → page/файл:строка;
#   live    — склейка page/ с меткой wfN-live-M (ниже любой боевой: «live» < «page») в живой каталог MyClaude под
#             /tmp/pimp-live.lock; шаг M — аргумент, без него — шаг текущей метки. Живое окно — одно на Мак.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAGE="$ROOT/claude-patch/page"
INJECT="$ROOT/claude-patch/inject.js"
MARKER='^  // ---- [0-9]'
LIVE="$HOME/Library/Application Support/MyClaude/inject.js"

die() { printf 'page.sh: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '5,5p' "$0" | sed 's/^# //' >&2; exit 2; }

# Файлы-разделы по порядку. Имя — строго NNN-[a-z0-9-].js: чужое имя склейка молча пропустила бы, а сортировка
# по байтам должна совпасть с tests/load.mjs.
FILES=()
parts() {
  [ -d "$PAGE" ] || die "нет каталога claude-patch/page"
  local f name
  FILES=()
  for f in "$PAGE"/*; do
    [ -e "$f" ] || continue
    name="${f##*/}"
    [[ "$name" =~ ^[0-9]{3}-[a-z0-9-]+\.js$ ]] || die "claude-patch/page/$name: имя не вида NNN-раздел.js — в склейку не попадёт"
    FILES+=("$f")
  done
  [ "${#FILES[@]}" -gt 0 ] || die "claude-patch/page пуст"
  [ "${FILES[0]##*/}" = "000-head.js" ] || die "первым файлом должен быть 000-head.js (замыкание, VERSION)"
}

# Раздел = файл: маркер — первая строка своего файла и только там. Иначе split разрезал бы по-другому, чем лежит.
shape() {
  awk -v marker="$MARKER" '
    FNR == 1 { name = FILENAME; sub(/.*\//, "", name) }
    $0 ~ marker {
      if (name == "000-head.js") { printf "page/%s:%d: маркер раздела в шапке — это новый файл\n", name, FNR; bad = 1 }
      else if (FNR != 1) { printf "page/%s:%d: второй маркер в файле — новый раздел = новый файл\n", name, FNR; bad = 1 }
    }
    FNR == 1 && name != "000-head.js" && $0 !~ marker { printf "page/%s: первая строка — не маркер «  // ---- <номер>.»\n", name; bad = 1 }
    END { exit bad }' "${FILES[@]}" >&2 || die "файлы-разделы не по правилу (выше)"
}

case "${1:-}" in
  build)
    version=""
    if [ "${2:-}" = "--version" ]; then
      version="${3:-}"
      [[ "$version" =~ ^wf[0-9]+-[a-z]+-[0-9]+$ ]] || die "метка «${version}» не вида wfN-x-M (Patcher.injectVersion)"
    elif [ -n "${2:-}" ]; then usage; fi
    parts; shape
    if [ -n "$version" ]; then
      [ "$(grep -c '^  const VERSION = "' "$PAGE/000-head.js")" = 1 ] || die "в 000-head.js нет ровно одной строки const VERSION"
      sed -i '' "s/^  const VERSION = \"[^\"]*\";/  const VERSION = \"$version\";/" "$PAGE/000-head.js"
    fi
    tmp="$ROOT/claude-patch/.inject.build.js"  # .js — иначе node --check не берёт файл
    trap 'rm -f "$tmp"' EXIT
    cat "${FILES[@]}" > "$tmp"
    if command -v node >/dev/null 2>&1 && ! node --check "$tmp"; then
      die "склейка не разбирается (выше) — inject.js не тронут"
    fi
    mv "$tmp" "$INJECT"
    printf 'page.sh: inject.js ← %s файлов page/ (%s строк)%s\n' "${#FILES[@]}" "$(wc -l < "$INJECT" | tr -d ' ')" \
      "${version:+, VERSION $version}"
    ;;
  check)
    parts; shape
    if ! diff=$(cat "${FILES[@]}" | cmp - "$INJECT" 2>&1); then
      line="$(printf '%s' "$diff" | sed -n 's/.* line \([0-9][0-9]*\).*/\1/p')"
      at=""
      [ -n "$line" ] && at=" — первое расхождение: строка $line inject.js ($("$0" where "$line" 2>/dev/null || echo "за концом page/"))"
      die "inject.js ≠ склейка claude-patch/page/*.js${at}. Правили page/ — tools/page.sh build; правили inject.js (слияние, горячая правка) — tools/page.sh split"
    fi
    ;;
  where)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || usage
    parts
    awk -v n="$2" '{ t++ } t == n { name = FILENAME; sub(/.*claude-patch\//, "", name); print name ":" FNR; found = 1; exit }
      END { exit !found }' "${FILES[@]}" || die "в склейке меньше $2 строк"
    ;;
  split)
    force=""
    [ "${2:-}" = "--force" ] && force=1 || { [ -z "${2:-}" ] || usage; }
    parts
    if cat "${FILES[@]}" | cmp -s - "$INJECT"; then echo "page.sh: page/ и так равен inject.js"; exit 0; fi
    if [ -z "$force" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 \
        && [ -n "$(git -C "$ROOT" status --porcelain -- claude-patch/page)" ]; then
      die "в claude-patch/page есть незакоммиченные правки, а inject.js от них отличается — split их затрёт. Сперва build или commit; затереть — split --force"
    fi
    python3 -B - "$PAGE" "$INJECT" "$MARKER" <<'PY'
import difflib, os, re, sys

page, inject, marker = sys.argv[1], sys.argv[2], re.compile(sys.argv[3])
names = sorted(n for n in os.listdir(page) if re.fullmatch(r"[0-9]{3}-[a-z0-9-]+\.js", n))
text = open(inject, encoding="utf-8").read()
lines = text.splitlines(keepends=True)
cuts = [i for i, line in enumerate(lines) if marker.match(line)]
chunks = ["".join(lines[:cuts[0] if cuts else len(lines)])]
chunks += ["".join(lines[a:b]) for a, b in zip(cuts, cuts[1:] + [len(lines)])]
new = [lines[i].rstrip("\n") for i in cuts]
old_files = names[1:]
old = [open(os.path.join(page, n), encoding="utf-8").readline().rstrip("\n") for n in old_files]

# Файл ↔ маркер: тот же текст — тот же файл; правленый заголовок на том же месте — тот же файл; лишние — новые/удалённые.
owner = [None] * len(new)
gone = []
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
    pair = min(i2 - i1, j2 - j1) if tag in ("equal", "replace") else 0
    for k in range(pair):
        owner[j1 + k] = old_files[i1 + k]
    gone += old_files[i1 + pair:i2]

# Номер нового файла — между соседями (шаг 10 оставляет место); имя после номера — «new», его переименовывают.
num = lambda n: int(n[:3])
taken = set(names) - set(gone)
j = 0
while j < len(new):
    if owner[j]:
        j += 1
        continue
    k = j
    while k < len(new) and not owner[k]:
        k += 1
    low = num(owner[j - 1]) if j else 0
    high = num(owner[k]) if k < len(new) else 1000
    room = high - low - 1
    if room < k - j:
        sys.exit(f"page.sh split: между {low:03d} и {high:03d} нет номеров под {k - j} новых раздела — раздвинь имена руками")
    for step in range(k - j):
        n = low + (step + 1) * (room + 1) // (k - j + 1)
        name, extra = f"{n:03d}-new.js", 2
        while name in taken:
            name, extra = f"{n:03d}-new-{extra}.js", extra + 1
        owner[j + step] = name
        taken.add(name)
    j = k

written = []
for name, body in zip([names[0]] + owner, chunks):
    target = os.path.join(page, name)
    if not os.path.exists(target) or open(target, encoding="utf-8").read() != body:
        with open(target, "w", encoding="utf-8") as f:
            f.write(body)
        written.append(name)
for name in gone:
    os.remove(os.path.join(page, name))
glued = "".join(open(os.path.join(page, n), encoding="utf-8").read() for n in sorted(os.listdir(page)) if n.endswith(".js"))
assert glued == text, "склейка после split не равна inject.js"
fresh = [n for n in owner if n not in names]
print("page.sh split: переписано " + (", ".join(written) or "ничего"))
if fresh:
    print("  новые разделы (имя после номера — переименовать git mv, номер оставить): " + ", ".join(fresh))
if gone:
    print("  маркера больше нет, файл удалён (его строки ушли в предыдущий): " + ", ".join(gone))
PY
    ;;
  live)
    [ -z "${2:-}" ] || [[ "$2" =~ ^[0-9]+$ ]] || usage
    parts; shape
    [ -d "${LIVE%/*}" ] || die "нет живого каталога ${LIVE%/*} — Пимп здесь не стоит"
    dir="$(mktemp -d "${TMPDIR:-/tmp}/pimp-live.XXXXXX")"
    trap 'rm -rf "$dir"' EXIT
    tmp="$dir/inject.js"
    cat "${FILES[@]}" > "$tmp"
    current="$(awk -F'"' '/^  const VERSION = "/ { print $2; exit }' "$tmp")"
    [[ "$current" =~ ^wf([0-9]+)-[^-]+-([0-9]+)$ ]] || die "метка VERSION «${current}» не вида wfN-x-M"
    label="wf${BASH_REMATCH[1]}-live-${2:-${BASH_REMATCH[2]}}"
    sed -i '' "s/^  const VERSION = \"[^\"]*\";/  const VERSION = \"$label\";/" "$tmp"
    node --check "$tmp" || die "склейка не разбирается (выше) — живое окно не тронуто"
    lockf -k -t 60 /tmp/pimp-live.lock /bin/sh -c 'cp "$1" "$2.tmp" && mv "$2.tmp" "$2"' sh "$tmp" "$LIVE" \
      || die "живое окно занято (/tmp/pimp-live.lock) или копия не легла"
    echo "page.sh: живая страница $label → $LIVE (лоадер подхватит по mtime)"
    ;;
  *) usage ;;
esac
