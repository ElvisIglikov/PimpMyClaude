#!/usr/bin/env python3
"""Тесты чтения «prs» CLI «Пимп» (WF120, #8030, контракт К-B4): запросы команды на GitHub.

Настоящего gh и сети тут нет: подставной gh лежит в PATH и отвечает по плану из файла
(FAKE_GH_PLAN), каждый вызов пишет в журнал (FAKE_GH_LOG). Запасные места gh
(/opt/homebrew/bin) отключены — до настоящего gh тест не дотянется. Проверяем, что CLI
спрашивает у gh и что показывает; только подставные чтения.

Запуск: python3 -B -m unittest tests/pimp_prs_test.py (строка в tools/test.sh).
"""

import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import time
import unittest
import unittest.mock
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools" / "pimp.py"
REPO = "ElvisIglikov/PimpMyClaude"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pimp = load("pimp_for_prs_test", CLI)

# План: {вид: ответ}; ответ — JSON (уйдёт в stdout) или {"code", "err", "out"}. Вид — по аргументам.
FAKE_GH = r'''
import json, os, sys, time, signal
args = sys.argv[1:]
with open(os.environ["FAKE_GH_LOG"], "a", encoding="utf-8") as f:
    f.write(json.dumps(args, ensure_ascii=False) + "\n")
plan = json.load(open(os.environ["FAKE_GH_PLAN"], encoding="utf-8"))
if args[:2] == ["api", "user"]:
    kind = "user"
elif args[0] == "api" and args[1].startswith("user/orgs?"):
    page = args[1].rsplit("page=", 1)[-1]
    kind = "orgs" if page == "1" else "orgs" + page
elif args[:2] == ["api", "graphql"]:
    cursor = next((a[7:] for a in args if a.startswith("cursor=")), "")
    kind = "search" + cursor
else:
    kind = "?"
answer = plan.get(kind, {"code": 1, "err": "unexpected " + kind})
if isinstance(answer, dict) and answer.get("sleep"):
    with open(os.environ["FAKE_GH_PID"], "w") as f:
        f.write(str(os.getpid()))
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if answer.get("close_pipes"):
        os.close(1); os.close(2)
    time.sleep(30)
if not (isinstance(answer, dict) and "code" in answer):
    answer = {"code": 0, "out": answer}
out = answer.get("out", "")
sys.stdout.write(out if isinstance(out, str) else json.dumps(out, ensure_ascii=False))
sys.stderr.write(answer.get("err", ""))
sys.exit(answer["code"])
'''


def stamp(minutes: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(minutes=minutes, seconds=20)).strftime("%Y-%m-%dT%H:%M:%SZ")


def node(number=5, repo=REPO, author="octocat", title="Фикс", minutes=30, draft=False, state="OPEN",
         mergeable="MERGEABLE", checks="SUCCESS", base="main", head="fix-x", oid="abc123"):
    """Узел PullRequest, как его отдаёт GraphQL на запрос PR_FIELDS."""
    rollup = {"state": checks} if checks else None
    return {"number": number, "title": title, "url": f"https://github.com/{repo}/pull/{number}",
            "createdAt": stamp(minutes), "isDraft": draft, "state": state, "baseRefName": base,
            "headRefName": head, "headRefOid": oid, "mergeable": mergeable,
            "repository": {"nameWithOwner": repo}, "author": {"login": author} if author else None,
            "commits": {"nodes": [{"commit": {"statusCheckRollup": rollup}}]}}


def search(*nodes, total=None, more=False, cursor=None):
    return {"data": {"search": {"issueCount": len(nodes) if total is None else total, "nodes": list(nodes),
                               "pageInfo": {"hasNextPage": more, "endCursor": cursor}}}}


ME = {"user": {"login": "ElvisIglikov"}, "orgs": [{"login": "VkusnoffKz"}]}


class PrsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        gh = self.bin / "gh"
        gh.write_text(f"#!{sys.executable}\n" + FAKE_GH, encoding="utf-8")
        gh.chmod(0o755)

    def run_cli(self, *argv, plan=None, gh=True):
        (self.root / "plan.json").write_text(json.dumps(plan or {}, ensure_ascii=False), encoding="utf-8")
        env = {"PATH": (f"{self.bin}:" if gh else "") + "/usr/bin:/bin",
               "FAKE_GH_PLAN": str(self.root / "plan.json"), "FAKE_GH_LOG": str(self.root / "gh.jsonl"),
               "FAKE_GH_PID": str(self.root / "gh.pid")}
        out, err = io.StringIO(), io.StringIO()
        with unittest.mock.patch.dict(os.environ, env), unittest.mock.patch.object(pimp, "GH_PLACES", ()), \
                unittest.mock.patch.object(pimp.shutil, "which", return_value=str(self.bin / "gh") if gh else None), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = pimp.main(list(argv))
        self.err = err.getvalue().strip()
        # Любой непредусмотренный вызов к gh валит тест, включая write-команду или mutation GraphQL.
        for call in self.calls():
            self.assertEqual(call[0], "api")
            self.assertTrue(call[1] in ("user", "graphql") or call[1].startswith("user/orgs?"))
            if call[1] == "graphql":
                self.assertTrue(next(a for a in call if a.startswith("query=")).startswith("query=query("))
        return code, out.getvalue().strip()

    def calls(self) -> list:
        path = self.root / "gh.jsonl"
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]

    # ---- prs: список --------------------------------------------------------------
    def test_prs_lists_team_requests_newest_first(self):
        plan = dict(ME, search=search(
            node(7, repo="VkusnoffKz/site", author="user-a", title="Новое меню", minutes=3 * 24 * 60, draft=True,
                 mergeable="CONFLICTING", checks="FAILURE"),
            node(5, minutes=30),
            node(8, author="ElvisIglikov", title="своё"),         # свои не показываем
            node(9, repo="VkusnoffKz/bot", author=None, title=" ", minutes=5 * 60, checks=None),
            node(11, repo="VkusnoffKz/bot", author="user-b", title="Кнопка", minutes=0, checks="PENDING"),
        ))
        code, out = self.run_cli("prs", plan=plan)
        self.assertEqual(code, 0, out)
        self.assertEqual(out.splitlines(), [
            "VkusnoffKz/bot#11 · user-b · Кнопка · только что · проверки идут",
            f"{REPO}#5 · octocat · Фикс · 30 минут назад · проверки зелёные",
            "VkusnoffKz/bot#9 · ghost · без заголовка · 5 часов назад · проверок нет",
            "VkusnoffKz/site#7 · user-a · Новое меню · 3 дня назад · проверки красные · конфликт · черновик",
        ])
        user, orgs, query = self.calls()
        self.assertEqual((user, orgs), (["api", "user"], ["api", "user/orgs?per_page=100&page=1"]))
        self.assertEqual(query[:2], ["api", "graphql"])
        self.assertIn("q=is:pr is:open -author:ElvisIglikov user:ElvisIglikov org:VkusnoffKz", query)
        text = next(arg for arg in query if arg.startswith("query="))
        for field in ("repository", "number", "title", "author", "createdAt", "isDraft", "baseRefName",
                      "mergeable", "headRefOid", "statusCheckRollup"):
            self.assertIn(field, text)

    def test_prs_empty_and_json(self):
        code, out = self.run_cli("prs", plan=dict(ME, search=search(node(8, author="elvisiglikov"))))
        self.assertEqual((code, out), (0, "Запросов нет"))
        code, out = self.run_cli("prs", "--json", plan=dict(ME, search=search(node(5, draft=True))))
        self.assertEqual(code, 0, out)
        [item] = json.loads(out)
        self.assertEqual(list(item), ["repo", "number", "title", "author", "createdAt", "isDraft", "state",
                                      "baseRefName", "headRefName", "headRefOid", "mergeable", "checks", "url"])
        self.assertEqual((item["repo"], item["number"], item["isDraft"], item["checks"], item["headRefOid"]),
                         (REPO, 5, True, "SUCCESS", "abc123"))
        code, out = self.run_cli("prs", "--json", plan=dict(ME, search=search()))
        self.assertEqual((code, out), (0, "[]"))

    def test_prs_errors_in_words(self):
        cases = (
            ({}, False, "нет gh — поставь GitHub CLI"),
            ({"user": {"code": 4, "err": "To get started with GitHub CLI, please run:  gh auth login\n"}}, True,
             "gh не вошёл — gh auth login"),
            ({"user": {"code": 1, "err": "HTTP 401: Bad credentials (https://api.github.com/user)\n"}}, True,
             "gh не вошёл — gh auth login"),
            ({"user": {"code": 1, "err": "error connecting to api.github.com\n"}}, True, "сеть не отвечает"),
            ({"user": {}}, True, "gh не вошёл — gh auth login"),
            (dict(ME, search={"code": 1, "err": "gh: HTTP 403: Resource not accessible by integration\n"}), True,
             "gh отказал: gh: HTTP 403: Resource not accessible by integration"),
            (dict(ME, search="<html>не JSON"), True, "gh ответил непонятно — список запросов не получен"),
        )
        for plan, gh, line in cases:
            with self.subTest(line=line):
                code, out = self.run_cli("prs", plan=plan, gh=gh)
                self.assertEqual((code, out), (1, line))
                code, out = self.run_cli("prs", "--json", plan=plan, gh=gh)
                self.assertEqual((code, out, self.err), (1, "", line))

    def test_more_than_50_requests_and_100_organizations(self):
        first = [node(i, minutes=i) for i in range(1, 51)]
        plan = {"user": ME["user"], "orgs": [{"login": f"Org{i}"} for i in range(100)],
                "orgs2": [{"login": "LastOrg"}],
                "search": search(*first, total=51, more=True, cursor="next"),
                "searchnext": search(node(51, repo="LastOrg/site"), total=51)}
        code, out = self.run_cli("prs", "--json", plan=plan)
        self.assertEqual(code, 0, self.err)
        items = json.loads(out)
        self.assertEqual(len(items), 51)
        self.assertEqual(len({(i["repo"], i["number"]) for i in items}), 51)
        calls = self.calls()
        self.assertIn(["api", "user/orgs?per_page=100&page=2"], calls)
        self.assertIn("cursor=next", calls[-1])
        self.assertIn("org:LastOrg", next(a for a in calls[-1] if a.startswith("q=")))

    def test_malformed_and_partial_results_never_become_empty_success(self):
        bad_nodes = [None, {}, node(number=0), node(number=True), node(draft="false")]
        for key, value in (("title", []), ("author", {}), ("repository", None), ("commits", {}),
                           ("url", "https://github.com/Other/Repo/pull/5"),
                           ("url", "file:///tmp/x"), ("url", "https://github.com.evil/x")):
            bad_nodes.append(dict(node(), **{key: value}))
        answers = [None, [], {}, {"data": None}, {"data": {"search": {"nodes": []}}},
                   search(total=1), search(node(), total=1001), search(node(), more=True, total=2),
                   dict(search(), errors=[{"message": "denied"}])]
        answers += [search(item) for item in bad_nodes]
        for answer in answers:
            with self.subTest(answer=answer):
                code, out = self.run_cli("prs", "--json", plan=dict(ME, search=answer))
                self.assertEqual((code, out), (1, ""), self.err)
                self.assertTrue(self.err)
                self.assertNotIn("Запросов нет", self.err)

    def test_organization_error_or_bad_page_is_not_zero_requests(self):
        for orgs in ({"message": "denied"}, None, [{"login": ""}], ["bad"],
                     [{"login": "x"}, {"login": "X"}], {"code": 1, "err": "network is unreachable"}):
            with self.subTest(orgs=orgs):
                code, out = self.run_cli("prs", "--json", plan=dict(ME, orgs=orgs, search=search()))
                self.assertEqual((code, out), (1, ""))
                self.assertTrue(self.err)
        plan = dict(ME, orgs=[{"login": f"Org{i}"} for i in range(100)],
                    orgs2={"code": 1, "err": "error connecting to api.github.com"}, search=search())
        code, out = self.run_cli("prs", "--json", plan=plan)
        self.assertEqual((code, out), (1, ""))

    def test_later_page_failure_or_loop_never_returns_partial_array(self):
        first = search(node(1), total=2, more=True, cursor="next")
        for second in ({"code": 1, "err": "network is unreachable"},
                       dict(search(node(2), total=2), errors=[{"message": "partial"}]),
                       search(node(1), total=2), search(node(2), total=3),
                       search(more=True, total=2, cursor="next")):
            with self.subTest(second=second):
                code, out = self.run_cli("prs", "--json", plan=dict(ME, search=first, searchnext=second))
                self.assertEqual((code, out), (1, ""))
                self.assertTrue(self.err)

    def test_unknown_checks_remain_unknown(self):
        code, out = self.run_cli("prs", plan=dict(ME, search=search(node(checks="UNKNOWN", mergeable="UNKNOWN"))))
        self.assertEqual(code, 0, out)
        self.assertIn("проверки неизвестны", out)
        self.assertNotIn("проверки зелёные", out)

    def test_missing_commit_or_null_check_state_is_incomplete(self):
        for commits in ({"nodes": []}, {"nodes": [{"commit": {"statusCheckRollup": {"state": None}}}]}):
            code, out = self.run_cli("prs", "--json", plan=dict(ME, search=search(dict(node(), commits=commits))))
            self.assertEqual((code, out), (1, ""), "unknown checks must not become no checks")
            self.assertIn("неполный", self.err)

    def test_real_fake_process_timeout_includes_exit_and_kills_child(self):
        for close_pipes in (False, True):
            with self.subTest(close_pipes=close_pipes):
                started = time.monotonic()
                # 1,5 с, не 0,3: на занятом Маке подставной gh не успевал даже записать свой pid (#9472).
                with unittest.mock.patch.object(pimp, "GH_TIMEOUT_S", 1.5):
                    code, out = self.run_cli("prs", "--json", plan={
                        "user": {"sleep": True, "close_pipes": close_pipes}})
                self.assertEqual((code, out, self.err), (1, "", "сеть не отвечает"))
                self.assertLess(time.monotonic() - started, 8)
                pid = int((self.root / "gh.pid").read_text())
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)

    def test_large_response_drains_both_pipes(self):
        text = "я" * 200_000
        plan = dict(ME, search={"code": 0, "out": search(node(title=text)), "err": "x" * 200_000})
        code, out = self.run_cli("prs", "--json", plan=plan)
        self.assertEqual(code, 0, self.err)
        self.assertEqual(json.loads(out)[0]["title"], text)

    def test_write_subcommand_is_not_available(self):
        for op in ("merge", "close"):
            code, _ = self.run_cli("pr", f"{REPO}#5", op, "--yes")
            self.assertEqual(code, 1)
        self.assertEqual(self.calls(), [])

    def test_age_words(self):
        for minutes, words in ((0, "только что"), (1, "1 минуту назад"), (59, "59 минут назад"),
                               (60, "1 час назад"), (47 * 60, "47 часов назад"), (48 * 60, "2 дня назад")):
            self.assertEqual(pimp.pr_age(stamp(minutes)), words)
        self.assertEqual(pimp.pr_age("вчера"), "давность неизвестна")



if __name__ == "__main__":
    unittest.main()
