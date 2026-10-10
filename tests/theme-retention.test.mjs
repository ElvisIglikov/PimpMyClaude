import test from 'node:test';
import assert from 'node:assert/strict';
import { loadInject } from './load.mjs';
const KEY = 'myclaude-themes-v1';
const read = p => JSON.parse(p.win.localStorage.getItem(KEY) ?? '{}');
const open = (entries = {}) => loadInject({ title: 'Current', href: 'https://claude.ai/epitaxy/local_current', storage: { local: { [KEY]: JSON.stringify(entries) } } });
const oldEntries = n => Object.fromEntries(Array.from({ length: n }, (_, i) => [`id:local_old_${i}`, { font: 'none', at: 1000 + i }]));

const inventory = async (p, rows = []) => {
  const popoutWindows = p.run(`new Map(${JSON.stringify(rows)})`);
  const Store = () => {};
  Store.getState = () => ({ popoutWindows, openPopout() {} });
  p.dom.modules('https://claude.ai/assets/v1/chunk-1.js');
  p.inner.setModuleImporter(() => Promise.resolve({ Store }));
  assert.equal(await p.inner.chatsScan(), 'ok');
};

test('F11: saved/used at — реальные миллисекунды; текущий вид и недавно использованный ранний ключ сохраняются', async () => {
  const start = Date.now();
  const entries = { ...oldEntries(210), 'id:local_aaa_recent': { font: 'none', at: start - 100 },
    'id:local_current': { font: { id: 'Menlo', family: 'Menlo' }, at: 1 },
    'chat:Current': { font: { id: 'Menlo', family: 'Menlo' }, by: 'local_current', at: 1 },
    '*': { size: 'none' }, main: { frame: 'none' } };
  const p = open(entries);
  assert.equal(p.error, null);
  assert.ok(Object.keys(read(p)).length > 200, 'до inventory глобальная уборка отложена');
  await inventory(p);
  let map = read(p);
  assert.ok(Object.keys(map).length <= 200);
  assert.ok(map['id:local_aaa_recent']);
  assert.ok(map['id:local_current'].at >= start);
  assert.ok(map['chat:Current'].at >= start);
  assert.ok(map['*']); assert.ok(map.main);
  assert.equal(p.api.status().font.id, 'Menlo');
  const initial = p.win.localStorage.getItem(KEY);
  p.inner.touchThemeMap();
  assert.equal(p.win.localStorage.getItem(KEY), initial, 'use не пишет повторно в ту же минуту');
  p.dom.command({ id: 'font', action: 'theme', scope: 'window', title: 'Current', font: { id: 'Monaco', family: 'Monaco' } });
  map = read(p);
  assert.equal(map['id:local_current'].font.id, 'Monaco');
  assert.ok(map['id:local_current'].at >= start);
  p.api.dispose();
});

test('F11: вытеснение идёт группами известных владельцев; legacy без by не приписывается тёзке', async () => {
  const p = open();
  await inventory(p);
  const map = { ...oldEntries(198), 'id:local_drop': { font: 'none', at: 1 },
    'chat:Twin': { font: 'none', by: 'local_drop', at: 1 },
    'w:Twin': { font: 'none', at: Date.now() } };
  p.win.localStorage.setItem(KEY, JSON.stringify(map));
  p.inner.writeThemeMap(p.inner.readThemeMap(), false);
  const kept = read(p);
  assert.equal(kept['id:local_drop'], undefined);
  assert.equal(kept['chat:Twin'], undefined);
  assert.ok(kept['w:Twin']);
  assert.equal(Object.keys(kept).length, 199);
  p.api.dispose();
});

test('F11: restore сохраняет возраст архива и не омолаживает неизменённую запись', () => {
  const p = open({ 'id:local_archive': { font: 'none', at: 1234 } });
  p.dom.command({ id: 'restore', action: 'themes-restore', scope: 'all', entries: {
    'id:local_archive': { font: 'none', size: 'none', at: 9999 },
    'id:local_import': { font: 'none', at: 4321 },
    'id:local_unknown': { font: 'none' },
  } });
  const map = read(p);
  assert.equal(map['id:local_archive'].at, 1234);
  assert.equal(map['id:local_import'].at, 4321);
  assert.equal(map['id:local_unknown'].at, undefined);
  p.api.dispose();
});

test('F11: stale snapshot сохраняет свежие ключи и чужие слои до retention', () => {
  const p = open({ 'id:local_other': { font: 'none', at: 1 } });
  const snapshot = p.inner.readThemeMap();
  snapshot['id:local_other'].size = 'none';
  const latest = read(p);
  latest['id:local_other'].font = { id: 'Monaco', family: 'Monaco' };
  latest['id:local_added'] = { font: 'none', at: Date.now() };
  p.win.localStorage.setItem(KEY, JSON.stringify(latest));
  p.win.dispatchEvent({ type: 'storage', key: KEY, newValue: JSON.stringify(latest) });
  p.inner.writeThemeMap(snapshot);
  const result = read(p);
  assert.equal(result['id:local_other'].font.id, 'Monaco');
  assert.equal(result['id:local_other'].size, 'none');
  assert.ok(result['id:local_added']);
  assert.ok(result['id:local_other'].at >= latest['id:local_added'].at);
  p.api.dispose();
});

test('F11: startup до inventory сохраняет старый открытый B; после scan уборка защищает B и тень', async () => {
  const entries = { ...oldEntries(205), 'id:local_open': { font: 'none', at: 1 }, 'chat:Open': { font: 'none', by: 'local_open', at: 1 } };
  const p = open(entries);
  assert.equal(Object.keys(read(p)).length, 207);
  assert.ok(read(p)['id:local_open']);
  await inventory(p, [['local_open', { title: 'Open' }]]);
  assert.ok(read(p)['id:local_open']);
  assert.ok(read(p)['chat:Open']);
  assert.ok(Object.keys(read(p)).length <= 200);
  p.api.dispose();
});

test('F11: popout сохраняет выбор, но не вытесняет архив без inventory главного окна', () => {
  const entries = oldEntries(205);
  const p = loadInject({ title: 'Popup', href: 'about:blank', storage: { local: { [KEY]: JSON.stringify(entries) } } });
  p.dom.command({ id: 'font', action: 'theme', scope: 'window', title: 'Popup', font: { id: 'Monaco', family: 'Monaco' } });
  const map = read(p);
  assert.equal(Object.keys(map).length, 206);
  assert.equal(map['chat:Popup'].font.id, 'Monaco');
  assert.ok(map['chat:Popup'].at > 0);
  p.api.dispose();
});


test('F11: один logical save даёт id и тени один at при постоянно меняющихся часах', () => {
  const p = open();
  p.run('Date.now = (() => { let t = 1800000000000; return () => ++t; })()');
  const layers = { font: { id: 'Monaco', family: 'Monaco' } };
  p.inner.newWindowPaintChat('local_new', 'New', 'New', layers);
  const first = read(p);
  assert.equal(first['id:local_new'].at, first['chat:New'].at);
  p.inner.newWindowPaintChat('local_new', 'New', 'New', layers);
  const next = read(p);
  assert.equal(next['id:local_new'].at, next['chat:New'].at, 'повторный выбор тех же слоёв тоже одна операция');
  assert.ok(next['id:local_new'].at > first['id:local_new'].at);
  p.api.dispose();
});
