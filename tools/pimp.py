#!/usr/bin/env python3
"""Пимп из любого чата (WF36): открыть окно Claude, расставить окна, запомнить
и вернуть раскладку, спросить проекты и окна — не трогая мышь и клавиатуру.

Как это работает. Клавиши жмёт само приложение PimpMyClaude, а разговаривают с
ним файлами: сюда кладётся запрос `<id>.json`, приложение на общем тике (2 с)
берёт его в работу (пишет `<id>.taken`) и отвечает `<id>.result.json` рядом.
Каталог по умолчанию — ~/Library/Application Support/MyClaude/pimp/ (для тестов
переопределяется переменной окружения MYCLAUDE_PIMP_DIR). Контракт полей —
tests/fixtures/pimp/*.json, они же правда для Swift-половины (PimpChannel).

Команды:
  pimp.py open <проект> [--at left|middle|right|below|above|x,y] [--last]
  pimp.py close <проект>
  pimp.py renew <local_…|проект> [--text T|-] [--model "Opus 5.5"] [--effort low|…|max]
    (WF102: новый чат проекта в рамке старого окна, старое окно закрывается;
     WF131: чат главного окна — новый чат открывается в главном, старый остаётся в списке слева)
  pimp.py send (--project <проект> | --chat <local_…>) <текст|->
    (WF103: текст в поле окна и отправка кнопкой страницы; в поле свой текст — не трогает)
  pimp.py arrange [--layout row|4|5|5x2|last|center] [--order Проект,Проект,…] [--center X]
    (раскладку не назвали — «last»: умная расстановка, стоящих на месте не трогает;
     center — главный по центру в треть экрана, остальные по бокам, WF102;
     WF107: у center запись «A+B» — один столбец клетками, A над B; главный,
     названный в --order, стоит там, где назван: слева — работа, справа — хобби)
  pimp.py layouts
  pimp.py layout save <имя>
  pimp.py layout restore <имя> [--new]
  pimp.py paste-airdrop [--project <проект>]
  pimp.py paste-clipboard [--project <проект>]
  pimp.py hud <текст>
  pimp.py projects [--status]
  pimp.py windows              (свёрнутые — строкой «спрятано: N»)
  pimp.py hide | show          (WF112, #8255: свернуть все окна Claude, кроме главного / развернуть)
  pimp.py dim on|off [--level 0.5]
    (WF113, #8256: притемнить окна чатов, кроме главного, окна в фокусе и где ждут тебя; сила 0.2–0.8 или 20–80)
  pimp.py look [1.8|1.9|1.10|1.1|1.2|1.4|1.6|1.5] [--size 120|+20|-20] [--show]
    (WF128 К1 v3: Обратный отсчёт; 1.8 «Взлёт» по умолчанию, 1.3 и 1.7 сняты;
     --show — показать в главном окне без отправки; без ключей — что выбрано)
  pimp.py restore-screens     (WF94: окна как стояли на этих мониторах, закрытые не открывает)
  pimp.py say <фраза|->        (WF75: фраза голосом → DeepSeek → шаги каналом)
  pimp.py gallery [N] [--chat local_…]  (WF98: фото чата по номерам, как в Viewer)
  pimp.py summary              (WF102: что в окнах — только чтение файлов Claude)
  pimp.py main <local_…|проект>
    (WF108, #8148: чат — в главное окно Claude, чат, что был там, — в своё окно;
     окна меняются местами)
  pimp.py term <проект> [--resume <cliSessionId> | --from-chat <local_…> | --last]
               [--text T|-] [--effort xhigh] [--app terminal|iterm]
  pimp.py term-send <проект> <текст|->
  pimp.py term-list [--with-terminal]
  pimp.py term-color <проект>
    (WF111: чат проекта в терминале — вкладка «<маркер> <проект>», tmux-сессия «rick-<проект>»;
     вкладка находится по tty из реестра term/<проект>.json, не по заголовку;
     term-list читает tmux/реестр без Terminal; --with-terminal добавляет старые вкладки без записи;
     вкладка Terminal — в цветах окна проекта (вид .pimpmyclaude.json или авто-цвет по имени
     папки, как у Пимпа), term-color — перекрасить; PIMP_TERM_PS / PIMP_TERM_LSOF — для тестов;
     claude --model claude-opus-5-5 --effort xhigh --permission-mode auto
     --settings <tools/claude-term-settings.json>; файл проверяется перед новым запуском;
     существующие процессы новых настроек не получают; PIMP_TERM_CLAUDE
     подменяет claude, PIMP_TERM_TMUX и PIMP_TERM_OSASCRIPT — tmux и osascript для тестов)
  pimp.py restart-claude [--force] [--from local_…]
    (WF108: перезапуск Claude путём «Обновить Claude», окна — по снимку; первой строкой
     id запроса, ждёт до 180 с; из чата внутри Claude CLI погибнет вместе с Claude —
     ответ тогда читать потом из pimp/<id>.result.json; --force оборвёт работающие чаты;
     «работает» — кнопка стопа в окне или транскрипт чата Claude Desktop за 90 с, чат без
     сессии в индексе Claude Desktop не виден, терминальные claude не в счёт)
  pimp.py prs [--json]         (WF120: открытые PR своего логина/организаций, кроме своих; только чтение gh)
Общие ключи: --json — напечатать сырой ответ приложения вместо строки по-русски.

На выход — ОДНА строка по-русски (у «projects --status» — строка на проект);
код возврата 0 (сделал) или 1 (не вышло).
Свой чат берётся из CLAUDE_CODE_HOST_SESSION_ID: её нет (субагент, чужой
терминал) — «под этим» и «над этим» деградируют в «справа», и это сказано вслух.

Ожидания настраиваются переменными окружения (нужны только тестам):
MYCLAUDE_PIMP_WAIT — сколько секунд ждать ответ (по умолчанию 60); счёт идёт от
последнего удара <id>.taken, а не от запроса: раскладка открывает окна по
одному и после каждого перезаписывает метку (WF41),
MYCLAUDE_PIMP_TAKEN — за сколько секунд приложение обязано взять запрос (5),
MYCLAUDE_PIMP_BUSY — сколько секунд `open`/`renew`/`send`/`close` повторяют запрос на «занят» (45).
Голосовой мозг (WF75): MYCLAUDE_VOICE_ENV — файл с ключом DeepSeek,
MYCLAUDE_VOICE_FAKE — путь к готовому ответу модели (тогда ни ключа, ни сети),
MYCLAUDE_DOWNLOADS — каталог загрузок, откуда берутся фотки Эйрдропа.
Сводка (WF102): MYCLAUDE_CLAUDE_SESSIONS — каталог claude-code-sessions Claude,
MYCLAUDE_CLAUDE_PROJECTS — каталог транскриптов ~/.claude/projects.
"""

import argparse
import json
import math
import os
import plistlib
import random
import re
import shlex
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DIR_ENV = "MYCLAUDE_PIMP_DIR"
DEFAULT_DIR = Path.home() / "Library" / "Application Support" / "MyClaude" / "pimp"
RESULT_WAIT_S = 60.0
TAKEN_WAIT_S = 5.0
POLL_S = 0.1
# Ответ на диске, а JSON не собрался: столько даём на дозапись файла.
BROKEN_GRACE_S = 2.0
# probe.js в каталоге MyClaude — общий канал приложения и агента на гейте.
# Держит его агент — карта чатов у приложения замирает (см. CLAUDE.md, WF29).
PROBE_MARK = "// myclaude-chats"

PLACES = ("left", "middle", "right", "below", "above")
PLACE_WORDS = {
    "left": "слева",
    "middle": "посередине",
    "right": "справа",
    "below": "под этим чатом",
    "above": "над этим чатом",
}
POINT_RE = re.compile(r"^-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?$")

# Раскладки (WF21). В ответе приложение называет применённую раскладку, поэтому
# словами нужны все пять. С WF77 голая «расставь» («last») идёт умным путём, а в
# ответе несёт `row` — про неё say_arrange говорит своими словами, не по словарю.
LAYOUTS = ("row", "4", "5", "5x2", "last", "center")
# «Главный по центру» (WF102) голосу не отдаём: центр назначает чат, который зовёт,
# а у Диктатора своего окна нет (критик WF102, C5).
LAYOUTS_VOICE = ("row", "4", "5", "5x2", "last")
LAYOUT_WORDS = {
    "row": "как сейчас (лента)",
    "4": "четыре в ряд",
    "5": "пять в ряд",
    "5x2": "в два ряда (5×2)",
    "last": "как в прошлый раз",
    "center": "главный по центру",
}
# Замена чата (WF102): id окна — ровно такой, иначе это имя проекта.
CHAT_RE = re.compile(r"^local_[0-9a-f-]{36}$")
RENEW_TEXT_LIMIT = 20000
# Отправка в окно (WF103, #7953): 1…8000 знаков без \0 — иначе отказ до канала.
SEND_TEXT_LIMIT = 8000
EFFORTS = ("low", "medium", "high", "extra", "max")
# #9116 (слово Элвиса 08.10 22:38: «Я же говорил только терминалы открывать… Есть только ты, главный
# оркестратор. Все остальные в терминалах пусть живут»): команды, которые открывают, закрывают,
# сворачивают, разворачивают или выводят вперёд окна Claude Desktop. Агент (в окружении CLAUDECODE
# или CLAUDE_CODE_ENTRYPOINT) зовёт их только с явным --desktop — его ставят Элвис и Рик; без агента
# (Терминал Элвиса, кнопка «↻ Claude» PimpViewer) — как раньше.
DESKTOP_COMMANDS = ("open", "close", "arrange", "renew", "main", "layout restore", "restore-screens",
                    "hide", "show", "paste-airdrop", "paste-clipboard", "restart-claude")
AGENT_ENV = ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT")
DESKTOP_REFUSAL = ("Окна Claude открывает только Элвис/Рик; проектам — pimp.py term <проект> "
                   "(чат в терминале). Элвис сам просил окно — повтори с --desktop. Окна не трогал")
# Обратный отсчёт (WF128 К1 v3): виды снова разные, 1.8 — по умолчанию; 1.3 и 1.7 сняты («слишком»).
LOOK_STYLES = {"1.8": "Взлёт", "1.9": "Пульс", "1.10": "Мерцание", "1.1": "Штрих по кругу",
               "1.2": "Удар", "1.4": "Кольцо", "1.6": "Шнур", "1.5": "Спокойная цифра"}
LOOK_RETIRED = ("1.3", "1.7")
LOOK_LIST = ", ".join(f"{k} «{v}»" for k, v in LOOK_STYLES.items())
LOOK_SIZE = (60, 200)
# Притемнение (WF113): сила в процентах.
DIM_LEVEL = (20, 80)

# Голосовой Пимп (WF75). Ключ лежит отдельным файлом рядом с каналом: его
# значение не печатается и не попадает в журнал — только имя модели.
VOICE_ENV_ENV = "MYCLAUDE_VOICE_ENV"
VOICE_FAKE_ENV = "MYCLAUDE_VOICE_FAKE"
DOWNLOADS_ENV = "MYCLAUDE_DOWNLOADS"
DEFAULT_VOICE_ENV = (Path.home() / "Library" / "Application Support" / "MyClaude"
                     / "pimp-voice.env")
