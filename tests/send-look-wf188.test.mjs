// WF188 (слово Элвиса 09.10 04:00): «оборвалась ракета, начала взлетать, оборвалась.
// Она должна вверху лететь, как раньше, и линию ставить яркую, которая затухнуть
// должна… И все остальные эффекты так же должны красиво работать». Проверяем
// поведение: ракета 1.8 уходит за верхний край окна, линия растёт за ней и тает,
// узел взлёта (и волны) снимается только когда доиграли ВСЕ анимации; отмена и
// отпускание гасят узел счёта таянием снимка, а не обрывом.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const KEY = "myclaude-send-look-v2";
const DIGITS = "myclaude-send-delay-digits";
const ROCKET = "myclaude-send-delay-rocket";
const SEND_RECT = { left: 1070, top: 748, width: 24, height: 24 };
const { inner } = loadInner({ title: "Тест взлёта" });
const { SEND_DELAY_FLY_MS, SEND_DELAY_TRAIL_FADE_MS, SEND_DELAY_FADE_MS } = inner;
const drain = () => new Promise(resolve => setImmediate(resolve));

const page = ({ style = "1.8", size = 100, rect = SEND_RECT } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, hasFocus: true, title: "Тест взлёта",
    storage: { local: { "myclaude-auto-allow-roam": "off", "myclaude-send-delay-seconds": "3", [KEY]: JSON.stringify({ style, size }) } },
    html: dom => {
      const parts = dom.composer({ text: "привет" });
      parts.enters = [];
      parts.editor.addEventListener("keydown", event => {
        if (event.key !== "Enter") return;
        parts.enters.push(event.isTrusted === true ? "trusted" : "synthetic");
        parts.editor.__text = "";
      });
      parts.send = parts.modelRow.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.advance = (times = 1) => { for (let i = 0; i < times; i += 1) loaded.dom.fireKind("timeout"); };
  // Анимации новых узлов кончаются только по команде теста (у стаба — сразу).
  loaded.held = [];
  const make = loaded.document.createElement.bind(loaded.document);
  loaded.document.createElement = (...args) => {
    const node = make(...args);
    const animate = node.animate;
    node.animate = (frames, options) => {
      const anim = animate.call(node, frames, options);
      let resolve;
      anim.finished = new Promise(done => { resolve = done; });
      anim.end = () => { anim.playState = "finished"; resolve(anim); };
      loaded.held.push(anim);
      return anim;
    };
    return node;
  };
  return loaded;
};
const enter = loaded => loaded.document.dispatchEvent({
  type: "keydown", key: "Enter", code: "Enter", target: loaded.parts.editor, isTrusted: true, bubbles: true, cancelable: true,
});
const esc = loaded => loaded.win.dispatchEvent({ type: "keydown", key: "Escape", code: "Escape", target: loaded.parts.editor, isTrusted: true, bubbles: true, cancelable: true });
const rocketAnims = loaded => loaded.held.filter(anim => {
  for (let node = anim.node; node; node = node.parentNode) if (node.id === ROCKET) return true;
  return false;
});
const translateY = transform => Number(/translateY\((-?[\d.]+)px\)/.exec(transform)?.[1]);
const scaleY = transform => Number(/scaleY\(([\d.]+)\)/.exec(transform)?.[1]);

test("1.8: ракета уходит за верхний край окна, линия растёт за ней и тает, узел живёт до конца всех анимаций", async () => {
  const loaded = page();
  enter(loaded);
  loaded.advance(3);
  assert.deepEqual(loaded.parts.enters, ["synthetic"], "отпускание не отправило");
  const node = loaded.document.getElementById(ROCKET);
  assert.ok(node, "взлёта нет");
  assert.equal(node.style.getPropertyValue("position"), "fixed", "взлёт не в своём fixed-слое");
  assert.equal(node.parentNode, loaded.document.body, "взлёт не на body — его снимет перерисовка Claude");
  const anims = rocketAnims(loaded);
  const fly = anims.filter(anim => anim.frames.some(frame => /translateY/.test(frame.transform ?? "")));
  const grow = anims.filter(anim => anim.frames.some(frame => /scaleY/.test(frame.transform ?? "")));
  const fade = anims.filter(anim => anim.frames.some(frame => "opacity" in frame));
  assert.equal(fly.length, 1, "полёта ракеты нет");
  assert.equal(grow.length, 1, "линия не растёт");
  assert.equal(fade.length, 1, "линия не тает");
  // Вверху: центр ракеты уходит выше верхнего края окна, ракета не гаснет в полёте.
  const cy = SEND_RECT.top + SEND_RECT.height / 2;
  const last = fly[0].frames.at(-1);
  assert.ok(-translateY(last.transform) > cy + 13 * 1.5, `ракета не уходит за верх окна: ${last.transform}`);
  assert.ok(fly[0].frames.every(frame => !("opacity" in frame) || frame.opacity > 0.5), "ракета тает посреди полёта — это и был обрыв");
  // Линия растёт ровно за ракетой: доля роста = доля пути на каждом кадре, та же кривая.
  assert.equal(grow[0].options.duration, fly[0].options.duration);
  assert.equal(grow[0].options.easing, fly[0].options.easing);
  const rise = -translateY(last.transform);
  fly[0].frames.forEach((frame, index) => {
    assert.ok(Math.abs(scaleY(grow[0].frames[index].transform) - (-translateY(frame.transform) / rise)) < 0.001, `линия отстала от ракеты на кадре ${index}`);
  });
  // Яркая линия стоит весь полёт и плавно тает после него.
  assert.equal(fade[0].options.duration, SEND_DELAY_FLY_MS + SEND_DELAY_TRAIL_FADE_MS);
  assert.equal(fade[0].frames[0].opacity, 1);
  assert.equal(fade[0].frames[1].opacity, 1);
  assert.ok(Math.abs(fade[0].frames[1].offset - SEND_DELAY_FLY_MS / (SEND_DELAY_FLY_MS + SEND_DELAY_TRAIL_FADE_MS)) < 1e-9, "линия гаснет раньше, чем ракета ушла");
  assert.equal(fade[0].frames.at(-1).opacity, 0, "линия не тает до нуля");
  assert.ok(SEND_DELAY_TRAIL_FADE_MS >= 400, "таяние короче 0,4 с — это рывок, а не затухание");
  // Узел не снимается, пока идёт хоть одна анимация.
  fly[0].end();
  grow[0].end();
  await drain();
  assert.ok(node.isConnected, "взлёт снят, пока линия ещё тает");
  fade[0].end();
  await drain();
  assert.equal(node.isConnected, false, "взлёт не снялся по концу");
  assert.equal(loaded.document.getElementById(ROCKET), null);
  loaded.api.dispose();
});

test("волны 1.1/1.2/1.10: узел снимается только когда доиграли ВСЕ волны, а не последняя в списке", async () => {
  for (const style of ["1.1", "1.2", "1.10"]) {
    const loaded = page({ style });
    enter(loaded);
    loaded.advance(3);
    const node = loaded.document.getElementById(ROCKET);
    assert.ok(node, `${style}: волны нет`);
    const waves = rocketAnims(loaded);
    assert.equal(waves.length, 2, `${style}: две волны`);
    waves.at(-1).end();
    await drain();
    assert.ok(node.isConnected, `${style}: узел снят, пока первая волна ещё идёт`);
    waves[0].end();
    await drain();
    assert.equal(node.isConnected, false, `${style}: не снялся по концу`);
    loaded.api.dispose();
  }
});

test("отмена и отпускание: узел счёта гаснет таянием снимка, а не обрывом; снимок мимо мыши и снимается сам", async () => {
  for (const style of ["1.8", "1.9", "1.4", "1.5"]) {
    for (const how of ["esc", "release"]) {
      const loaded = page({ style });
      enter(loaded);
      loaded.advance(how === "esc" ? 1 : 3);
      if (how === "esc") assert.equal(esc(loaded), false, "Esc ушёл в Claude");
      const real = loaded.document.getElementById(DIGITS);
      assert.equal(real.style.getPropertyValue("display"), "none", `${style}/${how}: узел счёта ловит нажатия после конца`);
      const ghosts = loaded.dom.animations.filter(anim => anim.node.getAttribute?.("aria-hidden") === "true" && !anim.node.id &&
        anim.frames.length === 2 && anim.frames[0].opacity === 1 && anim.frames[1].opacity === 0);
      assert.equal(ghosts.length, 1, `${style}/${how}: таяния нет — узел пропал обрывом`);
      const ghost = ghosts[0].node;
      assert.equal(ghosts[0].options.duration, SEND_DELAY_FADE_MS);
      assert.equal(ghost.style.getPropertyValue("pointer-events"), "none", "снимок ловит мышь");
      assert.equal(ghost.getAttribute("role"), null, "у снимка роль таймера");
      assert.equal(loaded.document.querySelectorAll(`#${DIGITS}`).length, 1, "снимок унёс id");
      await drain();
      assert.equal(ghost.isConnected, false, `${style}/${how}: снимок не снялся по концу`);
      loaded.api.dispose();
    }
  }
});

test("новый счёт поверх тающего снимка снимает снимок сразу; dispose — тоже", () => {
  const loaded = page({ style: "1.9" });
  enter(loaded);
  loaded.advance(1);
  esc(loaded);
  const ghost = loaded.dom.animations.filter(anim => !anim.node.id && anim.frames[1]?.opacity === 0).at(-1)?.node;
  assert.ok(ghost?.isConnected, "снимка нет");
  enter(loaded);
  assert.equal(ghost.isConnected, false, "снимок остался под новым счётом");
  esc(loaded);
  const second = loaded.dom.animations.filter(anim => !anim.node.id && anim.frames[1]?.opacity === 0).at(-1)?.node;
  assert.ok(second?.isConnected && second !== ghost, "второй отмены не видно");
  loaded.api.dispose();
  assert.equal(second.isConnected, false, "dispose оставил снимок");
});

test("«Уменьшить движение» при выбранной ракете — ракета взлетает до конца (WF179); узкая колонка — тоже за верх", () => {
  const loaded = page({ rect: { left: 300, top: 420, width: 22, height: 22 } });
  loaded.win.__reducedMotion = true;
  enter(loaded);
  loaded.advance(3);
  const fly = rocketAnims(loaded).find(anim => anim.frames.some(frame => /translateY/.test(frame.transform ?? "")));
  assert.ok(fly, "ракета не взлетела при «Уменьшить движение»");
  assert.ok(-translateY(fly.frames.at(-1).transform) > 420 + 11 + 13 * 1.5, "в узкой колонке ракета не уходит за верх");
  loaded.api.dispose();
});
