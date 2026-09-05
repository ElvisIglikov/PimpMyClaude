// Загрузчик боевого claude-patch/inject.js в стаб DOM. Тестируется тот самый
// файл, который уезжает в Claude, — без копий, склеек и правок текста.
//
// Путь берётся из MYCLAUDE_INJECT, а по умолчанию — из репозитория. Переменная
// нужна проверке «сторожевой тест умеет краснеть»: копию портят в scratchpad и
// гоняют по ней, боевой файл при этом не трогают вовсе (план WF24, К8).
//
// Контракт (зафиксирован планом, решение 2):
//   loadInject({ html?, geometry?, storage? }) → { win, api, inner, counters }
// где win — окно-стаб, api — window.__myclaude, inner — объект из тестового
// люка inject.js, counters — счётчики подписок, наблюдателей и таймеров.
//
// Как гонять: `tools/test.sh --js` или `node --test` из корня репозитория.
// `node --test tests/` на node 26 НЕ работает (каталог он пытается загрузить
// как модуль) — путь к каталогу заменяется списком файлов: `node --test
// tests/*.test.mjs`.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import vm from "node:vm";
import { createDom } from "./dom.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const INJECT_PATH = process.env.MYCLAUDE_INJECT ?? path.join(ROOT, "claude-patch", "inject.js");
export const injectSource = () => readFileSync(INJECT_PATH, "utf8");

export const loadInject = ({
  html = null,
  geometry = {},
  storage = {},
  title = "",
  href = "https://claude.ai/epitaxy/local_test",
  hasFocus = true,
} = {}) => {
  const dom = createDom({
    title,
    href,
    hasFocus,
    local: storage.local ?? {},
    session: storage.session ?? {},
    viewport: geometry.viewport ?? { width: 1200, height: 800 },
  });
  // Разметка страницы: "composer" — стандартное поле ввода Claude Code, функция —
  // свой билдер (получает dom), ничего — пустая страница.
  let parts = null;
  if (html === "composer") parts = dom.composer({ top: geometry.composerTop ?? 620 });
  else if (typeof html === "function") parts = html(dom) ?? null;

  const win = dom.window;
  // Колбэк люка ТОЛЬКО запоминает объект: ни проверок, ни исключений — иначе
  // поломка теста выглядела бы поломкой inject.js (план WF24, К3).
  let inner = null;
  win.__myclaudeTest = value => { inner = value; };
  vm.createContext(win);

  let version = null;
  let error = null;
  try { version = vm.runInContext(injectSource(), win, { filename: INJECT_PATH }); }
  catch (thrown) { error = thrown; }

  return {
    win,
    dom,
    document: dom.document,
    parts,
    // api и inner — свойства-геттеры: после второго прогона инжекта (reload)
    // объект в окне новый, и снимок здесь врал бы.
    get api() { return win.__myclaude; },
    get inner() { return inner; },
    counters: dom.counters,
    version,
    error,
    failure: win.__myclaudeFailure ?? null,
    // Второй прогон в том же окне — ровно то, что делает лоадер v6 по mtime.
    reload: () => {
      inner = null;
      let again = null;
      try { again = vm.runInContext(injectSource(), win, { filename: INJECT_PATH }); }
      catch (thrown) { return { version: null, error: thrown, inner }; }
      return { version: again, error: null, inner, api: win.__myclaude };
    },
    // Выполнить код В КОНТЕКСТЕ страницы: значения из чужого реалма (Map,
    // Promise) страница проверяет через instanceof, и такие объекты обязаны
    // родиться там же, где живёт inject.js.
    run: code => vm.runInContext(code, win),
  };
};

// Объект, вернувшийся из vm, живёт в ЧУЖОМ реалме: его прототип не наш, и
// assert.deepEqual («strict» по умолчанию) на нём краснеет даже при одинаковом
// содержимом. Поэтому всё, что сравнивается целиком, прогоняем через plain().
export const plain = value => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));

// Короткая форма для наборов, которым нужны только чистые функции замыкания.
export const loadInner = (options = {}) => {
  const loaded = loadInject(options);
  if (!loaded.inner) throw new Error(`тестовый люк не сработал: ${loaded.error ?? "объекта нет"}`);
  return loaded;
};
