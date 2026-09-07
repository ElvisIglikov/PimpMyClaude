#!/bin/bash
# Один прогон всех проверок проекта: JS (сторожевые проверки + node --test tests/) и Swift (swift build && swift test).
# Решение 5 плана WF24. Зовётся руками, строкой из docs/CHECKLIST.md; git-хука нет намеренно.
# Использование: tools/test.sh [--js|--swift|--help]
#   без ключа  — всё: сперва JS, потом Swift;
#   --js       — node --check inject.js, сторожевые проверки, node --test по файлам tests/*.test.mjs, тесты CLI «Пимп»;
#   --swift    — cd app && swift build && swift test.
# Любая красная проверка — ненулевой код возврата и стоп: не починил — не коммитим (слово Элвиса 05.09).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INJECT="$ROOT/claude-patch/inject.js"
TESTS_DIR="$ROOT/tests"
# node --test без package.json умеет искать файлы с 18-й версии; у нас 26.x.
MIN_NODE=18

say() { printf '· %s\n' "$*"; }
head2() { printf '\n=== %s ===\n' "$*"; }
fail() { printf '\n✗ %s\n' "$*" >&2; exit 1; }

# Метка VERSION из inject.js: awk по файлу (не по потоку — иначе pipefail ловит SIGPIPE).
version_of() { awk -F'"' '/const VERSION = "/ { print $2; exit }' "$1"; }

# Склонение в сводке: 1 файл, 2 файла, 5 файлов. Аргументы — число и три формы.
plural() {
  local n="$1" hundred ten
  hundred=$(( n % 100 )); ten=$(( n % 10 ))
  if [ "$hundred" -ge 11 ] && [ "$hundred" -le 14 ]; then printf '%s %s' "$n" "$4"
  elif [ "$ten" -eq 1 ]; then printf '%s %s' "$n" "$2"
  elif [ "$ten" -ge 2 ] && [ "$ten" -le 4 ]; then printf '%s %s' "$n" "$3"
  else printf '%s %s' "$n" "$4"
  fi
}

usage() {
  sed -n '2,8p' "$0"
}

