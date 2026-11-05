#!/usr/bin/env python3
"""Сторож контекста Claude Code (#10747, 23.10.2026): подписку жгут чаты на 200K+.

Хук на три события, вход — JSON на stdin, событие — `hook_event_name`:

* SessionStart — HANDOFF.md в корне проекта больше 12 КБ или паспорт
  (AGENTS.md / CLAUDE.md) больше 24 КБ: одна строка модели «ужми до работы».
* UserPromptSubmit, главный чат — контекст последнего хода от 125K (#11404): строка
  «смена близко, работу не останавливай, поручение — сразу»; от 140K (всегда, слово Элвиса 31.10.2026) —
  «доведи шаг, HANDOFF, коммит, push, готов к смене»; на итоге агента
  (`<task-notification>`) — «доведи волну, новую не запускай». Не блокирует
  (блок ломает доставку писем Рика и итоги агентов — критик WF1). Чат Рика
  (Rick и его копии Rick-*) пропускаем: его ведёт сам Рик.
* PreToolUse:
  - помощник (во входе есть `agent_id`): контекст ≥ max(200K, первый ход
    + 150K) — запрет чтения и запуска агентов; ещё на 30K выше — запрет всего,
    кроме Write/Edit (сдать итог и дописать начатую правку);
  - Bash помощника с timeout > 4 мин без фона: в bypass — timeout срезаем до
    4 мин (кеш помощника живёт 5 мин; не успеет — Claude Code сам уводит
    команду в фон), в других режимах — запрет;
  - Agent в любом чате: без effort — запрет; general-purpose или без типа
    без метки «[полный помощник]» — запрет, если стоит tonkiy. fork не трогаем;
  - Workflow: в тексте сценария agent( без agentType и без метки — запрет,
    если стоит tonkiy (продолжение прогона и сохранённый сценарий не трогаем).

Любая беда — exit 0 без вывода: сторож не должен ломать работу. Сработал —
строка в ~/.claude/kontekst_storozh.log для замера «после».

`kontekst_storozh.py install [--dry-run]` — слить хуки и autoCompactWindow в
~/.claude/settings.json, не трогая чужие ключи и хуки. Повторный запуск — тот же файл.
На Windows ещё enableArtifact: false и disableClaudeAiConnectors: true, если ключей
нет: Artifact (≈ 10K) и коннекторы claude.ai (≈ 2,3K) едут в каждом запросе, вызовов ~0.

Порог для опытов: KONTEKST_STOROZH_TEST_K=4 — база 4K вместо 200K, запасы
помощника (150K и 30K) уменьшаются в той же доле.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
import time
from pathlib import Path

from rules_size_guard import PROJECT_LIMITS_KB

HANDOFF_MAX_KB = 12  # правило (#10747); сторож коммита держит 30 — rules_size_guard.PROJECT_LIMITS_KB
PASSPORT_MAX_KB = PROJECT_LIMITS_KB["AGENTS.md"]
COMPACT_WINDOW = 283000  # окно сжатия: сжатие ≈ 250K (замер C2, 1f)
BASH_MAX_MS = 240_000
MAIN_K = 125_000  # предупреждение главному чату: работа и помощники не стоят (#11404, «никаких… простоев по 55 минут»)
HARD_K = 140_000  # смена главного чата — всегда 140K (слово Элвиса 31.10.2026 16:01, #11404: «нужно оставить 140 000 всегда»)
MARK_FULL = "[полный помощник]"
READ_TOOLS = {"Read", "Grep", "Glob", "WebFetch", "WebSearch", "Agent", "Task", "Workflow"}
WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit", "StructuredOutput"}  # StructuredOutput — итог агента Workflow
EVENTS = ("SessionStart", "UserPromptSubmit", "PreToolUse")
RICK_CWD = re.compile(r"[/\\]_Projects[/\\]Rick(-[^/\\]*)?[/\\]?$")  # Мак и ноутбук Оли
RICK_DIR = re.compile(r"-Projects-Rick(-[^/\\]*)?$")


def limits() -> tuple[int, int, int]:
    """База главного чата и помощника, запас помощника над первым ходом, шаг до запрета всего."""
    base, margin, step = 200_000, 150_000, 30_000
    test = os.environ.get("KONTEKST_STOROZH_TEST_K", "").strip()
    if test:
        share = float(test) * 1000 / base
        base, margin, step = int(base * share), int(margin * share), int(step * share)
    return base, margin, step


def usage_tokens(line: str, main_only: bool) -> int | None:
    """Контекст хода из строки транскрипта: вход + чтение и запись кеша; иначе None."""
    if '"usage"' not in line:
        return None
    try:
        rec = json.loads(line)
    except ValueError:
        return None
    msg = rec.get("message") if isinstance(rec, dict) else None
    if not isinstance(msg, dict) or rec.get("type") != "assistant":
        return None
    if main_only and rec.get("isSidechain"):
        return None
    use = msg.get("usage")
    if not isinstance(use, dict):
        return None
    total = sum(int(use.get(k) or 0) for k in
                ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    return total or None


def last_context(path: str | Path, main_only: bool = True) -> int | None:
    """Контекст последнего хода: читаем хвост файла, как Rick/tools/term_ctx.py (файл бывает 300 МБ)."""
    try:
        with open(path, "rb") as fh:
            fh.seek(0, 2)
            size = fh.tell()
            for tail in (2_000_000, 16_000_000):
                fh.seek(max(0, size - tail))
                lines = fh.read().decode("utf-8", "ignore").splitlines()
                for line in reversed(lines):
                    if '"compact_boundary"' in line:
                        return None  # после сжатия ходов ещё нет — прежний размер уже не тот
                    tokens = usage_tokens(line, main_only)
                    if tokens:
                        return tokens
                if tail >= size:
                    break
    except OSError:
        return None
    return None


def first_context(path: str | Path) -> int | None:
    """Контекст первого хода помощника: голова файла (у fork он сразу большой)."""
    try:
        with open(path, "rb") as fh:
            for raw in fh:
                tokens = usage_tokens(raw.decode("utf-8", "ignore"), main_only=False)
                if tokens:
                    return tokens
    except OSError:
        return None
    return None


def agent_transcript(transcript_path: str, agent_id: str) -> Path | None:
    """Транскрипт помощника: <чат>/subagents/agent-<id>.jsonl, у Workflow — subagents/workflows/*/."""
    if not transcript_path or not agent_id or "/" in agent_id:
        return None
    chat = Path(transcript_path)
    folder = chat.with_suffix("") / "subagents"
    direct = folder / f"agent-{agent_id}.jsonl"
    if direct.is_file():
        return direct
    found = sorted(folder.glob(f"workflows/*/agent-{agent_id}.jsonl"))
    return found[0] if found else None


