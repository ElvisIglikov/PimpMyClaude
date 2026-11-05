#!/usr/bin/env python3
"""Сторож вставки снимков tools/shot_watch.py и его служба «pimp.py shot-watch» (🔥 #9796).

Журнал Диктатора — эталонные куски tests/fixtures/shot-watch/*.txt (строки того же вида, что пишет Диктатор:
ShotDelivery, ScreenCapture, RecordingController). Trelvis, почта Рика и launchctl — подделки во временной папке:
пути подменяются переменными SHOT_WATCH_*, настоящие задачи и службы не трогаются. Время — UTC (TZ на модуль).
"""

import calendar
import contextlib
import io
import itertools
import json
import os
import plistlib
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pimp_testlib  # noqa: E402

WATCH = pimp_testlib.ROOT / "tools" / "shot_watch.py"
LOGS = pimp_testlib.FIXTURES / "shot-watch"
DAY = 24 * 3600
_names = itertools.count()
_tz = None


def setUpModule():
    global _tz
    _tz = os.environ.get("TZ")
    os.environ["TZ"] = "UTC"
    time.tzset()


def tearDownModule():
    if _tz is None:
        os.environ.pop("TZ", None)
    else:
        os.environ["TZ"] = _tz
    time.tzset()


def load_watch(env):
    """Свежая копия модуля: пути он берёт из окружения при загрузке."""
    with mock.patch.dict(os.environ, env):
        return pimp_testlib.load("shot_watch_%d" % next(_names), WATCH)


def lines(name):
    return (LOGS / name).read_text(encoding="utf-8").splitlines()


def ts(text):
    return calendar.timegm(time.strptime(text, "%Y-%m-%dT%H:%M:%SZ"))


FAKE_TRELVIS = r'''
import json, os, sys
calls = os.environ["FAKE_CALLS"]
with open(calls, "a", encoding="utf-8") as f:
    f.write(json.dumps(["trelvis"] + sys.argv[1:], ensure_ascii=False) + "\n")
if sys.argv[1] == "note" and os.environ.get("FAKE_NOTE_REFUSED"):
    print("⛔ Со второго Мака команда «note» не работает.")
    sys.exit(1)
if sys.argv[1] == "quick-add":
    if os.environ.get("FAKE_ADD_BROKEN"):
        print("Нет ключа: Элвис кладёт его в ~/.trelvis-key", file=sys.stderr)
        sys.exit(1)
    number = 9900 + sum(1 for line in open(calls, encoding="utf-8") if '"quick-add"' in line)
    print("#%d dictatorik · очередь · через облако" % number)
    print("[#%d](https://trelvis.example/#t/%d)" % (number, number))
'''

FAKE_BUS = r'''
import json, os, sys
with open(os.environ["FAKE_CALLS"], "a", encoding="utf-8") as f:
    f.write(json.dumps(["bus"] + sys.argv[1:], ensure_ascii=False) + "\n")
'''