run_js() {
  head2 "JS"

  # 1. node вообще есть и достаточно свежий: на старом «node --test» ругается невнятно.
  command -v node >/dev/null 2>&1 || fail "node не найден. Нужен node $MIN_NODE+ (brew install node) — на нём держатся все JS-проверки."
  local node_version node_major
  node_version="$(node --version)"
  node_major="$(printf '%s' "$node_version" | sed 's/^v//; s/\..*//')"
  case "$node_major" in
    ''|*[!0-9]*) fail "не разобрал версию node («$node_version»). Нужен node $MIN_NODE+." ;;
  esac
  [ "$node_major" -ge "$MIN_NODE" ] || fail "node $node_version слишком старый: «node --test» без package.json работает с $MIN_NODE-й версии. Обнови node (brew install node) и повтори."
  say "node $node_version"

  # 2. Синтаксис боевого файла. Он уезжает в каждую страницу Claude — падение здесь видно всей команде.
  [ -f "$INJECT" ] || fail "нет $INJECT"
  node --check "$INJECT"
  say "node --check claude-patch/inject.js — чисто"

  # 3. Модульность: лоадер v6 исполняет файл как обычный скрипт, статический ESM и CommonJS его убьют.
  #    Динамический import(...) разрешён намеренно — им ищется стор popout в разделе «новое окно» (WF13).
  if grep -nE '^[[:space:]]*(import|export)[[:space:]]' "$INJECT"; then
    fail "статический ESM в inject.js (строки выше): лоадер исполняет файл как обычный скрипт — перепиши через замыкание."
  fi
  if grep -nE '\brequire\(' "$INJECT"; then
    fail "require( в inject.js (строки выше): в странице Claude модулей нет."
  fi
  local dynamic
  dynamic="$(grep -nE '(^|[^.[:alnum:]_])import[[:space:]]*\(' "$INJECT" | grep -cvE '^[0-9]+:[[:space:]]*(//|\*)' || true)"
  say "статического ESM и require нет; динамический import(...) — $dynamic (поиск стора popout, так и задумано)"

  # 4. Идемпотентность: лоадер перечитывает файл по mtime и гоняет его в том же окне снова и снова.
  #    Три приметы снятия прошлой установки — без любой из них окно копит полоски, подписки и таймеры.
  grep -q 'window.__myclaude?.dispose?.()' "$INJECT" \
    || fail "в inject.js пропал вызов window.__myclaude?.dispose?.() — второй прогон оставит в окне зомби (раздел 0)."
  grep -q '__myclaudeUndo' "$INJECT" \
    || fail "в inject.js пропал реестр отмен __myclaudeUndo — упавшая установка не снимется (раздел 0)."
  grep -qE '^[[:space:]]*dispose,?[[:space:]]*$' "$INJECT" \
    || fail "window.__myclaude больше не отдаёт dispose — снять установку станет нечем (раздел 17)."
  say "снятие прошлой установки на месте (dispose, реестр отмен)"

  # 5. Живые файлы, которые лоадер читает как JSON: битый файл = молчаливо мёртвые темы.
  local json
  for json in "$ROOT/claude-patch/claude.json" "$ROOT/claude-patch/themes.json"; do
    [ -f "$json" ] || fail "нет $json"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$json" \
      || fail "$json — не валидный JSON"
  done
  say "claude.json и themes.json разбираются"

  # 6. inject.js изменился относительно main — значит метка VERSION обязана поехать:
  #    по ней probe на гейте отличает свежий файл от старого в Application Support.
  if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --verify -q refs/heads/main >/dev/null 2>&1; then
    if git -C "$ROOT" diff --quiet main -- claude-patch/inject.js; then
      say "inject.js не отличается от main — сверку VERSION пропускаю"
    else
      local tmp old new
      tmp="$(mktemp)"
      git -C "$ROOT" show main:claude-patch/inject.js > "$tmp"
      old="$(version_of "$tmp")"
      new="$(version_of "$INJECT")"
      rm -f "$tmp"
      [ -n "$new" ] || fail "в inject.js не нашлась строка const VERSION = \"…\""
      [ "$old" != "$new" ] || fail "inject.js правился, а VERSION остался «$new» — подними метку (wfN-a-M), иначе на гейте не отличить свежий файл от старого."
      say "VERSION: main «$old» → «$new»"
    fi
  else
    say "git или ветки main нет — сверку VERSION пропускаю"
  fi

  # 7. Сами наборы.
  [ -d "$TESTS_DIR" ] || fail "нет каталога tests/ — JS-наборы не прогнаны."
  # Файлы перечисляем сами: с 22-й версии node понимает позиционный аргумент как маску, а не как каталог.
  local out
  local -a files
  files=()
  while IFS= read -r file; do files+=("$file"); done < <(find "$TESTS_DIR" -name '*.test.mjs' -type f | sort)
  [ "${#files[@]}" -gt 0 ] || fail "в tests/ нет ни одного *.test.mjs"
  out="$(mktemp)"
  if ! node --test --test-reporter=tap "${files[@]}" 2>&1 | tee "$out"; then
    rm -f "$out"
    fail "node --test: красное (см. вывод выше)"
  fi
  JS_FILES="${#files[@]}"
  JS_CHECKS="$(awk '/^# pass [0-9]+$/ { n = $3 } END { print n + 0 }' "$out")"
  rm -f "$out"

  # 8. CLI «Пимп» (WF36): те же фикстуры канала, что читает Swift-половина.
  ( cd "$ROOT" && python3 -B -m unittest tests/pimp_cli_test.py ) || fail "python3 -m unittest tests/pimp_cli_test.py: красное (см. вывод выше)"  # -B: без __pycache__ в репозитории
}

run_swift() {
  head2 "Swift"
  command -v swift >/dev/null 2>&1 || fail "swift не найден — поставь Xcode или Command Line Tools."
  local out
  out="$(mktemp)"
  if ! ( cd "$ROOT/app" && swift build && swift test ) 2>&1 | tee "$out"; then
    rm -f "$out"
    fail "swift build/test: красное (см. вывод выше)"
  fi
  SWIFT_TESTS="$(awk '/Executed [0-9]+ test/ { n = $2 } END { print n + 0 }' "$out")"
  rm -f "$out"
}

JS_FILES=""
JS_CHECKS=""
SWIFT_TESTS=""
case "${1-}" in
  --js) run_js ;;
  --swift) run_swift ;;
  -h|--help) usage; exit 0 ;;
  '') run_js; run_swift ;;
  *) printf 'test.sh: не знаю ключ «%s»\n\n' "$1" >&2; usage >&2; exit 2 ;;
esac

# Сводка — числами из прогона, а не вшитыми: тестов в проекте прибавляется каждую волну.
SUMMARY=""
if [ -n "$JS_CHECKS" ]; then
  SUMMARY="JS: $(plural "$JS_FILES" файл файла файлов), $(plural "$JS_CHECKS" проверка проверки проверок)"
fi
if [ -n "$SWIFT_TESTS" ]; then
  if [ -n "$SUMMARY" ]; then SUMMARY="$SUMMARY · "; fi
  SUMMARY="${SUMMARY}Swift: $(plural "$SWIFT_TESTS" тест теста тестов)"
fi
printf '\n✅ %s\n' "$SUMMARY"
