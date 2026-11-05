#!/bin/bash
# Один прогон всех проверок проекта: JS (сторожевые проверки + node --test tests/), CLI и Swift (swift build && swift test).
# Решение 5 плана WF24. Зовётся руками, строкой из docs/CHECKLIST.md; git-хука нет намеренно.
# Использование: tools/test.sh [--js|--swift|--fast] [--gate] [--help]
#   без ключа  — всё: сперва JS, потом Swift;
#   --fast     — быстрый набор при выкладке (≈ 2,5 мин в тишине, TESTS.md): JS целиком, CLI одним python3 по файлам разом;
#                без Swift и без второго прогона /usr/bin/python3 — полный набор остаётся за гейтом;
#   --js       — node --check inject.js, сторожевые проверки, node --test tests/, CLI «Пимп» (python3 из PATH и /usr/bin/python3);
#   --swift    — cd app && swift build && swift test (пропущенные тесты видны вслух и в сводке);
#   --gate     — гейт оркестратора: метка VERSION в inject.js строго новее, чем в базе ($PIMP_GATE_BASE, по умолчанию main;
#                на марафоне — интеграционная ветка, напр. PIMP_GATE_BASE=wf247); в ветке батча не сверяется.
# Любая красная проверка — ненулевой код возврата и стоп: не починил — не коммитим (слово Элвиса 05.09).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE_BASE="${PIMP_GATE_BASE:-main}"
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
  sed -n '2,11p' "$0"
}