class Sandbox(unittest.TestCase):
    """Временная папка: журнал Диктатора, состояние, поддельные trelvis.py и rick_bus.py."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="shot-watch-"))
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.tmp)]))
        self.log = self.tmp / "dictatorik.log"
        self.state = self.tmp / "state" / "state.json"
        self.calls = self.tmp / "calls.jsonl"
        (self.tmp / "trelvis.py").write_text(FAKE_TRELVIS, encoding="utf-8")
        (self.tmp / "rick_bus.py").write_text(FAKE_BUS, encoding="utf-8")
        self.env = {"SHOT_WATCH_LOG": str(self.log), "SHOT_WATCH_STATE": str(self.state),
                    "SHOT_WATCH_TRELVIS": str(self.tmp / "trelvis.py"),
                    "SHOT_WATCH_BUS": str(self.tmp / "rick_bus.py"), "FAKE_CALLS": str(self.calls)}
        patch = mock.patch.dict(os.environ, self.env)
        patch.start()
        self.addCleanup(patch.stop)
        self.watch = load_watch(self.env)

    def use(self, *names):
        self.log.write_text("".join(n + "\n" for name in names for n in lines(name)), encoding="utf-8")

    def made(self):
        if not self.calls.exists():
            return []
        return [json.loads(x) for x in self.calls.read_text(encoding="utf-8").splitlines()]

    def saved(self):
        return json.loads(self.state.read_text(encoding="utf-8"))


class VerdictTest(Sandbox):
    """Исходы по эталонным кускам журнала."""

    def verdicts(self, name, now=None):
        return self.watch.parse(lines(name), now or ts("2026-10-20T00:00:00Z"))

    def test_sent(self):
        (shot,) = self.verdicts("sent.txt")
        self.assertEqual(shot["verdict"], "sent")
        self.assertEqual(shot["file"], "Снимок 2026-10-14 в 14.00.21-100001.png")

    def test_failed_reason_both_line_orders(self):
        # Строка отказа бывает и после «доставлен», и до него (исходное окно не подтверждается).
        got = [(x["verdict"], x["reason"]) for x in self.verdicts("failed.txt")]
        self.assertEqual(got, [("failed", "поле не вернулось в фокус"), ("failed", "поле не вернулось в фокус"),
                               ("failed", "исходное окно снимка больше не подтверждается"),
                               ("failed", "поле не вернулось в фокус")])

    def test_outside(self):
        (shot,) = self.verdicts("outside.txt")
        self.assertEqual((shot["verdict"], shot["reason"]), ("outside", "снят вне записи"))
        self.assertEqual(shot["detail"], "запись кончилась за 152 с до снимка, новая началась через 4 с после него")

    def test_alone_and_cancelled(self):
        # Отменённый снимок исхода не получает; снимок без записи рядом — не сбой.
        got = self.verdicts("alone.txt")
        self.assertEqual([x["verdict"] for x in got], ["alone"])
        self.assertEqual(got[0]["file"], "Снимок 2026-10-14 в 12.44.24-400001.png")

    def test_unknown(self):
        (shot,) = self.verdicts("unknown.txt")
        self.assertEqual(shot["verdict"], "unknown")
        self.assertIn("строк о вставке", shot["reason"])

    def test_every_recording_end_closes_recording(self):
        # Пустая запись, отмена, короткое нажатие, «без единого слова», ошибка разбора, выход Диктатора, запись
        # без конца дольше двух часов — снимки после них не «unknown»; конец ЧУЖОЙ записи нынешнюю не кончает.
        self.assertEqual([x["verdict"] for x in self.verdicts("ends.txt")], ["alone"] * 7 + ["unknown"])

    def test_too_early_to_judge(self):
        # На записи ждём строк вставки SETTLE_SEC; вне записи — старта записи NEAR_SEC.
        shot_t = ts("2026-10-14T09:00:07Z")
        self.assertEqual(self.verdicts("unknown.txt", now=shot_t + 5), [])
        alone = lines("alone.txt")[:10]
        self.assertEqual(self.watch.parse(alone, ts("2026-10-14T07:44:24Z") + 30), [])
        self.assertEqual([x["verdict"] for x in self.watch.parse(alone, ts("2026-10-14T07:44:24Z") + 120)],
                         ["alone"])


class TickTest(Sandbox):
    """Проход сторожа: задача, заметка, строка Рику, память о виденном."""

    def tick(self, now="2026-10-20T00:00:00Z", since=None, dry=False):
        return self.watch.tick(now=ts(now), since=ts(since) if since else None, dry=dry)

    def test_first_run_marks_history_seen(self):
        self.use("failed.txt", "unknown.txt")
        self.assertEqual(self.tick(), [])
        self.assertEqual(self.made(), [])
        self.assertEqual(len(self.saved()["seen"]), 5)
        self.assertEqual(self.tick(), [])

    def test_first_of_day_is_task_then_note(self):
        self.use("failed.txt")
        done = self.tick(since="2026-10-14T00:00:00Z")
        self.assertEqual(len(done), 4)
        self.assertTrue(done[0].startswith("задача #9901: 10:00:14 — поле не вернулось в фокус"), done[0])
        self.assertTrue(done[1].startswith("заметка в #9901: 11:00:13 — поле не вернулось в фокус"), done[1])
        self.assertTrue(done[2].startswith("задача #9902: 12:00:06 — исходное окно"), done[2])
        self.assertTrue(done[3].startswith("задача #9903: 10:00:12"), done[3])  # новый день — новая задача
        kinds = [(c[0], c[1]) for c in self.made()]
        self.assertEqual(kinds, [("trelvis", "quick-add"), ("bus", "tell"), ("trelvis", "note"),
                                 ("trelvis", "quick-add"), ("bus", "tell"), ("trelvis", "quick-add"), ("bus", "tell")])
        add = self.made()[0]
        self.assertEqual(add[add.index("--project") + 1], "dictatorik")
        self.assertEqual(add[add.index("--actor") + 1], "fable")
        self.assertIn("(14.10): поле не вернулось в фокус", add[2])
        note = self.made()[2]
        self.assertEqual(note[2], "9901")
        self.assertTrue(note[3].startswith("Снимок снова не вставился: 11:00:13"))
        self.assertIn("задача #9901 (Диктатор)", self.made()[1][-1])
        self.assertEqual(self.saved()["tasks"], {
            "2026-10-14": {"failed:поле не вернулось в фокус": 9901,
                           "failed:исходное окно снимка больше не подтверждается": 9902},
            "2026-10-15": {"failed:поле не вернулось в фокус": 9903}})
        self.assertEqual(self.tick(), [])  # всё уже видено — второй проход молчит
        self.assertEqual(len(self.made()), 7)

    def test_new_failure_after_first_run_goes_by_itself(self):
        head = lines("failed.txt")[:11]
        self.log.write_text("".join(x + "\n" for x in head), encoding="utf-8")
        self.assertEqual(self.tick(now="2026-10-14T10:30:00Z"), [])  # первый проход: снимок 10:00 — история
        self.assertEqual(self.made(), [])
        self.use("failed.txt")  # журнал дописался
        done = self.tick()
        self.assertEqual([x.split(":")[0] for x in done], ["задача #9901", "задача #9902", "задача #9903"])
        self.assertTrue(done[0].startswith("задача #9901: 11:00:13"), done)

    def test_good_shots_make_nothing(self):
        self.use("sent.txt", "alone.txt")
        self.assertEqual(self.tick(since="2026-10-14T00:00:00Z"), [])
        self.assertEqual(self.made(), [])

    def test_outside_and_unknown_are_failures(self):
        self.use("outside.txt", "unknown.txt")
        done = self.tick(since="2026-10-14T00:00:00Z")
        self.assertEqual([x.split(":")[0] for x in done], ["задача #9901", "задача #9902"])
        summaries = [c[c.index("--summary") + 1] for c in self.made() if c[1] == "quick-add"]
        self.assertIn("ShotShelf.beginRecordingSession", summaries[0])
        self.assertIn("goesToTheWindowNow", summaries[1])

    def test_note_refused_on_second_mac(self):
        self.use("failed.txt")
        with mock.patch.dict(os.environ, {"FAKE_NOTE_REFUSED": "1"}):
            done = self.tick(since="2026-10-14T00:00:00Z")
        self.assertTrue(done[1].startswith("заметка в #9901 не дописалась (⛔ Со второго Мака"), done[1])

    def test_task_not_created(self):
        self.use("unknown.txt")
        with mock.patch.dict(os.environ, {"FAKE_ADD_BROKEN": "1"}):
            done = self.tick(since="2026-10-14T00:00:00Z")
        self.assertEqual(len(done), 1)
        self.assertTrue(done[0].startswith("задача не завелась (Нет ключа"), done[0])
        self.assertEqual([c[0] for c in self.made()], ["trelvis"])  # Рику не о чем писать
        self.assertEqual(self.saved()["tasks"], {"2026-10-14": {}})

    def test_dry_writes_nothing(self):
        self.use("failed.txt")
        done = self.tick(since="2026-10-14T00:00:00Z", dry=True)
        self.assertTrue(done[0].startswith("задача: 🧠 🐞 Снимок экрана не вставился"), done[0])
        self.assertEqual(self.made(), [])
        self.assertFalse(self.state.exists())

    def test_old_days_forgotten(self):
        self.state.parent.mkdir(parents=True)
        old = {"2026-10-0%d" % d: {"failed:x": d} for d in range(1, 10)}
        self.state.write_text(json.dumps({"seen": [], "tasks": old}), encoding="utf-8")
        self.use("unknown.txt")
        self.tick()
        self.assertEqual(sorted(self.saved()["tasks"]), ["2026-10-0%d" % d for d in range(4, 10)] + ["2026-10-14"])

    def test_stat(self):
        self.use("sent.txt", "failed.txt", "outside.txt", "unknown.txt", "alone.txt")
        self.assertEqual(self.watch.stat(days=2), [
            "2026-10-14: вставлено 1, отказ 3, вне записи 1, без попытки на записи 1, просто снимков 1",
            "2026-10-15: вставлено 0, отказ 1, вне записи 0, без попытки на записи 0, просто снимков 0"])


class CommandLineTest(Sandbox):
    """«shot_watch.py scan» так, как его зовёт служба."""

    def scan(self, *args):
        env = dict(os.environ, TZ="UTC")
        return subprocess.run([sys.executable, str(WATCH), "scan"] + list(args), capture_output=True,
                              text=True, env=env, timeout=180)

    def test_quiet_is_silent_without_news(self):
        self.use("failed.txt")
        run = self.scan("--quiet")
        self.assertEqual((run.returncode, run.stdout, run.stderr), (0, "", ""))
        self.assertEqual(self.scan().stdout, "новых сбоев нет\n")

    def test_quiet_lines_have_time(self):
        self.use("failed.txt")
        run = self.scan("--quiet", "--since", "2026-10-15T00:00:00Z")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertRegex(run.stdout, r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d задача #9901: 10:00:12 — поле не вернулось")
        self.assertEqual(len(run.stdout.splitlines()), 1)


class PathsTest(unittest.TestCase):
    """trelvis.py и почта Рика — от HOME и корня проектов, а не от чужого Мака."""

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="shot-home-"))
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.home)]))
        self.env = {"HOME": str(self.home), "SHOT_WATCH_LOG": "", "SHOT_WATCH_STATE": "",
                    "SHOT_WATCH_TRELVIS": "", "SHOT_WATCH_BUS": ""}

    def test_default_root_is_home(self):
        watch = load_watch(self.env)
        root = self.home / "Projects"
        self.assertEqual(watch.TRELVIS, str(root / "TrelvisCom" / "trelvis.py"))
        self.assertEqual(watch.BUS, str(root / "Rick" / "tools" / "rick_bus.py"))
        self.assertEqual(watch.LOG, str(self.home / "Library/Application Support/Dictatorik/dictatorik.log"))
        self.assertEqual(watch.STATE, str(self.home / "Library/Application Support/MyClaude/shot-watch/state.json"))

    def test_projects_root_from_claude_json(self):
        config = self.home / "Library" / "Application Support" / "MyClaude" / "claude.json"
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({"projectsRoot": "~/Work"}), encoding="utf-8")
        watch = load_watch(self.env)
        self.assertEqual(watch.TRELVIS, str(self.home / "Work" / "TrelvisCom" / "trelvis.py"))
        self.assertEqual(watch.BUS, str(self.home / "Work" / "Rick" / "tools" / "rick_bus.py"))

    def test_no_foreign_home_in_source(self):
        self.assertNotIn("/Users/", WATCH.read_text(encoding="utf-8"))


FAKE_LAUNCHCTL = r'''#!/bin/sh
echo "$*" >> "$FAKE_LAUNCHCTL_CALLS"
case "$1" in
  print)
    [ -n "$FAKE_LAUNCHCTL_LOADED" ] || { echo "Could not find service in domain" >&2; exit 113; }
    printf '\tstate = not running\n\truns = 7\n\tlast exit code = 0\n' ;;
  bootstrap)
    [ -z "$FAKE_LAUNCHCTL_FAIL" ] || { echo "Bootstrap failed: 5: Input/output error" >&2; exit 5; } ;;
  bootout)
    [ -n "$FAKE_LAUNCHCTL_LOADED" ] || { echo "Boot-out failed: 3: No such process" >&2; exit 3; } ;;
esac
exit 0
'''


class ServiceTest(unittest.TestCase):
    """«pimp.py shot-watch install|uninstall|status» с поддельным launchctl и своей папкой LaunchAgents."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="shot-service-"))
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.tmp)]))
        fake = self.tmp / "launchctl"
        fake.write_text(FAKE_LAUNCHCTL, encoding="utf-8")
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
        self.agents = self.tmp / "LaunchAgents"
        self.plist = self.agents / "com.elvis.pimp.shotwatch.plist"
        self.calls = self.tmp / "launchctl.calls"
        (self.tmp / "pimp").mkdir()
        (self.tmp / "claude.json").write_text(json.dumps({"projectsRoot": str(self.tmp / "projects")}),
                                              encoding="utf-8")
        env = {"MYCLAUDE_PIMP_DIR": str(self.tmp / "pimp"), "SHOT_WATCH_AGENTS": str(self.agents),
               "SHOT_WATCH_LAUNCHCTL": str(fake), "FAKE_LAUNCHCTL_CALLS": str(self.calls),
               "SHOT_WATCH_LOG": str(self.tmp / "dictatorik.log"),
               "FAKE_LAUNCHCTL_LOADED": "", "FAKE_LAUNCHCTL_FAIL": ""}
        patch = mock.patch.dict(os.environ, env)
        patch.start()
        self.addCleanup(patch.stop)
        self.pimp = pimp_testlib.load_pimp("pimp_for_shot_watch_%d" % next(_names))

    def run_cli(self, *argv, **env):
        out = io.StringIO()
        with mock.patch.dict(os.environ, env), contextlib.redirect_stdout(out), \
                contextlib.redirect_stderr(io.StringIO()):
            code = self.pimp.main(["shot-watch"] + list(argv))
        return code, out.getvalue()

    def launchctl_calls(self):
        return self.calls.read_text(encoding="utf-8").splitlines() if self.calls.exists() else []

    def test_dry_shows_plist_and_touches_nothing(self):
        code, out = self.run_cli("install", "--dry")
        self.assertEqual(code, 0)
        body = plistlib.loads(out.encode("utf-8"))
        state = self.tmp / "shot-watch" / "state.json"
        self.assertEqual(body["Label"], "com.elvis.pimp.shotwatch")
        self.assertEqual(body["ProgramArguments"][1:], [str(WATCH), "scan", "--quiet"])
        self.assertEqual(body["StartInterval"], 60)
        self.assertTrue(body["RunAtLoad"])
        self.assertEqual(body["EnvironmentVariables"]["SHOT_WATCH_STATE"], str(state))
        self.assertEqual(body["StandardOutPath"], str(state.parent / "watch.log"))  # журнал рядом с состоянием
        self.assertEqual(body["StandardErrorPath"], body["StandardOutPath"])
        self.assertFalse(self.agents.exists())
        self.assertEqual(self.launchctl_calls(), [])

    def test_dry_only_with_install(self):
        self.assertEqual(self.run_cli("status", "--dry"), (1, "Ключ --dry — только с install\n"))

    def test_install_writes_plist_and_bootstraps(self):
        code, out = self.run_cli("install")
        self.assertEqual(code, 0, out)
        self.assertTrue(out.startswith("Сторож снимков включён: раз в 60 с"), out)
        self.assertIn("журнала Диктатора пока нет", out)
        self.assertIn("TrelvisCom/trelvis.py — задачи заводить нечем", out)
        self.assertEqual(plistlib.loads(self.plist.read_bytes())["Label"], "com.elvis.pimp.shotwatch")
        self.assertTrue((self.tmp / "shot-watch").is_dir())
        uid = os.getuid()
        self.assertEqual(self.launchctl_calls(), [
            "bootout gui/%d/com.elvis.pimp.shotwatch" % uid,
            "bootstrap gui/%d %s" % (uid, self.plist)])

    def test_install_failure_leaves_nothing(self):
        code, out = self.run_cli("install", FAKE_LAUNCHCTL_FAIL="1")
        self.assertEqual((code, out), (1, "Сторож снимков не включился: launchctl — Bootstrap failed: 5: "
                                          "Input/output error\n"))
        self.assertFalse(self.plist.exists())

    def test_status(self):
        self.assertEqual(self.run_cli("status"),
                         (1, "Сторож снимков не стоит — включить: python3 tools/pimp.py shot-watch install\n"))
        self.run_cli("install")
        code, out = self.run_cli("status")
        self.assertEqual(code, 1)
        self.assertIn("файл службы есть, launchd его не знает", out)
        state = self.tmp / "shot-watch" / "state.json"
        today = time.strftime("%Y-%m-%d")
        state.write_text(json.dumps({"seen": [], "tasks": {today: {"failed:a": 9901, "outside:b": 9902}}}),
                         encoding="utf-8")
        code, out = self.run_cli("status", FAKE_LAUNCHCTL_LOADED="1")
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith("Сторож снимков стоит: раз в 60 с, проходов 7, последний выход 0; "
                                       "сегодня задачи #9901, #9902; журнал — "), out)

    def test_uninstall(self):
        self.assertEqual(self.run_cli("uninstall"), (0, "Сторож снимков и так не стоит\n"))
        self.run_cli("install")
        code, out = self.run_cli("uninstall", FAKE_LAUNCHCTL_LOADED="1")
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith("Сторож снимков снят; состояние и журнал остались в"), out)
        self.assertFalse(self.plist.exists())
        self.assertEqual(self.launchctl_calls()[-1], "bootout gui/%d/com.elvis.pimp.shotwatch" % os.getuid())

    def test_bad_op(self):
        code, out = self.run_cli("start")
        self.assertEqual(code, 1)
        self.assertIn("Не понял команду", out)


if __name__ == "__main__":
    unittest.main()
