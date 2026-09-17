import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const ID = "myclaude-remove-last-composer-image-v1";
const SCOPE_ID = "myclaude-image-undo-composer-v1";
const rect = { left: 140, top: 630, width: 20, height: 20 };
const image = (box, id) => {
  const card = box.add("div", { attrs: {
    "data-cds": "MessageAttachmentsImage", "data-cds-attachment": "",
  }, rect: { ...rect, width: 56, height: 56 } });
  const button = card.add("button", { attrs: { "aria-label": "Remove", ...(id ? { id } : {}) }, rect });
  return { card, button };
};
const page = (options = {}, setup = () => {}) => loadInject({
  html: dom => {
    const parts = dom.composer({ text: "unchanged draft" });
    parts.box = parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
    parts.first = image(parts.box, "native-first");
    parts.last = image(parts.box, "native-last");
    parts.transcript = dom.document.body.add("div", { attrs: { "data-cds-composer-attachments": "" } });
    parts.sent = image(parts.transcript);
    setup(dom, parts);
    return parts;
  }, ...options,
});
const tick = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const marked = loaded => loaded.document.querySelectorAll(`#${ID}`);
const scopes = loaded => loaded.document.querySelectorAll(`#${SCOPE_ID}`);

test("only the last composer image exposes its native Remove; draft and CmdZ stay untouched", () => {
  const loaded = page();
  assert.equal(loaded.error, null);
  assert.deepEqual(marked(loaded), [loaded.parts.last.button]);
  assert.equal(loaded.parts.first.button.id, "native-first");
  assert.equal(loaded.parts.sent.button.id, "");
  assert.equal(loaded.parts.last.button.getAttribute("aria-label"), "Remove");
  assert.equal(loaded.parts.editor.textContent, "unchanged draft");
  assert.equal(loaded.api.status().composerImageUndo.available, true);
  assert.equal(loaded.win.dispatchEvent({ type: "keydown", key: "z", code: "KeyZ", metaKey: true }), true);
});

test("removing the marked native card moves capability to the preceding image", () => {
  const loaded = page();
  loaded.parts.last.button.addEventListener("click", () => loaded.parts.last.card.remove());
  loaded.parts.last.button.click();
  tick(loaded);
  assert.deepEqual(marked(loaded), [loaded.parts.first.button]);
  assert.equal(loaded.parts.last.button.id, "native-last");
  assert.equal(loaded.parts.editor.textContent, "unchanged draft");
});

test("no fallback to earlier image when the last one is ambiguous, disabled or hidden", () => {
  for (const setup of [
    (_, p) => p.last.button.remove(),
    (_, p) => p.last.card.add("button", { attrs: { "aria-label": "Remove image" }, rect }),
    (_, p) => p.last.button.setAttribute("aria-label", "Remove from queue"),
    (_, p) => p.last.button.setAttribute("disabled", ""),
    (_, p) => p.last.button.setAttribute("aria-disabled", "true"),
    (_, p) => p.last.card.setAttribute("hidden", ""),
    (_, p) => { p.last.card.computed.display = "none"; },
    (_, p) => { p.last.button.rect.width = 0; },
  ]) {
    const loaded = page({}, setup);
    assert.equal(loaded.error, null);
    assert.equal(marked(loaded).length, 0);
    assert.equal(loaded.api.status().composerImageUndo.available, false);
  }
});

test("multiple composers, attachment boxes, modal or foreign page expose no capability", () => {
  for (const setup of [
    dom => dom.composer({ top: 300 }),
    (_, p) => p.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } }),
    dom => dom.document.body.add("div", { attrs: { role: "dialog" }, rect }),
    (_, p) => p.editor.setAttribute("contenteditable", "false"),
  ]) assert.equal(marked(page({}, setup)).length, 0);
  assert.equal(marked(page({ href: "data:text/html,artifact" })).length, 0);
});

