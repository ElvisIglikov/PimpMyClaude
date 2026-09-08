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
  pimp.py open <проект> [--at left|middle|right|below|above|x,y]
  pimp.py arrange [--layout row|4|5|5x2|last] [--order Проект,Проект,…]
    (раскладку не назвали — «last»: повторяем ту, что Элвис выбрал плиткой)
  pimp.py layouts
  pimp.py layout save <имя>
  pimp.py layout restore <имя> [--new]
  pimp.py projects [--status]
  pimp.py windows
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
"""

import argparse
import json
import os
import random
import re
import sys
import time
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
    skipped = data.get("skipped")
    if isinstance(skipped, int) and skipped > 0:
        # Свободной ячейки в раскладке не нашлось — окно осталось, где родилось;
        # про место молчим, иначе соврём (WF21).
        line = "Окно открыл, но в раскладке места нет — оставил поверх"
    elif place in ("below", "above") and not data.get("fromResolved"):
        line = f"Открыл {title} справа: своего чата не нашёл, «{where}» не вышло"
    else:
        line = f"Открыл {title} {where}"
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
    if error == "layout-missing":
        names = [str(name).strip() for name in (data.get("layouts") or [])
                 if str(name).strip()]
        asked = request.get("name", "")
        if names:
            return f"Раскладки «{asked}» нет, есть: " + ", ".join(names)
        return f"Раскладки «{asked}» нет, и сохранённых пока нет"
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


def run(request: dict, as_json: bool) -> int:
    directory = pimp_dir()
    warn_probe(directory)
    try:
        write_request(directory, request)
    except OSError as error:
        print(f"Не смог положить запрос в {directory}: {error}")
        return 1
    kind, raw = wait_result(directory, request["id"])
    if kind == "silent":
        print("Пимп не запущен")
        return 1
    if kind == "timeout":
        print("Пимп взял запрос и не ответил — посмотри, жив ли он")
        return 1
    if kind == "bad":
        # В режиме --json ответ печатаем как есть и молчим: лишняя строка сверху
        # сломала бы разбор тому, кто нас позвал.
        print(raw.strip() if as_json else "Пимп ответил непонятным файлом")
        return 1
    if as_json:
        print(raw.strip())
    try:
        data = json.loads(raw)
        if not isinstance(data, dict):
            raise ValueError("ответ не объект")
    except (ValueError, TypeError):
        if not as_json:
            print("Пимп ответил непонятным файлом")
        return 1
    if not as_json:
        print(say_result(request, data))
    return 0 if data.get("ok") else 1


def build_request(args) -> dict:
    """Порядок полей — как в tests/fixtures/pimp/*.request.json."""
    request = {
        "id": new_id(),
        "at": now_iso(),
        "action": args.action,
        "from": os.environ.get("CLAUDE_CODE_HOST_SESSION_ID", "").strip(),
    }
    if args.action == "new-window":
        request["project"] = args.project
        request["place"] = args.place
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
    # «layout save/restore» — одно действие канала из двух слов.
    args.action = (f"layout-{args.op}" if args.command == "layout"
                   else {"open": "new-window"}.get(args.command, args.command))
    return run(build_request(args), getattr(args, "as_json", False))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("Прервал")
        sys.exit(1)
