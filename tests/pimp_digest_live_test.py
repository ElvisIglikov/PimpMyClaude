#!/usr/bin/env python3
"""`pimp.py digest`: свежесть по времени изменения СОДЕРЖИМОГО и «Не напоминать» — как у приложения.

#10315 (К-FL, docs/contracts/510-10315-flow-live.md): checkout, pull и `git worktree add` ставят старому тексту
свежий mtime — «идёт» и выбор сводки из рабочих деревьев берут время из flow-seen.json приложения, нет записи — mtime.
#9820 (К-MW, docs/contracts/530-9820-muted-waits.md): заглушённая строка «Ждёт Элвиса:» (muted-waits.json) не видна.
Нет файлов приложения — всё как раньше.
"""

import hashlib
import json
import os
import sys
import tempfile
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pimp_testlib  # noqa: E402

pimp = pimp_testlib.load_pimp("pimp_for_digest_live_test")

RUN = "# 🟢Alpha\n\n1️⃣ Workflow ✅ готово\n- о чём: первое\n\n2️⃣ Workflow ⏳ идёт\n- о чём: второе\n- шаги 1 из 3\n"
WAIT = "Постоянный лимит 99 %, доплата или ждём пятницы"
DAY = 86400


def seen_key(text: str) -> str:
    """Ключ памяти приложения (FlowSeen.key): SHA256 текста, первые 16 байт hex."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:32]


def muted_key(folder: Path, text: str) -> str:
    """Ключ «Не напоминать» как у MutedWaits.key: папка с раскрытыми ссылками (Foundation снимает /private
    спереди, если без него путь есть) и SHA1 текста."""
    real = os.path.realpath(str(folder))
    if real.startswith("/private/") and os.path.exists(real[len("/private"):]):
        real = real[len("/private"):]
    return real + "|" + hashlib.sha1(text.strip().encode("utf-8")).hexdigest()


def iso(seconds: float) -> str:
    stamp = datetime.fromtimestamp(seconds, timezone.utc)
    return stamp.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (stamp.microsecond // 1000)


class DigestLiveTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.support = Path(tmp.name)  # подставной MyClaude/
        self.root = self.support / "projects"
        old = os.environ.get(pimp.DIR_ENV)
        os.environ[pimp.DIR_ENV] = str(self.support / "pimp")
        self.addCleanup(lambda: os.environ.pop(pimp.DIR_ENV, None) if old is None else os.environ.update({pimp.DIR_ENV: old}))
        self.now = time.time()

    def status(self, folder: str, text: str, mtime: float = None, sub: str = "docs") -> Path:
        path = self.root / folder / sub / "status.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        stamp = self.now if mtime is None else mtime
        os.utime(path, (stamp, stamp))
        return path

    def seen(self, entries: dict):
        body = {"entries": {seen_key(text): {"changed": changed, "seen": self.now} for text, changed in entries.items()},
                "version": 1}
        (self.support / "flow-seen.json").write_text(json.dumps(body), encoding="utf-8")

    def muted(self, items: list):
        (self.support / "muted-waits.json").write_text(json.dumps({"muted": items, "version": 1}), encoding="utf-8")

    def collect(self) -> dict:
        return {item["project"]: item for item in pimp.digest_collect(self.root, {}, self.now)}

    # #10315 — свежесть

    def test_old_text_with_fresh_mtime_is_not_running(self):
        # checkout поставил свежий mtime, а содержимое приложение видело неделю назад.
        self.status("Alpha", RUN)
        self.seen({RUN: self.now - 7 * DAY})
        item = self.collect()["Alpha"]
        self.assertEqual(item["group"], "тихо")
        self.assertTrue(item["stale"])
        self.assertIn("· Тихо: 🟢Alpha", pimp.digest_text(list(self.collect().values())))

    def test_fresh_content_in_memory_is_running(self):
        self.status("Alpha", RUN, mtime=self.now - 3 * DAY)
        self.seen({RUN: self.now - 600})
        item = self.collect()["Alpha"]
        self.assertEqual((item["group"], item["stale"]), ("идут", False))

    def test_unknown_text_falls_back_to_mtime(self):
        self.seen({"другой текст": self.now - 7 * DAY})
        self.status("Fresh", RUN)
        self.status("Old", RUN.replace("Alpha", "Old"), mtime=self.now - 2 * DAY)
        items = self.collect()
        self.assertEqual((items["Fresh"]["group"], items["Old"]["group"]), ("идут", "тихо"))

    def test_no_app_files_as_before(self):
        self.status("Alpha", RUN)
        self.status("Beta", "# Beta\n\nЖдёт Элвиса: " + WAIT + "\n")
        self.status("Gamma", RUN.replace("Alpha", "Gamma"), mtime=self.now - 2 * DAY)
        items = self.collect()
        self.assertEqual({name: item["group"] for name, item in items.items()},
                         {"Alpha": "идут", "Beta": "ждут", "Gamma": "тихо"})
        self.assertEqual(items["Beta"]["wait"], WAIT)

    def test_broken_app_files_as_before(self):
        self.status("Alpha", RUN)
        (self.support / "flow-seen.json").write_text("{", encoding="utf-8")
        (self.support / "muted-waits.json").write_text("[]", encoding="utf-8")
        self.assertEqual(self.collect()["Alpha"]["group"], "идут")

    def test_worktree_chosen_by_content_time_not_mtime(self):
        # `git worktree add` только что: в дереве старый текст со свежим mtime, в главной папке — свежая правка.
        main_text = RUN + "\nСейчас: гейт 2.\n"
        tree_text = RUN + "\nСейчас: старое.\n"
        main, tree = self.root / "Cafe", self.root / "Cafe-wt"
        self.status("Cafe", main_text, mtime=self.now - 3600)
        self.status("Cafe-wt", tree_text, mtime=self.now)
        (main / ".git" / "worktrees" / "wt").mkdir(parents=True)
        (main / ".git" / "worktrees" / "wt" / "gitdir").write_text(f"{tree}/.git\n", encoding="utf-8")
        (tree / ".git").write_text(f"gitdir: {main}/.git/worktrees/wt\n", encoding="utf-8")
        self.assertEqual(self.collect()["Cafe"]["now"], "старое.", "без памяти — по mtime, как раньше")
        self.seen({main_text: self.now - 3600, tree_text: self.now - 5 * DAY})
        items = self.collect()
        self.assertEqual(list(items), ["Cafe"])
        self.assertEqual((items["Cafe"]["now"], items["Cafe"]["group"]), ("гейт 2.", "идут"))

    # #9820 — «Не напоминать»

    def test_muted_wait_is_not_printed(self):
        self.status("Beta", "# 🟠Beta\n\nЖдёт Элвиса: " + WAIT + "\n")
        self.muted([{"at": iso(self.now - 60), "key": muted_key(self.root / "Beta", WAIT), "until": None}])
        item = self.collect()["Beta"]
        self.assertEqual((item["wait"], item["group"]), ("", "тихо"))
        self.assertNotIn(WAIT, pimp.digest_text(list(self.collect().values())))

    def test_mute_until_deadline_then_back(self):
        self.status("Beta", "# 🟠Beta\n\nЖдёт Элвиса: " + WAIT + "\n")
        key = muted_key(self.root / "Beta", WAIT)
        self.muted([{"at": iso(self.now - 60), "key": key, "until": iso(self.now + 3600)}])
        self.assertEqual(self.collect()["Beta"]["wait"], "")
        self.muted([{"at": iso(self.now - 7200), "key": key, "until": iso(self.now - 1)}])
        self.assertEqual(self.collect()["Beta"]["wait"], WAIT, "срок вышел — снова видно")

    def test_new_text_is_reminded_again(self):
        self.status("Beta", "# 🟠Beta\n\nЖдёт Элвиса: новый вопрос\n")
        self.muted([{"at": iso(self.now), "key": muted_key(self.root / "Beta", WAIT), "until": None}])
        item = self.collect()["Beta"]
        self.assertEqual((item["wait"], item["group"]), ("новый вопрос", "ждут"))

    def test_hand_block_keeps_waiting_group(self):
        # Блок ✋ — состояние самого Workflow: заглушение строки его не снимает.
        self.status("Hand", "# Hand\n\n1️⃣ Workflow ❓ ждёт Элвиса\n\nЖдёт Элвиса: " + WAIT + "\n")
        self.muted([{"at": iso(self.now), "key": muted_key(self.root / "Hand", WAIT), "until": None}])
        item = self.collect()["Hand"]
        self.assertEqual((item["wait"], item["group"]), ("", "ждут"))

    def test_muted_file_rules(self):
        key = "/x|" + "0" * 40
        self.muted([{"key": key, "until": "2026-10-20T10:00:00Z"}, {"key": "без черты", "until": None},
                    {"key": "/y|1", "until": "не дата"}, {"key": "/z|2"}])
        self.assertEqual(pimp.digest_muted(), {key: datetime(2026, 10, 20, 10, tzinfo=timezone.utc).timestamp(),
                                               "/z|2": None})
        (self.support / "muted-waits.json").write_text(json.dumps({"muted": [{"key": key}], "version": 2}),
                                                       encoding="utf-8")
        self.assertEqual(pimp.digest_muted(), {}, "чужая версия — всё напоминается")
        self.assertEqual(pimp.digest_iso("2026-10-20T10:00:00.250Z"),
                         datetime(2026, 10, 20, 10, 0, 0, 250000, tzinfo=timezone.utc).timestamp())


if __name__ == "__main__":
    unittest.main()
