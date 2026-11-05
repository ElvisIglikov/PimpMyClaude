#!/usr/bin/env python3
"""Предохранитель окон iTerm в CLI «Пимп» (#10976): профиль iTerm сам запускает окна или псевдотерминалы у предела —
pimp.py term --show не открывает hub.command.

27.10.2026 «Initial Text» профиля «Default» (`…/iterm/open-tabs.command; exit`) наследовал профиль «Пимп»: каждое новое
окно iTerm открывало ещё окно с вкладками — 380 окон. Настройки iTerm тут — временные файлы, /dev и предел — подмена.

Запуск: python3 -B -m unittest tests/pimp_iterm_fuse_test.py (гейт tools/test.sh берёт pimp_*_test.py сам).
"""

import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pimp_testlib import CLI, load  # noqa: E402

pimp = load("pimp_for_iterm_fuse_test", CLI)


class ITermFuseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.prefs = root / "com.googlecode.iterm2.plist"
        self.dynamic = root / "DynamicProfiles"
        for name, value in (("ITERM_PREFS", self.prefs), ("ITERM_DYNAMIC", self.dynamic)):
            patch = mock.patch.object(pimp, name, value)
            patch.start()
            self.addCleanup(patch.stop)

    def bookmarks(self, *profiles):
        self.prefs.write_bytes(plistlib.dumps({"New Bookmarks": list(profiles)}, fmt=plistlib.FMT_BINARY))

    def test_launchers(self):
        self.assertTrue(pimp.iterm_launches("/Users/dev/Library/Application Support/MyClaude/iterm/open-tabs.command; exit"))
        self.assertTrue(pimp.iterm_launches("osascript -e 'tell application \"iTerm\" to create window'"))
        self.assertTrue(pimp.iterm_launches("cd ~; open ."))
        self.assertFalse(pimp.iterm_launches(""))
        self.assertFalse(pimp.iterm_launches("cd ~/projects && ls"))
        self.assertFalse(pimp.iterm_launches("opencode"), "слово open внутри другого — не запуск")

    def test_alarm_names_launching_profile_from_prefs_or_dynamic(self):
        with mock.patch.object(pimp, "pty_usage", return_value=(4, 511)):
            self.assertIsNone(pimp.iterm_alarm(), "настроек iTerm нет — держать нечего")
            self.bookmarks({"Name": "Default", "Initial Text": "~/iterm/open-tabs.command; exit"}, {"Name": "Работа"})
            self.assertEqual(pimp.iterm_alarm(),
                             "iTerm: профиль «Default» сам открывает окна (Initial Text) — окна не открываю")
            self.bookmarks({"Name": "Default", "Initial Text": ""})
            self.assertIsNone(pimp.iterm_alarm())
            self.dynamic.mkdir()
            (self.dynamic / "pimp.json").write_text(json.dumps(
                {"Profiles": [{"Name": "Пимп", "Initial Text": "osascript ~/tabs.applescript"}]}), encoding="utf-8")
            (self.dynamic / "битый.json").write_text("{", encoding="utf-8")
            self.assertIn("«Пимп»", pimp.iterm_alarm())

    def test_alarm_on_ptys_near_limit(self):
        with mock.patch.object(pimp, "pty_usage", return_value=(409, 511)):
            self.assertEqual(pimp.iterm_alarm(), "Терминалов 409 из 511 — новые окна iTerm не открываю")
        with mock.patch.object(pimp, "pty_usage", return_value=(408, 511)):
            self.assertIsNone(pimp.iterm_alarm())
        with mock.patch.object(pimp, "pty_usage", return_value=(900, 0)):
            self.assertIsNone(pimp.iterm_alarm(), "предела не прочли — по нему не держим")

    def test_pty_usage_reads_this_mac(self):
        used, limit = pimp.pty_usage()
        self.assertGreaterEqual(used, 0)
        self.assertGreater(limit, 0, "kern.tty.ptmx_max читается через sysctlbyname")

    def test_show_refuses_to_open_hub_command(self):
        command = Path(self.tmp.name) / "MyClaude" / "iterm" / "hub.command"
        command.parent.mkdir(parents=True)
        command.write_text("#!/bin/sh\n", encoding="utf-8")
        (command.parent.parent / "pimp").mkdir()

        def tmux(*argv):
            out = {"list-windows": "@7\n", "list-clients": "0\n"}.get(argv[0], "")
            return subprocess.CompletedProcess(argv, 0, out, "")

        self.bookmarks({"Name": "Default", "Initial Text": "~/iterm/open-tabs.command; exit"})
        with mock.patch.dict(os.environ, {"MYCLAUDE_PIMP_DIR": str(command.parent.parent / "pimp")}), \
                mock.patch.object(pimp, "tmux", side_effect=tmux), \
                mock.patch.object(pimp, "pty_usage", return_value=(4, 511)), \
                mock.patch.object(pimp.subprocess, "run", side_effect=AssertionError("hub.command открыт")):
            with self.assertRaises(pimp.TermError) as error:
                pimp.term_hub_show("rick-Demo", "Demo")
        self.assertIn("«Default» сам открывает окна", str(error.exception))


if __name__ == "__main__":
    unittest.main()