def is_rick(data: dict) -> bool:
    cwd = str(data.get("cwd") or "")
    folder = Path(str(data.get("transcript_path") or "")).parent.name
    return bool(RICK_CWD.search(cwd) or RICK_DIR.search(folder))


def kb(path: Path) -> float:
    return len(path.read_bytes().replace(b"\r\n", b"\n")) / 1000  # без CR, как git и rules_size_guard.py


def on_session_start(data: dict) -> tuple[dict | None, str]:
    root = Path(str(data.get("cwd") or ""))
    if not root.is_dir():
        return None, ""
    found, seen = [], set()
    for name, top in (("HANDOFF.md", HANDOFF_MAX_KB), ("AGENTS.md", PASSPORT_MAX_KB), ("CLAUDE.md", PASSPORT_MAX_KB)):
        path = root / name
        if not path.is_file():
            continue
        real = os.path.realpath(path)  # CLAUDE.md — часто ссылка на AGENTS.md
        if real in seen:
            continue
        seen.add(real)
        size = kb(path)
        if size > top:
            found.append(f"{name} {size:.1f} КБ > {top} КБ")
    if not found:
        return None, ""
    text = (f"Сторож контекста: {', '.join(found)} — ужми по WORKFLOW.md "
            "(старое — дословно в HANDOFF-archive.md) до работы.")
    return {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}, "; ".join(found)


