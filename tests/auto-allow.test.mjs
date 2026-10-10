// WF121: DOM-карточка из tests/auto-allow-roam.test.mjs в 1314f48,
// с прочитанной командой и двумя кнопками. Живой Claude здесь не запускается.
import test from 'node:test';
import assert from 'node:assert/strict';
import { loadInject, loadInner, plain } from './load.mjs';

const ON = 'myclaude.autoAllowOnce';
const JOURNAL = 'myclaude-auto-allow-journal-v2';
const SECRET = 'CONTROL_PRIVATE_VALUE_WF121';
const rect = { width: 400, height: 120, left: 10, top: 100 };
const page = ({ text = 'Allow Claude to run Bash: git status', labels = ['Allow once', 'Always allow'], on = 'true', local = {}, composer = true } = {}) => {
  let clicks = 0;
  const p = loadInject({ href: 'https://claude.ai/epitaxy/local_allow', title: 'Claude',
    storage: { local: { ...(on == null ? {} : { [ON]: on }), 'myclaude-auto-allow-roam': 'off', ...local } },
    html: dom => {
      const parts = composer ? dom.composer({ text: 'Мой черновик' }) : {};
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
const { autoAllowLabel, autoAllowBlockReason } = loadInner().inner;

test('shortcut: только полный известный хвост; Trust сохраняет прежние подписи', () => {
  for (const [raw, clean] of [
    ['Always allow 2', 'Always allow'], ['  Allow\n 1 ', 'Allow'], ['Allow once ⌘⏎', 'Allow once'],
    ['Always allow2⇧Shift⌘Command⏎Enter', 'Always allow'], ['Allow1⏎Enter', 'Allow'],
    ['Trust workspace⌘⏎', 'Trust workspace'], ['Trust this workspace 1', 'Trust this workspace'],
  ]) assert.equal(autoAllowLabel(raw), clean, raw);
  for (const raw of ['Allow once 2 days', 'Allow 1 time and always allow', 'Allow⌘ always', 'Allow 3', 'Allow for this session']) {
    assert.equal(autoAllowLabel(raw), raw, raw);
  }
});

for (const label of ['Allow once', 'Allow', 'Yes, allow', 'Allow1⏎Enter', 'Allow once2⌘Command⏎Enter']) {
  test(`обычная подпись ${label}: один раз жмёт git status, Always рядом не трогает`, () => {
    const p = page({ labels: [label, 'Always allow'] });
    p.tick();
    for (let n = 0; n < 5; n++) p.tick();
    assert.equal(p.clicks(), 1);
    assert.deepEqual(p.parts.buttons.map(b => b.presses), [1, 0]);
    assert.equal(p.aa().blocked, 0);
    assert.equal(p.aa().presses[0].button, autoAllowLabel(label));
    assert.equal(p.parts.editor.textContent, 'Мой черновик');
    assert.equal(p.parts.card.isConnected, true);
    p.api.dispose();
  });
}
for (const label of ['Always allow', 'Allow always', 'Allow for this tool', 'Yes, and switch mode',
  'Allow once and switch', 'Allow once 2 days', 'Allow 1 time and always allow', 'Allow⌘ always', `Allow ${SECRET}`]) {
  test(`закрытый список отклоняет ${label.replace(SECRET, 'unknown')}`, () => {
    const p = page({ labels: [label] }); p.tick();
    assert.equal(p.clicks(), 0);
    assert.equal(p.aa().blockedLog[0].reason, 'no-once');
    p.api.dispose();
  });
}

test('aria-label с иным смыслом и два разовых действия неоднозначны', () => {
  const p = page();
  p.parts.buttons[0].setAttribute('aria-label', 'Always allow'); p.tick();
  assert.equal(p.aa().blockedLog[0].reason, 'no-once');
  p.parts.buttons[0].removeAttribute('aria-label');
  p.parts.buttons[1].textContent = 'Allow'; p.tick();
  assert.equal(p.aa().blockedLog[0].reason, 'ambiguous');
  assert.equal(p.clicks(), 0); p.api.dispose();
});

for (const [input, reason] of [
  ['rm -rf sample', 'deletion'], ['/bin/rm -rf sample', 'deletion'], ['rmdir sample', 'deletion'], ['unlink sample', 'deletion'],
  ['git -C repo branch -D old', 'deletion'], ['git reset --hard', 'deletion'], ['git clean -fd', 'deletion'],
  ['find . -delete', 'deletion'], ['DROP\n TABLE sample', 'deletion'],
  ['git push', 'publication'], ['git -C repo push', 'publication'], ['/usr/bin/git merge branch', 'publication'], ['gh pr merge 7', 'publication'],
  ['npm publish', 'publication'], ['bash tools/release.sh', 'publication'], ['xcrun notarytool submit a', 'publication'],
  ['railway up', 'publication'], ['vercel deploy', 'publication'],
  ['kaspi_payment_create amount', 'money'], ['kaspi', 'money'], ['refund order', 'money'], ['возврат\nденег', 'money'],
  ['cat /project/.env.local', 'credentials'], ['cat /a/pimp-voice.env', 'credentials'], ['security find-password', 'credentials'],
  ['send_message hello', 'external'], ['curl example.test', 'external'],
  ['git status\n/bin/rm sample', 'deletion'], [`git status${' '.repeat(2200)}\nrm sample`, 'deletion'],
]) {
  test(`отказ ${reason}: ${input.slice(0, 65).replace(/\n/g, ' ')}`, () => {
    const p = page({ text: `Allow Claude to run Bash: ${input}` }); p.tick();
    assert.equal(p.clicks(), 0); assert.equal(p.aa().blockedLog[0].reason, reason);
    assert.match(p.document.getElementById('myclaude-auto-allow-toast').textContent, /^Жду тебя:/);
    p.api.dispose();
  });
}
for (const [tool, input, reason] of [
  ['delete_task', '1', 'deletion'], ['mcp__kaspi__payment_create', '1', 'money'],
  ['publish_post', 'sample', 'publication'], ['send_message', 'sample', 'external'],
  ['Read', '/project/.env', 'credentials'],
  ['AskUserQuestion', 'Which option?', 'manual-required'], ['ExitPlanMode', 'Ready to implement', 'manual-required'],
]) {
  test(`инструмент ${tool}: ${reason}`, () => {
    const p = page({ text: `Allow Claude to run ${tool}: ${input}` }); p.tick();
    assert.equal(p.clicks(), 0); assert.equal(p.aa().blockedLog[0].reason, reason); p.api.dispose();
  });
}

test('классификатор разрешает незапрещённые команды без дополнительных метаданных', () => {
  for (const input of ['pwd', 'git status', 'git status --short', 'npm test', 'git commit -m x', 'ssh build-mac pwd', 'scp source build-mac:source']) {
    const request = { tool: 'Bash', text: input, input, readable: true };
    assert.equal(autoAllowBlockReason(request), '');
  }
});

for (const [tool, input] of [
  ['Bash', 'npm test'], ['Bash', 'git commit -m x'], ['Bash', 'ssh build-mac pwd'], ['Bash', 'scp source build-mac:source'],
  ['Bash', 'rg --pre helper pattern .'], ['Bash', 'git diff --output=sample'], ['Bash', 'git diff --ext-diff'],
  ['Bash', 'git log --textconv'], ['Bash', 'python3 -c "print(1)"'], ['Bash', 'node -e "1"'],
  ['Bash', 'sh -c pwd'], ['Bash', '$(pwd)'], ['Bash', 'cat <<EOF\npwd\nEOF'], ['Bash', 'git status\npwd'],
  ['Read', '/project/file.txt'], ['Read', '/project/format-payment.txt'], ['Grep', 'format'], ['Glob', '*.swift'],
  ['Write', '{"path":"/project/a","content":""}'], ['Edit', '/project/file.txt'],
  ['UnknownTool', 'pwd'], ['mcp__workspace__read_file', '/project/file.txt'],
]) {
  test(`разовое разрешение ${tool}: ${input.replace(/\n/g, ' ')}`, () => {
    const p = page({ text: `Allow Claude to run ${tool}: ${input}` });
    p.tick(); p.tick();
    assert.deepEqual(p.parts.buttons.map(b => b.presses), [1, 0]);
    assert.equal(p.aa().blocked, 0);
    assert.equal(p.aa().presses[0].dialog, `${['UnknownTool', 'mcp__workspace__read_file'].includes(tool) ? 'unknown' : tool}:once`);
    p.api.dispose();
  });
}

for (const text of ['Claude wants to run Bash', 'Run command: npm test', 'Allow Claude to run Bash: ', 'x'.repeat(65536)]) {
  test(`нестандартный непустой заголовок (${text.length}): разовый Allow`, () => {
    const p = page({ text }); p.tick();
    assert.deepEqual(p.parts.buttons.map(b => b.presses), [1, 0]);
    assert.equal(p.aa().presses[0].dialog, 'unknown:once'); p.api.dispose();
  });
}
for (const input of ['git push', 'rm -rf sample', 'cat .env', 'kaspi', 'mcp__service__send_message']) {
  test(`нестандартный заголовок сохраняет запреты: ${input}`, () => {
    const p = page({ text: `Permission requested: ${input}` }); p.tick();
    assert.equal(p.clicks(), 0); assert.equal(p.aa().blocked, 1); p.api.dispose();
  });
}

for (const text of ['', ' \n\t ', 'x'.repeat(65537)]) {
  test(`пустой/слишком длинный запрос (${text.length})`, () => {
    const p = page({ text }); p.tick();
    assert.equal(p.clicks(), 0); assert.equal(p.aa().blockedLog[0].reason, 'unreadable'); p.api.dispose();
  });
}

test('соседний ответ и composer не заполняют пустую карточку и не влияют на её категорию', () => {
  const p = page({ text: '' });
  p.document.body.add('div', { text: 'Allow Claude to run Bash: git status' });
  p.parts.editor.textContent = 'Allow Claude to run Bash: git status'; p.tick();
  assert.equal(p.aa().blockedLog[0].reason, 'unreadable');
  p.parts.card.__text = 'Allow Claude to run Bash: git status';
  p.parts.editor.textContent = 'rm -rf sample'; p.tick();
  assert.equal(p.aa().blocked, 1, 'соседний черновик не добавил отказов');
  assert.equal(p.clicks(), 1); p.api.dispose();
});

test('CSS-обрезка, скрытые потомки и прокрутка сохраняют полный текст запроса', () => {
  for (const mutate of [
    p => p.parts.card.add('pre', { text: 'input', attrs: { hidden: '' } }),
    p => p.parts.card.add('pre', { text: 'input', attrs: { 'aria-expanded': 'false' } }),
    p => { p.parts.card.style.textOverflow = 'ellipsis'; },
    p => { p.parts.card.style.webkitLineClamp = '2'; },
    p => { p.parts.card.clientHeight = 20; p.parts.card.scrollHeight = 120; },
    p => { p.parts.card.clientWidth = 20; p.parts.card.scrollWidth = 120; },
  ]) {
    const p = page(); mutate(p); p.tick();
    assert.deepEqual(p.parts.buttons.map(b => b.presses), [1, 0]);
    p.parts.card.add('pre', { text: 'git push', attrs: { hidden: '' } }); p.tick();
    assert.equal(p.clicks(), 1); assert.equal(p.aa().blockedLog[0].reason, 'publication'); p.api.dispose();
  }
});

test('исключение DOM — не нажимать', () => {
  const p = page(); p.parts.card.cloneNode = () => { throw Error('DOM'); }; p.tick();
  assert.equal(p.clicks(), 0); assert.equal(p.aa().blockedLog[0].reason, 'unreadable'); p.api.dispose();
});

test('карточка или кнопка hidden/disabled/disconnected/чужой chat: нет нажатий', () => {
  for (const mutate of [
    p => p.parts.card.remove(), p => { p.parts.card.hidden = true; },
    p => { for (const b of p.parts.buttons) b.disabled = true; },
    p => { for (const b of p.parts.buttons) b.setAttribute('aria-disabled', 'true'); },
    p => { for (const b of p.parts.buttons) b.style.display = 'none'; },
    p => { p.win.location.pathname = '/epitaxy'; p.win.location.href = 'https://claude.ai/epitaxy'; },
  ]) { const p = page(); mutate(p); p.tick(); assert.equal(p.clicks(), 0); p.api.dispose(); }
});

test('off/fresh и битые значения не включают функцию; команда без поля и фокуса сохраняет preview', () => {
  const p = page({ on: null, composer: false });
  p.document.hasFocus = () => false;
  const theme = { id: 'preview', name: 'Preview', type: 'dark', palette: { accent: '#2299ff', background: '#001122', foreground: '#eeffff', sidebar: '#000811', panel: '#00223a', muted: '#88aabb' } };
  p.dom.command({ action: 'theme', id: 'theme', scope: 'window', title: 'Claude', preview: true, theme });
  assert.equal(p.api.status().preview, true);
  assert.equal(p.aa().on, false);
  for (const value of ['true', true, 'false', false, null, undefined, {}, 1, 'TRUE']) {
    p.dom.command({ action: 'auto-allow-once', id: `a-${String(value)}`, on: value });
    assert.equal(p.aa().on, value === 'true' || value === true);
    assert.equal(p.api.status().preview, true);
    p.tick();
  }
  p.dom.command({ action: 'unknown', id: 'unknown' }); assert.equal(p.api.status().preview, true);
  assert.equal(p.aa().switched, 9); assert.equal(p.clicks(), 1);
  p.dom.command({ action: 'expand', id: 'expand' }); assert.equal(p.api.status().preview, false);
  p.api.dispose();
});

test('ошибка storage чтения — off', () => {
  const p = page(); p.win.localStorage.getItem = () => { throw Error('storage'); };
  p.tick(); assert.equal(p.aa().on, false); assert.equal(p.clicks(), 0); p.api.dispose();
});

test('отказ один на запрос/причину, toast 6 секунд и уборка dispose/reinject', () => {
  const p = page({ text: 'Allow Claude to run ExitPlanMode: Ready to implement' }); p.tick(); const toast = p.document.getElementById('myclaude-auto-allow-toast');
  assert.equal(toast.textContent, 'Жду тебя: нужно ручное подтверждение');
  for (let n = 0; n < 5; n++) p.tick();
  assert.equal(p.document.getElementById('myclaude-auto-allow-toast'), toast);
  assert.equal(p.aa().blocked, 1);
  p.dom.fireKind('timeout'); assert.equal(toast.isConnected, false);
  assert.equal(p.reload().error, null); p.inner.setAutoAllowClock(() => 10000000); p.inner.autoAllowCycle();
  assert.equal(p.aa().blocked, 0, 'тот же DOM пережил reinject, повторного тоста нет');
  p.parts.card.__text = 'Allow Claude to run Bash: rm sample'; p.inner.autoAllowCycle();
  assert.equal(p.aa().blocked, 1);
  p.api.dispose(); assert.equal(p.document.getElementById('myclaude-auto-allow-toast'), null);
  p.inner.autoAllowCycle(); assert.equal(p.clicks(), 0);
});

test('ограниченные журналы без input, путей, подписей и toolName; v1 не читается', () => {
  const old = JSON.stringify([{ dialog: SECRET, buttons: [SECRET] }]);
  const p = page({ local: { 'myclaude-auto-allow-journal-v1': old } });
  for (let n = 0; n < 45; n++) {
    p.parts.card.__text = `Allow Claude to run Tool_${SECRET}: token ${SECRET}-${n}`;
    p.parts.buttons[0].textContent = `Allow ${SECRET}`;
    p.parts.buttons[0].setAttribute('aria-label', SECRET); p.tick();
  }
  assert.equal(p.clicks(), 0);
  assert.equal(p.aa().blockedLog.length, 5); assert.equal(p.aa().journal.length, 10);
  assert.equal(p.inner.autoAllowState.blockedLog.length, 10);
  assert.equal(JSON.parse(p.win.localStorage.getItem(JOURNAL)).length, 30);
  assert.equal(p.win.localStorage.getItem('myclaude-auto-allow-journal-v1'), old);
  assert.ok(!JSON.stringify(p.aa()).includes(SECRET)); assert.ok(!p.win.localStorage.getItem(JOURNAL).includes(SECRET));
  p.reload(); assert.ok(!JSON.stringify(p.aa()).includes(SECRET)); p.api.dispose();
});

test('status: порядок полей и отдельный Trust сохранены', () => {
  const p = page();
  assert.deepEqual(Object.keys(p.aa()), ['on', 'switched', 'mutationRuns', 'presses', 'blocked', 'blockedLog', 'journal', 'tickAt', 'roam']);
  assert.deepEqual(Object.keys(p.aa().roam), ['on', 'mode', 'state', 'chat', 'from', 'since', 'roams', 'lastRoam', 'skipped', 'reason', 'waiting', 'unrendered', 'dryRuns', 'disabled']);
  assert.deepEqual(plain(p.api.status().trust), { presses: 0, refused: 0, last: null, root: null });
  p.api.dispose();
});

test('неудачная запись off не оставляет старое true активным до следующей успешной команды', () => {
  const p = page();
  const write = p.win.localStorage.setItem;
  p.win.localStorage.setItem = () => { throw Error('quota'); };
  p.dom.command({ action: 'auto-allow-once', on: false });
  assert.equal(p.win.localStorage.getItem(ON), 'true', 'хранилище осталось прежним');
  assert.equal(p.aa().on, false, 'ошибка записи выключает текущий экземпляр');
  p.tick(); assert.equal(p.aa().blocked, 0);
  p.win.localStorage.setItem = write;
  p.dom.command({ action: 'auto-allow-once', on: true });
  assert.equal(p.aa().on, true); p.api.dispose();
});

test('новый К3 не читает и не пишет legacy-ключ; старая команда сохраняет off/on и preview', () => {
  const legacy = 'myclaude.autoAllow';
  const p = page({ on: null, local: { [legacy]: 'true' } });
  const theme = { id: 'preview', name: 'Preview', type: 'dark', palette: { accent: '#2299ff', background: '#001122', foreground: '#eeffff', sidebar: '#000811', panel: '#00223a', muted: '#88aabb' } };
  p.dom.command({ action: 'theme', id: 'preview', scope: 'window', title: 'Claude', preview: true, theme });
  p.dom.command({ action: 'auto-allow', on: 'true' }); p.tick();
  assert.equal(p.aa().on, false); assert.equal(p.aa().switched, 0); assert.equal(p.clicks(), 0);
  assert.equal(p.win.localStorage.getItem(ON), null);
  assert.equal(p.api.status().preview, true);
  p.dom.command({ action: 'auto-allow-once', on: 'true' }); p.tick();
  p.dom.command({ action: 'auto-allow', on: 'false' });
  assert.equal(p.aa().on, true); assert.equal(p.aa().switched, 1); assert.equal(p.clicks(), 1);
  assert.equal(p.api.status().preview, true);
  p.dom.command({ action: 'auto-allow-once', on: 'false' });
  assert.equal(p.aa().on, false);
  assert.equal(p.win.localStorage.getItem(legacy), 'true');
  assert.equal(p.win.localStorage.getItem(ON), 'false');
  assert.equal(p.reload().error, null); p.inner.autoAllowCycle();
  assert.equal(p.aa().on, false); assert.equal(p.clicks(), 1); p.api.dispose();
});

test('успешный клик не повторяется при reinject, новый запрос той же карточки нажимается', () => {
  const p = page(); p.tick(); assert.equal(p.clicks(), 1);
  assert.equal(p.reload().error, null);
  p.inner.setAutoAllowClock(() => 10000000); p.inner.autoAllowCycle();
  assert.equal(p.clicks(), 1);
  p.parts.card.__text = 'Allow Claude to run Bash: pwd'; p.inner.autoAllowCycle();
  assert.equal(p.clicks(), 2); assert.equal(p.parts.buttons[1].presses, 0);
  p.api.dispose();
});

test('перед кликом повторное чтение отменяет смену запроса/карточки/чата, off и dispose', () => {
  for (const mutate of [
    p => { p.parts.card.__text = 'Allow Claude to run Bash: git push'; },
    p => p.parts.card.remove(),
    p => { p.win.location.pathname = '/epitaxy/local_other'; p.win.location.href = 'https://claude.ai/epitaxy/local_other'; },
    p => p.dom.command({ action: 'auto-allow-once', on: 'false' }),
    p => p.api.dispose(),
    p => { p.parts.buttons[0].disabled = true; },
    p => { p.parts.buttons[0].textContent = 'Always allow'; },
  ]) {
    const p = page();
    const clone = p.parts.card.cloneNode.bind(p.parts.card);
    let reads = 0;
    p.parts.card.cloneNode = deep => { if (++reads === 2) mutate(p); return clone(deep); };
    p.tick(); assert.equal(reads, 2); assert.equal(p.clicks(), 0);
    p.api?.dispose();
  }
});
