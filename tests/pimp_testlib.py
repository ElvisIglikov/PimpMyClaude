"""Общее для тестов CLI «Пимп»: пути, загрузка tools/pimp.py модулем без запуска main и FakeApp —
приложение на минималках для канала pimp/.

Подключение из набора: sys.path.insert(0, str(Path(__file__).resolve().parent)); import pimp_testlib —
так набор идёт и через `unittest discover -s tests`, и путём к файлу (tests/pimp_cli_test.py).
"""

import importlib.util
import json
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools" / "pimp.py"
FIXTURES = ROOT / "tests" / "fixtures"
# MYCLAUDE_PIMP_TAKEN, когда в тесте есть FakeApp: он берёт запрос, как только его нитке дадут процессор, —
# молчать не может, окно — лишь потолок от зависания. С 2 с под нагрузкой CLI говорил «PMP не запущен»
# при живом FakeApp (#11441). Где приложения нет, тест ждёт молчания своим коротким окном.
APP_TAKEN_S = "30"


def load(name: str, path: Path):
    """Модуль из файла под своим именем: у каждого набора своя копия, подмены не текут между ними."""
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_pimp(name: str):
    return load(name, CLI)


def fixture_json(name: str):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class FakeApp(threading.Thread):
    """Приложение на минималках: взял запрос — ответил по образцу.

    `beats` — сколько раз перезаписать <id>.taken перед ответом с паузой
    `beat_s`: так приложение показывает, что открывает окна раскладки по одному
    (heartbeat WF41), и CLI обязан ждать дальше.
    `result` списком и `count` больше единицы — разговор на несколько запросов
    подряд: так идёт голосовая фраза (WF75), где шагов несколько, а первым
    уходит `projects`. Кончились образцы — отвечаем последним.
    """

    def __init__(self, directory: Path, result, taken: bool = True,
                 beats: int = 0, beat_s: float = 0.0, count: int = 1):
        super().__init__(daemon=True)
        self.dir = Path(directory)
        self.results = list(result) if isinstance(result, list) else [result]
        self.taken = taken
        self.beats = beats
        self.beat_s = beat_s
        self.count = count
        self.requests = []
        self.paths = []
        self.seen = set()
        self._halt = threading.Event()

    def run(self):
        # Живём до stop() или последнего ответа; срок — только от забытой нитки. 20 с от старта нитки
        # под нагрузкой кончались раньше, чем CLI успевал написать запрос (#11441).
        deadline = time.monotonic() + 120
        served = 0
        while time.monotonic() < deadline and not self._halt.is_set():
            for path in sorted(self.dir.glob("*.json")):
                if path.name.startswith(".") or path.name.endswith(".result.json"):
                    continue
                try:
                    text = path.read_text(encoding="utf-8")
                    request = json.loads(text)
                except (OSError, ValueError):
                    continue
                if request["id"] in self.seen:
                    continue
                self.seen.add(request["id"])
                self.requests.append(request)
                self.paths.append(path)
                mark = self.dir / f"{request['id']}.taken"
                if self.taken:
                    mark.write_text("", encoding="utf-8")
                for _ in range(self.beats):
                    if self._halt.wait(self.beat_s):
                        return
                    mark.write_text("", encoding="utf-8")   # окно открыто, живы
                answer = dict(self.results[min(served, len(self.results) - 1)])
                answer["id"] = request["id"]
                body = json.dumps(answer, ensure_ascii=False, separators=(",", ":")) + "\n"
                (self.dir / f"{request['id']}.result.json").write_text(body, encoding="utf-8")
                served += 1
                if served >= self.count:
                    return
            time.sleep(0.01)

    def stop(self):
        self._halt.set()
