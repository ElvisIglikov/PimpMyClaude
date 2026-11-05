// #9998 (слово Элвиса 16.10.2026 20:38: «bypass permission стоит, и всё равно он allow запрашивает… Сделай,
// чтобы автоматом пимп сам нажимал эту штуку»): в чате, который стоит в режиме Bypass permissions, разовое
// «Allow once» жмётся само и при выключенном тумблере (myclaude.autoAllowOnce), тем же тиком раздела 12е:
// тот же список «не жму сам», журнал и плашка, «Always allow» — никогда. Режим чата — кнопка режима под
// полем (раздел 12с¹); карточка закрыла поле — действует последний замер этого же чата.
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadInject, plain } from './load.mjs';

const ON = 'myclaude.autoAllowOnce';
const JOURNAL = 'myclaude-auto-allow-journal-v2';
const rect = { width: 400, height: 120, left: 10, top: 100 };
const page = ({ text = 'Allow Claude to run Bash: git status', labels = ['Allow once', 'Always allow'], on = 'false', mode = 'Bypass permissions' } = {}) => {
  let clicks = 0;
  const p = loadInject({ href: 'https://claude.ai/epitaxy/local_allow', title: 'Claude',
    storage: { local: { ...(on == null ? {} : { [ON]: on }), 'myclaude-auto-allow-roam': 'off' } },
    html: dom => {
      const parts = dom.composer({ text: 'Мой черновик' });
      const chin = parts.modelRow.add('div', { attrs: { 'data-cds': 'ChatComposerChin' } });
      chin.add('button', { text: 'Opus 5.5', attrs: { 'data-testid': 'epitaxy-cds-model-selector' } });
      parts.chin = chin;
      parts.mode = chin.add('button', { text: mode, attrs: { 'aria-haspopup': 'menu' } });
      const card = dom.document.body.add('div', { class: 'epitaxy-approval-card', text, rect });
      const buttons = labels.map(label => {
        const b = card.add('button', { text: label, rect: { width: 100, height: 28 } });
        b.presses = 0;
        b.addEventListener('click', () => { clicks++; b.presses++; });
        return b;
      });
      return { ...parts, card, buttons };
    },
  });
  assert.equal(p.error, null, String(p.error?.stack));
  const clock = { t: 9000000 };
  p.inner.setAutoAllowClock(() => clock.t);
  p.tick = (ms = 700) => { clock.t += ms; p.inner.autoAllowCycle(); };
  p.clicks = () => clicks;
  p.aa = () => plain(p.api.status().autoAllow);
  return p;
};

for (const on of ['false', null]) {
  test(`Bypass permissions, тумблер ${on ?? 'не задан'}: Allow once жмётся сам один раз, Always allow — нет`, () => {
    const p = page({ on });
    assert.equal(p.aa().on, false, 'тумблер выключен');
    assert.equal(p.aa().bypass, true, 'чат в Bypass — видно в status()');
    for (let n = 0; n < 5; n++) p.tick();
    assert.equal(p.clicks(), 1);
    assert.deepEqual(p.parts.buttons.map(b => b.presses), [1, 0]);
    assert.equal(p.aa().presses[0].button, 'Allow once');
    assert.equal(p.aa().presses[0].dialog, 'Bash:once');
    assert.equal(p.parts.editor.textContent, 'Мой черновик', 'черновик цел');
    p.api.dispose();
  });
}

for (const mode of ['Auto mode', 'Ask permissions', 'Accept edits', 'Plan mode']) {
  test(`режим ${mode}, тумблер выключен: не жмёт и не пишет плашек`, () => {
    const p = page({ mode, text: 'Allow Claude to run Bash: rm -rf sample' });
    for (let n = 0; n < 3; n++) p.tick();
    assert.equal(p.clicks(), 0);
    assert.equal(p.aa().bypass, false);
    assert.equal(p.aa().blocked, 0, 'выключено — отказов нет');
    assert.equal(p.document.getElementById('myclaude-auto-allow-toast'), null);
    p.api.dispose();
  });
}

test('тумблер включён — жмёт и вне Bypass, как раньше', () => {
  const p = page({ on: 'true', mode: 'Auto mode' });
  p.tick();
  assert.equal(p.clicks(), 1);
  assert.equal(p.aa().bypass, false);
  p.api.dispose();
});

for (const [input, reason] of [['rm -rf sample', 'deletion'], ['git push', 'publication'], ['kaspi', 'money'],
  ['cat /project/.env', 'credentials'], ['curl example.test', 'external']]) {
  test(`Bypass: тот же список «не жму сам» — ${reason}, журнал и плашка`, () => {
    const p = page({ text: `Allow Claude to run Bash: ${input}` });
    p.tick();
    assert.equal(p.clicks(), 0);
    assert.equal(p.aa().blockedLog[0].reason, reason);
    assert.equal(JSON.parse(p.win.localStorage.getItem(JOURNAL))[0].reason, reason, 'журнал отказов');
    assert.match(p.document.getElementById('myclaude-auto-allow-toast').textContent, /^Жду тебя:/);
    p.api.dispose();
  });
}

test('Bypass: одна «Always allow» без разового — не жмёт (no-once)', () => {
  const p = page({ labels: ['Always allow', 'Deny'] });
  p.tick();
  assert.equal(p.clicks(), 0);
  assert.equal(p.aa().blockedLog[0].reason, 'no-once');
  p.api.dispose();
});

test('Bypass: карточка закрыла поле — действует замер этого чата; другой чат его не наследует', () => {
  const p = page();
  p.parts.card.remove();
  p.tick();
  assert.equal(p.aa().bypass, true, 'замер снят, пока поле на виду');
  // Карточка встала, а строки режима под полем не видно.
  p.parts.mode.remove();
  p.document.body.appendChild(p.parts.card);
  p.tick();
  assert.equal(p.clicks(), 1, 'тот же чат — жмёт по прошлому замеру');
  // Другой чат без строки режима: замер прошлого чата не в счёт.
  p.parts.card.__text = 'Allow Claude to run Bash: pwd';
  p.win.location.pathname = '/epitaxy/local_other';
  p.win.location.href = 'https://claude.ai/epitaxy/local_other';
  p.tick(); p.tick();
  assert.equal(p.aa().bypass, false);
  assert.equal(p.clicks(), 1, 'в другом чате без замера — не жмёт');
  p.api.dispose();
});

test('Bypass сменили на Ask — больше не жмёт; вернули — жмёт новый запрос', () => {
  const p = page();
  p.parts.mode.textContent = 'Ask permissions';
  p.tick();
  assert.equal(p.clicks(), 0);
  assert.equal(p.aa().bypass, false);
  p.parts.mode.textContent = 'Bypass permissions';
  p.tick();
  assert.equal(p.clicks(), 1);
  p.api.dispose();
});

test('Bypass: обход чатов списка слева — только по тумблеру', () => {
  const p = page();
  p.tick();
  assert.equal(p.aa().roam.on, false, 'режим чужого чата странице не известен — обхода нет');
  p.api.dispose();
});
