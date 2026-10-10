// WF147 (#9108, слово Элвиса 08.10 22:27): звук обратного отсчёта синхронно с цифрами.
// На показе каждой цифры — короткий тихий звук (kind "step"), на отпускании — свой
// завершающий ("done"); отмена — тишина. Выбор — localStorage["myclaude-send-delay-sound"]
// (bell|tick|drop|retro|off), ставит его команда send-delay полем sound; нет/мусор — bell.
// AudioContext — заглушка теста: один на страницу, лениво, suspended → resume.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const SOUND_KEY = "myclaude-send-delay-sound";
const SEND_RECT = { left: 1070, top: 748, width: 24, height: 24 };

// Заглушка WebAudio: пишет, какие источники запущены и когда (по «сейчас» контекста).
const audioStub = log => {
  const param = () => ({ setValueAtTime() {}, linearRampToValueAtTime() {}, exponentialRampToValueAtTime() {} });
  const node = extra => ({ connect() {}, ...extra });
  return class FakeAudioContext {
    constructor() {
      log.contexts += 1;
      this.state = "suspended";
      this.currentTime = 0;
      this.sampleRate = 8000;
      this.destination = node({});
    }
    resume() { log.resumes += 1; this.state = "running"; return Promise.resolve(); }
    close() { log.closed += 1; this.state = "closed"; return Promise.resolve(); }
    createGain() { return node({ gain: param() }); }
    createBiquadFilter() { return node({ type: "", frequency: param(), Q: param() }); }
    createOscillator() {
      return node({ type: "", frequency: param(), start: () => { log.starts += 1; log.voices.push("osc"); }, stop() {} });
    }
    createBuffer(channels, length) { const data = new Float32Array(length); return { getChannelData: () => data }; }
    createBufferSource() {
      return node({ buffer: null, start: () => { log.starts += 1; log.voices.push("noise"); }, stop() {} });
    }
  };
};

const page = ({ local = {}, hidden = false, audio = true } = {}) => {
  const log = { contexts: 0, resumes: 0, closed: 0, starts: 0, voices: [] };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Тест звука",
    storage: { local: { "myclaude-auto-allow-roam": "off", "myclaude-send-delay-seconds": "3", ...local } },
    html: dom => {
      if (audio) dom.window.AudioContext = audioStub(log);
      dom.document.hidden = hidden;
      const parts = dom.composer({ text: "привет" });
      parts.enters = [];
      parts.editor.addEventListener("keydown", event => {
        if (event.key !== "Enter") return;
        parts.enters.push(event.isTrusted === true ? "trusted" : "synthetic");
        parts.editor.__text = "";
      });
      parts.send = parts.modelRow.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: SEND_RECT });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.log = log;
  loaded.advance = (times = 1) => { for (let i = 0; i < times; i += 1) loaded.dom.fireKind("timeout"); };
  return loaded;
};
const enter = (loaded, extra = {}) => loaded.document.dispatchEvent({
  type: "keydown", key: "Enter", code: "Enter", target: loaded.parts.editor, isTrusted: true,
  bubbles: true, cancelable: true, ...extra,
});
const esc = loaded => loaded.win.dispatchEvent({
  type: "keydown", key: "Escape", code: "Escape", target: loaded.parts.editor, isTrusted: true,
  bubbles: true, cancelable: true,
});
const sound = loaded => plain(loaded.api.status().sendDelay.sound);
const digitText = loaded => loaded.document.getElementById("myclaude-send-delay-digits")?.textContent;

test("звук на каждой цифре 3-2-1 ровно в момент смены и завершающий на отпускании (bell по умолчанию)", () => {
  const p = page();
  assert.equal(p.log.contexts, 0, "AudioContext создан до первого отсчёта");
  assert.equal(sound(p).id, "bell");
  enter(p);
  assert.equal(digitText(p), "3");
  assert.equal(p.log.contexts, 1, "контекст не создан лениво на первом звуке");
  assert.equal(p.log.resumes, 1, "suspended не разбужен");
  assert.deepEqual(sound(p).last, { id: "bell", kind: "step" });
  assert.equal(sound(p).played, 1);
  for (const [left, played] of [["2", 2], ["1", 3]]) {
    p.advance();
    assert.equal(digitText(p), left);
    assert.equal(sound(p).played, played, `на цифре ${left} звука нет или он лишний`);
    assert.deepEqual(sound(p).last, { id: "bell", kind: "step" });
  }
  p.advance();
  assert.deepEqual(p.parts.enters, ["synthetic"]);
  assert.equal(sound(p).played, 4);
  assert.deepEqual(sound(p).last, { id: "bell", kind: "done" }, "на отпускании не завершающий звук");
  // Второй отсчёт — тот же контекст.
  p.parts.editor.__text = "ещё";
  enter(p);
  assert.equal(p.log.contexts, 1, "AudioContext создан второй раз");
  p.api.dispose();
  assert.equal(p.log.closed, 1, "dispose не закрыл AudioContext");
});

test("каждый звук из набора играет: tick (шум), drop, retro; off — тишина", () => {
  for (const id of ["tick", "drop", "retro"]) {
    const p = page({ local: { [SOUND_KEY]: id } });
    enter(p);
    p.advance(3);
    assert.equal(sound(p).id, id);
    assert.equal(sound(p).played, 4, id);
    assert.deepEqual(sound(p).last, { id, kind: "done" });
    assert.ok(p.log.starts >= 4, `${id}: источники не запущены`);
    if (id === "tick") assert.ok(p.log.voices.includes("noise"), "тик без шума");
    p.api.dispose();
  }
  const off = page({ local: { [SOUND_KEY]: "off" } });
  enter(off);
  off.advance(3);
  assert.deepEqual(off.parts.enters, ["synthetic"], "без звука отсчёт сломался");
  assert.equal(off.log.contexts, 0, "«Без звука» всё равно создал AudioContext");
  assert.equal(sound(off).played, 0);
  off.api.dispose();
});

