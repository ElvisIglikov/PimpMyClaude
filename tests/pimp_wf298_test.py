"""#11162: bot_send.py комплекта Рика — предел ожидания sendDocument растёт с размером файла
(60 с + 1 с на 100 КБ, как TrelvisBot #11024); без файла — 60 с."""
import importlib.util
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parent.parent / "resources" / "rick-kit" / "tools"


def load_bot_send():
    sys.path.insert(0, str(TOOLS))
    try:
        spec = importlib.util.spec_from_file_location("rick_bot_send_wf298", TOOLS / "bot_send.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    finally:
        sys.path.remove(str(TOOLS))


class BotSendTimeoutTest(unittest.TestCase):
    def test_timeout_grows_with_file_size(self):
        bs = load_bot_send()
        seen = []

        class Reply(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        def fake_urlopen(req, timeout=None):
            seen.append(timeout)
            return Reply(b'{"ok": true}')

        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        big = Path(tmp.name) / "big.zip"
        big.write_bytes(b"x" * 5_000_000)
        small = Path(tmp.name) / "small.txt"
        small.write_bytes(b"x" * 10)
        with patch.object(bs.urllib.request, "urlopen", fake_urlopen):
            bs.call("TOKEN", "sendDocument", {"chat_id": "1"}, big)
            bs.call("TOKEN", "sendDocument", {"chat_id": "1"}, small)
            bs.call("TOKEN", "getChat", {"chat_id": "1"})
        self.assertGreaterEqual(seen[0], 60 + 50, "5 МБ — не меньше 110 с")
        self.assertLess(seen[0], 60 + 52)
        self.assertEqual(seen[1], 60, "маленький файл — 60 с")
        self.assertEqual(seen[2], 60, "без файла — 60 с")


if __name__ == "__main__":
    unittest.main()
