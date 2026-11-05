#!/usr/bin/env python3
"""Форма общего эталона tests/fixtures/commands.json (WF248): его читают Swift- и JS-наборы,
поэтому битая запись должна краснеть здесь, а не загадкой в чужом наборе. Сверку с кодом делают они."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pimp_testlib  # noqa: E402

SENDERS = {"swift", "page-only", "ax-only", "legacy"}


class CommandsFixtureTest(unittest.TestCase):
    def test_shape(self):
        commands = pimp_testlib.fixture_json("commands.json")["commands"]
        self.assertTrue(commands)
        actions = [entry.get("action") for entry in commands]
        self.assertEqual(len(actions), len(set(actions)), "команда дважды")
        for entry in commands:
            with self.subTest(entry=entry):
                self.assertEqual(set(entry), {"action", "sender", "file"})
                self.assertRegex(entry["action"], r"^[A-Za-z][A-Za-z-]*$")
                self.assertIn(entry["sender"], SENDERS)
                self.assertTrue((pimp_testlib.ROOT / entry["file"]).is_file(), entry["file"])


if __name__ == "__main__":
    unittest.main()
