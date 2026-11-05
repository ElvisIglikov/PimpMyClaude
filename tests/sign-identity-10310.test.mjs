// #10310, контракт К-SIGN: выбор личности для постоянной подписи Claude в patch-claude.mjs — тот же, что
// SignIdentity.choose в приложении. Эталон общий: tests/fixtures/sign-identity/cases.json (его же читает XCTest
// SignIdentity10310Tests). Из сценария берутся только функции выбора — хвост, который сразу ставит патч, не выполняется.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const mjs = fs.readFileSync(new URL('../claude-patch/patch-claude.mjs', import.meta.url), 'utf8');
const start = mjs.indexOf('const SIGN_DEVELOPER_ID');
const fnStart = mjs.indexOf('function chooseSignIdentity', start);
const end = mjs.indexOf('\n}\n', fnStart);
assert.ok(start > 0 && fnStart > start && end > fnStart, 'в patch-claude.mjs нет блока выбора личности');
const { chooseSignIdentity, parseSignIdentities } =
  new Function(`${mjs.slice(start, end + 2)}\nreturn { chooseSignIdentity, parseSignIdentities };`)();

const dir = new URL('./fixtures/sign-identity/', import.meta.url);
const { cases } = JSON.parse(fs.readFileSync(new URL('cases.json', dir), 'utf8'));

test('эталон выбора личности: все случаи', () => {
  assert.ok(cases.length >= 8);
  for (const item of cases) {
    const list = fs.readFileSync(new URL(item.list, dir), 'utf8');
    assert.equal(parseSignIdentities(list).length, item.count, `${item.name}: повторы по SHA-1 не убраны`);
    assert.deepEqual(chooseSignIdentity(list, item.saved), item.expect, item.name);
  }
});

test('своя личность без доверия годится, просроченная и отозванная — нет', () => {
  const local = fs.readFileSync(new URL('local-only.txt', dir), 'utf8');
  assert.deepEqual(parseSignIdentities(local)[0],
    { sha1: 'E6282567E9AC9930B040F0368D3AB8FF783032A6', name: 'PimpMyClaude Local Signing', problem: 'CSSMERR_TP_NOT_TRUSTED' });
  assert.equal(chooseSignIdentity(fs.readFileSync(new URL('unusable.txt', dir), 'utf8'), null), null);
  assert.equal(chooseSignIdentity('', null), null, 'security не ответил — временная подпись');
});