# Метка новее? $1 — старая, $2 — новая. Правило Patcher.injectVersion / injectKeepsLive: «wfN-буква-M», волна
# числом, потом буква строкой, потом шаг числом. 0 — новее, 1 — нет, 2 — метка не того вида.
version_newer() {
  local LC_ALL=C re='^wf([0-9]+)-([^-]+)-([0-9]+)$' old_wave old_tag old_step
  [[ "$1" =~ $re ]] || return 2
  old_wave=$((10#${BASH_REMATCH[1]})); old_tag="${BASH_REMATCH[2]}"; old_step=$((10#${BASH_REMATCH[3]}))
  [[ "$2" =~ $re ]] || return 2
  local new_wave=$((10#${BASH_REMATCH[1]})) new_tag="${BASH_REMATCH[2]}" new_step=$((10#${BASH_REMATCH[3]}))
  if [ "$new_wave" -ne "$old_wave" ]; then [ "$new_wave" -gt "$old_wave" ]; return; fi
  if [ "$new_tag" != "$old_tag" ]; then [[ "$new_tag" > "$old_tag" ]]; return; fi
  [ "$new_step" -gt "$old_step" ]
}

# Реальный путь интерпретатора: python3 из PATH и /usr/bin/python3 бывают одним и тем же.
python_real() { "$1" -c 'import os, sys; print(os.path.realpath(sys.executable))' 2>/dev/null || true; }

# Наборы CLI «Пимп» одним интерпретатором: все tests/pimp_*_test.py (новый файл попадает в гейт сам).
# Число тестов и пропуски — в CLI_RAN / CLI_SKIP: без числа пропажу набора никто не увидит (#5749).
# unittest пишет отчёт в stderr, поэтому 2>&1; -B — без __pycache__ в репозитории.
run_cli() {
  local python="$1" log
  log="$(mktemp)"
  if ! ( cd "$ROOT" && "$python" -B -m unittest discover -s tests -p 'pimp_*_test.py' ) 2>&1 | tee "$log"; then
    rm -f "$log"
    fail "$python -m unittest discover -s tests -p 'pimp_*_test.py': красное (см. вывод выше)"
  fi
  CLI_RAN="$(awk '/^Ran [0-9]+ test/ { n = $2 } END { print n + 0 }' "$log")"
  CLI_SKIP="$(sed -n 's/.*skipped=\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
  CLI_SKIP="${CLI_SKIP:-0}"
  rm -f "$log"
  [ "$CLI_RAN" -gt 0 ] || fail "$python: в tests/ не нашлось ни одного теста pimp_*_test.py"
}

# То же для --fast: каждый файл своим процессом, разом по 4 — подряд CLI идёт ≈ 3,5 мин, разом — по самому
# долгому файлу (pimp_term ≈ 1,5 мин, замер 31.10.2026, #11441). Красный файл — его отчёт целиком и стоп.
run_cli_fast() {
  local python="$1" logs log
  logs="$(mktemp -d)"
  ( cd "$ROOT" && find tests -name 'pimp_*_test.py' -type f | sort | xargs -P 4 -I{} sh -c \
      '"$1" -B -m unittest "$2" > "$3/$(basename "$2").log" 2>&1 || echo "$2" >> "$3/red"' sh "$python" {} "$logs" )
  if [ -s "$logs/red" ]; then
    while IFS= read -r file; do printf '\n--- %s\n' "$file"; cat "$logs/$(basename "$file").log"; done < "$logs/red"
    rm -rf "$logs"
    fail "$python -m unittest: красное (файлы выше)"
  fi
  CLI_RAN=0; CLI_SKIP=0
  for log in "$logs"/*.log; do
    CLI_RAN=$(( CLI_RAN + $(awk '/^Ran [0-9]+ test/ { n = $2 } END { print n + 0 }' "$log") ))
    CLI_SKIP=$(( CLI_SKIP + $(awk 'match($0, /skipped=[0-9]+/) { n = substr($0, RSTART + 8, RLENGTH - 8) } END { print n + 0 }' "$log") ))
  done
  rm -rf "$logs"
  [ "$CLI_RAN" -gt 0 ] || fail "$python: в tests/ не нашлось ни одного теста pimp_*_test.py"
}

run_js() {
  head2 "JS"
  local started=$SECONDS

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
  #    Страница правится в claude-patch/page/NNN-*.js, inject.js — их склейка (WF248 П3): сперва она побайтно.
  [ -f "$INJECT" ] || fail "нет $INJECT"
  "$ROOT/tools/page.sh" check || fail "inject.js не равен склейке claude-patch/page/*.js (выше) — тесты гоняли бы не то"
  say "склейка claude-patch/page/*.js == inject.js"
  node --check "$INJECT"
  say "node --check claude-patch/inject.js — чисто"

  # 3. Модульность: лоадер исполняет файл как обычный скрипт, статический ESM и CommonJS его убьют.
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

  # 6. Метка VERSION: по ней probe на гейте отличает свежий файл от старого, а «Пропатчить Claude» кладёт страницу
  #    поверх живой, только если метка в сборке СТРОГО новее (Patcher.injectKeepsLive). В ветке батча не сверяем —
  #    метку поднимает оркестратор на гейте (план WF248); с --gate inject.js, отличный от main, обязан нести метку новее.
  local new
  new="$(version_of "$INJECT")"
  [ -n "$new" ] || fail "в inject.js не нашлась строка const VERSION = \"…\""
  if [ -z "$GATE" ]; then
    say "VERSION «${new}» — со сверкой с базой только на гейте (--gate)"
  elif ! command -v git >/dev/null 2>&1 || ! git -C "$ROOT" rev-parse --verify -q "${GATE_BASE}^{commit}" >/dev/null 2>&1; then
    fail "--gate: git или ветки ${GATE_BASE} нет — метку VERSION не с чем сверить"
  elif git -C "$ROOT" diff --quiet "$GATE_BASE" -- claude-patch/inject.js; then
    say "inject.js не отличается от ${GATE_BASE} — сверку VERSION пропускаю"
  else
    local tmp old rc=0
    tmp="$(mktemp)"
    git -C "$ROOT" show "${GATE_BASE}:claude-patch/inject.js" > "$tmp"
    old="$(version_of "$tmp")"
    rm -f "$tmp"
    version_newer "$old" "$new" || rc=$?
    [ "$rc" -ne 2 ] || fail "метка VERSION не вида wfN-буква-M (${GATE_BASE} «${old}», здесь «${new}») — Patcher её не прочтёт."
    [ "$rc" -eq 0 ] || fail "inject.js правился, а VERSION «${new}» не новее ${GATE_BASE} «${old}» — подними метку (волна, буква, шаг), иначе «Пропатчить Claude» оставит у людей старую страницу."
    say "VERSION: ${GATE_BASE} «${old}» → «${new}»"
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
  JS_SKIPPED="$(awk '/^# skipped [0-9]+$/ { n = $3 } END { print n + 0 }' "$out")"
  rm -f "$out"
  JS_TIME=$(( SECONDS - started ))

  # 8. CLI «Пимп» (WF36): те же фикстуры канала, что читает Swift-половина. Дважды: python3 из PATH и системный
  #    /usr/bin/python3 (3.9 на Маках команды; его зовут PimpViewer и скилл) — новый синтаксис в pimp.py 8 дней
  #    ломал CLI у команды при зелёном гейте (ревизия WF247). Второй прогон — только если это другой интерпретатор;
  #    без Command Line Tools /usr/bin/python3 не зовём — он лишь предлагает их поставить.
  started=$SECONDS
  if [ -n "$FAST" ]; then run_cli_fast python3; else run_cli python3; fi
  CLI_TESTS="$CLI_RAN"; CLI_SKIPPED="$CLI_SKIP"; CLI_TIME=$(( SECONDS - started ))
  local system=/usr/bin/python3
  if [ -n "$FAST" ]; then
    say "второй прогон CLI (/usr/bin/python3) — только в полном наборе"
  elif [ -x "$system" ] && xcode-select -p >/dev/null 2>&1 && [ "$(python_real python3)" != "$(python_real "$system")" ]; then
    started=$SECONDS
    SYS_VERSION="$("$system" -c 'import platform; print(platform.python_version())')"
    # Комплект Рика и прочие скрипты tools/ едут команде, тестов CLI у них нет — хотя бы разбор.
    local py_files
    py_files="$(find "$ROOT/tools" "$ROOT/resources/rick-kit" "$ROOT/resources/kontekst" -name '*.py' -type f 2>/dev/null | sort)"
    if [ -n "$py_files" ] && ! printf '%s\n' "$py_files" | "$system" -B -c 'import ast, sys
for path in sys.stdin.read().split("\n"):
    if path:
        ast.parse(open(path, encoding="utf-8").read(), path)'; then
      fail "скрипт не разбирается системным Python $SYS_VERSION (см. выше) — у команды он не запустится."
    fi
    run_cli "$system"
    SYS_TESTS="$CLI_RAN"; SYS_SKIPPED="$CLI_SKIP"; SYS_TIME=$(( SECONDS - started ))
  else
    say "второй прогон CLI пропускаю: /usr/bin/python3 нет, нет Command Line Tools или это тот же python3"
  fi
  # Число тестов комплекта и пропуск — в сводку, как у CLI (z8-r03): LiveTests молча
  # пропускается без каталога SkilZZZ.
  # В открытой копии (tools/public_export.sh) сборщика комплекта и его теста нет — пропуск, а не красное.
  local kit
  if [ -f "$ROOT/tests/kit_build_test.py" ]; then
  started=$SECONDS
  kit="$(mktemp)"
  if ! ( cd "$ROOT" && python3 -B -m unittest tests/kit_build_test.py ) 2>&1 | tee "$kit"; then
    rm -f "$kit"
    fail "python3 -m unittest tests/kit_build_test.py: красное (сборщик комплекта Workflow, WF89)"
  fi
  KIT_TESTS="$(awk '/^Ran [0-9]+ test/ { n = $2 } END { print n + 0 }' "$kit")"
  KIT_SKIPPED="$(sed -n 's/.*skipped=\([0-9][0-9]*\).*/\1/p' "$kit" | tail -1)"
  rm -f "$kit"
  KIT_TIME=$(( SECONDS - started ))
  fi
  # Сверка двух портов лоадера (Loader.swift ↔ patch-claude.mjs) и его синтаксис — tests/loader-trust.test.mjs
  # (побайтно, с версией Asar.loaderVersion, и исполняет лоадер в vm); свой шаг здесь снят как дубль (ревизия WF247).
}

run_swift() {
  head2 "Swift"
  local started=$SECONDS
  command -v swift >/dev/null 2>&1 || fail "swift не найден — поставь Xcode или Command Line Tools."
  # ClaudeAXTests и LookSchemeWF145Tests читают inject.js — он обязан быть свежей склейкой page/ (WF248 П3).
  "$ROOT/tools/page.sh" check || fail "inject.js не равен склейке claude-patch/page/*.js (выше) — Swift сверял бы не то"
  local out
  out="$(mktemp)"
  # Сборочный Мак задан (tools/m1.sh) — Swift идёт там, рабочий Мак не греется (30.09.2026).
  # SDKROOT на Command Line Tools (ноут коллеги, 16.10.2026) ломает swift test: Testing.framework из Xcode не
  # собирается со старым SDK («no type named 'SendableMetatype'»). Без переменной xcrun берёт SDK Xcode.
  local swift_cmd='cd "$ROOT/app" && env -u SDKROOT swift build && env -u SDKROOT swift test'
  if [ -n "${PIMP_M1:-}" ] || [ -s "$HOME/.config/pimpmyclaude/m1-host" ]; then
    say "Swift — на сборочном Маке (tools/m1.sh)"
    swift_cmd='"$ROOT/tools/m1.sh" test'
  fi
  if ! ( eval "$swift_cmd" ) 2>&1 | tee "$out"; then
    rm -f "$out"
    fail "swift build/test: красное (см. вывод выше)"
  fi
  # Сумма по тест-бандлам: на сборочном Маке (Xcode 27) каждый бандл идёт своим «All tests», и последняя
  # строка «Executed» — только ClaudeAX (30.09.2026: 775 вместо 840).
  SWIFT_TESTS="$(awk '/Test Suite .*\.xctest. (passed|failed)/ { f = 1; next } f && /Executed [0-9]+ test/ { n += $2; f = 0 } END { print n + 0 }' "$out")"
  # Пропущенные тесты (WF45, задача #5760). Тесты патчера отключаются сами, когда на Маке нет
  # Claude.app: прогон остаётся зелёным, а число в сводке — прежним, и «✅ Swift: 202 теста»
  # ничего не говорит о патче. Считаем пропуск и называем его вслух.
  SWIFT_SKIPPED="$(awk '/Executed [0-9]+ test/ && /skipped/ { for (i = 1; i < NF; i++) if ($i == "with") { n = $(i + 1); break } } END { print n + 0 }' "$out")"
  if [ "$SWIFT_SKIPPED" -gt 0 ]; then
    printf '\n⚠️  Swift: пропущено тестов — %s, прогон НЕ полный:\n' "$SWIFT_SKIPPED"
    grep -E 'Test skipped' "$out" | sed 's/^/    /' | sort -u
  fi
  rm -f "$out"
  SWIFT_TIME=$(( SECONDS - started ))
}

JS_FILES=""
JS_CHECKS=""
JS_SKIPPED=""
JS_TIME=""
CLI_TESTS=""
CLI_SKIPPED=""
CLI_TIME=""
CLI_RAN=""
CLI_SKIP=""
SYS_VERSION=""
SYS_TESTS=""
SYS_SKIPPED=""
SYS_TIME=""
KIT_TESTS=""
KIT_SKIPPED=""
KIT_TIME=""
SWIFT_TESTS=""
SWIFT_SKIPPED=""
SWIFT_TIME=""
MODE=""
GATE=""
FAST=""
for arg in "$@"; do
  case "$arg" in
    --js|--swift)
      [ -z "$MODE" ] || { printf 'test.sh: --js и --swift вместе — это и есть прогон без ключа\n\n' >&2; usage >&2; exit 2; }
      MODE="$arg" ;;
    --gate) GATE=1 ;;
    --fast) FAST=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'test.sh: не знаю ключ «%s»\n\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -n "$FAST" ] && { [ -n "$GATE" ] || [ "$MODE" = --swift ]; }; then
  printf 'test.sh: --fast — набор при выкладке; гейт и Swift — только полным прогоном\n\n' >&2; usage >&2; exit 2
fi
[ -z "$FAST" ] || MODE=--js
case "$MODE" in
  --js) run_js ;;
  --swift) run_swift ;;
  '') run_js; run_swift ;;
