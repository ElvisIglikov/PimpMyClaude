#!/usr/bin/env python3
"""`pimp.py digest` против общего эталона tests/fixtures/status-states.json (ревизия WF247).

Правило заголовка — как у приложения (StatusFeed.isWorkflowHeading): «Сейчас: Workflow …» не блок,
«1️⃣ Исследование ✅ готово» — блок. Строки «Сейчас:» / «Ждёт Элвиса:» — как PanelProjects.tailLine.
Тот же эталон подключают Swift- и JS-наборы.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pimp_testlib  # noqa: E402

pimp = pimp_testlib.load_pimp("pimp_for_digest_test")
TABLE = pimp_testlib.fixture_json("status-states.json")
PY = {key: names["py"] for key, names in TABLE["states"].items()}


class DigestStatusStatesTest(unittest.TestCase):
    def test_headings_and_states(self):
        for line, state in TABLE["headings"]:
            with self.subTest(line=line):
                self.assertTrue(pimp.digest_heading(line))
                self.assertEqual(pimp.digest_state(line), PY[state])
                self.assertEqual([flow["state"] for flow in pimp.digest_parse(line)["workflows"]], [PY[state]])

    def test_not_headings(self):
        for line in TABLE["notHeadings"]:
            with self.subTest(line=line):
                self.assertFalse(pimp.digest_heading(line))
                self.assertEqual(pimp.digest_parse("# Проект\n" + line)["workflows"], [])

    def test_tails(self):
        for line, field, value in TABLE["tails"]:
            with self.subTest(line=line):
                self.assertEqual(pimp.digest_tail(line), (field, value))

    def test_documents(self):
        for doc in TABLE["documents"]:
            with self.subTest(doc=doc["name"]):
                parsed = pimp.digest_parse(doc["text"])
                self.assertEqual([flow["state"] for flow in parsed["workflows"]], [PY[s] for s in doc["workflows"]])
                self.assertEqual((parsed["now"], parsed["wait"]), (doc["now"], doc["wait"]))

    def test_block_items_still_read(self):
        parsed = pimp.digest_parse("# П\n\n1️⃣ Исследование 💭 идёт\n- о чём: что есть у других\n- шаги 2 из 5\n")
        self.assertEqual(parsed["workflows"], [{"state": "идёт", "about": "что есть у других", "steps": "2/5"}])


if __name__ == "__main__":
    unittest.main()
