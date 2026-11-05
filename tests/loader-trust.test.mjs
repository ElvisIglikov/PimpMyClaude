import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';

const mjs = fs.readFileSync(new URL('../claude-patch/patch-claude.mjs', import.meta.url), 'utf8');
const version = Number(mjs.match(/const LOADER_VERSION = (\d+);/)[1]);
const source = mjs.match(/const LOADER = String\.raw`([\s\S]*?)`;/)[1]
  .replaceAll('${MARK_START}', `/* [MyClaude:v${version}:start] */`)
  .replaceAll('${MARK_END}', `/* [MyClaude:v${version}:end] */`)
  .replaceAll('${LOADER_VERSION}', String(version));

function page(id, url, origin) {
  const listeners = new Map(), calls = [];
  const c = {
    id, url, calls, listeners, isDestroyed: () => false, getURL: () => c.url,
    on: (event, fn) => listeners.set(event, fn),
    insertCSS: async () => { calls.push('css'); return 'key'; }, removeInsertedCSS: async () => {},
  };
  c.owner = { getMediaSourceId: () => `window:${1000 + id}:0` };
  c.mainFrame = { origin, processId: 100 + id, routingId: id,
    executeJavaScript: async code => { calls.push(code); return { kind: 'main', nonce: 'n', working: false }; } };
  return c;
}

function rig(pages, windows = []) {
  const events = new Map(), watches = new Map(), intervals = [], writes = new Map();
  const files = new Map([['claude.json', '{}'], ['claude.css', 'body{}'], ['inject.js', '// inject'],
    ['probe.js', '// probe'], ['command.json', JSON.stringify({ id: '1', action: 'send-text', text: 'private' })]]);
  const context = {
    URL, console: { log() {}, error(e) { throw e; } },
    setTimeout() {}, setInterval: fn => intervals.push(fn),
    require(name) {
      if (name === 'electron') return {
        app: { on: (event, fn) => { const all = events.get(event) || []; all.push(fn); events.set(event, all); },
          whenReady: () => Promise.resolve() },
        BrowserWindow: Object.assign(function () {}, { getAllWindows: () => windows, fromWebContents: c => c.owner }),
        webContents: { getAllWebContents: () => pages },
      };
      if (name === 'node:fs') return {
        readFileSync: name => files.get(path.basename(name)) || '',
        statSync: name => ({ mtimeMs: 1, size: (files.get(path.basename(name)) || '').length }),
        writeFileSync: (name, value) => writes.set(path.basename(name), value),
        watchFile: (name, _, fn) => watches.set(path.basename(name), fn),
      };
      if (name === 'node:os') return { homedir: () => '/fixture' };
      if (name === 'node:path') return path;
      throw new Error(name);
    },
  };
  vm.runInNewContext(source, context);
  for (const c of pages) for (const listener of events.get('web-contents-created') || []) listener({}, c);
  return { watches, intervals, writes, files };
}
const settle = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };

test('Swift and Node loader bytes and versions agree', () => {
  const swift = fs.readFileSync(new URL('../app/Sources/Patcher/Loader.swift', import.meta.url), 'utf8');
  assert.equal(swift.split('#"""\n')[1].split('\n"""#')[0], source);
  const asar = fs.readFileSync(new URL('../app/Sources/Patcher/Asar.swift', import.meta.url), 'utf8');
  assert.match(asar, new RegExp(`static let loaderVersion = ${version}\\b`));
});

test('inject, CSS, probe and private commands reach only trusted Chromium origins', async () => {
  const good = [page(1, 'https://claude.ai/epitaxy', 'https://claude.ai'),
    page(2, 'about:blank', 'https://claude.ai'), page(3, '', 'https://claude.ai')];
  const bad = [page(4, 'about:blank', 'null'), page(5, 'about:blank', 'https://evil.test'),
    page(6, 'https://claude.ai/epitaxy', 'null'), page(7, 'https://claude.ai.evil.test', 'https://evil.test'),
    page(8, 'data:text/html,PRIVATE-DATA', 'https://claude.ai'),
    page(9, 'file:///tmp/view.html', 'https://claude.ai'), page(10, 'devtools://x', 'https://claude.ai'), page(11, 'blob:https://claude.ai/id', 'https://claude.ai')];
  const r = rig([...good, ...bad]);
  r.watches.get('claude.css')();
  r.watches.get('inject.js')();
  r.watches.get('command.json')();
  r.intervals[0]();
  await settle();
  for (const c of good) {
    assert.ok(c.calls.includes('css'));
    assert.ok(c.calls.includes('// inject'));
    assert.ok(c.calls.includes('// probe'));
    assert.ok(c.calls.some(x => x.includes('private')));
  }
  for (const c of bad) assert.deepEqual(c.calls, [], c.url);
  const answer = JSON.parse(r.writes.get('probe-result.json'));
  assert.deepEqual(answer.results.map(x => x.id), [1, 2, 3]);
  for (const entry of answer.results) {
    assert.equal(entry.source.loader, version);
    assert.equal(entry.source.origin, 'https://claude.ai');
  }
  assert.ok(!r.writes.get('status.json').includes('PRIVATE-DATA'));
});