def on_prompt(data: dict) -> tuple[dict | None, str]:
    if data.get("agent_id") or is_rick(data):
        return None, ""
    base, _, _ = limits()
    tokens = last_context(str(data.get("transcript_path") or ""))
    if not tokens or tokens < min(base, MAIN_K):
        return None, ""
    k = tokens // 1000
    if tokens < HARD_K:
        text = (f"Сторож: контекст {k}K — смена близко, но работу и помощников не останавливай: новое поручение "
                f"делай сразу, HANDOFF держи свежим на границе шага; смена — от {HARD_K // 1000}K.")
    elif str(data.get("prompt") or "").lstrip().startswith("<task-notification>"):
        text = (f"Сторож: контекст {k}K — доведи волну, новую не запускай; потом запиши HANDOFF, "
                "коммит и push, скажи «готов к смене»; новый чат стартует ≤ 60K.")
    else:
        text = (f"Сторож: контекст {k}K — доведи шаг, запиши HANDOFF, коммит и push, скажи «готов к смене»; "
                "новый чат стартует ≤ 60K.")
    return {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": text}}, f"{k}K"


def deny(reason: str) -> dict:
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


def tonkiy_installed() -> bool:
    return (Path.home() / ".claude" / "agents" / "tonkiy.md").exists()


def check_agent_call(tool_input: dict) -> str:
    """Причина запрета запуска Agent или пусто."""
    kind = str(tool_input.get("subagent_type") or "").strip()
    if kind == "fork":
        return ""
    if not str(tool_input.get("effort") or "").strip():
        return "Сторож: эффорт явно (MODELS.md) — допиши effort в вызов Agent."
    if kind in ("", "general-purpose") and MARK_FULL not in str(tool_input.get("prompt") or "") \
            and tonkiy_installed():
        return (f"Сторож: бери subagent_type tonkiy; браузер, MCP, веб, скилл — допиши в prompt {MARK_FULL}.")
    return ""


def check_workflow_call(tool_input: dict) -> str:
    """Причина запрета запуска Workflow или пусто: агенты сценария без agentType."""
    if tool_input.get("resumeFromRunId") or str(tool_input.get("name") or "").strip() or not tonkiy_installed():
        return ""  # продолжение прогона или сохранённый сценарий — текста нет
    text = tool_input.get("script")
    if not isinstance(text, str) or not text:
        path = str(tool_input.get("scriptPath") or "")
        if not path:
            return ""
        try:
            text = Path(path).read_text(encoding="utf-8")
        except (OSError, ValueError):
            return ""
    if "agent(" in text and "agentType" not in text and MARK_FULL not in text:
        return ("Сторож: агентам Workflow — agentType: 'tonkiy' (MODELS.md, «Тонкий помощник»: агент Workflow "
                "по умолчанию — 57 тыс. токенов старта, tonkiy — 12 тыс.); агенту с браузером, вебом, скиллом или MCP — agentType: 'general-purpose' "
                f"и «{MARK_FULL}» в prompt.")
    return ""


def check_helper(data: dict, tool: str) -> tuple[str, str]:
    """Причина запрета помощнику по его контексту и метка для журнала."""
    path = agent_transcript(str(data.get("transcript_path") or ""), str(data.get("agent_id") or ""))
    if path is None:
        return "", ""
    tokens = last_context(path, main_only=False)
    if not tokens:
        return "", ""
    base, margin, step = limits()
    first = first_context(path) or 0
    wall = max(base, first + margin)
    k = tokens // 1000
    if tokens >= wall + step and tool not in WRITE_TOOLS:
        return (f"Сторож: контекст {k}K — инструменты закрыты; сдай итог (что сделано и проверено, что осталось, "
                "пути); остаток — новому помощнику."), f"{k}K всё"
    if tokens >= wall and tool in READ_TOOLS:
        return f"Сторож: контекст {k}K — сдай итог, остаток — новому помощнику.", f"{k}K чтение"
    return "", ""


def on_tool(data: dict) -> tuple[dict | None, str]:
    tool = str(data.get("tool_name") or "")
    tool_input = data.get("tool_input") if isinstance(data.get("tool_input"), dict) else {}
    if data.get("agent_id"):
        reason, note = check_helper(data, tool)
        if reason:
            return deny(reason), f"помощник {note} {tool}"
        # Кеш помощника живёт 5 мин: ход дольше 4 мин читает весь контекст заново. В bypass срезаем timeout —
        # Claude Code 2.1.295 сам уводит команду в фон по его концу; в других режимах allow обошёл бы спрос.
        if tool == "Bash" and not tool_input.get("run_in_background") \
                and float(tool_input.get("timeout") or 0) > BASH_MAX_MS:
            if data.get("permission_mode") == "bypassPermissions":
                return {"hookSpecificOutput": {
                    "hookEventName": "PreToolUse", "permissionDecision": "allow",
                    "updatedInput": {**tool_input, "timeout": BASH_MAX_MS},
                    "additionalContext": "Сторож: timeout срезан до 4 мин (кеш помощника живёт 5 мин); не успеет — "
                                         "Claude Code сам уведёт команду в фон: жди её конца петлёй ≤ 230 с "
                                         "(until grep -q … ; do sleep 5; done), без sleep N первой командой "
                                         "и без Monitor."}}, "помощник Bash > 4 мин → 4 мин"
            return deny("Сторож: фоном (run_in_background), жди кусками ≤ 4 мин."), "помощник Bash > 4 мин"
    if tool in ("Agent", "Task"):
        reason = check_agent_call(tool_input)
        if reason:
            return deny(reason), f"Agent {tool_input.get('subagent_type') or '-'}"
    if tool == "Workflow":
        reason = check_workflow_call(tool_input)
        if reason:
            return deny(reason), "Workflow без agentType"
    return None, ""


def log(event: str, note: str, data: dict) -> None:
    try:
        line = "\t".join((time.strftime("%Y-%m-%d %H:%M:%S"), event, note,
                          Path(str(data.get("cwd") or "")).name, str(data.get("session_id") or "")[:8]))
        with open(Path.home() / ".claude" / "kontekst_storozh.log", "a", encoding="utf-8") as fh:
            fh.write(line.replace("\n", " ") + "\n")
    except OSError:
        pass


def hook() -> None:
    data = json.loads(sys.stdin.buffer.read().decode("utf-8", "ignore") or "{}")
    if not isinstance(data, dict):
        return
    event = data.get("hook_event_name")
    handler = {"SessionStart": on_session_start, "UserPromptSubmit": on_prompt, "PreToolUse": on_tool}.get(event)
    if handler is None:
        return
    out, note = handler(data)
    if out:
        sys.stdout.write(json.dumps(out))
        sys.stdout.flush()
        log(str(event), note, data)


# --- установка -----------------------------------------------------------------------------------

def is_ours(command: object) -> bool:
    text = str(command.get("command") or "") if isinstance(command, dict) else ""
    try:
        tokens = shlex.split(text)
    except ValueError:
        tokens = text.split()
    return any(Path(token).name == "kontekst_storozh.py" for token in tokens)


def merge(settings: dict, script: Path) -> tuple[dict, list[str]]:
    """Наши хуки — в конец каждого события, чужие группы и ключи на месте; окно сжатия — если своего нет."""
    notes: list[str] = []
    hooks = settings.get("hooks")
    if hooks is None:
        hooks = {}
    if not isinstance(hooks, dict):
        raise ValueError("hooks в settings.json не словарь — не трогаю")
    ours = {"type": "command", "command": f"python3 {shlex.quote(script.as_posix())}"}
    for event in EVENTS:
        was = hooks.get(event, [])
        if not isinstance(was, list):
            raise ValueError(f"hooks.{event} не список — не трогаю")
        kept = []
        for group in was:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                kept.append(group)
                continue
            rest = [c for c in group["hooks"] if not is_ours(c)]
            if rest:
                kept.append({**group, "hooks": rest})
        hooks[event] = kept + [{"hooks": [ours]}]
    settings["hooks"] = hooks
    window = settings.get("autoCompactWindow")
    if window is None:
        settings["autoCompactWindow"] = COMPACT_WINDOW
    elif window != COMPACT_WINDOW:
        notes.append(f"autoCompactWindow уже {window} — своё значение не трогаю (наше {COMPACT_WINDOW}).")
    if sys.platform == "win32":  # Artifact и коннекторы claude.ai едут в каждом запросе, вызовов почти нет
        for key, value in (("enableArtifact", False), ("disableClaudeAiConnectors", True)):
            if key not in settings:
                settings[key] = value
            elif settings[key] != value:
                notes.append(f"{key} уже {json.dumps(settings[key])} — своё значение не трогаю (наше {json.dumps(value)}).")
    return settings, notes


def install(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    path = Path.home() / ".claude" / "settings.json"
    script = Path(__file__).resolve()
    try:
        raw = path.read_text(encoding="utf-8-sig") if path.exists() else ""
        settings = json.loads(raw) if raw.strip() else {}
        if not isinstance(settings, dict):
            raise ValueError("settings.json не объект")
        settings, notes = merge(settings, script)
    except ValueError as error:
        print(f"⛔ Сторож контекста не поставлен: {error}")
        return 1
    text = json.dumps(settings, ensure_ascii=False, indent=2) + "\n"
    for note in notes:
        print(f"⚠️ {note}")
    if dry:
        print(text, end="")
        return 0
    if text == raw:
        print("✅ Сторож контекста уже стоит.")
        return 0
    tmp = path.with_name(f"settings.{os.getpid()}.tmp")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(text, encoding="utf-8")
        tmp.replace(path)
    except OSError as error:
        print(f"⛔ Не смог записать {path}: {error}")
        return 1
    print("✅ Сторож контекста поставлен: хуки SessionStart, UserPromptSubmit, PreToolUse и окно сжатия.")
    return 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["install"]:
        raise SystemExit(install(sys.argv[2:]))
    try:
        hook()
    except Exception:  # сторож не ломает работу: любая беда — молча мимо
        pass
    raise SystemExit(0)
