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
  pimp.py arrange [--layout row|4|5|5x2|last] [--order Проект,Проект,…]
    (раскладку не назвали — «last»: повторяем ту, что Элвис выбрал плиткой)
  pimp.py layouts
  pimp.py layout save <имя>
  pimp.py layout restore <имя> [--new]
  pimp.py paste-airdrop [--project <проект>]
  pimp.py paste-clipboard [--project <проект>]
  pimp.py hud <текст>
  pimp.py projects [--status]
  pimp.py windows
  pimp.py say <фраза|->        (WF75: фраза голосом → DeepSeek → шаги каналом)
Общие ключи: --json — напечатать сырой ответ приложения вместо строки по-русски.

На выход — ОДНА строка по-русски (у «projects --status» — строка на проект);
код возврата 0 (сделал) или 1 (не вышло).
Свой чат берётся из CLAUDE_CODE_HOST_SESSION_ID: её нет (субагент, чужой
терминал) — «под этим» и «над этим» деградируют в «справа», и это сказано вслух.

Ожидания настраиваются переменными окружения (нужны только тестам):
MYCLAUDE_PIMP_WAIT — сколько секунд ждать ответ (по умолчанию 60); счёт идёт от
последнего удара <id>.taken, а не от запроса: раскладка открывает окна по
одному и после каждого перезаписывает метку (WF41),
MYCLAUDE_PIMP_TAKEN — за сколько секунд приложение обязано взять запрос (5).
Голосовой мозг (WF75): MYCLAUDE_VOICE_ENV — файл с ключом DeepSeek,
MYCLAUDE_VOICE_FAKE — путь к готовому ответу модели (тогда ни ключа, ни сети),
MYCLAUDE_DOWNLOADS — каталог загрузок, откуда берутся фотки Эйрдропа.
"""

import argparse
import json
import os
import random
import re
import sys
import time
import urllib.error
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

# Раскладки (WF21). «last» — повторить последнюю выбранную: в ответе приложение
# называет уже применённую, поэтому словами нужны все пять.
LAYOUTS = ("row", "4", "5", "5x2", "last")
LAYOUT_WORDS = {
    "row": "как сейчас (лента)",
    "4": "четыре в ряд",
    "5": "пять в ряд",
    "5x2": "в два ряда (5×2)",
    "last": "как в прошлый раз",
}

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
# Общий бюджет фразы: три окна по 40 с плюс тик канала — дольше Диктатор ждать
# не станет, поэтому договариваем частичным итогом «сделал 2 из 3».
VOICE_BUDGET_S = 180.0
VOICE_LOG_LINES = 1000
BUSY_RETRY_S = 2.0
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
    "window-missing": "Чат создал, а окно не появилось — вынеси его в окно руками",
    "too-small": "Мало места: окно не делится пополам",
    "bad-request": "Пимп не понял запрос",
    # Ни одно окно не совпало с ячейкой сетки — запоминать нечего (#5728).
    "not-arranged": "Окна стоят не по сетке — сперва расставь их, потом запоминай раскладку",
    # WF75. Последнего чата нет — Claude переустановлен или проект новый.
    "chat-missing": "Последнего чата в этом проекте нет — открой новый",
    "ambiguous": "Окон проекта несколько — скажи, какое именно, я ничего не трогал",
    "main-window": "Это главное окно Claude — его я не закрываю",
}


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


def wait_result(directory: Path, request_id: str):
    """Ждём ответ. Отдаёт (вид, сырой текст): "ok" | "silent" | "timeout" | "bad".

    "silent" — за MYCLAUDE_PIMP_TAKEN секунд не появилось ни ответа, ни метки
    <id>.taken: приложение не работает (или не видит каталог). "bad" — файл
    есть, а JSON в нём так и не собрался: недописанный файл даём дочитать
    (BROKEN_GRACE_S), но ждать из-за него всю минуту не станем.

    Терпение считаем от ПОСЛЕДНЕГО признака жизни, а не от запроса: приложение
    перезаписывает <id>.taken после каждого открытого окна (heartbeat, WF41), и
    возврат раскладки из пяти чатов честно занимает минуты. Метка не двигается —
    ждём ровно MYCLAUDE_PIMP_WAIT, как раньше.
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
        if now - last_beat >= limit:
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
        # про место молчим, иначе соврём (WF21).
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
    action = request.get("action", "")
    if error == "window-missing" and action == "close-window":
        return (f"Окон проекта {short_name(request.get('project', ''))} не нашёл — может, окно уже "
                "закрыто, или карта чатов молчит: включи «Цвет по проекту»")
    if error == "window-missing" and action == "paste":
        return "Окна, куда вставлять, не нашёл — открой чат проекта или встань в нужное окно"
    if error == "no-windows" and action == "paste":
        return "Claude сейчас не впереди — встань в нужный чат и повтори"
    known = ERRORS.get(error)
    if known:
        return known
    return f"Пимп отказал: {error}" if error else "Пимп отказал молча"


