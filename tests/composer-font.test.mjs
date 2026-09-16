import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const KEY = "myclaude-composer-font-size-v1";
const font = editor => editor.style.getPropertyValue("font-size");
const page = options => loadInject({
  html: dom => {
    const parts = dom.composer({ text: "test draft" });
    parts.editor.computed["font-size"] = "16px";
    parts.message = dom.document.body.add("div", { class: "epitaxy-user-turn" });
    parts.message.style.setProperty("font-size", "14px");
    return parts;
  },
  ...options,
});
const key = (loaded, overrides = {}) => loaded.win.dispatchEvent({
  type: "keydown", code: "BracketRight", key: "ъ",
  ctrlKey: true, altKey: true, metaKey: true, shiftKey: false,
  target: loaded.parts?.editor, ...overrides,
});

test("dedicated physical codes change only composer by one pixel on Russian layout", () => {
  const loaded = page();
  assert.equal(loaded.error, null);
  assert.equal(font(loaded.parts.editor), "");
  const sizeBefore = JSON.stringify(loaded.api.status().size);
  assert.equal(key(loaded), false);
  assert.equal(font(loaded.parts.editor), "17px");
  assert.equal(key(loaded, { code: "BracketLeft", key: "х" }), false);
  assert.equal(font(loaded.parts.editor), "16px");
  assert.equal(font(loaded.parts.message), "14px");
  assert.equal(loaded.parts.editor.textContent, "test draft");
  assert.equal(JSON.stringify(loaded.api.status().size), sizeBefore);
  assert.equal(loaded.win.localStorage.getItem(KEY), "16");
});

test("ordinary zoom, incomplete modifiers, Shift and composition remain untouched", () => {
  const loaded = page();
  for (const change of [
    { code: "Equal", key: "=" }, { code: "Minus", key: "-" },
    { ctrlKey: false }, { altKey: false }, { metaKey: false },
    { shiftKey: true }, { isComposing: true },
    { code: "KeyA", key: "]" },
  ]) assert.equal(key(loaded, change), true);
  assert.equal(font(loaded.parts.editor), "");
  assert.equal(loaded.win.localStorage.getItem(KEY), null);
});

test("font is bounded at 11 and 32 and boundary keys remain consumed", () => {
  const loaded = page();
  for (let i = 0; i < 40; i++) assert.equal(key(loaded), false);
  assert.equal(font(loaded.parts.editor), "32px");
  for (let i = 0; i < 40; i++) assert.equal(key(loaded, { code: "BracketLeft" }), false);
  assert.equal(font(loaded.parts.editor), "11px");
});

test("unfocused, foreign, missing and disconnected editors cannot receive the command", () => {
  for (const options of [
    { hasFocus: false }, { href: "data:text/html,artifact" }, { html: null },
  ]) {
    const loaded = page(options);
    assert.equal(key(loaded), true);
    assert.equal(loaded.win.localStorage.getItem(KEY), null);
  }
  const detached = page();
  detached.parts.editor.remove();
  assert.equal(key(detached), true);
  assert.equal(detached.win.localStorage.getItem(KEY), null);
});

test("an open dialog keeps its own keys", () => {
  const loaded = page();
  loaded.document.body.add("div", {
    attrs: { role: "dialog" }, rect: { left: 10, top: 10, width: 200, height: 100 },
  });
  assert.equal(key(loaded), true);
  assert.equal(font(loaded.parts.editor), "");
});

test("saved size survives reload without accumulating listeners and dispose restores the old style", () => {
  const loaded = page({ html: dom => {
    const parts = dom.composer();
    parts.editor.style.setProperty("font-size", "19px");
    return parts;
  }});
  const listeners = loaded.counters.listeners;
  key(loaded);
  assert.equal(font(loaded.parts.editor), "20px");
  assert.equal(loaded.reload().error, null);
  assert.equal(font(loaded.parts.editor), "20px");
  assert.equal(loaded.counters.listeners, listeners);
  loaded.api.dispose();
  assert.equal(font(loaded.parts.editor), "19px");
  assert.equal(loaded.win.localStorage.getItem(KEY), "20");
  assert.equal(loaded.counters.listeners, 0);
  assert.equal(key(loaded), true);
});

