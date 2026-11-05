// MyClaude — ручка высоты поля ввода Claude Desktop и команды снаружи.
//
// Файл кладётся в ~/Library/Application Support/MyClaude/inject.js; лоадер v8
// (LOADER в patch-claude.mjs, боевой — app/Sources/Patcher/Loader.swift) выполняет его
// через executeJavaScript при dom-ready и заново при каждом изменении файла — только
// в страницах claude.ai и их about:blank-попапах. Отсюда три требования:
//   1. никаких модулей и импортов — это обычный скрипт в контексте страницы;
//   2. идемпотентность: скрипт сам снимает прошлый экземпляр (window.__myclaude.dispose);
//   3. попап без разметки Claude (about:blank до въезда чата) — тихо ждать (stopWatching).
//
// Что делает сейчас: ручка высоты поля ввода и ступени поля (из донора ElvisOS,
// его пояснения к числам сохранены), слои чата — цвет, шрифт, размер и
// оформление (раздел 2а, ключ `id:<id чата>`, имя — тень), ряд номеров
// воркфлоу в рамке поля и его карточка (2б), живые цвета (2в), «Обкэшить» и
// перенос чата (12), Workflow (12а), новое окно и вынос чата (12б), «кто этот
// чат» для приложения (12в), кнопки и нажималки ответа, микрофон, лимиты и
// прочее по разделам ниже. Команды приходят событием window
// "myclaude-command"; их поля, адресация и status() — в docs/CONTRACTS.md.

"use strict";
(() => {
  const VERSION = "wf304-page-8";
  // Реестры файлов-разделов (WF248 П4): раздел регистрирует своё у себя, в конце файла, а не в общем хвосте.
  //   HATCH — тестовый люк: объект только под tests/load.mjs, в бою null; имя без читателя в tests/ не кладут.
  //   statusParts — поля status(): statusPart("ключ", () => значение), порядок — STATUS_ORDER раздела 17.
  //   lateRules — CSS новых фич: ложится после RULES раздела 4 (старые правила там: порядок = каскад).
  const HATCH = typeof globalThis.__myclaudeTest === "function" ? {} : null;
  const statusParts = new Map();
  const statusPart = (key, get) => {
    if (statusParts.has(key)) throw new Error(`status(): поле «${key}» уже зарегистрировано`);
    statusParts.set(key, get);
  };
  const lateRules = [];

