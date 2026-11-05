#!/usr/bin/env python3
"""iTerm сам вперёд не выходит (#11016, второй заход): Пимп прячет iTerm, показавшийся без человека, кроме показа
по `pimp.py term --show` — его CLI отмечает файлом iterm/show-at до связи окна в hub (связь и будит iTerm).

Запуск: python3 -B -m unittest tests/pimp_iterm_quiet_test.py (гейт tools/test.sh берёт pimp_*_test.py сам).
"""

import contextlib
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pimp_testlib import CLI, load  # noqa: E402
from pimp_iterm_hub_test import FakeTmux  # noqa: E402

pimp = load("pimp_for_iterm_quiet_test", CLI)


class ShowMarkTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        pimp_dir = Path(tmp.name) / "MyClaude" / "pimp"
        pimp_dir.mkdir(parents=True)
        self.mark = pimp_dir.parent / "iterm" / "show-at"
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(mock.patch.dict(os.environ, {"MYCLAUDE_PIMP_DIR": str(pimp_dir),
                                                         "PIMP_TERM_TMUX": "/fake/tmux"}))
        stack.enter_context(mock.patch.object(pimp, "iterm_alarm", return_value=None))
        stack.enter_context(mock.patch.object(pimp.subprocess, "run",
                                              side_effect=lambda argv, *a, **k: subprocess.CompletedProcess(argv, 0, "", "")))
        self.tmux = FakeTmux({"rick-Demo": ["@7"], "pimp-hub": ["@1"]}, control="1\n")
        self.marked_at_link = None

        def tmux(*argv):
            if argv[0] == "link-window":
                self.marked_at_link = self.mark.is_file()
            return self.tmux(*argv)
        stack.enter_context(mock.patch.object(pimp, "tmux", side_effect=tmux))

    def test_show_marks_before_link(self):
        before = time.time()
        pimp.term_hub_show("rick-Demo", "Demo")
        self.assertTrue(self.marked_at_link, "метка — до связи окна: связь будит iTerm, и Пимп сверяется с меткой")
        self.assertGreaterEqual(float(self.mark.read_text(encoding="utf-8")), before - 1)

    def test_mark_on_show_without_link(self):
        self.tmux.sessions["pimp-hub"].append("@7")
        pimp.term_hub_show("rick-Demo", "Demo")
        self.assertIsNone(self.marked_at_link)
        self.assertTrue(self.mark.is_file(), "вкладка уже в hub — iTerm всё равно показываем, метка нужна")


if __name__ == "__main__":
    unittest.main()
