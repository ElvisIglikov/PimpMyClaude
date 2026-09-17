import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const ID = "myclaude-composer-attachments-v1";
const SCOPE = "myclaude-image-undo-composer-v1";
const CHAT_A = "/chat/11111111-1111-4111-8111-111111111111";
const CHAT_B = "/chat/22222222-2222-4222-8222-222222222222";
const rect = { left: 140, top: 640, width: 40, height: 40 };
const card = (box, kind = "MessageAttachmentsImage") => {
  const node = box.add("div", { attrs: { "data-cds-attachment": "", "data-cds": kind }, rect });
  if (kind === "MessageAttachmentsImage") {
    const image = node.add("img", { rect });
    image.complete = true; image.naturalWidth = 40;
  }
  node.add("button", { attrs: { "aria-label": "Remove" }, rect });
  return node;
};
const page = (options = {}, setup = () => {}) => {
  const observers = [];
  const loaded = loadInject({ ...options, html: dom => {
    const Observer = dom.window.MutationObserver;
    dom.window.MutationObserver = class extends Observer {
      constructor(callback) { super(callback); observers.push(this); }
      observe(target) { this.target = target; super.observe(target); }
    };
    const parts = dom.composer({ text: "private draft must remain untouched" });
    parts.box = parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" }, rect });
    setup(dom, parts);
    return parts;
  } });
  assert.equal(loaded.error, null);
  loaded.observers = observers;
  return loaded;
};
const marker = loaded => loaded.document.getElementById(ID);
const snapshot = loaded => {
  const node = marker(loaded);
  return node ? JSON.parse(node.getAttribute("aria-label")) : null;
};
const tick = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const mutation = (loaded, target, extra = {}) => {
  const record = { type: "childList", target, addedNodes: [], removedNodes: [], ...extra };
  for (const observer of [...loaded.observers]) {
    if (observer.live && observer.target?.contains(target)) observer.fn([record]);
  }
};

test("empty known and new composers expose direct AX metadata without changing the draft", () => {
  for (const href of ["https://claude.ai/epitaxy/local_test", "https://claude.ai/epitaxy", "https://claude.ai/new", `https://claude.ai${CHAT_A}`]) {
    const loaded = page({ href }, (_, p) => p.box.remove());
    const value = snapshot(loaded);
    assert.equal(value.v, 1);
    assert.equal(value.count, 0);
    assert.deepEqual(value.members, []);
    assert.equal(marker(loaded).parentElement.id, SCOPE);
    assert.equal(marker(loaded).parentElement.getAttribute("role"), "group");
    assert.equal(marker(loaded).getAttribute("role"), "img");
    assert.equal(marker(loaded).hasAttribute("tabindex"), false);
    assert.equal(loaded.parts.editor.textContent, "private draft must remain untouched");
    assert.deepEqual(Object.keys(value).sort(), ["count", "generation", "members", "revision", "session", "v"]);
    assert.ok(!JSON.stringify(value).includes("local_test"));
    loaded.api.dispose();
  }
});

test("counts all composer cards including documents, excluding transcript cards", () => {
  const loaded = page({}, (dom, p) => {
    card(p.box); card(p.box, "MessageAttachmentsFile");
    const transcript = dom.document.body.add("div", { attrs: { "data-cds-composer-attachments": "" } });
    card(transcript);
  });
  const value = snapshot(loaded);
  assert.equal(value.count, 2);
  assert.equal(new Set(value.members).size, 2);
  assert.ok(value.members.every(id => /^m\d+$/.test(id)));
});

test("metadata never includes private file attributes or draft content", () => {
  const loaded = page({}, (_, p) => {
    const item = card(p.box);
    item.setAttribute("data-cds-attachment", "private-file-id");
    item.setAttribute("title", "private-name.png");
    item.querySelector("img").setAttribute("src", "blob:private-image-url");
    item.querySelector("button").setAttribute("aria-label", "Remove private-name.png");
  });
  assert.equal(snapshot(loaded).count, 1);
  assert.ok(!marker(loaded).getAttribute("aria-label").includes("private"));
});

test("growth changes revision and preserves generation plus all existing member IDs", () => {
  const loaded = page({}, (_, p) => card(p.box));
  const before = snapshot(loaded);
  const added = card(loaded.parts.box, "MessageAttachmentsFile");
  mutation(loaded, loaded.parts.box, { addedNodes: [added] });
  const after = snapshot(loaded);
  assert.equal(after.generation, before.generation);
  assert.equal(after.session, before.session);
  assert.equal(after.count, before.count + 1);
  assert.ok(after.revision > before.revision);
  assert.ok(before.members.every(id => after.members.includes(id)));
  tick(loaded);
  assert.deepEqual(snapshot(loaded), after);
});

