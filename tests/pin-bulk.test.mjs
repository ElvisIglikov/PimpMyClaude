import test from 'node:test';
import assert from 'node:assert/strict';
import { loadInject } from './load.mjs';

const ROOT = '#myclaude-pin-bulk';
const ACTION = 'data-myclaude-pin-action';
const CHAT = 'data-myclaude-pin-chat';
const settle = () => new Promise(resolve => setImmediate(resolve));
const page = ({ ids = ['local_a', 'local_b', 'local_c'], href, setter, missing = false } = {}) => {
  const calls = [], pins = { ids: [...ids], order: ids.map(id => `code:${id}`) };
  const p = loadInject({ href, html: dom => {
    const parts = dom.composer();
    parts.pinned = dom.document.body.add('div', { attrs: { 'data-testid': 'sidebar-pinned' } });
    for (const id of ['local_a', 'local_b']) parts.pinned.add('div', { attrs: { 'data-row-key': `code:${id}` }, text: 'Одинаковое имя' });
    return parts;
  } });
  assert.equal(p.error, null);
  let time = p.win.performance.now();
  p.win.performance.now = () => time;
  const remove = id => { pins.ids = pins.ids.filter(raw => raw !== id && raw !== `code:${id}`); pins.order = pins.order.filter(raw => raw !== `code:${id}`); };
  const store = () => {};
  store.getState = () => ({ starredIds: pins.ids, setStarred: (id, on) => {
    calls.push([id, on]);
    return setter ? setter(id, remove) : remove(id);
  } });
  p.dom.modules('https://claude.ai/assets/v1/chunk-1.js');
  let imports = 0;
  p.inner.setModuleImporter(() => { imports++; return Promise.resolve(missing ? {} : { Star: store }); });
  const root = () => p.dom.query(ROOT);
  const button = action => root()?.querySelector(`[${ACTION}="${action}"]`);
  const click = action => {
    const target = button(action); assert.ok(target, `button ${action}`);
    p.document.dispatchEvent({ type: 'click', target, isTrusted: true, detail: 1 });
  };
  const select = id => {
    const target = root().querySelector(`[${CHAT}="${id}"]`); assert.ok(target);
    target.checked = !target.checked;
    p.document.dispatchEvent({ type: 'change', target, isTrusted: true });
  };
  const advance = async ms => { for (let i = 0; i < ms; i += 100) { time += 100; p.dom.fireKind('timeout'); await settle(); } };
  return { p, pins, calls, root, button, click, select, advance, imports: () => imports,
    open: async () => { click('open'); await settle(); } };
};

test('#8224: only main UI, store scanned on open, canonical unique IDs including virtual rows', async () => {
  const q = page({ ids: ['local_a', 'code:local_a', 'code:local_b', 'local_c', 'chat:web', 2, 'unknown'] });
  assert.equal(q.imports(), 0);
  assert.equal(q.root().nextElementSibling, q.p.parts.pinned);
  await q.open();
  assert.equal(q.p.inner.pinBulk.phase, 'select');
  assert.deepEqual([...q.root().querySelectorAll(`[${CHAT}]`)].map(el => el.getAttribute(CHAT)), ['local_a', 'local_b', 'local_c']);
  assert.match(q.root().textContent, /Закреплённые чаты Code/);
  assert.match(q.root().textContent, /пропущены: 3/);
  assert.match(q.root().textContent, /Одинаковое имя · …a/);
  assert.match(q.root().textContent, /Одинаковое имя · …b/);
  assert.deepEqual(q.calls, []);
  q.p.api?.dispose();
  const popup = page({ href: 'about:blank' });
  assert.equal(popup.root(), null); popup.p.api.dispose();
});

test('#8224: select all/clear, explicit Unpin only selected IDs, unrelated order preserved', async () => {
  const q = page(); await q.open();
  assert.equal(q.button('unpin').disabled, true);
  q.click('all'); assert.equal(q.button('unpin').textContent, 'Открепить (3)');
  q.click('all'); assert.equal(q.button('unpin').disabled, true);
  q.select('local_b');
  assert.deepEqual(q.calls, []);
  q.click('unpin'); await settle();
  assert.deepEqual(q.calls, [['local_b', false]]);
  assert.deepEqual(q.pins.order, ['code:local_a', 'code:local_c']);
  assert.match(q.root().textContent, /Откреплено 1/);
  assert.equal(q.p.inner.pinBulk.phase, 'done'); q.p.api?.dispose();
});

