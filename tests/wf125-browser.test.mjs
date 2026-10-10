// Необязательный стенд в настоящем Chromium (образец — wf120-browser.test.mjs):
// стаб DOM не исполняет ни `:has()`, ни `@container`, а WF125 чинит именно их.
// Страница — три скелета панели чата по живому замеру Claude 2.19675.0
// (06.10.2026): попап, главное окно до WF82 и новое главное окно с обёрткой
// `div.contents`; таблицы — готовый текст layoutCss() и themeCss().
// Второй тест — сама страница в Chromium: слова блока «Скажи — и сделаю» с новой
// строки (#8687) и снятие слова шагами назад через границу строки.
// Без Claude, сети и профиля. Переменные среды те же, что у стенда WF120:
// PIMP_WF120_PLAYWRIGHT=/path/to/playwright/index.mjs
// PIMP_WF120_CHROMIUM=/path/to/chrome-headless-shell node --test tests/wf125-browser.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { injectSource, loadInner } from "./load.mjs";

const enabled = Boolean(process.env.PIMP_WF120_PLAYWRIGHT && process.env.PIMP_WF120_CHROMIUM);
const { inner } = loadInner({ title: "Trelvis" });
const theme = {
  id: "рик", name: "Рик", type: "dark",
  palette: { accent: "#b06cff", background: "#381655", foreground: "#f3e9ff", sidebar: "#2a1040", panel: "#48246a", muted: "#b9a3d0" },
};
const BACKGROUND = "rgb(56, 22, 85)";
const CLEAR = "rgba(0, 0, 0, 0)";

// Колонка с шапкой, телом ленты и докой; deep — тело в двух `div.contents` (с WF82).
const column = deep => {
  // Липкая полоса под лентой и дока несут один класс подложки Claude (замер 07.10, #8880).
  const body = '<div class="epitaxy-chat-panel-body"><div data-testid="epitaxy-virtual-transcript">лента</div><div class="strip sticky bottom-0 bg-[var(--epitaxy-transcript-surface,var(--cds-surface-1))]"></div></div>';
  const dock = '<div data-epitaxy-chat-column><div class="group/approval-dock bg-[var(--epitaxy-transcript-surface,var(--cds-surface-1))]" data-band-enter>поле</div></div>';
  const inside = deep ? `<div class="contents"><div class="contents">${body}</div>${dock}</div>` : `<div class="contents">${body}${dock}</div>`;
  return `<div class="column"><div class="epitaxy-titlebar">шапка</div><div class="contents"></div>${inside}</div>`;
};
const panel = (id, wrapped, deep) => `<div class="tile" data-tile><div class="tiles-shell"><div><div>
  <div class="epitaxy-chat-panel" id="${id}"><div class="rounded-card"></div>${wrapped ? `<div class="contents">${column(deep)}</div>` : column(deep)}</div>
</div></div></div></div>`;
// Что под лентой: в главном окне — основа темы (main.dframe-content), в попапе —
// непрозрачный .epitaxy-root поверх div.dframe-content.
const main = (id, wrapped, deep) => `<div class="dframe-root"><main class="dframe-content"><div class="dframe-content-inner"><div class="dframe-pane-host"><div class="dframe-pane dframe-pane-primary"><div class="dframe-pane-scroller"><div class="epitaxy-root">${panel(id, wrapped, deep)}</div></div></div></div></div></main></div>`;
const popup = (id, deep) => `<div class="dframe-root"><div class="dframe-content"><div class="epitaxy-root solid">${panel(id, false, deep)}</div></div></div>`;

const html = `<!doctype html>
<style>
  .contents { display: contents; }
  .tile { container-name: tile-slot; container-type: inline-size; width: 900px; height: 300px; }
  .epitaxy-chat-panel { position: relative; height: 300px; }
  .rounded-card { position: absolute; inset: 0; }
  .column { display: flex; flex-direction: column; height: 100%; }
  /* Подложка доки, как её красит Claude 2.19675.0, и фон попапа. */
  [class*="--epitaxy-transcript-surface"] { background-color: var(--epitaxy-transcript-surface, var(--cds-surface-1)); }
  .strip { height: 10px; }
  .epitaxy-root.solid { background: var(--cds-surface-1); }
</style>
<style id="theme"></style>
<style id="layout"></style>
${popup("popup", true)}
${main("main-old", false, false)}
${main("main-prev", false, true)}
${main("main-new", true, true)}`;