test('navigation during an awaited probe invalidates the answer and later commands', async () => {
  const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
  let finish;
  c.mainFrame.executeJavaScript = () => new Promise(resolve => { finish = resolve; });
  const r = rig([c]);
  r.intervals[0]();
  c.listeners.get('did-start-navigation')({}, 'https://evil.test', false, true);
  c.url = 'https://evil.test'; c.mainFrame.origin = 'https://evil.test';
  finish({ kind: 'main', nonce: 'n', working: false, send: { state: 'sent' } });
  await settle();
  assert.deepEqual(JSON.parse(r.writes.get('probe-result.json')).results, []);
  let called = false;
  c.mainFrame.executeJavaScript = async () => { called = true; };
  r.watches.get('command.json')();
  assert.equal(called, false);
});


test('a same-URL document navigation invalidates an outstanding probe', async () => {
  const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
  let finish;
  c.mainFrame.executeJavaScript = () => new Promise(resolve => { finish = resolve; });
  const r = rig([c]);
  r.intervals[0]();
  c.listeners.get('did-start-navigation')({ isMainFrame: true, isSameDocument: false });
  finish({ kind: 'main', nonce: 'n' });
  await settle();
  assert.deepEqual(JSON.parse(r.writes.get('probe-result.json')).results, []);
});

test('in-document navigation (pushState of the claude.ai router) keeps an outstanding probe answer', async () => {
  for (const fire of [c => c.listeners.get('did-start-navigation')({ isMainFrame: true, isSameDocument: true }),
    c => c.listeners.get('did-start-navigation')({}, 'https://claude.ai/epitaxy', true, true)]) {
    const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
    let finish;
    c.mainFrame.executeJavaScript = () => new Promise(resolve => { finish = resolve; });
    const r = rig([c]);
    r.intervals[0]();
    fire(c);
    finish({ kind: 'main', nonce: 'n' });
    await settle();
    assert.deepEqual(JSON.parse(r.writes.get('probe-result.json')).results.map(x => x.id), [1]);
  }
});

test('CSS inserted across an in-document chat switch stays in the page and is cached', async () => {
  const c = page(1, 'https://claude.ai/epitaxy/a', 'https://claude.ai');
  let finish;
  const removed = [];
  c.insertCSS = () => new Promise(resolve => { finish = resolve; });
  c.removeInsertedCSS = async key => removed.push(key);
  const r = rig([c]);
  r.watches.get('claude.css')();
  c.listeners.get('did-start-navigation')({ isMainFrame: true, isSameDocument: true });
  c.url = 'https://claude.ai/epitaxy/b';
  finish('sheet');
  await settle();
  assert.deepEqual(removed, []);
  r.intervals[0]();
  assert.equal(JSON.parse(r.writes.get('status.json')).webContents[0].css, 'inserted');
});

test('CSS cut by a document navigation drops its cache, so the next apply inserts again', async () => {
  const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
  const r = rig([c]);
  r.watches.get('claude.css')();
  await settle();
  let finish;
  c.removeInsertedCSS = () => new Promise(resolve => { finish = resolve; });
  r.files.set('claude.css', 'body{color:red}');
  r.watches.get('claude.css')();
  c.listeners.get('did-start-navigation')({ isMainFrame: true, isSameDocument: false });
  finish();
  await settle();
  c.removeInsertedCSS = async () => {};
  r.files.set('claude.css', 'body{}');
  c.calls.length = 0;
  r.watches.get('claude.css')();
  await settle();
  assert.deepEqual(c.calls.map(x => (x === 'css' ? x : 'mark')), ['css', 'mark']);
});

test('review: CSS must not cross navigation while old sheet is removed', async () => {
  const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
  const r = rig([c]);
  r.watches.get('claude.css')();
  await settle();
  let finish;
  c.removeInsertedCSS = () => new Promise(resolve => { finish = resolve; });
  r.files.set('claude.css', 'body{color:red}');
  r.watches.get('claude.css')();
  c.listeners.get('did-start-navigation')({}, 'https://evil.test', false, true);
  c.url = 'https://evil.test'; c.mainFrame.origin = 'https://evil.test';
  c.calls.length = 0;
  finish();
  await settle();
  assert.deepEqual(c.calls, []);
});


