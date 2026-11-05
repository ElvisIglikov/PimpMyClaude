#!/usr/bin/env python3
"""Сторож вставки снимков экрана (задача 9796, слово Элвиса 11.10.2026: «контролировать: вставился, не вставился,
если не вставился, регистрировать это как задачу и разбираться, почему»).

Снимок в поле Claude вставляет Диктатор (ShotDelivery.swift: буфер + ⌘V), сам он в Trelvis не пишет. Сторож читает
хвост его журнала и по каждому снимку выносит исход:
  sent     — «уехал в окно сразу» (Диктатор пишет это сразу после ⌘V, плитку не проверяет);
  failed   — попытка была, снимок не вставлен («остался в стопке», «не вставлен, он в буфере») — причина из журнала;
  outside  — снят вне записи, а запись началась в ближайшие NEAR_SEC: вставки не было вовсе;
  alone    — снят вне записи и диктовки рядом нет: обычный снимок, не сбой;
  unknown  — снят на записи, а строк «снимок на диктовке» нет.
failed, outside и unknown — сбой: первая за день по своей причине заводит задачу в Trelvis (проект Диктатора,
--actor fable) и строку Рику, следующие дописываются в ту же задачу заметкой.

  python3 tools/shot_watch.py scan [--since 2026-10-11T15:20:00Z] [--dry] [--quiet]   один проход
  python3 tools/shot_watch.py stat [--days 3]                                         счёт исходов по дням
Службой (раз в 60 с «scan --quiet») ставит «python3 tools/pimp.py shot-watch install».
Пути: журнал Диктатора, состояние, trelvis.py и rick_bus.py — от HOME и корня проектов (projectsRoot из
MyClaude/claude.json, нет его — ~/Projects); тестам — переменные SHOT_WATCH_LOG/STATE/TRELVIS/BUS.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys

MYCLAUDE = os.path.expanduser("~/Library/Application Support/MyClaude")


def projects_root():
    """Корень проектов — как у pimp.py: `projectsRoot` из claude.json, нет его — ~/Projects."""
    try:
        with open(os.path.join(MYCLAUDE, "claude.json"), encoding="utf-8") as f:
            root = json.load(f).get("projectsRoot")
    except (OSError, ValueError, AttributeError):
        root = None
    return os.path.expanduser(root if isinstance(root, str) and root else "~/Projects")


LOG = os.environ.get("SHOT_WATCH_LOG") or os.path.expanduser(
    "~/Library/Application Support/Dictatorik/dictatorik.log")
STATE = os.environ.get("SHOT_WATCH_STATE") or os.path.join(MYCLAUDE, "shot-watch", "state.json")
TRELVIS = os.environ.get("SHOT_WATCH_TRELVIS") or os.path.join(projects_root(), "TrelvisCom", "trelvis.py")
BUS = os.environ.get("SHOT_WATCH_BUS") or os.path.join(projects_root(), "Rick", "tools", "rick_bus.py")
PROJECT = "dictatorik"
ACTOR = "fable"

TAIL = 400 * 1024       # читаем хвост журнала: это часы работы Диктатора, снимки старше уже разобраны
NEAR_SEC = 90           # запись началась не позже этого после снимка вне записи — снимок был для диктовки
SETTLE_SEC = 20         # столько ждём строк «снимок на диктовке» после съёмки
GROUP_SEC = 15          # строка «снимок на диктовке» относится к снимку, если она не дальше этого от его строк
REC_MAX = 2 * 3600      # запись без строки конца дольше этого — кончилась (перезапуск Диктатора), не «идёт»
SEEN_MAX = 600
BAD = ("failed", "outside", "unknown")

_LINE = re.compile(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)Z (.*)$")
_SHOT = re.compile(r"^Снимок shot-(\d+): (.*)$")
_DONE = re.compile(r"доставлен \(([^;)]*);? ?файл: (.+)\)\s*$")
_REC_START = re.compile(r"^recording started ")
# Все концы записи из журнала Диктатора (RecordingController): пропущенный конец держал бы «запись идёт», и снимок
# после неё выходил бы ложным «unknown». Строка с id чужой записи (разбор старой в очереди) нынешнюю не кончает.
_REC_END = re.compile(r"^(transcription completed |no usable voice in |dictation cancelled |recording finalized |"
                      r"случайное короткое нажатие: |запись без единого слова|error: Распознать запись не удалось)")
_REC_ID = re.compile(r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}")
_DICT = "снимок на диктовке: "


def _ts(s):
    return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=datetime.timezone.utc).timestamp()


def _local(t, fmt="%H:%M:%S"):
    return datetime.datetime.fromtimestamp(t).strftime(fmt)


def read_tail(path=None, limit=TAIL):
    path = path or LOG
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - limit))
            data = f.read().decode("utf-8", "replace")
    except OSError:
        return []
    lines = data.splitlines()
    return lines[1:] if size > limit else lines  # первая строка хвоста может быть обрезана


def parse(lines, now):
    """Строки журнала → список снимков {key, t, file, verdict, reason, steps}; нерешённые (рано судить) не входят."""
    shots, cur = [], None
    rec_on, rec_id, rec_t, rec_end, starts = False, None, None, None, []
    pre = []  # строки «на диктовке», пришедшие без открытого снимка
    for line in lines:
        m = _LINE.match(line)
        if not m:
            continue
        t, msg = _ts(m.group(1)), m.group(2)
        if rec_on and t - rec_t > REC_MAX:
            rec_on = False
        if _REC_START.match(msg):
            rec_id = _REC_ID.search(msg)
            rec_on, rec_id, rec_t = True, rec_id and rec_id.group(0), t
            starts.append(t)
            continue
        if _REC_END.match(msg):
            end_id = _REC_ID.search(msg)
            if end_id is None or rec_id is None or end_id.group(0) == rec_id:
                rec_on, rec_end = False, t
            continue
        s = _SHOT.match(msg)
        if s:
            n, rest = s.group(1), s.group(2)
            if cur is None or cur["n"] != n or t - cur["last"] > 120:
                cur = {"n": n, "t0": t, "last": t, "t": None, "file": "", "steps": [], "cancel": False,
                       "rec": rec_on, "rec_end": rec_end}
                shots.append(cur)
            cur["last"] = t
            if rest.startswith("отменён"):
                cur["cancel"] = True
            d = _DONE.search(rest)
            if d:
                cur["t"], cur["file"] = t, d.group(2).strip()
                cur["rec"], cur["rec_end"] = rec_on, rec_end
            continue
        if msg.startswith(_DICT) and cur is not None and t - cur["last"] <= GROUP_SEC:
            cur["steps"].append(msg[len(_DICT):])
            cur["last"] = t
    out = []
    for sh in shots:
        if sh["cancel"] or sh["t"] is None:
            continue
        t, steps = sh["t"], sh["steps"]
        res = {"key": "%s|%s" % (int(t), sh["file"]), "t": t, "file": sh["file"], "steps": steps, "reason": ""}
        sent = any("уехал в окно" in x for x in steps)
        bad = [x for x in steps if "остался в стопке" in x or "не вставлен" in x]
        if sent:
            res["verdict"] = "sent"
        elif bad:
            res["verdict"], res["reason"] = "failed", bad[-1].split(" — ")[0].strip()
        elif sh["rec"]:
            if now - t < SETTLE_SEC:
                continue
            res["verdict"], res["reason"] = "unknown", "снят на записи, строк о вставке в журнале нет"
        else:
            nxt = next((x for x in starts if x >= t), None)
            if nxt is not None and nxt - t <= NEAR_SEC:
                ago = ("запись кончилась за %d с до снимка, " % (t - sh["rec_end"])) if sh["rec_end"] and t - sh["rec_end"] < 600 else ""
                res["verdict"] = "outside"
                res["reason"] = "снят вне записи"
                res["detail"] = "%sновая началась через %d с после него" % (ago, nxt - t)
            elif now - t < NEAR_SEC:
                continue
            else:
                res["verdict"] = "alone"
        out.append(res)
    return out


def _load():
    try:
        with open(STATE, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _save(data):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, STATE)


def _run(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except (OSError, subprocess.SubprocessError) as e:
        return 1, str(e)


def _first(out):
    """Первая непустая строка ответа чужого CLI — в журнал сторожа, не больше 200 знаков."""
    return next((x.strip() for x in out.splitlines() if x.strip()), "пустой ответ")[:200]


def describe(sh):
    """Одна строка о сбое: время, причина, подробность, файл."""
    parts = ["%s — %s" % (_local(sh["t"]), sh["reason"])]
    if sh.get("detail"):
        parts.append(sh["detail"])
    if sh["verdict"] == "failed" and sh["steps"]:
        parts.append("шаги: " + " → ".join(sh["steps"][-4:]))
    if sh["file"]:
        parts.append("файл «%s»" % sh["file"])
    return "; ".join(parts)


WHY = {
    "outside": "Вне записи Диктатор снимок в окно не шлёт вовсе (ShotDelivery.handOverDuringDictation, нет цели "
               "диктовки), а старт записи убирает его из стопки (ShotShelf.beginRecordingSession). Нужно: держать "
               "такой снимок и вставлять на ближайшем старте записи.",
    "failed": "Попытка вставки была, но Диктатор сам отказался — причина в строке журнала. Разбирать по шагам "
              "«снимок на диктовке» вокруг этого времени в dictatorik.log.",
    "unknown": "Снимок снят на идущей записи, а строк «снимок на диктовке» в журнале нет: Диктатор молча не стал "
               "вставлять (ShotDelivery.goesToTheWindowNow — настройка вставки на диктовке, вывод «только в буфер», "
               "нет Универсального доступа или окна цели) или land() вернул false — эти выходы журнал не пишет.",
}


def report(sh, state, dry=False):
    """Сбой → задача (первая за день по причине) или заметка в неё. Возвращает строку, что сделано."""
    day = _local(sh["t"], "%Y-%m-%d")
    cls = "%s:%s" % (sh["verdict"], sh["reason"])
    tasks = state.setdefault("tasks", {}).setdefault(day, {})
    line = describe(sh)
    if cls in tasks:
        if not dry:
            code, out = _run([sys.executable, TRELVIS, "note", str(tasks[cls]), "Снимок снова не вставился: " + line,
                              "--actor", ACTOR])
            if code != 0:  # второй Мак заметок не пишет (trelvis.py: «Со второго Мака команда «note» не работает»)
                return "заметка в #%s не дописалась (%s): %s" % (tasks[cls], _first(out), line)
        return "заметка в #%s: %s" % (tasks[cls], line)
    title = "🧠 🐞 Снимок экрана не вставился в окно Claude (%s): %s" % (_local(sh["t"], "%d.%m"), sh["reason"])
    summary = "Сторож вставки снимков: %s. %s" % (line, WHY.get(sh["verdict"], ""))
    if dry:
        return "задача: %s · %s" % (title, summary)
    code, out = _run([sys.executable, TRELVIS, "quick-add", title, "--project", PROJECT, "--origin", "agent",
                      "--actor", ACTOR, "--allow-duplicates", "--summary", summary,
                      "--original", "Автоматически, сторож tools/shot_watch.py (PimpMyClaude) по журналу Диктатора. "
                      "Слово Элвиса 11.10.2026: «если не вставился, регистрировать это как задачу и разбираться, "
                      "почему не вставился»."])
    m = re.match(r"(?:Уже есть: )?#(\d+)\b", out.strip())  # «#9900 dictatorik · очередь…» — первая строка quick-add
    if code != 0 or not m:
        return "задача не завелась (%s): %s" % (_first(out), line)
    tasks[cls] = int(m.group(1))
    _run([sys.executable, BUS, "tell", "--from", "PimpMyClaude",
          "снимок экрана не вставился в окно Claude: %s — задача #%s (Диктатор), сторож shot_watch" % (line, tasks[cls])])
    return "задача #%s: %s" % (tasks[cls], line)


def tick(now=None, since=None, dry=False):
    """Один проход. Первый запуск без состояния всё старое считает виденным — историю задачами не заливает."""
    import time
    now = now or time.time()
    state = _load()
    shots = parse(read_tail(), now)
    seen = state.get("seen")
    first = seen is None
    seen = list(seen or [])
    known = set(seen)
    done = []
    for sh in shots:
        if sh["key"] in known:
            continue
        fresh = sh["t"] >= since if since is not None else not first
        if fresh and sh["verdict"] in BAD:
            done.append(report(sh, state, dry=dry))
        seen.append(sh["key"])
    if not dry:
        state["seen"] = seen[-SEEN_MAX:]
        for day in sorted(state.get("tasks", {}))[:-7]:
            del state["tasks"][day]
        if done or len(seen) != len(known):
            _save(state)
    return done


def stat(days=3):
    import time
    rows = {}
    for sh in parse(read_tail(limit=8 * 2 ** 20), time.time()):
        rows.setdefault(_local(sh["t"], "%Y-%m-%d"), {}).setdefault(sh["verdict"], 0)
        rows[_local(sh["t"], "%Y-%m-%d")][sh["verdict"]] += 1
    out = []
    for day in sorted(rows)[-days:]:
        r = rows[day]
        out.append("%s: вставлено %d, отказ %d, вне записи %d, без попытки на записи %d, просто снимков %d" % (
            day, r.get("sent", 0), r.get("failed", 0), r.get("outside", 0), r.get("unknown", 0), r.get("alone", 0)))
    return out


def main(argv):
    ap = argparse.ArgumentParser(description="Сторож вставки снимков экрана в окно Claude")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("scan", help="один проход по журналу Диктатора")
    p.add_argument("--since", help="считать новыми снимки с этого времени журнала, UTC: 2026-10-11T15:20:00Z")
    p.add_argument("--dry", action="store_true", help="ничего не заводить и не запоминать, только напечатать")
    p.add_argument("--quiet", action="store_true",
                   help="служба: молчать, когда нового нет, строки — со временем (журнал не растёт впустую)")
    p = sub.add_parser("stat", help="счёт исходов по дням")
    p.add_argument("--days", type=int, default=3)
    a = ap.parse_args(argv)
    if a.cmd == "stat":
        print("\n".join(stat(a.days)) or "снимков в журнале нет")
        return 0
    since = _ts(a.since.rstrip("Z")) if a.since else None
    done = tick(since=since, dry=a.dry)
    if a.quiet:
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print("\n".join("%s %s" % (stamp, x) for x in done), end="\n" if done else "")
    else:
        print("\n".join(done) or "новых сбоев нет")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
