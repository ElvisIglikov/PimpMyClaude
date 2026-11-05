#!/usr/bin/env python3
"""«pimp.py login» — очередь входов на сайт logins/ (WF302, #11225, контракт К-LOGIN, docs/contracts/630-wf302-login.md).

Каталог очереди — временный (MYCLAUDE_LOGINS_DIR), приложение — нитка, которая пишет <id>.state.json, как
LoginBeacon.swift. Chrome и живой каталог MyClaude не трогаются.
"""

import contextlib
import io
import json
import os
import stat
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pimp_testlib  # noqa: E402

pimp = pimp_testlib.load_pimp("pimp_login_cli")


class LoginTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name) / "logins"
        self.env = mock.patch.dict(os.environ, {"MYCLAUDE_LOGINS_DIR": str(self.folder), "MYCLAUDE_LOGIN_WAIT": "0",
                                                "CLAUDE_CODE_HOST_SESSION_ID": "local_test"})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def call(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = pimp.main(["login", *argv])
        return code, out.getvalue().strip()

    def requests(self):
        return sorted(p.name for p in self.folder.glob("*.json") if not p.name.endswith(".state.json"))

    def state(self, rid, state, reason="", at=None, total=1):
        body = {"v": 1, "id": rid, "state": state, "reason": reason, "at": at or pimp.now_iso(), "url": "",
                "name": "", "index": 1, "total": total}
        (self.folder / f"{rid}.state.json").write_text(json.dumps(body), encoding="utf-8")

    def test_url_rules(self):
        self.assertEqual(pimp.login_url("appstoreconnect.apple.com"), "https://appstoreconnect.apple.com")
        self.assertEqual(pimp.login_url(" http://x.com/login "), "http://x.com/login")
        for bad in ("", "ftp://x.com", "https://", "a b.com", "x.com/\x07", "x.com/" + "a" * 2000):
            self.assertIsNone(pimp.login_url(bad), bad)
        self.assertEqual(pimp.login_host("https://WWW.Example.com/a"), "example.com")

    def test_request_file_private_and_no_answer_is_code_1(self):
        code, line = self.call("appstoreconnect.apple.com", "--name", "App Store Connect")
        self.assertEqual(code, 1)
        self.assertIn("Пимп не ответил", line)
        [name] = self.requests()
        path = self.folder / name
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.folder.stat().st_mode), 0o700)
        body = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(body["v"], 1)
        self.assertEqual(body["id"] + ".json", name)
        self.assertEqual(body["url"], "https://appstoreconnect.apple.com")
        self.assertEqual(body["name"], "App Store Connect")
        self.assertEqual(body["from"], "local_test")
        self.assertNotIn("again", body)
        self.assertEqual([p.name for p in self.folder.iterdir() if p.name.startswith(".")], [], "без хвостов tmp")

    def test_waits_for_app_answer(self):
        os.environ["MYCLAUDE_LOGIN_WAIT"] = "3"

        def app():
            for _ in range(100):
                names = self.requests() if self.folder.exists() else []
                if names:
                    rid = names[0][:-5]
                    self.state(rid, "waiting", "сейчас покажу")
                    time.sleep(0.3)
                    self.state(rid, "shown")
                    return
                time.sleep(0.05)

        thread = threading.Thread(target=app)
        thread.start()
        started = time.time()
        code, line = self.call("https://appstoreconnect.apple.com", "--name", "App Store Connect")
        thread.join()
        self.assertEqual(code, 0)
        self.assertIn("App Store Connect", line)
        self.assertIn("Chrome впереди", line)
        self.assertLess(time.time() - started, 2.5, "«сейчас покажу» — ждём «shown», но не до конца срока")

    def test_same_site_is_one_login_with_again(self):
        self.call("https://appstoreconnect.apple.com/login")
        [first] = self.requests()
        self.state(first[:-5], "waiting", "30 мин без входа — маяк погашен; повтори pimp.py login",
                   at="2026-10-30T10:00:00Z")
        self.call("appstoreconnect.apple.com", "--name", "ASC")
        self.assertEqual(self.requests(), [first], "тот же сайт — тот же вход")
        body = json.loads((self.folder / first).read_text(encoding="utf-8"))
        self.assertTrue(body.get("again"))
        self.assertEqual(body["name"], "ASC")
        self.assertEqual(body["url"], "https://appstoreconnect.apple.com/login", "адрес и порядок — первого")

    def test_finished_site_gets_new_login(self):
        self.call("https://x.com/login")
        [first] = self.requests()
        self.state(first[:-5], "done", "поле входа пропало — вошёл")
        time.sleep(0.002)
        self.call("https://x.com/login")
        self.assertEqual(len(self.requests()), 2)

    def test_list_done_clear(self):
        self.call("https://a.com/login", "--name", "A")
        self.call("https://b.com/login")
        rid_a = next(n[:-5] for n in self.requests()
                     if json.loads((self.folder / n).read_text(encoding="utf-8"))["url"].startswith("https://a."))
        self.state(rid_a, "shown")
        code, text = self.call("--list")
        self.assertEqual(code, 0)
        lines = text.splitlines()
        self.assertEqual(len(lines), 2)
        self.assertIn("«A» — Chrome впереди", text)
        self.assertIn("«b.com» — в очереди", text)
        code, raw = self.call("--list", "--json")
        self.assertEqual(len(json.loads(raw)), 2)
        self.assertEqual(self.call("--done", "www.b.com")[0], 0)
        self.assertEqual(len(self.requests()), 1)
        self.assertEqual(self.call("--done", "nope.com")[0], 1)
        self.assertEqual(self.call("--clear")[0], 0)
        self.assertEqual(self.requests(), [])
        self.assertEqual(self.call("--list"), (0, "Входов в очереди нет"))

    def test_refusals(self):
        self.assertEqual(self.call()[0], 1)
        self.assertEqual(self.call("ftp://x.com")[0], 1)
        self.assertEqual(self.call("x.com", "--list")[0], 1)
        self.assertEqual(self.call("--list", "--name", "A")[0], 1)
        self.assertEqual(self.call("x.com", "--name", "a\x01")[0], 1)
        self.assertFalse(self.folder.exists(), "отказ — ничего не пишем")

    def test_default_dir_next_to_pimp_channel(self):
        os.environ.pop("MYCLAUDE_LOGINS_DIR")
        with mock.patch.dict(os.environ, {"MYCLAUDE_PIMP_DIR": str(Path(self.tmp.name) / "pimp")}):
            self.assertEqual(pimp.logins_dir(), Path(self.tmp.name) / "logins")


if __name__ == "__main__":
    unittest.main()