test('#8224: selection snapshot excludes new pins, skips externally unpinned, ignores changed labels', async () => {
  const q = page(); await q.open(); q.click('all');
  q.pins.ids = ['local_b', 'local_c', 'local_new'];
  q.p.parts.pinned.children[1].textContent = 'Новое имя';
  q.click('unpin'); await settle();
  assert.deepEqual(q.calls, [['local_b', false], ['local_c', false]]);
  assert.deepEqual(q.pins.ids, ['local_new']);
  assert.match(q.root().textContent, /Уже были откреплены: 1/); q.p.api?.dispose();
});

for (const cancel of ['cancel', 'Escape']) test(`#8224: ${cancel} before confirmation has no effect on store`, async () => {
  const q = page(); await q.open(); q.click('all');
  if (cancel === 'Escape') q.p.win.dispatchEvent({ type: 'keydown', key: 'Escape', isTrusted: true }); else q.click('cancel');
  assert.equal(q.p.inner.pinBulk.phase, 'closed'); assert.deepEqual(q.calls, []); q.p.api?.dispose();
});

test('#8224: partial cancellation reports confirmed/issued and never starts remaining IDs', async () => {
  let finish;
  const q = page({ setter: (id, remove) => id === 'local_a' ? remove(id) : new Promise(resolve => { finish = () => { remove(id); resolve(); }; }) });
  await q.open(); q.click('all'); q.click('unpin'); await settle();
  assert.deepEqual(q.calls, [['local_a', false], ['local_b', false]]);
  q.p.win.dispatchEvent({ type: 'keydown', key: 'Escape', isTrusted: true });
  assert.match(q.root().textContent, /Откреплено 1.*Не подтверждено: 1.*Остальные оставлены/);
  finish(); await q.advance(2500);
  assert.deepEqual(q.calls, [['local_a', false], ['local_b', false]]);
  assert.equal(q.p.inner.pinBulk.phase, 'cancelled'); q.p.api?.dispose();
});

for (const mode of ['throw', 'reject', 'hung']) test(`#8224: ${mode} stops without retry; deadline includes pending setter`, async () => {
  const q = page({ setter: () => { if (mode === 'throw') throw Error('failed'); if (mode === 'reject') return Promise.reject(Error('failed')); return new Promise(() => {}); } });
  await q.open(); q.click('all'); q.click('unpin'); await settle(); await q.advance(2000);
  assert.equal(q.p.inner.pinBulk.phase, 'error');
  assert.match(q.root().textContent, /Не удалось подтвердить.*Откреплено 0.*Не подтверждено: 1/);
  await q.advance(4000); assert.deepEqual(q.calls, [['local_a', false]]);
  q.click('open'); await settle(); assert.equal(q.p.inner.pinBulk.phase, 'select');
  assert.equal(q.button('unpin').disabled, true); assert.equal(q.calls.length, 1); q.p.api?.dispose();
});

for (const mode of ['detach', 'dispose', 'reload']) test(`#8224: ${mode} while pending cancels remainder`, async () => {
  let finish;
  const q = page({ setter: (id, remove) => new Promise(resolve => { finish = () => { remove(id); resolve(); }; }) });
  await q.open(); q.click('all'); q.click('unpin'); await settle();
  if (mode === 'detach') q.root().remove();
  else if (mode === 'dispose') q.p.api?.dispose();
  else assert.equal(q.p.reload().error, null);
  finish(); await q.advance(2500);
  assert.deepEqual(q.calls, [['local_a', false]]);
  if (mode === 'reload') assert.equal(q.p.dom.queryAll(ROOT).length, 1);
  q.p.api?.dispose();
});

