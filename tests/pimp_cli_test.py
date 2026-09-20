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
# Подставной ключ: он обязан не попасть ни в вывод, ни в журнал (WF75).
SECRET = "sk-this-key-must-not-leak"


def fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class FakeApp(threading.Thread):
    """Приложение на минималках: взял запрос — ответил по образцу.

    `beats` — сколько раз перезаписать <id>.taken перед ответом с паузой
    `beat_s`: так приложение показывает, что открывает окна раскладки по одному
    (heartbeat WF41), и CLI обязан ждать дальше.
    `result` списком и `count` больше единицы — разговор на несколько запросов
    подряд: так идёт голосовая фраза (WF75), где шагов несколько, а первым
    уходит `projects`. Кончились образцы — отвечаем последним.
    """

    def __init__(self, directory: Path, result, taken: bool = True,
                 beats: int = 0, beat_s: float = 0.0, count: int = 1):
        super().__init__(daemon=True)
        self.dir = Path(directory)
        self.results = list(result) if isinstance(result, list) else [result]
        self.taken = taken
        self.beats = beats
        self.beat_s = beat_s
        self.count = count
        self.requests = []
        self.paths = []
        self.seen = set()
        self._stop = threading.Event()

    def run(self):
        deadline = time.monotonic() + 20
        served = 0
        while time.monotonic() < deadline and not self._stop.is_set():
            for path in sorted(self.dir.glob("*.json")):
                if path.name.startswith(".") or path.name.endswith(".result.json"):
                    continue
                try:
                    text = path.read_text(encoding="utf-8")
                    request = json.loads(text)
                except (OSError, ValueError):
                    continue
                if request["id"] in self.seen:
                    continue
                self.seen.add(request["id"])
                self.requests.append(request)
                self.paths.append(path)
                mark = self.dir / f"{request['id']}.taken"
                if self.taken:
                    mark.write_text("", encoding="utf-8")
                for _ in range(self.beats):
                    if self._stop.wait(self.beat_s):
                        return
                    mark.write_text("", encoding="utf-8")   # окно открыто, живы
                answer = dict(self.results[min(served, len(self.results) - 1)])
                answer["id"] = request["id"]
                body = json.dumps(answer, ensure_ascii=False, separators=(",", ":")) + "\n"
                (self.dir / f"{request['id']}.result.json").write_text(body, encoding="utf-8")
                served += 1
                if served >= self.count:
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
             beats=0, beat_s=0.0, count=None, extra=None):
        if result is not None:
            self.dir.mkdir(parents=True, exist_ok=True)
            if count is None:
                count = len(result) if isinstance(result, list) else 1
            self.app = FakeApp(self.dir, result, taken=taken, beats=beats, beat_s=beat_s,
                               count=count)
            self.app.start()
        env = dict(os.environ)
        env["MYCLAUDE_PIMP_DIR"] = str(self.dir)
        env["MYCLAUDE_PIMP_WAIT"] = wait
        env["MYCLAUDE_PIMP_TAKEN"] = silent
        # Ключ Элвиса лежит на его же Маке (0600): ни один тест не смеет попасть в
        # настоящий файл и в настоящий DeepSeek — оба пути уводим в tmp (WF75).
        env["MYCLAUDE_VOICE_ENV"] = str(self.support / "pimp-voice.env")
        env["MYCLAUDE_DOWNLOADS"] = str(self.support / "Downloads")
        env.pop("MYCLAUDE_VOICE_FAKE", None)
        env.pop("CLAUDE_CODE_HOST_SESSION_ID", None)
        if session is not None:
            env["CLAUDE_CODE_HOST_SESSION_ID"] = session
        env.update(extra or {})
        done = subprocess.run([sys.executable, str(CLI), *argv], env=env,
                              capture_output=True, text=True, timeout=60)
        if self.app is not None:
            self.app.join(timeout=2)
        return done

    # ---- голос (WF75): подставной мозг и подставные загрузки ----------------
    def brain(self, answer: dict) -> str:
        """Готовый ответ модели на диске: MYCLAUDE_VOICE_FAKE = ни ключа, ни сети."""
        path = self.support / "brain.json"
        path.write_text(json.dumps(answer, ensure_ascii=False), encoding="utf-8")
        return str(path)

    def voice(self, phrase: str, answer: dict, results: list, extra=None, **kwargs):
        env = {"MYCLAUDE_VOICE_FAKE": self.brain(answer)}
        env.update(extra or {})
        return self.call("say", phrase, result=results, extra=env, **kwargs)

    def shots(self, ages, suffix=".jpeg"):
        """Фотки в подставных загрузках: ages — сколько секунд назад легла каждая."""
        folder = self.support / "Downloads"
        folder.mkdir(parents=True, exist_ok=True)
        now = time.time()
        made = []
        for number, age in enumerate(ages):
            path = folder / f"IMG_{number:04d}{suffix}"
            path.write_bytes(b"jpeg")
            os.utime(path, (now - age, now - age))
            made.append(path)
        return made

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
        # Голая «расставить» едет «last» — умным путём приложения, а не подменяет его
        # лентой: иначе выбор Элвиса плиткой стирается молча (#5745, WF77).
        self.call("arrange", result=fixture("arrange.result.json"))
        self.assertEqual(list(self.app.requests[0].keys()),
                         list(fixture("arrange.request.json").keys()))
        self.assertEqual(self.app.requests[0]["layout"], "last")

    def test_arrange_request_row_asked(self):
        # «Как сейчас» по-прежнему лента — но только когда её попросили словом.
        self.call("arrange", "--layout", "row", result=fixture("arrange.result.json"))
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
        # Голая «расставь» — умный путь (WF77): в ответе `row`, но лентой это не
        # называем, говорим, что стоящие окна остались на месте.
        done = self.call("arrange", result=fixture("arrange.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Расставил 3 окна: стоящие на месте не трогал")

    def test_arrange_row_asked_ok(self):
        # Ленту попросили словом — слова прежние: это другое поведение, и Элвис
        # должен видеть, что вышло именно оно.
        done = self.call("arrange", "--layout", "row", result=fixture("arrange.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Расставил 3 окна на экране, где стоят окна: как сейчас (лента)")

    def test_arrange_smart_order(self):
        # Умный путь с порядком проектов: хвост про «сперва» остаётся (WF41).
        order = "/Users/elvis/_ElvisProjects/VkusnoffKz,SkilZZZ"
        answer = dict(fixture("arrange-order.result.json"))
        answer["layout"] = "row"
        answer["missing"] = []
        answer["unknown"] = 0
        done = self.call("arrange", "--order", order, result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["layout"], "last")
        self.assertEqual(done.stdout.strip(),
                         "Расставил 3 окна: стоящие на месте не трогал — сперва VkusnoffKz, SkilZZZ")

    def test_arrange_layout_and_skipped(self):
        # Ответ назвал плитку — называем её словами (умного пути тут нет).
        answer = dict(fixture("arrange.result.json"))
        answer["layout"] = "5"
        answer["skipped"] = 2
        done = self.call("arrange", "--layout", "last", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["layout"], "last")
        self.assertEqual(done.stdout.strip(),
                         "Расставил 3 окна на экране, где стоят окна: пять в ряд, 2 не тронул — ячеек нет")

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
                         "Расставил 3 окна на экране, где стоят окна: пять в ряд — сперва "
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

    def test_layout_save_not_arranged(self):
        # Окна стоят не по сетке — запоминать нечего, и Пимп говорит, что делать (#5728).
        answer = dict(fixture("bad.result.json"))
        answer["error"] = "not-arranged"
        done = self.call("layout", "save", "Проба", result=answer)
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(),
                         "Окна стоят не по сетке — сперва расставь их, "
                         "потом запоминай раскладку")

    def test_no_windows_names_minimized(self):
        # Свёрнутые окна приложение не видит: «Claude не запущен» при живом Claude — ложь
        # (#5746). Строка называет все три причины и говорит, что сделать.
        answer = dict(fixture("bad.result.json"))
        answer["error"] = "no-windows"
        done = self.call("arrange", result=answer)
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(),
                         "Claude не запущен, окон нет или все свёрнуты — разверни окно")

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

    # ---- WF75: последний чат, закрытие, вставка, плашка --------------------
    def test_open_last_request(self):
        done = self.call("open", "TrelvisCom", "--last",
                         result=fixture("new-window-last.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()),
                         list(fixture("new-window-last.request.json").keys()))
        self.assertEqual(request["chat"], "last")
        self.assertEqual(done.stdout.strip(), "Открыл Дубли задач справа")

    def test_open_last_raised(self):
        # Чат уже был открыт окном — окно подняли, а не открыли: «открыл» тут ложь.
        answer = dict(fixture("new-window-last.result.json"))
        answer["opened"] = False
        done = self.call("open", "TrelvisCom", "--last", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Поднял Дубли задач справа")

    def test_open_without_last_has_no_chat(self):
        self.call("open", "TrelvisCom", result=fixture("new-window.result.json"))
        self.assertNotIn("chat", self.app.requests[0])

    def test_chat_missing(self):
        done = self.call("open", "TrelvisCom", "--last",
                         result=fixture("new-window-last.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(),
                         "Последнего чата в этом проекте нет — открой новый")

    def test_close_request(self):
        done = self.call("close", "TrelvisCom", result=fixture("close-window.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(list(self.app.requests[0].keys()),
                         list(fixture("close-window.request.json").keys()))
        self.assertEqual(self.app.requests[0]["action"], "close-window")
        self.assertEqual(done.stdout.strip(), "Закрыл окно «Дубли задач»")

    def test_close_ambiguous(self):
        # Двусмысленность — отказ без движения: закрыть не то окно дороже вопроса.
        done = self.call("close", "TrelvisCom", result=fixture("close-window.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(),
                         "Окон проекта несколько («Дубли задач», «Бот: голос») — "
                         "скажи, какое именно, я ничего не трогал")

    def test_close_main_window(self):
        done = self.call("close", "TrelvisCom",
                         result=fixture("close-window-main.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Это главное окно Claude — его я не закрываю")

    def test_paste_clipboard_front(self):
        done = self.call("paste-clipboard", result=fixture("paste-clipboard.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), ["id", "at", "action", "from", "front"])
        self.assertIs(request["front"], True)
        self.assertEqual(done.stdout.strip(),
                         "Вставил из буфера в «Сайт: корзина» — жми Enter")

    def test_paste_clipboard_project(self):
        done = self.call("paste-clipboard", "--project", "VkusnoffKz",
                         result=fixture("paste-clipboard.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()),
                         list(fixture("paste-clipboard.request.json").keys()))
        self.assertEqual(request["project"], "VkusnoffKz")
        self.assertNotIn("front", request)

    def test_paste_bad_request(self):
        done = self.call("paste-clipboard", result=fixture("paste.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Пимп не понял запрос")

    def test_paste_airdrop_batch(self):
        # Эйрдроп кладёт пачку подряд: берём её целиком, а лежавшую до неё фотку
        # (разрыв больше двух минут) не трогаем. Не картинка — не в счёт.
        self.shots([600, 20, 14, 8])
        self.shots([5], suffix=".txt")
        done = self.call("paste-airdrop", result=fixture("paste.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(fixture("paste.request.json").keys()))
        self.assertIs(request["front"], True)
        self.assertEqual([Path(path).name for path in request["paths"]],
                         ["IMG_0001.jpeg", "IMG_0002.jpeg", "IMG_0003.jpeg"])
        self.assertEqual(done.stdout.strip(),
                         "Вставил 2 файла в «Сайт: корзина» — жми Enter")

    def test_paste_airdrop_limit(self):
        self.shots([300 - 10 * number for number in range(25)])
        done = self.call("paste-airdrop", result=fixture("paste.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        names = [Path(path).name for path in self.app.requests[0]["paths"]]
        self.assertEqual(len(names), 20)
        self.assertEqual([names[0], names[-1]], ["IMG_0005.jpeg", "IMG_0024.jpeg"])

    def test_paste_airdrop_stale(self):
        # Вся пачка старше получаса — это не «сейчас скинул»: молча тащить нельзя.
        self.shots([4000, 3900])
        done = self.call("paste-airdrop")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Свежих фоток нет", done.stdout)

    def test_paste_airdrop_remembers(self):
        self.shots([20, 10])
        done = self.call("paste-airdrop", result=fixture("paste.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        mark = json.loads((self.support / "voice-pasted.json").read_text(encoding="utf-8"))
        self.assertIsInstance(mark["mtime"], float)
        again = self.call("paste-airdrop", result=fixture("paste.result.json"))
        self.assertEqual(again.returncode, 1)
        self.assertIn("Новых фоток нет", again.stdout)

    def test_hud_request(self):
        sample = fixture("hud.request.json")
        done = self.call("hud", sample["text"], result=fixture("hud.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(sample.keys()))
        self.assertEqual(request["text"], sample["text"])
        self.assertEqual(done.stdout.strip(), "Показал плашку")

    def test_hud_cuts_long_text(self):
        self.call("hud", "я" * 300, result=fixture("hud.result.json"))
        self.assertEqual(len(self.app.requests[0]["text"]), 200)

    # ---- WF75: голос ------------------------------------------------------
    def test_say_fake_touches_neither_key_nor_net(self):
        # Ключ на месте и адрес заведомо мёртвый: раз фраза прошла, ни файла, ни
        # сети мозг не касался — проверка MYCLAUDE_VOICE_FAKE стоит ДО ключа.
        (self.support / "pimp-voice.env").write_text(
            f"DEEPSEEK_API_KEY={SECRET}\nDEEPSEEK_BASE_URL=http://127.0.0.1:1\n",
            encoding="utf-8")
        done = self.voice("что открыто", {"steps": [{"action": "windows"}], "say": "Смотрю"},
                          [fixture("projects.result.json"), fixture("windows.result.json"),
                           fixture("hud.result.json")])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("Окон 1", done.stdout)
        log = (self.support / "voice-log.jsonl").read_text(encoding="utf-8")
        self.assertNotIn(SECRET, log, "ключ в журнал не пишется никогда")
        record = json.loads(log.splitlines()[-1])
        self.assertEqual(record["phrase"], "что открыто")
        self.assertEqual(record["model"], "fake")
        self.assertEqual(oct((self.support / "voice-log.jsonl").stat().st_mode & 0o777),
                         oct(0o600))

    def test_say_without_fake_reads_key(self):
        # Тот же ключ и тот же мёртвый адрес, но без подставного ответа — значит
        # ключ прочитан и в сеть Пимп пошёл (и честно сказал, что не дозвонился).
        # Заодно единственная проверка, что tools/voice_prompt.md читается: без него
        # строка была бы другой — промпт собирается ДО запроса.
        (self.support / "pimp-voice.env").write_text(
            f"DEEPSEEK_API_KEY={SECRET}\nDEEPSEEK_BASE_URL=http://127.0.0.1:1\n",
            encoding="utf-8")
        done = self.call("say", "что открыто",
                         result=[fixture("projects.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 1)
        self.assertIn("DeepSeek не ответил", done.stdout)
        self.assertNotIn(SECRET, done.stdout + done.stderr)

    def test_say_key_not_latin(self):
        # Кривой ключ валил CLI трассой: Диктатору с его stdout это мусор.
        (self.support / "pimp-voice.env").write_text(
            "DEEPSEEK_API_KEY=ключ\nDEEPSEEK_BASE_URL=http://127.0.0.1:1\n",
            encoding="utf-8")
        done = self.call("say", "что открыто",
                         result=[fixture("projects.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 1)
        self.assertIn("не латинские знаки", done.stdout)
        self.assertEqual(done.stderr.strip(), "")

    def test_say_without_key(self):
        done = self.call("say", "что открыто",
                         result=[fixture("projects.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 1)
        self.assertIn("ключа DeepSeek нет", done.stdout)

    def test_say_close_needs_the_word(self):
        # Ворота стоят в КОДЕ: модель решает, что делать, но не решает, можно ли.
        done = self.voice("открой чат по вкуснофф",
                          {"steps": [{"action": "close", "project": "VkusnoffKz"}],
                           "say": "Закрыл"},
                          [fixture("projects.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 1)
        self.assertIn("слова «закрой» в твоей фразе нет", done.stdout)
        self.assertEqual([item["action"] for item in self.app.requests],
                         ["projects", "hud"], "закрывать канал не просили")

    def test_say_close_with_the_word(self):
        done = self.voice("закрой чат с вкуснофф",
                          {"steps": [{"action": "close", "project": "VkusnoffKz"}],
                           "say": "Закрыл окно Вкусноффа"},
                          [fixture("projects.result.json"),
                           fixture("close-window.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[1]
        self.assertEqual(list(request.keys()),
                         list(fixture("close-window.request.json").keys()))
        self.assertEqual(request["project"], "VkusnoffKz")
        self.assertEqual(self.app.requests[2]["text"], "Закрыл окно Вкусноффа")

    def test_say_airdrop_needs_photo_word(self):
        self.shots([10])
        done = self.voice("вставь это",
                          {"steps": [{"action": "paste_airdrop"}], "say": "Вставил"},
                          [fixture("projects.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 1)
        self.assertIn("про фотки в твоей фразе нет", done.stdout)

    def test_say_airdrop_with_photo_word(self):
        self.shots([20, 10])
        done = self.voice("вставь фотки с эйрдропа",
                          {"steps": [{"action": "paste_airdrop"}], "say": "Вставил фотки"},
                          [fixture("projects.result.json"), fixture("paste.result.json"),
                           fixture("hud.result.json")])
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[1]
        self.assertEqual(list(request.keys()), list(fixture("paste.request.json").keys()))
        self.assertEqual(len(request["paths"]), 2)
        self.assertTrue((self.support / "voice-pasted.json").exists())

    def test_say_unknown_project(self):
        done = self.voice("открой чат по ресторану",
                          {"steps": [{"action": "open", "project": "Ресторан",
                                      "chat": "new", "place": "right"}], "say": "Открыл"},
                          [fixture("projects.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 1)
        self.assertIn("не знаю проект «Ресторан»", done.stdout)

    def test_say_two_opens_get_arrange(self):
        # Несколько окон подряд встают стопкой — раскладку дописываем сами, порядком,
        # который назвала модель.
        answer = {"steps": [{"action": "open", "project": "VkusnoffKz",
                             "chat": "new", "place": "right"},
                            {"action": "open", "project": "PimpMyClaude",
                             "chat": "last", "place": "right"}],
                  "say": "Открыл два чата"}
        done = self.voice("открой чаты по вкуснофф и пимпу", answer,
                          [fixture("projects.result.json"), fixture("new-window.result.json"),
                           fixture("new-window-last.result.json"),
                           fixture("arrange.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual([item["action"] for item in self.app.requests],
                         ["projects", "new-window", "new-window", "arrange", "hud"])
        self.assertNotIn("chat", self.app.requests[1])
        self.assertEqual(self.app.requests[2]["chat"], "last")
        self.assertEqual(self.app.requests[3]["layout"], "last")
        self.assertEqual(self.app.requests[3]["order"], ["VkusnoffKz", "PimpMyClaude"])
        # Всё вышло — плашка говорит короткой фразой модели.
        self.assertEqual(self.app.requests[4]["text"], "Открыл два чата")

    def test_say_busy_repeats_with_new_id(self):
        # У прежнего id ответ уже лежит: второй раз приложение его не возьмёт, а
        # `at` старше 30 с даст stale — поэтому повтор идёт новым id и свежим at.
        done = self.voice("что открыто", {"steps": [{"action": "windows"}], "say": "Смотрю"},
                          [fixture("projects.result.json"), fixture("busy.result.json"),
                           fixture("windows.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 0, done.stderr)
        first, again = self.app.requests[1], self.app.requests[2]
        self.assertEqual([first["action"], again["action"]], ["windows", "windows"])
        self.assertNotEqual(first["id"], again["id"])
        self.assertGreaterEqual(again["at"], first["at"])

    def test_say_partial_result(self):
        # Сорвался один шаг из двух — плашка и stdout говорят одно и то же, и это
        # не фраза модели: она бы соврала.
        answer = {"steps": [{"action": "windows"}, {"action": "projects"}],
                  "say": "Всё сделал"}
        done = self.voice("что открыто и какие проекты", answer,
                          [fixture("projects.result.json"), fixture("windows.result.json"),
                           fixture("bad.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 1)
        self.assertIn("Сделал 1 из 2", done.stdout)
        self.assertIn("Пимп не понял запрос", done.stdout)
        self.assertEqual(self.app.requests[3]["text"], done.stdout.strip())

    def test_say_none_step(self):
        done = self.voice("пимп это отличная штука",
                          {"steps": [{"action": "none", "say": "Понял, ничего не трогаю"}],
                           "say": "Понял, ничего не трогаю"},
                          [fixture("projects.result.json"), fixture("hud.result.json")])
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Понял, ничего не трогаю")

    def test_say_reads_stdin(self):
        fake = self.brain({"steps": [{"action": "windows"}], "say": "Смотрю"})
        self.dir.mkdir(parents=True, exist_ok=True)
        self.app = FakeApp(self.dir, [fixture("projects.result.json"),
                                      fixture("windows.result.json"),
                                      fixture("hud.result.json")], count=3)
        self.app.start()
        env = dict(os.environ)
        env["MYCLAUDE_PIMP_DIR"] = str(self.dir)
        env["MYCLAUDE_PIMP_WAIT"] = "5"
        env["MYCLAUDE_PIMP_TAKEN"] = "2"
        env["MYCLAUDE_VOICE_FAKE"] = fake
        env["MYCLAUDE_VOICE_ENV"] = str(self.support / "pimp-voice.env")
        done = subprocess.run([sys.executable, str(CLI), "say", "-"], env=env,
                              input="Пимп, что открыто\n", capture_output=True,
                              text=True, timeout=60)
        self.app.join(timeout=2)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("Окон 1", done.stdout)

    def test_bad_place(self):
        # Кодов ровно два: ругань argparse (её 2) сведена к 1 и строке по-русски.
        done = self.call("open", "Dictator", "--at", "куда-нибудь")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Не понял команду", done.stdout)
        self.assertIn("left, middle, right", done.stderr)


if __name__ == "__main__":
    unittest.main()
