"""#11665: term.py комплекта Рика — диалог Claude только внизу экрана, с меню.

«Do you want…» или «Bypass Permissions mode» выше в ленте — текст, а не диалог: question() не будит Рика,
dialogs() не держит send. Экраны — куски настоящих Claude Code 2.1.318 (05.11.2026)."""
import importlib.util
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent / "resources" / "rick-kit" / "tools"

ASK = """⏺ Write(hello.txt)
────────────────────────────────────────
 Create file
 hello.txt
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
  1 hi
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Do you want to create hello.txt?
 ❯ 1. Yes
   2. Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)
   3. No
 Esc to cancel · Tab to amend"""

TRUST = """ Accessing workspace:

 /tmp/dlg

 Quick safety check: Is this a project you created or one you trust? (Like your own code, a well-known open source

 Claude Code'll be able to read, edit, and execute files here.

 Security guide

 ❯ No, exit
   Yes, I trust this folder

 Enter to confirm · Esc to cancel"""

FEED = """❯ Рик → PimpMyClaude · ошибка классом: term.py question() считает диалогом любое «Do you want» на экране
  — а это бывает просто текст в ленте; Bypass Permissions mode и trust this folder — тоже.
Do you want to proceed? — так спрашивает Claude, пишу в ответе.
⏺ Понял, чиню.
  1. Yes — это пункт из примера, не меню.
────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ bypass permissions on (shift+tab to cycle)"""


def load_term():
    sys.path.insert(0, str(TOOLS))
    try:
        spec = importlib.util.spec_from_file_location("rick_term_11665", TOOLS / "term.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    finally:
        sys.path.remove(str(TOOLS))


class DialogOnScreenTest(unittest.TestCase):
    def setUp(self):
        self.term = load_term()
        self.pressed = []
        self.term.sessions = lambda: {}
        self.term.keys = lambda sess, *a: self.pressed.append(a)
        self.term.wait = lambda *a: None

    def show(self, pane):
        self.term.capture = lambda sess, lines=None: pane

    def test_text_in_feed_is_not_a_question(self):
        self.show(FEED)
        self.assertIsNone(self.term.question("rick-X"), "«Do you want» в ленте — не вопрос")

    def test_text_in_feed_does_not_block_send(self):
        self.show(FEED)
        self.assertEqual(self.term.dialogs("rick-X", {"projects_root": "/nowhere"}), "")
        self.assertEqual(self.pressed, [], "ни одной клавиши в окно")

    def test_old_question_above_the_bottom_is_text(self):
        self.show(ASK + "\n" + "\n".join("⏺ строка ленты %d" % i for i in range(20)) + "\n❯ ")
        self.assertIsNone(self.term.question("rick-X"), "диалог ушёл наверх — это уже лента")

    def test_real_permission_dialog_is_a_question(self):
        self.show("⏺ старая лента\n" * 30 + ASK)
        self.assertIn("Do you want to create hello.txt?", self.term.question("rick-X") or "")
        with self.assertRaises(self.term.TermError):
            self.term.dialogs("rick-X", {"projects_root": "/nowhere"})
        self.assertEqual(self.pressed, [])

    def test_real_trust_dialog_without_numbers_is_a_question(self):
        self.show(TRUST)
        self.assertIn("Yes, I trust this folder", self.term.question("rick-X") or "")
        with self.assertRaises(self.term.TermError):
            self.term.dialogs("rick-X", {"projects_root": "/nowhere"})


if __name__ == "__main__":
    unittest.main()
