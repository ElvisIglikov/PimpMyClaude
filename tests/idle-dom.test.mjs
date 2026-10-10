import test from 'node:test';
import assert from 'node:assert/strict';
import { loadInject } from './load.mjs';

const page = () => {
  const p = loadInject({ href: 'https://claude.ai/epitaxy/local_idle', title: 'Idle fixture',
    storage: { local: { 'myclaude-auto-allow-roam': 'off' } },
    html: dom => {
      const parts = dom.composer({});
      parts.feed = dom.document.body.add('div', { attrs: { 'data-testid': 'epitaxy-virtual-transcript' } });
      for (let i = 0; i < 100; i++) {
        const row = parts.feed.add('div', { attrs: { 'data-testid': 'transcript-row', 'data-perf-row': 'assistant_text' } });
        row.add('h3', { text: 'Ответ ' + i });
        row.add('p', { text: 'Текст ответа '.repeat(20) });
      }
      return parts;
    },
  });
  assert.equal(p.error, null);
  let t = Date.now();
  p.win.performance.now = () => t;
  p.beat = ({ frames = true } = {}) => {
    t += 500;
    p.inner.heartbeatTick();
    if (frames) { p.dom.fireKind('timeout'); p.dom.fireKind('raf'); }
  };
  p.changed = target => p.inner.onMutated([{ type: 'childList', target, addedNodes: [target] }]);
  for (let i = 0; i < 4; i++) p.beat();
  return p;
};
const addPhrase = p => {
  const row = p.parts.feed.add('div', { attrs: { 'data-testid': 'transcript-row', 'data-perf-row': 'assistant_text' } });
  const head = row.add('h3', { text: 'Обычный заголовок' });
  const word = row.add('p').add('strong', { text: '«чисти»' });
  return { row, head, word };
};

test('F09: idle DOM budget, 100 ответов / 20 тиков; страховочный проход раз в 5 с', () => {
  const p = page();
  const layouts = p.api.status().layoutRuns;
  const q = p.dom.queries();
  for (let i = 0; i < 20; i++) p.beat();
  const queries = p.dom.queries() - q;
  assert.ok(queries < 2000, `idle queries=${queries}; baseline до dirty gate >10000`);
  assert.equal(p.api.status().layoutRuns - layouts, 2);
  p.api.dispose();
});

test('F09: новый ответ и characterData будят разметку фраз на ближайшем тике', () => {
  const p = page();
  const { row, head, word } = addPhrase(p);
  p.changed(row); p.beat();
  assert.equal(word.hasAttribute('data-myclaude-say'), false);
  head.textContent = '❗ Скажи — и сделаю ❗';
  p.inner.onMutated([{ type: 'characterData', target: head, addedNodes: [] }]);
  p.beat();
  assert.equal(word.hasAttribute('data-myclaude-say'), true);
  p.document.dispatchEvent({ type: 'click', target: word, detail: 1, isTrusted: true });
  assert.equal(p.api.status().say.armed, true);
  p.win.location.href = 'https://claude.ai/epitaxy/local_other';
  p.win.location.pathname = '/epitaxy/local_other';
  p.beat();
  assert.equal(p.api.status().say.armed, false);
  p.api.dispose();
});

test('F09: поле и resize сохраняют раскладку, скрытое окно доводит её без rAF', () => {
  const p = page();
  let before = p.api.status().layoutRuns;
  p.parts.editor.textContent = 'новый черновик';
  p.document.dispatchEvent({ type: 'input', target: p.parts.editor });
  p.beat();
  assert.ok(p.api.status().layoutRuns > before);
  p.document.hidden = true;
  before = p.api.status().layoutRuns;
  p.win.dispatchEvent({ type: 'resize' });
  p.beat({ frames: false });
  assert.ok(p.api.status().layoutRuns > before);
  const { row, head, word } = addPhrase(p);
  head.textContent = '❗ Скажи — и сделаю ❗';
  p.changed(row); p.beat({ frames: false });
  assert.equal(word.hasAttribute('data-myclaude-say'), true);
  p.api.dispose();
});

// Авто-Trust работает из общего цикла мутаций и при выключенном Auto-Allow.
test('F09: новый диалог Trust в скрытом окне обрабатывается прямо из observer', () => {
  const p = page();
  p.document.hidden = true;
  p.win.localStorage.setItem('myclaude-trust-root-v1', '/Users/dev/Projects/');
  const dialog = p.document.body.add('div', { attrs: { role: 'dialog' } });
  dialog.add('h2', { text: 'Trust this workspace?' });
  dialog.add('div', { attrs: { class: 'text-code' }, text: '/Users/dev/Projects/PimpMyClaude' });
  const trust = dialog.add('button', { text: 'Trust workspace', rect: { width: 120, height: 24 } });
  let clicks = 0;
  trust.addEventListener('click', () => { clicks++; });
  p.changed(dialog);
  assert.equal(clicks, 1);
  assert.equal(p.api.status().trust.presses, 1);
  p.api.dispose();
});

test('F09: clock label text mutations не будят тяжёлые проходы; структурная замена будит (плашки голоса нет с 01.10)', () => {
  const p = page();
  p.parts.editor.textContent = 'занятый черновик';
  p.dom.command({ id: 'queued', action: 'send-text', chat: 'local_idle', text: 'голосовая фраза' });
  assert.equal(p.document.getElementById('myclaude-send-queue'), null, 'плашки очереди голоса нет');
  const clock = p.document.getElementById('myclaude-corner').children[2];
  const text = p.document.createTextNode('01:23');
  // Команда и поле ввода сами помечают страницу грязной — дать проходам улечься.
  p.changed(p.parts.editor); p.beat(); p.beat();
  const before = p.api.status().layoutRuns;
  const q = p.dom.queries();
  for (let i = 0; i < 8; i++) {
    p.inner.onMutated([{ type: 'childList', target: clock, addedNodes: [text], removedNodes: [] }]);
    p.beat();
  }
  assert.equal(p.api.status().layoutRuns, before, '4 s собственных тиков не запускают layout');
  assert.ok(p.dom.queries() - q < 1000);
  // Удаление cornerClock приходит на родителя, а не на отфильтрованный label.
  const parent = clock.parentNode;
  clock.remove();
  p.inner.onMutated([{ type: 'childList', target: parent, addedNodes: [], removedNodes: [clock] }]);
  p.beat();
  assert.ok(p.api.status().layoutRuns > before);
  p.api.dispose();
});
