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
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pimp_testlib  # noqa: E402

ROOT = pimp_testlib.ROOT
CLI = pimp_testlib.CLI
FIXTURES = pimp_testlib.FIXTURES / "pimp"
ID_RE = re.compile(r"^\d{13,}-\d{4}$")
CHAT = "local_5265171a-0ab8-4472-b4e5-40604a36ef6e"
# #9116: тесты гонятся и из чата агента, а агенту окна Claude — только с --desktop. Прежние
# тесты играют Терминал Элвиса (агента в окружении нет); агента зовёт WF141DesktopGuardTest.
AGENT_ENV = ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT")
for _key in AGENT_ENV:
    os.environ.pop(_key, None)


def fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


# Приложение на минималках — общее для наборов CLI (pimp_testlib.FakeApp).
FakeApp = pimp_testlib.FakeApp


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

    def call(self, *argv, result=None, session=CHAT, taken=True, wait="5", silent=None,
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
        if silent is None:
            silent = pimp_testlib.APP_TAKEN_S if result is not None else "2"
        env["MYCLAUDE_PIMP_TAKEN"] = silent
        # summary перечисляет терминалы: живые сессии и Terminal в тесты не попадают.
        env["PIMP_TERM_TMUX"] = "none"
        env["PIMP_TERM_OSASCRIPT"] = "/usr/bin/true"
        # Подставные загрузки (paste-airdrop): настоящие ~/Downloads в тесты не попадают.
        env["MYCLAUDE_DOWNLOADS"] = str(self.support / "Downloads")
        # Сессии и транскрипты Claude — подставные (renew читает прежний чат, #10904): настоящие не попадают.
        env["MYCLAUDE_CLAUDE_SESSIONS"] = str(self.support / "no-sessions")
        env["MYCLAUDE_CLAUDE_PROJECTS"] = str(self.support / "no-projects")
        env.pop("CLAUDE_CODE_HOST_SESSION_ID", None)
        if session is not None:
            env["CLAUDE_CODE_HOST_SESSION_ID"] = session
        env.update(extra or {})
        # timeout — страховка от зависания, не замер: под нагрузкой сам pimp.py шёл дольше 60 с (#11441).
        done = subprocess.run([sys.executable, str(CLI), *argv], env=env,
                              capture_output=True, text=True, timeout=180)
        if self.app is not None:
            self.app.join(timeout=2)
        return done

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
        order = "/Users/dev/Projects/VkusnoffKz, SkilZZZ ,/Users/dev/Projects/Dictator"
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
        # Очередь так и не дошла — говорим «занят».
        done = self.call("open", "Dictator", result=fixture("busy.result.json"),
                         extra={"MYCLAUDE_PIMP_BUSY": "0.1"})
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "PMP занят — открывает или возвращает окна")

    def test_open_busy_then_ok(self):
        # Занят — повтор новым id и свежим at, второй ответ ok (G4 WF101).
        done = self.call("open", "Dictator",
                         result=[fixture("busy.result.json"), fixture("new-window.result.json")])
        self.assertEqual(done.returncode, 0, done.stdout)
        first, again = self.app.requests[0], self.app.requests[1]
        self.assertEqual([first["action"], again["action"]], ["new-window", "new-window"])
        self.assertNotEqual(first["id"], again["id"])

    def test_send_busy_then_ok_retries_only_confirmed_refusal(self):
        done = self.call("send", "--chat", CHAT, "текст",
                         result=[fixture("busy.result.json"), fixture("send.result.json")])
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual([r["action"] for r in self.app.requests], ["send", "send"])
        self.assertNotEqual(self.app.requests[0]["id"], self.app.requests[1]["id"])

    def test_send_success_with_conflicting_error_is_never_retried(self):
        done = self.call("send", "--chat", CHAT, "текст",
                         result=dict(fixture("send.result.json"), error="busy"))
        self.assertEqual(done.returncode, 0)
        self.assertEqual(len(self.app.requests), 1)

    def test_send_no_answer_is_never_retried(self):
        answer = dict(fixture("send.result.json"), ok=False, error="no-answer")
        done = self.call("send", "--chat", CHAT, "текст", result=answer)
        self.assertEqual(done.returncode, 1)
        self.assertEqual(len(self.app.requests), 1)

    def test_close_busy_then_ok(self):
        done = self.call("close", "VkusnoffKz",
                         result=[fixture("busy.result.json"), fixture("close-window.result.json")])
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual([r["action"] for r in self.app.requests], ["close-window", "close-window"])

    def test_bad_request(self):
        done = self.call("arrange", result=fixture("bad.result.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "PMP не понял запрос")

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
        order = "/Users/dev/Projects/VkusnoffKz,SkilZZZ"
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
        order = ("/Users/dev/Projects/VkusnoffKz,SkilZZZ,"
                 "/Users/dev/Projects/Dictator")
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
                         "включи «Свой цвет у каждого проекта» в «Оформлении» панели PMP или подожди минуту")

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
                         "Окон 1: Claude; спрятано: 1 — «pimp.py show» покажет")

    # ---- спрятать и показать окна (WF112, #8255) --------------------------
    def test_hide_request_and_answer(self):
        done = self.call("hide", result=fixture("hide.result.json"), session="")
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(fixture("hide.request.json").keys()))
        self.assertEqual(request["action"], "hide")
        self.assertEqual(done.stdout.strip(),
                         "Спрятал 2 окна: «Дубли задач», «Бот: голос»; во весь экран не трогал: 1")

    def test_hide_already(self):
        done = self.call("hide", result=fixture("hide-already.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Прятать нечего — на экране только главное окно")

    def test_hide_only_full_screen_left(self):
        # Гейт 1 WF111: прятать некого, кроме окон во весь экран, — так и сказать, с их числом.
        answer = dict(fixture("hide-already.result.json"), skipped=2)
        done = self.call("hide", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Прятать нечего: окна во весь экран не трогаю (2)")

    def test_hide_without_main_touches_nothing(self):
        done = self.call("hide", result=fixture("hide-no-main.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Главное окно Claude не нашёл — ничего не прятал")

    def test_show_request_and_answer(self):
        done = self.call("show", result=fixture("show.result.json"), session="")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(list(self.app.requests[0].keys()), list(fixture("show.request.json").keys()))
        self.assertEqual(self.app.requests[0]["action"], "show")
        self.assertEqual(done.stdout.strip(),
                         "Показал 2 окна: «Дубли задач», «Бот: голос»; фокус — главному окну")

    def test_show_already(self):
        done = self.call("show", result=fixture("show-already.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Спрятанных окон нет")

    def test_show_no_windows(self):
        answer = dict(fixture("bad.result.json"), error="no-windows")
        done = self.call("show", result=answer)
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Claude не запущен или окон у него нет")

    def test_hide_busy(self):
        done = self.call("hide", result=fixture("busy.result.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "PMP занят — открывает или возвращает окна")

    # ---- притемнение и обратный отсчёт (WF113 #8256, WF119) --------------
    def check_request(self, request: dict, name: str):
        """Поля, их типы и порядок — как в эталоне; id, at и from — свои."""
        want = fixture(name)
        self.assertEqual(list(request.keys()), list(want.keys()))
        for key in want:
            if key not in ("id", "at", "from"):
                self.assertEqual(request[key], want[key], key)

    def test_dim_on_with_level(self):
        done = self.call("dim", "on", "--level", "60", result=fixture("dim.result.json"), session="")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.check_request(self.app.requests[0], "dim.request.json")
        self.assertEqual(done.stdout.strip(),
                         "Притемнил окна чатов 60 %: главное, окно в фокусе и окно, где ждут тебя, — светлые")

    def test_dim_off_keeps_level(self):
        done = self.call("dim", "off", result=fixture("dim-off.result.json"), session="")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.check_request(self.app.requests[0], "dim-off.request.json")
        self.assertEqual(done.stdout.strip(), "Притемнение снял")

    def test_dim_level_fraction_same_as_percent(self):
        done = self.call("dim", "on", "--level", "0.6", result=fixture("dim.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["level"], 0.6)

    def test_dim_bad_level_sends_nothing(self):
        done = self.call("dim", "on", "--level", "95")
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Сила притемнения — от 20 до 80 % (или 0.2–0.8); ничего не менял")
        self.assertFalse(self.dir.exists() and any(self.dir.glob("*.json")))

    def test_look_style_size_show(self):
        done = self.call("look", "1.5", "--size", "120", "--show", result=fixture("look.result.json"), session="")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["style"], "1.5")
        self.assertEqual(list(self.app.requests[0]), list(fixture("look.request.json")))
        self.assertEqual(done.stdout.strip(), "Обратный отсчёт: 1.5 «Спокойная цифра», размер 120 %; "
                                              "показ в главном окне запрошен")

    def test_look_styles_keep_request_and_raw_answer(self):
        for style in ("1.8", "1.9", "1.10", "1.1", "1.2", "1.4", "1.6", "1.5"):
            with self.subTest(style=style):
                self.dir = self.support / f"pimp-look-{style}"
                answer = fixture("look.result.json")
                done = self.call("look", style, "--size", "120", "--show", "--json", result=answer, session="")
                self.assertEqual(done.returncode, 0, done.stderr)
                request = self.app.requests[0]
                self.assertEqual(list(request), list(fixture("look.request.json")))
                self.assertEqual(request["style"], style)
                self.assertEqual(request["size"], 120)
                self.assertIs(request["show"], True)
                answer["id"] = request["id"]
                actual = json.loads(done.stdout)
                self.assertEqual(actual, answer)
                self.assertEqual(list(actual), list(answer))
                self.assertEqual((actual["style"], actual["name"]), ("1.5", "Спокойная цифра"))

    def test_look_names_v3(self):
        for style, name in (("1.8", "Взлёт"), ("1.9", "Пульс"), ("1.10", "Мерцание"), ("1.1", "Штрих по кругу"),
                            ("1.2", "Удар"), ("1.4", "Кольцо"), ("1.6", "Шнур"), ("1.5", "Спокойная цифра")):
            with self.subTest(style=style):
                self.dir = self.support / f"pimp-name-{style}"
                answer = dict(fixture("look.result.json"), style=style)
                del answer["name"]
                done = self.call("look", style, result=answer)
                self.assertEqual(done.returncode, 0, done.stderr)
                self.assertEqual(done.stdout.strip(), f"Обратный отсчёт: {style} «{name}», размер 120 %")

    def test_look_retired_styles_send_nothing(self):
        for style in ("1.3", "1.7"):
            done = self.call("look", style, "--show")
            self.assertEqual(done.returncode, 1)
            self.assertTrue(done.stdout.startswith(f"Вид {style} снят — слишком; выбери: 1.8 «Взлёт»"), done.stdout)
        self.assertFalse(self.dir.exists() and any(self.dir.glob("*.json")))

    def test_look_without_options_reads_current(self):
        done = self.call("look", result=fixture("look-grow.result.json"), session="")
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request), ["id", "at", "action", "from"])
        self.assertEqual(request["action"], "look")
        self.assertEqual(done.stdout.strip(), "Обратный отсчёт: 1.5 «Спокойная цифра», размер 140 %")

    def test_look_name_fallback(self):
        answer = fixture("look-grow.result.json")
        del answer["name"]
        done = self.call("look", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Обратный отсчёт: 1.5 «Спокойная цифра», размер 140 %")

    def test_look_help_describes_one_countdown(self):
        for argv in (("--help",), ("look", "--help")):
            with self.subTest(argv=argv):
                done = self.call(*argv)
                self.assertEqual(done.returncode, 0, done.stderr)
                self.assertIn("Обратный отсчёт", done.stdout)
                self.assertNotIn("ракет", done.stdout.lower())
                if argv[0] == "look":
                    help_text = " ".join(done.stdout.split())
                    for style, name in (("1.8", "Взлёт"), ("1.9", "Пульс"), ("1.10", "Мерцание"),
                                        ("1.1", "Штрих по кругу"), ("1.2", "Удар"), ("1.4", "Кольцо"),
                                        ("1.6", "Шнур"), ("1.5", "Спокойная цифра")):
                        self.assertIn(f"{style} «{name}»", help_text)
                    self.assertNotIn("1.3", help_text)
                    self.assertNotIn("1.7", help_text)
        self.assertFalse(self.dir.exists() and any(self.dir.glob("*.json")))

    def test_look_bigger_is_grow(self):
        done = self.call("look", "--size", "+20", result=fixture("look-grow.result.json"), session="")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.check_request(self.app.requests[0], "look-grow.request.json")
        self.assertEqual(done.stdout.strip(), "Обратный отсчёт: 1.5 «Спокойная цифра», размер 140 %")

    def test_look_smaller(self):
        done = self.call("look", "--size", "-20", result=fixture("look-grow.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["grow"], -20)

    def test_look_size_limits(self):
        for size, field, value in (("60", "size", 60), ("200", "size", 200),
                                   ("+200", "grow", 200), ("-200", "grow", -200)):
            with self.subTest(size=size):
                self.dir = self.support / f"pimp-size-{size}"
                done = self.call("look", "--size", size, result=fixture("look-grow.result.json"))
                self.assertEqual(done.returncode, 0, done.stderr)
                request = self.app.requests[0]
                self.assertEqual(list(request), ["id", "at", "action", "from", field])
                self.assertEqual(request[field], value)
                self.assertIs(type(request[field]), int)

    def test_look_show_without_claude(self):
        answer = dict(fixture("look.result.json"), shown=False)
        done = self.call("look", "--show", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(list(self.app.requests[0]), ["id", "at", "action", "from", "show"])
        self.assertIs(self.app.requests[0]["show"], True)
        self.assertEqual(done.stdout.strip(), "Обратный отсчёт: 1.5 «Спокойная цифра», размер 120 %; "
                                              "показ не запрошен, выбор запомнил")

    def test_look_unknown_style_sends_nothing(self):
        done = self.call("look", "1.11")
        self.assertEqual(done.returncode, 1)
        self.assertTrue(done.stdout.startswith("Такого вида нет — выбери: 1.8 «Взлёт», 1.9 «Пульс»"), done.stdout)
        self.assertFalse(self.dir.exists() and any(self.dir.glob("*.json")))

    def test_look_bad_size_sends_nothing(self):
        for size in ("59", "201", "250", "12.5", "+300", "-201", "nan", "inf", "big"):
            done = self.call("look", "--size", size)
            self.assertEqual(done.returncode, 1, size)
            self.assertIn("Размер обратного отсчёта — от 60 до 200 %", done.stdout)
        self.assertFalse(self.dir.exists() and any(self.dir.glob("*.json")))

    def test_look_refused_by_app(self):
        done = self.call("look", "1.8", result=fixture("look-bad.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "PMP не понял запрос")

    # ---- окна WF94: ChatGPT, честный отказ страницы, мониторы ------------
    def test_windows_names_chatgpt_apart(self):
        # ChatGPT — отдельной записью с app: окном Claude его не считаем.
        done = self.call("windows", result=fixture("windows-chatgpt.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Окон 1: Claude; ещё окно ChatGPT")

    def test_window_missing_is_honest(self):
        # 65 с без окна (WF102, было 40) — не «чат создал»: страница могла и не создать его.
        answer = dict(fixture("new-window-last.error.json"))
        answer["error"] = "window-missing"
        done = self.call("open", "Dictator", result=answer)
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Окно не появилось за 65 с — чат мог и не создаться")

    def test_window_missing_last_chat(self):
        # z4-r04: у --last чат старый и точно есть — без «65 с» и «мог не создаться».
        answer = dict(fixture("new-window-last.error.json"))
        answer["error"] = "window-missing"
        done = self.call("open", "TrelvisCom", "--last", result=answer)
        self.assertEqual(done.returncode, 1)
        self.assertNotIn("65 с", done.stdout)
        self.assertNotIn("мог и не создаться", done.stdout)
        self.assertIn("--last", done.stdout)

    def test_chat_not_created_says_why(self):
        done = self.call("open", "Dictator", result=fixture("new-window-not-created.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "Чат не создан: в поле главного окна черновик")

    def test_chat_not_created_popout(self):
        # Чат есть, но в окно не вынесся — «не создан» было бы неправдой.
        answer = dict(fixture("new-window-not-created.error.json"))
        answer["state"] = "popout-failed"
        done = self.call("open", "Dictator", result=answer)
        self.assertEqual(done.stdout.strip(), "Чат создан, но в окно не вынесся — вынеси его руками")

    def test_chat_not_created_unknown_state(self):
        answer = dict(fixture("new-window-not-created.error.json"))
        answer["state"] = "no-mystery"
        done = self.call("open", "Dictator", result=answer)
        self.assertEqual(done.stdout.strip(), "Чат не создан (no-mystery)")

    def test_restore_screens_request_and_answer(self):
        done = self.call("restore-screens", result=fixture("screens-restore.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(list(self.app.requests[0].keys()),
                         list(fixture("screens-restore.request.json").keys()))
        self.assertEqual(self.app.requests[0]["action"], "screens-restore")
        self.assertEqual(done.stdout.strip(),
                         "Вернул окна как стояли на этих мониторах: 7 окон; "
                         "1 не нашёл — закрытые чаты не открываю")

    def test_restore_screens_unknown(self):
        done = self.call("restore-screens", result=fixture("screens-restore.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(),
                         "На этом наборе мониторов окна ещё не запоминал — расставь их, я запомню")

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
        self.assertEqual(done.stdout.strip(), "PMP не запущен")

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
        # Ударов на 1,6 с при ожидании 1 с: счёт от начала сдаётся, а запас 0,8 с на удар
        # держит опоздание нити под нагрузкой (#11441).
        done = self.call("layout", "restore", "Утро",
                         result=fixture("layout-restore.result.json"),
                         beats=8, beat_s=0.2, wait="1.0")
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

    def test_paste_project_beats_own_chat(self):
        # z4-r05: названный проект сильнее своего чата — from пустой.
        done = self.call("paste-clipboard", "--project", "VkusnoffKz", session="local_abc",
                         result=fixture("paste-clipboard.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["from"], "")

    def test_paste_bad_request(self):
        done = self.call("paste-clipboard", result=fixture("paste.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "PMP не понял запрос")

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

    # ---- фото чата по номерам (WF98, #7851): порядок как у Viewer chatNumbers ----
    def write_viewer(self, records):
        viewer = self.support / "viewer"
        viewer.mkdir(parents=True, exist_ok=True)
        (viewer / "index.json").write_text(
            json.dumps({"version": 1, "records": records}), encoding="utf-8")
        return viewer

    def gallery_records(self):
        files = self.support / "photos"
        files.mkdir(exist_ok=True)
        for name in ("b.png", "a.png", "c.jpg", "z.png"):
            (files / name).write_bytes(b"x")
        other = "local_other"
        return files, [
            # createdAt решает первым, при равенстве — имя файла, потом id.
            {"id": "i3", "kind": "photo", "path": str(files / "c.jpg"), "createdAt": 30, "chats": [CHAT]},
            {"id": "i2", "kind": "photo", "path": str(files / "b.png"), "createdAt": 20, "chats": [CHAT]},
            {"id": "i1", "kind": "photo", "path": str(files / "a.png"), "createdAt": 20, "chats": [CHAT, other]},
            {"id": "h1", "kind": "html", "path": str(files / "x.html"), "createdAt": 1, "chats": [CHAT]},
            {"id": "o1", "kind": "photo", "path": str(files / "z.png"), "createdAt": 5, "chats": [other]},
            # исходника нет — отдаём копию склада
            {"id": "i4", "kind": "photo", "path": str(files / "gone.png"), "createdAt": 40,
             "chats": [CHAT], "copy": "revs/i4/1.png"},
        ]

    def test_gallery_list_and_number(self):
        files, records = self.gallery_records()
        viewer = self.write_viewer(records)
        (viewer / "revs" / "i4").mkdir(parents=True)
        (viewer / "revs" / "i4" / "1.png").write_bytes(b"x")
        done = self.call("gallery")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.splitlines(), [
            f"1  {files / 'a.png'}", f"2  {files / 'b.png'}", f"3  {files / 'c.jpg'}",
            f"4  {viewer / 'revs' / 'i4' / '1.png'}"])
        done = self.call("gallery", "2")
        self.assertEqual((done.returncode, done.stdout.strip()), (0, str(files / "b.png")))
        done = self.call("gallery", "--chat", "local_other")
        self.assertEqual(done.stdout.splitlines(), [f"1  {files / 'z.png'}", f"2  {files / 'a.png'}"])

    def test_gallery_refusals(self):
        _, records = self.gallery_records()
        self.write_viewer(records)
        done = self.call("gallery", "9")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Фото 9 в этом чате нет: их 4", done.stdout)
        done = self.call("gallery", session=None)
        self.assertEqual(done.returncode, 1)
        self.assertIn("--chat", done.stdout)
        done = self.call("gallery", "--chat", "local_nobody")
        self.assertEqual((done.returncode, done.stdout.strip()), (1, "В этом чате фото нет"))

    # ---- замена чата (WF102, #7917): renew-window по эталонам ----------------
    def test_renew_request_by_chat(self):
        sample = fixture("renew-window.request.json")
        done = self.call("renew", sample["chat"], "--text", sample["text"],
                         "--model", sample["model"], "--effort", sample["effort"],
                         result=fixture("renew-window.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(sample.keys()), "порядок полей запроса")
        for key in ("action", "chat", "text", "model", "effort"):
            self.assertEqual(request[key], sample[key], key)
        # Файла сессии прежнего чата нет — текст как был, и это сказано (#10904).
        self.assertEqual(done.stdout.strip(), "Заменил окно «Ожидание задачи» новым чатом "
                         "local_9f1c2d3e-0000-4000-8000-000000000102; последний ответ прежнего "
                         "чата не нашёл — новый чат начат без него")

    def test_renew_request_by_project(self):
        # Не local_… — значит проект; без текста, модели и усилия ключей нет вовсе.
        done = self.call("renew", "Risovalka", result=fixture("renew-window.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()),
                         list(fixture("renew-window-project.request.json").keys()))
        self.assertEqual(request["project"], "Risovalka")

    def test_renew_text_from_stdin_and_limit(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        self.app = FakeApp(self.dir, fixture("renew-window.result.json"))
        self.app.start()
        env = dict(os.environ, MYCLAUDE_PIMP_DIR=str(self.dir), MYCLAUDE_PIMP_WAIT="5",
                   MYCLAUDE_PIMP_TAKEN=pimp_testlib.APP_TAKEN_S, CLAUDE_CODE_HOST_SESSION_ID=CHAT)
        done = subprocess.run([sys.executable, str(CLI), "renew", "Risovalka", "--text", "-"],
                              env=env, input="Передача\nв две строки\n", capture_output=True,
                              text=True, timeout=180)
        self.app.join(timeout=2)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["text"], "Передача\nв две строки")
        # Длиннее 20 000 знаков — отказ до канала: запроса нет.
        self.app = None
        shutil.rmtree(self.dir)
        done = self.call("renew", "Risovalka", "--text", "я" * 20001)
        self.assertEqual(done.returncode, 1)
        self.assertIn("20000", done.stdout)
        self.assertFalse(self.dir.exists())

    def test_renew_model_missed(self):
        answer = dict(fixture("renew-window.result.json"), model="missed")
        done = self.call("renew", "Risovalka", "--model", "Opus 5.5", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("модель не встала", done.stdout)

    def test_renew_effort_missed(self):
        answer = dict(fixture("renew-window.result.json"), effort="missed")
        done = self.call("renew", "Risovalka", "--effort", "extra", result=answer)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("эффорт не встал", done.stdout)

    def renew_refused(self, name):
        if self.dir.exists():
            shutil.rmtree(self.dir)     # прошлый запрос в каталоге ответил бы первым
        return self.call("renew", fixture("renew-window.request.json")["chat"],
                         result=fixture(name))

    def test_renew_refusals(self):
        done = self.renew_refused("renew-window-main.error.json")
        self.assertEqual((done.returncode, done.stdout.strip()),
                         (1, "Этот чат в главном окне Claude — эта версия PMP его не меняет, обнови PMP"))
        done = self.renew_refused("renew-window-not-created.error.json")
        self.assertEqual(done.stdout.strip(), "Чат не создан: сообщение не ушло")
        done = self.renew_refused("renew-window-unknown.error.json")
        self.assertEqual(done.returncode, 1)
        self.assertIn("«Ожидание задачи»", done.stdout)
        self.assertIn("старое окно не закрывал", done.stdout)

    # ---- замена чата главного окна (WF131, #9078) ------------------------------
    def test_renew_main_window(self):
        answer = dict(fixture("renew-window.result.json"), main=True)
        done = self.call("renew", "Rick", "--text", "Передача", result=answer)
        self.assertEqual((done.returncode, done.stdout.strip()),
                         (0, "Новый чат local_9f1c2d3e-0000-4000-8000-000000000102 открыл в главном "
                             "окне, старый остался в списке слева"))
        self.assertEqual(self.app.requests[0]["project"], "Rick")

    def test_renew_main_window_not_moved(self):
        failed = dict(fixture("renew-window-main.error.json"),
                      window=fixture("renew-window.result.json")["window"])
        if self.dir.exists():
            shutil.rmtree(self.dir)
        done = self.call("renew", "Rick", result=failed)
        self.assertEqual(done.returncode, 1)
        self.assertIn("«Ожидание задачи» local_9f1c2d3e-0000-4000-8000-000000000102 открыл "
                      "отдельным окном, но в главное окно не перенёс", done.stdout)
        self.assertEqual(len(self.app.requests), 1, "main-window не повторяется, как busy")

    # ---- отправка в окно (WF103, #7953): send по эталонам ----------------------
    def test_send_request_by_chat(self):
        sample = fixture("send.request.json")
        done = self.call("send", "--chat", sample["chat"], sample["text"],
                         result=fixture("send.result.json"), session=sample["from"])
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(sample.keys()), "порядок полей запроса")
        for key in ("action", "from", "chat", "text"):
            self.assertEqual(request[key], sample[key], key)
        self.assertEqual(done.stdout.strip(), "Отправил в «WF103 оркестровка просмотра файлов»")

    def test_send_request_by_project(self):
        sample = fixture("send-project.request.json")
        done = self.call("send", "--project", sample["project"], sample["text"],
                         result=fixture("send.result.json"), session=sample["from"])
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(sample.keys()), "порядок полей запроса")
        self.assertEqual((request["project"], request["text"]), (sample["project"], sample["text"]))

    def test_send_text_from_stdin(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        self.app = FakeApp(self.dir, fixture("send.result.json"))
        self.app.start()
        env = dict(os.environ, MYCLAUDE_PIMP_DIR=str(self.dir), MYCLAUDE_PIMP_WAIT="5",
                   MYCLAUDE_PIMP_TAKEN=pimp_testlib.APP_TAKEN_S, CLAUDE_CODE_HOST_SESSION_ID=CHAT)
        done = subprocess.run([sys.executable, str(CLI), "send", "--project", "VkusnoffKz", "-"],
                              env=env, input="Две\nстроки\n", capture_output=True,
                              text=True, timeout=180)
        self.app.join(timeout=2)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["text"], "Две\nстроки")

    def test_send_refused_before_channel(self):
        # Плохой запрос в канал не уходит вовсе: каталога так и нет.
        for argv in (("send", "--chat", CHAT, "я" * 8001),
                     ("send", "--chat", CHAT, "   "),
                     ("send", "--chat", "VkusnoffKz", "текст"),
                     ("send", "текст"),
                     ("send", "--chat", CHAT, "--project", "VkusnoffKz", "текст")):
            done = self.call(*argv)
            self.assertEqual(done.returncode, 1, argv)
            self.assertFalse(self.dir.exists(), argv)
        done = self.call("send", "--chat", CHAT, "я" * 8001)
        self.assertIn("8000", done.stdout)
        env = dict(os.environ, MYCLAUDE_PIMP_DIR=str(self.dir), CLAUDE_CODE_HOST_SESSION_ID=CHAT)
        done = subprocess.run([sys.executable, str(CLI), "send", "--chat", CHAT, "-"], env=env,
                              input="до\0после", capture_output=True, text=True, timeout=180)
        self.assertEqual(done.returncode, 1)
        self.assertIn("нулевой", done.stdout)
        self.assertFalse(self.dir.exists())
        # Ровно 8000 знаков — можно.
        done = self.call("send", "--chat", CHAT, "я" * 8000, result=fixture("send.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(len(self.app.requests[0]["text"]), 8000)

    def send_refused(self, answer):
        if self.dir.exists():
            shutil.rmtree(self.dir)     # прошлый запрос в каталоге ответил бы первым
        return self.call("send", "--chat", CHAT, "текст", result=answer,
                         extra={"MYCLAUDE_PIMP_BUSY": "0.1"})

    def test_send_to_rick_only_voice(self):
        # #8364: в поле Рика окна не пишут — только голос Элвиса («Голос Элвиса: …» от rick_bus).
        done = self.call("send", "--project", "Rick", "ответ окна")
        self.assertEqual(done.returncode, 1)
        self.assertIn("В поле Рика окна не пишут", done.stdout)
        self.assertFalse(self.dir.exists(), "в канал не ушло")
        done = self.call("send", "--project", "Rick", "Голос Элвиса: привет", result=fixture("send.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["text"], "Голос Элвиса: привет")

    def test_send_queued_is_success(self):
        # WF111: в поле свой текст Элвиса — фраза ждёт в очереди окна; для голоса это успех, не «мост не сработал».
        done = self.send_refused(fixture("send-queued.result.json"))
        self.assertEqual((done.returncode, done.stdout.strip()),
                         (0, "Фраза ждёт в окне «WF103 оркестровка просмотра файлов»: в поле твой текст — "
                             "уйдёт, как только поле опустеет"))

    def test_send_refusals(self):
        title = "«WF103 оркестровка просмотра файлов»"
        done = self.send_refused(fixture("send-field-busy.error.json"))
        self.assertEqual((done.returncode, done.stdout.strip()),
                         (1, f"В окне {title} в поле свой текст — не отправил"))
        done = self.send_refused(fixture("send-no-answer.error.json"))
        self.assertEqual((done.returncode, done.stdout.strip()),
                         (1, f"Отправил в окно {title}, но подтверждения нет — глянь, ушло ли"))
        done = self.send_refused(dict(fixture("send-field-busy.error.json"), error="no-field"))
        self.assertEqual(done.stdout.strip(), f"В окне {title} нет поля ввода — не отправил")
        done = self.send_refused(dict(fixture("send-field-busy.error.json"), error="no-send"))
        self.assertEqual(done.stdout.strip(),
                         f"Вставил в окно {title}, но не отправилось — текст в поле")
        missing = dict(fixture("send.result.json"), ok=False, error="window-missing")
        missing.pop("window")
        done = self.send_refused(missing)
        self.assertEqual((done.returncode, done.stdout.strip()),
                         (1, f"Окна чата {CHAT} не нашёл — ничего не отправил"))
        ambiguous = dict(missing, error="ambiguous", windows=["Вкуснофф 1", "Вкуснофф 2"])
        done = self.send_refused(ambiguous)
        self.assertIn("«Вкуснофф 1», «Вкуснофф 2»", done.stdout)
        done = self.send_refused(dict(missing, error="busy"))
        self.assertEqual(done.stdout.strip(), "PMP занят — открывает или возвращает окна")

    def test_send_json_is_raw(self):
        done = self.call("send", "--chat", CHAT, "текст", "--json",
                         result=fixture("send-field-busy.error.json"))
        self.assertEqual(done.returncode, 1)
        self.assertEqual(json.loads(done.stdout)["error"], "field-busy")

    # ---- главный по центру (WF102, #7904) -------------------------------------
    def test_arrange_center_request_and_answer(self):
        sample = fixture("arrange-center.request.json")
        done = self.call("arrange", "--layout", "center", "--order", ",".join(sample["order"]),
                         "--center", sample["center"], result=fixture("arrange-center.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(sample.keys()), "порядок полей запроса")
        self.assertEqual((request["layout"], request["center"], request["order"]),
                         ("center", "Rick", sample["order"]))
        self.assertTrue(done.stdout.startswith(
            "Расставил 7 окон на экране, где стоят окна: главный по центру (Rick)"), done.stdout)

    def test_arrange_center_without_key_and_misuse(self):
        self.call("arrange", "--layout", "center", result=fixture("arrange-center.result.json"))
        self.assertNotIn("center", self.app.requests[0])
        self.app = None
        shutil.rmtree(self.dir)
        done = self.call("arrange", "--center", "Rick")
        self.assertEqual((done.returncode, done.stdout.strip()),
                         (1, "Ключ --center — только с --layout center"))

    # ---- центр клетками (WF107, #8125) ---------------------------------------------
    def test_arrange_center_stack_request_and_answer(self):
        sample = fixture("arrange-center-stack.request.json")
        done = self.call("arrange", "--layout", "center", "--order", ",".join(sample["order"]),
                         "--center", sample["center"],
                         result=fixture("arrange-center-stack.result.json"))
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(sample.keys()), "порядок полей запроса")
        self.assertEqual(request["order"], sample["order"], "«A+B» уходит одной записью")
        self.assertEqual(done.stdout.strip(),
                         "Расставил 9 окон на экране, где стоят окна: главный по центру (Rick) — сперва "
                         "VkusnoffKz, Marketolog над VkusUchet, Risovalka над MenuMaker, Rick, "
                         "PimpViewer, PimpMyClaude, Dictator")

    def test_arrange_center_names_hub_by_field(self):
        # hub — кто в центре; в тесноте это уже не середина ответа.
        answer = dict(fixture("arrange-center.result.json"), hub=4)
        done = self.call("arrange", "--layout", "center", result=answer)
        self.assertIn("главный по центру (PimpMyClaude)", done.stdout)
        # Нет поля (старое приложение) — середина, как было.
        answer.pop("hub")
        self.app = None
        shutil.rmtree(self.dir)
        done = self.call("arrange", "--layout", "center", result=answer)
        self.assertIn("главный по центру (Rick)", done.stdout)

    def test_arrange_center_stack_missing_part_and_rows(self):
        sample = fixture("arrange-center-stack.request.json")
        answer = dict(fixture("arrange-center-stack.result.json"), missing=["VkusUchet"])
        done = self.call("arrange", "--layout", "center", "--order", ",".join(sample["order"]),
                         result=answer)
        self.assertIn("сперва VkusnoffKz, Marketolog, Risovalka над MenuMaker,", done.stdout)
        self.assertIn("; не нашёл окна: VkusUchet", done.stdout)
        self.app = None
        shutil.rmtree(self.dir)
        refused = {"id": "x", "at": "2026-09-29T20:40:02Z", "ok": False, "error": "too-small",
                   "fromResolved": False, "screen": "windows", "rows": 2}
        done = self.call("arrange", "--layout", "center", "--order", "A+B+C,Rick", result=refused)
        self.assertEqual((done.returncode, done.stdout.strip()),
                         (1, "В столбик на этом экране влезает не больше 2 окон — "
                             "Claude не даёт окну быть ниже"))
        # Без rows — прежние слова «экран мал».
        self.app = None
        shutil.rmtree(self.dir)
        refused.pop("rows")
        done = self.call("arrange", "--layout", "center", result=refused)
        self.assertTrue(done.stdout.startswith("Экран мал"), done.stdout)

    # ---- сводка окон (WF102, #7916): только чтение файлов -----------------------
    def summary_env(self):
        sessions = self.support / "sessions" / "acc" / "place"
        projects = self.support / "projects"
        sessions.mkdir(parents=True)
        projects.mkdir()
        return sessions, projects, {"MYCLAUDE_CLAUDE_SESSIONS": str(self.support / "sessions"),
                                    "MYCLAUDE_CLAUDE_PROJECTS": str(projects)}

    @staticmethod
    def answer_record(text, stop="end_turn", mid="m1"):
        return {"type": "assistant", "isSidechain": False,
                "message": {"id": mid, "stop_reason": stop,
                            "content": [{"type": "text", "text": text}]}}

    def write_session(self, sessions, projects, chat, cli, minutes_ago, summary, records,
                      pad=0):
        body = {"sessionId": chat, "cliSessionId": cli, "cwd": "/x/Projects/Rick",
                "title": "Семь окон", "isArchived": False,
                # Полминуты запаса: счёт минут идёт вниз, тест не должен ловить границу.
                "lastActivityAt": int((time.time() - (minutes_ago - 0.5) * 60) * 1000),
                "postTurnSummary": summary}
        (sessions / f"{chat}.json").write_text(json.dumps(body, ensure_ascii=False),
                                               encoding="utf-8")
        folder = projects / "-x--Projects-Rick"
        folder.mkdir(exist_ok=True)
        lines = []
        if pad:
            # Длинный хвост: первая строка в окне 512 КБ окажется рваной.
            lines.append(json.dumps({"type": "user", "pad": "x" * pad}))
        lines += [json.dumps(record, ensure_ascii=False) for record in records]
        (folder / f"{cli}.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def summary_windows(self, *chats):
        windows = [{"title": f"Окно {n}", "chat": chat, "folder": "", "frame": [0, 0, 280, 720]}
                   for n, chat in enumerate(chats)]
        windows.append({"title": "ChatGPT", "chat": "", "folder": "", "frame": [0, 0, 700, 720],
                        "app": "chatgpt"})
        return dict(fixture("windows.result.json"), windows=windows, minimized=0)

    def test_summary_reads_session_and_transcript_tail(self):
        sessions, projects, env = self.summary_env()
        ready = "local_00000000-0000-4000-8000-000000000001"
        running = "local_00000000-0000-4000-8000-000000000002"
        cold = "local_00000000-0000-4000-8000-000000000003"
        text = ("## Итог\n\nГотово.\n\n## 👾 ЭЛВИС, СДЕЛАЙ\n\n1. **Проверь** баннер\n"
                "   - вложенный, не считать\n2. Узнай у повара\n3. Выбери цвет\n4. Лишний пункт\n\n"
                "## Дальше\n\n5. не отсюда\n\n🧪[Rick](status.md) · жду ❓")
        self.write_session(sessions, projects, ready, "cli-1", 12,
                           {"status_category": "blocked", "status_detail": "ждём",
                            "needs_action": "выбрать баннер"},
                           [self.answer_record(text)], pad=600 * 1024)
        self.write_session(sessions, projects, running, "cli-2", 1,
                           {"status_category": "completed", "needs_action": ""},
                           [self.answer_record("Старое\n\n🧪Rick · готово ✅"),
                            {"type": "user", "message": {"content": "дальше"}},
                            self.answer_record("", stop="tool_use", mid="m2")])
        self.write_session(sessions, projects, cold, "cli-3", 75, None, [])
        unknown = "local_00000000-0000-4000-8000-00000000000f"
        done = self.call("summary", result=self.summary_windows(ready, running, cold, unknown),
                         extra=env)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["action"], "windows")
        self.assertEqual(done.stdout.splitlines(), [
            "Rick · «Семь окон» — ждёт Элвиса · кеш 48 мин",
            "  🧪Rick · жду ❓",
            "  нужно: выбрать баннер",
            "  1. Проверь баннер",
            "  2. Узнай у повара",
            "  3. Выбери цвет",
            "Rick · «Семь окон» — идёт · кеш 59 мин",
            "  🧪Rick · готово ✅",
            "Rick · «Семь окон» — ждёт · кеш остыл",
            "без папки · «Окно 3» — нет данных",
        ])

    def test_summary_uses_newest_transcript_copy(self):
        sessions, projects, env = self.summary_env()
        self.write_session(sessions, projects, CHAT, "cli-copy", 5, None,
                           [self.answer_record("старое\n🧪Rick · готово ✅")])
        old = projects / "-x--Projects-Rick" / "cli-copy.jsonl"
        folder = projects / "z-new-location"
        folder.mkdir()
        fresh = folder / "cli-copy.jsonl"
        fresh.write_text(json.dumps(self.answer_record("свежее\n🧪Rick · жду ❓")) + "\n")
        os.utime(old, (100, 100))
        os.utime(fresh, (200, 200))
        done = self.call("summary", result=self.summary_windows(CHAT), extra=env)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("жду ❓", done.stdout)
        self.assertNotIn("готово ✅", done.stdout)

    def test_summary_skips_subagent_records_for_running(self):
        # Ответ основной ветки закончен, ниже в транскрипте — реплики субагента (isSidechain): чат ждёт, а не «идёт».
        sessions, projects, env = self.summary_env()
        side = dict(self.answer_record("", stop="tool_use", mid="s1"), isSidechain=True)
        self.write_session(sessions, projects, CHAT, "cli-side", 5, None,
                           [self.answer_record("Сделал.\n\n🧪Rick · готово ✅"),
                            {"type": "user", "isSidechain": True, "message": {"content": "задача субагенту"}},
                            side])
        done = self.call("summary", result=self.summary_windows(CHAT), extra=env)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.splitlines()[:2],
                         ["Rick · «Семь окон» — ждёт · кеш 55 мин", "  🧪Rick · готово ✅"])

    def test_summary_status_line_from_early_part_of_answer(self):
        # Один ответ Claude пишет в транскрипт кусками с тем же message.id: строка состояния — в раннем куске.
        sessions, projects, env = self.summary_env()
        early = self.answer_record("Итог.\n\n🧪Rick · жду ❓", stop=None, mid="m2")
        self.write_session(sessions, projects, CHAT, "cli-parts", 5, None,
                           [self.answer_record("Прошлый.\n\n🧪Rick · готово ✅"), early,
                            self.answer_record("Ссылки — в файле.", mid="m2")])
        done = self.call("summary", result=self.summary_windows(CHAT), extra=env)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.splitlines()[:2],
                         ["Rick · «Семь окон» — ждёт · кеш 55 мин", "  🧪Rick · жду ❓"])

    def test_digest_groups_projects_by_status(self):
        # #9077: сводка всех проектов — по status.md, рабочие деревья git (.git-файл) не считаются проектом.
        root = self.support / "projects"
        (self.support / "claude.json").write_text(json.dumps({"projectsRoot": str(root)}), encoding="utf-8")
        def status(folder, text):
            (root / folder / "docs").mkdir(parents=True)
            (root / folder / "docs" / "status.md").write_text(text, encoding="utf-8")
        status("Alpha", "# 🟢Alpha\nобновлено 21:00\n\n2 воркфлоу\nмарафон «Чистка», волна 1 из 2\n\n"
                        "1️⃣ Workflow ✅ готово\n- о чём: первое\n- шаги 2 из 2\n\n"
                        "2️⃣ Workflow ⏳ идёт\n- о чём: второе\n- шаги 1 из 3\n\nСейчас: гейт 1.\n")
        status("Beta", "# 🟠Beta\n\n1️⃣ Workflow ✅ готово\n- о чём: всё\n\nЖдёт Элвиса: глянуть файл 3\n")
        status("Gamma", "# 💤Gamma\n\nЖдёт Элвиса: ничего\n")
        status("Alpha-wf2", "# 🟢Alpha\n\n1️⃣ Workflow ⏳ идёт\n")
        (root / "Alpha-wf2" / ".git").write_text("gitdir: ../Alpha/.git/worktrees/x\n", encoding="utf-8")
        done = self.call("digest")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.splitlines(), [
            "⏳ Идут — 1",
            "  🟢Alpha · Workflow 1 из 2 готово · марафон «Чистка», волна 1 из 2",
            "    2-й идёт (шаги 1 из 3): второе",
            "    Сейчас: гейт 1.",
            "✋ Ждут Элвиса — 1",
            "  🟠Beta · Workflow 1 из 1 готово",
            "    Ждёт: глянуть файл 3",
            "· Тихо: 💤Gamma",
        ])
        items = json.loads(self.call("digest", "--json").stdout)
        self.assertEqual([(i["project"], i["group"], i["workflows"], i["done"]) for i in items],
                         [("Alpha", "идут", 2, 1), ("Beta", "ждут", 1, 1), ("Gamma", "тихо", 0, 0)])

    def test_digest_reads_freshest_worktree_status(self):
        # #9519: Workflow сайта идёт в рабочем дереве (VkusnoffKz-iiko1019), сводка главной папки стоит — берётся
        # самая свежая сводка из папки и её деревьев (.git/worktrees/*/gitdir), проектом дерево не становится.
        root = self.support / "projects"
        (self.support / "claude.json").write_text(json.dumps({"projectsRoot": str(root)}), encoding="utf-8")
        main, tree = root / "Cafe", root / "Cafe-iiko1019"
        for folder in (main, tree):
            (folder / "audit").mkdir(parents=True)
        (main / "audit" / "status.md").write_text("# 🟠Cafe\n\n1️⃣ Workflow ✅ готово\n- о чём: старое\n", encoding="utf-8")
        (tree / "audit" / "status.md").write_text("# 🟠Cafe\n\n1️⃣ Workflow ✅ готово\n- о чём: старое\n\n"
                                                  "2️⃣ Workflow ⏳ идёт\n- о чём: меню кафе\n- шаги 1 из 4\n", encoding="utf-8")
        (main / ".git" / "worktrees" / "iiko").mkdir(parents=True)
        (main / ".git" / "worktrees" / "iiko" / "gitdir").write_text(f"{tree}/.git\n", encoding="utf-8")
        (tree / ".git").write_text(f"gitdir: {main}/.git/worktrees/iiko\n", encoding="utf-8")
        now = time.time()
        os.utime(main / "audit" / "status.md", (now - 3600, now - 3600))
        os.utime(tree / "audit" / "status.md", (now, now))
        items = json.loads(self.call("digest", "--json").stdout)
        self.assertEqual([(i["project"], i["group"], i["workflows"]) for i in items], [("Cafe", "идут", 2)])

    def test_digest_one_state_rule(self):
        # WF145: правило состояний — как у приложения (PanelProjects.blockState): ⏳ идёт, ⬜ впереди (не «ждёт»),
        # проект «ждут» и по Workflow, что ждёт Элвиса, а не только по строке «Ждёт Элвиса».
        pimp = pimp_testlib.load_pimp("pimp_digest_wf145")
        cases = {"1️⃣ Workflow ⏳ идёт": "идёт", "2️⃣ Workflow 💭 идёт": "идёт", "3️⃣ Workflow ✅ готово": "готово",
                 "4️⃣ Workflow ✅ готово, выложено": "готово", "5️⃣ Workflow ⬜ запланирован": "впереди",
                 "6️⃣ Workflow ❓ ждёт Элвиса": "ждёт", "7️⃣ Workflow ⚠️ глянь": "ждёт", "8️⃣ Workflow 🛑 упал": "упал",
                 "9️⃣ Workflow ❌ стоп": "упал", "🔟 Workflow кодинг": "идёт", "1️⃣ Workflow запланирован": "впереди",
                 "2️⃣ Workflow": "впереди"}
        for heading, state in cases.items():
            self.assertEqual(pimp.digest_state(heading), state, heading)
        root = self.support / "projects"
        (self.support / "claude.json").write_text(json.dumps({"projectsRoot": str(root)}), encoding="utf-8")
        for folder, text in (("Plan", "# Plan\n\n1️⃣ Workflow ✅ готово\n2️⃣ Workflow ⬜ запланирован\n"),
                             ("Hand", "# Hand\n\n1️⃣ Workflow ❓ ждёт Элвиса\n- о чём: глянь\n"),
                             ("Run", "# Run\n\n1️⃣ Workflow ⏳ идёт\n2️⃣ Workflow ⬜ запланирован\n")):
            (root / folder / "docs").mkdir(parents=True)
            (root / folder / "docs" / "status.md").write_text(text, encoding="utf-8")
        items = json.loads(self.call("digest", "--json").stdout)
        self.assertEqual({i["project"]: i["group"] for i in items}, {"Run": "идут", "Hand": "ждут", "Plan": "тихо"})

    def test_summary_json(self):
        sessions, projects, env = self.summary_env()
        chat = "local_00000000-0000-4000-8000-000000000001"
        self.write_session(sessions, projects, chat, "cli-1", 5,
                           {"status_category": "review_ready", "needs_action": "глянуть"}, [])
        done = self.call("summary", "--json", result=self.summary_windows(chat), extra=env)
        self.assertEqual(done.returncode, 0, done.stderr)
        cards = json.loads(done.stdout)
        self.assertEqual(len(cards), 1)            # ChatGPT пропущен
        self.assertEqual((cards[0]["chat"], cards[0]["state"], cards[0]["needs"], cards[0]["todo"]),
                         (chat, "ждёт проверки", "глянуть", []))

    def test_summary_finds_chat_by_single_title(self):
        # Карта чатов замерла (probe.js занят): окно без chat — по заголовку, только
        # если такая живая сессия одна.
        sessions, projects, env = self.summary_env()
        self.write_session(sessions, projects, "local_00000000-0000-4000-8000-000000000001",
                           "cli-1", 5, {"status_category": "completed"}, [])
        answer = dict(fixture("windows.result.json"), minimized=0, windows=[
            {"title": "Семь окон", "chat": "", "folder": "", "frame": [0, 0, 280, 720]},
            {"title": "Чужое", "chat": "", "folder": "/x/Dictator", "frame": [0, 0, 280, 720]}])
        done = self.call("summary", result=answer, extra=env)
        self.assertEqual(done.stdout.splitlines(), ["Rick · «Семь окон» — готово · кеш 55 мин",
                                                     "Dictator · «Чужое» — нет данных"])

    # ---- перезапуск Claude (WF108, #8176): restart-claude по эталонам -------------
    def restart(self, *argv, name="restart-claude.result.json", **kwargs):
        if self.dir.exists():
            shutil.rmtree(self.dir)     # прошлый запрос в каталоге ответил бы первым
        return self.call("restart-claude", *argv, result=fixture(name), **kwargs)

    def test_restart_request_and_answer(self):
        sample = fixture("restart-claude.request.json")
        done = self.restart(session=sample["from"])
        self.assertEqual(done.returncode, 0, done.stderr)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(sample.keys()), "порядок полей запроса")
        self.assertEqual((request["action"], request["from"]), ("restart-claude", sample["from"]))
        lines = done.stdout.strip().split("\n")
        self.assertEqual(lines[0], request["id"], "первой строкой — id запроса")
        self.assertEqual(lines[1:], ["Перезапустил Claude, окна вернул: 1 на месте, 2 чата открыл "
                                     "заново; не нашёл: «Дубли задач»"])

    def test_restart_force_and_from(self):
        sample = fixture("restart-claude-force.request.json")
        done = self.restart("--force", session=None)
        request = self.app.requests[0]
        self.assertEqual(list(request.keys()), list(sample.keys()), "force — последним")
        self.assertEqual((request["from"], request["force"]), ("", True))
        done = self.restart("--from", CHAT, session="local_00000000-0000-4000-8000-000000000000")
        request = self.app.requests[0]
        self.assertEqual(request["from"], CHAT, "--from сильнее своего чата")
        self.assertNotIn("force", request, "force — только когда просили")
        done = self.call("restart-claude", "--from", "Rick")
        self.assertEqual((done.returncode, done.stdout.strip()),
                         (1, "Ключ --from — это local_… чата; Claude не трогал"))
        self.assertIn("оборвёт работающие чаты",
                      " ".join(self.call("restart-claude", "--help").stdout.split()))

    def test_restart_refusals(self):
        cases = {
            "restart-claude-working.error.json":
                "Не перезапускаю: идёт ответ в «TrelvisCom / Дубли задач» — дождись или --force "
                "(оборвёт работающие чаты)",
            "restart-claude-unknown.error.json":
                "Не перезапускаю: не удалось проверить, идёт ли ответ в чатах — --force "
                "перезапустит всё равно и оборвёт работающие чаты",
            "restart-claude-failed.error.json":
                "Claude не перезапустился: Claude не закрылся за 30 секунд. Закрой его сам (⌘Q) и повтори.",
            "restart-claude-timeout.error.json":
                "Claude перезапустил, но окна не вернулись за 130 с — верни их: pimp.py restore-screens",
            "restart-claude-gaveup.error.json":
                "Claude перезапустил, но окна не вернулись («Чат А», «Чат Б», «Дубли задач») — "
                "верни их: pimp.py restore-screens",
        }
        for name, line in cases.items():
            done = self.restart(name=name)
            self.assertEqual(done.returncode, 1, name)
            self.assertEqual(done.stdout.strip().split("\n")[1:], [line], name)

    def test_restart_waits_no_longer_than_total(self):
        # Сердце бьётся, а ответа нет: общий потолок (180 с, тут 1 с) сильнее ударов.
        done = self.restart(beats=40, beat_s=0.1, wait="5",
                            extra={"MYCLAUDE_PIMP_RESTART_WAIT": "1"})
        self.assertEqual(done.returncode, 1)
        lines = done.stdout.strip().split("\n")
        self.assertTrue(lines[1].startswith("Ответа нет за 1 с — исход ляжет в"), lines)
        self.assertNotIn("не перезапустился", lines[1], "исхода не знаем — без приговора")
        self.assertIn(f"pimp/{lines[0]}.result.json", lines[1])

    def test_restart_json_is_raw(self):
        done = self.restart("--json")
        self.assertEqual(done.returncode, 0)
        self.assertEqual(json.loads(done.stdout)["placed"], 1, "в --json строки id нет — только ответ")

    # ---- чат в главное окно (WF108, #8148): main по эталонам ----------------------
    def main_call(self, *argv, name="main.result.json", **kwargs):
        if self.dir.exists():
            shutil.rmtree(self.dir)
        return self.call("main", *argv, result=fixture(name), **kwargs)

    def test_main_request_by_chat_and_project(self):
        for sample_name, target in (("main.request.json", "chat"), ("main-project.request.json", "project")):
            sample = fixture(sample_name)
            done = self.main_call(sample[target], session=sample["from"])
            self.assertEqual(done.returncode, 0, done.stderr)
            request = self.app.requests[0]
            self.assertEqual(list(request.keys()), list(sample.keys()), f"{sample_name}: порядок полей")
            self.assertEqual((request["action"], request[target]), ("main", sample[target]))
            self.assertEqual(done.stdout.strip(), "Чат в главном окне, прежний — в своём окне")

    def test_main_answers(self):
        already = dict(fixture("main.result.json"), popped="", already=True)
        done = self.call("main", "Rick", result=already)
        self.assertEqual((done.returncode, done.stdout.strip()), (0, "Этот чат уже в главном окне"))
        home = dict(fixture("main.result.json"), popped="")
        shutil.rmtree(self.dir)
        done = self.call("main", "Rick", result=home)
        self.assertEqual(done.stdout.strip(), "Чат в главном окне")

    def test_main_refusals(self):
        cases = {
            "main-chat-missing.error.json": "Чат проекта Rick в главном окне не открылся — ничего не поменял",
            "main-no-main.error.json": "Главного окна Claude нет — не с чем меняться",
            "main-not-created.error.json":
                "Чат в главном окне, а прежний вынести окном не вышло — он в списке слева",
        }
        for name, line in cases.items():
            done = self.main_call("Rick", name=name)
            self.assertEqual((done.returncode, done.stdout.strip()), (1, line), name)
        closed = dict(fixture("main-no-main.error.json"), windows=["Rick"])
        shutil.rmtree(self.dir)
        done = self.call("main", "Rick", result=closed)
        self.assertEqual(done.stdout.strip(), "Не смог закрыть окно «Rick» — главное окно не трогал")
        done = self.call("main", "  ")
        self.assertEqual((done.returncode, done.stdout.strip()), (1, "Не назван чат — ничего не трогал"))

    def test_bad_place(self):
        # Кодов ровно два: ругань argparse (её 2) сведена к 1 и строке по-русски.
        done = self.call("open", "Dictator", "--at", "куда-нибудь")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Не понял команду", done.stdout)
        self.assertIn("left, middle, right", done.stderr)

    def test_point_has_at_most_six_digits(self):
        # Ревизия WF247 (пара к PimpRequest.place): 20 цифр Swift переводит в Int ловушкой — в канал не пускаем;
        # граница та же, что у приложения: |x|, |y| ≤ 100 000.
        pimp = pimp_testlib.load_pimp("pimp_point_test")
        for good in ("1200,-40", "100000,0", "-99999.5,12.123456", "0,0"):
            self.assertEqual(pimp.parse_place(good), good)
        for bad in ("100001,0", "999999,0", "0,-1000000", "99999999999999999999,0", "1e300,0", "1.1234567,0", "inf,0"):
            with self.subTest(bad=bad), self.assertRaises(pimp.argparse.ArgumentTypeError):
                pimp.parse_place(bad)
        done = self.call("open", "Dictator", "--at", "99999999999999999999,0")
        self.assertEqual(done.returncode, 1)
        self.assertIn("числа до 100 000", done.stderr)
        self.assertEqual(list(self.dir.glob("*.json")), [], "в канал ничего не ушло")


class WF141DesktopGuardTest(unittest.TestCase):
    """#9116: агент (CLAUDECODE в окружении) без --desktop окна Claude Desktop не трогает."""

    AGENT = {"CLAUDECODE": "1"}
    setUp = PimpCliTest.setUp
    tearDown = PimpCliTest.tearDown
    call = PimpCliTest.call

    def test_agent_refused_without_desktop_flag(self):
        for argv in (("open", "Dictator"), ("close", "Dictator"), ("arrange",), ("renew", "Risovalka"),
                     ("main", "Rick"), ("layout", "restore", "Утро"), ("restore-screens",), ("hide",),
                     ("show",), ("paste-clipboard",), ("paste-airdrop",), ("restart-claude",)):
            done = self.call(*argv, extra=self.AGENT)
            self.assertEqual(done.returncode, 1, argv)
            self.assertIn("Окна Claude открывает только Элвис/Рик", done.stdout, argv)
            self.assertIn("pimp.py term", done.stdout, argv)
            self.assertFalse(self.dir.exists(), f"{argv}: запрос не ушёл в канал")
        done = self.call("open", "Dictator", extra={"CLAUDE_CODE_ENTRYPOINT": "cli"})
        self.assertEqual(done.returncode, 1)

    def test_agent_with_desktop_flag_and_human_pass(self):
        for argv in (("open", "Dictator", "--desktop"), ("--desktop", "open", "Dictator")):
            done = self.call(*argv, result=fixture("new-window.result.json"), extra=self.AGENT)
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            request = self.app.requests[0]
            self.assertEqual(list(request.keys()), list(fixture("new-window.request.json").keys()),
                             "--desktop в запрос не попадает")
            self.app = None
            shutil.rmtree(self.dir)
        # Без агента в окружении (Терминал Элвиса, кнопка «↻ Claude» PimpViewer) — как раньше.
        done = self.call("open", "Dictator", result=fixture("new-window.result.json"))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_agent_keeps_harmless_commands(self):
        done = self.call("send", "--chat", CHAT, "привет", result=fixture("send.result.json"), extra=self.AGENT)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.app = None
        shutil.rmtree(self.dir)
        done = self.call("layout", "save", "Утро", result=fixture("layout-save.result.json"), extra=self.AGENT)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)


# ---- #10527: pimp.py live-check (контракт К-HEALTH) ------------------------------------------------
LIVE_EXPRESSION = ('(() => { const m = window.__myclaude; if (!m) return null; if (typeof m.health !== "function") '
                   'return { v: 0 }; const h = m.health(); return h === null ? { v: 0, other: true } : h; })()')
APP_PROBE = "// myclaude-chats v1 chats-1617021464-7114\n(() => ({}))()\n"


class FakeLoader(threading.Thread):
    """Лоадер на минималках: увидел новый probe.js — кладёт probe-result.json с ответом answer(script).
    answer вернул None — молчит (страницы не ответили). `stale` — круг приложения (с nonce), который
    ложится ПЕРЕД ответом на наш скрипт: CLI обязан его пропустить."""

    def __init__(self, support: Path, answer, stale=None):
        super().__init__(daemon=True)
        self.support = support
        self.answer = answer
        self.stale = stale
        self.scripts = []
        self._halt = threading.Event()

    def write(self, results):
        body = json.dumps({"at": "2026-10-22T09:14:05.400Z", "results": results}, ensure_ascii=False)
        (self.support / "probe-result.json").write_text(body, encoding="utf-8")

    def run(self):
        probe = self.support / "probe.js"
        last = None
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline and not self._halt.is_set():
            try:
                stat = probe.stat()
                stamp = (stat.st_mtime_ns, stat.st_size)
                script = probe.read_text(encoding="utf-8")
            except OSError:
                stamp = script = None
            if stamp is not None and stamp != last:
                last = stamp
                self.scripts.append(script)
                if script.startswith("// pimp live-check v1 ") and self.stale is not None:
                    time.sleep(0.05)
                    self.write(self.stale)
                results = self.answer(script)
                if results is not None:
                    time.sleep(0.05)
                    self.write(results)
            time.sleep(0.02)

    def stop(self):
        self._halt.set()


def probe_entry(number, url, result):
    return {"id": number, "url": url,
            "source": {"loader": 8, "origin": "https://claude.ai", "url": url, "processId": 9, "routingId": 2},
            "result": result}


def report_pages():
    """Страницы эталона отчёта (tests/fixtures/live-check.json) записями probe-result.json."""
    pages = pimp_testlib.fixture_json("live-check.json")["pages"]
    return [probe_entry(page["id"], page["health"]["page"], page["health"]) for page in pages]


class LiveCheckTest(unittest.TestCase):
    setUp_base = PimpCliTest.setUp
    tearDown_base = PimpCliTest.tearDown
    call_base = PimpCliTest.call

    def setUp(self):
        self.setUp_base()
        self.loader = None
        (self.support / "installed.json").write_text(json.dumps({"version": "3.1623.0"}), encoding="utf-8")
        self.live = self.support / "live-check"

    def tearDown(self):
        if self.loader is not None:
            self.loader.stop()
            self.loader.join(timeout=2)
        self.tearDown_base()

    def call(self, *argv, wait="3", extra=None, **kwargs):
        env = {"MYCLAUDE_LIVE_WAIT": wait, "MYCLAUDE_CLAUDE_APP": str(self.support / "NoClaude.app"),
               "MYCLAUDE_SLICE_DIR": str(self.support / "claude-dom")}
        env.update(extra or {})
        return self.call_base(*argv, extra=env, **kwargs)

    def load(self, answer, stale=None):
        self.loader = FakeLoader(self.support, answer, stale=stale)
        self.loader.start()

    def pages_answer(self, results):
        return lambda script: results if script.startswith("// pimp live-check v1 ") else None

    def app_answer(self, app):
        return dict(fixture("live-check.result.json"), app=app)

    def test_green(self):
        # Канал держало приложение — берём; после проверки probe.js нет, приложение заберёт канал обратно.
        (self.support / "probe.js").write_text(APP_PROBE, encoding="utf-8")
        health = pimp_testlib.fixture_json("health.json")
        self.load(self.pages_answer([probe_entry(3, health["page"], health)]))
        done = self.call("live-check", result=fixture("live-check-first.result.json"))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertFalse((self.support / "probe.js").exists(), "probe.js удалён")
        script = self.loader.scripts[-1]
        head, body, tail = script.split("\n")
        self.assertRegex(head, r"^// pimp live-check v1 \d{13,}-\d{4}$")
        self.assertEqual(body, LIVE_EXPRESSION, "выражение — побайтно по контракту")
        self.assertEqual(tail, "")
        request = self.app.requests[0]
        self.assertEqual(list(request), list(fixture("live-check.request.json")), "порядок полей запроса")
        self.assertEqual(request["action"], "live-check")
        lines = done.stdout.splitlines()
        self.assertRegex(lines[0], r"^Claude 3\.1623\.0 · страница wf274-page-100 · \d{4}-\d{2}-\d{2} \d{2}:\d{2}$")
        self.assertEqual(lines[1].split(), ["anchors", "wide", "fold", "title", "sidebarButton", "look",
                                            "ownButtons", "claudeButtons", "install"])
        self.assertEqual(lines[2].split(), ["main", "широкое", "Сторожи", "Пимпа"] + ["✓"] * 9)
        self.assertEqual(lines[3], "Пимп 1.10.65: statusItem ✓ · iconNumber – · stripWindow – · clickLog – · "
                                   "panelOpaque –")
        dated = sorted(self.live.glob("*-claude-3.1623.0.json"))
        self.assertEqual(len(dated), 1)
        self.assertEqual(lines[-1], f"Отчёт: {dated[0]}")
        report = json.loads(dated[0].read_text(encoding="utf-8"))
        self.assertTrue(report["ok"])
        self.assertEqual(report["red"], [])
        self.assertEqual((self.live / "live-check.json").read_text(encoding="utf-8"),
                         dated[0].read_text(encoding="utf-8"), "копия последнего прогона")
        self.assertEqual(oct(self.live.stat().st_mode & 0o777), oct(0o700))
        self.assertEqual(oct(dated[0].stat().st_mode & 0o777), oct(0o600))
        self.assertEqual([p.name for p in self.live.iterdir() if p.name.startswith(".")], [], "временных нет")

    def test_red_report_matches_fixture(self):
        sample = pimp_testlib.fixture_json("live-check.json")
        # Круг приложения, легший после нашей записи, — не наш ответ: CLI его пропускает.
        stale = [probe_entry(3, "https://claude.ai/epitaxy/x", {"nonce": "chats-1-0001", "kind": "main"})]
        self.load(self.pages_answer(report_pages()), stale=stale)
        done = self.call("live-check", result=self.app_answer(sample["app"]))
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        report = json.loads((self.live / "live-check.json").read_text(encoding="utf-8"))
        self.assertRegex(report.pop("at"), r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$")
        sample.pop("at")
        self.assertEqual(report, sample, "отчёт = эталон tests/fixtures/live-check.json")
        self.assertEqual(json.dumps(report, ensure_ascii=False), json.dumps(sample, ensure_ascii=False),
                         "и порядок ключей")
        out = done.stdout
        self.assertIn("✗ main широкое Сторожи Пимпа · wide: dock-left: лента 0–1184, дока 0–1184", out)
        self.assertIn("✗ main широкое Сторожи Пимпа · fold: no-target: modelRow", out)
        self.assertIn("popout узкое Вкуснофф — меню", out)
        self.assertNotIn("\033[", out, "не терминал — без цвета")

    def test_json_prints_report_only(self):
        self.load(self.pages_answer(report_pages()))
        done = self.call("live-check", "--json", result=self.app_answer(fixture("live-check.result.json")["app"]))
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        printed = json.loads(done.stdout)
        self.assertEqual(printed, json.loads((self.live / "live-check.json").read_text(encoding="utf-8")))
        self.assertIn({"window": "app", "chat": "", "check": "clickLog"}, printed["red"])
        self.assertEqual(printed["red"][-1], {"window": "app", "chat": "", "check": "clickLog"}, "app — последним")

    def test_pimp_silent_is_red_answer(self):
        health = pimp_testlib.fixture_json("health.json")
        self.load(self.pages_answer([probe_entry(3, health["page"], health)]))
        done = self.call("live-check")                    # Пимпа нет: taken не появится
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        report = json.loads((self.live / "live-check.json").read_text(encoding="utf-8"))
        self.assertIsNone(report["app"])
        self.assertIsNone(report["pimp"])
        self.assertEqual(report["red"], [{"window": "app", "chat": "", "check": "answer"}])
        self.assertIn("Пимп: не ответил (не взял запрос)", done.stdout)
        self.assertIn("✗ Пимп · answer: не взял запрос", done.stdout)

    def test_no_pages_exit_2_without_report(self):
        for results in ([], [probe_entry(3, "https://claude.ai/epitaxy/x", {"v": 0})]):
            with self.subTest(results=results):
                shutil.rmtree(self.dir, ignore_errors=True)
                self.load(self.pages_answer(results))
                done = self.call("live-check", result=fixture("live-check-first.result.json"))
                self.loader.stop()
                self.loader.join(timeout=2)
                self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
                self.assertIn("Ни одной страницы с health()", done.stdout)
                self.assertFalse(self.live.exists(), "при коде 2 отчёт не пишется")
                self.assertFalse((self.support / "probe.js").exists())

    def test_page_without_inject_is_red_install(self):
        health = pimp_testlib.fixture_json("health.json")
        self.load(self.pages_answer([probe_entry(3, health["page"], health),
                                     probe_entry(5, "https://claude.ai/settings", None)]))
        done = self.call("live-check", result=fixture("live-check-first.result.json"))
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        report = json.loads((self.live / "live-check.json").read_text(encoding="utf-8"))
        self.assertEqual(report["red"], [{"window": "main", "chat": "", "check": "install"}])
        self.assertIn("✗ main · install:", done.stdout)

    def test_non_chat_page_is_not_red(self):
        health = pimp_testlib.fixture_json("health.json")
        self.load(self.pages_answer([probe_entry(3, health["page"], health),
                                     probe_entry(5, "https://claude.ai/settings", {"v": 0, "other": True})]))
        done = self.call("live-check", result=fixture("live-check-first.result.json"))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        report = json.loads((self.live / "live-check.json").read_text(encoding="utf-8"))
        self.assertEqual((report["red"], report["unchecked"], len(report["pages"])), ([], 0, 1),
                         "страница не чата (health() → null) — не красная и не «без health()»")

    def test_busy_channel_untouched(self):
        foreign = "window.__myclaude?.status?.()\n"
        (self.support / "probe.js").write_text(foreign, encoding="utf-8")
        done = self.call("live-check")
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("Канал probe занят", done.stdout)
        self.assertEqual((self.support / "probe.js").read_text(encoding="utf-8"), foreign, "чужое не трогаем")
        self.assertFalse(self.dir.exists(), "в канал «Пимп» ничего не ушло")
        self.assertFalse(self.live.exists())

    def test_timeout_removes_probe(self):
        self.load(lambda script: None)                    # страницы молчат
        done = self.call("live-check", wait="1")
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("Страницы не ответили за 1 с", done.stdout)
        self.assertFalse((self.support / "probe.js").exists(), "probe.js удалён и после ошибки")
        self.assertFalse(self.live.exists())

    def test_ctrl_c_removes_probe(self):
        env = dict(os.environ, MYCLAUDE_PIMP_DIR=str(self.dir), MYCLAUDE_LIVE_WAIT="30", MYCLAUDE_PIMP_TAKEN="30",
                   MYCLAUDE_CLAUDE_APP=str(self.support / "NoClaude.app"))
        probe = self.support / "probe.js"
        for sig in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(sig=sig):
                proc = subprocess.Popen([sys.executable, str(CLI), "live-check"], env=env,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline and not probe.exists():
                    time.sleep(0.02)
                self.assertTrue(probe.exists(), "CLI положил probe.js")
                proc.send_signal(sig)
                proc.communicate(timeout=10)
                self.assertNotEqual(proc.returncode, 0)
                self.assertFalse(probe.exists(), "probe.js удалён после прерывания")

    def test_press_is_stage_3(self):
        (self.support / "probe.js").write_text(APP_PROBE, encoding="utf-8")
        done = self.call("live-check", "--press")
        self.assertEqual(done.returncode, 2)
        self.assertEqual(done.stdout.strip(), "--press: этап 3, не сделан")
        self.assertEqual((self.support / "probe.js").read_text(encoding="utf-8"), APP_PROBE, "ничего не тронуто")
        self.assertFalse(self.dir.exists())

    def test_old_reports_pruned_to_50(self):
        self.live.mkdir(mode=0o700)
        for day in range(55):
            old = self.live / f"2026-08-{day % 28 + 1:02d}-claude-1.{day}.json"
            old.write_text("{}", encoding="utf-8")
            os.utime(old, (1_000_000 + day, 1_000_000 + day))
        health = pimp_testlib.fixture_json("health.json")
        self.load(self.pages_answer([probe_entry(3, health["page"], health)]))
        done = self.call("live-check", result=fixture("live-check-first.result.json"))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        dated = [p.name for p in self.live.iterdir() if p.name != "live-check.json"]
        self.assertEqual(len(dated), 50)
        self.assertNotIn("2026-08-01-claude-1.0.json", dated, "старейшие ушли")
        self.assertTrue(any(name.endswith("-claude-3.1623.0.json") for name in dated), "свежий остался")

    def test_slice(self):
        health = pimp_testlib.fixture_json("health.json")
        root = {"t": "body", "r": [0, 0, 1200, 800], "k": [{"t": "div", "c": ["epitaxy-chat-panel"],
                                                           "r": [0, 0, 1200, 800]}]}

        def answer(script):
            if script.startswith("// pimp live-check v1 "):
                return [probe_entry(3, health["page"], health)]
            if script.startswith("// pimp live-check slice v1 "):
                nonce = script.split("\n", 1)[0].rsplit(" ", 1)[1]
                return [probe_entry(3, health["page"], json.dumps({"pimpSlice": nonce, "page": "wf274-page-100",
                                                                   "viewport": [1200, 800], "dpr": 2, "nodes": 2,
                                                                   "root": root}))]
            return None

        self.load(answer)
        done = self.call("live-check", "--slice", "main-wide", result=fixture("live-check-first.result.json"))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        path = self.support / "claude-dom" / "3.1623-main-wide.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(list(data), ["v", "claude", "page", "view", "at", "viewport", "dpr", "root"])
        self.assertEqual((data["claude"], data["page"], data["view"], data["root"]),
                         ("3.1623.0", "wf274-page-100", "main-wide", root))
        self.assertIn(f"Слепок: {path} (2 узла)", done.stdout)
        self.assertFalse((self.support / "probe.js").exists())
        slice_script = self.loader.scripts[-1]
        self.assertIn(json.dumps(health["chat"]), slice_script, "слепок только нужного окна")
        shutil.rmtree(self.dir, ignore_errors=True)
        self.load(answer)
        done = self.call("live-check", "--slice", "popout", result=fixture("live-check-first.result.json"))
        self.assertEqual(done.returncode, 2)
        self.assertIn("Слепок: нет окна вида popout", done.stdout)
        self.assertFalse((self.support / "probe.js").exists())

    def test_slice_script_reads_only_shape(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("нет node")
        pimp = pimp_testlib.load_pimp("pimp_live_slice")
        health = {"page": "https://claude.ai/epitaxy/local_x", "chat": "local_x", "kind": "main"}
        script = self.support / "slice.js"
        script.write_text(pimp.slice_script(health, "n-1"), encoding="utf-8")
        runner = self.support / "run.mjs"
        runner.write_text("""import fs from "node:fs";
const el = (tag, attrs = {}, kids = [], rect = [0, 0, 10, 10]) => ({ tagName: tag.toUpperCase(), children: kids,
  getAttribute: name => (name in attrs ? attrs[name] : null),
  getBoundingClientRect: () => ({ left: rect[0], top: rect[1], width: rect[2], height: rect[3] }) });
const body = el("body", { class: "a myclaude-x" }, [
  el("div", { id: "myclaude-rail" }, [el("span")]),
  el("div", { "data-testid": "t", "aria-label": "Model: Opus 5.5", title: "секрет", "data-state": "open",
              style: "color:red", "data-myclaude-x": "1", "data-row-key": "k", "data-cds": "ChatComposerChin",
              role: "group", "aria-hidden": "x".repeat(80) }, [
    el("svg", {}, [el("path")]), el("script"), el("style"),
    el("h2", { id: "как-устроено", "aria-label": "Привет мир" }),
    el("button", { id: "radix-:r1:", "aria-label": "Show sidebar", type: "button" }),
  ], [1.4, 2.6, 100.2, 50.5]),
  el("div", { id: "myclaude-image-undo-composer-v1", role: "group" }, [
    el("button", { "data-pane-title": "Секретный чат", "aria-haspopup": "dialog" }),
  ]),
]);
const want = JSON.parse(process.argv[3]);
globalThis.window = { __myclaude: { health: () => ({ v: 1, version: "wf-x", ...want }) },
  innerWidth: 1200, innerHeight: 800, devicePixelRatio: 2 };
globalThis.document = { body };
process.stdout.write(JSON.stringify((0, eval)(fs.readFileSync(process.argv[2], "utf8"))));
""", encoding="utf-8")

        def run(want):
            done = subprocess.run([node, str(runner), str(script), json.dumps(want)], capture_output=True,
                                  text=True, timeout=180)
            self.assertEqual(done.returncode, 0, done.stderr)
            out = json.loads(done.stdout)
            return json.loads(out) if isinstance(out, str) else out

        out = run(health)
        self.assertEqual((out["pimpSlice"], out["page"], out["viewport"], out["dpr"], out["nodes"]),
                         ("n-1", "wf-x", [1200, 800], 2, 7))
        body = out["root"]
        self.assertEqual(body["c"], ["a"], "классы myclaude-* вырезаны")
        self.assertEqual(len(body["k"]), 2, "узел myclaude-… вырезан с детьми")
        self.assertEqual(body["k"][1], {"t": "div", "role": "group", "r": [0, 0, 10, 10], "k": [
            {"t": "button", "a": {"aria-haspopup": "dialog", "data-pane-title": ""}, "r": [0, 0, 10, 10]}]},
            "узел Claude с нашим id остаётся без id; data-pane-title — только наличие")
        div = body["k"][0]
        self.assertEqual(div, {"t": "div", "tid": "t", "cds": "ChatComposerChin", "role": "group", "aria": "Model:…",
                               "a": {"aria-hidden": "x" * 64, "data-state": "open"}, "r": [1, 3, 100, 51],
                               "k": div["k"]})
        self.assertEqual([kid["t"] for kid in div["k"]], ["svg", "h2", "button"], "script и style не пишутся")
        self.assertNotIn("k", div["k"][0], "у svg детей нет")
        self.assertEqual(div["k"][1], {"t": "h2", "r": [0, 0, 10, 10]}, "id из текста и чужой aria-label не идут")
        self.assertEqual(div["k"][2], {"t": "button", "id": "radix-:r1:", "aria": "Show sidebar",
                                       "a": {"type": "button"}, "r": [0, 0, 10, 10]})
        self.assertIsNone(run(dict(health, chat="local_other")), "чужое окно отвечает null")

    def test_summary_and_digest_line(self):
        report = pimp_testlib.fixture_json("live-check.json")
        self.live.mkdir(mode=0o700)
        (self.live / "live-check.json").write_text(json.dumps(report, ensure_ascii=False), encoding="utf-8")
        app = self.support / "Claude.app" / "Contents"
        app.mkdir(parents=True)
        (self.support / "claude.json").write_text(json.dumps({"projectsRoot": str(self.support / "none")}),
                                                  encoding="utf-8")
        line = "проверка окна Claude 3.1623.0: 2 красных (wide, fold)"
        for version, expected in (("3.1623.0", True), ("3.1700.0", False)):
            with self.subTest(version=version):
                with (app / "Info.plist").open("wb") as handle:
                    plistlib.dump({"CFBundleShortVersionString": version}, handle)
                env = {"MYCLAUDE_CLAUDE_APP": str(self.support / "Claude.app")}
                digest = self.call("digest", extra=env)
                self.assertEqual(digest.returncode, 0, digest.stderr)
                summary = self.call("summary", extra=env)            # Пимп молчит — строка всё равно есть
                self.assertEqual(summary.returncode, 1)
                for done in (digest, summary):
                    self.assertEqual(line in done.stdout.splitlines(), expected, done.stdout)
                self.assertNotIn("проверка окна", self.call("digest", "--json", extra=env).stdout)


if __name__ == "__main__":
    unittest.main()
