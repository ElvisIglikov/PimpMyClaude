#!/usr/bin/env python3
"""Тесты CLI «Пимп» (WF36, раскладки — WF21 и WF41): tools/pimp.py против эталонов канала.

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
    """Приложение на минималках: взял первый запрос — ответил по образцу.

    `beats` — сколько раз перезаписать <id>.taken перед ответом с паузой
    `beat_s`: так приложение показывает, что открывает окна раскладки по одному
    (heartbeat WF41), и CLI обязан ждать дальше.
    """

    def __init__(self, directory: Path, result: dict, taken: bool = True,
                 beats: int = 0, beat_s: float = 0.0):
        super().__init__(daemon=True)
        self.dir = Path(directory)
        self.result = result
        self.taken = taken
        self.beats = beats
        self.beat_s = beat_s
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
                mark = self.dir / f"{request['id']}.taken"
                if self.taken:
                    mark.write_text("", encoding="utf-8")
                for _ in range(self.beats):
                    if self._stop.wait(self.beat_s):
                        return
                    mark.write_text("", encoding="utf-8")   # окно открыто, живы
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

    def call(self, *argv, result=None, session=CHAT, taken=True, wait="5", silent="2",
             beats=0, beat_s=0.0):
        if result is not None:
            self.dir.mkdir(parents=True, exist_ok=True)
            self.app = FakeApp(self.dir, result, taken=taken, beats=beats, beat_s=beat_s)
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

    def test_arrange_request_layout(self):
        # Раскладка едет тем же полем и не двигает порядок ключей (WF21).
        self.call("arrange", "--layout", "5x2", result=fixture("arrange.result.json"))
        self.assertEqual(list(self.app.requests[0].keys()),
                         list(fixture("arrange.request.json").keys()))
        self.assertEqual(self.app.requests[0]["layout"], "5x2")

    def test_arrange_order_request(self):
        # Порядок проектов едет как дали — именами и путями вперемешку (WF41).
        order = "/Users/elvis/_ElvisProjects/VkusnoffKz, SkilZZZ ,/Users/elvis/_ElvisProjects/Dictator"
        self.call("arrange", "--layout", "5", "--order", order,
                  result=fixture("arrange-order.result.json"))
        request = self.app.requests[0]
        sample = fixture("arrange-order.request.json")
        self.assertEqual(list(request.keys()), list(sample.keys()), "порядок полей запроса")
        self.assertEqual(request["order"], sample["order"])

    def test_projects_request(self):
        self.call("projects", result=fixture("projects.result.json"))
        self.assertEqual(list(self.app.requests[0].keys()),
                         list(fixture("projects.request.json").keys()))

    def test_projects_status_request(self):
        # Ключ status есть, только когда просили сводку.
        self.call("projects", "--status", result=fixture("projects-status.result.json"))
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()),
                         list(fixture("projects-status.request.json").keys()))
        self.assertIs(request["status"], True)

    def test_layouts_request(self):
        self.call("layouts", result=fixture("layouts.result.json"))
        self.assertEqual(list(self.app.requests[0].keys()),
                         list(fixture("layouts.request.json").keys()))
        self.assertEqual(self.app.requests[0]["action"], "layouts")

    def test_layout_save_request(self):
        self.call("layout", "save", "Утро", result=fixture("layout-save.result.json"))
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()),
                         list(fixture("layout-save.request.json").keys()))
        self.assertEqual(request["action"], "layout-save")
        self.assertEqual(request["name"], "Утро")

    def test_layout_restore_request(self):
        self.call("layout", "restore", "Утро", result=fixture("layout-restore.result.json"))
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()),
                         list(fixture("layout-restore.request.json").keys()))
        self.assertEqual(request["action"], "layout-restore")
        self.assertIs(request["fresh"], False)

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

    def test_open_without_cell(self):
        # Ячейки в раскладке не нашлось — про «посередине» молчим: окно поверх.
        answer = dict(fixture("new-window.result.json"))
        answer["skipped"] = 1
        done = self.call("open", "Dictator", "--at", "middle", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(),
                         "Окно открыл, но в раскладке места нет — оставил поверх")

    def test_project_missing(self):
        done = self.call("open", "Диктатор", result=fixture("new-window.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertIn("Не нашёл проект «Диктатор»", done.stdout)
        self.assertIn("PimpMyClaude, VkusnoffKz, Dictator, SkilZZZ", done.stdout)

    def test_busy(self):
        done = self.call("open", "Dictator", result=fixture("busy.result.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Пимп занят — открывает или возвращает окна")

    def test_bad_request(self):
        done = self.call("arrange", result=fixture("bad.result.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Пимп не понял запрос")

    def test_arrange_ok(self):
        done = self.call("arrange", result=fixture("arrange.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Расставил 3 окна на главном экране: как сейчас (лента)")

    def test_arrange_layout_and_skipped(self):
        # Просили «как в прошлый раз» — называем ту раскладку, что применилась.
        answer = dict(fixture("arrange.result.json"))
        answer["layout"] = "5"
        answer["skipped"] = 2
        done = self.call("arrange", "--layout", "last", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["layout"], "last")
        self.assertEqual(done.stdout.strip(),
                         "Расставил 3 окна на главном экране: пять в ряд, 2 не тронул — ячеек нет")

    def test_arrange_too_small(self):
        # Тесно не окну, а раскладке: текст «Мало места…» тут не годится.
        answer = dict(fixture("bad.result.json"))
        answer["error"] = "too-small"
        done = self.call("arrange", "--layout", "5", result=answer)
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(),
                         "Экран мал: столько окон в эту раскладку не влезает — "
                         "сделай окна уже или выбери другую раскладку")

    def test_arrange_order_ok(self):
        # Кто встал первым, чьих окон не нашлось и сколько уехало в хвост.
        order = ("/Users/elvis/_ElvisProjects/VkusnoffKz,SkilZZZ,"
                 "/Users/elvis/_ElvisProjects/Dictator")
        done = self.call("arrange", "--layout", "5", "--order", order,
                         result=fixture("arrange-order.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(),
                         "Расставил 3 окна на главном экране: пять в ряд — сперва "
                         "VkusnoffKz; не нашёл окна: SkilZZZ, Dictator; "
                         "1 без папки — в хвосте")

    def test_layouts_ok(self):
        done = self.call("layouts", result=fixture("layouts.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(),
                         "Раскладки: Утро — пять в ряд, 2 окна · "
                         "Разбор — как сейчас (лента), 3 окна")

    def test_layouts_empty(self):
        answer = dict(fixture("layouts.result.json"))
        answer["layouts"] = []
        done = self.call("layouts", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(),
                         "Раскладок пока нет — скажи «запомни раскладку как …»")

    def test_layout_save_ok(self):
        done = self.call("layout", "save", "Утро", result=fixture("layout-save.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Запомнил раскладку «Утро»: пять в ряд, 2 окна")

    def test_layout_save_chat_unknown(self):
        # Чат окна неизвестен — запоминать нечего, и Элвису сказано, что включить.
        done = self.call("layout", "save", "Утро", result=fixture("layout-save.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(),
                         "Не могу запомнить: не знаю, какой чат в окне «Диктаторик» — "
                         "включи «Цвет по проекту» в меню Пимпа или подожди минуту")

    def test_layout_restore_ok(self):
        done = self.call("layout", "restore", "Утро",
                         result=fixture("layout-restore.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(),
                         "Вернул «Утро»: 1 стояло, 1 открыл; не нашёл чат: Диктаторик")

    def test_layout_restore_fresh(self):
        # «Новые чаты по Утру»: чатов из раскладки не ищем, потерянных нет.
        answer = dict(fixture("layout-restore.result.json"))
        answer["placed"] = 0
        answer["opened"] = 2
        answer["missing"] = []
        done = self.call("layout", "restore", "Утро", "--new", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIs(self.app.requests[0]["fresh"], True)
        self.assertEqual(done.stdout.strip(), "Открыл новые чаты по раскладке «Утро»: 2")

    def test_layout_missing(self):
        done = self.call("layout", "restore", "Вечер",
                         result=fixture("layout-restore.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Раскладки «Вечер» нет, есть: Утро, Разбор")

    def test_projects_ok(self):
        done = self.call("projects", result=fixture("projects.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Проекты: PimpMyClaude, VkusnoffKz")

    def test_projects_status_ok(self):
        # Со сводкой — строка на проект: счёт воркфлоу и открытые окна.
        done = self.call("projects", "--status", result=fixture("projects-status.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip().splitlines(),
                         ["PimpMyClaude — 41 воркфлоу · 27 готово · Сейчас: WF21 кодится "
                          "· окна: Claude",
                          "VkusnoffKz — без сводки · окна: VkusnoffKz 3"])

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

    def test_wait_counted_from_heartbeat(self):
        # Раскладка открывает окна по одному и после каждого бьёт <id>.taken:
        # ждём от последнего удара, иначе сдались бы на первом окне (WF41).
        done = self.call("layout", "restore", "Утро",
                         result=fixture("layout-restore.result.json"),
                         beats=4, beat_s=0.25, wait="0.5")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("Вернул «Утро»", done.stdout)

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
