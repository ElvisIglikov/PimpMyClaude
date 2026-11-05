#!/usr/bin/env python3
"""renew и черновик Элвиса (#11201, WF302; слово Элвиса 30.10 ~17:45: «Я там скриншоты ещё закреплял, скриншоты
не закрепились… диктовки ещё куски большие не вставились»): строка вывода говорит, что стало с набранным и
вложениями прежнего чата, а смена чата ждёт паузы в наборе (Пимп отвечает busy с typing).

Канал — MYCLAUDE_PIMP_DIR и FakeApp; сессии Claude — пустые подставные (последний ответ #10904 здесь не важен).
"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pimp_testlib  # noqa: E402

CLI = pimp_testlib.CLI
pimp = pimp_testlib.load_pimp("pimp_for_renew_draft_test")
RICK = "local_301ae90e-755b-49e8-8ee1-ae716fb5ff2f"
FRESH = "local_9f1c2d3e-0000-4000-8000-000000000102"


def main_answer(draft=None):
    answer = {"id": "x", "at": "2026-10-30T14:00:05.000Z", "ok": True, "error": "", "fromResolved": True,
              "screen": "", "window": {"title": "Рик", "chat": FRESH, "frame": [0, 0, 800, 700]},
              "replaced": RICK, "main": True}
    if draft is not None:
        answer["draft"] = draft
    return answer


BUSY_TYPING = {"id": "x", "at": "2026-10-30T14:00:00.000Z", "ok": False, "error": "busy", "fromResolved": True,
               "screen": "", "typing": True}


class SayDraftTest(unittest.TestCase):
    def test_no_draft_no_words(self):
        self.assertEqual(pimp.say_draft(None), "")
        self.assertEqual(pimp.say_draft({"state": "ok", "chars": 0, "want": 0, "landed": 0}), "")

    def test_text_and_pictures(self):
        line = pimp.say_renew(main_answer({"state": "ok", "chars": 120, "want": 3, "landed": 3}))
        self.assertTrue(line.startswith(f"Новый чат {FRESH} открыл в главном окне"))
        self.assertIn("черновик Элвиса перенёс в поле нового чата (текст 120 зн. и 3 вложения)", line)
        self.assertIn("(1 вложение)", pimp.say_draft({"state": "ok", "chars": 0, "want": 1, "landed": 1}))

    def test_part_fail_wait(self):
        self.assertIn("вложений 1 из 3 — остальные в поле прежнего чата",
                      pimp.say_draft({"state": "part", "chars": 5, "want": 3, "landed": 1}))
        self.assertIn("черновик не перенёс (поле нового чата не освободилось) — он в поле прежнего чата",
                      pimp.say_draft({"state": "fail", "why": "поле нового чата не освободилось"}))
        self.assertIn("ещё переносится", pimp.say_draft({"state": "wait"}))


class RenewTypingCliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name) / "pimp"
        self.dir.mkdir(parents=True)
        self.app = None

    def tearDown(self):
        if self.app is not None:
            self.app.stop()
            self.app.join(timeout=2)

    def call(self, results, extra=None):
        self.app = pimp_testlib.FakeApp(self.dir, results, count=len(results))
        self.app.start()
        env = dict(os.environ, MYCLAUDE_PIMP_DIR=str(self.dir), MYCLAUDE_PIMP_WAIT="5", MYCLAUDE_PIMP_TAKEN=pimp_testlib.APP_TAKEN_S,
                   MYCLAUDE_CLAUDE_SESSIONS=str(Path(self.tmp.name) / "none"),
                   MYCLAUDE_CLAUDE_PROJECTS=str(Path(self.tmp.name) / "none"),
                   PIMP_TERM_TMUX="none", CLAUDE_CODE_HOST_SESSION_ID=RICK, **(extra or {}))
        for key in pimp.AGENT_ENV:      # гейт гоняют из чата агента: без этого renew отказал бы (#9116)
            env.pop(key, None)
        return subprocess.run([sys.executable, str(CLI), "renew", RICK, "--text", "Ты — Рик."], env=env,
                              capture_output=True, text=True, timeout=180)

    def test_waits_for_typing_pause_then_says_draft(self):
        # Короткий потолок общего «занят» не мешает: пока Пимп говорит typing, ждём паузы.
        done = self.call([BUSY_TYPING, main_answer({"state": "ok", "chars": 40, "want": 0, "landed": 0})],
                         extra={"MYCLAUDE_PIMP_BUSY": "0.1"})
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(len(self.app.requests), 2)
        self.assertNotEqual(self.app.requests[0]["id"], self.app.requests[1]["id"])
        self.assertIn("черновик Элвиса перенёс в поле нового чата (текст 40 зн.)", done.stdout)
        self.assertIn("; ждал паузы в наборе", done.stdout)

    def test_typing_without_end_says_busy(self):
        done = self.call([BUSY_TYPING], extra={"MYCLAUDE_PIMP_BUSY": "0.1", "MYCLAUDE_PIMP_TYPING": "0.1"})
        self.assertEqual(done.returncode, 1)
        self.assertIn("PMP занят", done.stdout)


if __name__ == "__main__":
    unittest.main()