test("WF125 Chromium: широкий вид на трёх формах панели, дока цветом основы только в узком главном окне", { skip: !enabled, timeout: 30000 }, async () => {
  const { chromium } = await import(pathToFileURL(process.env.PIMP_WF120_PLAYWRIGHT));
  const scratch = mkdtempSync(resolve("audit/wf125-browser-"));
  let context;
  const previousTmp = process.env.TMPDIR;
  process.env.TMPDIR = scratch;
  try {
    context = await chromium.launchPersistentContext(resolve(scratch, "profile"), {
      executablePath: process.env.PIMP_WF120_CHROMIUM, headless: true,
      downloadsPath: scratch, env: { ...process.env, TMPDIR: scratch },
      args: ["--disable-breakpad", "--disable-crash-reporter"],
    });
    await context.route("**/*", route => route.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: html }));
    const page = context.pages()[0];
    await page.goto("https://claude.ai/epitaxy/local_wf125_fixture");
    const sheets = async (layout, themed) => page.evaluate(([layout, themed]) => {
      document.getElementById("layout").textContent = layout;
      document.getElementById("theme").textContent = themed;
    }, [layout, themed]);
    const width = value => page.evaluate(value => { for (const tile of document.querySelectorAll("[data-tile]")) tile.style.width = `${value}px`; }, value);
    const read = () => page.evaluate(() => Object.fromEntries([...document.querySelectorAll(".epitaxy-chat-panel")].map(panel => {
      const style = node => getComputedStyle(node);
      const title = panel.querySelector(".epitaxy-titlebar");
      const dock = panel.querySelector('[class~="group/approval-dock"]');
      return [panel.id, {
        wide: style(panel).getPropertyValue("--myclaude-wide").trim(),
        display: style(title.parentElement).display,
        title: style(title).gridColumnStart,
        body: style(panel.querySelector(".epitaxy-chat-panel-body")).gridColumnStart,
        dock: style(dock).gridColumnStart,
        dockBackground: style(dock).backgroundColor,
        stripBackground: style(panel.querySelector(".strip")).backgroundColor,
        line: style(title).boxShadow !== "none",
      }];
    })));
    const IDS = ["popup", "main-old", "main-prev", "main-new"];

    // Все правила приняты браузером: вложенный :has() молча выбросил бы правило флага.
    await sheets(inner.layoutCss(), inner.themeCss(theme));
    const wide = await read();
    for (const id of IDS) {
      assert.deepEqual([wide[id].wide, wide[id].display, wide[id].title, wide[id].body, wide[id].dock, wide[id].line],
        ["1", "grid", "2", "1", "2", true], `широкий вид не включился: ${id}`);
      assert.equal(wide[id].dockBackground, CLEAR, `в широком виде дока прозрачна: ${id}`);
    }

    // Шапка слева — по атрибуту панели: правило не зависит от числа обёрток.
    await page.evaluate(() => { for (const panel of document.querySelectorAll(".epitaxy-chat-panel")) panel.setAttribute("data-myclaude-title", "left"); });
    const left = await read();
    for (const id of IDS) assert.deepEqual([left[id].title, left[id].line], ["1", false], `шапка слева: ${id}`);
    await page.evaluate(() => { for (const panel of document.querySelectorAll(".epitaxy-chat-panel")) panel.removeAttribute("data-myclaude-title"); });

    // Узкая плитка — раскладка Claude; дока главного окна — цветом основы, попапа — как была.
    await width(500);
    const narrow = await read();
    const surface = await page.evaluate(() => getComputedStyle(document.querySelector(".epitaxy-root.solid")).backgroundColor);
    assert.notEqual(surface, BACKGROUND, "стенд: surface-1 обязан отличаться от основы");
    for (const id of IDS) {
      assert.deepEqual([narrow[id].wide, narrow[id].display], ["", "flex"], `узкий вид тронут: ${id}`);
      assert.equal(narrow[id].dockBackground, id === "popup" ? surface : BACKGROUND, `цвет доки в узком виде: ${id}`);
      assert.equal(narrow[id].stripBackground, narrow[id].dockBackground, `полоса под лентой — того же цвета, что дока (#8880): ${id}`);
    }

    // Тема не выбрана — правила доки нет, подложка Claude остаётся.
    await sheets(inner.layoutCss(), ":root { --cds-surface-1: rgb(64, 31, 93); }");
    const plain = await read();
    for (const id of IDS) assert.equal(plain[id].dockBackground, "rgb(64, 31, 93)", `без темы дока — как у Claude: ${id}`);
  } finally {
    await context?.close();
    if (previousTmp === undefined) delete process.env.TMPDIR; else process.env.TMPDIR = previousTmp;
    rmSync(scratch, { recursive: true, force: true });
  }
});