test("replacement editor receives stored preference and the previous one is cleaned", () => {
  const loaded = page({ storage: { local: { [KEY]: "23" } } });
  const previous = loaded.parts.editor;
  assert.equal(font(previous), "23px");
  previous.remove();
  const replacement = loaded.parts.root.add("div", {
    class: "ProseMirror", attrs: { contenteditable: "true" },
    rect: { left: 110, top: 630, width: 980, height: 100 },
  });
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  assert.equal(font(previous), "");
  assert.equal(font(replacement), "23px");
});

test("invalid saved values do not override Claude and unavailable storage does not block adjustment", () => {
  for (const value of ["0", "33", "NaN", "12.5", "not a size"]) {
    const loaded = page({ storage: { local: { [KEY]: value } } });
    assert.equal(font(loaded.parts.editor), "");
    key(loaded);
    assert.equal(font(loaded.parts.editor), "17px");
  }
  const loaded = page();
  loaded.win.localStorage.setItem = () => { throw new Error("storage unavailable"); };
  assert.equal(key(loaded), false);
  assert.equal(font(loaded.parts.editor), "17px");
});

test("dispose does not undo a later foreign font-size change", () => {
  const loaded = page();
  key(loaded);
  loaded.parts.editor.style.setProperty("font-size", "22px");
  loaded.api.dispose();
  assert.equal(font(loaded.parts.editor), "22px");
});


test("generic fields and ProseMirror outside Claude composer keep their keys and styles", () => {
  for (const [tag, attrs, className] of [
    ["textarea", {}, ""], ["div", { contenteditable: "true" }, ""],
    ["div", { contenteditable: "true" }, "ProseMirror"],
  ]) {
    const loaded = page({ storage: { local: { [KEY]: "23" } }, html: dom => ({
      editor: dom.document.body.add(tag, {
        attrs, class: className, rect: { left: 100, top: 630, width: 980, height: 100 },
      }),
    }) });
    assert.equal(loaded.error, null);
    assert.equal(key(loaded), true);
    assert.equal(font(loaded.parts.editor), "");
    assert.equal(loaded.parts.editor.getAttribute("data-myclaude-composer-font"), null);
    assert.equal(loaded.win.localStorage.getItem(KEY), "23");
  }
});

test("font rule is confined to the marked composer and its editable text; cleanup removes the mark", () => {
  const loaded = page();
  const marker = "data-myclaude-composer-font";
  key(loaded);
  assert.equal(loaded.parts.editor.getAttribute(marker), "true");
  assert.equal(loaded.parts.message.getAttribute(marker), null);
  // The DOM stub does not compute CSS cascades. Inspect the installed rule,
  // including the descendant override and exclusions for non-text widgets.
  const rule = loaded.dom.sheets().match(/:is\(\.epitaxy-prompt, \[data-cds="ChatComposer"\]\) \.ProseMirror\[data-myclaude-composer-font="true"\][^{]+\{[^}]+\}/)?.[0];
  assert.ok(rule);
  assert.match(rule, /font-size: inherit !important/);
  assert.match(rule, /:is\(p, span, div,/);
  assert.match(rule, /:not\(:is\(\[contenteditable="false"\], button, svg\) \*\)/);
  loaded.api.dispose();
  assert.equal(loaded.parts.editor.getAttribute(marker), null);
  assert.equal(loaded.counters.sheets, 0);
});

test("moving the editor outside composer removes the persisted font override", () => {
  const loaded = page({ storage: { local: { [KEY]: "23" } } });
  loaded.document.body.appendChild(loaded.parts.editor);
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  assert.equal(font(loaded.parts.editor), "");
  assert.equal(key(loaded), true);
  assert.equal(loaded.parts.editor.getAttribute("data-myclaude-composer-font"), null);
});
