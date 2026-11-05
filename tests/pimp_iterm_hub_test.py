#!/usr/bin/env python3
"""Сводное окно iTerm2 в CLI «Пимп» (#10564): pimp.py term --show при сессии tmux pimp-hub.

Живого tmux и iTerm тут нет: tmux — подделка в памяти (сессии и их окна, клиенты hub), `open` ловится подменой
subprocess.run, AppleScript запрещён вовсе — режим iTerm его не зовёт. Проверяется: окно чата связывается в hub
с меткой @pimp-chat (по ней Пимп убирает окна умерших чатов), выбирается его вкладка, iTerm — вперёд через
`open -a iTerm`; окна iTerm нет — запускатель Пимпа iterm/hub.command.

Запуск: python3 -B -m unittest tests/pimp_iterm_hub_test.py (гейт tools/test.sh берёт pimp_*_test.py сам).
"""

import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pimp_testlib import CLI, load  # noqa: E402

pimp = load("pimp_for_iterm_hub_test", CLI)


class FakeTmux:
    """tmux на минималках: {сессия: [окна]}, режим клиентов hub, журнал вызовов."""

    def __init__(self, sessions, control=""):
        self.sessions = {name: list(windows) for name, windows in sessions.items()}
        self.control = control
        self.calls = []
        self.fail = None

    def __call__(self, *argv):
        self.calls.append(list(argv))
        out, code = "", 0
        target = argv[argv.index("-t") + 1] if "-t" in argv else ""
        session = target.lstrip("=").partition(":")[0]
        if argv[0] == self.fail:
            code = 1
        elif argv[0] == "list-sessions":
            if not self.sessions:
                return subprocess.CompletedProcess(argv, 1, "", "no server running\n")
            both = argv[-1] == "#{session_name}\t#{session_attached}"
            out = "".join(f"{name}\t0\n" if both else f"{name}\n" for name in self.sessions)
        elif argv[0] == "list-windows":
            if session not in self.sessions:
                code = 1
            else:
                out = "".join(window + "\n" for window in self.sessions[session])
        elif argv[0] == "list-clients":
            out = self.control if session == pimp.ITERM_HUB else ""
        elif argv[0] == "link-window":
            self.sessions[session].append(argv[argv.index("-s") + 1])
        elif argv[0] == "select-window":
            code = 0 if target.partition(":")[2] in self.sessions.get(session, []) else 1
        return subprocess.CompletedProcess(argv, code, out, "")

    def named(self, command):
        return [call for call in self.calls if call[0] == command]


