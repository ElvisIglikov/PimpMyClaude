#!/usr/bin/env python3
"""Тесты терминальных чатов CLI «Пимп» (WF111): pimp.py term / term-send / term-list / term-color.

Ни Terminal, ни tmux, ни настоящего claude тут нет: вместо них подставные скрипты —
osascript (ловит скрипт и аргументы, «открытие вкладки» исполняет команду zsh'ем и
отвечает tty новой вкладки), tmux (сессии в файле состояния, new-session исполняет свою
команду), ps и lsof (таблицы в файлах) и claude (пишет
папку, аргументы и окружение в журнал и выходит). Так проверяется вся цепочка
кавычек: текст и пути доходят до claude байт в байт, AppleScript текста не видит.

Запуск: python3 -B -m unittest tests/pimp_term_test.py (строка в tools/test.sh).
"""

import contextlib
import importlib.util
import io
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import unittest.mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools" / "pimp.py"
CHAT = "local_5265171a-0ab8-4472-b4e5-40604a36ef6e"
CLI_SESSION = "9378c07b-b2cd-4dab-82c3-0db0bdb19f65"
NASTY = 'он сказал "да" и \'нет\' $HOME `id` $(whoami) \\ ; && | > *'


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pimp = load("pimp_for_term_test", CLI)
FakeApp = load("pimp_cli_for_term_test", ROOT / "tests" / "pimp_cli_test.py").FakeApp

FAKE_OSASCRIPT = r'''#!/usr/bin/env python3
import json, os, subprocess, sys, time
script = sys.stdin.read()
mark = script.splitlines()[0].replace("-- pimp:", "").strip() if script else ""
argv = sys.argv[2:]
with open(os.environ["FAKE_OSA_LOG"], "a", encoding="utf-8") as f:
    f.write(json.dumps({"mark": mark, "argv": argv, "script": script}, ensure_ascii=False) + "\n")
tabs_path = os.environ["FAKE_TABS"]
tabs = open(tabs_path, encoding="utf-8").read() if os.path.exists(tabs_path) else ""
opened_path = tabs_path + ".opened"
opened = open(opened_path, encoding="utf-8").read().split() if os.path.exists(opened_path) else []
if os.environ.get("FAKE_OSA_DENY"):
    sys.stderr.write("execution error: Not authorized to send Apple events to Terminal. (-1743)\n")
    sys.exit(1)
if os.environ.get("FAKE_OSA_SLEEP"):
    time.sleep(30)
if mark.startswith("open"):
    subprocess.run(["/bin/zsh", "-f", "-c", argv[0]], check=False)
    if mark == "open-terminal":
        dev = "/dev/ttys9%02d" % len(opened)
        with open(opened_path, "a", encoding="utf-8") as f:
            f.write(dev + "\n")
        print(dev)
    else:
        print("ok")
elif mark in ("color", "title"):
    known = [line.partition("\t")[0] for line in tabs.splitlines()] + opened
    print("1" if argv[0] in known else "0")
elif mark == "list":
    print(tabs.strip())
elif mark == "act":
    shells = argv[3].split("\n")
    for line in tabs.splitlines():
        tty, procs, _title = (line.split("\t") + ["", ""])[:3]
        live = any(p and p not in shells for p in procs.split(","))
        if tty == argv[1]:
            print(("sent" if argv[0] == "send" else "shown") if live else "none")
            break
    else:
        print("none")
'''

FAKE_TMUX = r'''#!/usr/bin/env python3
import json, os, subprocess, sys, time
state_path = os.environ["FAKE_TMUX_STATE"]
state = json.load(open(state_path)) if os.path.exists(state_path) else {}
# Глобальное окружение сервера (#8366): {имя: значение}; «-ИМЯ»: None — помечено к снятию.
env_path = os.environ.get("FAKE_TMUX_ENV", "")
genv = json.load(open(env_path)) if env_path and os.path.exists(env_path) else {}
args = sys.argv[1:]
with open(os.environ["FAKE_TMUX_LOG"], "a", encoding="utf-8") as f:
    f.write(json.dumps(args, ensure_ascii=False) + "\n")
if args[0] == os.environ.get("FAKE_TMUX_FAIL"):
    sys.stderr.write("permission denied: fake-token-must-not-leak-8366\n"); sys.exit(1)
if args[0] == os.environ.get("FAKE_TMUX_SLEEP"):
    time.sleep(30)
if args[0] == "list-sessions":
    if not state:
        sys.stderr.write("no server running\n"); sys.exit(1)
    for name, attached in state.items():
        print(f"{name}\t{1 if attached else 0}")
elif args[0] == "list-clients":
    client = state.get(args[2].lstrip("="))
    if isinstance(client, str):
        print(client)
elif args[0] == "list-windows":
    if args[2].lstrip("=") not in state:
        sys.exit(1)
    print("@10\n@11")
elif args[0] == "show-environment":
    if not state:
        sys.stderr.write("no server running\n"); sys.exit(1)
    for name, value in genv.items():
        print(name if value is None else f"{name}={value}")
elif args[0] == "set-environment":
    if os.environ.get("FAKE_TMUX_SETENV_FAIL"):
        sys.exit(1)
    genv.pop(args[-1], None)
    genv.pop("-" + args[-1], None)
    json.dump(genv, open(env_path, "w"))
elif args[0] == "new-session":
    name = args[args.index("-s") + 1]
    folder = args[args.index("-c") + 1]
    # Живой сервер отдаёт новой сессии своё глобальное окружение; нет сервера — родится с нашим.
    child = dict(os.environ)
    if state:
        child.update({key: value for key, value in genv.items() if value is not None})
    else:
        json.dump(sorted(os.environ), open(os.environ["FAKE_TMUX_BORN_NAMES"], "w"))
    state[name] = 1
    json.dump(state, open(state_path, "w"))
    subprocess.run(args[args.index("-c") + 2:], cwd=folder, env=child, check=False)
elif args[0] == "send-keys":
    if args[2].lstrip("=").rstrip(":") not in state:
        sys.stderr.write("can't find session\n"); sys.exit(1)
'''

# ps -t <ttysNNN> -o pid=,comm= по файлу {"ttysNNN": [[pid, comm], …]}.
FAKE_PS = r'''#!/usr/bin/env python3
import json, os, sys
table = json.load(open(os.environ["FAKE_PS"])) if os.path.exists(os.environ["FAKE_PS"]) else {}
rows = table.get(sys.argv[sys.argv.index("-t") + 1])
if not rows:
    sys.exit(1)
for pid, comm in rows:
    print(f"{pid:>5} {comm}")
'''

# lsof -a -p PID -d cwd -Fn по файлу {"pid": "папка"}.
FAKE_LSOF = r'''#!/usr/bin/env python3
import json, os, sys
table = json.load(open(os.environ["FAKE_LSOF"])) if os.path.exists(os.environ["FAKE_LSOF"]) else {}
pid = sys.argv[sys.argv.index("-p") + 1]
if pid not in table:
    sys.exit(1)
print(f"p{pid}\nfcwd\nn{table[pid]}")
'''

FAKE_CLAUDE = r'''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_CLAUDE_LOG"], "a", encoding="utf-8") as f:
    f.write(json.dumps({"cwd": os.getcwd(), "argv": sys.argv[1:],
                        "reply": os.environ.get("PIMP_REPLY_CHAT", "<нет>"),
                        "claudecode": os.environ.get("CLAUDECODE", "<нет>"),
                        "names": sorted(key for key in os.environ if key.startswith("CLAUDE")),
                        "disable_title": os.environ.get("CLAUDE_CODE_DISABLE_TERMINAL_TITLE")}, ensure_ascii=False) + "\n")
'''


class TermTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.cli = CLI
        self.support = self.root / "MyClaude"
        self.dir = self.support / "pimp"
        self.support.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, body in (("osascript", FAKE_OSASCRIPT), ("tmux", FAKE_TMUX), ("claude", FAKE_CLAUDE),
                           ("ps", FAKE_PS), ("lsof", FAKE_LSOF)):
            path = self.bin / name
            path.write_text(body, encoding="utf-8")
            path.chmod(0o755)
        # Папка проекта с неудобным именем: пробел, кавычки, доллар — cd обязан попасть.
        self.folder = self.root / "Pro ject $x `y` 'q'"
        self.folder.mkdir()
        (self.support / "projects.json").write_text(json.dumps(
            {"version": 1, "projects": [{"name": "Demo", "folder": str(self.folder)}]}), encoding="utf-8")
        self.app = None

    def tearDown(self):
        if self.app is not None:
            self.app.stop()
            self.app.join(timeout=2)

    def call(self, *argv, tmux=False, stdin=None, session=CHAT, app_result=None, extra=None, short_timeout=None):
        if app_result is not None:
            self.dir.mkdir(parents=True, exist_ok=True)
            self.app = FakeApp(self.dir, app_result)
            self.app.start()
        env = dict(os.environ)
        # Тест из терминального чата: его собственный адрес ответа не должен протечь в прогон.
        for leak in list(env):
            if leak != "PIMP_REPLY_CHAT" and not pimp.term_host_var(leak):
                continue
            env.pop(leak, None)
        env.update({
            "MYCLAUDE_PIMP_DIR": str(self.dir),
            "MYCLAUDE_PIMP_WAIT": "3",
            "MYCLAUDE_PIMP_TAKEN": "2" if app_result is not None else "0.2",
            "MYCLAUDE_CLAUDE_SESSIONS": str(self.root / "sessions"),
            "MYCLAUDE_CLAUDE_PROJECTS": str(self.root / "transcripts"),
            "PIMP_TERM_CLAUDE": str(self.bin / "claude"),
            "PIMP_TERM_OSASCRIPT": str(self.bin / "osascript"),
            "PIMP_TERM_TMUX": str(self.bin / "tmux") if tmux else "none",
            "FAKE_OSA_LOG": str(self.root / "osa.jsonl"),
            "FAKE_TABS": str(self.root / "tabs.txt"),
            "FAKE_TMUX_STATE": str(self.root / "tmux.json"),
            "FAKE_TMUX_LOG": str(self.root / "tmux.jsonl"),
            "FAKE_TMUX_ENV": str(self.root / "tmux-env.json"),
            "FAKE_TMUX_BORN_NAMES": str(self.root / "tmux-born-names.json"),
            "FAKE_CLAUDE_LOG": str(self.root / "claude.jsonl"),
            "PIMP_TERM_PS": str(self.bin / "ps"),
            "PIMP_TERM_LSOF": str(self.bin / "lsof"),
            "FAKE_PS": str(self.root / "ps.json"),
            "FAKE_LSOF": str(self.root / "lsof.json"),
            "HOME": str(self.root),  # тумблер «Цвет по проекту» — из своего (пустого) ~/Library
            "CLAUDECODE": "1",
        })
        env.pop("CLAUDE_CODE_HOST_SESSION_ID", None)
        if session is not None:
            env["CLAUDE_CODE_HOST_SESSION_ID"] = session
        env.update(extra or {})
        if short_timeout is not None:
            real_run = subprocess.run
            def bounded(command, **kwargs):
                kwargs["timeout"] = min(kwargs.get("timeout", 60), short_timeout)
                return real_run(command, **kwargs)
            out, err = io.StringIO(), io.StringIO()
            with unittest.mock.patch.dict(os.environ, env), \
                    unittest.mock.patch.object(pimp.subprocess, "run", side_effect=bounded), \
                    contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = pimp.main(list(argv))
            return subprocess.CompletedProcess(argv, code, out.getvalue(), err.getvalue())
        done = subprocess.run([sys.executable, "-B", str(self.cli), *argv], env=env, input=stdin,
                              capture_output=True, text=True, timeout=60)
        if self.app is not None:
            self.app.join(timeout=2)
        return done

    def log(self, name: str) -> list:
        path = self.root / name
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]

    def tabs(self, text: str):
        (self.root / "tabs.txt").write_text(text, encoding="utf-8")

    def sessions(self, **state):
        (self.root / "tmux.json").write_text(json.dumps(state), encoding="utf-8")

    def ps(self, **table):
        (self.root / "ps.json").write_text(json.dumps(table), encoding="utf-8")

    def lsof(self, **table):
        (self.root / "lsof.json").write_text(json.dumps(table), encoding="utf-8")

    def record(self, name="Demo", **fields):
        """Запись реестра, как её пишет файл запуска."""
        body = {"v": 1, "name": pimp.TERM_PREFIX + name, "project": name, "folder": str(self.folder),
                "cwd": str(self.folder), "tmux": "", "at": "2026-09-30T21:00:00Z"}
        body.update(fields)
        path = self.support / "term" / f"{name}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(body), encoding="utf-8")
        return path

    def live_tab(self, tty="/dev/ttys005", pid=500, title="◐ Переименовал сам claude"):
        """Вкладка с claude, чей заголовок claude уже переписал, и её запись в реестре."""
        self.tabs(f"{tty}\tlogin,claude,caffeinate\t{title}\n")
        self.ps(**{tty[5:]: [[pid - 1, "login"], [pid, "/Apps/claude.app/Contents/MacOS/claude"]]})
        return self.record(tty=tty, pid=pid)

    def copy_cli(self):
        # Файл разрешений должен искаться возле настоящего CLI, не в cwd/проекте.
        folder = self.root / "CLI 'quotes' $x `y` $(no-command)"
        folder.mkdir()
        self.cli = folder / "pimp.py"
        shutil.copyfile(CLI, self.cli)
        return self.cli.with_name("claude-term-settings.json")

    def assert_no_terminal_mutations(self):
        self.assertTrue(all(call[0] == "list-sessions" for call in self.log("tmux.jsonl")),
                        self.log("tmux.jsonl"))
        self.assertTrue(all(call["mark"] == "list" for call in self.log("osa.jsonl")),
                        self.log("osa.jsonl"))
        self.assertEqual(self.log("claude.jsonl"), [])
        self.assertEqual(list((self.support / "term").glob("*.sh")), [])

    def assert_settings_arg(self, run):
        argv = run["argv"]
        self.assertEqual(argv.count("--settings"), 1)
        index = argv.index("--settings")
        self.assertEqual(argv[index + 1], str(self.cli.resolve().with_name("claude-term-settings.json")))
        for later in ("--resume", "--continue", "--"):
            if later in argv:
                self.assertLess(index + 1, argv.index(later))

    # ---- term: открыть ---------------------------------------------------------
    def test_open_terminal_without_tmux_passes_text_and_path_verbatim(self):
        text = NASTY + "\nвторая строка\n-не ключ"
        done = self.call("term", "demo", "--text", "-", stdin=text)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("Открыл терминальный чат rick-Demo", done.stdout)
        self.assertIn("Terminal без tmux", done.stdout)
        osa = self.log("osa.jsonl")
        self.assertEqual([o["mark"] for o in osa], ["list", "open-terminal", "color"])
        osa = osa[1:]
        self.assertEqual(osa[0]["script"], pimp.OSA_OPEN_TERMINAL, "скрипт постоянный — текста в нём нет")
        self.assertEqual(osa[0]["argv"][1], "Demo")
        self.assertTrue(osa[0]["argv"][0].startswith("exec /bin/sh "))
        self.assertNotIn("вторая строка", osa[0]["argv"][0], "текст — в файле запуска, не в строке вкладки")
        [run] = self.log("claude.jsonl")
        self.assertEqual(run["cwd"], os.path.realpath(self.folder))
        self.assertEqual(run["argv"], ["--model", "claude-opus-5-5", "--effort", "high",
                                       "--permission-mode", "bypassPermissions", "--settings",
                                       str(CLI.with_name("claude-term-settings.json")), "--", text.strip()])
        self.assertEqual(run["reply"], CHAT)
        self.assertEqual(run["claudecode"], "<нет>", "метка чата Claude внутрь не протекает")
        self.assertEqual(run["disable_title"], "1", "новый Claude не переписывает custom title")
        self.assertEqual(list((self.support / "term").glob("*.sh")), [], "файл запуска удалил себя")

    def test_launcher_writes_registry_record_before_claude(self):
        done = self.call("term", "Demo")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        path = self.support / "term" / "Demo.json"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        record = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual((record["name"], record["project"], record["folder"], record["tmux"]),
                         ("rick-Demo", "Demo", str(self.folder), ""), "папка с кавычками и $ — байт в байт")
        self.assertIsInstance(record["pid"], int)
        self.assertEqual(record["tty"], "", "у теста нет терминала — tty пустой, а не мусор")
        self.assertEqual([p.name for p in (self.support / "term").iterdir()], ["Demo.json"],
                         "временный файл переименован, не брошен")

    def test_tmux_default_runs_in_background_without_window(self):
        # Слово Элвиса 01.10: окна терминалов не нужны — с tmux чат идёт фоном, окно только по --show.
        done = self.call("term", "Demo", tmux=True, session=None)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("фоном в tmux, без окна", done.stdout)
        self.assertEqual(self.log("osa.jsonl"), [], "фоном — ни одного AppleEvent")

    def test_open_with_tmux_starts_named_session_in_folder(self):
        done = self.call("term", "Demo", "--show", "--effort", "high", tmux=True, session=None)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("(tmux)", done.stdout)
        command = [o for o in self.log("osa.jsonl") if o["mark"] == "open-terminal"][0]["argv"][0]
        self.assertIn(" attach -t '=rick-Demo'", command)
        new = [a for a in self.log("tmux.jsonl") if a[0] == "new-session"]
        self.assertEqual(len(new), 1)
        self.assertEqual(new[0][new[0].index("-c") + 1], str(self.folder))
        [run] = self.log("claude.jsonl")
        self.assertEqual(run["argv"], ["--model", "claude-opus-5-5", "--effort", "high",
                                       "--permission-mode", "bypassPermissions", "--settings",
                                       str(CLI.with_name("claude-term-settings.json"))])
        self.assertEqual(run["reply"], "<нет>", "без своего чата ответного адреса нет")
        record = json.loads((self.support / "term" / "Demo.json").read_text(encoding="utf-8"))
        self.assertEqual(record["tmux"], "rick-Demo", "с tmux главный адрес — сессия")

    def test_project_comes_from_pimp_like_open(self):
        answer = {"ok": True, "error": "", "fromResolved": False, "screen": "windows",
                  "projects": [{"name": "Other", "folder": str(self.folder)}]}
        done = self.call("term", "Other", app_result=answer)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.app.requests[0]["action"], "projects")
        self.assertIn("rick-Other", done.stdout)

    def test_unknown_project_refused_without_terminal(self):
        done = self.call("term", "Nope")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Проекта «Nope» не знаю — есть: Demo", done.stdout)
        self.assertEqual(self.log("osa.jsonl"), [])

    def test_last_is_continue(self):
        done = self.call("term", "Demo", "--last")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.log("claude.jsonl")[0]["argv"][-1], "--continue")
        self.assert_settings_arg(self.log("claude.jsonl")[0])
        self.assertIn("не держи открытым в окне Claude", done.stdout)

    def test_resume_checks_id(self):
        done = self.call("term", "Demo", "--resume", "$(rm -rf ~)")
        self.assertEqual(done.returncode, 1)
        self.assertIn("--resume", done.stdout)
        self.assertEqual(self.log("osa.jsonl"), [])
        done = self.call("term", "Demo", "--resume", CLI_SESSION)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(self.log("claude.jsonl")[0]["argv"][-2:], ["--resume", CLI_SESSION])
        self.assert_settings_arg(self.log("claude.jsonl")[0])

    def test_from_chat_reads_cli_session_and_warns(self):
        other = self.root / "worktree"
        other.mkdir()
        place = self.root / "sessions" / "acc" / "org"
        place.mkdir(parents=True)
        (place / f"{CHAT}.json").write_text(json.dumps({
            "sessionId": CHAT, "cliSessionId": CLI_SESSION, "cwd": str(other), "title": "Рисуем баннер"}),
            encoding="utf-8")
        done = self.call("term", "Demo", "--from-chat", CHAT)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("чат «Рисуем баннер» закрой в окне Claude", done.stdout)
        [run] = self.log("claude.jsonl")
        self.assertEqual(run["argv"][-2:], ["--resume", CLI_SESSION])
        self.assert_settings_arg(run)
        self.assertEqual(run["cwd"], os.path.realpath(other), "продолжение — в папке чата")
        done = self.call("term", "Demo", "--from-chat", "local_00000000-0000-0000-0000-000000000000")
        self.assertEqual(done.returncode, 1)
        self.assertIn("в файлах Claude нет", done.stdout)

    def test_existing_tmux_session_is_shown_not_doubled(self):
        self.sessions(**{"rick-Demo": "/dev/ttys001"})
        self.tabs("/dev/ttys001\tlogin,tmux\t✳ claude сменил заголовок\n")
        done = self.call("term", "Demo", "--show", "--text", "привет", tmux=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("уже открыт — показал", done.stdout)
        self.assertIn(", текст отправил", done.stdout)
        self.assertEqual([o["argv"][:2] for o in self.log("osa.jsonl") if o["mark"] == "act"],
                         [["show", "/dev/ttys001"]], "вкладка tmux — по tty клиента, не по заголовку")
        self.assertFalse([a for a in self.log("tmux.jsonl") if a[0] == "new-session"])
        self.assertEqual(self.log("claude.jsonl"), [])
        sends = [a for a in self.log("tmux.jsonl") if a[0] == "send-keys"]
        self.assertEqual(sends, [["send-keys", "-t", "=rick-Demo:", "-l", "--", "привет"],
                                 ["send-keys", "-t", "=rick-Demo:", "Enter"]])
        done = self.call("term", "Demo", "--show", "--last", tmux=True)
        self.assertEqual(done.returncode, 1)
        self.assertIn("другой чат не открыл", done.stdout)

    def test_existing_detached_tmux_session_gets_attach_tab(self):
        self.sessions(**{"rick-Demo": 0})
        done = self.call("term", "Demo", "--show", tmux=True)
        self.assertEqual(done.returncode, 0, done.stdout)
        opens = [o for o in self.log("osa.jsonl") if o["mark"] == "open-terminal"]
        self.assertEqual(len(opens), 1)
        self.assertIn(" attach -t '=rick-Demo'", opens[0]["argv"][0], "голое =имя zsh раскрыл бы в путь команды")
        self.assertEqual([c["argv"][0] for c in self.colors()], ["/dev/ttys900"], "новую вкладку красим")

    def test_existing_terminal_tab_is_shown_after_title_change(self):
        self.live_tab()
        done = self.call("term", "Demo")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual([o["mark"] for o in self.log("osa.jsonl")], ["list", "title", "act", "color"])
        self.assertEqual(self.log("osa.jsonl")[2]["argv"][:2], ["show", "/dev/ttys005"])
        self.assertEqual(self.log("claude.jsonl"), [])

    # ---- WF121: файл разрешений для новых процессов ---------------
    def test_settings_path_quotes_and_initial_prompt_reach_new_process(self):
        settings = self.copy_cli()
        shutil.copyfile(CLI.with_name(settings.name), settings)
        text = "--settings /another-file --resume " + NASTY + "\nвторая строка"
        for use_tmux in (False, True):
            for flags in ((), ("--resume", CLI_SESSION), ("--last",)):
                with self.subTest(tmux=use_tmux, flags=flags):
                    (self.root / "tmux.json").unlink(missing_ok=True)
                    done = self.call("term", "Demo", *flags, "--text", "-", stdin=text, tmux=use_tmux)
                    self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                    run = self.log("claude.jsonl")[-1]
                    self.assert_settings_arg(run)
                    self.assertEqual(run["argv"][-2:], ["--", text])
                    self.assertEqual(run["cwd"], os.path.realpath(self.folder))
                    self.assertNotIn(str(settings), done.stdout, "argv не выдаётся за прочитанный policy")

    def test_from_chat_with_tmux_gets_settings_before_resume_and_prompt(self):
        place = self.root / "sessions" / "acc" / "org"
        place.mkdir(parents=True)
        (place / f"{CHAT}.json").write_text(json.dumps({
            "sessionId": CHAT, "cliSessionId": CLI_SESSION, "cwd": str(self.folder)}))
        done = self.call("term", "Demo", "--from-chat", CHAT, "--text", "1", tmux=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        [run] = self.log("claude.jsonl")
        self.assert_settings_arg(run)
        self.assertEqual(run["argv"][-4:], ["--resume", CLI_SESSION, "--", "1"])

    def test_missing_settings_refuses_new_process_for_both_backends(self):
        self.copy_cli()
        for use_tmux in (False, True):
            with self.subTest(tmux=use_tmux):
                done = self.call("term", "Demo", "--text", "1", tmux=use_tmux)
                self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
                self.assertIn("Файл разрешений", done.stdout)
                self.assertIn("новый чат не запущен", done.stdout)
                self.assert_no_terminal_mutations()
                self.assertFalse((self.support / "term").exists())

    def test_invalid_settings_refuse_launch_without_echoing_contents(self):
        settings = self.copy_cli()
        marker = "private-input-must-not-appear"
        valid = {"allow": [], "ask": ["Bash(rm *)"], "deny": ["Read(~/.ssh/**)"]}
        invalid = {
            "syntax": '{"' + marker + '":',
            "encoding": b"\xff\xfe",
            "null": "null",
            "array": "[]",
            "hooks": json.dumps({"permissions": valid, "hooks": {marker: []}}),
            "env": json.dumps({"permissions": valid, "env": {"X": marker}}),
            "missing-ask": json.dumps({"permissions": {"allow": [], "deny": valid["deny"]}}),
            "missing-deny": json.dumps({"permissions": {"allow": [], "ask": valid["ask"]}}),
            "missing-allow": json.dumps({"permissions": {"ask": valid["ask"], "deny": valid["deny"]}}),
            "mode": json.dumps({"permissions": dict(valid, defaultMode="auto")}),
            "empty-ask": json.dumps({"permissions": dict(valid, ask=[])}),
            "empty-deny": json.dumps({"permissions": dict(valid, deny=[])}),
            "not-object": '{"permissions": []}',
            "not-array": json.dumps({"permissions": dict(valid, ask=marker)}),
            "blank-rule": json.dumps({"permissions": dict(valid, allow=[" \t"])}),
            "empty-rule": json.dumps({"permissions": dict(valid, deny=[""])}),
            "number-rule": json.dumps({"permissions": dict(valid, allow=[1])}),
            "null-rule": json.dumps({"permissions": dict(valid, ask=[None])}),
            "constant": json.dumps({"permissions": dict(valid, allow=[float("nan")])}),
            "duplicate-top": '{"permissions": {}, "permissions":' + json.dumps(valid) + '}',
            "duplicate-section": '{"permissions": {"allow":[], "ask":[], "ask":["Bash(rm *)"], '
                                 '"deny":["Read(~/.ssh/**)"]}}',
            "oversize": json.dumps({"permissions": valid}) + " " * (2 * 1024 * 1024),
            "too-deep": '[' * 1100 + ']' * 1100,
        }
        for name, raw in invalid.items():
            with self.subTest(name=name):
                settings.write_bytes(raw if isinstance(raw, bytes) else raw.encode("utf-8"))
                done = self.call("term", "Demo", "--resume", CLI_SESSION, "--text", "1", tmux=True)
                self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
                self.assertIn("Файл разрешений", done.stdout)
                self.assertNotIn(marker, done.stdout + done.stderr)
                self.assertNotIn("Traceback", done.stderr)
                self.assert_no_terminal_mutations()
                self.assertFalse((self.support / "term").exists())

    def test_settings_must_be_regular_file(self):
        settings = self.copy_cli()
        settings.mkdir()
        done = self.call("term", "Demo")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("Файл разрешений", done.stdout)
        settings.rmdir()
        os.mkfifo(settings)
        done = self.call("term", "Demo", tmux=True)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("Файл разрешений", done.stdout)
        self.assert_no_terminal_mutations()

    def test_empty_allow_and_exact_size_limit_are_valid(self):
        settings = self.copy_cli()
        raw = json.dumps({"permissions": {"allow": [], "ask": ["Bash(rm *)"],
                                          "deny": ["Read(~/.ssh/**)"]}}).encode("utf-8")
        settings.write_bytes(raw + b" " * (2 * 1024 * 1024 - len(raw)))
        done = self.call("term", "Demo", "--last")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assert_settings_arg(self.log("claude.jsonl")[0])

    def test_unreadable_settings_are_plain_error(self):
        with unittest.mock.patch.object(Path, "open", side_effect=PermissionError("private-input")):
            with self.assertRaises(pimp.TermError) as error:
                pimp.term_settings_path()
        self.assertIn("Файл разрешений", str(error.exception))
        self.assertNotIn("private-input", str(error.exception))

    def test_existing_chat_can_be_shown_without_valid_settings(self):
        settings = self.copy_cli()
        for raw in (None, '{"hooks":{}}'):
            if raw is not None:
                settings.write_text(raw)
            for use_tmux in (False, True):
                with self.subTest(settings=raw, tmux=use_tmux):
                    self.live_tab()
                    if use_tmux:
                        self.sessions(**{"rick-Demo": "/dev/ttys005"})
                    done = self.call("term", "Demo", "--show", tmux=use_tmux)
                    self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                    self.assertIn("уже открыт — показал", done.stdout)
                    self.assertNotIn("настройки", done.stdout)
                    self.assertNotIn("--settings", done.stdout)
                    self.assertEqual(self.log("claude.jsonl"), [])

    def test_term_help_explains_settings_and_message_delivery(self):
        term = self.call("term", "--help")
        sender = self.call("term-send", "--help")
        self.assertEqual(term.returncode, 0, term.stderr)
        self.assertEqual(sender.returncode, 0, sender.stderr)
        self.assertIn("claude-term-settings.json", term.stdout)
        self.assertIn("существующий чат", term.stdout)
        self.assertIn("текст", sender.stdout)
        self.assert_no_terminal_mutations()

    def project_status(self, heading="# 🟢Demo", relative="docs/status.md"):
        path = self.folder / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(heading + "\nобновлено сегодня\n", encoding="utf-8")

    def assert_tmux_title(self, title, name="rick-Demo"):
        calls = self.log("tmux.jsonl")
        self.assertIn(["set-option", "-t", "=" + name + ":", "set-titles", "on"], calls)
        self.assertIn(["set-option", "-t", "=" + name + ":", "set-titles-string", title], calls)
        for window in ("@10", "@11"):
            for option in ("allow-rename", "automatic-rename"):
                self.assertIn(["set-option", "-w", "-t", window, option, "off"], calls)
        # Глобальное окружение (#8366) — не опции: метки чата Claude снимаются для всех сессий.
        self.assertFalse(any("-g" in call for call in calls
                             if call[0] not in ("show-environment", "set-environment")),
                         "соседние сессии не меняются")

    def test_new_background_and_shown_sessions_get_project_title(self):
        self.project_status("# 🟢 Demo — состояние")
        for flags in ((), ("--show",)):
            with self.subTest(flags=flags):
                (self.root / "tmux.json").unlink(missing_ok=True)
                (self.root / "tmux.jsonl").unlink(missing_ok=True)
                done = self.call("term", "Demo", *flags, tmux=True)
                self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                self.assert_tmux_title("🟢 Demo")
                if flags:
                    opened = [o for o in self.log("osa.jsonl") if o["mark"] == "open-terminal"][-1]
                    self.assertEqual(opened["argv"][1], "🟢 Demo")
                    calls = self.log("tmux.jsonl")
                    attach = next(i for i, c in enumerate(calls) if c[0] == "attach")
                    title = next(i for i, c in enumerate(calls) if "set-titles-string" in c)
                    self.assertLess(title, attach, "заголовок закреплён до attach")

    def test_existing_sessions_refresh_title_on_term_show_and_list(self):
        self.project_status("# 🟠 Demo", "audit/status.md")
        self.sessions(**{"rick-Demo": "/dev/ttys001", "unrelated": 1})
        self.tabs("/dev/ttys001\tlogin,tmux\t✳ claude\n")
        for args in (("term", "Demo"), ("term", "Demo", "--show"), ("term-list",)):
            with self.subTest(args=args):
                (self.root / "tmux.jsonl").unlink(missing_ok=True)
                (self.root / "osa.jsonl").unlink(missing_ok=True)
                done = self.call(*args, tmux=True)
                self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                self.assert_tmux_title("🟠 Demo")
                # term-list заголовок tmux-чата Terminal'ом не ставит — его держит set-titles (#8365).
                titles = [o["argv"] for o in self.log("osa.jsonl") if o["mark"] == "title"]
                self.assertEqual(titles, [], "заголовок tmux держит set-titles без AppleEvents")
                self.assertFalse(any(c[0] in ("new-session", "send-keys", "rename-session", "kill-session")
                                     for c in self.log("tmux.jsonl")))

    def test_terminal_without_tmux_gets_and_refreshes_custom_title(self):
        self.project_status("# 🎛️[Имя проекта](status.md)")
        done = self.call("term", "Demo")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        opened = [o for o in self.log("osa.jsonl") if o["mark"] == "open-terminal"]
        self.assertEqual(opened[0]["argv"][1], "🎛️ Имя проекта")
        self.live_tab()
        done = self.call("term", "Demo")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        titles = [o for o in self.log("osa.jsonl") if o["mark"] == "title"]
        self.assertEqual(titles[-1]["argv"], ["/dev/ttys005", "🎛️ Имя проекта"])

    def test_title_no_marker_and_only_first_line(self):
        self.project_status("# Demo\n🟢 Нельзя брать вторую строку")
        self.assertEqual(pimp.term_title("Demo", str(self.folder)), "Demo")
        self.project_status("# 🟠Другой проект", "audit/status.md")
        self.assertEqual(pimp.term_title("Demo", str(self.folder)), "🟠 Другой проект")

    @unittest.skipUnless(os.environ.get("PIMP_TEST_REAL_TMUX") == "1" and shutil.which("tmux"),
                         "живой tmux только явно: PIMP_TEST_REAL_TMUX=1")
    def test_title_options_on_isolated_tmux_server(self):
        # Ни один вызов не идёт на сокет рабочих сессий пользователя.
        binary = shutil.which("tmux")
        socket = str(self.root / "title.sock")

        def run(*args):
            return subprocess.run([binary, "-S", socket, *args], capture_output=True,
                                  text=True, timeout=10)

        try:
            for name in ("rick-TitleTest", "unrelated"):
                done = run("-f", "/dev/null", "new-session", "-d", "-s", name, "/bin/sleep 30")
                self.assertEqual(done.returncode, 0, done.stderr)
            with unittest.mock.patch.object(pimp, "tmux", side_effect=run), \
                    unittest.mock.patch.object(pimp, "term_tab_ttys", return_value=[]):
                pimp.term_set_title({"name": "rick-TitleTest", "kind": "tmux"}, "🟢 Test #{session_name}")
            self.assertEqual(run("show-options", "-A", "-v", "-t", "=unrelated:", "set-titles").stdout.strip(), "off")
            self.assertEqual(run("show-options", "-v", "-t", "=rick-TitleTest:", "set-titles").stdout.strip(), "on")
            self.assertEqual(run("display-message", "-p", "-t", "=rick-TitleTest:",
                                 "#{T:set-titles-string}").stdout.strip(), "🟢 Test #{session_name}")
            for option in ("allow-rename", "automatic-rename"):
                self.assertEqual(run("show-options", "-w", "-v", "-t", "=rick-TitleTest:", option).stdout.strip(), "off")
        finally:
            run("kill-server")

    def transcript(self, folder=None, name="latest", text=None, age=7):
        folder = str(folder or self.folder)
        directory = self.root / "transcripts" / re.sub(r"[^a-zA-Z0-9]", "-", folder)
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / (name + ".jsonl")
        if text is None:
            text = (ROOT / "tests/fixtures/term/context.jsonl").read_text(encoding="utf-8")
        path.write_text(text, encoding="utf-8")
        stamp = time.time() - (age * 60 + 15)
        os.utime(path, (stamp, stamp))
        return path

    def test_summary_terminal_context_and_age_preserves_desktop_line(self):
        self.live_tab()
        self.transcript()
        answer = {"ok": True, "windows": [{"title": "Окно", "folder": "/x/Desktop", "chat": ""}]}
        done = self.call("summary", app_result=answer)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(done.stdout.splitlines(), ["Desktop · «Окно» — нет данных",
                         "rick-Demo (terminal) · ctx 368K · 7 мин назад"])
        self.assertEqual([o["mark"] for o in self.log("osa.jsonl")], ["list"], "summary не меняет заголовки")

    def test_summary_tmux_without_record_latest_file_and_read_only(self):
        self.sessions(**{"rick-Demo": 0, "rick-Missing": 0, "other": 1})
        dead = self.record("Gone", tmux="rick-Gone")
        self.transcript(name="older", text=json.dumps({"type": "assistant", "message": {
            "usage": {"input_tokens": 999000}}}) + "\n", age=60)
        self.transcript(name="newer")
        done = self.call("summary", "--json", tmux=True, app_result={"ok": True, "windows": []})
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        cards = json.loads(done.stdout)
        self.assertEqual([(c["name"], c["contextTokens"], c["activityMinutes"]) for c in cards],
                         [("rick-Demo", 368000, 7), ("rick-Missing", None, None)])
        self.assertTrue(dead.exists(), "summary не чистит реестр")
        self.assertEqual(self.log("tmux.jsonl"), [["list-sessions", "-F", "#{session_name}\t#{session_attached}"]])

    def test_summary_uses_record_cwd_and_handles_damaged_tail(self):
        self.sessions(**{"rick-Demo": 0})
        cwd = self.root / "worktree"
        self.record(tmux="rick-Demo", cwd=str(cwd))
        self.transcript()  # папка проекта — не cwd продолжаемого чата
        self.transcript(folder=cwd, text='{"pad":"' + "x" * 3_000_100 + '"}\n' +
                        (ROOT / "tests/fixtures/term/context.jsonl").read_text() + '\n{"partial":')
        done = self.call("summary", tmux=True, app_result={"ok": True, "windows": []})
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(done.stdout.strip(), "rick-Demo (tmux) · ctx 368K · 7 мин назад")

    def test_context_reader_ignores_usage_outside_tail(self):
        self.transcript(text=json.dumps({"type": "assistant", "message": {
            "usage": {"input_tokens": 1000}}}) + "\n" + "x" * 3_000_010)
        with unittest.mock.patch.dict(os.environ, {"MYCLAUDE_CLAUDE_PROJECTS": str(self.root / "transcripts")}):
            card = pimp.term_summary({"name": "rick-Demo", "kind": "tmux", "folder": str(self.folder)})
        self.assertIsNone(card["contextTokens"])
        self.assertEqual(card["activityMinutes"], 7)

    def test_summary_missing_or_malformed_usage_is_dash(self):
        self.live_tab()
        self.transcript(text='null\n[]\n{"type":"assistant","message":{"usage":{"input_tokens":"bad"}}}\n')
        done = self.call("summary", app_result={"ok": True, "windows": []})
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(done.stdout.strip(), "rick-Demo (terminal) · ctx — · 7 мин назад")

    def test_automation_denied_is_plain_line(self):
        done = self.call("term", "Demo", extra={"FAKE_OSA_DENY": "1"})
        self.assertEqual(done.returncode, 1)
        self.assertIn("Автоматизация", done.stdout)
        self.assertEqual(list((self.support / "term").glob("*.sh")), [], "файл запуска не остаётся")

    # ---- term-send --------------------------------------------------------------
    def test_send_tmux_literal_and_multiline_as_paste(self):
        self.sessions(**{"rick-Demo": 1})
        done = self.call("term-send", "demo", NASTY, tmux=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(done.stdout.strip(), "Отправил в терминал rick-Demo")
        text = "строка 1\r\nстрока 2\x1b[201~\x03\tконец"
        done = self.call("term-send", "Demo", "-", stdin=text, tmux=True)
        self.assertEqual(done.returncode, 0, done.stdout)
        sends = [a for a in self.log("tmux.jsonl") if a[0] == "send-keys"]
        self.assertEqual(sends[0][-1], NASTY)
        self.assertEqual(sends[2][-1], "\x1b[200~строка 1\nстрока 2[201~\tконец\x1b[201~",
                         "Esc и Ctrl+C из текста вырезаны, вставку не закрыть изнутри")
        self.assertEqual(sends[3][-1], "Enter")

    def test_send_finds_tab_by_tty_after_title_change(self):
        self.live_tab(title="◑ PimpViewer марафон оркестрация")
        done = self.call("term-send", "rick-demo", "раз\nдва")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(done.stdout.strip(), "Отправил в терминал rick-Demo")
        act = [o for o in self.log("osa.jsonl") if o["mark"] == "act"][0]
        self.assertEqual(act["script"], pimp.OSA_ACT)
        self.assertEqual(act["argv"][:3], ["send", "/dev/ttys005", "\x1b[200~раз\nдва\x1b[201~"])

    def test_send_refuses_bare_shell_and_missing_chat(self):
        self.tabs("/dev/ttys005\tlogin,-zsh\trick-Demo\n")
        done = self.call("term-send", "Demo", "ls")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Терминального чата rick-Demo нет", done.stdout)
        self.assertFalse([o for o in self.log("osa.jsonl") if o["mark"] == "act"])
        done = self.call("term-send", "Demo", "   ")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Текст пустой", done.stdout)

    def test_send_two_live_tabs_is_ambiguous(self):
        demo = self.root / "Demo"
        demo.mkdir()
        self.tabs("/dev/ttys001\tlogin,claude\ta\n/dev/ttys002\tlogin,claude\tb\n")
        self.ps(ttys001=[[11, "claude"]], ttys002=[[22, "claude"]])
        self.lsof(**{"11": str(demo), "22": str(demo)})
        done = self.call("term-send", "Demo", "текст")
        self.assertEqual(done.returncode, 1)
        self.assertIn("несколько", done.stdout)

    # ---- реестр: мёртвые записи и чаты без записи ---------------------------------
    def test_dead_record_is_removed(self):
        path = self.live_tab()
        self.ps(ttys005=[[499, "login"], [612, "/bin/zsh"]])  # claude вышел, на tty уже другое
        tmux_path = self.record("Gone", tmux="rick-Gone", tty="/dev/ttys007", pid=7)
        done = self.call("term-list", tmux=True)
        self.assertEqual(done.stdout.strip(), "Терминальных чатов нет")
        self.assertFalse(path.exists(), "мёртвая запись вкладки убрана")
        self.assertFalse(tmux_path.exists(), "сессии tmux нет — запись убрана")

    def test_broken_ps_keeps_record(self):
        path = self.live_tab()
        done = self.call("term-list", extra={"PIMP_TERM_PS": str(self.root / "no-ps")})
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertTrue(path.exists(), "не проверили — не хороним")

    def test_record_less_claude_tab_found_by_cwd(self):
        viewer = self.root / "PimpViewer"
        viewer.mkdir()
        self.tabs("/dev/ttys018\tlogin,claude,caffeinate\t◐ PimpViewer марафон оркестрация\n"
                  "/dev/ttys016\tlogin,-zsh,node,codex\t⠴ VkusnoffKz\n")
        self.ps(ttys018=[[84924, "login"], [84925, "/Users/x/Application Support/claude.app/Contents/MacOS/claude"]])
        self.lsof(**{"84925": str(viewer)})
        done = self.call("term-list", "--with-terminal")
        self.assertEqual(done.stdout.strip(), "Терминальные чаты: rick-PimpViewer (Terminal, без записи)")
        done = self.call("term-send", "PimpViewer", "привет")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        act = [o for o in self.log("osa.jsonl") if o["mark"] == "act"][0]
        self.assertEqual(act["argv"][:3], ["send", "/dev/ttys018", "привет"])
        self.assertNotIn("/dev/ttys016", json.dumps(self.log("osa.jsonl")), "codex не трогаем")

    # ---- term-list --------------------------------------------------------------
    def test_list(self):
        done = self.call("term-list")
        self.assertEqual(done.stdout.strip(), "Терминальных чатов нет")
        self.sessions(**{"rick-A": 1, "rick-B": 0, "other": 1})
        self.tabs("/dev/ttys001\tlogin,tmux\trick-A\n/dev/ttys003\tlogin,claude\t◑ что-то своё\n"
                  "/dev/ttys004\tlogin,-zsh\trick-D\n/dev/ttys005\tlogin,claude\t✳ E\n")
        self.ps(ttys003=[[30, "claude"]], ttys005=[[50, "claude"]])
        self.lsof(**{"30": "/x/C"})
        self.record("E", tty="/dev/ttys005", pid=50)
        done = self.call("term-list", "--with-terminal", tmux=True)
        self.assertEqual(done.returncode, 0)
        self.assertEqual(done.stdout.strip(), "Терминальные чаты: rick-A (tmux, подключён), "
                                              "rick-B (tmux, без вкладки), rick-C (Terminal, без записи), "
                                              "rick-E (Terminal)")
        done = self.call("term-list", "--with-terminal", "--json", tmux=True)
        self.assertEqual([item["name"] for item in json.loads(done.stdout)], ["rick-A", "rick-B", "rick-C", "rick-E"])

    # ---- ответ Рику из терминала: send без своего чата ---------------------------
    def test_send_to_rick_works_without_host_session(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        answer = json.loads((ROOT / "tests" / "fixtures" / "pimp" / "send.result.json").read_text())
        done = self.call("send", "--chat", CHAT, "готово", session=None, app_result=answer)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        request = self.app.requests[0]
        self.assertEqual((request["from"], request["chat"], request["text"]), ("", CHAT, "готово"))

    # ---- цвета вкладки = цвет окна проекта ----------------------------------------
    THEMES = {
        # светлая «Апельсин» (my-themes), тёмная «Дракула», оранжевая «Вкуснофф»
        "light": ({"id": "user-1790071800259", "name": "Апельсин", "type": "light", "palette": {
            "accent": "#a31000", "background": "#ffcb8f", "foreground": "#321f08", "sidebar": "#ffb969",
            "panel": "#ffedd9", "muted": "#815d35"}},
            ["65535", "52171", "36751", "12850", "7967", "2056", "41891", "4112", "0"]),
        "dark": ({"id": "dracula", "name": "Дракула", "type": "dark", "palette": {
            "accent": "#bd93f9", "background": "#282a36", "foreground": "#f8f8f2", "sidebar": "#21222c",
            "panel": "#343746", "muted": "#6272a4"}},
            ["10280", "10794", "13878", "63736", "63736", "62194", "48573", "37779", "63993"]),
        "vkusnoff": ({"id": "vkusnoff", "name": "Вкуснофф", "type": "dark", "palette": {
            "accent": "#ff9800", "background": "#0f0f10", "foreground": "#f5f2ee", "sidebar": "#17171a",
            "panel": "#1c1c1e", "muted": "#b8b0a8"}},
            ["3855", "3855", "4112", "62965", "62194", "61166", "65535", "39064", "0"]),
    }

    def project_theme(self, theme):
        (self.folder / ".pimpmyclaude.json").write_text(json.dumps(
            {"pimpmyclaude": 1, "name": "Demo", "theme": theme}, ensure_ascii=False), encoding="utf-8")

    def colors(self) -> list:
        return [o for o in self.log("osa.jsonl") if o["mark"] == "color"]

    def test_new_tab_gets_project_theme_colors(self):
        for kind, (theme, numbers) in self.THEMES.items():
            with self.subTest(kind):
                self.project_theme(theme)
                (self.root / "osa.jsonl").unlink(missing_ok=True)
                (self.root / "tabs.txt.opened").unlink(missing_ok=True)
                done = self.call("term", "Demo", "--show", tmux=True)
                self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                self.assertIn(f", цвета темы «{theme['name']}»", done.stdout)
                self.assertEqual([o["mark"] for o in self.log("osa.jsonl")], ["open-terminal", "color"])
                [color] = self.colors()
                self.assertEqual(color["script"], pimp.OSA_COLOR, "скрипт постоянный — цвета аргументами")
                self.assertEqual(color["argv"], ["/dev/ttys900"] + numbers)
                (self.root / "tmux.json").unlink()

    def test_project_without_view_gets_auto_color_like_window(self):
        # Числа сверены со Swift AutoPaint.projectTheme: «Pro ject $x `y` 'q'» → 78°,
        # фон #2b3611, текст #edf0e6, акцент #83b314.
        done = self.call("term", "Demo")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn(f", цвета темы «{self.folder.name} · 78°»", done.stdout)
        [color] = self.colors()
        self.assertEqual(color["argv"][1:], pimp.term_rgb16("#2b3611") + pimp.term_rgb16("#edf0e6")
                         + pimp.term_rgb16("#83b314"))

    def test_auto_palette_matches_swift(self):
        # Эталоны — вывод Swift AutoPaint.palette(hue:light:false) и hue(forName:) (ProjectTests).
        for name, hue, colors in (("PimpMyClaude", 199, ("#112b36", "#e6ecf0", "#19a2e1")),
                                  ("VkusnoffKz", 232, ("#111636", "#e6e7f0", "#7182ef")),
                                  ("PimpViewer", 349, ("#361118", "#f0e6e7", "#ed5e79")),
                                  ("Диктатор", 208, ("#112536", "#e6ebf0", "#3e9aea"))):
            self.assertEqual(pimp.auto_hue(name), hue, name)
            palette = pimp.auto_palette(hue)
            self.assertEqual((palette["background"], palette["foreground"], palette["accent"]), colors, name)

    def test_open_tab_is_repainted_on_second_term_and_by_term_color(self):
        theme, numbers = self.THEMES["vkusnoff"]
        self.project_theme(theme)
        self.live_tab()
        done = self.call("term", "Demo")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("уже открыт — показал, цвета темы «Вкуснофф»", done.stdout)
        self.assertEqual([o["mark"] for o in self.log("osa.jsonl")], ["list", "title", "act", "color"])
        light, light_numbers = self.THEMES["light"]
        self.project_theme(light)
        done = self.call("term-color", "demo")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(done.stdout.strip(), "Покрасил rick-Demo в тему «Апельсин»")
        self.assertEqual([c["argv"] for c in self.colors()],
                         [["/dev/ttys005"] + numbers, ["/dev/ttys005"] + light_numbers])

    def test_no_color_when_project_says_so_or_toggle_off(self):
        self.project_theme(None)  # «Как у Claude» пишет "theme": null — цвета нет
        self.call("term", "Demo", tmux=True)
        self.assertEqual(self.colors(), [], "цвета нет — профиль Терминала как есть")
        done = self.call("term-color", "Demo", tmux=True)
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertEqual(done.stdout.strip(),
                         f"У проекта {self.folder.name} цвета окна нет — вкладку rick-Demo не крашу")
        (self.folder / ".pimpmyclaude.json").unlink()
        prefs = self.root / "Library" / "Preferences"
        prefs.mkdir(parents=True)
        with open(prefs / "com.elvis.pimpmyclaude.plist", "wb") as file:
            plistlib.dump({"projectPaintEnabled": False}, file)
        done = self.call("term-color", "Demo", tmux=True)
        self.assertIn("цвета окна нет", done.stdout, "тумблер «Цвет по проекту» выключен")
        self.assertEqual(self.colors(), [])

    def test_term_color_without_tab_fails(self):
        self.project_theme(self.THEMES["dark"][0])
        done = self.call("term-color", "Demo")
        self.assertEqual(done.returncode, 1)
        self.assertIn("Терминального чата rick-Demo нет", done.stdout)

    def test_theme_hex_like_page_and_registry(self):
        with unittest.mock.patch.dict(os.environ, {"HOME": str(self.root), "MYCLAUDE_PIMP_DIR": str(self.dir)}):
            self.project_theme({"type": "light", "palette": {"background": "#AbC", "foreground": "junk"}})
            theme = pimp.term_theme(str(self.folder))
            self.assertEqual((theme["background"], theme["foreground"], theme["accent"]),
                             ("#aabbcc", "#111827", "#2563eb"), "короткий hex растянут, мусор — запасной цвет")
            (self.folder / ".pimpmyclaude.json").unlink()
            (self.support / "project-views.json").write_text(json.dumps({"version": 1, "projects": {
                str(self.folder): {"theme": self.THEMES["dark"][0]}}}), encoding="utf-8")
            self.assertEqual(pimp.term_theme(str(self.folder))["name"], "Дракула",
                             "в папку писать нельзя — вид из запасного реестра")

    # ---- WF120: метки чата Claude вне tmux (#8366), tmux без Terminal (#8365) -------------
    MARKS = {"CLAUDE_CODE_SESSION_ID": "fake-session-8366", "CLAUDE_CODE_MESSAGING_SOCKET": "/fake/sock-8366",
             "CLAUDE_CODE_MESSAGING_TOKEN": "fake-token-must-not-leak-8366"}

    def assert_no_marks(self, done):
        [run] = self.log("claude.jsonl")
        self.assertEqual([name for name in run["names"] if name == "CLAUDECODE" or name in self.MARKS], [],
                         "claude в tmux не видит меток чата Claude")
        self.assertIn("CLAUDE_CONFIG_DIR", run["names"], "настройки человека не трогаем")
        self.assertEqual(run["disable_title"], "1")
        seen = done.stdout + done.stderr + (self.root / "tmux.jsonl").read_text(encoding="utf-8")
        for value in self.MARKS.values():
            self.assertNotIn(value, seen, "значения не печатаем и не передаём аргументами")

    def test_new_tmux_server_is_born_without_claude_marks(self):
        done = self.call("term", "Demo", tmux=True, extra=dict(self.MARKS, CLAUDE_CONFIG_DIR="/fake/config"))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        calls = self.log("tmux.jsonl")
        self.assertIn(["show-environment", "-g"], calls, "сервера нет — отказ show-environment не ошибка")
        self.assertFalse([c for c in calls if c[0] == "set-environment"])
        self.assert_no_marks(done)
        born = json.loads((self.root / "tmux-born-names.json").read_text())
        self.assertEqual([name for name in born if pimp.term_host_var(name)], [])
        self.assertIn("CLAUDE_CONFIG_DIR", born)
        self.assertIn("PATH", born)

    def test_live_tmux_server_from_chat_drops_claude_marks(self):
        self.sessions(**{"rick-Other": 0})
        (self.root / "tmux-env.json").write_text(json.dumps(dict(
            self.MARKS, CLAUDECODE="1", CLAUDE_CONFIG_DIR="/fake/config", PATH="/usr/bin:/bin",
            **{"-CLAUDE_CODE_ENTRYPOINT": None})), encoding="utf-8")
        done = self.call("term", "Demo", tmux=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        calls = self.log("tmux.jsonl")
        dropped = sorted(c[-1] for c in calls if c[:3] == ["set-environment", "-g", "-u"])
        self.assertEqual(dropped, sorted(["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", *self.MARKS]))
        self.assertLess(calls.index(["set-environment", "-g", "-u", "CLAUDECODE"]),
                        next(i for i, c in enumerate(calls) if c[0] == "new-session"), "чистка — до new-session")
        self.assertEqual(json.loads((self.root / "tmux-env.json").read_text())["CLAUDE_CONFIG_DIR"], "/fake/config")
        self.assert_no_marks(done)

    def test_tmux_refusing_to_drop_marks_opens_nothing(self):
        self.sessions(**{"rick-Other": 0})
        (self.root / "tmux-env.json").write_text(json.dumps({"CLAUDECODE": "1"}), encoding="utf-8")
        done = self.call("term", "Demo", tmux=True, extra={"FAKE_TMUX_SETENV_FAIL": "1"})
        self.assertEqual(done.returncode, 1)
        self.assertEqual(done.stdout.strip(), "tmux не снял CLAUDECODE из своего окружения — сессию не завёл")
        self.assertFalse([c for c in self.log("tmux.jsonl") if c[0] == "new-session"])
        self.assertEqual(list((self.support / "term").glob("*.sh")), [], "файла запуска нет")

    def test_existing_tmux_session_does_not_touch_environment(self):
        self.sessions(**{"rick-Demo": 0})
        done = self.call("term", "Demo", tmux=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertFalse([c for c in self.log("tmux.jsonl") if c[0].endswith("-environment")])

    def test_default_list_uses_registry_without_appleevents(self):
        self.sessions(**{"rick-Demo": 0})
        self.live_tab(tty="/dev/ttys005")
        for flags in ((), ("--json",)):
            done = self.call("term-list", *flags, tmux=True, extra={"FAKE_OSA_SLEEP": "1"})
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertEqual(done.stderr, "")
            self.assertEqual(self.log("osa.jsonl"), [])
            if flags:
                self.assertEqual([item["kind"] for item in json.loads(done.stdout)], ["tmux", "terminal"])

    def test_new_and_existing_background_chat_ignore_hung_terminal(self):
        for args in (("term", "Demo"), ("term", "Demo", "--text", "hello")):
            done = self.call(*args, tmux=True, extra={"FAKE_OSA_SLEEP": "1"})
            self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertEqual(self.log("osa.jsonl"), [])
        self.assertEqual(len([c for c in self.log("tmux.jsonl") if c[0] == "new-session"]), 1)

    def test_list_session_errors_preserve_registry_and_block_actions(self):
        saved = self.record(tmux="rick-Demo")
        before = saved.read_bytes()
        self.sessions(**{"rick-Demo": 0})
        for fault in ("FAKE_TMUX_FAIL", "FAKE_TMUX_SLEEP"):
            for args in (("term-list", "--json"), ("term-send", "Demo", "x"), ("term", "Demo")):
                with self.subTest(fault=fault, args=args):
                    done = self.call(*args, tmux=True, extra={fault: "list-sessions"}, short_timeout=0.3)
                    self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
                    self.assertIn("tmux", done.stdout + done.stderr)
                    self.assertNotIn(self.MARKS["CLAUDE_CODE_MESSAGING_TOKEN"], done.stdout + done.stderr)
                    self.assertEqual(saved.read_bytes(), before)
                    self.assertEqual(list(saved.parent.glob("*.sh")), [])
                    if "--json" in args:
                        self.assertEqual(done.stdout, "")
        self.assertTrue(all(c[0] == "list-sessions" for c in self.log("tmux.jsonl")))
        self.assertEqual(self.log("osa.jsonl"), [])

    def test_environment_read_failure_or_timeout_blocks_new_session(self):
        self.sessions(**{"rick-Other": 0})
        for fault in ("FAKE_TMUX_FAIL", "FAKE_TMUX_SLEEP"):
            with self.subTest(fault=fault):
                done = self.call("term", "Demo", tmux=True, extra={fault: "show-environment"}, short_timeout=0.3)
                self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
                self.assertIn("tmux", done.stdout)
                self.assertNotIn(self.MARKS["CLAUDE_CODE_MESSAGING_TOKEN"], done.stdout + done.stderr)
                self.assertEqual(list((self.support / "term").glob("*.sh")), [])
        self.assertFalse([c for c in self.log("tmux.jsonl") if c[0] in ("new-session", "send-keys")])
        self.assertEqual(self.log("claude.jsonl"), [])

    def test_ambiguous_tmux_name_never_sends_or_launches(self):
        self.sessions(**{"rick-Demo": 0, "rick-demo": 0})
        for args in (("term-send", "Demo", "x"), ("term", "Demo")):
            done = self.call(*args, tmux=True)
            self.assertEqual(done.returncode, 1, done.stdout)
            self.assertIn("несколько", done.stdout)
        self.assertFalse([c for c in self.log("tmux.jsonl") if c[0] in ("new-session", "send-keys")])
        self.assertEqual(self.log("osa.jsonl"), [])

    def test_terminal_launcher_cleans_host_marks_and_keeps_config(self):
        done = self.call("term", "Demo", extra=dict(self.MARKS, CLAUDE_CONFIG_DIR="/fake/config"))
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        run = self.log("claude.jsonl")[0]
        self.assertEqual([n for n in run["names"] if pimp.term_host_var(n)], ["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"])
        self.assertIn("CLAUDE_CONFIG_DIR", run["names"])
        for value in self.MARKS.values():
            self.assertNotIn(value, done.stdout + done.stderr + (self.root / "claude.jsonl").read_text())

    def test_no_server_is_distinct_from_read_error(self):
        for error in ("no server running", "no server running on /tmp/tmux-0/default",
                      "error connecting to /tmp/tmux-0/default (No such file or directory)"):
            self.assertTrue(pimp.tmux_no_server(subprocess.CompletedProcess([], 1, "", error)))
        for error in ("permission denied", "no sessions", "", "no server running\npermission denied"):
            self.assertFalse(pimp.tmux_no_server(subprocess.CompletedProcess([], 1, "", error)))

    def test_send_to_tmux_never_asks_terminal(self):
        # Terminal не пускает (или висит) — tmux-чат всё равно получает текст, osascript не зовётся.
        self.sessions(**{"rick-Demo": 0})
        done = self.call("term-send", "demo", "привет", tmux=True, extra={"FAKE_OSA_DENY": "1"})
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(done.stdout.strip(), "Отправил в терминал rick-Demo")
        self.assertEqual(self.log("osa.jsonl"), [])
        self.assertEqual([c for c in self.log("tmux.jsonl") if c[0] == "send-keys"],
                         [["send-keys", "-t", "=rick-Demo:", "-l", "--", "привет"],
                          ["send-keys", "-t", "=rick-Demo:", "Enter"]])

    def test_term_color_of_tmux_chat_takes_folder_from_record(self):
        self.project_theme(self.THEMES["dark"][0])
        self.sessions(**{"rick-Demo": "/dev/ttys001"})
        self.tabs("/dev/ttys001\tlogin,tmux\t✳ claude\n")
        self.record(tmux="rick-Demo")
        done = self.call("term-color", "Demo", tmux=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(done.stdout.strip(), "Покрасил rick-Demo в тему «Дракула»")
        self.assertEqual([o["mark"] for o in self.log("osa.jsonl")], ["color"], "вкладки не перечитываем")

    def test_missing_chat_with_terminal_refusal_names_terminal(self):
        done = self.call("term-send", "Demo", "текст", tmux=True, extra={"FAKE_OSA_DENY": "1"})
        self.assertEqual(done.returncode, 1)
        self.assertIn("Нет доступа к Terminal", done.stdout, "не «чата нет»: вкладки не прочитаны")

    def test_list_survives_terminal_refusal(self):
        self.sessions(**{"rick-A": "/dev/ttys001", "rick-B": 0})
        self.ps(ttys005=[[50, "claude"]])
        self.record("E", tty="/dev/ttys005", pid=50)
        stale = self.record("Unverified", tty="/dev/ttys006", pid=60)
        deny = {"FAKE_OSA_DENY": "1"}
        for flags in ((), ("--json",)):
            with self.subTest(flags=flags):
                done = self.call("term-list", "--with-terminal", *flags, tmux=True, extra=deny)
                self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
                self.assertIn("Вкладки Terminal не прочитал: Нет доступа к Terminal", done.stderr)
                self.assertTrue(stale.exists(), "отказ Terminal не удаляет непроверенную запись")
                if flags:
                    self.assertEqual([item["name"] for item in json.loads(done.stdout)],
                                     ["rick-A", "rick-B", "rick-E"])
                else:
                    self.assertIn("rick-A (tmux, подключён)", done.stdout)
                self.assertTrue(all(o["mark"] == "list" for o in self.log("osa.jsonl")))

    def test_tabs_read_has_short_timeout(self):
        slow = self.bin / "slow-osascript"
        slow.write_text("#!/bin/sh\nexec sleep 30\n", encoding="utf-8")
        slow.chmod(0o755)
        env = {"PIMP_TERM_OSASCRIPT": str(slow), "PIMP_TERM_TMUX": "none", "MYCLAUDE_PIMP_DIR": str(self.dir),
               "PIMP_TERM_PS": str(self.bin / "ps"), "FAKE_PS": str(self.root / "ps.json")}
        out, err = io.StringIO(), io.StringIO()
        with unittest.mock.patch.dict(os.environ, env), \
                unittest.mock.patch.object(pimp, "TERM_TABS_TIMEOUT_S", 0.2), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            started = time.monotonic()
            code = pimp.main(["term-list", "--with-terminal", "--json"])
            elapsed = time.monotonic() - started
        self.assertEqual((code, json.loads(out.getvalue())), (0, []))
        self.assertIn("Terminal не ответил за 0.2 с", err.getvalue())
        self.assertLess(elapsed, 5)

    # ---- мелочи ---------------------------------------------------------------------
    def test_term_name_is_tmux_safe(self):
        self.assertEqual(pimp.term_name("Vkus.noff:Kz"), "rick-Vkus_noff_Kz")
        self.assertEqual(pimp.term_name("/a/b/Диктатор"), "rick-Диктатор")

    def test_newest_claude_version_wins(self):
        base = self.root / "claude-code"
        for version in ("2.1.9", "2.1.284", "2.1.30", "junk"):
            binary = base / version / "claude.app" / "Contents" / "MacOS" / "claude"
            binary.parent.mkdir(parents=True)
            binary.write_text("#!/bin/sh\n")
            binary.chmod(0o755)
        with unittest.mock.patch.object(pimp, "CLAUDE_CODE_DIR", base), \
                unittest.mock.patch.dict(os.environ, {"PIMP_TERM_CLAUDE": ""}):
            self.assertIn("/2.1.284/", pimp.claude_binary())
            # Обновлённый Claude: <версия>/<хеш>/claude.app — на уровень глубже.
            nested = base / "2.1.286" / "f2326db61802" / "claude.app" / "Contents" / "MacOS" / "claude"
            nested.parent.mkdir(parents=True)
            nested.write_text("#!/bin/sh\n")
            nested.chmod(0o755)
            self.assertEqual(pimp.claude_binary(), str(nested))

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("osacompile"), "нужен osacompile")
    def test_terminal_scripts_compile(self):
        for script in (pimp.OSA_OPEN_TERMINAL, pimp.OSA_LIST, pimp.OSA_ACT, pimp.OSA_COLOR, pimp.OSA_TITLE):
            done = subprocess.run(["osacompile", "-o", str(self.root / "x.scpt"), "-"], input=script,
                                  capture_output=True, text=True, timeout=30)
            self.assertEqual(done.returncode, 0, done.stderr)


if __name__ == "__main__":
    unittest.main()