def say_arrange(request: dict, data: dict) -> str:
    windows = data.get("windows") or []
    line = f"Расставил {plural(len(windows), 'окно', 'окна', 'окон')}"
    # Раскладываем на том экране, где стоят окна Claude, — так и говорим (#5732; до 08.09
    # тут стояло «на главном экране», и это была неправда).
    if data.get("screen") == "windows":
        line += " на экране, где стоят окна"
    # Раскладку называем ту, что применилась: «last» приложение разрешает
    # в конкретную, и Элвис должен видеть, что именно вышло (WF21).
    layout = LAYOUT_WORDS.get(str(data.get("layout") or ""))
    if layout:
        line += f": {layout}"
    # Просили порядок проектов (WF41): кто встал первым, кого не нашли, сколько
    # окон без папки уехало в хвост. Не просили — строка прежняя.
    order = request.get("order") or []
    missing = [str(item) for item in (data.get("missing") or [])]
    if order:
        first = [short_name(item) for item in order if item not in missing]
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
    if action == "paste":
        return say_paste(data)
    if action == "hud":
        return "Показал плашку"
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
        titles = [str(item.get("title") or "").strip() or "без имени"
                  for item in (data.get("windows") or []) if isinstance(item, dict)]
        if not titles:
            return f"Окон Claude нет{minimized_note(data)}"
        return (f"Окон {len(titles)}: " + " · ".join(titles)) + minimized_note(data)
    return "Пимп ответил, но я не знаю на что"


SILENT_LINES = {
    "write": "Не смог положить запрос Пимпу",
    "silent": "Пимп не запущен",
    "timeout": "Пимп взял запрос и не ответил — посмотри, жив ли он",
    "bad": "Пимп ответил непонятным файлом",
}


def send(request: dict):
    """Положить запрос и дождаться ответа: (вид, разобранный ответ, сырой текст).

    Вид — "ok" | "write" | "silent" | "timeout" | "bad"; ответ есть только у "ok".
    """
    directory = pimp_dir()
    try:
        write_request(directory, request)
    except OSError as error:
        return "write", None, str(error)
    kind, raw = wait_result(directory, request["id"])
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
    kind, data, raw = send(request)
    if kind != "ok":
        # В режиме --json непонятный ответ печатаем как есть и молчим: лишняя строка
        # сверху сломала бы разбор тому, кто нас позвал.
        if kind == "bad" and as_json:
            print(raw.strip())
        elif kind == "write":
            print(f"Не смог положить запрос в {pimp_dir()}: {raw}")
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


def voice_net(phrase: str, names: list, values: dict):
    """Один POST и жёсткий срок: рассуждения выключены, ответ — объект JSON."""
    key = values.get("DEEPSEEK_API_KEY", "").strip()
    model = (values.get("DEEPSEEK_MODEL") or VOICE_MODEL).strip()
    base = (values.get("DEEPSEEK_BASE_URL") or VOICE_BASE).strip().rstrip("/")
    payload = {
        "model": model,
        "messages": [{"role": "system", "content": voice_prompt_text(names)},
                     {"role": "user", "content": phrase}],
        "response_format": {"type": "json_object"},
        "max_tokens": VOICE_MAX_TOKENS,
        "thinking": {"type": "disabled"},
    }
    request = urllib.request.Request(
        base + "/chat/completions",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        # Ключ только заголовком: в URL он попал бы в логи прокси.
        headers={"Authorization": "Bearer " + key,
                 "Content-Type": "application/json; charset=utf-8"},
        method="POST")
    try:
        with urllib.request.urlopen(request, timeout=VOICE_TIMEOUT_S) as answer:
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
    """Проект берётся только из живого списка: чужая папка в чате с авто-Allow
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
                          "layout": layout if layout in LAYOUTS else "last",
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
    elif args.action == "paste":
        # Адрес ровно один: либо «переднее окно» (Элвис жмёт F5 там, куда вставляет),
        # либо названный проект. Порядок ключей — front, project, paths (WF75).
        if getattr(args, "project", None):
            request["project"] = args.project
        else:
            request["front"] = True
        paths = getattr(args, "paths", None)
        if paths:
            request["paths"] = paths
    elif args.action == "hud":
        request["text"] = args.text[:HUD_LIMIT]
    elif args.action == "arrange":
        request["layout"] = args.layout
        # Порядка не просили — ключа нет вовсе (arrange.request.json).
        if args.order:
            request["order"] = args.order
    elif args.action == "layout-save":
        request["name"] = args.name
    elif args.action == "layout-restore":
        request["name"] = args.name
        request["fresh"] = args.fresh
    elif args.action == "projects" and args.status:
        request["status"] = True
    return request


def main(argv=None) -> int:
    # --json пишется и до подкоманды, и после неё: SUPPRESS нужен, чтобы
    # умолчание подкоманды не затёрло ключ, поставленный раньше.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", dest="as_json",
                        default=argparse.SUPPRESS,
                        help="напечатать сырой ответ приложения")
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
    # Умолчание — «last»: голая «расставь» повторяет раскладку, которую Элвис выбрал
    # плиткой, а не подменяет её лентой молча (#5745).
    arranger.add_argument("--layout", choices=LAYOUTS, default="last",
                          help="row | 4 | 5 | 5x2 | last (по умолчанию last — как в прошлый раз)")
    arranger.add_argument("--order", type=parse_order, default=None,
                          help="какие проекты первыми, через запятую: VkusnoffKz,SkilZZZ")
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

    # Кодов у нас всего два: 0 — сделал, 1 — не вышло. Ругань argparse
    # (её код 2) сводим к тому же 1 и одной строке по-русски; --help не трогаем.
    try:
        args = parser.parse_args(argv)
    except SystemExit as stop:
        if stop.code in (0, None):
            raise
        print("Не понял команду — «pimp.py --help» покажет, что умею")
        return 1
    # «Скажи фразу» — не действие канала: мозг сам разложит её на шаги.
    if args.command == "say":
        text = sys.stdin.read() if args.text == "-" else args.text
        return run_say(text)
    # «layout save/restore» — одно действие канала из двух слов.
    args.action = (f"layout-{args.op}" if args.command == "layout"
                   else {"open": "new-window", "close": "close-window",
                         "paste-airdrop": "paste", "paste-clipboard": "paste",
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
