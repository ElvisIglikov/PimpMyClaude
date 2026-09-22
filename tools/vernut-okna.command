#!/bin/bash
# Двойной клик ПОСЛЕ обновления Claude и «Поставить» в Пимпе.
# Возвращает шесть окон на Одиссей ровно туда, где они стояли 22.09.2026 в 00:20.
# Снимок — PimpMyClaude/docs/okna-22.09.2026.json, он же источник правды.
# Открывает ПОСЛЕДНИЙ чат каждого проекта: именно он в каждом окне и стоял.
PIMP="/Users/elvis/_ElvisProjects/PimpMyClaude/tools/pimp.py"
SNAP="/Users/elvis/_ElvisProjects/PimpMyClaude/docs/okna-22.09.2026.json"

echo "🪟 Возвращаю окна на места…"
if ! pgrep -f "PimpMyClaude.app/Contents/MacOS" >/dev/null; then
    echo "⛔ Пимп не запущен — открываю."
    open -a PimpMyClaude
    sleep 4
fi
if ! pgrep -f "Claude.app/Contents/MacOS" >/dev/null; then
    echo "⛔ Claude не запущен — открываю."
    open -a Claude
    sleep 6
fi

python3 - "$PIMP" "$SNAP" <<'PY'
import json, subprocess, sys, time
pimp, snap = sys.argv[1], sys.argv[2]
okna = json.load(open(snap, encoding="utf-8"))["okna"]
for o in okna:
    proekt, (x, y, w, h) = o["proekt"], o["ramka"]
    print(f'  {o["nomer"]}. {proekt} → {x},{y}')
    subprocess.run(["python3", pimp, "open", proekt, "--at", f"{x},{y}", "--last"],
                   capture_output=True, text=True)
    time.sleep(3)
    # Размер сперва, потом позиция: Electron зажимает ширину своим минимумом и
    # после ресайза окно уезжает — позицию ставим последней (проверено 22.09).
    # Только что открытое окно — переднее, значит window 1 у процесса Claude.
    for prop, val in (("size", f"{{{w}, {h}}}"), ("position", f"{{{x}, {y}}}")):
        subprocess.run(["osascript", "-e",
            f'tell application "System Events" to tell process "Claude" to set {prop} of window 1 to {val}'],
            capture_output=True, text=True)
    time.sleep(1)
print("✅ Готово. Что не встало — скажи чату Пимпа: «Пимп, расставь».")
PY
read -r -p "Enter — закрыть."