test("ordinary document attachments and unrelated Remove buttons never receive the image marker", () => {
  const loaded = page({}, (_, p) => {
    p.first.card.remove(); p.last.card.remove();
    p.box.add("div", { attrs: { "data-cds-attachment": "", "data-cds": "MessageAttachmentsFile" } })
      .add("button", { attrs: { "aria-label": "Remove file" }, rect });
    p.shell.add("button", { attrs: { "aria-label": "Remove" }, rect });
  });
  assert.equal(marked(loaded).length, 0);
});

test("reload and dispose restore original ids without adding timers or retaining stale nodes", () => {
  const loaded = page();
  const counters = { ...loaded.counters };
  assert.equal(loaded.reload().error, null);
  assert.deepEqual(marked(loaded), [loaded.parts.last.button]);
  assert.deepEqual({ ...loaded.counters }, counters);
  loaded.api.dispose();
  assert.equal(loaded.parts.last.button.id, "native-last");
  assert.equal(marked(loaded).length, 0);
  assert.equal(loaded.counters.listeners, 0);
  assert.equal(loaded.counters.intervals, 0);
});

test("removed editor clears the marker; dispose does not overwrite a later foreign id", () => {
  const loaded = page();
  loaded.parts.editor.remove();
  tick(loaded);
  assert.equal(marked(loaded).length, 0);
  assert.equal(loaded.parts.last.button.id, "native-last");
  const foreign = page();
  foreign.parts.last.button.id = "later-id";
  foreign.api.dispose();
  assert.equal(foreign.parts.last.button.id, "later-id");
});

test("buttons without native ids are restored, and hover-hidden Remove stays usable", () => {
  const loaded = page({}, (_, p) => {
    p.last.button.removeAttribute("id");
    p.last.button.computed.opacity = "0";
  });
  assert.deepEqual(marked(loaded), [loaded.parts.last.button]);
  loaded.api.dispose();
  assert.equal(loaded.parts.last.button.getAttribute("id"), null);
});

test("composer boundary exists before the first image or attachment box, with original id restored", () => {
  const loaded = page({}, (_, p) => {
    p.box.remove();
    p.shell.id = "native-composer";
    p.shell.setAttribute("aria-label", "Draft");
    p.shell.setAttribute("role", "group");
  });
  assert.equal(loaded.error, null);
  assert.deepEqual(scopes(loaded), [loaded.parts.shell]);
  assert.equal(marked(loaded).length, 0);
  assert.equal(loaded.api.status().composerImageUndo.composer, true);
  assert.equal(loaded.api.status().composerImageUndo.available, false);
  assert.equal(loaded.parts.shell.getAttribute("aria-label"), "Draft");
  assert.equal(loaded.parts.shell.getAttribute("role"), "group");
  assert.equal(loaded.reload().error, null);
  assert.deepEqual(scopes(loaded), [loaded.parts.shell]);
  loaded.api.dispose();
  assert.equal(loaded.parts.shell.id, "native-composer");
});

test("tall wide composer encloses editor and sibling attachments without a half-window height limit", () => {
  const loaded = page({}, (_, p) => {
    p.wide = p.block.add("div", {
      attrs: { "data-cds": "ChatComposer", id: "native-wide" },
      rect: { left: 810, top: 20, width: 350, height: 760 },
    });
    p.wide.appendChild(p.shell);
    p.wide.appendChild(p.box);
    p.editor.rect = { left: 820, top: 110, width: 310, height: 610 };
  });
  assert.equal(loaded.error, null);
  assert.deepEqual(scopes(loaded), [loaded.parts.wide]);
  assert.deepEqual(marked(loaded), [loaded.parts.last.button]);
  assert.equal(loaded.parts.wide.contains(loaded.parts.editor), true);
  assert.equal(loaded.parts.wide.contains(loaded.parts.last.button), true);
  loaded.api.dispose();
  assert.equal(loaded.parts.wide.id, "native-wide");
});

