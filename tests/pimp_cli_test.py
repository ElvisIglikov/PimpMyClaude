#!/usr/bin/env python3
"""Тесты CLI «Пимп» (WF36): tools/pimp.py против эталонов канала.

Приложения тут нет — вместо него нитка FakeApp: она ловит запрос в подставном
каталоге (MYCLAUDE_PIMP_DIR), помечает его <id>.taken и кладёт рядом ответ,
собранный из tests/fixtures/pimp/*.result.json. Проверяем ровно две вещи:
что CLI пишет в канал (имена, типы и ПОРЯДОК полей — по фикстурам запросов) и
что он говорит Элвису на ответ приложения (строка и код возврата).

Запуск: python3 -m unittest tests/pimp_cli_test.py (строка в tools/test.sh).
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools" / "pimp.py"
FIXTURES = ROOT / "tests" / "fixtures" / "pimp"
ID_RE = re.compile(r"^\d{13,}-\d{4}$")
CHAT = "local_5265171a-0ab8-4472-b4e5-40604a36ef6e"


def fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class FakeApp(threading.Thread):
    """Приложение на минималках: взял первый запрос — ответил по образцу."""

    def __init__(self, directory: Path, result: dict, taken: bool = True):
        super().__init__(daemon=True)
        self.dir = Path(directory)
        self.result = result
        self.taken = taken
        self.requests = []
        self.paths = []
        self._stop = threading.Event()

    def run(self):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and not self._stop.is_set():
            for path in sorted(self.dir.glob("*.json")):
                if path.name.startswith(".") or path.name.endswith(".result.json"):
                    continue
                try:
                    text = path.read_text(encoding="utf-8")
                    request = json.loads(text)
                except (OSError, ValueError):
                    continue
                self.requests.append(request)
                self.paths.append(path)
                if self.taken:
                    (self.dir / f"{request['id']}.taken").write_text("", encoding="utf-8")
                answer = dict(self.result)
                answer["id"] = request["id"]
                body = json.dumps(answer, ensure_ascii=False, separators=(",", ":")) + "\n"
                (self.dir / f"{request['id']}.result.json").write_text(body, encoding="utf-8")
                return
            time.sleep(0.01)

    def stop(self):
        self._stop.set()


class PimpCliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.support = Path(self.tmp.name)          # подставной MyClaude/
        self.dir = self.support / "pimp"
        self.addCleanup(self.tmp.cleanup)
        self.app = None

    def tearDown(self):
        if self.app is not None:
            self.app.stop()
            self.app.join(timeout=2)

    def call(self, *argv, result=None, session=CHAT, taken=True, wait="5", silent="2"):
        if result is not None:
            self.dir.mkdir(parents=True, exist_ok=True)
            self.app = FakeApp(self.dir, result, taken=taken)
            self.app.start()
        env = dict(os.environ)
        env["MYCLAUDE_PIMP_DIR"] = str(self.dir)
        env["MYCLAUDE_PIMP_WAIT"] = wait
        env["MYCLAUDE_PIMP_TAKEN"] = silent
        env.pop("CLAUDE_CODE_HOST_SESSION_ID", None)
        if session is not None:
            env["CLAUDE_CODE_HOST_SESSION_ID"] = session
        done = subprocess.run([sys.executable, str(CLI), *argv], env=env,
                              capture_output=True, text=True, timeout=30)
        if self.app is not None:
            self.app.join(timeout=2)
        return done

    # ---- запрос: имена, типы и порядок полей ------------------------------
    def test_request_matches_fixture(self):
        done = self.call("open", "Dictator", "--at", "middle",
                         result=fixture("new-window.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        sample = fixture("new-window.request.json")
        self.assertEqual(list(request.keys()), list(sample.keys()), "порядок полей запроса")
        self.assertTrue(ID_RE.match(request["id"]), request["id"])
        self.assertRegex(request["at"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        self.assertEqual(request["action"], "new-window")
        self.assertEqual(request["from"], CHAT)
        self.assertEqual(request["project"], "Dictator")
        self.assertEqual(request["place"], "middle")
        self.assertEqual(oct(self.app.paths[0].stat().st_mode & 0o777), oct(0o600))

    def test_request_without_session(self):
        done = self.call("windows", result=fixture("windows.result.json"), session=None)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["from"], "")

    def test_arrange_request(self):
        self.call("arrange", result=fixture("arrange.result.json"))
        self.assertEqual(list(self.app.requests[0].keys()),
                         list(fixture("arrange.request.json").keys()))
        self.assertEqual(self.app.requests[0]["layout"], "row")

    def test_projects_request(self):
        self.call("projects", result=fixture("projects.result.json"))
        self.assertEqual(list(self.app.requests[0].keys()),
                         list(fixture("projects.request.json").keys()))

    # ---- что Пимп говорит на ответ ----------------------------------------
    def test_open_ok(self):
        done = self.call("open", "Dictator", "--at", "middle",
                         result=fixture("new-window.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Открыл Диктаторик посередине")

    def test_open_below_without_chat(self):
        answer = dict(fixture("new-window.result.json"))
        answer["fromResolved"] = False
        done = self.call("open", "Dictator", "--at", "below", result=answer, session=None)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("справа", done.stdout)
        self.assertIn("своего чата не нашёл", done.stdout)

    def test_open_without_color(self):
        answer = dict(fixture("new-window.result.json"))
        answer["layers"] = ""
        done = self.call("open", "Dictator", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("цвет не встал", done.stdout)

    def test_project_missing(self):
        done = self.call("open", "Диктатор", result=fixture("new-window.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertIn("Не нашёл проект «Диктатор»", done.stdout)
        self.assertIn("PimpMyClaude, VkusnoffKz, Dictator, SkilZZZ", done.stdout)

    def test_busy(self):
        done = self.call("open", "Dictator", result=fixture("busy.result.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Пимп занят — открывает предыдущее окно")

    def test_bad_request(self):
        done = self.call("arrange", result=fixture("bad.result.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Пимп не понял запрос")

    def test_arrange_ok(self):
        done = self.call("arrange", result=fixture("arrange.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Расставил 3 окна на главном экране")

    def test_projects_ok(self):
        done = self.call("projects", result=fixture("projects.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Проекты: PimpMyClaude, VkusnoffKz")

    def test_windows_ok_with_minimized(self):
        done = self.call("windows", result=fixture("windows.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(),
                         "Окон 1: Claude, одно окно свёрнуто — не считал")

    def test_json_prints_raw(self):
        done = self.call("--json", "windows", result=fixture("windows.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(json.loads(done.stdout)["minimized"], 1)
        self.assertNotIn("Окон 1", done.stdout, "--json печатает только сырой ответ")

    def test_json_after_command(self):
        done = self.call("windows", "--json", result=fixture("windows.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(json.loads(done.stdout)["ok"], True)

    # ---- приложение молчит и probe.js занят --------------------------------
    def test_not_running(self):
        done = self.call("arrange", silent="0.3", wait="5")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Пимп не запущен")

    def test_taken_but_silent(self):
        # Метка взятия есть, ответа нет: это уже не «не запущен», а «завис».
        self.dir.mkdir(parents=True, exist_ok=True)

        def mark():
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                for path in self.dir.glob("*.json"):
                    if path.name.startswith(".") or path.name.endswith(".result.json"):
                        continue
                    (self.dir / f"{path.stem}.taken").write_text("", encoding="utf-8")
                    return
                time.sleep(0.01)

        worker = threading.Thread(target=mark, daemon=True)
        worker.start()
        done = self.call("arrange", silent="0.3", wait="1.2")
        worker.join(timeout=2)
        self.assertEqual(done.returncode, 1)
        self.assertIn("не ответил", done.stdout)

    def test_probe_warning(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        (self.support / "probe.js").write_text("window.__myclaude.status()\n", encoding="utf-8")
        done = self.call("windows", result=fixture("windows.result.json"))
        self.assertEqual(done.returncode, 0)
        self.assertIn("probe.js", done.stderr)

    def test_probe_of_app_is_quiet(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        (self.support / "probe.js").write_text(
            "// myclaude-chats v1 42\nwindow.__myclaude.chats({})\n", encoding="utf-8")
        done = self.call("windows", result=fixture("windows.result.json"))
        self.assertEqual(done.returncode, 0)
        self.assertEqual(done.stderr.strip(), "")

    def test_bad_place(self):
        # Кодов ровно два: ругань argparse (её 2) сведена к 1 и строке по-русски.
        done = self.call("open", "Dictator", "--at", "куда-нибудь")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Не понял команду", done.stdout)
        self.assertIn("left, middle, right", done.stderr)


if __name__ == "__main__":
    unittest.main()
