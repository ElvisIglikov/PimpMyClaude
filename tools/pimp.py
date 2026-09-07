#!/usr/bin/env python3
"""Пимп из любого чата (WF36): открыть окно Claude, расставить окна, спросить
проекты и окна — не трогая мышь и клавиатуру.

Как это работает. Клавиши жмёт само приложение PimpMyClaude, а разговаривают с
ним файлами: сюда кладётся запрос `<id>.json`, приложение на общем тике (2 с)
берёт его в работу (пишет `<id>.taken`) и отвечает `<id>.result.json` рядом.
Каталог по умолчанию — ~/Library/Application Support/MyClaude/pimp/ (для тестов
переопределяется переменной окружения MYCLAUDE_PIMP_DIR). Контракт полей —
tests/fixtures/pimp/*.json, они же правда для Swift-половины (PimpChannel).

Команды:
  pimp.py open <проект> [--at left|middle|right|below|above|x,y]
  pimp.py arrange
  pimp.py projects
  pimp.py windows
Общие ключи: --json — напечатать сырой ответ приложения вместо строки по-русски.

На выход — ОДНА строка по-русски; код возврата 0 (сделал) или 1 (не вышло).
Свой чат берётся из CLAUDE_CODE_HOST_SESSION_ID: её нет (субагент, чужой
терминал) — «под этим» и «над этим» деградируют в «справа», и это сказано вслух.

Ожидания настраиваются переменными окружения (нужны только тестам):
MYCLAUDE_PIMP_WAIT — сколько секунд ждать ответ (по умолчанию 60),
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

ERRORS = {
    "stale": "Пимп не успел взять запрос вовремя — повтори",
    "busy": "Пимп занят — открывает предыдущее окно",
    "no-windows": "Claude не запущен или окон нет",
    "window-missing": "Чат создал, а окно не появилось — вынеси его в окно руками",
    "too-small": "Мало места: окно не делится пополам",
    "bad-request": "Пимп не понял запрос",
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
    """
    result = directory / f"{request_id}.result.json"
    taken = directory / f"{request_id}.taken"
    limit = seconds("MYCLAUDE_PIMP_WAIT", RESULT_WAIT_S)
    silent_at = seconds("MYCLAUDE_PIMP_TAKEN", TAKEN_WAIT_S)
    started = time.monotonic()
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
        if not seen_taken:
            seen_taken = taken.exists()
        spent = time.monotonic() - started
        if not seen_taken and spent >= silent_at:
            return "silent", ""
        if spent >= limit:
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


def say_open(request: dict, data: dict) -> str:
    window = data.get("window") if isinstance(data.get("window"), dict) else {}
    title = str(window.get("title") or "").strip() or request["project"]
    place = request["place"]
    where = PLACE_WORDS.get(place, f"в точку {place}")
    if place in ("below", "above") and not data.get("fromResolved"):
        line = f"Открыл {title} справа: своего чата не нашёл, «{where}» не вышло"
    else:
        line = f"Открыл {title} {where}"
    layers = data.get("layers")
    if not layers or layers in ("failed", "no-title"):
        line += ", но цвет не встал — поставь тему из меню окна"
    return line


def say_error(request: dict, data: dict) -> str:
    error = str(data.get("error") or "").strip()
    if error == "project-missing":
        names = [str(name) for name in (data.get("projects") or []) if str(name).strip()]
        if names:
            return f"Не нашёл проект «{request.get('project', '')}», есть: " + ", ".join(names)
        return f"Не нашёл проект «{request.get('project', '')}», и списка Пимп не дал"
    known = ERRORS.get(error)
    if known:
        return known
    return f"Пимп отказал: {error}" if error else "Пимп отказал молча"


def say_result(request: dict, data: dict) -> str:
    action = request["action"]
    if not data.get("ok"):
        return say_error(request, data)
    if action == "new-window":
        return say_open(request, data)
    if action == "arrange":
        windows = data.get("windows") or []
        # Второй экран Пимп не раскладывает — и говорит об этом словами, а не
        # молча (риск 3 плана WF36): «screen» в ответе для того и есть.
        screen = "на главном экране" if data.get("screen") == "main" else "на экране"
        return (f"Расставил {plural(len(windows), 'окно', 'окна', 'окон')} "
                f"{screen}{minimized_note(data)}")
    if action == "projects":
        names = [str(item.get("name") or "").strip()
                 for item in (data.get("projects") or []) if isinstance(item, dict)]
        names = [name for name in names if name]
        if not names:
            return "Проектов Пимп пока не знает — открой чат в папке проекта"
        return "Проекты: " + ", ".join(names)
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
        request["layout"] = "row"
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
    subs.add_parser("arrange", parents=[common], help="расставить окна в ряд")
    subs.add_parser("projects", parents=[common], help="список проектов, которые знает Пимп")
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
    args.action = {"open": "new-window"}.get(args.command, args.command)
    return run(build_request(args), getattr(args, "as_json", False))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("Прервал")
        sys.exit(1)
