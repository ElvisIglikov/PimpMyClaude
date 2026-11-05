#!/usr/bin/env python3
"""Сторож размера правил 💤 SkilZZZ.

`AGENTS.md` читает каждый чат и субагент Claude и Codex, `ELVIS.md` — каждый чат
с Элвисом, `WORKFLOW.md` — каждый прогон.
С 14 августа по 18 сентября 2026 общий файл вырос с 3 до 44 КБ, и никто этого
не заметил: проверки размера не было. Теперь она стоит на коммите
(`hooks/pre-commit`) и запускается руками после правки правил.

С ключом `--project <корень>` проверяет файлы, которые читает каждый чат
любого проекта: паспорт `AGENTS.md` и `HANDOFF.md` (правило — в WORKFLOW.md).

Перебор — код возврата 1 и строка, которую агент обязан передать Элвису.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# КБ здесь — тысяча байт, как в Finder: Элвис сверяет глазами там.
LIMITS_KB = {"AGENTS.md": 12}
# Остальные файлы правил читаются по случаю, но складом тоже не становятся.
DEFAULT_LIMIT_KB = 24
# В проектах каждый чат читает паспорт и точку продолжения.
PROJECT_LIMITS_KB = {"AGENTS.md": 24, "HANDOFF.md": 30}  # правило — 12 КБ (#10747); сторож коммита — 30, пока HANDOFF проектов не ужаты
# На Windows git с core.autocrlf=true кладёт в рабочую копию CRLF, а в git
# хранит LF (17.10.2026: AGENTS.md в git 11 993 байт, на диске 12 084 — ложный
# красный). Там меряем, как в git; на Маке — размер файла, как и было.
CRLF_IS_LF = os.linesep == "\r\n"


def size_kb(path: Path) -> float:
    if CRLF_IS_LF:
        return len(path.read_bytes().replace(b"\r\n", b"\n")) / 1000
    return path.stat().st_size / 1000


def oversized(root: Path = ROOT) -> list[str]:
    problems = []
    # Файлы компьютера (`platform/mac.md`, `platform/windows.md`, 17.10.2026) читает каждый чат своей машины.
    # `skills/*/SKILL.md` грузится целиком при вызове навыка (31.10.2026, #11420).
    for path in sorted([*root.glob("*.md"), *root.glob("platform/*.md"), *root.glob("skills/*/SKILL.md")]):
        if path.is_symlink():
            continue
        limit = LIMITS_KB.get(path.name, DEFAULT_LIMIT_KB)
        kb = size_kb(path)
        if kb > limit:
            name = path.relative_to(root).as_posix()
            problems.append(f"⚠️ файл правил раздулся: {name} {kb:.1f} КБ при потолке {limit}")
    return problems


def oversized_project(root: Path) -> list[str]:
    problems = []
    for name, limit in PROJECT_LIMITS_KB.items():
        path = root / name
        if not path.is_file():
            continue
        kb = size_kb(path)
        if kb > limit:
            problems.append(f"⚠️ файл правил раздулся: {root.name}/{name} {kb:.1f} КБ при потолке {limit}")
    return problems


def main() -> int:
    # Консоль Windows (cp1251) не печатает «⚠️», и сторож падал вместо отчёта.
    reconfigure = getattr(sys.stdout, "reconfigure", None)
    if reconfigure is not None:
        reconfigure(encoding="utf-8", errors="replace")
    if len(sys.argv) == 3 and sys.argv[1] == "--project":
        problems = oversized_project(Path(sys.argv[2]).expanduser().resolve())
    else:
        problems = oversized()
    for line in problems:
        print(line)
    if problems:
        print("Скажи это Элвису и сократи файл: редкое — отдельным файлом рядом, старое из HANDOFF — в HANDOFF-archive.md (AGENTS.md «Потолок размера», WORKFLOW.md «Потолок»).")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
