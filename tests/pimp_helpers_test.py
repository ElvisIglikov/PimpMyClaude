#!/usr/bin/env python3
"""Общие помощники CLI «Пимп» после чистки ревизии WF247 (WF248 К2): хвост JSONL, текст ключа или stdin,
корень проектов и projects.json — по одной копии на правило."""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pimp_testlib  # noqa: E402

pimp = pimp_testlib.load_pimp("pimp_for_helpers_test")


class HelpersTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.support = Path(tmp.name)               # подставной MyClaude/
        (self.support / "pimp").mkdir()
        patcher = unittest.mock.patch.dict(os.environ, {"MYCLAUDE_PIMP_DIR": str(self.support / "pimp")})
        patcher.start()
        self.addCleanup(patcher.stop)

    def main(self, *argv, stdin=""):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), unittest.mock.patch.object(sys, "stdin", io.StringIO(stdin)):
            code = pimp.main(list(argv))
        return code, out.getvalue().strip()

    # ---- хвост файла: одна копия на transcript_tail и term_summary --------------
    def test_read_tail_short_file_whole(self):
        path = self.support / "t.jsonl"
        path.write_bytes(b'{"a":1}\n{"b":2}\n')
        self.assertEqual(pimp.read_tail(path, 1000), [b'{"a":1}', b'{"b":2}', b""])

    def test_read_tail_long_file_drops_torn_first_line(self):
        path = self.support / "t.jsonl"
        path.write_bytes(b'{"first":"' + b"x" * 50 + b'"}\n{"b":2}\n{"c":3}\n')
        self.assertEqual(pimp.read_tail(path, 18), [b'{"b":2}', b'{"c":3}', b""])

    def test_read_tail_missing_file_raises_os_error(self):
        with self.assertRaises(OSError):
            pimp.read_tail(self.support / "нет.jsonl", 10)

    # ---- текст ключа или stdin --------------------------------------------------
    def test_read_text_rules(self):
        self.assertIsNone(pimp.read_text(None))
        self.assertEqual(pimp.read_text("  привет \n"), "привет")
        self.assertEqual(pimp.read_text("   "), "")
        with unittest.mock.patch.object(sys, "stdin", io.StringIO(" со stdin \n")):
            self.assertEqual(pimp.read_text("-"), "со stdin")
        with self.assertRaisesRegex(pimp.TextRefused, "нулевой символ — ничего не отправил"):
            pimp.read_text("a\0b", refused="ничего не отправил")
        with self.assertRaisesRegex(pimp.TextRefused, "длиннее 5 знаков"):
            pimp.read_text("123456", 5)
        self.assertEqual(pimp.read_text(" 12345 ", 5), "12345")

    def test_renew_refuses_zero_byte_before_channel(self):
        # Раньше у renew проверки \0 не было (ревизия WF247): теперь как у send и term.
        code, out = self.main("renew", "Demo", "--text", "-", "--desktop", stdin="a\0b")
        self.assertEqual((code, out), (1, "В тексте нулевой символ — окно не менял"))
        self.assertEqual(list((self.support / "pimp").iterdir()), [], "в канал ничего не ушло")

    def test_send_refuses_before_channel(self):
        code, out = self.main("send", "--project", "Demo", "-", stdin="a\0b")
        self.assertEqual((code, out), (1, "В тексте нулевой символ — ничего не отправил"))
        code, out = self.main("send", "--project", "Demo", "-", stdin="я" * (pimp.SEND_TEXT_LIMIT + 1))
        self.assertEqual((code, out), (1, f"Текст длиннее {pimp.SEND_TEXT_LIMIT} знаков — сократи"))
        self.assertEqual(list((self.support / "pimp").iterdir()), [])

    def test_voice_say_is_gone(self):
        # Голосовой Пимп снят (слово Элвиса 17.10.2026: «Это уже неактуально»): `say` — незнакомая команда.
        code, out = self.main("say", "открой Пимп")
        self.assertEqual((code, out), (1, "Не понял команду — «pimp.py --help» покажет, что умею"))
        self.assertFalse(hasattr(pimp, "run_say"))

    # ---- корень проектов и projects.json ------------------------------------------
    def test_projects_root_from_claude_json(self):
        home = Path.home() / "Projects"
        self.assertEqual(pimp.projects_root(), home, "нет claude.json — запасной корень")
        config = self.support / "claude.json"
        config.write_text("не json", encoding="utf-8")
        self.assertEqual(pimp.projects_root(), home)
        config.write_text("[]", encoding="utf-8")
        self.assertEqual(pimp.projects_root(), home)
        config.write_text(json.dumps({"projectsRoot": "/Users/x/Проекты"}), encoding="utf-8")
        self.assertEqual(pimp.projects_root(), Path("/Users/x/Проекты"))

    def test_saved_projects(self):
        path = self.support / "projects.json"
        self.assertEqual(pimp.saved_projects(), [])
        path.write_text("{", encoding="utf-8")
        self.assertEqual(pimp.saved_projects(), [])
        path.write_text(json.dumps({"version": 1, "projects": {"a": 1}}), encoding="utf-8")
        self.assertEqual(pimp.saved_projects(), [])
        item = {"name": "Demo", "folder": "/x/Demo", "lastUsed": "2026-10-17T00:00:00Z"}
        path.write_text(json.dumps({"version": 1, "projects": [item, "мусор", 3]}), encoding="utf-8")
        self.assertEqual(pimp.saved_projects(), [item])

    def test_terminal_project_folder_uses_list_then_root(self):
        (self.support / "claude.json").write_text(json.dumps({"projectsRoot": "/r"}), encoding="utf-8")
        self.assertEqual(pimp.term_chat_project({"name": "rick-Demo"}), ("Demo", "/r/Demo"))
        (self.support / "projects.json").write_text(json.dumps(
            {"version": 1, "projects": [{"name": "Demo", "folder": "/x/Demo"}]}), encoding="utf-8")
        self.assertEqual(pimp.term_chat_project({"name": "rick-Demo"}), ("Demo", "/x/Demo"))

    def test_rick_mail_path_follows_projects_root(self):
        # У человека команды корень свой: почта Рика — там же, где RickKit ставит Рика.
        (self.support / "claude.json").write_text(json.dumps({"projectsRoot": "/Users/x/Проекты"}),
                                                  encoding="utf-8")
        self.assertEqual(pimp.rick_bus(), "/Users/x/Проекты/Rick/tools/rick_bus.py")
        code, out = self.main("send", "--project", "Rick", "готово")
        self.assertEqual(code, 1)
        self.assertIn("python3 /Users/x/Проекты/Rick/tools/rick_bus.py tell", out)


if __name__ == "__main__":
    unittest.main()