esac

# Сводка — числами из прогона, а не вшитыми: тестов в проекте прибавляется каждую волну.
# Пропуски JS и CLI называются в числе (Chromium-стенды, настоящий tmux), время — у каждой части.
SUMMARY=""
part() {  # $1 — подпись с числами, $2 — пропущено, $3 — секунды, $4 — «сверх», если пропуск не входит в число
  local text="$1"
  if [ "${2:-0}" -gt 0 ] && [ -n "${4:-}" ]; then text="$text, ещё пропущено $2"
  elif [ "${2:-0}" -gt 0 ]; then text="$text, из них пропущено $2"; fi
  if [ -n "$3" ]; then text="$text ($3 с)"; fi
  if [ -n "$SUMMARY" ]; then SUMMARY="$SUMMARY · "; fi
  SUMMARY="$SUMMARY$text"
}
if [ -n "$JS_CHECKS" ]; then
  part "JS: $(plural "$JS_FILES" файл файла файлов), $(plural "$JS_CHECKS" проверка проверки проверок)" "$JS_SKIPPED" "$JS_TIME" сверх
fi
if [ -n "$CLI_TESTS" ]; then
  part "CLI «Пимп»: $(plural "$CLI_TESTS" тест теста тестов)" "$CLI_SKIPPED" "$CLI_TIME"
fi
if [ -n "$SYS_TESTS" ]; then
  part "CLI под /usr/bin/python3 $SYS_VERSION: $(plural "$SYS_TESTS" тест теста тестов)" "$SYS_SKIPPED" "$SYS_TIME"
fi
if [ -n "$KIT_TESTS" ]; then
  part "Комплект: $(plural "$KIT_TESTS" тест теста тестов)" "$KIT_SKIPPED" "$KIT_TIME"
fi
if [ -n "$SWIFT_TESTS" ]; then
  # Пропуск идёт в само число сводки: без этого «202 теста» врёт про то, что прогнано (#5760).
  part "Swift: $(plural "$SWIFT_TESTS" тест теста тестов)" "$SWIFT_SKIPPED" "$SWIFT_TIME"
fi
if [ -n "$FAST" ]; then SUMMARY="быстрый набор (без Swift) · $SUMMARY"; fi
if [ "${SWIFT_SKIPPED:-0}" -gt 0 ]; then
  printf '\n⚠️ %s\n' "$SUMMARY"
else
  printf '\n✅ %s\n' "$SUMMARY"
fi