test("мусор в ключе — умолчание bell", () => {
  for (const junk of ["", "BELL", "bell ", "{}", "loud"]) {
    const p = page({ local: { [SOUND_KEY]: junk } });
    assert.equal(sound(p).id, "bell", JSON.stringify(junk));
    enter(p);
    assert.deepEqual(sound(p).last, { id: "bell", kind: "step" });
    p.api.dispose();
  }
});

test("отмена Esc и кликом — тишина: ни завершающего, ни следующих звуков", () => {
  const p = page();
  enter(p);
  assert.equal(sound(p).played, 1);
  esc(p);
  p.advance(5);
  assert.equal(sound(p).played, 1, "после Esc прозвучало ещё");
  assert.deepEqual(p.parts.enters, []);

  enter(p);
  assert.equal(sound(p).played, 2);
  const digits = p.document.getElementById("myclaude-send-delay-digits");
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
    p.document.dispatchEvent({ type, target: digits, isTrusted: true, bubbles: true, cancelable: true });
  }
  assert.equal(p.api.status().sendDelay.counting, false);
  p.advance(5);
  assert.equal(sound(p).played, 2, "после клика по цифре прозвучало ещё");
  assert.deepEqual(sound(p).last, { id: "bell", kind: "step" });
  p.api.dispose();
});

test("скрытое окно — счёт идёт, звука нет и AudioContext не создаётся", () => {
  const p = page({ hidden: true });
  enter(p);
  p.advance(3);
  assert.deepEqual(p.parts.enters, ["synthetic"]);
  assert.equal(sound(p).played, 0);
  assert.equal(p.log.contexts, 0);
  p.api.dispose();
});

test("отсчёт выключен — Enter уходит сразу и молча", () => {
  const p = page({ local: { "myclaude-send-delay-off": "1" } });
  enter(p);
  p.advance(3);
  assert.equal(sound(p).played, 0);
  assert.equal(p.log.contexts, 0);
  p.api.dispose();
});

test("нет WebAudio — отсчёт работает, звук молча пропущен", () => {
  const p = page({ audio: false });
  enter(p);
  p.advance(3);
  assert.deepEqual(p.parts.enters, ["synthetic"]);
  assert.equal(sound(p).played, 0);
  p.api.dispose();
});

test("⇧Enter во время счёта (явное «сразу») — сразу и с завершающим звуком", () => {
  const p = page({ local: { "myclaude-send-delay-shift": "send" } });
  enter(p);
  enter(p, { shiftKey: true });
  assert.deepEqual(p.parts.enters, ["synthetic"]);
  assert.equal(sound(p).played, 2);
  assert.deepEqual(sound(p).last, { id: "bell", kind: "done" });
  p.api.dispose();
});

test("смена чата во время счёта — дальше тишина", () => {
  const p = page();
  enter(p);
  p.win.location.pathname = "/epitaxy/local_bbbb-2222";
  p.win.location.href = "https://claude.ai/epitaxy/local_bbbb-2222";
  p.advance(5);
  assert.equal(sound(p).played, 1, "после смены чата прозвучало ещё");
  assert.deepEqual(p.parts.enters, []);
  p.api.dispose();
});

test("команда send-delay полем sound: пишет выбор, bell снимает ключ, мусор не берётся, секунды не трогает", () => {
  const p = page();
  const cmd = (id, extra) => p.dom.command({ id, action: "send-delay", at: "2026-10-08T22:30:00Z", ...extra });
  cmd("s1", { sound: "retro" });
  assert.equal(p.win.localStorage.getItem(SOUND_KEY), "retro");
  assert.equal(p.win.localStorage.getItem("myclaude-send-delay-seconds"), "3");
  assert.equal(sound(p).id, "retro");
  cmd("s2", { sound: "kazoo" });
  assert.equal(p.win.localStorage.getItem(SOUND_KEY), "retro", "мусор переписал выбор");
  cmd("s3", { sound: "off" });
  assert.equal(sound(p).id, "off");
  cmd("s4", { sound: "bell" });
  assert.equal(p.win.localStorage.getItem(SOUND_KEY), null, "bell — умолчание, ключ должен сниматься");
  assert.equal(sound(p).id, "bell");
  cmd("s5", { on: true, seconds: 5, sound: "drop" });
  assert.equal(p.win.localStorage.getItem("myclaude-send-delay-seconds"), "5");
  assert.equal(sound(p).id, "drop");
  p.api.dispose();
});

test("показ вида (send-look preview) слышен как настоящий счёт: цифры + финал, ничего не отправлено", () => {
  const p = page();
  p.dom.command({ id: "look-1", action: "send-look", at: "2026-10-08T22:31:00Z", style: "1.5", size: 100, preview: true, seconds: 3, match: `/epitaxy/${CHAT}` });
  assert.equal(p.api.status().sendDelay.look.preview, true);
  assert.equal(sound(p).played, 1);
  p.advance(3);
  assert.equal(sound(p).played, 4);
  assert.deepEqual(sound(p).last, { id: "bell", kind: "done" });
  assert.deepEqual(p.parts.enters, []);
  p.api.dispose();
});
