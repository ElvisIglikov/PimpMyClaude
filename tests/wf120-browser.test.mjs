// Optional real Chromium gate: isolated fixture, no Claude/Viewer/network/profile.
// PIMP_WF120_PLAYWRIGHT=/path/to/playwright/index.mjs
// PIMP_WF120_CHROMIUM=/path/to/chrome-headless-shell node --test tests/wf120-browser.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { injectSource } from "./load.mjs";

const enabled = Boolean(process.env.PIMP_WF120_PLAYWRIGHT && process.env.PIMP_WF120_CHROMIUM);
test("WF120 Chromium: реальные PNG-байты, pending/off, CSS :has и обновление ленты", { skip: !enabled, timeout: 30000 }, async () => {
  const { chromium } = await import(pathToFileURL(process.env.PIMP_WF120_PLAYWRIGHT));
  const scratch = mkdtempSync(resolve("audit/wf120-browser-"));
  let context;
  const previousTmp = process.env.TMPDIR;
  process.env.TMPDIR = scratch;
  try {
    context = await chromium.launchPersistentContext(resolve(scratch, "profile"), {
      executablePath: process.env.PIMP_WF120_CHROMIUM, headless: true,
      downloadsPath: scratch, env: { ...process.env, TMPDIR: scratch },
      args: ["--disable-breakpad", "--disable-crash-reporter"],
    });
    await context.route("**/*", route => route.fulfill({ status: 200, contentType: "text/html", body: `<!doctype html>
      <style>.epitaxy-composer-width{position:fixed;bottom:10px;left:100px;width:900px;height:200px}.epitaxy-prompt{height:160px}.editor-root{height:100px;overflow:auto}.ProseMirror{height:90px;width:850px}button{min-width:24px;min-height:24px}[data-cds-attachment]{width:60px;height:60px}</style>
      <div data-testid="transcript-row" data-perf-row="assistant"><div data-cds="AssistantMessage" data-is-streaming="false">
        <div id="done" data-cds="TurnStatus" data-tool-anchor="toolu_1" data-state="done">Ran 2 commands</div>
        <div id="edited" class="contents" data-find-omitted><div><ul role="list"><li><button data-base-ui-tooltip-trigger>Edited 2 files</button></li></ul></div></div>
        <div class="epitaxy-codeblock">Обычный код</div>
      </div></div>
      <div class="epitaxy-composer-width"><div class="epitaxy-prompt" data-cds="ChatComposer"><div class="editor-root"><div class="ProseMirror" contenteditable="true">Текст</div></div><div data-cds-composer-attachments></div></div><div class="model-row"><button data-testid="code-prompt-send">Send</button></div></div>` }));
    const page = context.pages()[0];
    await page.goto("https://claude.ai/epitaxy/local_wf120_fixture");
    await page.evaluate(() => {
      window.__myclaudeTest = inner => { window.testInner = inner; };
      window.sent = [];
      window.files = [];
      const editor = document.querySelector(".ProseMirror");
      const box = document.querySelector("[data-cds-composer-attachments]");
      editor.addEventListener("paste", event => {
        event.preventDefault();
        for (const file of event.clipboardData.files) {
          window.files.push(file);
          const tile = document.createElement("div");
          tile.setAttribute("data-cds-attachment", "");
          tile.setAttribute("data-cds", "MessageAttachmentsImage");
          const img = document.createElement("img");
          img.src = URL.createObjectURL(file);
          const remove = document.createElement("button");
          remove.setAttribute("aria-label", `Remove ${file.name}`);
          tile.append(img, remove);
          box.append(tile);
        }
      });
      editor.addEventListener("keydown", event => {
        if (event.key === "Enter") { event.preventDefault(); window.sent.push([...window.files]); }
      });
    });
    assert.equal(await page.evaluate(injectSource()), "wf125-page-5");
    const command = async detail => page.evaluate(detail => window.dispatchEvent(new CustomEvent("myclaude-command", { detail })), detail);
    await command({ action: "hide-tools", on: "true" });
    const visibility = () => page.evaluate(() => ["done", "edited"].map(id => getComputedStyle(document.getElementById(id)).display));
    assert.deepEqual(await visibility(), ["none", "none"]);
    await page.evaluate(() => document.getElementById("done").setAttribute("data-state", "running"));
    assert.deepEqual(await visibility(), ["block", "block"]);
    await page.evaluate(() => {
      const node = document.getElementById("done");
      node.setAttribute("data-state", "done");
      const button = document.createElement("button"); button.textContent = "Allow once"; node.append(button);
    });
    assert.equal((await visibility())[0], "block");
    await page.evaluate(() => document.getElementById("done").querySelector("button").remove());
    assert.equal((await visibility())[0], "none");
    // Unknown choice disguised as an Edited wrapper is also visible.
    await page.evaluate(() => { document.querySelector("#edited button").textContent = "Утвердить план"; });
    assert.equal((await visibility())[1], "block");
    await page.evaluate(() => {
      document.querySelector("#edited button").textContent = "Edited 2 files";
      document.getElementById("edited").append("План: проверь результат");
      document.getElementById("done").setAttribute("role", "alert");
    });
    assert.deepEqual(await visibility(), ["block", "block"]);
    await command({ action: "send-delay", on: false, seconds: 5 });
    await page.evaluate(async () => {
      const canvas = document.createElement("canvas"); canvas.width = 320; canvas.height = 200;
      const ctx = canvas.getContext("2d"); ctx.fillStyle = "rgb(30,100,180)"; ctx.fillRect(0, 0, 320, 200);
      window.original = new File([await new Promise(resolve => canvas.toBlob(resolve))], "input.png", { type: "image/png" });
      const decode = window.createImageBitmap;
      window.createImageBitmap = (...args) => new Promise(resolve => { window.finishDecode = () => { window.createImageBitmap = decode; resolve(decode(...args)); }; });
      window.testInner.shotPaste({ isTrusted: true, target: document.querySelector(".ProseMirror"),
        clipboardData: { files: [window.original], getData: () => "" }, preventDefault() {}, stopPropagation() {}, stopImmediatePropagation() {} });
    });
    await page.locator(".ProseMirror").focus();
    await page.keyboard.press("Enter");
    assert.equal(await page.evaluate(() => window.sent.length), 0);
    await page.evaluate(() => window.finishDecode());
    await page.evaluate(() => window.testInner.shotState.chain);
    assert.equal(await page.evaluate(() => window.sent.length), 0);
    await page.keyboard.press("Enter");
    const bytes = await page.evaluate(async () => {
      const file = window.sent[0][0];
      const original = new Uint8Array(await window.original.arrayBuffer());
      const out = new Uint8Array(await file.arrayBuffer());
      const bitmap = await createImageBitmap(file);
      const canvas = document.createElement("canvas"); canvas.width = bitmap.width; canvas.height = bitmap.height;
      const ctx = canvas.getContext("2d"); ctx.drawImage(bitmap, 0, 0); bitmap.close();
      const pixels = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let changed = 0, white = 0, outside = 0;
      for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
        const at = (y * 320 + x) * 4;
        if (pixels[at] !== 30 || pixels[at + 1] !== 100 || pixels[at + 2] !== 180) {
          changed++;
          if (x > 60 || y < 160) outside++;
          if (pixels[at] > 220 && pixels[at + 1] > 220 && pixels[at + 2] > 220) white++;
        }
      }
      return { name: file.name, type: file.type, signature: [...out.slice(0, 8)], width: canvas.width, height: canvas.height,
        equal: out.length === original.length && out.every((byte, i) => byte === original[i]), changed, white, outside,
        mark: document.querySelector("[data-cds-attachment]").getAttribute("data-myclaude-shot"), sends: window.sent.length };
    });
    assert.equal(bytes.name, "Скриншот 1.png");
    assert.equal(bytes.type, "image/png");
    assert.deepEqual(bytes.signature, [137, 80, 78, 71, 13, 10, 26, 10]);
    assert.deepEqual([bytes.width, bytes.height, bytes.mark, bytes.sends], [320, 200, "1", 1]);
    assert.equal(bytes.equal, false);
    assert.ok(bytes.changed > 100 && bytes.white > 10, JSON.stringify(bytes));
    assert.equal(bytes.outside, 0, "исходная картинка изменилась за пределами номера");
    assert.deepEqual(await page.evaluate(() => {
      const tile = document.querySelector("[data-cds-attachment]");
      const badge = getComputedStyle(tile, "::after");
      return [getComputedStyle(tile).position, badge.content, badge.left, badge.bottom, badge.pointerEvents];
    }), ["relative", '"1"', "3px", "3px", "none"]);
  } finally {
    await context?.close();
    if (previousTmp === undefined) delete process.env.TMPDIR; else process.env.TMPDIR = previousTmp;
    rmSync(scratch, { recursive: true, force: true });
  }
});