test('#8224: unavailable store gives visible error; empty valid list is disabled', async () => {
  const q = page({ missing: true }); await q.open();
  assert.equal(q.p.inner.pinBulk.phase, 'error'); assert.match(q.root().textContent, /Не удалось прочитать/);
  q.click('cancel'); assert.equal(q.p.inner.pinBulk.phase, 'closed'); q.p.api?.dispose();
  const empty = page({ ids: [] }); await empty.open();
  assert.match(empty.root().textContent, /Закреплённых чатов Code нет/);
  assert.equal(empty.button('all').disabled, true); assert.equal(empty.button('unpin').disabled, true); empty.p.api.dispose();
});

test('#8224: cancelled discovery cannot reopen selection or alter new-window operation', async () => {
  const q = page(); let resolve;
  q.p.inner.setModuleImporter(() => new Promise(done => { resolve = done; }));
  const before = JSON.stringify(q.p.api.status().newWindow);
  q.click('open'); await settle();
  assert.equal(q.p.inner.pinBulk.phase, 'loading'); q.click('cancel');
  const store = () => {}; store.getState = () => ({ starredIds: ['local_a'], setStarred: () => { throw Error('must not be called'); } });
  resolve({ Star: store }); await settle();
  assert.equal(q.p.inner.pinBulk.phase, 'closed');
  assert.equal(JSON.stringify(q.p.api.status().newWindow), before);
  assert.deepEqual(q.calls, []); q.p.api.dispose();
});

for (const kind of ['reject', 'pending-reject', 'pending-ok', 'hung']) test(`#8224: optimistic remove + ${kind} requires setter settlement and membership together`, async () => {
  let resolve, reject;
  const q = page({ setter: (id, remove) => {
    remove(id);
    if (id !== 'local_a') return;
    if (kind === 'reject') return Promise.reject(Error('server rejected'));
    return new Promise((yes, no) => { resolve = yes; reject = no; });
  } });
  await q.open(); q.click('all'); q.click('unpin'); await settle();
  assert.deepEqual(q.calls, [['local_a', false]], 'optimistic removal alone must not advance');
  assert.equal(q.p.inner.pinBulk.done, 0);
  if (kind === 'pending-reject') reject(Error('late rejection'));
  if (kind === 'pending-ok') resolve();
  await settle(); await q.advance(kind === 'hung' ? 2000 : 100);
  if (kind === 'pending-ok') {
    assert.equal(q.p.inner.pinBulk.phase, 'done'); assert.equal(q.p.inner.pinBulk.done, 3);
  } else {
    assert.equal(q.p.inner.pinBulk.phase, 'error'); assert.deepEqual(q.calls, [['local_a', false]]);
    assert.match(q.root().textContent, /Одинаковое имя · …a/);
  }
  q.p.api.dispose();
});

test('#8224: compact unique/missing labels, distinct suffixes and full ID tooltip', async () => {
  const q = page({ ids: ['local_a', 'local_left-1234', 'local_right-1234'] }); await q.open();
  const labels = [...q.root().querySelectorAll('label')];
  assert.equal(labels[0].textContent, 'Одинаковое имя', 'unique name has no suffix');
  assert.equal(labels[0].getAttribute('title'), 'local_a');
  assert.match(labels[1].textContent, /^Название недоступно · …/);
  assert.notEqual(labels[1].textContent, labels[2].textContent, 'colliding short tails expand');
  assert.equal(labels[1].getAttribute('title'), 'local_left-1234');
  assert.equal(q.root().textContent.includes('local_'), false); q.p.api.dispose();
});

test('#8224: fulfilled optimistic removal after deadline cannot advance on delayed timer delivery', async () => {
  let finish;
  const q = page({ setter: (id, remove) => { remove(id); return new Promise(resolve => { finish = resolve; }); } });
  await q.open(); q.click('all'); q.click('unpin'); await settle();
  const before = q.p.win.performance.now();
  q.p.win.performance.now = () => before + 2100;
  finish(); await settle();
  q.p.dom.fireKind('timeout'); await settle();
  assert.equal(q.p.inner.pinBulk.phase, 'error');
  assert.equal(q.p.inner.pinBulk.done, 0);
  assert.deepEqual(q.calls, [['local_a', false]]);
  assert.match(q.root().textContent, /Не удалось подтвердить/);
  q.p.api.dispose();
});