test("ambiguous composers and modal transitions remove both markers and restore them only when safe", () => {
  const loaded = page();
  const second = loaded.dom.composer({ top: 300 });
  tick(loaded);
  assert.equal(scopes(loaded).length, 0);
  assert.equal(marked(loaded).length, 0);
  second.block.remove();
  tick(loaded);
  assert.equal(scopes(loaded).length, 1);
  const modal = loaded.document.body.add("div", { attrs: { role: "dialog" }, rect });
  tick(loaded);
  assert.equal(scopes(loaded).length, 0);
  assert.equal(marked(loaded).length, 0);
  modal.remove();
  tick(loaded);
  assert.equal(scopes(loaded).length, 1);
  assert.equal(marked(loaded).length, 1);
});

test("composer teardown restores its id and dispose preserves a later foreign scope id", () => {
  const loaded = page({}, (_, p) => { p.shell.id = "native-composer"; });
  loaded.parts.editor.remove();
  tick(loaded);
  assert.equal(scopes(loaded).length, 0);
  assert.equal(loaded.parts.shell.id, "native-composer");
  const foreign = page();
  foreign.parts.shell.id = "new-foreign-composer";
  foreign.api.dispose();
  assert.equal(foreign.parts.shell.id, "new-foreign-composer");
});

test("roleless composer receives a temporary group before attachments and loses it on dispose", () => {
  const loaded = page({}, (_, p) => { p.box.remove(); });
  assert.deepEqual(scopes(loaded), [loaded.parts.shell]);
  assert.equal(loaded.parts.shell.getAttribute("role"), "group");
  tick(loaded);
  assert.equal(loaded.parts.shell.getAttribute("role"), "group");
  assert.equal(loaded.reload().error, null);
  assert.equal(loaded.parts.shell.getAttribute("role"), "group");
  loaded.api.dispose();
  assert.equal(loaded.parts.shell.getAttribute("role"), null);
  assert.equal(loaded.parts.shell.getAttribute("id"), null);
});

test("existing semantic roles survive cleanup and explicitly ignored containers get no capability", () => {
  for (const role of ["region", "group"]) {
    const loaded = page({}, (_, p) => { p.shell.setAttribute("role", role); });
    assert.equal(scopes(loaded).length, 1);
    assert.equal(loaded.parts.shell.getAttribute("role"), role);
    loaded.api.dispose();
    assert.equal(loaded.parts.shell.getAttribute("role"), role);
  }
  for (const role of ["generic", "none", "presentation", " GENERIC ", ""]) {
    const loaded = page({}, (_, p) => { p.shell.setAttribute("role", role); });
    assert.equal(scopes(loaded).length, 0);
    assert.equal(marked(loaded).length, 0);
    assert.equal(loaded.parts.shell.getAttribute("role"), role);
    loaded.api.dispose();
    assert.equal(loaded.parts.shell.getAttribute("role"), role);
  }
});

test("temporary role cleanup respects later role changes and still restores its own role after id changes", () => {
  const foreignRole = page();
  foreignRole.parts.shell.setAttribute("role", "region");
  foreignRole.api.dispose();
  assert.equal(foreignRole.parts.shell.getAttribute("role"), "region");
  const foreignId = page();
  foreignId.parts.shell.id = "new-foreign-composer";
  foreignId.api.dispose();
  assert.equal(foreignId.parts.shell.id, "new-foreign-composer");
  assert.equal(foreignId.parts.shell.getAttribute("role"), null);
  const removedRole = page();
  removedRole.parts.shell.removeAttribute("role");
  removedRole.api.dispose();
  assert.equal(removedRole.parts.shell.getAttribute("role"), null);
});

test("composer ambiguity removes the temporary group and recovery reinstates it", () => {
  const loaded = page();
  const second = loaded.dom.composer({ top: 300 });
  tick(loaded);
  assert.equal(loaded.parts.shell.getAttribute("role"), null);
  second.block.remove();
  tick(loaded);
  assert.equal(loaded.parts.shell.getAttribute("role"), "group");
});