test("loading, disabled, error and unknown cards are unavailable and recover after readiness", () => {
  for (const change of [
    node => node.setAttribute("aria-busy", "true"),
    node => node.setAttribute("data-status", "uploading"),
    node => node.setAttribute("data-status", "error"),
    node => node.setAttribute("data-cds", "UnknownAttachment"),
    node => node.querySelector("button").setAttribute("disabled", ""),
    node => { node.querySelector("img").complete = false; },
    node => { node.querySelector("img").naturalWidth = 0; },
    node => node.add("div", { attrs: { role: "progressbar" }, rect }),
    node => card(node),
  ]) {
    const loaded = page();
    const before = snapshot(loaded);
    const added = card(loaded.parts.box);
    change(added);
    mutation(loaded, loaded.parts.box, { addedNodes: [added] });
    assert.equal(snapshot(loaded), null);
    added.remove();
    const ready = card(loaded.parts.box);
    mutation(loaded, loaded.parts.box, { addedNodes: [ready], removedNodes: [added] });
    assert.equal(snapshot(loaded).count, 1);
    assert.equal(snapshot(loaded).generation, before.generation);
    loaded.api.dispose();
  }
});

test("attribute-only loading transitions invalidate immediately without a layout timer", () => {
  const loaded = page({}, (_, p) => card(p.box));
  const before = snapshot(loaded);
  const node = loaded.parts.box.children[0];
  node.setAttribute("aria-busy", "true");
  mutation(loaded, node, { type: "attributes", attributeName: "aria-busy" });
  assert.equal(snapshot(loaded), null);
  node.removeAttribute("aria-busy");
  mutation(loaded, node, { type: "attributes", attributeName: "aria-busy" });
  assert.deepEqual(snapshot(loaded), before);
});

test("ambiguous composers, duplicate boxes, foreign pages and unidentified popouts are unavailable", () => {
  for (const setup of [
    dom => dom.composer({ top: 350 }),
    (_, p) => p.shell.add("div", { attrs: { "data-cds-composer-attachments": "" }, rect }),
    dom => dom.document.body.add("div", { attrs: { role: "dialog" }, rect }),
    (_, p) => card(p.shell),
    (_, p) => p.box.add("div", { rect }),
  ]) assert.equal(snapshot(page({}, setup)), null);
  assert.equal(snapshot(page({ href: "data:text/html,private" })), null);
  assert.equal(snapshot(page({ href: "about:blank" })), null);
  for (const path of ["/chat/unknown", `${CHAT_A}/settings`, "/projects"]) {
    assert.equal(snapshot(page({ href: `https://claude.ai${path}` })), null);
  }
});

test("removing or replacing prior cards invalidates generation even at the same count", () => {
  const loaded = page({}, (_, p) => card(p.box));
  const before = snapshot(loaded);
  const removed = loaded.parts.box.children[0]; removed.remove();
  const added = card(loaded.parts.box);
  mutation(loaded, loaded.parts.box, { addedNodes: [added], removedNodes: [removed] });
  const after = snapshot(loaded);
  assert.equal(after.count, 1);
  assert.ok(after.generation > before.generation);
  assert.ok(!after.members.includes(before.members[0]));
  added.remove();
  mutation(loaded, loaded.parts.box, { removedNodes: [added] });
  assert.equal(snapshot(loaded).count, 0);
  assert.ok(snapshot(loaded).generation > after.generation);
});

test("same composer on a different chat invalidates before the next layout", () => {
  for (const action of ["pushState", "replaceState", "popstate", "hashchange"]) {
    const loaded = page();
    const before = snapshot(loaded);
    loaded.win.location.pathname = "/epitaxy/local_next";
    if (action.endsWith("State")) loaded.win.history[action]({}, "", "/epitaxy/local_next");
    else loaded.win.dispatchEvent({ type: action });
    assert.equal(snapshot(loaded), null);
    tick(loaded);
    assert.ok(snapshot(loaded).generation > before.generation);
  }
});

