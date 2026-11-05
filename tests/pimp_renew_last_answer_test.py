#!/usr/bin/env python3
"""renew начинает новый чат с последнего ответа прежнего Элвису (#10904, слово Элвиса 24.10.2026: «чтобы этот
чат начинался с твоего последнего ответа мне… чтобы я нить повествования не терял»).

Сессии и транскрипты Claude — подставные (MYCLAUDE_CLAUDE_SESSIONS, MYCLAUDE_CLAUDE_PROJECTS), канал —
MYCLAUDE_PIMP_DIR и FakeApp: проверяем, что уходит в запрос `text` и что сказано строкой.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pimp_testlib  # noqa: E402

CLI = pimp_testlib.CLI
pimp = pimp_testlib.load_pimp("pimp_for_renew_last_answer_test")
OLD = "local_11111111-2222-4333-8444-555555555555"
CLI_ID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
SERVICE = "Режим коротких ответов. Ты — Рик, главный чат Элвиса."


def human(text, stamp="2026-10-24T16:30:00.000Z"):
    return {"type": "user", "isSidechain": False, "timestamp": stamp,
            "message": {"role": "user", "content": text}}


def tool_result():
    return {"type": "user", "isSidechain": False,
            "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}}


def said(text, mid, stop="end_turn", stamp="2026-10-24T16:33:06.000Z", kind="text"):
    block = {"type": "text", "text": text} if kind == "text" else {"type": "thinking", "thinking": "…"}
    return {"type": "assistant", "isSidechain": False, "timestamp": stamp,
            "message": {"id": mid, "role": "assistant", "stop_reason": stop, "content": [block]}}


def mail(stamp="2026-10-24T16:34:00.000Z"):
    return human("<task-notification>\n<summary>Stop hook feedback</summary>\n</task-notification>\n"
                 "<system-reminder>Почта Рика: 1 входящих</system-reminder>", stamp)


class AnswerToHumanTest(unittest.TestCase):
    def test_last_answer_to_human_skips_mail_and_service_turns(self):
        records = [
            human("Как дела?"), said("Старый ответ.", "m0"),
            human("Покажи ролик ещё разок"),
            said("Смотрю.", "m1", stop="tool_use"), tool_result(),
            said("", "m2", kind="thinking"),                       # думанье — тот же id, что и текст
            said("**Ролик — выше:** твой C4077.", "m2"),
            mail(), said("Сам ничего не пишу. Почта разобрана.", "m3"),
            {"type": "user", "isMeta": True, "message": {"content": "[Your previous response had no visible output.]"}},
            human("Another Claude session sent a message: привет"), said("Принял.", "m4"),
            human("<cross-session-message from=\"x\">письмо</cross-session-message>"), said("Ок.", "m5"),
            mail("2026-10-24T16:35:00.000Z"),
            said("Меняю чат.", "m6", stop="tool_use"),               # ход смены — не закончен
        ]
        text, stamp = pimp.answer_to_human(records)
        self.assertEqual(text, "**Ролик — выше:** твой C4077.")
        self.assertEqual(stamp, "2026-10-24T16:33:06.000Z")

    def test_word_mid_turn_and_pasted_count_as_human(self):
        records = [
            mail(), said("Шаг.", "m1", stop="tool_use"), tool_result(),
            {"type": "attachment", "attachment": {"type": "queued_command", "prompt": "И ещё одно, срочно"}},
            said("Сделал и то, и другое.", "m2"),
            mail(), said("Почта.", "m3"),
        ]
        self.assertEqual(pimp.answer_to_human(records)[0], "Сделал и то, и другое.")
        pasted = [human("\n\n<pasted_content id=\"ff85\">\nДлинная диктовка\n</pasted_content>"), said("Ответ.", "m9")]
        self.assertEqual(pimp.answer_to_human(pasted)[0], "Ответ.")

    def test_no_human_or_empty_answer_gives_nothing(self):
        self.assertEqual(pimp.answer_to_human([mail(), said("Почта.", "m1")]), ("", ""))
        # Слово было, ответа текстом нет — берём прежний ответ на слово, а не почту после.
        records = [human("Раз"), said("Первый.", "m1"), human("Два"), said("", "m2", kind="thinking"),
                   mail(), said("Почта.", "m3")]
        self.assertEqual(pimp.answer_to_human(records)[0], "Первый.")

    def test_clip_answer_marks_cut(self):
        self.assertEqual(pimp.clip_answer("коротко", 100), "коротко")
        long = ("слово " * 2000).strip()
        cut = pimp.clip_answer(long, 6000)
        body, mark = cut.split("\n\n… (обрезал: ")
        self.assertLessEqual(len(body), 6000)
        self.assertFalse(body.endswith(" "))
        self.assertTrue(long.startswith(body))
        self.assertEqual(mark, f"здесь {len(body)} из {len(long)} знаков, целиком — в прежнем чате)")


class RenewLastAnswerCliTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.dir = self.root / "pimp"
        self.dir.mkdir()
        self.sessions = self.root / "sessions" / "acc" / "place"
        self.sessions.mkdir(parents=True)
        self.transcripts = self.root / "projects" / "-x-Rick"
        self.transcripts.mkdir(parents=True)
        self.app = None

    def tearDown(self):
        if self.app is not None:
            self.app.stop()
            self.app.join(timeout=2)

    def write_chat(self, records, folder="/x/Projects/Rick", chat=OLD):
        body = {"sessionId": chat, "cliSessionId": CLI_ID, "cwd": folder, "title": "Рик"}
        (self.sessions / f"{chat}.json").write_text(json.dumps(body, ensure_ascii=False), encoding="utf-8")
        lines = "\n".join(json.dumps(record, ensure_ascii=False) for record in records)
        (self.transcripts / f"{CLI_ID}.jsonl").write_text(lines + "\n", encoding="utf-8")

    def renew(self, *argv, stdin=None, session=None):
        shutil.rmtree(self.dir, ignore_errors=True)     # прошлый запрос в каталоге ответил бы первым
        self.dir.mkdir()
        self.app = pimp_testlib.FakeApp(self.dir, pimp_testlib.fixture_json("pimp/renew-window.result.json"))
        self.app.start()
        env = dict(os.environ, MYCLAUDE_PIMP_DIR=str(self.dir), MYCLAUDE_PIMP_WAIT="5", MYCLAUDE_PIMP_TAKEN=pimp_testlib.APP_TAKEN_S,
                   MYCLAUDE_CLAUDE_SESSIONS=str(self.root / "sessions"),
                   MYCLAUDE_CLAUDE_PROJECTS=str(self.root / "projects"))
        for key in ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_HOST_SESSION_ID"):
            env.pop(key, None)
        if session:
            env["CLAUDE_CODE_HOST_SESSION_ID"] = session
        done = subprocess.run([sys.executable, str(CLI), "renew", *argv], env=env, input=stdin,
                              capture_output=True, text=True, timeout=180)
        self.app.join(timeout=2)
        return done

    def test_block_first_then_rule_then_service(self):
        self.write_chat([human("Покажи ролик"), said("**Ролик — выше:**\n\n1. C4077, 4:20.", "m1"),
                         mail(), said("Сам ничего не пишу.", "m2")])
        done = self.renew(OLD, "--text", "-", stdin=SERVICE + "\n")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.strip(), "Заменил окно «Ожидание задачи» новым чатом "
                         "local_9f1c2d3e-0000-4000-8000-000000000102")
        text = self.app.requests[0]["text"]
        clock = pimp.local_clock("2026-10-24T16:33:06.000Z")
        self.assertEqual(text.split("\n"), [
            f"Последний ответ Рика тебе (из прежнего чата, {clock}):", "",
            "**Ролик — выше:**", "", "1. C4077, 4:20.", "",
            "———",
            "Блок выше — последний ответ прежнего Рика Элвису; Элвис его видит в начале чата — "
            "дословно не повторяй, продолжай по тексту ниже.", "",
            SERVICE])

    def test_long_answer_clipped_and_ceiling_kept(self):
        self.write_chat([human("Расскажи всё"), said(("строка ответа\n" * 1000).strip(), "m1")])
        service = "с" * 15000
        done = self.renew(OLD, "--text", service)
        self.assertEqual(done.returncode, 0, done.stderr)
        text = self.app.requests[0]["text"]
        self.assertLessEqual(len(text), pimp.RENEW_TEXT_LIMIT)
        self.assertIn("… (обрезал: здесь ", text)
        self.assertTrue(text.endswith("\n\n" + service))
        head, rest = text.split("\n\n———\n", 1)
        self.assertLess(len(head), 5000, "места под ответ меньше 6000 — режется по потолку renew")

    def test_answer_capped_at_6000(self):
        self.write_chat([human("Ещё"), said("а" * 9000, "m1")])
        done = self.renew(OLD, "--text", SERVICE)
        text = self.app.requests[0]["text"]
        answer = text.split("\n\n", 1)[1].split("\n\n… (обрезал: ")[0]
        self.assertEqual(len(answer), 6000)
        self.assertIn("здесь 6000 из 9000 знаков", text)

    def test_not_found_said_and_text_kept(self):
        self.write_chat([mail(), said("Почта.", "m1")])
        done = self.renew(OLD, "--text", SERVICE)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.app.requests[0]["text"], SERVICE)
        self.assertTrue(done.stdout.strip().endswith(
            "; последний ответ прежнего чата не нашёл — новый чат начат без него"), done.stdout)

    def test_opt_out_and_without_text(self):
        self.write_chat([human("Слово"), said("Ответ.", "m1")])
        done = self.renew(OLD, "--text", SERVICE, "--no-last-answer")
        self.assertEqual(self.app.requests[0]["text"], SERVICE)
        self.assertNotIn("не нашёл", done.stdout)
        self.app = None
        done = self.renew(OLD)
        self.assertNotIn("text", self.app.requests[0], "без --text первого сообщения нет — блока тоже")

    def test_project_target_uses_own_chat_of_that_folder(self):
        self.write_chat([human("Слово"), said("Ответ своему.", "m1")], folder="/x/Projects/Marketolog")
        done = self.renew("Marketolog", "--text", SERVICE, session=OLD)
        text = self.app.requests[0]["text"]
        self.assertTrue(text.startswith("Последний ответ Marketolog тебе (из прежнего чата"), text)
        self.assertIn("последний ответ прежнего чата Элвису", text)
        # Свой чат из другой папки — чей прежний, не знаем: текст как был и без приписки.
        self.app = None
        done = self.renew("Risovalka", "--text", SERVICE, session=OLD)
        self.assertEqual(self.app.requests[0]["text"], SERVICE)
        self.assertNotIn("не нашёл", done.stdout)


if __name__ == "__main__":
    unittest.main()