class ITermHubCLITest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.pimp_dir = self.root / "MyClaude" / "pimp"
        self.pimp_dir.mkdir(parents=True)
        self.command = self.root / "MyClaude" / "iterm" / "hub.command"
        self.folder = self.root / "Demo"
        self.folder.mkdir()
        (self.folder / "AGENTS.md").write_text("# 🟢 Demo — памятка\n", encoding="utf-8")
        self.opened = []
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        self.addCleanup(self.tmp.cleanup)
        stack.enter_context(mock.patch.dict(os.environ, {"MYCLAUDE_PIMP_DIR": str(self.pimp_dir),
                                                         "PIMP_TERM_TMUX": "/fake/tmux"}))
        stack.enter_context(mock.patch.object(pimp, "osascript", side_effect=AssertionError("AppleScript в режиме iTerm")))
        stack.enter_context(mock.patch.object(pimp.subprocess, "run", side_effect=self.fake_run))
        # Предохранитель (#10976) читает настройки iTerm этого Мака — здесь он молчит, его проверяет pimp_iterm_fuse_test.
        stack.enter_context(mock.patch.object(pimp, "iterm_alarm", return_value=None))

    def fake_run(self, argv, *args, **kwargs):
        if argv and argv[0] == "/usr/bin/open":
            self.opened.append(list(argv))
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv and argv[0] == "/fake/tmux" and argv[1] == "new-session":
            self.tmux.sessions[argv[argv.index("-s") + 1]] = ["@40"]
            return subprocess.CompletedProcess(argv, 0, "", "")
        raise AssertionError(f"неожиданный процесс: {argv}")

    def use(self, tmux):
        self.tmux = tmux
        patch = mock.patch.object(pimp, "tmux", side_effect=tmux)
        patch.start()
        self.addCleanup(patch.stop)
        return tmux

    def term(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), mock.patch.object(pimp, "claude_binary", return_value="/fake/claude"):
            code = pimp.main(["term", str(self.folder), *argv])
        return code, out.getvalue()

    # ---- term_hub ---------------------------------------------------------------------------------------------
    def test_hub_is_exact_session(self):
        self.use(FakeTmux({"rick-Demo": ["@7"], "pimp-hub": ["@1"]}))
        self.assertTrue(pimp.term_hub())
        self.tmux.sessions = {"rick-Demo": ["@7"], "pimp-hub-old": ["@1"]}
        self.assertFalse(pimp.term_hub())
        self.tmux.sessions = {}
        self.assertFalse(pimp.term_hub(), "сервера нет — не hub и не ошибка")

    # ---- term_hub_show -----------------------------------------------------------------------------------------
    def test_show_links_with_chat_mark_then_selects_and_brings_iterm(self):
        tmux = self.use(FakeTmux({"rick-Demo": ["@7"], "pimp-hub": ["@1"]}, control="1\n"))
        self.assertEqual(pimp.term_hub_show("rick-Demo", "Demo"), "показал вкладкой в iTerm")
        steps = [call for call in tmux.calls if call[0] in ("set-option", "rename-window", "select-pane",
                                                            "link-window", "select-window")]
        self.assertEqual(steps, [
            ["set-option", "-w", "-t", "@7", "@pimp-chat", "1"],
            ["rename-window", "-t", "@7", "Demo"],
            ["select-pane", "-t", "@7", "-T", "Demo"],
            ["link-window", "-d", "-s", "@7", "-t", "=pimp-hub:"],
            ["select-window", "-t", "=pimp-hub:@7"],
        ], "метка — до связи: иначе окно умершего чата Пимп не узнал бы")
        self.assertEqual(self.opened, [["/usr/bin/open", "-a", "iTerm"]], "iTerm вперёд — без hub.command")

    def test_show_in_hub_already_only_selects(self):
        tmux = self.use(FakeTmux({"rick-Demo": ["@7"], "pimp-hub": ["@1", "@7"]}, control="0\n1\n"))
        pimp.term_hub_show("rick-Demo", "Demo")
        self.assertEqual(tmux.named("link-window"), [])
        self.assertEqual(tmux.named("set-option"), [])
        self.assertEqual(tmux.named("select-window"), [["select-window", "-t", "=pimp-hub:@7"]])
        self.assertFalse(any(call[0] in ("kill-window", "kill-session", "unlink-window") for call in tmux.calls))

    def test_show_without_iterm_client_runs_hub_command(self):
        self.use(FakeTmux({"rick-Demo": ["@7"], "pimp-hub": ["@1", "@7"]}, control="0\n"))
        with self.assertRaises(pimp.TermError) as error:
            pimp.term_hub_show("rick-Demo", "Demo")
        self.assertIn("hub.command", str(error.exception))
        self.assertEqual(self.opened, [], "запускателя нет — ничего не открываем")
        self.command.parent.mkdir(parents=True, exist_ok=True)
        self.command.write_text("#!/bin/sh\n", encoding="utf-8")
        self.assertEqual(pimp.term_hub_show("rick-Demo", "Demo"), "открыл окно iTerm на его вкладке")
        self.assertEqual(self.opened, [["/usr/bin/open", "-a", "iTerm", str(self.command)]])

    def test_show_refuses_without_chat_window(self):
        self.use(FakeTmux({"pimp-hub": ["@1"]}, control="1"))
        with self.assertRaises(pimp.TermError):
            pimp.term_hub_show("rick-Demo", "Demo")
        self.assertEqual(self.opened, [])

    def test_failed_link_is_an_error(self):
        tmux = self.use(FakeTmux({"rick-Demo": ["@7"], "pimp-hub": ["@1"]}, control="1"))
        tmux.fail = "link-window"
        with self.assertRaises(pimp.TermError) as error:
            pimp.term_hub_show("rick-Demo", "Demo")
        self.assertIn("pimp-hub", str(error.exception))
        self.assertEqual(self.opened, [])

    # ---- pimp.py term --show --------------------------------------------------------------------------------------
    def test_term_show_existing_chat_goes_to_hub_tab(self):
        tmux = self.use(FakeTmux({"rick-Demo": ["@7"], "pimp-hub": ["@1"]}, control="1"))
        code, out = self.term("--show")
        self.assertEqual(code, 0, out)
        self.assertIn("Терминал rick-Demo уже открыт — показал вкладкой в iTerm", out)
        self.assertIn(["link-window", "-d", "-s", "@7", "-t", "=pimp-hub:"], tmux.calls)
        self.assertIn(["select-window", "-t", "=pimp-hub:@7"], tmux.calls)
        self.assertEqual(self.opened, [["/usr/bin/open", "-a", "iTerm"]])

    def test_term_without_show_stays_background(self):
        tmux = self.use(FakeTmux({"rick-Demo": ["@7"], "pimp-hub": ["@1"]}, control="1"))
        code, out = self.term()
        self.assertEqual(code, 0, out)
        self.assertIn("уже идёт фоном", out)
        self.assertEqual(tmux.named("link-window") + tmux.named("select-window"), [])
        self.assertEqual(self.opened, [])

    def test_term_show_new_chat_opens_in_hub(self):
        tmux = self.use(FakeTmux({"pimp-hub": ["@1"]}, control="1"))
        code, out = self.term("--show")
        self.assertEqual(code, 0, out)
        self.assertIn("Открыл терминальный чат rick-Demo", out)
        self.assertIn("показал вкладкой в iTerm", out)
        self.assertIn(["set-option", "-w", "-t", "@40", "@pimp-chat", "1"], tmux.calls)
        self.assertIn(["select-window", "-t", "=pimp-hub:@40"], tmux.calls)
        self.assertEqual(self.opened, [["/usr/bin/open", "-a", "iTerm"]])

    def test_without_hub_show_keeps_terminal_path(self):
        self.use(FakeTmux({"rick-Demo": ["@7"]}))
        with mock.patch.object(pimp, "term_hub_show", side_effect=AssertionError("hub без pimp-hub")), \
                mock.patch.object(pimp, "osascript", return_value="/dev/ttys900") as osa:
            code, out = self.term("--show")
        self.assertEqual(code, 0, out)
        self.assertIn("уже открыт — показал", out)
        self.assertTrue(osa.called, "без pimp-hub — прежний Terminal")


if __name__ == "__main__":
    unittest.main()