test("ordinary chat routes and new chat invalidate tickets while recycling the same composer", () => {
  const loaded = page({ href: `https://claude.ai${CHAT_A}` }, (_, p) => card(p.box));
  const composer = marker(loaded).parentElement;
  for (const [path, action] of [[CHAT_B, "pushState"], ["/new", "replaceState"], [CHAT_A, "pushState"]]) {
    const before = snapshot(loaded);
    loaded.win.location.pathname = path;
    loaded.win.history[action]({}, "", path);
    assert.equal(snapshot(loaded), null, "old ticket disappears synchronously");
    tick(loaded);
    const after = snapshot(loaded);
    assert.equal(marker(loaded).parentElement, composer);
    assert.equal(after.session, before.session);
    assert.ok(after.generation > before.generation);
    assert.equal(after.count, 1);
    assert.ok(!after.members.some(id => before.members.includes(id)));
    assert.ok(!marker(loaded).getAttribute("aria-label").includes(path));
  }
});

test("editor replacement invalidates while retaining the same outer composer", () => {
  const loaded = page();
  const before = snapshot(loaded);
  const old = loaded.parts.editor;
  const editor = old.cloneNode(true);
  loaded.parts.root.appendChild(editor); old.remove();
  mutation(loaded, loaded.parts.root, { addedNodes: [editor], removedNodes: [old] });
  assert.equal(snapshot(loaded), null);
  tick(loaded);
  assert.ok(snapshot(loaded).generation > before.generation);
});

test("structural editor reset invalidates without reading its old or new text", () => {
  const loaded = page({}, (_, p) => p.editor.add("p", { text: "private content" }));
  const before = snapshot(loaded);
  const old = loaded.parts.editor.children[0]; old.remove();
  const paragraph = loaded.parts.editor.add("p");
  mutation(loaded, loaded.parts.editor, { addedNodes: [paragraph], removedNodes: [old] });
  assert.ok(snapshot(loaded).generation > before.generation);
});

test("submit, reset and send intent invalidate synchronously without intercepting input", () => {
  for (const event of [
    { type: "keydown", key: "Enter" }, { type: "submit" }, { type: "reset" }, { type: "click" },
  ]) {
    const loaded = page();
    const before = snapshot(loaded);
    const target = event.type === "click"
      ? loaded.parts.shell.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect })
      : loaded.parts.editor;
    assert.equal(loaded.document.dispatchEvent({ ...event, target }), true);
    assert.equal(snapshot(loaded), null);
    tick(loaded);
    assert.ok(snapshot(loaded).generation > before.generation);
    assert.equal(loaded.parts.editor.textContent, "private draft must remain untouched");
  }
});

test("Shift Enter and IME composition do not invalidate or swallow editing", () => {
  const loaded = page();
  const before = snapshot(loaded);
  for (const extra of [{ shiftKey: true }, { isComposing: true }]) {
    assert.equal(loaded.document.dispatchEvent({ type: "keydown", key: "Enter", target: loaded.parts.editor, ...extra }), true);
    assert.deepEqual(snapshot(loaded), before);
  }
});

test("reloading changes session and dispose restores history without overwriting a newer wrapper", () => {
  const loaded = page();
  const first = snapshot(loaded);
  const counts = { ...loaded.counters };
  assert.equal(loaded.reload().error, null);
  assert.notEqual(snapshot(loaded).session, first.session);
  assert.equal(loaded.dom.queryAll(`#${ID}`).length, 1);
  assert.deepEqual({ ...loaded.counters }, counts);
  const foreign = () => "newer wrapper";
  loaded.win.history.pushState = foreign;
  loaded.api.dispose();
  assert.equal(loaded.win.history.pushState, foreign);
  assert.equal(marker(loaded), null);
  assert.equal(loaded.counters.listeners, 0);
  assert.equal(loaded.counters.observers, 0);
});

test("history wrappers preserve arguments, receiver, result, errors and restore their originals", () => {
  const calls = [];
  const original = function (...args) { calls.push({ receiver: this, args }); return 42; };
  const failure = new Error("native history failure");
  const throwing = () => { throw failure; };
  const loaded = page({}, dom => {
    dom.window.history.pushState = original;
    dom.window.history.replaceState = throwing;
  });
  const value = { state: 1 };
  assert.equal(loaded.win.history.pushState(value, "", "/epitaxy/local_test"), 42);
  assert.equal(calls[0].receiver, loaded.win.history);
  assert.deepEqual(calls[0].args, [value, "", "/epitaxy/local_test"]);
  assert.throws(() => loaded.win.history.replaceState(null, "", "/new"), error => error === failure);
  loaded.api.dispose();
  assert.equal(loaded.win.history.pushState, original);
  assert.equal(loaded.win.history.replaceState, throwing);
});