DEFAULT_DOWNLOADS = Path.home() / "Downloads"
VOICE_PROMPT = Path(__file__).resolve().parent / "voice_prompt.md"
VOICE_MODEL = "deepseek-v4-flash"
VOICE_BASE = "https://api.deepseek.com"
VOICE_TIMEOUT_S = 8.0
VOICE_MAX_TOKENS = 400
# Общий бюджет фразы: три окна по 65 с (WF102, было 40) плюс тик канала — дольше Диктатор
# ждать не станет, поэтому договариваем частичным итогом «сделал 2 из 3».
VOICE_BUDGET_S = 210.0
VOICE_LOG_LINES = 1000
BUSY_RETRY_S = 2.0
# «Открой окно» на занятом Пимпе ждёт очереди, как голос (G4 WF101); тестам — env.
OPEN_BUSY_S = 45.0
HUD_LIMIT = 200
VOICE_OPEN_LIMIT = 5
# Ворота стоят в КОДЕ, а не в ответе модели: «уверена» она про себя всегда.
CLOSE_WORDS = ("закр", "убери окно", "убрать окно")
PHOTO_WORDS = ("фот", "картин", "снимк", "эйрдроп", "airdrop", "аирдроп")
# Порция Эйрдропа: фотки приезжают пачкой — берём свежайшую и всё, что легло
# вплотную к ней, но только то, чего ещё не вставляли (отметка voice-pasted.json).
PHOTO_EXT = (".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".webp")
AIRDROP_GAP_S = 120.0
AIRDROP_FRESH_S = 1800.0
AIRDROP_LIMIT = 20

ERRORS = {
    "stale": "Пимп не успел взять запрос вовремя — повтори",
    "busy": "Пимп занят — открывает или возвращает окна",
    # Свёрнутых окон приложение не видит вовсе: говорить «Claude не запущен» при живом
    # Claude со свёрнутыми окнами — врать (#5746).
    "no-windows": "Claude не запущен, окон нет или все свёрнуты — разверни окно",
    # WF94: 65 с без окна (WF102, было 40) не значат, что чат есть, — отказ страницы
    # приходит отдельной ошибкой `chat-not-created`, а тут честно «мог и не создаться».
    "window-missing": "Окно не появилось за 65 с — чат мог и не создаться",
    "chat-not-created": "Чат не создан — страница Claude отказала",
    "screens-unknown": "На этом наборе мониторов окна ещё не запоминал — расставь их, я запомню",
    "too-small": "Мало места: окно не делится пополам",
    "bad-request": "Пимп не понял запрос",
    # Ни одно окно не совпало с ячейкой сетки — запоминать нечего (#5728).
    "not-arranged": "Окна стоят не по сетке — сперва расставь их, потом запоминай раскладку",
    # WF75. Последнего чата нет — Claude переустановлен или проект новый.
    "chat-missing": "Последнего чата в этом проекте нет — открой новый",
    "ambiguous": "Окон проекта несколько — скажи, какое именно, я ничего не трогал",
    "main-window": "Это главное окно Claude — его я не закрываю",
    # WF108 (restart-claude): `working` со списком чатов говорит say_error.
    "working-unknown": ("Не перезапускаю: не удалось проверить, идёт ли ответ в чатах — "
                        "--force перезапустит всё равно и оборвёт работающие чаты"),
    "restore-timeout": ("Claude перезапустил, но окна не вернулись за 130 с — "
                        "«↩️ Вернуть окна» в меню Пимпа"),
}
# Перезапуск Claude (WF108): выход до 30 с, запуск до 20 с, возврат окон до 130 с —
# ждём всего столько, сколько бы ни билось сердце <id>.taken; тестам — env.
RESTART_WAIT_S = 180.0


# Исход цепочки «Нового окна» на странице (WF94, поле `state` у `chat-not-created`).
NOT_CREATED_WORDS = {
    "draft": "в поле главного окна черновик",
    "no-folder": "папка проекта не выбралась",
    "no-send": "сообщение не ушло",
    "no-home": "Claude не открыл новый чат",
    "no-store": "страница Claude не готова",
    "no-insert": "текст не вставился в поле",
    "error": "ошибка на странице",
}
# Запись окна ChatGPT в ответе `windows` (WF94) — с полем app.
CHATGPT_APP = "chatgpt"


def pimp_dir() -> Path:
    value = os.environ.get(DIR_ENV, "").strip()
    return Path(value).expanduser() if value else DEFAULT_DIR


def seconds(name: str, default: float) -> float:
    try:
        value = float(os.environ.get(name, "").strip())
    except ValueError:
        return default
    return value if value > 0 else default


def plural(n: int, one: str, few: str, many: str) -> str:
    hundred, ten = n % 100, n % 10
    if 11 <= hundred <= 14:
        return f"{n} {many}"
    if ten == 1:
        return f"{n} {one}"
    if 2 <= ten <= 4:
        return f"{n} {few}"
    return f"{n} {many}"


def minimized_note(data: dict) -> str:
    n = data.get("minimized")
    if not isinstance(n, int) or n <= 0:
        return ""
    if n == 1:
        return ", одно окно свёрнуто — не считал"
    return f", {plural(n, 'окно свёрнуто', 'окна свёрнуты', 'окон свёрнуты')} — не считал"


def hidden_note(data: dict) -> str:
    """WF112 (#8255): свёрнутые окна Claude — «спрятано: N» (поле minimized ответа windows)."""
    n = data.get("minimized")
    if not isinstance(n, int) or n <= 0:
        return ""
    return f"; спрятано: {n} — «pimp.py show» покажет"


def parse_number(raw: str):
    """Число из строки ключа; не число или не конечное — None."""
    try:
        value = float(str(raw).strip().replace(",", "."))
    except ValueError:
        return None
    return value if value == value and abs(value) != float("inf") else None


def say_dim(data: dict) -> str:
    """Притемнение (WF113): включено с силой или снято."""
    if not data.get("on"):
        return "Притемнение снял"
    level = data.get("level")
    percent = f" {round(level * 100)} %" if isinstance(level, (int, float)) else ""
    return (f"Притемнил окна чатов{percent}: главное, окно в фокусе и окно, где ждут тебя, — светлые")


def say_look(request: dict, data: dict) -> str:
    """Обратный отсчёт (WF119): вид, размер и принят ли запрос показа."""
    style = str(data.get("style") or "").strip()
    name = str(data.get("name") or LOOK_STYLES.get(style, "")).strip()
    size = data.get("size")
    line = f"Обратный отсчёт: {style}" + (f" «{name}»" if name else "")
    if isinstance(size, int):
        line += f", размер {size} %"
    if request.get("show"):
        line += ("; показ в главном окне запрошен" if data.get("shown")
                 else "; показ не запрошен, выбор запомнил")
    return line


def say_hide(request: dict, data: dict) -> str:
    """Спрятал / показал окна (WF112): число, заголовки, окна во весь экран не трогаем."""
    show = request.get("action") == "show"
    titles = [str(title).strip() or "без имени" for title in (data.get("windows") or [])]
    skipped = data.get("skipped") if isinstance(data.get("skipped"), int) else 0
    tail = f"; во весь экран не трогал: {skipped}" if skipped > 0 else ""
    if not titles:
        if show:
            return "Спрятанных окон нет"
        if skipped > 0:
            return f"Прятать нечего: окна во весь экран не трогаю ({skipped})"
        return "Прятать нечего — на экране только главное окно"
    verb = "Показал" if show else "Спрятал"
    line = f"{verb} {plural(len(titles), 'окно', 'окна', 'окон')}: " + ", ".join(f"«{t}»" for t in titles)
    return line + ("; фокус — главному окну" if show else "") + tail


def warn_probe(directory: Path) -> None:
    """probe.js держит не приложение — сказать вслух: карта чатов замерла."""
    probe = directory.parent / "probe.js"
    try:
        with probe.open("r", encoding="utf-8", errors="replace") as handle:
            first = handle.readline().strip()
    except OSError:
        return
    if not first.startswith(PROBE_MARK):
        print(
            "Внимание: probe.js в MyClaude держит не приложение — карта чатов "
            "замерла, окна опознаются по заголовку. Удали probe.js.",
            file=sys.stderr,
        )


def new_id() -> str:
    return f"{int(time.time() * 1000)}-{random.randrange(10000):04d}"


def from_chat() -> str:
    return os.environ.get("CLAUDE_CODE_HOST_SESSION_ID", "").strip()


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_request(directory: Path, request: dict) -> Path:
    """Запрос кладётся целиком: временный файл рядом, права 0600, os.replace."""
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = directory / f"{request['id']}.json"
    tmp = directory / f".{request['id']}.tmp"
    body = json.dumps(request, ensure_ascii=False, separators=(",", ":")) + "\n"
    handle = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            file.write(body)
    except Exception:
        try:
            tmp.unlink()
        except OSError:
            pass
        raise
    os.replace(tmp, path)
    return path


def wait_result(directory: Path, request_id: str, total=None):
    """Ждём ответ. Отдаёт (вид, сырой текст): "ok" | "silent" | "timeout" | "bad".

    "silent" — за MYCLAUDE_PIMP_TAKEN секунд не появилось ни ответа, ни метки
    <id>.taken: приложение не работает (или не видит каталог). "bad" — файл
    есть, а JSON в нём так и не собрался: недописанный файл даём дочитать
    (BROKEN_GRACE_S), но ждать из-за него всю минуту не станем.

    Терпение считаем от ПОСЛЕДНЕГО признака жизни, а не от запроса: приложение
    перезаписывает <id>.taken после каждого открытого окна (heartbeat, WF41), и
    возврат раскладки из пяти чатов честно занимает минуты. Метка не двигается —
    ждём ровно MYCLAUDE_PIMP_WAIT, как раньше. `total` — потолок всего ожидания от
    запроса, как бы ни билось сердце (перезапуск Claude, WF108).
    """
    result = directory / f"{request_id}.result.json"
    taken = directory / f"{request_id}.taken"
    limit = seconds("MYCLAUDE_PIMP_WAIT", RESULT_WAIT_S)
    silent_at = seconds("MYCLAUDE_PIMP_TAKEN", TAKEN_WAIT_S)
    started = time.monotonic()
    last_beat = started         # когда мы в последний раз видели признак жизни
    beat_stamp = None           # mtime метки, по которому этот удар уже засчитан
    seen_taken = False
    broken_since = None
    while True:
        try:
            raw = result.read_text(encoding="utf-8")
        except OSError:
            raw = None
        if raw is not None:
            try:
                json.loads(raw)
                return "ok", raw
            except ValueError:
                now = time.monotonic()
                if broken_since is None:
                    broken_since = now
                elif now - broken_since >= BROKEN_GRACE_S:
                    return "bad", raw
        try:
            stamp = taken.stat().st_mtime
        except OSError:
            stamp = None
        if stamp is not None:
            seen_taken = True
            if stamp != beat_stamp:
                beat_stamp = stamp
                last_beat = time.monotonic()
        now = time.monotonic()
        if not seen_taken and now - started >= silent_at:
            return "silent", ""
        if now - last_beat >= limit or (total is not None and now - started >= total):
            return "timeout", ""
        time.sleep(POLL_S)


def parse_place(value: str) -> str:
    place = (value or "").strip().lower().replace(" ", "")
    if place in PLACES:
        return place
    if POINT_RE.match(place):
        return place
    raise argparse.ArgumentTypeError(
        "место — left, middle, right, below, above или «x,y» (без пробелов)")


def parse_order(value: str) -> list:
    """«Вкуснофф первым, потом Скиллз» — список папок через запятую.

    Имена и пути уходят приложению как дали: сопоставляет их с проектами скилл
    (по `pimp.py projects`), а Swift сверяет папку целиком или её имя (WF41).
    """
    items = [part.strip() for part in (value or "").split(",")]
    items = [part for part in items if part]
    if not items:
        raise argparse.ArgumentTypeError(
            "порядок — имена папок или пути через запятую, например VkusnoffKz,SkilZZZ")
    return items


def stack_parts(entry: str) -> list:
    """Запись --order «A+B» — стопка (WF107): части по «+», обрезанные, без пустых."""
    return [part.strip() for part in str(entry).split("+") if part.strip()]


def short_name(entry: str) -> str:
    """Проект в строке для Элвиса — последней папкой пути: он называет её так."""
    name = str(entry).strip().rstrip("/")
    return name.rsplit("/", 1)[-1] or name


def say_open(request: dict, data: dict) -> str:
    window = data.get("window") if isinstance(data.get("window"), dict) else {}
    title = str(window.get("title") or "").strip() or request["project"]
    place = request["place"]
    where = PLACE_WORDS.get(place, f"в точку {place}")
    # Просили последний чат, а он уже был открыт окном — окно подняли, а не открыли
    # (WF75): «открыл» тут было бы неправдой.
    verb = "Поднял" if data.get("opened") is False else "Открыл"
    skipped = data.get("skipped")
    if isinstance(skipped, int) and skipped > 0:
        # Свободной ячейки в раскладке не нашлось — окно осталось, где родилось;
        # про место молчим, иначе соврём (WF21). С WF77 так отвечают только явные
        # плитки: у умной расстановки ячейка находится всегда.
        line = "Окно открыл, но в раскладке места нет — оставил поверх"
    elif place in ("below", "above") and not data.get("fromResolved"):
        line = f"{verb} {title} справа: своего чата не нашёл, «{where}» не вышло"
    else:
        line = f"{verb} {title} {where}"
    # Приложение кладёт в `layers` ровно две строки: "ok" или пустую (PimpChannel.swift).
    if not data.get("layers"):
        line += ", но цвет не встал — поставь тему из меню окна"
    return line


def say_error(request: dict, data: dict) -> str:
    error = str(data.get("error") or "").strip()
    if error == "project-missing":
        names = [str(name) for name in (data.get("projects") or []) if str(name).strip()]
        if names:
            return f"Не нашёл проект «{request.get('project', '')}», есть: " + ", ".join(names)
        return f"Не нашёл проект «{request.get('project', '')}», и списка Пимп не дал"
    action = request.get("action", "")
    if action == "renew-window":
        # Замена чата (WF102): старое окно закрывается только когда известен новый чат —
        # в любом отказе оно стоит, где стояло, и это говорим вслух.
        if error == "main-window":
            window = data.get("window") if isinstance(data.get("window"), dict) else {}
            if window.get("chat"):
                # WF131 (#9078): новый чат создан окном, но главное окно его не взяло.
                title = str(window.get("title") or "").strip()
                where = f"«{title}» " if title else ""
                return (f"Новый чат {where}{window['chat']} открыл отдельным окном, но в главное "
                        "окно не перенёс — старый чат остался в главном, перенеси руками или "
                        "pimp.py main")
            # Приложение старше WF131 меняет только вынесенные окна.
            return "Этот чат в главном окне Claude — эта версия Пимпа его не меняет, обнови Пимп"
        if error == "chat-unknown":
            window = data.get("window") if isinstance(data.get("window"), dict) else {}
            title = str(window.get("title") or "").strip()
            where = f"«{title}»" if title else "нового чата"
            return (f"Новое окно {where} открыл, но его чат не опознал — старое окно "
                    "не закрывал, закрой лишнее руками")
        if error == "window-missing":
            return ("Окна этого чата не нашёл или новое не появилось за 65 с — "
                    "старое окно не трогал")
    if action == "send":
        # Отправка (WF103): исходы страницы несут заголовок окна (`window` — строка).
        title = str(data.get("window") or "").strip()
        where = f" «{title}»" if title else ""
        if error == "field-busy":
            return f"В окне{where} в поле свой текст — не отправил"
        if error == "no-field":
            return f"В окне{where} нет поля ввода — не отправил"
        if error == "no-send":
            return f"Вставил в окно{where}, но не отправилось — текст в поле"
        if error == "no-answer":
            return f"Отправил в окно{where}, но подтверждения нет — глянь, ушло ли"
        if error == "window-missing":
            what = (f"чата {request['chat']}" if request.get("chat")
                    else f"проекта {short_name(request.get('project', ''))}")
            return f"Окна {what} не нашёл — ничего не отправил"
    if action == "main":
        # Чат в главное окно (WF108, #8148).
        what = request.get("chat") or f"проекта {short_name(request.get('project', ''))}"
        if error == "window-missing":
            titles = [str(title).strip() for title in (data.get("windows") or []) if str(title).strip()]
            if titles:
                return f"Не смог закрыть окно «{titles[0]}» — главное окно не трогал"
            return "Главного окна Claude нет — не с чем меняться"
        if error == "chat-missing":
            return f"Чат {what} в главном окне не открылся — ничего не поменял"
        if error == "chat-unknown":
            return "Окно проекта есть, но его чат не опознан — включи «Цвет по проекту» в меню Пимпа"
        if error == "chat-not-created":
            return "Чат в главном окне, а прежний вынести окном не вышло — он в списке слева"
        if error == "no-answer":
            return "Главное окно не ответило за 15 с — глянь глазами"
    if action == "restart-claude":
        # Перезапуск (WF108): Claude не тронут, если отказ до перезапуска.
        if error == "working":
            names = [str(name).strip() for name in (data.get("chats") or []) if str(name).strip()]
            where = ", ".join(f"«{name}»" for name in names) or "чате"
            return (f"Не перезапускаю: идёт ответ в {where} — дождись или --force "
                    "(оборвёт работающие чаты)")
        if error == "restart-failed":
            reason = str(data.get("reason") or "").strip()
            return f"Claude не перезапустился: {reason}" if reason else "Claude не перезапустился"
        if error == "no-windows":
            return "Claude не запущен — перезапускать нечего"
        if error == "restore-timeout" and isinstance(data.get("skipped"), list) and data["skipped"]:
            # Снимок сдался (гейт 2 WF108): окна нового Claude не появились — какие чаты не вернулись.
            names = ", ".join(f"«{str(title).strip() or 'без имени'}»" for title in data["skipped"])
            return f"Claude перезапустил, но окна не вернулись ({names}) — «↩️ Вернуть окна» в меню Пимпа"
    if action == "arrange" and error == "window-missing" and request.get("center"):
        return f"Окна «{short_name(request['center'])}» для центра не нашёл — ничего не двигал"
    if error == "too-small" and request["action"] == "arrange" and isinstance(data.get("rows"), int):
        # Стопка «A+B+C» выше экрана (WF107): Claude не даёт окну быть ниже 357 pt.
        rows = data["rows"]
        word = "окна" if rows % 10 == 1 and rows % 100 != 11 else "окон"
        return (f"В столбик на этом экране влезает не больше {rows} {word} — "
                "Claude не даёт окну быть ниже")
    if error == "too-small" and request["action"] == "arrange":
        # У «расставить» тесно не окну, а всей раскладке — и лечится это иначе.
        return ("Экран мал: столько окон в эту раскладку не влезает — сделай окна "
                "уже или выбери другую раскладку")
    if error == "chat-unknown":
        # Чата окна приложение не знает — запоминать нечего: вернулись бы не те
        # чаты. Лечится тумблером «🗂 Цвет по проекту» и свободным probe.js (WF41).
        titles = [str(title).strip() for title in (data.get("windows") or [])
                  if str(title).strip()]
        where = ", ".join(f"«{title}»" for title in titles)
        if len(titles) == 1:
            what = f"не знаю, какой чат в окне {where}"
        elif titles:
            what = f"не знаю, какие чаты в окнах {where}"
        else:
            what = "не знаю, какие чаты в окнах"
        return (f"Не могу запомнить: {what} — включи «Цвет по проекту» "
                "в меню Пимпа или подожди минуту")
    if error == "ambiguous":
        # Двусмысленность — отказ без единого движения: закрыть или вставить не в то
        # окно дороже лишнего вопроса (WF75).
        titles = [str(title).strip() for title in (data.get("windows") or [])
                  if str(title).strip()]
        if titles:
            where = ", ".join(f"«{title}»" for title in titles)
            return f"Окон проекта несколько ({where}) — скажи, какое именно, я ничего не трогал"
        return ERRORS["ambiguous"]
    if error == "layout-missing":
        names = [str(name).strip() for name in (data.get("layouts") or [])
                 if str(name).strip()]
        asked = request.get("name", "")
        if names:
            return f"Раскладки «{asked}» нет, есть: " + ", ".join(names)
        return f"Раскладки «{asked}» нет, и сохранённых пока нет"
    if action in ("hide", "show") and error == "window-missing":
        return "Главное окно Claude не нашёл — ничего не прятал"
    if action in ("hide", "show") and error == "no-windows":
        return "Claude не запущен или окон у него нет"
    if error == "window-missing" and action == "close-window":
        return (f"Окон проекта {short_name(request.get('project', ''))} не нашёл — может, окно уже "
                "закрыто, или карта чатов молчит: включи «Цвет по проекту»")
    if error == "window-missing" and action == "new-window" and request.get("chat") == "last":
        # Старый чат точно есть: окно не вынеслось за 15 с или нет главного окна (z4-r04).
        return ("Окно чата не открылось за 15 с — вынеси его руками или повтори --last; "
                "без главного окна Claude выносить чат нечем")
    if error == "window-missing" and action == "paste":
        return "Окна, куда вставлять, не нашёл — открой чат проекта или встань в нужное окно"
    if error == "no-windows" and action == "paste":
        return "Claude сейчас не впереди — встань в нужный чат и повтори"
    if error == "chat-not-created":
        state = str(data.get("state") or "").strip()
        if state == "popout-failed":
            # Чат есть, но в окно не вынесся: «не создан» тут было бы неправдой.
            return "Чат создан, но в окно не вынесся — вынеси его руками"
        words = NOT_CREATED_WORDS.get(state)
        if words:
            return f"Чат не создан: {words}"
        return f"Чат не создан ({state})" if state else ERRORS["chat-not-created"]
    known = ERRORS.get(error)
    if known:
        return known
    return f"Пимп отказал: {error}" if error else "Пимп отказал молча"


def say_arrange(request: dict, data: dict) -> str:
    windows = data.get("windows") or []
    line = f"Расставил {plural(len(windows), 'окно', 'окна', 'окон')}"
    # Просили «last» — приложение пошло умным путём (WF77): окна каждого экрана
    # встали столбцами на своём экране, стоящие на месте не двинулись. В ответе у
    # него `layout: "row"`, но «как сейчас (лента)» — другое поведение, его просят
    # явным `--layout row`; поэтому про умный путь говорим своими словами.
    smart = (str(request.get("layout") or "") == "last"
             and str(data.get("layout") or "") == "row")
    if smart:
        line += ": стоящие на месте не трогал"
    else:
        # Раскладываем на том экране, где стоят окна Claude, — так и говорим (#5732; до 08.09
        # тут стояло «на главном экране», и это была неправда).
        if data.get("screen") == "windows":
            line += " на экране, где стоят окна"
        # Раскладку называем ту, что применилась: «last» приложение разрешает
        # в конкретную, и Элвис должен видеть, что именно вышло (WF21).
        layout = LAYOUT_WORDS.get(str(data.get("layout") or ""))
        if layout:
            line += f": {layout}"
        # Кто встал в центр — по полю hub (WF107); нет его — середина ответа (WF102: (n−1)//2).
        if str(data.get("layout") or "") == "center" and windows:
            hub = data.get("hub")
            if not (isinstance(hub, int) and not isinstance(hub, bool) and 0 <= hub < len(windows)):
                hub = (len(windows) - 1) // 2
            middle = windows[hub]
            folder = middle.get("folder") if isinstance(middle, dict) else ""
            if folder:
                line += f" ({short_name(folder)})"
    # Просили порядок проектов (WF41): кто встал первым, кого не нашли, сколько
    # окон без папки уехало в хвост. Не просили — строка прежняя.
    order = request.get("order") or []
    missing = [str(item) for item in (data.get("missing") or [])]
    if order:
        # Стопка «A+B» (WF107) — словами «A над B»; ненайденные части выпадают по одной.
        first = []
        for item in order:
            parts = [short_name(part) for part in stack_parts(item) if part not in missing]
            if parts:
                first.append(" над ".join(parts))
        if first:
            line += " — сперва " + ", ".join(first)
    skipped = data.get("skipped")
    if isinstance(skipped, int) and skipped > 0:
        line += f", {skipped} не тронул — ячеек нет"
    if order:
        if missing:
            line += "; не нашёл окна: " + ", ".join(short_name(item) for item in missing)
        unknown = data.get("unknown")
        if isinstance(unknown, int) and unknown > 0:
            line += f"; {unknown} без папки — в хвосте"
    return line + minimized_note(data)


def say_layouts(data: dict) -> str:
    parts = []
    for item in (data.get("layouts") or []):
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip()
        if not name:
            continue
        mode = LAYOUT_WORDS.get(str(item.get("mode") or ""), "")
        cells = item.get("cells")
        cells = plural(cells, "окно", "окна", "окон") if isinstance(cells, int) else ""
        tail = ", ".join(part for part in (mode, cells) if part)
        parts.append(f"{name} — {tail}" if tail else name)
    if not parts:
        return "Раскладок пока нет — скажи «запомни раскладку как …»"
    return "Раскладки: " + " · ".join(parts)


def say_layout_save(data: dict) -> str:
    name = str(data.get("name") or "").strip()
    mode = LAYOUT_WORDS.get(str(data.get("mode") or ""), "")
    cells = data.get("cells")
    cells = plural(cells, "окно", "окна", "окон") if isinstance(cells, int) else ""
    tail = ", ".join(part for part in (mode, cells) if part)
    line = f"Запомнил раскладку «{name}»"
    return f"{line}: {tail}" if tail else line


def say_layout_restore(request: dict, data: dict) -> str:
    name = str(data.get("name") or "").strip() or str(request.get("name") or "")
    placed = data.get("placed") if isinstance(data.get("placed"), int) else 0
    opened = data.get("opened") if isinstance(data.get("opened"), int) else 0
    missing = [str(title).strip() for title in (data.get("missing") or [])
               if str(title).strip()]
    # Чат из раскладки закрыт совсем — ячейка осталась пустой, чужой чат туда
    # не подставляется (#5455): говорим об этом вслух.
    tail = ""
    if missing:
        tail = ("; не нашёл " + ("чат: " if len(missing) == 1 else "чаты: ")
                + ", ".join(missing))
    if request.get("fresh"):
        return f"Открыл новые чаты по раскладке «{name}»: {opened}{tail}"
    return f"Вернул «{name}»: {placed} стояло, {opened} открыл{tail}"


def say_close(request: dict, data: dict) -> str:
    title = str(data.get("closed") or "").strip()
    if title:
        return f"Закрыл окно «{title}»"
    return f"Закрыл окно проекта {short_name(request.get('project', ''))}"


def say_renew(data: dict) -> str:
    window = data.get("window") if isinstance(data.get("window"), dict) else {}
    title = str(window.get("title") or "").strip() or "без имени"
    chat = str(window.get("chat") or "").strip()
    line = f"Заменил окно «{title}» новым чатом {chat}"
    if data.get("main"):
        # WF131 (#9078): чат главного окна — новый встал в главное окно, старый в списке слева.
        line = f"Новый чат {chat} открыл в главном окне, старый остался в списке слева"
    # Модель не встала — текст всё равно ушёл первым сообщением (эталон WF102).
    if data.get("model") == "missed":
        line += "; модель не встала — текст ушёл на той, что стояла"
    return line


def say_paste(data: dict) -> str:
    """Вставка — это не отправка: Enter канал не жмёт никогда (WF75)."""
    where = str(data.get("window") or "").strip()
    where = f" в «{where}»" if where else ""
    pasted = data.get("pasted")
    if isinstance(pasted, int) and pasted > 0:
        return f"Вставил {plural(pasted, 'файл', 'файла', 'файлов')}{where} — жми Enter"
    return f"Вставил из буфера{where} — жми Enter"


def say_project(item: dict) -> str:
    """Строка проекта в «projects --status»: сводка status.md и открытые окна."""
    name = str(item.get("name") or "").strip()
    state = str(item.get("state") or "").strip() or "без сводки"
    chats = [str(chat).strip() for chat in (item.get("chats") or []) if str(chat).strip()]
    windows = "окна: " + ", ".join(chats) if chats else "окон нет"
    return f"{name} — {state} · {windows}"


def say_result(request: dict, data: dict) -> str:
    action = request["action"]
    if not data.get("ok"):
        return say_error(request, data)
    if action == "new-window":
        return say_open(request, data)
    if action == "close-window":
        return say_close(request, data)
    if action == "renew-window":
        return say_renew(data)
    if action == "paste":
        return say_paste(data)
    if action == "send":
        title = str(data.get("window") or "").strip()
        if data.get("queued") is True:
            # WF111: в поле свой текст Элвиса — фраза ждёт в очереди окна и уйдёт, когда поле опустеет.
            where = f" «{title}»" if title else ""
            return f"Фраза ждёт в окне{where}: в поле твой текст — уйдёт, как только поле опустеет"
        return f"Отправил в «{title}»" if title else "Отправил"
    if action == "hud":
        return "Показал плашку"
    if action in ("hide", "show"):
        return say_hide(request, data)
    if action == "dim":
        return say_dim(data)
    if action == "look":
        return say_look(request, data)
    if action == "arrange":
        return say_arrange(request, data)
    if action == "layouts":
        return say_layouts(data)
    if action == "layout-save":
        return say_layout_save(data)
    if action == "layout-restore":
        return say_layout_restore(request, data)
    if action == "projects":
        items = [item for item in (data.get("projects") or []) if isinstance(item, dict)
                 and str(item.get("name") or "").strip()]
        if not items:
            return "Проектов Пимп пока не знает — открой чат в папке проекта"
        if request.get("status"):
            # Со сводкой строка на проект: в одну её не уложить (WF41).
            return "\n".join(say_project(item) for item in items)
        return "Проекты: " + ", ".join(str(item["name"]).strip() for item in items)
    if action == "windows":
        items = [item for item in (data.get("windows") or []) if isinstance(item, dict)]
        # ChatGPT (WF94) — отдельной записью с полем app: окном Claude его не считаем.
        chatgpt = any(item.get("app") == CHATGPT_APP for item in items)
        titles = [str(item.get("title") or "").strip() or "без имени"
                  for item in items if not item.get("app")]
        tail = "; ещё окно ChatGPT" if chatgpt else ""
        if not titles:
            return f"Окон Claude нет{tail}{hidden_note(data)}"
        return (f"Окон {len(titles)}: " + " · ".join(titles)) + tail + hidden_note(data)
    if action == "main":
        if data.get("already"):
            return "Этот чат уже в главном окне"
        if str(data.get("popped") or "").strip():
            return "Чат в главном окне, прежний — в своём окне"
        return "Чат в главном окне"
    if action == "restart-claude":
        placed = data.get("placed") if isinstance(data.get("placed"), int) else 0
        opened = data.get("opened") if isinstance(data.get("opened"), int) else 0
        skipped = [str(title).strip() or "без имени" for title in (data.get("skipped") or [])]
        line = (f"Перезапустил Claude, окна вернул: {placed} на месте, "
                f"{plural(opened, 'чат', 'чата', 'чатов')} открыл заново")
        if skipped:
            line += "; не нашёл: " + ", ".join(f"«{title}»" for title in skipped)
        return line
    if action == "screens-restore":
        placed = data.get("placed") if isinstance(data.get("placed"), int) else 0
        missing = data.get("missing") if isinstance(data.get("missing"), int) else 0
        line = f"Вернул окна как стояли на этих мониторах: {plural(placed, 'окно', 'окна', 'окон')}"
        if missing > 0:
            line += f"; {missing} не нашёл — закрытые чаты не открываю"
        return line
    return "Пимп ответил, но я не знаю на что"


SILENT_LINES = {
    "write": "Не смог положить запрос Пимпу",
    "silent": "Пимп не запущен",
    "timeout": "Пимп взял запрос и не ответил — посмотри, жив ли он",
    "bad": "Пимп ответил непонятным файлом",
}


def send(request: dict, total=None):
    """Положить запрос и дождаться ответа: (вид, разобранный ответ, сырой текст).

    Вид — "ok" | "write" | "silent" | "timeout" | "bad"; ответ есть только у "ok".
    """
    directory = pimp_dir()
    try:
        write_request(directory, request)
    except OSError as error:
        return "write", None, str(error)
    kind, raw = wait_result(directory, request["id"], total)
    if kind != "ok":
        return kind, None, raw
    try:
        data = json.loads(raw)
    except ValueError:
        return "bad", None, raw
    if not isinstance(data, dict):
        return "bad", None, raw
    return "ok", data, raw


def run(request: dict, as_json: bool) -> int:
    warn_probe(pimp_dir())
    restart = request.get("action") == "restart-claude"
    if restart and not as_json:
        # Первой строкой — id (WF108): из чата внутри Claude CLI погибнет вместе с Claude,
        # и ответ читают потом из pimp/<id>.result.json.
        print(request["id"], flush=True)
    total = seconds("MYCLAUDE_PIMP_RESTART_WAIT", RESTART_WAIT_S) if restart else None
    kind, data, raw = send(request, total)
    if request.get("action") in ("new-window", "renew-window", "send", "close-window"):
        # Занят — повторяем новым id и свежим at (как deliver у голоса).
        deadline = time.monotonic() + seconds("MYCLAUDE_PIMP_BUSY", OPEN_BUSY_S)
        while (kind == "ok" and data.get("ok") is False and str(data.get("error") or "") == "busy"
               and time.monotonic() + BUSY_RETRY_S < deadline):
            time.sleep(BUSY_RETRY_S)
            request["id"] = new_id()
            request["at"] = now_iso()
            kind, data, raw = send(request)
    if kind != "ok":
        # В режиме --json непонятный ответ печатаем как есть и молчим: лишняя строка
        # сверху сломала бы разбор тому, кто нас позвал.
        if kind == "bad" and as_json:
            print(raw.strip())
        elif kind == "write":
            print(f"Не смог положить запрос в {pimp_dir()}: {raw}")
        elif restart and kind == "timeout":
            # Исхода не знаем: Claude мог и перезапуститься (гейт 2 WF108) — говорим нейтрально.
            print(f"Ответа нет за {total:g} с — исход ляжет в pimp/{request['id']}.result.json")
        else:
            print(SILENT_LINES[kind])
        return 1
    if as_json:
        print(raw.strip())
    else:
        print(say_result(request, data))
    return 0 if data.get("ok") else 1


# ---- Эйрдроп: какие фотки считать новыми --------------------------------------

def downloads_dir() -> Path:
    value = os.environ.get(DOWNLOADS_ENV, "").strip()
    return Path(value).expanduser() if value else DEFAULT_DOWNLOADS


def mark_path() -> Path:
    """Отметка последней вставленной фотки — рядом с каналом, не внутри него:
    файлы в pimp/ приложение убирает по часу (WF36)."""
    return pimp_dir().parent / "voice-pasted.json"


def read_mark() -> float:
    try:
        data = json.loads(mark_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return 0.0
    value = data.get("mtime") if isinstance(data, dict) else None
    return float(value) if isinstance(value, (int, float)) else 0.0


def write_mark(mtime: float) -> None:
    body = json.dumps({"mtime": mtime}, separators=(",", ":")) + "\n"
    path = mark_path()
    try:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        handle = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            file.write(body)
    except OSError:
        pass


def airdrop_batch():
    """Порция фоток из загрузок: (пути по времени, отметка, почему пусто).

    Эйрдроп кладёт пачку подряд, поэтому порция — свежайшая фотка и всё, что
    легло вплотную к ней (разрыв не больше AIRDROP_GAP_S), но только то, чего
    ещё не вставляли. Вся пачка старше получаса — это не «сейчас скинул», и
    молча тащить её в чат нельзя.
    """
    shots = []
    try:
        entries = list(downloads_dir().iterdir())
    except OSError:
        entries = []
    for item in entries:
        if item.suffix.lower() not in PHOTO_EXT or not item.is_file():
            continue
        try:
            shots.append((item.stat().st_mtime, item))
        except OSError:
            continue
    shots.sort(key=lambda pair: pair[0])
    if not shots:
        return [], 0.0, "картинок в загрузках нет"
    newest = shots[-1][0]
    if time.time() - newest > AIRDROP_FRESH_S:
        return [], 0.0, "свежих фоток нет — последняя старше получаса"
    mark = read_mark()
    if newest <= mark:
        return [], 0.0, "новых фоток нет — эти я уже вставлял"
    batch, previous = [], None
    for stamp, item in reversed(shots):
        if stamp <= mark or (previous is not None and previous - stamp > AIRDROP_GAP_S):
            break
        batch.append((stamp, item))
        previous = stamp
        if len(batch) >= AIRDROP_LIMIT:
            break
    batch.reverse()
    return [str(item) for _, item in batch], newest, ""


# ---- Мозг: фраза голосом → шаги ------------------------------------------------

class VoiceError(RuntimeError):
    """Не ответил, ответил не тем или ответить нечем."""

    def __init__(self, message: str, head: str = "Пимп не понял"):
        super().__init__(message)
        self.head = head

    def line(self) -> str:
        return f"{self.head}: {self}"


def voice_env_path() -> Path:
    value = os.environ.get(VOICE_ENV_ENV, "").strip()
    return Path(value).expanduser() if value else DEFAULT_VOICE_ENV


def voice_env(path: Path) -> dict:
    """Строки вида ИМЯ=значение. Значения наружу не отдаются — только сюда."""
    values = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, _, value = line.partition("=")
        values[name.strip()] = value.strip().strip('"').strip("'")
    return values


def voice_prompt_text(names: list) -> str:
    try:
        body = VOICE_PROMPT.read_text(encoding="utf-8")
    except OSError as error:
        raise VoiceError(f"нет файла {VOICE_PROMPT.name} ({error})")
    # В модель уходят ТОЛЬКО имена проектов: папки Элвиса наружу не отдаём (WF75).
    return body + "\n## Список проектов\n\n" + ", ".join(names) + "\n"


def voice_json(content: str) -> dict:
    """Терпимый разбор: модель иногда заворачивает ответ в ```json … ```."""
    text = (content or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text, flags=re.IGNORECASE).strip()
    for attempt in (text, ""):
        if attempt == "":
            match = re.search(r"\{.*\}", text, flags=re.DOTALL)
            attempt = match.group(0) if match else ""
        if not attempt:
            break
        try:
            data = json.loads(attempt)
        except ValueError:
            continue
        if isinstance(data, dict):
            return data
    raise VoiceError("модель ответила не JSON")


class VoiceNoRedirect(urllib.request.HTTPRedirectHandler):
    """Не переносить фразу и Authorization на адрес из ответа сервера."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, "redirect refused", headers, fp)


def voice_endpoint(base: str) -> str:
    """Ключ и голосовая фраза уходят только по HTTPS, без реквизитов в URL."""
    try:
        parsed = urllib.parse.urlsplit(base)
        valid = (parsed.scheme == "https" and bool(parsed.hostname)
                 and parsed.username is None and parsed.password is None
                 and not parsed.query and not parsed.fragment
                 and not any(c.isspace() or ord(c) < 32 for c in base))
        parsed.port  # негодный номер порта тоже даёт понятный отказ
    except ValueError:
        valid = False
    if not valid:
        raise VoiceError("адрес DeepSeek должен быть HTTPS без логина, пароля и параметров")
    return base.rstrip("/") + "/chat/completions"


def voice_net(phrase: str, names: list, values: dict):
    """Один POST и жёсткий срок: рассуждения выключены, ответ — объект JSON."""
    key = values.get("DEEPSEEK_API_KEY", "").strip()
    model = (values.get("DEEPSEEK_MODEL") or VOICE_MODEL).strip()
    base = (values.get("DEEPSEEK_BASE_URL") or VOICE_BASE).strip().rstrip("/")
    endpoint = voice_endpoint(base)
    payload = {
        "model": model,
        "messages": [{"role": "system", "content": voice_prompt_text(names)},
                     {"role": "user", "content": phrase}],
        "response_format": {"type": "json_object"},
        "max_tokens": VOICE_MAX_TOKENS,
        "thinking": {"type": "disabled"},
    }
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        # Ключ только заголовком: в URL он попал бы в логи прокси.
        headers={"Authorization": "Bearer " + key,
                 "Content-Type": "application/json; charset=utf-8"},
        method="POST")
    try:
        with urllib.request.build_opener(VoiceNoRedirect()).open(request, timeout=VOICE_TIMEOUT_S) as answer:
            body = answer.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        detail = ""
        try:
            detail = error.read().decode("utf-8", "replace")[:300].lower()
        except Exception:      # noqa: BLE001 — тело ошибки читаться не обязано
            pass
        if error.code == 400 and "model" in detail:
            raise VoiceError(f"модель {model} не принята", head="Пимп")
        raise VoiceError(f"DeepSeek ответил ошибкой {error.code}")
    except (urllib.error.URLError, TimeoutError, OSError):
        raise VoiceError(f"DeepSeek не ответил за {int(VOICE_TIMEOUT_S)} с")
    except UnicodeError:
        # Заголовок берёт только латиницу: кривой ключ иначе свалил бы CLI трассой.
        raise VoiceError("ключ DeepSeek не годится — в нём не латинские знаки",
                         head="Пимп")
    try:
        answer = json.loads(body)
        content = answer["choices"][0]["message"]["content"]
    except (ValueError, KeyError, IndexError, TypeError):
        raise VoiceError("DeepSeek прислал ответ незнакомого вида")
    return voice_json(content), str(answer.get("model") or model)


def voice_ask(phrase: str, names: list):
    """Спросить мозг: (ответ модели, имя модели).

    MYCLAUDE_VOICE_FAKE проверяется ДО ключа и сети: тесты гоняют настоящий CLI,
    и уйти в живой DeepSeek с ключом Элвиса им нельзя ни при каких условиях.
    """
    fake = os.environ.get(VOICE_FAKE_ENV, "").strip()
    if fake:
        try:
            data = json.loads(Path(fake).expanduser().read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise VoiceError(f"подставной ответ не читается ({error})")
        if not isinstance(data, dict):
            raise VoiceError("подставной ответ не объект")
        return data, str(data.get("model") or "fake")
    path = voice_env_path()
    try:
        values = voice_env(path)
    except OSError:
        values = {}
    if not values.get("DEEPSEEK_API_KEY", "").strip():
        raise VoiceError(f"ключа DeepSeek нет — впиши DEEPSEEK_API_KEY в {path}",
                         head="Пимп")
    return voice_net(phrase, names, values)


def voice_project(value, names: list):
    """Проект берётся только из живого списка: открыть чужую папку
    дороже лишнего вопроса (тот же запрет, что в скилле)."""
    want = str(value or "").strip()
    for name in names:
        if name.lower() == want.lower():
            return name
    return None


def voice_steps(answer: dict, phrase: str, names: list):
    """Ответ модели → (шаги, отказы). Ворота стоят ЗДЕСЬ, в коде: «уверена» ли
    модель, она решает сама, и защитой это не работает (критик WF75, п. 10).
    """
    low = phrase.lower()
    steps, refused, opened = [], [], 0
    raw = answer.get("steps")
    for item in (raw if isinstance(raw, list) else []):
        if not isinstance(item, dict):
            continue
        action = str(item.get("action") or "").strip()
        asked = str(item.get("project") or "").strip()
        project = voice_project(asked, names) if action in ("open", "close") else None
        if action in ("open", "close") and not project:
            refused.append(f"не знаю проект «{asked}»")
            continue
        if action == "none":
            steps.append({"action": "none", "say": str(item.get("say") or "").strip()})
        elif action == "open":
            if opened >= VOICE_OPEN_LIMIT:
                refused.append(f"больше {VOICE_OPEN_LIMIT} окон за раз не открываю")
                continue
            opened += 1
            place = str(item.get("place") or "").strip().lower()
            chat = str(item.get("chat") or "").strip().lower()
            steps.append({"action": "open", "project": project,
                          "place": place if place in PLACES else "right",
                          "chat": "last" if chat == "last" else "new"})
        elif action == "close":
            if not any(word in low for word in CLOSE_WORDS):
                refused.append("окно не закрывал: слова «закрой» в твоей фразе нет")
                continue
            steps.append({"action": "close", "project": project})
        elif action == "arrange":
            layout = str(item.get("layout") or "").strip().lower()
            asked_order = item.get("order")
            order = [voice_project(name, names)
                     for name in (asked_order if isinstance(asked_order, list) else [])]
            steps.append({"action": "arrange",
                          "layout": layout if layout in LAYOUTS_VOICE else "last",
                          "order": [name for name in order if name]})
        elif action in ("layout_save", "layout_restore"):
            name = str(item.get("name") or "").strip()
            if not name:
                refused.append("не расслышал имя раскладки")
                continue
            step = {"action": action, "name": name}
            if action == "layout_restore":
                step["fresh"] = item.get("fresh") is True
            steps.append(step)
        elif action == "paste_airdrop":
            if not any(word in low for word in PHOTO_WORDS):
                refused.append("фоток не вставлял: про фотки в твоей фразе нет")
                continue
            steps.append({"action": "paste_airdrop"})
        elif action in ("paste_clipboard", "projects", "windows"):
            steps.append({"action": action})
        else:
            refused.append(f"шага «{action}» я не умею")
    # Несколько окон подряд сами собой встают стопкой — раскладку добавляем, если
    # модель о ней не сказала: порядок берём тот, в котором она назвала проекты.
    if opened >= 2 and not any(step["action"] == "arrange" for step in steps):
        steps.append({"action": "arrange", "layout": "last", "auto": True,
                      "order": [step["project"] for step in steps
                                if step["action"] == "open"]})
    return steps, refused


VOICE_ACTIONS = {
    "open": "new-window", "close": "close-window", "arrange": "arrange",
    "layout_save": "layout-save", "layout_restore": "layout-restore",
    "paste_airdrop": "paste", "paste_clipboard": "paste",
    "projects": "projects", "windows": "windows",
}


def step_request(step: dict, paths=None) -> dict:
    """Шаг → запрос канала. Порядок ключей — как в эталонах (build_request рядом)."""
    action = VOICE_ACTIONS[step["action"]]
    request = {"id": new_id(), "at": now_iso(), "action": action, "from": from_chat()}
    if action == "new-window":
        request["project"] = step["project"]
        request["place"] = step["place"]
        if step["chat"] == "last":
            request["chat"] = "last"
    elif action == "close-window":
        request["project"] = step["project"]
    elif action == "paste":
        # Голос всегда вставляет в переднее окно: Элвис жмёт F5 в том чате, куда
        # диктует, — это то же самое, что его собственное ⌘V.
        request["front"] = True
        if paths:
            request["paths"] = paths
    elif action == "arrange":
        request["layout"] = step["layout"]
        if step.get("order"):
            request["order"] = step["order"]
    elif action == "layout-save":
        request["name"] = step["name"]
    elif action == "layout-restore":
        request["name"] = step["name"]
        request["fresh"] = step["fresh"]
    return request


def deliver(request: dict, deadline: float):
    """Отправить и на «занят» повторить с НОВЫМ id и свежим at: у старого id ответ
    уже лежит, второй раз приложение его не возьмёт, а `at` старше 30 с даст stale."""
    while True:
        kind, data, _ = send(request)
        if kind != "ok" or str(data.get("error") or "") != "busy":
            return kind, data
        if time.monotonic() + BUSY_RETRY_S >= deadline:
            return "ok", data
        time.sleep(BUSY_RETRY_S)
        request["id"] = new_id()
        request["at"] = now_iso()


def voice_names(deadline: float):
    """Живой список проектов: (имена, что сказать, если не вышло)."""
    request = {"id": new_id(), "at": now_iso(), "action": "projects", "from": from_chat()}
    kind, data = deliver(request, deadline)
    if kind != "ok":
        return None, SILENT_LINES[kind]
    if not data.get("ok"):
        return None, say_error(request, data)
    names = [str(item.get("name") or "").strip() for item in (data.get("projects") or [])
             if isinstance(item, dict) and str(item.get("name") or "").strip()]
    if not names:
        return None, "Проектов Пимп пока не знает — открой чат в папке проекта"
    return names, ""


def voice_do(step: dict, deadline: float):
    """Один шаг: (вышло ли, строка для Элвиса)."""
    action = step["action"]
    if action == "none":
        return True, step.get("say") or "Понял, ничего не трогаю"
    paths, mark = None, 0.0
    if action == "paste_airdrop":
        paths, mark, why = airdrop_batch()
        if not paths:
            return False, why
    request = step_request(step, paths)
    kind, data = deliver(request, deadline)
    if kind != "ok":
        return False, SILENT_LINES[kind]
    line = say_result(request, data)
    if not data.get("ok"):
        return False, line
    if action == "paste_airdrop":
        write_mark(mark)
    return True, line


def voice_hud(text: str) -> None:
    """Плашка — не итог: ответ не разбираем. Канал отвечает на hud и занятым."""
    text = (text or "").strip()[:HUD_LIMIT]
    if not text:
        return
    send({"id": new_id(), "at": now_iso(), "action": "hud",
          "from": from_chat(), "text": text})


def voice_log(phrase: str, steps: list, refused: list, result: str,
              started: float, model: str) -> None:
    """Журнал 0600 рядом с каналом: тут лежит речь Элвиса, ключа — нет."""
    record = {"at": now_iso(), "phrase": phrase, "steps": steps, "refused": refused,
              "result": result, "ms": int((time.monotonic() - started) * 1000),
              "model": model}
    path = pimp_dir().parent / "voice-log.jsonl"
    try:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            lines = []
        lines = [line for line in lines if line.strip()]
        lines.append(json.dumps(record, ensure_ascii=False))
        handle = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            file.write("\n".join(lines[-VOICE_LOG_LINES:]) + "\n")
        os.chmod(path, 0o600)
    except OSError:
        pass


def run_say(phrase: str) -> int:
    """«Пимп, открой три чата…»: фраза → шаги → канал. Текст приходит с мусором
    распознавания, поэтому смысл вынимает модель, а разрешает — код."""
    started = time.monotonic()
    deadline = started + VOICE_BUDGET_S
    warn_probe(pimp_dir())
    phrase = (phrase or "").strip()
    if not phrase:
        print("Пимп не понял: фраза пустая")
        return 1
    names, trouble = voice_names(deadline)
    if names is None:
        print(trouble)
        return 1
    try:
        answer, model = voice_ask(phrase, names)
    except VoiceError as error:
        voice_hud(error.line())
        voice_log(phrase, [], [], error.line(), started, "")
        print(error.line())
        return 1
    steps, refused = voice_steps(answer, phrase, names)
    lines, fails, done = [], list(refused), 0
    # Дописанный нами `arrange` Элвис не заказывал — в счёт «сделал N из M» он не идёт.
    total = len(refused) + sum(1 for step in steps if not step.get("auto"))
    for step in steps:
        if time.monotonic() >= deadline:
            fails.append("на остальное времени не хватило")
            break
        ok, line = voice_do(step, deadline)
        (lines if ok else fails).append(line)
        done += 1 if ok and not step.get("auto") else 0
    if fails:
        result = (f"Сделал {done} из {total}" if done else "Не вышло") + ": " + "; ".join(fails)
    else:
        result = "; ".join(lines) or "Пимп не понял, что сделать"
    # Плашке — короткая фраза модели, в stdout — что вышло на самом деле; сорвалось
    # хоть что-то — плашка говорит ровно то же, что stdout, иначе соврёт.
    said = str(answer.get("say") or "").strip()
    voice_hud(said if (said and not fails) else result)
    voice_log(phrase, steps, refused, result, started, model)
    print(result)
    # Ни одного сделанного шага — это отказ, даже когда жаловаться не на что.
    return 1 if (fails or not lines) else 0


def run_paste_airdrop(args) -> int:
    paths, mark, why = airdrop_batch()
    if not paths:
        print(why[:1].upper() + why[1:])
        return 1
    args.paths = paths
    code = run(build_request(args), getattr(args, "as_json", False))
    if code == 0:
        write_mark(mark)
    return code


# ---- Фото чата по номерам (WF98, #7851) -----------------------------------------
# Номера — ровно как у галереи (PimpViewer, web/model.js chatNumbers): фото склада, где в
# chats есть этот чат, по createdAt, при равенстве по имени (basename пути —
# так его отдаёт мост, ViewerStore.item), потом по id; счёт с 1. Склад только читаем.

def viewer_dir() -> Path:
    return pimp_dir().parent / "viewer"


def js_key(text: str) -> bytes:
    """Строки в JS сравниваются по кодовым единицам UTF-16 — так же и здесь."""
    return str(text).encode("utf-16-be", "surrogatepass")


def chat_photos(chat: str) -> list:
    data = json.loads((viewer_dir() / "index.json").read_text(encoding="utf-8"))
    records = data.get("records") if isinstance(data, dict) else None
    photos = [r for r in (records or []) if isinstance(r, dict) and r.get("kind") == "photo"
              and chat in (r.get("chats") or [])]
    photos.sort(key=lambda r: (r.get("createdAt") or 0,
                               js_key(os.path.basename(str(r.get("path") or ""))),
                               js_key(r.get("id") or "")))
    return photos


def photo_path(record: dict) -> str:
    """Исходный файл; пропал — копия склада, если она есть."""
    path = str(record.get("path") or "")
    if path and os.path.exists(path):
        return path
    copy = record.get("copy")
    if copy and (viewer_dir() / copy).exists():
        return str(viewer_dir() / copy)
    return path


def run_gallery(args) -> int:
    chat = (args.chat or from_chat()).strip()
    if not chat:
        print("Не знаю, какой чат: нет CLAUDE_CODE_HOST_SESSION_ID — назови его ключом --chat local_…")
        return 1
    try:
        photos = chat_photos(chat)
    except (OSError, ValueError):
        print("Склад Viewer не прочитался — Viewer ещё ни разу не открывали?")
        return 1
    if not photos:
        print("В этом чате фото нет")
        return 1
    if args.number is None:
        for n, record in enumerate(photos, 1):
            print(f"{n}  {photo_path(record)}")
        return 0
    if not 1 <= args.number <= len(photos):
        print(f"Фото {args.number} в этом чате нет: их {len(photos)}, номера 1…{len(photos)}")
        return 1
    print(photo_path(photos[args.number - 1]))
    return 0


# ---- Сводка окон (WF102, #7916) --------------------------------------------------
# Главному чату — что в окнах, не читая переписок: окна берём у канала (`windows`),
# остальное только ЧИТАЕМ из файлов Claude. Файл сессии даёт папку, время и итог хода
# (postTurnSummary), хвост транскрипта — строку состояния и «👾 ЭЛВИС, СДЕЛАЙ».

SESSIONS_ENV = "MYCLAUDE_CLAUDE_SESSIONS"
TRANSCRIPTS_ENV = "MYCLAUDE_CLAUDE_PROJECTS"
DEFAULT_SESSIONS = (Path.home() / "Library" / "Application Support" / "Claude"
                    / "claude-code-sessions")
DEFAULT_TRANSCRIPTS = Path.home() / ".claude" / "projects"
TAIL_BYTES = 512 * 1024
CACHE_MINUTES = 60
SUMMARY_TODO = 3
SUMMARY_CLIP = 160
# Слово и значок строки состояния — в конце строки (SkilZZZ/ELVIS.md, «Строка состояния»).
STATUS_LINE_RE = re.compile(r"(идёт|жду|готово|упал)\s*(💭|❓|✅|🛑)\s*$")
TODO_HEAD_RE = re.compile(r"^#+\s*👾\s*ЭЛВИС,\s*СДЕЛАЙ")
TODO_ITEM_RE = re.compile(r"^(\d+)[.)]\s+(.*)$|^[-*•]\s+(.*)$")
LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
SUMMARY_STATES = {
    "blocked": "ждёт Элвиса",
    "review_ready": "ждёт проверки",
    "completed": "готово",
}


def env_dir(name: str, default: Path) -> Path:
    value = os.environ.get(name, "").strip()
    return Path(value).expanduser() if value else default


def clip(text: str, limit: int = SUMMARY_CLIP) -> str:
    text = " ".join(str(text or "").split())
    return text if len(text) <= limit else text[:limit - 1].rstrip() + "…"


def plain(text: str) -> str:
    """Ссылки — одной подписью, жирный — без звёздочек: главному чату это лишние токены."""
    return LINK_RE.sub(r"\1", str(text)).replace("**", "").strip()


def session_files(chat: str = "local_*"):
    """Файлы сессий Claude: claude-code-sessions/<аккаунт>/<место>/local_<id>.json."""
    for path in sorted(env_dir(SESSIONS_ENV, DEFAULT_SESSIONS).glob(f"*/*/{chat}.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict):
            yield data


# #8364: чат Рика — папка проекта Rick (как путь голоса Рика `<projectsRoot>/Rick/voice`).
RICK_PROJECT = "Rick"
RICK_VOICE_PREFIX = "Голос Элвиса:"
RICK_BUS = os.path.expanduser("~/Projects/Rick/tools/rick_bus.py")


def send_to_rick(args) -> bool:
    """Отправка адресована чату Рика: --project Rick или --chat, чья сессия живёт в папке Rick."""
    project = str(getattr(args, "project", None) or "").strip().rstrip("/")
    if project:
        return Path(project).name.lower() == RICK_PROJECT.lower()
    chat = str(getattr(args, "chat", None) or "")
    if not chat:
        return False
    for data in session_files(chat):
        cwd = str(data.get("cwd") or data.get("originCwd") or "").rstrip("/")
        if cwd and Path(cwd).name.lower() == RICK_PROJECT.lower():
            return True
    return False


def session_by_title(title: str):
    """Чата окна канал не знает (probe.js занят, карта замерла) — ищем по заголовку,
    но только если живой сессии с таким заголовком ровно одна: наугад не подставляем."""
    if not title:
        return None
    found = [data for data in session_files() if not data.get("isArchived")
             and str(data.get("title") or "").strip() == title]
    return found[0] if len(found) == 1 else None


def transcript_tail(cli_session: str) -> list:
    """Записи хвоста транскрипта (≤ 512 КБ). Файл длиннее — первая строка рваная, её вон."""
    if not cli_session:
        return []
    paths = []
    for path in env_dir(TRANSCRIPTS_ENV, DEFAULT_TRANSCRIPTS).glob(f"*/{cli_session}.jsonl"):
        try:
            paths.append((path.stat().st_mtime_ns, str(path), path))
        except OSError:
            continue
    if not paths:
        return []
    # Как ChatContext.transcript: копия с самой свежей записью, а не первая папка по алфавиту.
    newest = max(paths)[2]
    try:
        with newest.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - TAIL_BYTES))
            tail = handle.read()
    except OSError:
        return []
    lines = tail.split(b"\n")
    if size > TAIL_BYTES:
        lines = lines[1:]
    records = []
    for raw in lines:
        try:
            record = json.loads(raw)
        except ValueError:
            continue
        if isinstance(record, dict):
            records.append(record)
    return records


def turn_running(records: list) -> bool:
    """Ход идёт, если последняя реплика основной ветки — не законченный ответ."""
    for record in reversed(records):
        if record.get("type") not in ("user", "assistant") or record.get("isSidechain"):
            continue
        message = record.get("message") if isinstance(record.get("message"), dict) else {}
        if record["type"] == "assistant":
            return message.get("stop_reason") != "end_turn"
        content = message.get("content")
        text = content if isinstance(content, str) else ""
        return "Request interrupted" not in text
    return False


def last_answer(records: list) -> str:
    """Текст последнего законченного ответа (все его куски с тем же message.id)."""
    for index in range(len(records) - 1, -1, -1):
        record = records[index]
        message = record.get("message") if isinstance(record.get("message"), dict) else {}
        if (record.get("type") != "assistant" or record.get("isSidechain")
                or message.get("stop_reason") != "end_turn"):
            continue
        mid = message.get("id")
        parts = []
        for other in records[:index + 1]:
            body = other.get("message") if isinstance(other.get("message"), dict) else {}
            if other.get("type") != "assistant" or (mid and body.get("id") != mid):
                continue
            if not mid and other is not record:
                continue
            for block in (body.get("content") or []):
                if isinstance(block, dict) and block.get("type") == "text":
                    parts.append(str(block.get("text") or ""))
        return "\n".join(parts)
    return ""


def status_line(answer: str) -> str:
    for line in reversed(answer.splitlines()):
        if STATUS_LINE_RE.search(line.strip()):
            return clip(plain(line))
    return ""


def todo_items(answer: str) -> list:
    """До трёх пунктов блока «👾 ЭЛВИС, СДЕЛАЙ» — до следующего заголовка."""
    items, inside = [], False
    for line in answer.splitlines():
        stripped = line.strip()
        if TODO_HEAD_RE.match(stripped):
            inside, items = True, []
            continue
        if not inside:
            continue
        if stripped.startswith("#"):
            break
        if line[:1].isspace():
            continue                 # вложенный пункт — не отдельное дело
        match = TODO_ITEM_RE.match(stripped)
        if match:
            number = match.group(1) or str(len(items) + 1)
            items.append(f"{number}. " + clip(plain(match.group(2) or match.group(3))))
    return items[:SUMMARY_TODO]


def window_card(window: dict, now_ms: float) -> dict:
    chat = str(window.get("chat") or "").strip()
    folder = str(window.get("folder") or "").strip()
    card = {"chat": chat, "project": short_name(folder) if folder else "",
            "title": str(window.get("title") or "").strip(), "data": False}
    if CHAT_RE.match(chat):
        session = next(session_files(chat), None)
    else:
        session = session_by_title(card["title"])
    if session is None:
        return card
    card["data"] = True
    card["chat"] = str(session.get("sessionId") or chat)
    if session.get("cwd"):
        card["project"] = short_name(session["cwd"])
    if str(session.get("title") or "").strip():
        card["title"] = str(session["title"]).strip()
    records = transcript_tail(str(session.get("cliSessionId") or ""))
    summary = session.get("postTurnSummary") if isinstance(session.get("postTurnSummary"), dict) else {}
    if turn_running(records):
        card["state"] = "идёт"
    else:
        card["state"] = SUMMARY_STATES.get(str(summary.get("status_category") or ""), "ждёт")
    card["needs"] = clip(summary.get("needs_action") or "")
    last = session.get("lastActivityAt")
    if isinstance(last, (int, float)) and last > 0:
        left_ms = CACHE_MINUTES * 60000 - (now_ms - last)
        card["cacheMinutes"] = max(0, int(left_ms // 60000)) if left_ms > 0 else 0
        card["cacheCold"] = left_ms <= 0
    answer = last_answer(records)
    card["status"] = status_line(answer)
    card["todo"] = todo_items(answer)
    return card


def say_card(card: dict) -> str:
    """Окно — не больше 6 строк: шапка, строка состояния, что нужно, три дела."""
    name = card["project"] or "без папки"
    title = f" · «{card['title']}»" if card["title"] else ""
    if not card["data"]:
        return f"{name}{title} — нет данных"
    head = f"{name}{title} — {card['state']}"
    if "cacheCold" in card:
        if card["cacheCold"]:
            head += " · кеш остыл"
        else:
            minutes = card["cacheMinutes"]
            head += f" · кеш {minutes} мин" if minutes else " · кеш <1 мин"
    lines = [head]
    if card.get("status"):
        lines.append("  " + card["status"])
    if card.get("needs"):
        lines.append("  нужно: " + card["needs"])
    lines.extend("  " + item for item in card.get("todo") or [])
    return "\n".join(lines[:6])


def run_summary(as_json: bool) -> int:
    warn_probe(pimp_dir())
    request = {"id": new_id(), "at": now_iso(), "action": "windows", "from": from_chat()}
    kind, data, raw = send(request)
    if kind != "ok":
        print(f"Не смог положить запрос в {pimp_dir()}: {raw}" if kind == "write"
              else SILENT_LINES[kind])
        return 1
    if not data.get("ok"):
        print(say_error(request, data))
        return 1
    # ChatGPT (запись с app) — не окно Claude: у него нет ни сессии, ни транскрипта.
    windows = [item for item in (data.get("windows") or [])
               if isinstance(item, dict) and not item.get("app")]
    now_ms = time.time() * 1000
    cards = [window_card(item, now_ms) for item in windows]
    try:
        terminals = [term_summary(chat) for chat in term_chats(prune=False, with_terminal=True)]
    except TermError:
        terminals = []
    if as_json:
        print(json.dumps(cards + terminals, ensure_ascii=False))
    elif not cards and not terminals:
        print(f"Окон Claude нет{minimized_note(data)}")
    else:
        lines = [say_card(card) for card in cards]
        for card in terminals:
            ctx = f"{card['contextTokens'] // 1000}K" if card['contextTokens'] is not None else "—"
            age = f"{card['activityMinutes']} мин назад" if card['activityMinutes'] is not None else "—"
            lines.append(f"{card['name']} ({card['kind']}) · ctx {ctx} · {age}")
        print("\n".join(lines))
    return 0


# ---- Терминальные чаты (WF111) --------------------------------------------------
# Подчинённый чат — не окно Claude, а `claude` в терминале: меньше памяти и тепла.
# Вкладка Terminal (или окно iTerm2) с заголовком «rick-<проект>»; есть tmux — внутри
# tmux-сессия с тем же именем, и писать в неё можно, не трогая окон. Пользовательские
# данные (текст, пути) в AppleScript не вклеиваются никогда — только аргументами
# osascript; в оболочку — через shlex.quote в файле запуска, который удаляет себя сам.
# Заголовок — только для глаза: claude переписывает его сразу. Адрес вкладки — её tty:
# файл запуска до exec claude пишет tty и pid в реестр term/<проект>.json (0600, атомарно),
# живость — этот pid ещё на этом tty (ps -t). С tmux главный адрес — сессия rick-<проект>.

TERM_PREFIX = "rick-"
TERM_MODEL = "claude-opus-5-5"
TERM_EFFORTS = ("low", "medium", "high", "xhigh", "max")
# Режим разрешений по `claude --help` (2.1.284): acceptEdits | auto | bypassPermissions | …
# bypassPermissions — слово Элвиса 08.10.2026 (#9047): в терминалы он не заходит и ничего не жмёт.
TERM_PERMISSION = "bypassPermissions"
TERM_TEXT_LIMIT = 20000
TERM_CLAUDE_ENV = "PIMP_TERM_CLAUDE"        # путь к «claude» (живая проверка — безвредная подмена)
TERM_TMUX_ENV = "PIMP_TERM_TMUX"            # путь к tmux; «none» — будто его нет (тесты)
TERM_OSASCRIPT_ENV = "PIMP_TERM_OSASCRIPT"  # путь к osascript (тесты)
TERM_PS_ENV = "PIMP_TERM_PS"                # путь к ps (тесты)
TERM_LSOF_ENV = "PIMP_TERM_LSOF"            # путь к lsof (тесты)
TTY_RE = re.compile(r"^/dev/tty[a-z0-9]+$")
CLAUDE_CODE_DIR = Path.home() / "Library" / "Application Support" / "Claude" / "claude-code"
TMUX_PLACES = ("/opt/homebrew/bin/tmux", "/usr/local/bin/tmux")
ITERM_PLACES = (Path("/Applications/iTerm.app"), Path.home() / "Applications" / "iTerm.app")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
# Вкладка жива, пока в ней идёт что-то кроме оболочки: в голую оболочку текст не печатаем —
# она его исполнит.
TERM_SHELLS = ("login", "sh", "-sh", "zsh", "-zsh", "bash", "-bash", "fish", "-fish")
# Многострочный текст — «вставкой» (bracketed paste): иначе каждая строка ушла бы Enter'ом.
PASTE_OPEN, PASTE_CLOSE = "\x1b[200~", "\x1b[201~"
# Файлы запуска старше часа (чужой сбой) — вон при следующем `term`.
TERM_STALE_S = 3600.0
# Чтение старых вкладок — только явно; зависший Terminal не держит список дольше 10 с.
TERM_TABS_TIMEOUT_S = 10.0

# Скрипты AppleScript постоянные: всё изменчивое приходит в `argv`.
# Открыть вкладку; ответ — её tty (по нему вкладку потом и находим).
OSA_OPEN_TERMINAL = """-- pimp:open-terminal
on run argv
  set dev to ""
  tell application "Terminal"
    set t to do script (item 1 of argv)
    -- Профиль «Пимп» (если он есть в Terminal) — заголовок без пути, процесса и размера окна.
    try
      set current settings of t to settings set "Пимп"
    end try
    set custom title of t to (item 2 of argv)
    set title displays custom title of t to true
    activate
    try
      set dev to tty of t
    end try
  end tell
  return dev
end run
"""
OSA_OPEN_ITERM = """-- pimp:open-iterm
on run argv
  tell application "iTerm"
    set w to (create window with default profile)
    tell current session of w
      set name to (item 2 of argv)
      write text (item 1 of argv)
    end tell
    activate
  end tell
  return "ok"
end run
"""
OSA_TITLE = """-- pimp:title
on run argv
  if application "Terminal" is not running then return "0"
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        if tty of t is (item 1 of argv) and (count of (processes of t)) > 0 then
          set custom title of t to (item 2 of argv)
          set title displays custom title of t to true
          return "1"
        end if
      end repeat
    end repeat
  end tell
  return "0"
end run
"""
# Строка на КАЖДУЮ вкладку Terminal (только чтение): tty, TAB, процессы через запятую, TAB,
# заголовок (последним — в нём может быть что угодно).
OSA_LIST = """-- pimp:list
on run argv
  if application "Terminal" is not running then return ""
  set sep to character id 9
  set out to {}
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        set AppleScript's text item delimiters to ","
        set end of out to (tty of t) & sep & ((processes of t) as text) & sep & (custom title of t)
      end repeat
    end repeat
  end tell
  set AppleScript's text item delimiters to linefeed
  return out as text
end run
"""
# item 1 — show | send, item 2 — tty вкладки, item 3 — текст, item 4 — имена оболочек строками.
# Совпал tty, но вкладка мертва (tty отдан новой) — ищем дальше.
OSA_ACT = """-- pimp:act
on run argv
  if application "Terminal" is not running then return "none"
  set shells to paragraphs of (item 4 of argv)
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        if tty of t is (item 2 of argv) then
          set live to false
          set procs to (processes of t)
          repeat with i from 1 to (count of procs)
            if shells does not contain (item i of procs) then set live to true
          end repeat
          if live then
            if (item 1 of argv) is "send" then
              do script (item 3 of argv) in t
              return "sent"
            end if
            set selected of t to true
            set index of w to 1
            activate
            return "shown"
          end if
        end if
      end repeat
    end repeat
  end tell
  return "none"
end run
"""
# Цвета вкладки (item 1 — tty): фон, текст, курсор — по три 16-битных числа (items 2–10).
# Ответ — сколько вкладок покрашено (0 или 1). У закрытой вкладки («[Процесс завершён]») tty
# остаётся прежним, а система отдаёт его новой — поэтому вкладку без процессов пропускаем.
OSA_COLOR = """-- pimp:color
on run argv
  if application "Terminal" is not running then return "0"
  set bg to {(item 2 of argv) as integer, (item 3 of argv) as integer, (item 4 of argv) as integer}
  set fg to {(item 5 of argv) as integer, (item 6 of argv) as integer, (item 7 of argv) as integer}
  set cur to {(item 8 of argv) as integer, (item 9 of argv) as integer, (item 10 of argv) as integer}
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        if tty of t is (item 1 of argv) and (count of (processes of t)) > 0 then
          set background color of t to bg
          set normal text color of t to fg
          set cursor color of t to cur
          return "1"
        end if
      end repeat
    end repeat
  end tell
  return "0"
end run
"""
# Запасные цвета палитры — как THEME_FALLBACK страницы (claude-patch/inject.js).
TERM_THEME_FALLBACK = {
    "dark": {"background": "#0b1020", "foreground": "#e5edff", "accent": "#60a5fa"},
    "light": {"background": "#ffffff", "foreground": "#111827", "accent": "#2563eb"},
}


class TermError(Exception):
    """Отказ терминальной команды: строка по-русски, код 1."""


def term_name(project: str) -> str:
    """«rick-<проект>»: tmux не любит «.» и «:» в имени — всё, кроме букв, цифр, «_» и «-», — «_»."""
    base = short_name(project)
    return TERM_PREFIX + "".join(ch if ch.isalnum() or ch in "_-" else "_" for ch in base)


def version_key(name: str):
    try:
        return tuple(int(part) for part in name.split("."))
    except ValueError:
        return None


def claude_binary() -> str:
    """`claude` приложения Claude — последней версии; PIMP_TERM_CLAUDE подменяет его."""
    forced = os.environ.get(TERM_CLAUDE_ENV, "").strip()
    if forced:
        path = Path(forced).expanduser()
        if not (path.is_file() and os.access(path, os.X_OK)):
            raise TermError(f"{TERM_CLAUDE_ENV} указывает не на исполняемый файл: {path}")
        return str(path)
    found = []
    try:
        for entry in CLAUDE_CODE_DIR.iterdir():
            key = version_key(entry.name)
            if key is None:
                continue
            # Обновлённый Claude кладёт программу на уровень глубже: <версия>/<хеш>/claude.app (02.10.2026).
            for binary in (entry / "claude.app" / "Contents" / "MacOS" / "claude",
                           *entry.glob("*/claude.app/Contents/MacOS/claude")):
                if binary.is_file() and os.access(binary, os.X_OK):
                    found.append((key, str(binary)))
    except OSError:
        pass
    if not found:
        raise TermError(f"Не нашёл claude в {CLAUDE_CODE_DIR} — открой Claude хоть раз, он его положит")
    return max(found)[1]


def term_settings_path() -> Path:
    """WF121: отдельный файл разрешений рядом с CLI; ошибка — отказ до запуска процесса.
    Проверяем форму, а семантику правил принимает штатный Claude Code на живом гейте."""
    path = Path(__file__).resolve().with_name("claude-term-settings.json")
    limit = 2 * 1024 * 1024

    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate key")
            result[key] = value
        return result

    try:
        if not path.is_file() or path.stat().st_size > limit:
            raise ValueError("not a regular settings file within 2 MiB")
        with path.open("rb") as file:
            raw = file.read(limit + 1)
        if len(raw) > limit:
            raise ValueError("settings exceed 2 MiB")
        data = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object)
        if not isinstance(data, dict) or set(data) != {"permissions"}:
            raise ValueError("expected permissions only")
        permissions = data["permissions"]
        if not isinstance(permissions, dict) or set(permissions) != {"allow", "ask", "deny"}:
            raise ValueError("expected allow/ask/deny")
        for key, rules in permissions.items():
            if not isinstance(rules, list) or (key != "allow" and not rules) \
                    or any(not isinstance(rule, str) or not rule.strip() for rule in rules):
                raise ValueError("expected nonempty permission strings")
    except (OSError, ValueError, UnicodeError, RecursionError):
        # Ни содержимое JSON, ни исключение парсера (в нём может быть input) в ответ не попадают.
        raise TermError(f"Файл разрешений {path} отсутствует или повреждён — новый чат не запущен") from None
    return path


def tmux_binary():
    forced = os.environ.get(TERM_TMUX_ENV)
    if forced is not None:
        forced = forced.strip()
        return None if forced in ("", "none") else forced
    found = shutil.which("tmux")
    if found:
        return found
    return next((place for place in TMUX_PLACES if os.access(place, os.X_OK)), None)


def osascript(script: str, *argv: str, timeout: float = 120.0) -> str:
    """AppleScript со stdin, данные — аргументами (никакой склейки строк)."""
    binary = os.environ.get(TERM_OSASCRIPT_ENV, "").strip() or "/usr/bin/osascript"
    try:
        # 120 с — как таймаут AppleEvent: под нагрузкой Terminal отвечает за минуту с лишним, а
        # убитый раньше osascript всё равно успевает открыть вкладку — уже без файла запуска.
        done = subprocess.run([binary, "-", *argv], input=script, capture_output=True,
                              text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise TermError(f"Terminal не ответил за {timeout:g} с") from None
    except OSError as error:
        raise TermError(f"osascript не отработал: {error}")
    if done.returncode != 0:
        err = done.stderr.strip()
        if "-1743" in err or "Not authorized" in err:
            raise TermError("Нет доступа к Terminal: разреши в «Системные настройки → "
                            "Конфиденциальность → Автоматизация» (Claude → Terminal)")
        raise TermError("AppleScript отказал: " + (err.splitlines()[-1] if err else f"код {done.returncode}"))
    return done.stdout.strip()


def tmux(*argv: str):
    binary = tmux_binary()
    try:
        return subprocess.run([binary, *argv], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise TermError(f"tmux не отработал: {error}")


def tmux_no_server(done) -> bool:
    """Только известный ответ об отсутствии сервера, не отказ доступа или чтения."""
    error = done.stderr.strip().lower()
    return done.returncode == 1 and bool(re.fullmatch(
        r"no server running(?: on [^\n]+)?|error connecting to [^\n]+ \(no such file or directory\)", error))


def tmux_sessions() -> dict:
    """{имя: подключён ли} — только наши «rick-…»; сервера нет — пусто."""
    if not tmux_binary():
        return {}
    done = tmux("list-sessions", "-F", "#{session_name}\t#{session_attached}")
    if done.returncode != 0:
        if tmux_no_server(done):
            return {}
        raise TermError("tmux не прочитал список сессий — реестр сохранён, ничего не запустил и не отправил")
    sessions = {}
    for line in done.stdout.splitlines():
        name, _, attached = line.partition("\t")
        if not name or not attached.isdigit():
            raise TermError("tmux вернул неполный список сессий — реестр сохранён")
        if name.startswith(TERM_PREFIX):
            sessions[name] = attached.strip() not in ("", "0")
    return sessions


def tmux_client_ttys(session: str) -> list:
    """tty вкладок, подключённых к сессии (по ним вкладку показывают и красят)."""
    if not tmux_binary():
        return []
    done = tmux("list-clients", "-t", "=" + session, "-F", "#{client_tty}")
    if done.returncode != 0:
        return []
    return [line.strip() for line in done.stdout.splitlines() if TTY_RE.match(line.strip())]


def terminal_tabs() -> list:
    """Все вкладки Terminal: [{tty, procs, title}]; Terminal не запущен — пусто (не запускаем)."""
    tabs = []
    for line in osascript(OSA_LIST, timeout=TERM_TABS_TIMEOUT_S).splitlines():
        tty, _, rest = line.partition("\t")
        processes, _, title = rest.partition("\t")
        if TTY_RE.match(tty.strip()):
            tabs.append({"tty": tty.strip(), "title": title.strip(),
                         "procs": [p.strip() for p in processes.split(",") if p.strip()]})
    return tabs


def term_tool(env: str, default: str, *argv: str, environ=None):
    """ps / lsof: CompletedProcess или None, если сам инструмент не запустился."""
    binary = os.environ.get(env, "").strip() or default
    try:
        return subprocess.run([binary, *argv], capture_output=True, text=True, timeout=15, env=environ)
    except (OSError, subprocess.TimeoutExpired):
        return None


def term_host_var(name: str) -> bool:
    """Метки чужого чата; CLAUDE_CONFIG_DIR и остальные настройки человека сохраняются."""
    return name == "CLAUDECODE" or name.startswith("CLAUDE_CODE_")


def tmux_drop_host_env() -> None:
    """Снять глобальные метки до создания новой сессии. Значения не выдаём в диагностику."""
    done = tmux("show-environment", "-g")
    if done.returncode != 0:
        if tmux_no_server(done):
            return
        raise TermError("tmux не прочитал окружение — новую сессию не запустил")
    for line in done.stdout.splitlines():
        name = line.removeprefix("-").partition("=")[0]
        if term_host_var(name) and tmux("set-environment", "-g", "-u", name).returncode != 0:
            raise TermError(f"tmux не снял {name} из своего окружения — сессию не завёл")


def tty_processes(tty: str):
    """[(pid, путь программы)] на этом tty; ps не отработал — None (записи тогда не трогаем)."""
    done = term_tool(TERM_PS_ENV, "/bin/ps", "-t", tty.replace("/dev/", "", 1), "-o", "pid=,comm=")
    if done is None:
        return None
    out = []
    for line in done.stdout.splitlines():
        pid, _, comm = line.strip().partition(" ")
        if pid.isdigit():
            out.append((int(pid), comm.strip()))
    return out


def process_cwd(pid: int) -> str:
    done = term_tool(TERM_LSOF_ENV, "/usr/sbin/lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn")
    if done is None or done.returncode != 0:
        return ""
    return next((line[1:] for line in done.stdout.splitlines() if line.startswith("n/")), "")


def term_records_dir() -> Path:
    return pimp_dir().parent / "term"


def term_record_path(session_name: str) -> Path:
    return term_records_dir() / (session_name[len(TERM_PREFIX):] + ".json")


def term_chats(prune: bool = True, with_terminal: bool = False, tab_errors=None) -> list:
    """Живые терминальные чаты: [{name, kind: tmux|terminal, tty?, attached?, record, folder}].
    Источники: реестр (мёртвые записи удаляются), tmux-сессии «rick-…», и вкладки Terminal
    с claude без записи — только при with_terminal, имя по папке claude (lsof cwd)."""
    sessions = tmux_sessions()
    tabs, tabs_failed = [], False
    try:
        if with_terminal:
            tabs = terminal_tabs()
    except TermError as error:
        tabs_failed = True
        if tab_errors is not None:
            tab_errors.append(str(error))
        elif prune:
            raise
    chats, names, ttys = [], set(), set()
    for path in sorted(term_records_dir().glob("*.json")) if term_records_dir().is_dir() else []:
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            record = None
        name = str(record.get("name") or "") if isinstance(record, dict) else ""
        session = str(record.get("tmux") or "") if isinstance(record, dict) else ""
        tty = str(record.get("tty") or "") if isinstance(record, dict) else ""
        pid = record.get("pid") if isinstance(record, dict) else None
        folder = str(record.get("folder") or "") if isinstance(record, dict) else ""
        if session:
            alive = session in sessions
            if alive:
                chats.append({"name": session, "kind": "tmux", "attached": sessions[session],
                              "record": True, "folder": folder, "cwd": record.get("cwd") or folder,
                              "project": record.get("project") or ""})
                names.add(session)
        else:
            procs = tty_processes(tty) if TTY_RE.match(tty) and isinstance(pid, int) else []
            if procs is None:
                continue  # ps сломан — не хороним то, чего не проверили
            alive = name.startswith(TERM_PREFIX) and any(p == pid for p, _ in procs)
            if alive:
                chats.append({"name": name, "kind": "terminal", "tty": tty, "record": True,
                              "folder": folder, "cwd": record.get("cwd") or folder,
                              "project": record.get("project") or ""})
                ttys.add(tty)
        if not alive and prune and not (tabs_failed and not session):
            try:
                path.unlink()
            except OSError:
                pass
    for session, attached in sessions.items():
        if session not in names:
            chats.append({"name": session, "kind": "tmux", "attached": attached, "record": False,
                          "folder": ""})
    for tab in tabs:
        if tab["tty"] in ttys or "claude" not in tab["procs"]:
            continue
        pids = [p for p, comm in tty_processes(tab["tty"]) or [] if comm.rsplit("/", 1)[-1] == "claude"]
        cwd = process_cwd(pids[0]) if pids else ""
        name = term_name(cwd) if cwd else tab["title"] if tab["title"].startswith(TERM_PREFIX) else ""
        if name:
            chats.append({"name": name, "kind": "terminal", "tty": tab["tty"], "record": False,
                          "folder": cwd})
    return chats


def term_chat_project(chat: dict):
    """Имя и папка для оформления/сводки; адрес сессии и поиск по tty не меняются."""
    name = chat.get("project") or chat["name"][len(TERM_PREFIX):]
    if chat.get("folder"):
        return name, chat["folder"]
    try:
        body = json.loads((pimp_dir().parent / "projects.json").read_text(encoding="utf-8"))
        for item in body.get("projects", []):
            if isinstance(item, dict) and term_name(str(item.get("name") or "")).lower() == chat["name"].lower():
                return item["name"], str(item.get("folder") or "")
    except (OSError, ValueError, AttributeError, TypeError):
        pass
    try:
        config = json.loads((pimp_dir().parent / "claude.json").read_text(encoding="utf-8"))
        root = Path(config.get("projectsRoot") or Path.home() / "Projects").expanduser()
    except (OSError, ValueError, AttributeError, TypeError):
        root = Path.home() / "Projects"
    return name, str(root / name)


def term_title(name: str, folder: str) -> str:
    for relative in ("docs/status.md", "audit/status.md"):
        try:
            with (Path(folder) / relative).open(encoding="utf-8") as handle:
                heading = plain(handle.readline(4096)).lstrip("# ")
        except (OSError, UnicodeError):
            continue
        match = re.match(r"([\u2300-\u27ff\U0001f000-\U0001faff\ufe0f\u200d]+)\s*(.+)", heading)
        if match:
            label = re.split(r"\s+[—–|·-]\s+", match[2], maxsplit=1)[0].strip()
            return match[1] + " " + label
    return name


# #9077 (слово Элвиса 08.10 через Рика): «что происходит во всех проектах, агрегируй… раздели на группы… проект
# такой-то, марафон, столько-то из стольких-то Workflow». Источник — status.md проектов (их ведут чаты и терминалы,
# формат — PanelProjects.parse приложения) и живые tmux-сессии «rick-…»; приложение и канал не нужны.
DIGEST_STALE_S = 24 * 3600
DIGEST_HEAD_RE = re.compile(r"^\S*\s*Workflow\b\s*(.*)$")
# WF145: одно правило состояний для всех разборщиков status.md (приложение — PanelProjects.stateMarks/stateWords,
# страница — statusParse): значок сильнее слова, порядок — по силе; ни значка, ни слова — «впереди».
DIGEST_MARKS = (("упал", ("🛑", "❌")), ("ждёт", ("✋", "⚠", "❓", "🙋", "⏸")), ("впереди", ("⬜",)),
                ("готово", ("✅", "🟢")), ("идёт", ("💭", "⏳")))
DIGEST_WORDS = (("упал", ("упал", "стоп", "сломал")), ("впереди", ("заплан", "впереди", "в очереди")),
                ("ждёт", ("ждёт", "жду", "пауз")), ("готово", ("готов", "выложен")),
                ("идёт", ("идёт", "кодинг", "критик", "проверк", "исследов", "планирован", "ревизи")))


def digest_state(heading: str) -> str:
    """Состояние Workflow по заголовку: идёт / ждёт (Элвиса) / впереди / готово / упал."""
    for state, marks in DIGEST_MARKS:
        if any(mark in heading for mark in marks):
            return state
    text = heading.lower()
    for state, words in DIGEST_WORDS:
        if any(word in text for word in words):
            return state
    return "впереди"


def digest_root() -> Path:
    try:
        config = json.loads((pimp_dir().parent / "claude.json").read_text(encoding="utf-8"))
        return Path(config.get("projectsRoot") or Path.home() / "Projects").expanduser()
    except (OSError, ValueError, AttributeError, TypeError):
        return Path.home() / "Projects"


def digest_parse(text: str) -> dict:
    """Шапка, итоги и блоки Workflow одного status.md."""
    out = {"title": "", "summary": [], "workflows": [], "now": "", "wait": ""}
    block = None
    for raw in text.splitlines():
        line = raw.strip()
        if not out["title"] and line.startswith("# "):
            out["title"] = line[2:].strip()
            continue
        head = DIGEST_HEAD_RE.match(line)
        if head and not line.startswith(("-", "*")):
            block = {"state": digest_state(line), "about": "", "steps": ""}
            out["workflows"].append(block)
            continue
        if line.startswith("Сейчас:"):
            out["now"] = line[len("Сейчас:"):].strip()
            continue
        if line.startswith(("Ждёт Элвиса:", "Ждёт пользователя:")):
            out["wait"] = line.split(":", 1)[1].strip()
            continue
        if block is None:
            if line and not line.startswith(("обновлено", "#")):
                out["summary"].append(line)
            continue
        item = line[2:].strip() if line.startswith(("- ", "* ")) else ""
        if item.startswith("о чём:"):
            block["about"] = item[len("о чём:"):].strip()
        elif re.match(r"шаги \d+ из \d+", item):
            block["steps"] = "/".join(re.findall(r"\d+", item)[:2])
    return out


def digest_collect(root: Path, sessions: dict, now: float) -> list:
    items = []
    for folder in sorted(root.iterdir() if root.is_dir() else [], key=lambda p: p.name.lower()):
        # Рабочее дерево git (.git — файл) — копия проекта для параллельного прогона, не проект: как isWorktree панели.
        if not folder.is_dir() or folder.name.startswith(".") or (folder / ".git").is_file():
            continue
        status = next((folder / rel for rel in ("docs/status.md", "audit/status.md") if (folder / rel).is_file()), None)
        term = TERM_PREFIX + folder.name
        if status is None and term not in sessions:
            continue
        parsed = digest_parse(status.read_text(encoding="utf-8", errors="replace")) if status else digest_parse("")
        flows = parsed["workflows"]
        stale = bool(status) and now - status.stat().st_mtime > DIGEST_STALE_S
        running = [i for i, flow in enumerate(flows, 1) if flow["state"] == "идёт"]
        # «ждут» — строка «Ждёт Элвиса» или Workflow, что ждёт его (как ProjectsDigest); «впереди» — не ждёт.
        waits = (bool(parsed["wait"]) and not nothing_said(parsed["wait"])) or any(
            flow["state"] == "ждёт" for flow in flows)
        group = "идут" if running and not stale else "ждут" if waits else "тихо"
        items.append({"project": folder.name, "title": parsed["title"] or folder.name, "group": group,
                      "workflows": len(flows), "done": sum(flow["state"] == "готово" for flow in flows),
                      "running": [{"n": i, "about": flows[i - 1]["about"], "steps": flows[i - 1]["steps"]}
                                  for i in running],
                      "summary": parsed["summary"][:3], "now": parsed["now"], "wait": parsed["wait"],
                      "stale": stale, "terminal": term in sessions})
    return items


def nothing_said(text: str) -> bool:
    return text.strip().strip(".").lower() in ("", "ничего", "нет", "—", "-")


def digest_text(items: list) -> str:
    if not items:
        return "Сводок проектов нет"
    lines = []
    for group, label in (("идут", "⏳ Идут"), ("ждут", "✋ Ждут Элвиса"), ("тихо", "· Тихо")):
        part = [item for item in items if item["group"] == group]
        if not part:
            continue
        if group == "тихо":
            lines.append(f"{label}: " + ", ".join(item["title"] for item in part))
            continue
        lines.append(f"{label} — {len(part)}")
        for item in part:
            head = f"  {item['title']} · Workflow {item['done']} из {item['workflows']} готово"
            if item["summary"]:
                marathon = next((text for text in item["summary"] if "марафон" in text.lower()), "")
                if marathon:
                    head += f" · {marathon}"
            if item["terminal"]:
                head += " · терминал"
            if item["stale"]:
                head += " · сводка старше суток"
            lines.append(head)
            for flow in item["running"]:
                steps = f" (шаги {flow['steps'].replace('/', ' из ')})" if flow["steps"] else ""
                lines.append(f"    {flow['n']}-й идёт{steps}: {clip(flow["about"], 90)}")
            tail = item["now"] if group == "идут" else item["wait"]
            if tail:
                lines.append(f"    {'Сейчас' if group == 'идут' else 'Ждёт'}: {clip(tail, 110)}")
    return "\n".join(lines)


def run_digest(as_json: bool) -> int:
    try:
        sessions = tmux_sessions()
    except TermError:
        sessions = {}
    items = digest_collect(digest_root(), sessions, time.time())
    print(json.dumps(items, ensure_ascii=False, indent=2) if as_json else digest_text(items))
    return 0


def term_set_title(chat: dict, title: str, tabs: bool = True) -> None:
    if chat["kind"] == "tmux":
        target = "=" + chat["name"]
        # Опции сессии, без -g: соседние сессии сохраняют свои заголовки.
        # В формате tmux буквальный # экранируется как ##.
        # set-option разбирает target-window: двоеточие сохраняет точное имя сессии (=).
        commands = [("set-option", "-t", target + ":", "set-titles", "on"),
                    ("set-option", "-t", target + ":", "set-titles-string", title.replace("#", "##"))]
        windows = tmux("list-windows", "-t", target, "-F", "#{window_id}")
        if windows.returncode != 0:
            raise TermError(f"Не прочитал окна tmux {chat['name']} для заголовка")
        for window in windows.stdout.splitlines():
            for option in ("allow-rename", "automatic-rename"):
                commands.append(("set-option", "-w", "-t", window, option, "off"))
        for command in commands:
            if tmux(*command).returncode != 0:
                raise TermError(f"Не закрепил заголовок tmux {chat['name']}")
    elif tabs:
        osascript(OSA_TITLE, chat["tty"], title)


def term_summary(chat: dict) -> dict:
    name, folder = term_chat_project(chat)
    card = {"name": chat["name"], "kind": chat["kind"], "project": name,
            "contextTokens": None, "activityMinutes": None}
    # Claude Code кодирует каждый не-ASCII-alnum знак пути дефисом, включая подчёркивания.
    encoded = re.sub(r"[^a-zA-Z0-9]", "-", str(chat.get("cwd") or folder))
    directory = env_dir(TRANSCRIPTS_ENV, DEFAULT_TRANSCRIPTS) / encoded
    candidates = []
    for path in directory.glob("*.jsonl"):
        try:
            candidates.append((path.stat().st_mtime, path.name, path))
        except OSError:
            continue
    if not candidates:
        return card
    modified, _, newest = max(candidates)
    try:
        with newest.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - 3_000_000))
            lines = handle.read(3_000_000).splitlines()
        if size > 3_000_000:
            lines = lines[1:]
        card["activityMinutes"] = max(0, int((time.time() - modified) / 60))
        for line in reversed(lines):
            try:
                record = json.loads(line)
            except (ValueError, UnicodeError):
                continue
            if not isinstance(record, dict) or record.get("type") != "assistant" or record.get("isSidechain"):
                continue
            message = record.get("message")
            usage = message.get("usage") if isinstance(message, dict) else None
            if not isinstance(usage, dict) or not usage:
                continue
            tokens = [usage.get(key, 0) for key in
                      ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")]
            if all(type(value) is int and value >= 0 for value in tokens):
                card["contextTokens"] = sum(tokens)
            break
    except OSError:
        pass
    return card


def term_payload(text: str) -> str:
    """Текст для поля claude: управляющие знаки вон (ни Esc, ни Ctrl+C из текста не пройдут),
    \\r\\n → \\n; многострочный или с табом — вставкой, Enter добавит отправитель."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = "".join(ch for ch in text if ch in "\n\t" or not (ord(ch) < 32 or ord(ch) == 127))
    text = text.strip()
    if "\n" in text or "\t" in text:
        return PASTE_OPEN + text + PASTE_CLOSE
    return text


def term_text(raw) -> str:
    """--text / аргумент: «-» — stdin; пустой — None для term, отказ для term-send решает зовущий."""
    if raw is None:
        return None
    text = sys.stdin.read() if raw == "-" else raw
    if "\0" in text:
        raise TermError("В тексте нулевой символ — ничего не сделал")
    text = text.strip()
    if len(text) > TERM_TEXT_LIMIT:
        raise TermError(f"Текст длиннее {TERM_TEXT_LIMIT} знаков — сократи")
    return text or None


def term_projects() -> list:
    """Проекты — как у `open`: список приложения (`projects` каналом); Пимп молчит — его
    файл projects.json. [(имя, папка)]."""
    request = {"id": new_id(), "at": now_iso(), "action": "projects", "from": from_chat()}
    kind, data, _ = send(request)
    items = data.get("projects") if kind == "ok" and data.get("ok") else None
    if not isinstance(items, list):
        try:
            body = json.loads((pimp_dir().parent / "projects.json").read_text(encoding="utf-8"))
            items = body.get("projects") if isinstance(body, dict) else None
        except (OSError, ValueError):
            items = None
    return [(str(item.get("name") or "").strip(), str(item.get("folder") or "").strip())
            for item in (items or []) if isinstance(item, dict)
            and str(item.get("name") or "").strip() and str(item.get("folder") or "").strip()]


def term_project(raw: str):
    """(имя, папка): путь — как есть, иначе имя из списка, сперва точно, потом без регистра
    (как PimpChannel.project). Наугад не открываем."""
    wanted = (raw or "").strip()
    if not wanted:
        raise TermError("Проект не назван — ничего не открыл")
    if wanted.startswith(("/", "~")):
        folder = Path(wanted).expanduser().resolve()
        if not folder.is_dir():
            raise TermError(f"Папки {folder} нет — ничего не открыл")
        return folder.name, str(folder)
    projects = term_projects()
    hit = next((p for p in projects if p[0] == wanted), None) \
        or next((p for p in projects if p[0].lower() == wanted.lower()), None)
    if hit is None:
        names = ", ".join(name for name, _ in projects[:30]) or "список пуст"
        raise TermError(f"Проекта «{wanted}» не знаю — есть: {names}")
    if not Path(hit[1]).is_dir():
        raise TermError(f"Папки {hit[1]} нет — ничего не открыл")
    return hit


def term_launcher(folder: str, claude: str, args: list, reply: str, record: dict) -> Path:
    """Файл запуска (0700): cd, чистое окружение, запись в реестр, exec claude. Удаляет себя
    первой строкой — в нём может лежать начальный текст. Запись реестра — JSON, собранный
    здесь; оболочка вставляет только tty (проверенный шаблоном) и $$ (он же pid claude после
    exec). Пишется во временный файл с umask 077 и переносится mv — атомарно, 0600."""
    directory = term_records_dir()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    now = time.time()
    for old in directory.glob("*.sh"):
        try:
            if now - old.stat().st_mtime > TERM_STALE_S:
                old.unlink()
        except OSError:
            pass
    lines = ["#!/bin/sh", "# pimp.py term: запуск терминального чата; файл удаляет себя сам",
             'rm -f -- "$0"',
             # tmux-сервер мог родиться в чате Claude — его метки внутреннему claude не нужны.
             # Проверяем имена уже в новом процессе: Terminal/tmux могли добавить свои метки.
             "for name in $(env | sed -En 's/^(CLAUDECODE|CLAUDE_CODE_[A-Za-z0-9_]*)=.*/\\1/p'); do",
             '  unset "$name"',
             "done",
             "export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1"]
    if reply:
        lines.append("export PIMP_REPLY_CHAT=" + shlex.quote(reply))
    lines.append("cd -- " + shlex.quote(folder) + " || exit 1")
    head = json.dumps(record, ensure_ascii=False)[:-1] + ', "tty": "'
    target = term_record_path(record["name"])
    lines += ["t=$(tty 2>/dev/null) || t=''",
              "case \"$t\" in /dev/tty*) ;; *) t='' ;; esac",
              "case \"$t\" in *[!a-z0-9/]*) t='' ;; esac",
              "f=" + shlex.quote(str(target)),
              "( umask 077 && printf '%s%s%s%s%s' " + shlex.quote(head) + " \"$t\" "
              + shlex.quote('", "pid": ') + " \"$$\" '}' > \"$f.$$\" && mv -f \"$f.$$\" \"$f\" ) 2>/dev/null"]
    lines.append("exec " + " ".join(shlex.quote(part) for part in [claude, *args]))
    path = directory / f"launch-{new_id()}.sh"
    handle = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o700)
    with os.fdopen(handle, "w", encoding="utf-8") as file:
        file.write("\n".join(lines) + "\n")
    return path


def term_find(project: str) -> dict:
    """Какой терминальный чат зовут (сверка без регистра); tmux-сессия сильнее вкладки."""
    raw = project.strip()
    named = term_name(raw[len(TERM_PREFIX):] if raw.lower().startswith(TERM_PREFIX) else raw)
    # Сначала только tmux/реестр: живой tmux не зависит от AppleEvents.
    hits = [chat for chat in term_chats() if chat["name"].lower() == named.lower() and chat["kind"] == "tmux"]
    if len(hits) > 1:
        raise TermError(f"Сессий {named} несколько — уточни имя, я ничего не отправил")
    if hits:
        return hits[0]
    # Без tmux ищем и незарегистрированные вкладки; отказ Terminal не значит «чата нет».
    hits = [chat for chat in term_chats(with_terminal=True) if chat["name"].lower() == named.lower()]
    if len(hits) > 1:
        raise TermError(f"Вкладок {named} несколько — закрой лишнюю, я ничего не отправил")
    if hits:
        return hits[0]
    raise TermError(f"Терминального чата {named} нет — открой: pimp.py term {raw}")


def term_tab_ttys(chat: dict) -> list:
    """tty вкладок Terminal этого чата: своя у вкладки, у tmux — подключённые клиенты."""
    return [chat["tty"]] if chat["kind"] == "terminal" else tmux_client_ttys(chat["name"])


def term_deliver(chat: dict, text: str) -> None:
    payload = term_payload(text)
    if not payload:
        raise TermError("Текст пустой — ничего не отправил")
    if chat["kind"] == "tmux":
        target = f"={chat['name']}:"
        done = tmux("send-keys", "-t", target, "-l", "--", payload)
        if done.returncode == 0:
            done = tmux("send-keys", "-t", target, "Enter")
        if done.returncode != 0:
            raise TermError(f"tmux не принял текст: {done.stderr.strip() or done.returncode}")
        return
    # Terminal сам добавляет Enter (\r) после текста — проверено на живой вкладке.
    if osascript(OSA_ACT, "send", chat["tty"], payload, "\n".join(TERM_SHELLS)) != "sent":
        raise TermError(f"Вкладка {chat['name']} закрылась или в ней уже не claude — ничего не отправил")


# ---- цвет вкладки = цвет окна проекта --------------------------------------------
# Окну проекта Пимп ставит (ProjectPaint.wanted): вид из <папка>/.pimpmyclaude.json (нет файла —
# запасной реестр project-views.json); вида нет вовсе — авто-цвет по имени папки
# (AutoPaint.projectTheme); тумблер «🗂 Цвет по проекту» выключен или "theme": null — цвета нет.
# Страница красит окно палитрой: фон = background, текст = foreground, акцент (курсор) = accent.
PIMP_BUNDLE_ID = "com.elvis.pimpmyclaude"
PROJECT_PAINT_KEY = "projectPaintEnabled"   # ProjectPaint.enabledKey
TERM_VIEW_KEYS = ("theme", "font", "size", "frame", "look")


def term_hex(value, fallback: str) -> str:
    """#rrggbb как normalizeHex страницы: #rgb/#rgba/#rrggbbaa → 6 знаков, мусор — запасной."""
    source = value.strip() if isinstance(value, str) else fallback
    if not re.fullmatch(r"#[0-9a-fA-F]{3,8}", source):
        source = fallback
    digits = source[1:]
    if len(digits) not in (3, 4, 6, 8):
        digits = fallback[1:]
    if len(digits) in (3, 4):
        digits = "".join(ch * 2 for ch in digits)
    return "#" + digits[:6].lower()


def project_paint_enabled() -> bool:
    """Тумблер «🗂 Цвет по проекту» из настроек приложения; нет ключа — включён (как в Swift)."""
    try:
        with open(Path.home() / "Library" / "Preferences" / f"{PIMP_BUNDLE_ID}.plist", "rb") as file:
            value = plistlib.load(file).get(PROJECT_PAINT_KEY)
    except Exception:  # нет файла, битый plist — умолчание
        return True
    return not (isinstance(value, (bool, int)) and not value)


def project_view(folder: str):
    """Вид проекта как ProjectSettingsStore.settings(in:): файл в папке сильнее; он есть, но это
    не JSON-объект — вида нет. Файла нет — запасной реестр (старое имя — если там объект)."""
    path = Path(folder) / ".pimpmyclaude.json"
    if path.exists():
        try:
            body = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        return body if isinstance(body, dict) else None
    for name in ("project-views.json", "projects.json"):
        try:
            root = json.loads((pimp_dir().parent / name).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        items = root.get("projects") if isinstance(root, dict) else None
        if isinstance(items, dict) and items:
            item = items.get(os.path.normpath(folder))
            return item if isinstance(item, dict) else None
    return None


def view_palette(theme):
    """Палитра темы как ProjectSettings.theme: объект, палитра — непустая, все значения строки."""
    palette = theme.get("palette") if isinstance(theme, dict) else None
    if isinstance(palette, dict) and palette and all(isinstance(v, str) for v in palette.values()):
        return palette
    return None


def view_given(view: dict, key: str) -> bool:
    """Слой задан (поставить или снять), а не «не трогать»: мусор равен отсутствию ключа."""
    if key not in view:
        return False
    value = view[key]
    if value is None or key == "frame":
        return True
    return view_palette(value) is not None if key == "theme" else isinstance(value, dict)


def auto_hue(name: str) -> int:
    """AutoPaint.hue(forName:): FNV-1a 64 над name.lowercased() в UTF-8, остаток от 360."""
    value = 14_695_981_039_346_656_037
    for byte in name.lower().encode("utf-8"):
        value = ((value ^ byte) * 1_099_511_628_211) & 0xFFFFFFFFFFFFFFFF
    return value % 360


def hsl_rgb(hue: float, saturation: float, lightness: float) -> tuple:
    """HSL.channels из AutoPaint.swift: каналы 0–255, округление от нуля."""
    h = (hue % 360) / 360
    s = min(max(saturation, 0), 100) / 100
    light = min(max(lightness, 0), 100) / 100
    if s <= 0:
        gray = math.floor(light * 255 + 0.5)
        return gray, gray, gray
    q = light * (1 + s) if light < 0.5 else light + s - light * s
    p = 2 * light - q

    def channel(t: float) -> int:
        t = t + 1 if t < 0 else t - 1 if t > 1 else t
        if t < 1 / 6:
            v = p + (q - p) * 6 * t
        elif t < 1 / 2:
            v = q
        elif t < 2 / 3:
            v = p + (q - p) * (2 / 3 - t) * 6
        else:
            v = p
        return math.floor(v * 255 + 0.5)
    return channel(h + 1 / 3), channel(h), channel(h - 1 / 3)


def rgb_luminance(rgb: tuple) -> float:
    def part(value: int) -> float:
        c = value / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * part(rgb[0]) + 0.7152 * part(rgb[1]) + 0.0722 * part(rgb[2])


def hsl_contrast(a: list, b: list) -> float:
    first, second = rgb_luminance(hsl_rgb(*a)), rgb_luminance(hsl_rgb(*b))
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)


def hsl_pulled(color: list, target: float, background: list) -> list:
    """AutoPaint.pulled: светлота шагом 1 %, пока контраст не дотянет до цели."""
    color = list(color)
    up = rgb_luminance(hsl_rgb(*background)) < 0.5
    for _ in range(100):
        if hsl_contrast(color, background) >= target:
            break
        step = color[2] + (1 if up else -1)
        if not 0 <= step <= 100:
            break
        color[2] = step
    return color


def auto_palette(hue: int) -> dict:
    """AutoPaint.palette(hue:light:false) при силе 0,5 — тёмная тема проекта без файла."""
    background = [hue, min(60, 45 + 15 * 0.5), 16 - 4 * 0.5]
    for _ in range(100):  # capped: насыщенность фона по hex не выше 60 %
        r, g, b = (c / 255 for c in hsl_rgb(*background))
        high, low = max(r, g, b), min(r, g, b)
        sat = 0 if high == low else (high - low) / (1 - abs(high + low - 1)) * 100
        if sat <= 60 or background[1] <= 0:
            break
        background[1] = max(0, background[1] - 0.5)
    foreground = hsl_pulled([hue, 25, 92], 7, background)
    aim = (4.5 + 6) / 2  # banded: акцент в середину полосы 4,5…6
    accent = hsl_pulled([hue, 70 + 20 * 0.5, 62], aim, background)
    back = -1 if rgb_luminance(hsl_rgb(*background)) < 0.5 else 1
    for _ in range(100):
        if hsl_contrast(accent, background) <= aim:
            break
        step = [accent[0], accent[1], accent[2] + back]
        if not 0 <= step[2] <= 100 or hsl_contrast(step, background) < 4.5:
            break
        accent = step
    return {key: "#%02x%02x%02x" % hsl_rgb(*color)
            for key, color in (("background", background), ("foreground", foreground), ("accent", accent))}


def term_theme(folder: str):
    """{background, foreground, accent, name} — те цвета, что Пимп ставит окну проекта; нет — None."""
    if not project_paint_enabled():
        return None
    view = project_view(folder)
    if view is None or not any(view_given(view, key) for key in TERM_VIEW_KEYS):
        name = Path(folder).name
        hue = auto_hue(name)
        return dict(auto_palette(hue), name=f"{name} · {hue}°")
    theme = view.get("theme")
    palette = view_palette(theme)
    if palette is None:
        return None
    base = TERM_THEME_FALLBACK["light" if theme.get("type") == "light" else "dark"]
    colors = {key: term_hex(palette.get(key), base[key]) for key in base}
    colors["name"] = str(theme.get("name") or theme.get("id") or "Тема")
    return colors


def term_rgb16(hex_color: str) -> list:
    return [str(int(hex_color[i:i + 2], 16) * 257) for i in (1, 3, 5)]


def term_paint(tty: str, theme: dict) -> bool:
    """Покрасить вкладку Terminal с этим tty; покрасил ли."""
    argv = [tty] + term_rgb16(theme["background"]) + term_rgb16(theme["foreground"]) \
        + term_rgb16(theme["accent"])
    return osascript(OSA_COLOR, *argv) == "1"


def term_paint_note(ttys: list, folder: str) -> str:
    """Для term: покраска не должна ронять открытие — хвост строки или пусто."""
    theme = term_theme(folder) if ttys else None
    if theme is None:
        return ""
    try:
        painted = [tty for tty in ttys if term_paint(tty, theme)]
    except TermError as error:
        return f"; цвет не поставил: {error}"
    return f", цвета темы «{theme['name']}»" if painted else ""


def run_term_color(args) -> int:
    chat = term_find(args.project)
    raw = args.project.strip()
    folder = chat.get("folder") or term_project(
        raw[len(TERM_PREFIX):] if raw.lower().startswith(TERM_PREFIX) else raw)[1]
    theme = term_theme(folder)
    if theme is None:
        print(f"У проекта {Path(folder).name} цвета окна нет — вкладку {chat['name']} не крашу")
        return 0
    ttys = term_tab_ttys(chat)
    if not ttys or not [tty for tty in ttys if term_paint(tty, theme)]:
        raise TermError(f"Вкладки {chat['name']} в Terminal нет — красить нечего")
    print(f"Покрасил {chat['name']} в тему «{theme['name']}»")
    return 0


def run_term(args) -> int:
    text = term_text(args.text)
    effort = args.effort
    resume, note = None, ""
    if args.resume is not None:
        resume = args.resume.strip().lower()
        if not UUID_RE.match(resume):
            raise TermError("--resume — это cliSessionId вида 9378c07b-…-…; ничего не открыл")
    claude = claude_binary()
    name, folder = term_project(args.project)
    theme_folder = folder  # цвет — по проекту, даже если чат живёт в другой папке
    title = term_title(name, theme_folder)
    if args.from_chat is not None:
        chat = args.from_chat.strip()
        if not CHAT_RE.match(chat):
            raise TermError("--from-chat — это local_… чата; ничего не открыл")
        session = next(session_files(chat), None)
        if session is None:
            raise TermError(f"Чата {chat} в файлах Claude нет — ничего не открыл")
        resume = str(session.get("cliSessionId") or "").strip()
        if not UUID_RE.match(resume):
            raise TermError(f"У чата {chat} нет cliSessionId — продолжить в терминале нечего")
        # Продолжение ищется по папке чата: в другой claude его не найдёт.
        cwd = str(session.get("cwd") or "").strip()
        if cwd and cwd != folder and Path(cwd).is_dir():
            folder = cwd
        title = str(session.get("title") or "").strip() or chat
        note = f"; чат «{title}» закрой в окне Claude — один чат двумя хозяевами не держат"
    elif resume or args.last:
        note = "; этот чат не держи открытым в окне Claude"
    session_name = term_name(name)
    tmux_bin = tmux_binary()
    if args.app == "iterm":
        if not any(place.is_dir() for place in ITERM_PLACES):
            raise TermError("iTerm2 не установлен — открой без --app iterm (Terminal)")
        if not tmux_bin:
            raise TermError("iTerm2 — только с tmux (brew install tmux): вкладку без него я не найду")

    # Уже открыт — показать, второй не заводить. Ищем по реестру/tty, не по заголовку.
    hits = [chat for chat in term_chats(with_terminal=not bool(tmux_bin))
            if chat["name"].lower() == session_name.lower()]
    if len([chat for chat in hits if chat["kind"] == "tmux"]) > 1 or \
            (len(hits) > 1 and all(chat["kind"] != "tmux" for chat in hits)):
        raise TermError(f"Чатов {session_name} несколько — ничего не запустил и не отправил")
    existing = next((chat for chat in hits if chat["kind"] == "tmux"), None) or (hits[0] if hits else None)
    if existing:
        term_set_title(existing, title)
    # Слово Элвиса 01.10 ~02:20: окна терминалов не нужны («вертикальный монитор нужен для HTML») —
    # с tmux чат живёт фоном, окно — только по --show.
    background = bool(tmux_bin) and not args.show
    if existing and background and existing["kind"] == "tmux":
        line = f"Терминальный чат {existing['name']} уже идёт фоном (tmux; окно — term {name} --show)"
        if text:
            term_deliver(existing, text)
            line += ", текст отправил"
        if resume or args.last:
            print(line + "; другой чат не открыл — сперва закрой этот терминал")
            return 1
        print(line)
        return 0
    if existing:
        ttys = term_tab_ttys(existing) if args.app == "terminal" else []
        shells = "\n".join(TERM_SHELLS)
        shown = next((tty for tty in ttys if osascript(OSA_ACT, "show", tty, "", shells) == "shown"), None)
        if existing["kind"] == "tmux" and not shown and not existing.get("attached"):
            # «=имя» — в кавычках: shlex.quote «=» не кавычит, а zsh (EQUALS) раскрыл бы голое =слово в путь
            # команды — «zsh: rick-… not found». Имя из term_name — только буквы, цифры, «_» и «-».
            attach = f"exec {shlex.quote(tmux_bin)} attach -t '={existing['name']}'"
            dev = osascript(OSA_OPEN_ITERM if args.app == "iterm" else OSA_OPEN_TERMINAL,
                            attach, title)
            if args.app == "terminal" and TTY_RE.match(dev):
                ttys.append(dev)
        line = f"Терминал {existing['name']} уже открыт — показал"
        if args.app == "terminal":
            line += term_paint_note(ttys, theme_folder)
        if text:
            term_deliver(existing, text)
            line += ", текст отправил"
        if resume or args.last:
            print(line + "; другой чат не открыл — сперва закрой этот терминал")
            return 1
        print(line)
        return 0

    settings = term_settings_path()
    claude_args = ["--model", TERM_MODEL, "--effort", effort, "--permission-mode", TERM_PERMISSION,
                   "--settings", str(settings)]
    if resume:
        claude_args += ["--resume", resume]
    elif args.last:
        claude_args.append("--continue")
    if text:
        claude_args += ["--", text]
    reply = from_chat() if CHAT_RE.match(from_chat()) else ""
    record = {"v": 1, "name": session_name, "project": name, "folder": theme_folder, "cwd": folder,
              "tmux": session_name if tmux_bin else "", "at": now_iso()}
    if tmux_bin:
        tmux_drop_host_env()
    launcher = term_launcher(folder, claude, claude_args, reply, record)
    what = " — продолжает чат" if resume else " — последний чат папки" if args.last else ""
    if tmux_bin:
        clean = {key: value for key, value in os.environ.items() if not term_host_var(key)}
        done = term_tool(TERM_TMUX_ENV, tmux_bin, "new-session", "-d", "-s", session_name, "-c", folder,
                         "/bin/sh", str(launcher), environ=clean)
        if done is None or done.returncode != 0:
            try:
                launcher.unlink()
            except OSError:
                pass
            raise TermError(f"tmux не завёл сессию {session_name}: {(done.stderr if done else '').strip()[:200]}")
        term_set_title({"name": session_name, "kind": "tmux"}, title)
    if background:
        print(f"Открыл терминальный чат {session_name} фоном в tmux, без окна ({folder}){what}{note}; "
              f"окно — term {name} --show")
        return 0
    if tmux_bin:
        command = f"{shlex.quote(tmux_bin)} attach -t '={session_name}'"
        how = "tmux"
    else:
        command = "/bin/sh " + shlex.quote(str(launcher))
        how = "Terminal без tmux"
    try:
        dev = osascript(OSA_OPEN_ITERM if args.app == "iterm" else OSA_OPEN_TERMINAL,
                        "exec " + command, title)
    except TermError:
        try:
            launcher.unlink()
        except OSError:
            pass
        raise
    paint = term_paint_note([dev] if args.app == "terminal" and TTY_RE.match(dev) else [], theme_folder)
    print(f"Открыл терминальный чат {session_name} в {folder} ({how}){what}{paint}{note}")
    return 0


def run_term_send(args) -> int:
    text = term_text(args.text)
    if not text:
        raise TermError("Текст пустой — ничего не отправил")
    chat = term_find(args.project)
    term_deliver(chat, text)
    print(f"Отправил в терминал {chat['name']}")
    return 0


def run_term_list(as_json: bool, with_terminal: bool = False) -> int:
    problems = []
    chats = sorted(term_chats(with_terminal=with_terminal, tab_errors=problems),
                   key=lambda chat: (chat["kind"] != "tmux", chat["name"]))
    if problems:
        print(f"Вкладки Terminal не прочитал: {problems[0]}", file=sys.stderr)
    items = []
    for chat in chats:
        name, folder = term_chat_project(chat)
        title = term_title(name, folder)
        term_set_title(chat, title, tabs=with_terminal and not problems)
        item = {"name": chat["name"], "kind": chat["kind"], "record": chat["record"]}
        item.update({"attached": chat["attached"]} if chat["kind"] == "tmux" else {"tty": chat["tty"]})
        items.append(item)
    if as_json:
        print(json.dumps(items, ensure_ascii=False))
        return 0
    if not items:
        print("Терминальных чатов в tmux и реестре нет" if problems else "Терминальных чатов нет")
        return 0
    words = []
    for item in items:
        if item["kind"] == "tmux":
            words.append(f"{item['name']} (tmux{', подключён' if item['attached'] else ', без вкладки'})")
        else:
            words.append(f"{item['name']} (Terminal{'' if item['record'] else ', без записи'})")
    print("Терминальные чаты: " + ", ".join(words))
    return 0


def run_term_command(args) -> int:
    try:
        if args.command == "term":
            return run_term(args)
        if args.command == "term-send":
            return run_term_send(args)
        if args.command == "term-color":
            return run_term_color(args)
        return run_term_list(getattr(args, "as_json", False), args.with_terminal)
    except TermError as error:
        print(str(error), file=sys.stderr if getattr(args, "as_json", False) else sys.stdout)
        return 1


# ---- запросы команды на GitHub (WF120, #8030, К-B4): только чтение -----------------
GH_PLACES = ("/opt/homebrew/bin/gh", "/usr/local/bin/gh")
GH_TIMEOUT_S = 60.0
PR_LIMIT = 50
GH_LOGIN_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*")
PR_REPO_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+")
PR_FIELDS = ("number title url createdAt isDraft state baseRefName headRefName headRefOid mergeable "
             "repository { nameWithOwner } author { login } "
             "commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }")
PR_SEARCH = ("query($q: String!, $cursor: String) { search(query: $q, type: ISSUE, first: %d, "
             "after: $cursor) { issueCount pageInfo { hasNextPage endCursor } "
             "nodes { ... on PullRequest { %s } } } }" % (PR_LIMIT, PR_FIELDS))
PR_CHECKS = {"SUCCESS": "проверки зелёные", "FAILURE": "проверки красные", "ERROR": "проверки красные",
             "PENDING": "проверки идут", "EXPECTED": "проверки идут", None: "проверок нет"}
GH_WORDS = {"no-gh": "нет gh — поставь GitHub CLI", "auth": "gh не вошёл — gh auth login",
            "network": "сеть не отвечает"}
GH_SIGNS = (
    ("auth", ("gh auth login", "not logged in", "bad credentials", "http 401")),
    ("network", ("error connecting to", "could not resolve host", "no such host", "dial tcp",
                 "i/o timeout", "connection refused", "network is unreachable", "tls handshake timeout")),
)


class PrError(Exception):
    """Отказ чтения prs: строка по-русски, код 1; --json пишет ошибку в stderr."""


def gh(*argv: str) -> str:
    """Чтение gh без оболочки; timeout включает чтение потоков и выход процесса."""
    binary = shutil.which("gh") or next((place for place in GH_PLACES if os.access(place, os.X_OK)), None)
    if not binary:
        raise PrError(GH_WORDS["no-gh"])
    try:
        done = subprocess.run([binary, *argv], stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, timeout=GH_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        raise PrError(GH_WORDS["network"]) from None
    except OSError:
        raise PrError(GH_WORDS["no-gh"]) from None
    if done.returncode == 0:
        return done.stdout
    if done.returncode == 4:
        raise PrError(GH_WORDS["auth"])
    message = (done.stderr + "\n" + done.stdout).lower()
    for word, signs in GH_SIGNS:
        if any(sign in message for sign in signs):
            raise PrError(GH_WORDS[word])
    last = next((line.strip() for line in reversed(done.stderr.splitlines()) if line.strip()), "")
    raise PrError("gh отказал: " + (last[:200] or f"код {done.returncode}"))


def gh_json(*argv: str):
    try:
        answer = json.loads(gh(*argv))
    except ValueError:
        raise PrError("gh ответил непонятно — список запросов не получен") from None
    if isinstance(answer, dict) and answer.get("errors"):
        raise PrError("GitHub вернул ошибку GraphQL — список запросов неполный")
    return answer


def pr_item(node) -> dict:
    """GraphQL PullRequest → строгая форма К-B4; повреждённый узел не теряем молча."""
    try:
        number, draft = node["number"], node["isDraft"]
        repo = node["repository"]["nameWithOwner"]
        author = node["author"]["login"] if node["author"] is not None else "ghost"
        fields = [node[key] for key in ("title", "createdAt", "state", "baseRefName", "headRefName",
                                       "headRefOid", "mergeable", "url")]
        if type(number) is not int or number <= 0 or type(draft) is not bool \
                or not all(isinstance(value, str) for value in [repo, author, *fields]) \
                or not PR_REPO_RE.fullmatch(repo) or not author \
                or node["url"] != f"https://github.com/{repo}/pull/{number}":
            raise ValueError()
        commits = node["commits"]["nodes"]
        if not isinstance(commits, list) or len(commits) != 1:
            raise ValueError()
        rollup = commits[0]["commit"]["statusCheckRollup"]
        checks = rollup["state"] if rollup is not None else None
        if rollup is not None and not isinstance(checks, str):
            raise ValueError()
    except (KeyError, TypeError, ValueError, IndexError):
        raise PrError("GitHub вернул повреждённый запрос — список неполный") from None
    return {"repo": repo, "number": number, "title": node["title"].strip(), "author": author,
            "createdAt": node["createdAt"], "isDraft": draft, "state": node["state"],
            "baseRefName": node["baseRefName"], "headRefName": node["headRefName"],
            "headRefOid": node["headRefOid"], "mergeable": node["mergeable"], "checks": checks,
            "url": node["url"]}


def pr_age(created: str) -> str:
    try:
        then = datetime.strptime(created, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return "давность неизвестна"
    minutes = max(0, int((datetime.now(timezone.utc) - then).total_seconds() // 60))
    if minutes < 1:
        return "только что"
    if minutes < 60:
        return plural(minutes, "минуту", "минуты", "минут") + " назад"
    if minutes < 48 * 60:
        return plural(minutes // 60, "час", "часа", "часов") + " назад"
    return plural(minutes // (24 * 60), "день", "дня", "дней") + " назад"


def say_pr(item: dict) -> str:
    """repo#N · автор · заголовок · давность · проверки [· конфликт] [· черновик]."""
    parts = [f"{item['repo']}#{item['number']}", item["author"], item["title"] or "без заголовка",
             pr_age(item["createdAt"]), PR_CHECKS.get(item["checks"], "проверки неизвестны")]
    if item["mergeable"] == "CONFLICTING":
        parts.append("конфликт")
    if item["isDraft"]:
        parts.append("черновик")
    return " · ".join(parts)


def run_prs(as_json: bool) -> int:
    me = gh_json("api", "user")
    login = me.get("login") if isinstance(me, dict) else None
    if not isinstance(login, str) or not GH_LOGIN_RE.fullmatch(login):
        raise PrError(GH_WORDS["auth"])
    owners, org_names, page = [f"user:{login}"], set(), 1
    while True:
        orgs = gh_json("api", f"user/orgs?per_page=100&page={page}")
        if not isinstance(orgs, list) or len(orgs) > 100:
            raise PrError("Не прочитал организации GitHub — список запросов неполный")
        for org in orgs:
            name = org.get("login") if isinstance(org, dict) else None
            if not isinstance(name, str) or not GH_LOGIN_RE.fullmatch(name) or name.lower() in org_names:
                raise PrError("Не прочитал организации GitHub — список запросов неполный")
            owners.append(f"org:{name}")
            org_names.add(name.lower())
        if len(orgs) < 100:
            break
        page += 1
    query = f"is:pr is:open -author:{login} " + " ".join(owners)
    items, seen, cursors, cursor, total = [], set(), set(), None, None
    while True:
        args = ["api", "graphql", "-f", "query=" + PR_SEARCH, "-f", "q=" + query]
        if cursor is not None:
            args += ["-f", "cursor=" + cursor]
        answer = gh_json(*args)
        try:
            search = answer["data"]["search"]
            nodes, count, info = search["nodes"], search["issueCount"], search["pageInfo"]
            more, end = info["hasNextPage"], info["endCursor"]
            if not isinstance(nodes, list) or type(count) is not int or count < 0 \
                    or type(more) is not bool or (end is not None and not isinstance(end, str)):
                raise ValueError()
        except (KeyError, TypeError, ValueError):
            raise PrError("GitHub вернул неполный список запросов — обнови ещё раз") from None
        # Поиск GitHub ограничен 1000 результатами: молча выдавать первые страницы за полный список нельзя.
        if count > 1000:
            raise PrError("Список запросов неполный: поиск GitHub ограничен 1000 результатами")
        if total is not None and total != count:
            raise PrError("Список запросов изменился во время чтения — обнови ещё раз")
        total = count
        for raw in nodes:
            item = pr_item(raw)
            key = (item["repo"].lower(), item["number"])
            if key in seen:
                raise PrError("GitHub повторил страницу — список запросов неполный")
            seen.add(key)
            if item["author"].lower() != login.lower():
                items.append(item)
        if not more:
            if len(seen) != total:
                raise PrError("GitHub вернул неполный список запросов — обнови ещё раз")
            break
        if not nodes or not end or end in cursors or len(seen) >= total:
            raise PrError("GitHub не отдал следующую страницу — список запросов неполный")
        cursors.add(end)
        cursor = end
    items.sort(key=lambda item: item["createdAt"], reverse=True)
    if as_json:
        print(json.dumps(items, ensure_ascii=False))
    else:
        print("\n".join(say_pr(item) for item in items) if items else "Запросов нет")
    return 0


def run_pr_command(args) -> int:
    as_json = getattr(args, "as_json", False)
    try:
        return run_prs(as_json)
    except PrError as error:
        print(str(error), file=sys.stderr if as_json else sys.stdout)
        return 1


def build_request(args) -> dict:
    """Порядок полей — как в tests/fixtures/pimp/*.request.json."""
    request = {
        "id": new_id(),
        "at": now_iso(),
        "action": args.action,
        "from": from_chat(),
    }
    if args.action == "new-window":
        request["project"] = args.project
        request["place"] = args.place
        # Ключ есть, только когда просили последний чат (new-window-last.request.json).
        if getattr(args, "last", False):
            request["chat"] = "last"
    elif args.action == "close-window":
        request["project"] = args.project
    elif args.action == "main":
        # Ровно одно из chat или project (main.request.json, main-project.request.json).
        request["chat" if CHAT_RE.match(args.target) else "project"] = args.target
    elif args.action == "renew-window":
        # Ровно одно из chat или project, как у close-window (эталоны renew-window*).
        request["chat" if CHAT_RE.match(args.target) else "project"] = args.target
        if args.text is not None:
            request["text"] = args.text
        if args.model:
            request["model"] = args.model
        if args.effort:
            request["effort"] = args.effort
    elif args.action == "paste":
        # Адрес ровно один: либо «переднее окно» (Элвис жмёт F5 там, куда вставляет),
        # либо названный проект. Порядок ключей — front, project, paths (WF75).
        if getattr(args, "project", None):
            # Названный проект сильнее своего чата: без from Swift идёт к окну проекта (z4-r05).
            request["from"] = ""
            request["project"] = args.project
        else:
            request["front"] = True
        paths = getattr(args, "paths", None)
        if paths:
            request["paths"] = paths
    elif args.action == "send":
        # Ровно одно из chat или project, потом text (send.request.json, send-project.request.json).
        if args.chat:
            request["chat"] = args.chat
        else:
            request["project"] = args.project
        request["text"] = args.text
    elif args.action == "hud":
        request["text"] = args.text[:HUD_LIMIT]
    elif args.action == "arrange":
        request["layout"] = args.layout
        # Порядка не просили — ключа нет вовсе (arrange.request.json).
        if args.order:
            request["order"] = args.order
        # Ключ center — после order и только у «главного по центру» (arrange-center.request.json).
        if args.center:
            request["center"] = args.center
    elif args.action == "layout-save":
        request["name"] = args.name
    elif args.action == "layout-restore":
        request["name"] = args.name
        request["fresh"] = args.fresh
    elif args.action == "projects" and args.status:
        request["status"] = True
    elif args.action == "dim":
        # on, потом level — только когда назвали (dim.request.json, dim-off.request.json).
        request["on"] = args.state == "on"
        if args.level is not None:
            request["level"] = args.level
    elif args.action == "look":
        # style, size или grow, show — каждое только когда назвали (look*.request.json).
        if args.style:
            request["style"] = args.style
        if args.size is not None:
            request["grow" if args.size[0] else "size"] = args.size[1]
        if args.show:
            request["show"] = True
    elif args.action == "restart-claude":
        # Позвавший чат сам «идёт», пока ждёт инструмента, — его Пимп из проверки выкинет.
        if args.from_chat:
            request["from"] = args.from_chat
        # Ключ есть, только когда просили (restart-claude-force.request.json).
        if args.force:
            request["force"] = True
    return request


def desktop_refused(args, environ=None) -> bool:
    """#9116: агент без --desktop не открывает и не трогает окна Claude Desktop."""
    environ = os.environ if environ is None else environ
    name = args.command + (f" {args.op}" if args.command == "layout" else "")
    if name not in DESKTOP_COMMANDS or getattr(args, "desktop", False):
        return False
    return any(environ.get(key) for key in AGENT_ENV)


def main(argv=None) -> int:
    # --json пишется и до подкоманды, и после неё: SUPPRESS нужен, чтобы
    # умолчание подкоманды не затёрло ключ, поставленный раньше.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", dest="as_json",
                        default=argparse.SUPPRESS,
                        help="напечатать сырой ответ приложения")
    common.add_argument("--desktop", action="store_true", dest="desktop",
                        default=argparse.SUPPRESS,
                        help="агенту: окна Claude Desktop трогать можно (только Элвис/Рик, #9116)")
    parser = argparse.ArgumentParser(
        prog="pimp.py", parents=[common],
        description="Пимп: окна Claude из любого чата.")
    subs = parser.add_subparsers(dest="command", required=True)

    opener = subs.add_parser("open", parents=[common], help="открыть новое окно Claude в проекте")
    opener.add_argument("project", help="имя папки проекта или абсолютный путь")
    opener.add_argument("--at", dest="place", type=parse_place, default="right",
                        help="left | middle | right | below | above | x,y (по умолчанию right)")
    opener.add_argument("--last", action="store_true", dest="last",
                        help="не новый чат, а последний чат проекта")
    closer = subs.add_parser("close", parents=[common], help="закрыть окно проекта")
    closer.add_argument("project", help="имя папки проекта или абсолютный путь")
    arranger = subs.add_parser("arrange", parents=[common], help="расставить окна по раскладке")
    # Умолчание — «last»: голая «расставь» идёт умным путём приложения, а не
    # подменяет его лентой молча (#5745; умная расстановка — WF77).
    arranger.add_argument("--layout", choices=LAYOUTS, default="last",
                          help="row | 4 | 5 | 5x2 | last | center (по умолчанию last — умная расстановка)")
    arranger.add_argument("--order", type=parse_order, default=None,
                          help="какие проекты первыми, через запятую: VkusnoffKz,SkilZZZ; у center "
                               "«A+B» — один столбец, A над B (в столбец на Одиссее — не больше двух), "
                               "главный в списке — его место: слева работа, справа хобби")
    arranger.add_argument("--center", default=None,
                          help="с --layout center: чей чат в центре — проект, путь или local_… "
                               "(по умолчанию свой чат, нет его — главное окно)")
    renewer = subs.add_parser("renew", parents=[common],
                              help="новый чат проекта на месте окна, старое окно закрыть")
    renewer.add_argument("target", help="local_… окна или имя папки проекта")
    renewer.add_argument("--text", default=None,
                         help="первое сообщение нового чата; «-» — читать со stdin")
    renewer.add_argument("--model", default=None, help="подпись модели в меню, например «Opus 5.5»")
    renewer.add_argument("--effort", choices=EFFORTS, default=None,
                         help="low | medium | high | extra | max")
    sender = subs.add_parser("send", parents=[common],
                             help="вставить текст в поле окна и отправить (кнопкой страницы)")
    target = sender.add_mutually_exclusive_group(required=True)
    target.add_argument("--project", default=None, help="в единственное окно проекта")
    target.add_argument("--chat", default=None, help="в окно чата local_…")
    sender.add_argument("text", help="текст сообщения, до 8000 знаков; «-» — читать со stdin")
    subs.add_parser("layouts", parents=[common], help="список сохранённых раскладок")
    layout = subs.add_parser("layout", parents=[common], help="запомнить раскладку и вернуть её")
    layout_subs = layout.add_subparsers(dest="op", required=True)
    saver = layout_subs.add_parser("save", parents=[common], help="запомнить нынешние окна")
    saver.add_argument("name", help="имя раскладки, например «Утро»")
    restorer = layout_subs.add_parser("restore", parents=[common], help="вернуть раскладку")
    restorer.add_argument("name", help="имя раскладки")
    restorer.add_argument("--new", action="store_true", dest="fresh",
                          help="не те же чаты, а новые по тем же проектам")
    for name, about in (("paste-airdrop", "вставить свежие фотки из загрузок"),
                        ("paste-clipboard", "вставить то, что лежит в буфере")):
        paster = subs.add_parser(name, parents=[common], help=about)
        paster.add_argument("--project", default=None,
                            help="в единственное окно проекта (по умолчанию — переднее окно)")
    hudder = subs.add_parser("hud", parents=[common], help="показать плашку на экране")
    hudder.add_argument("text", help="текст плашки, до 200 знаков")
    sayer = subs.add_parser("say", parents=[common],
                            help="фраза голосом: разобрать мозгом и исполнить")
    sayer.add_argument("text", help="фраза после слова «Пимп»; «-» — читать со stdin")
    lister = subs.add_parser("projects", parents=[common],
                             help="список проектов, которые знает Пимп")
    lister.add_argument("--status", action="store_true",
                        help="ещё и сводка status.md с открытыми окнами проекта")
    subs.add_parser("windows", parents=[common], help="список окон Claude")
    subs.add_parser("hide", parents=[common],
                    help="спрятать (свернуть) все окна Claude, кроме главного — свёрнутые не греют Мак")
    subs.add_parser("show", parents=[common], help="показать спрятанные окна Claude, фокус — главному")
    dimmer = subs.add_parser("dim", parents=[common],
                             help="притемнить окна чатов, кроме главного (on) или снять (off)")
    dimmer.add_argument("state", choices=("on", "off"), help="on — притемнить, off — снять")
    dimmer.add_argument("--level", default=None, help="сила: 0.2–0.8 или проценты 20–80 (по умолчанию прежняя)")
    looker = subs.add_parser("look", parents=[common],
                             help="Обратный отсчёт: размер и показ; без ключей — что выбрано",
                             description="Обратный отсчёт: вид, размер и показ без отправки.")
    looker.add_argument("style", nargs="?", default=None,
                        help="вид: " + LOOK_LIST.replace("%", "%%") + "; по умолчанию 1.8")
    looker.add_argument("--size", default=None, help="размер 60–200 %% или прибавка +20 / -20")
    looker.add_argument("--show", action="store_true", help="показать обратный отсчёт в главном окне (ничего не отправит)")
    subs.add_parser("restore-screens", parents=[common],
                    help="окна как стояли на этих мониторах (закрытые чаты не открывает)")
    gallery = subs.add_parser("gallery", parents=[common],
                              help="фото чата по номерам, как в Viewer: «N  путь» или путь фото N")
    gallery.add_argument("number", nargs="?", type=int, default=None, help="номер фото")
    gallery.add_argument("--chat", default=None,
                         help="чат local_… (по умолчанию — свой, из CLAUDE_CODE_HOST_SESSION_ID)")
    about = ("перезапустить Claude и вернуть окна по снимку; из чата внутри Claude CLI погибнет "
             "вместе с Claude — ответ потом в pimp/<id>.result.json (id — первая строка), "
             "синхронный код 0/1 — для внешних вызывающих (PimpViewer)")
    restarter = subs.add_parser("restart-claude", parents=[common], help=about, description=about)
    restarter.add_argument("--force", action="store_true",
                           help="перезапустить, даже когда в чатах идёт ответ — оборвёт работающие чаты")
    restarter.add_argument("--from", dest="from_chat", default=None,
                           help="чат local_…, который зовёт: его собственный ответ не мешает "
                                "(по умолчанию CLAUDE_CODE_HOST_SESSION_ID)")
    subs.add_parser("summary", parents=[common],
                    help="что в окнах: проект, идёт или ждёт, кеш, строка состояния, «сделай»")
    subs.add_parser("digest", parents=[common],
                    help="сводка всех проектов по status.md и терминалам: идут, ждут Элвиса, тихо (#9077)")
    mainer = subs.add_parser("main", parents=[common],
                             help="чат — в главное окно Claude, прежний чат главного окна — в своё окно")
    mainer.add_argument("target", help="local_… чата или имя папки проекта (его окно или последний чат)")
    termer = subs.add_parser("term", parents=[common],
                             help="чат проекта в терминале (вкладка «rick-<проект>», есть tmux — в tmux)",
                             description="Новый процесс получает tools/claude-term-settings.json через --settings. "
                             "Уже работающему процессу настройки не применяются; --text отправляет сообщение в существующий чат.")
    termer.add_argument("project", help="имя папки проекта (как у open) или абсолютный путь")
    which = termer.add_mutually_exclusive_group()
    which.add_argument("--resume", default=None, help="продолжить чат по cliSessionId")
    which.add_argument("--from-chat", dest="from_chat", default=None,
                       help="продолжить чат окна local_… (его в окне Claude потом не держать)")
    which.add_argument("--last", action="store_true", help="последний чат папки (claude --continue)")
    termer.add_argument("--text", default=None, help="начальная фраза чату; «-» — читать со stdin")
    termer.add_argument("--effort", choices=TERM_EFFORTS, default="high",
                        help="low | medium | high | xhigh | max (по умолчанию high — окна не выше HIGH, 02.10.2026)")
    termer.add_argument("--show", action="store_true",
                        help="открыть окно Терминала (с tmux чат иначе идёт фоном, без окна)")
    termer.add_argument("--app", choices=("terminal", "iterm"), default="terminal",
                        help="terminal (по умолчанию) или iterm — iTerm2, только с tmux")
    term_sender = subs.add_parser("term-send", parents=[common],
                                  help="написать в терминальный чат проекта (и нажать Enter)")
    term_sender.add_argument("project", help="имя проекта (как в term) или rick-<проект>")
    term_sender.add_argument("text", help="текст; «-» — читать со stdin")
    term_lister = subs.add_parser("term-list", parents=[common], help="терминальные чаты в tmux и реестре")
    term_lister.add_argument("--with-terminal", action="store_true",
                             help="добавить старые вкладки Terminal (чтение до 10 с)")
    term_colorer = subs.add_parser("term-color", parents=[common],
                                   help="перекрасить вкладку «rick-<проект>» в тему проекта")
    term_colorer.add_argument("project", help="имя проекта (как в term) или абсолютный путь")
    subs.add_parser("prs", parents=[common],
                    help="открытые запросы команды в репозиториях своего логина и организаций (только чтение)")

    # Кодов у нас всего два: 0 — сделал, 1 — не вышло. Ругань argparse
    # (её код 2) сводим к тому же 1 и одной строке по-русски; --help не трогаем.
    try:
        args = parser.parse_args(argv)
    except SystemExit as stop:
        if stop.code in (0, None):
            raise
        print("Не понял команду — «pimp.py --help» покажет, что умею")
        return 1
    if desktop_refused(args):
        print(DESKTOP_REFUSAL)
        return 1
    # «Скажи фразу» — не действие канала: мозг сам разложит её на шаги.
    if args.command == "gallery":
        return run_gallery(args)
    if args.command == "say":
        text = sys.stdin.read() if args.text == "-" else args.text
        return run_say(text)
    if args.command == "summary":
        return run_summary(getattr(args, "as_json", False))
    if args.command == "digest":
        return run_digest(getattr(args, "as_json", False))
    if args.command in ("term", "term-send", "term-list", "term-color"):
        return run_term_command(args)
    if args.command == "prs":
        return run_pr_command(args)
    if args.command == "arrange" and args.center and args.layout != "center":
        print("Ключ --center — только с --layout center")
        return 1
    if args.command == "renew" and args.text is not None:
        if args.text == "-":
            args.text = sys.stdin.read()
        args.text = args.text.strip()
        if len(args.text) > RENEW_TEXT_LIMIT:
            print(f"Текст длиннее {RENEW_TEXT_LIMIT} знаков — сократи передачу")
            return 1
        if not args.text:
            args.text = None
    if args.command == "send":
        # Проверки — до канала: плохой запрос в окно Элвиса не уходит вовсе.
        if args.text == "-":
            args.text = sys.stdin.read()
        args.text = args.text.strip()
        if args.chat is not None and not CHAT_RE.match(args.chat):
            print("Ключ --chat — это local_… окна; проект — через --project")
            return 1
        if args.project is not None and not args.project.strip():
            print("Проект не назван — ничего не отправил")
            return 1
        if not args.text:
            print("Текст пустой — ничего не отправил")
            return 1
        if "\0" in args.text:
            print("В тексте нулевой символ — ничего не отправил")
            return 1
        if len(args.text) > SEND_TEXT_LIMIT:
            print(f"Текст длиннее {SEND_TEXT_LIMIT} знаков — сократи")
            return 1
        # #8364 (слово Элвиса 01.10 ~02:20: в его поле ввода служебное не слать): в поле
        # чата Рика пишет только голос Элвиса (rick_bus шлёт «Голос Элвиса: …»); окна отвечают Рику почтой.
        if send_to_rick(args) and not args.text.startswith(RICK_VOICE_PREFIX):
            print("В поле Рика окна не пишут — ответь почтой: python3 " + RICK_BUS
                  + ' tell --from <проект> "…"; ничего не отправил')
            return 1
    if args.command == "dim" and args.level is not None:
        level = parse_number(args.level)
        if level is not None and level > 1:
            level = level / 100
        if level is None or not DIM_LEVEL[0] <= round(level * 100) <= DIM_LEVEL[1]:
            print("Сила притемнения — от 20 до 80 % (или 0.2–0.8); ничего не менял")
            return 1
        args.level = round(level * 100) / 100
    if args.command == "look":
        if args.style in LOOK_RETIRED:
            print(f"Вид {args.style} снят — слишком; выбери: {LOOK_LIST}")
            return 1
        if args.style is not None and args.style not in LOOK_STYLES:
            print(f"Такого вида нет — выбери: {LOOK_LIST}")
            return 1
        if args.size is not None:
            raw = args.size.strip().rstrip("%").strip()
            relative = raw[:1] in ("+", "-")
            value = parse_number(raw)
            if value is None or value != int(value) or (not relative and not LOOK_SIZE[0] <= value <= LOOK_SIZE[1]) \
                    or (relative and abs(value) > LOOK_SIZE[1]):
                print("Размер обратного отсчёта — от 60 до 200 % или прибавка вроде +20 / -20; ничего не менял")
                return 1
            args.size = (relative, int(value))
    if args.command == "main" and not args.target.strip():
        print("Не назван чат — ничего не трогал")
        return 1
    if args.command == "restart-claude" and args.from_chat is not None \
            and not CHAT_RE.match(args.from_chat):
        print("Ключ --from — это local_… чата; Claude не трогал")
        return 1
    # «layout save/restore» — одно действие канала из двух слов.
    args.action = (f"layout-{args.op}" if args.command == "layout"
                   else {"open": "new-window", "close": "close-window",
                         "paste-airdrop": "paste", "paste-clipboard": "paste",
                         "restore-screens": "screens-restore",
                         "renew": "renew-window",
                         }.get(args.command, args.command))
    if args.command == "paste-airdrop":
        return run_paste_airdrop(args)
    return run(build_request(args), getattr(args, "as_json", False))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("Прервал")
        sys.exit(1)