// #8687: стаб DOM границу строки не моделирует (Selection.modify там — минус один знак).
// Поле стенда — простой contenteditable, не ProseMirror Claude: живую проверку делает гейт.
const sayHtml = `<!doctype html>
<style>.epitaxy-composer-width{position:fixed;bottom:10px;left:100px;width:900px;height:200px}.epitaxy-prompt{height:160px}.editor-root{height:100px;overflow:auto}.ProseMirror{height:90px;width:850px;white-space:pre-wrap}button{min-width:24px;min-height:24px}</style>
<div data-testid="epitaxy-virtual-transcript"><div data-testid="transcript-row" data-perf-row="assistant_text"><div class="contents">
  <h3>❗ Скажи — и сделаю ❗</h3>
  <p><strong id="clean">«чисти»</strong> — склею повторы</p>
  <p><strong id="go">«поехали 👍»</strong> — план следующей пачки</p>
</div></div></div>
<div class="epitaxy-composer-width"><div class="epitaxy-prompt" data-cds="ChatComposer"><div class="editor-root"><div class="ProseMirror" contenteditable="true"></div></div></div><div class="model-row"><button data-testid="code-prompt-send">Send</button></div></div>`;

test("WF125 Chromium: слова «Скажи — и сделаю» — с новой строки, снятие слова не трогает свой текст", { skip: !enabled, timeout: 30000 }, async () => {
  const { chromium } = await import(pathToFileURL(process.env.PIMP_WF120_PLAYWRIGHT));
  const scratch = mkdtempSync(resolve("audit/wf125-browser-"));
  let context;
  const previousTmp = process.env.TMPDIR;
  process.env.TMPDIR = scratch;
  try {
    context = await chromium.launchPersistentContext(resolve(scratch, "profile"), {
      executablePath: process.env.PIMP_WF120_CHROMIUM, headless: true,
      downloadsPath: scratch, env: { ...process.env, TMPDIR: scratch },
      args: ["--disable-breakpad", "--disable-crash-reporter"],
    });
    await context.route("**/*", route => route.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: sayHtml }));
    const page = context.pages()[0];
    await page.goto("https://claude.ai/epitaxy/local_wf125_say");
    await page.evaluate(() => { window.__myclaudeTest = inner => { window.testInner = inner; }; });
    assert.equal(await page.evaluate(injectSource()), "wf125-page-5");
    // Кнопки размечает проход страницы; стенд зовёт его сам, не дожидаясь правки ленты.
    await page.evaluate(() => window.testInner.sayTick(Date.now()));
    // Строки поля: пустые (между блоками innerText даёт лишний перенос) не в счёт.
    const lines = () => page.evaluate(() => document.querySelector(".ProseMirror").innerText.split("\n").map(line => line.trim()).filter(Boolean));
    await page.waitForSelector("#go[data-myclaude-say]");
    await page.click("#clean");
    assert.deepEqual(await lines(), ["чисти"]);
    await page.click("#go");
    assert.deepEqual(await lines(), ["чисти", "поехали 👍"], "два слова — две строки, не одна фраза");
    await page.click("#clean");
    assert.deepEqual(await lines(), ["поехали 👍"]);
    await page.click("#go");
    assert.deepEqual(await lines(), []);

    // Свой текст в поле: слова дописываются хвостом с новой строки, снятие — шагами назад.
    await page.locator(".ProseMirror").focus();
    await page.keyboard.type("мой текст 🙂");
    await page.click("#clean");
    await page.click("#go");
    assert.deepEqual(await lines(), ["мой текст 🙂", "чисти", "поехали 👍"]);
    await page.click("#clean");
    assert.deepEqual(await lines(), ["мой текст 🙂", "поехали 👍"], "снято первое слово: хвост пересобран через границы строк");
    await page.click("#go");
    assert.deepEqual(await lines(), ["мой текст 🙂"], "снято последнее слово — свой текст цел до знака");
  } finally {
    await context?.close();
    if (previousTmp === undefined) delete process.env.TMPDIR; else process.env.TMPDIR = previousTmp;
    rmSync(scratch, { recursive: true, force: true });
  }
});