test('CSS insertion completing after navigation is removed and never cached', async () => {
  const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
  let finish;
  const removed = [];
  c.insertCSS = () => new Promise(resolve => { finish = resolve; });
  c.removeInsertedCSS = async key => removed.push(key);
  const r = rig([c]);
  r.watches.get('claude.css')();
  c.listeners.get('did-start-navigation')({ isMainFrame: true, isSameDocument: false });
  c.url = 'https://evil.test'; c.mainFrame.origin = 'https://evil.test';
  finish('late-style');
  await settle();
  assert.deepEqual(removed, ['late-style']);
  r.intervals[0]();
  assert.equal(JSON.parse(r.writes.get('status.json')).webContents[0].css, 'untouched');
});

test('native window identity belongs to the owner, never to renderer result', async () => {
  const c = page(1, 'about:blank', 'https://claude.ai');
  c.mainFrame.executeJavaScript = async () => ({ kind: 'popout', nonce: 'n', windowId: 999, source: { windowId: 999 } });
  const r = rig([c]); r.intervals[0](); await settle();
  const entry = JSON.parse(r.writes.get('probe-result.json')).results[0];
  assert.equal(entry.source.windowId, 1001);
  assert.equal(entry.result.windowId, 999);
});

test('owner replacement or native ID change during probe invalidates the answer', async () => {
  for (const replacement of [true, false]) {
    const c = page(1, 'about:blank', 'https://claude.ai');
    let finish;
    c.mainFrame.executeJavaScript = () => new Promise(resolve => { finish = resolve; });
    const r = rig([c]); r.intervals[0]();
    if (replacement) c.owner = { getMediaSourceId: () => 'window:1001:0' };
    else c.owner.getMediaSourceId = () => 'window:1002:0';
    finish({ kind: 'popout', nonce: 'n' }); await settle();
    assert.deepEqual(JSON.parse(r.writes.get('probe-result.json')).results, []);
  }
});

test('missing, throwing and malformed owners never invent native IDs', async () => {
  const invalid = [null, { getMediaSourceId() { throw Error('gone'); } },
    ...['window:0:0', 'window:-1:0', 'window:1.5:0', 'window:4294967296:0', 'window:01:0', 'screen:1:0', 'window:12:x'].map(raw => ({ getMediaSourceId: () => raw }))];
  for (const owner of invalid) {
    const c = page(1, 'about:blank', 'https://claude.ai'); c.owner = owner;
    const r = rig([c]); r.intervals[0](); await settle();
    const entry = JSON.parse(r.writes.get('probe-result.json')).results[0];
    assert.ok(entry);
    assert.equal(entry.source.windowId, undefined);
  }
});

test('main claude.ai page hosted as a WebContentsView gets its window ID from the view tree', async () => {
  const main = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai'); main.owner = null;
  const orphan = page(2, 'about:blank', 'https://claude.ai'); orphan.owner = null;
  const win = (id, contentView, destroyed = false) => ({ id, contentView, isDestroyed: () => destroyed,
    getMinimumSize: () => [280, 0], getSize: () => [800, 600], getMediaSourceId: () => `window:${id}:0` });
  const windows = [win(40, { webContents: main, children: [] }, true), win(41, { webContents: {}, children: [] }),
    win(42, { webContents: {}, children: [{ children: [{ webContents: main, children: [] }] }] })];
  const r = rig([main, orphan], windows);
  r.intervals[0]();
  await settle();
  const results = JSON.parse(r.writes.get('probe-result.json')).results;
  assert.equal(results.find(x => x.id === 1).source.windowId, 42);
  assert.equal(results.find(x => x.id === 2).source.windowId, undefined);
});

// #10787 (v9): Electron снимает вставленный лист только как author — user-лист остаётся. Каждое поколение — в @scope
// по метке на <html>; новая метка гасит прежние листы, пустой файл тоже двигает метку.
test('claude.css generations: scoped sheet first, then a growing mark; html and :root become :scope', async () => {
  const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
  const inserted = [];
  c.insertCSS = async text => { inserted.push(text); c.calls.push('css'); return `k${inserted.length}`; };
  const r = rig([c]);
  r.files.set('claude.css', '/* x; html */\nhtml.dark body{color:red}\n:root{--a:1}\n.x, HTML{y:1}\n' +
    '@media (min-width:1px){:root{--b:2}}\n.html-y,html-z,:root-ish,[lang=html]{z:1}\n:not(:root) a{w:1}');
  r.watches.get('claude.css')();
  await settle();
  assert.equal(inserted.length, 1);
  assert.equal(inserted[0], '@scope (html[data-myclaude-css="1"]){\n/* x; html */\n:scope.dark body{color:red}\n' +
    ':scope{--a:1}\n.x, :scope{y:1}\n@media (min-width:1px){:scope{--b:2}}\n.html-y,html-z,:root-ish,[lang=html]{z:1}\n' +
    ':not(:root) a{w:1}\n}\n');
  assert.equal(c.calls[0], 'css');
  assert.match(c.calls[1], /setAttribute\("data-myclaude-css","1"\)/);
  r.files.set('claude.css', 'body{}');
  r.watches.get('claude.css')();
  await settle();
  assert.match(inserted[1], /^@scope \(html\[data-myclaude-css="2"\]\)\{\nbody\{\}\n\}\n$/);
  r.files.set('claude.css', '');
  c.calls.length = 0;
  r.watches.get('claude.css')();
  await settle();
  assert.equal(inserted.length, 2);
  assert.equal(c.calls.length, 1);
  assert.match(c.calls[0], /setAttribute\("data-myclaude-css","3"\)/);
});

test('claude.css mark never goes back: a late answer of an older insert keeps the newer mark', async () => {
  const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
  const r = rig([c]);
  r.watches.get('claude.css')();
  await settle();
  r.files.set('claude.css', 'body{color:red}');
  r.watches.get('claude.css')();
  await settle();
  const marks = c.calls.filter(x => x !== 'css');
  assert.equal(marks.length, 2);
  const attrs = new Map();
  const html = { getAttribute: name => attrs.get(name) ?? null, setAttribute: (name, value) => attrs.set(name, value) };
  for (const code of [marks[1], marks[0]]) vm.runInNewContext(code, { document: { documentElement: html } });
  assert.equal(attrs.get('data-myclaude-css'), '2');
  vm.runInNewContext(marks[0], { document: { documentElement: null } });
});

// Ревью WF294 п. 1 и 7: метку сняла страница или сорвалась её вставка — тик ставит её заново, без жеста пользователя.
test('claude.css mark lost or failed is restored by the tick, and only for trusted pages with a sheet', async () => {
  const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
  const gone = page(2, 'https://claude.ai/epitaxy', 'https://claude.ai');
  const gestures = [];
  c.mainFrame.executeJavaScript = async (code, gesture) => {
    c.calls.push(code);
    if (code.includes('data-myclaude-css')) { gestures.push(gesture); if (gestures.length === 1) throw new Error('frame busy'); }
  };
  const pages = [c, gone];
  const r = rig(pages);
  r.watches.get('claude.css')();
  await settle();
  gone.url = 'https://evil.test'; gone.mainFrame.origin = 'https://evil.test'; gone.calls.length = 0;
  const fresh = page(3, 'https://claude.ai/epitaxy', 'https://claude.ai');
  pages.push(fresh);
  r.intervals[0]();
  assert.equal(JSON.parse(r.writes.get('status.json')).webContents[0].css, 'inserted');
  assert.deepEqual(gestures, [true, false]);
  assert.match(c.calls.at(-1), /setAttribute\("data-myclaude-css","1"\)/);
  for (const other of [gone, fresh]) assert.ok(!other.calls.some(x => x.includes('data-myclaude-css')), other.url);
});

// Ревью WF294 п. 3: старый вызов, закончивший последним, не перетирает запись нового — возврат файла к старому
// тексту вставляет лист заново.
test('claude.css record keeps the newest generation when an older insert finishes last', async () => {
  const c = page(1, 'https://claude.ai/epitaxy', 'https://claude.ai');
  const inserted = [];
  let release;
  c.insertCSS = text => { inserted.push(text); c.calls.push('css');
    return inserted.length === 1 ? new Promise(resolve => { release = () => resolve('k1'); }) : Promise.resolve(`k${inserted.length}`); };
  const r = rig([c]);
  r.files.set('claude.css', 'a{x:1}');
  r.watches.get('claude.css')();
  await settle();
  r.files.set('claude.css', 'b{x:2}');
  r.watches.get('claude.css')();
  await settle();
  release();
  await settle();
  r.files.set('claude.css', 'a{x:1}');
  r.watches.get('claude.css')();
  await settle();
  assert.equal(inserted.length, 3);
  assert.match(inserted[2], /^@scope \(html\[data-myclaude-css="3"\]\)\{\na\{x:1\}/);
});
