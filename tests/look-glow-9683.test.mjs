// #9683 (слово Элвиса 11.10.2026 01:40: «сиреневая слишком переход яркий, вот этот шевелящийся, да и фиолетовый
// тоже. Градиентность надо уменьшить… понижнее переход сделать»; «красный… хотелось бы более интимный»), лист
// docs/43.html: ★1.4 и ★2.4 — «низкое зарево» у «Сиреневой» и «Фиолетовой», ★3.3 — новая «Винная». Рисунок пятен
// — по теме окна (LOOK_THEME_GLOW); у остальных тем и у «Картинки» он прежний. Проверяем настоящим путём: тема и
// живой фон в карте и командой, экран — dom.sheets(), Web Animations — dom.running().
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const CATALOG = JSON.parse(readFileSync(new URL("../claude-patch/themes.json", import.meta.url), "utf8")).themes;
const theme = id => CATALOG.find(item => item.id === id);
const open = map => loadInject({
  title: "Trelvis", storage: { local: { [MAP_KEY]: JSON.stringify(map) } },
  html: dom => { dom.document.body.add("div", { class: "dframe-root" }); },
});
let seq = 0;
const send = (loaded, detail) => loaded.dom.command({
  id: `g9683-${++seq}`, action: "theme", at: "now", scope: "all", title: "Trelvis", ...detail,
});
const layerRules = css => css.split("\n").filter(line => /:is\(\.dframe-root, \.epitaxy-chat-panel:not\(\.dframe-root \*\)\)::(?:before|after) \{ background/.test(line));
const live = scheme => ({ aurora: true, scheme, motion: "live" });

test("«Сиреневая» и «Фиолетовая» — низкое зарево: без лучей, один тон, свет у нижнего края, тише и без поворота", () => {
  for (const id of ["lilac", "violet"]) {
    const loaded = open({ "*": { theme: theme(id), look: live("theme") } });
    const css = loaded.dom.sheets();
    const [before, after] = layerRules(css);
    assert.ok(before && after, id);
    assert.ok(!/conic-gradient/.test(after), `${id}: лучей нет`);
    // Доли: 38·0,7·0,7 и 32·0,7·0,7 — дымка; 30·0,7·2 и 24·0,7·1,8 — полоса у нижнего края.
    assert.match(before, /ellipse 84% 70% at 30% 34%, color-mix\(in oklab, #[0-9a-f]{6} 19%, transparent\)/, id);
    assert.match(before, /ellipse 78% 66% at 72% 68%, color-mix\(in oklab, hsl\(from #[0-9a-f]{6} calc\(h - 16\) s l\) 16%/, `${id}: соседний тон −16°`);
    assert.match(after, /ellipse 46% 19% at 54% 86%, color-mix\(in oklab, hsl\(from #[0-9a-f]{6} calc\(h \+ 16\) s l\) 42%/, id);
    assert.match(after, /ellipse 34% 15% at 26% 88%, color-mix\(in oklab, #[0-9a-f]{6} 30%/, id);
    assert.match(before, /animation-name: myclaude-aurora-calm-a; animation-duration: 34s;/);
    assert.match(after, /animation-name: myclaude-aurora-calm-b; animation-duration: 45s; animation-delay: -17s;/);
    assert.match(css, /@keyframes myclaude-aurora-calm-a \{/);
    assert.ok(!/@keyframes myclaude-aurora-a \{/.test(css), `${id}: прежних кадров нет`);
    assert.ok(!/rotate\((?!0deg)/.test(css.split("\n").filter(line => line.startsWith("@keyframes myclaude-aurora-calm")).join("\n")), "без поворота");
    loaded.api.dispose();
  }
});

test("тихие кадры шагают по 1/30 с, как прежние (34 и 45 ступеней на отрезок)", () => {
  const { inner } = open({});
  const [a, b] = inner.LOOK_AURORA_CALM;
  assert.ok(inner.lookAuroraFrames(a).every(frame => frame.easing === "steps(34, end)"));
  assert.ok(inner.lookAuroraFrames(b).every(frame => frame.easing === "steps(45, end)"));
  assert.equal(inner.LOOK_AURORA_CALM.map(item => item.pseudo).join(), inner.LOOK_AURORA.map(item => item.pseudo).join());
});

test("«Винная» — ровная дымка своих тонов при «Как у темы»; при схеме — тона схемы, рисунок дымки", () => {
  const own = open({ "*": { theme: theme("wine"), look: live("theme") } });
  const [before, after] = layerRules(own.dom.sheets());
  assert.match(before, /ellipse 84% 70% at 30% 34%, color-mix\(in oklab, #e2647c 21%/, "38·0,55");
  assert.match(before, /#d9577a 18%/);
  assert.match(after, /ellipse 74% 72% at 66% 30%, color-mix\(in oklab, #e8707a 17%/);
  assert.match(after, /ellipse 82% 62% at 34% 74%, color-mix\(in oklab, #c96a86 13%/);
  assert.ok(!/conic-gradient/.test(after), "лучей нет");
  assert.match(before, /animation-name: myclaude-aurora-a; animation-duration: 22s;/, "движение прежнее");
  own.api.dispose();
  const scheme = open({ "*": { theme: theme("wine"), look: { aurora: true } } });
  const [first] = layerRules(scheme.dom.sheets());
  assert.match(first, /ellipse 84% 70% at 30% 34%, color-mix\(in oklab, #a47cf0 21%/, "«Фиолетовые сумерки» по умолчанию — свои тона");
  assert.ok(!/#e2647c/.test(first));
  scheme.api.dispose();
});

test("остальные темы и «Картинка» — рисунок прежний, побайтно", () => {
  const { inner } = open({});
  const colors = { accent: "#5b9bff", muted: "#9db1d6", foreground: "#e4ecfb", dark: true };
  for (const scheme of ["violet", "sea", "theme"]) {
    for (const motion of ["live", "still", "image"]) {
      const look = { aurora: true, neon: false, dense: false, scheme, motion };
      assert.equal(inner.lookCss(look, colors, null), inner.lookCss(look, colors), `${scheme}/${motion}`);
      if (motion === "image") assert.equal(inner.lookCss(look, colors, inner.LOOK_THEME_GLOW.lilac), inner.lookCss(look, colors), "картинка одна на все темы");
    }
  }
  const blue = open({ "*": { theme: theme("blue"), look: live("theme") } });
  const [before, after] = layerRules(blue.dom.sheets());
  assert.match(before, /ellipse 52% 42% at 26% 30%, color-mix\(in oklab, #5b9bff 38%/);
  assert.match(after, /conic-gradient\(from 200deg/);
  assert.match(before, /animation-name: myclaude-aurora-a; animation-duration: 22s;/);
  blue.api.dispose();
});

test("«стоит» у «Сиреневой» — тот же тихий рисунок без кадров; «Уменьшить движение» — Web Animations тихих слоёв, смена темы их меняет", () => {
  const still = open({ "*": { theme: theme("lilac"), look: { aurora: true, scheme: "theme" } } });
  const css = still.dom.sheets();
  assert.match(css, /ellipse 46% 19% at 54% 86%/);
  assert.ok(!/@keyframes|animation-name/.test(css));
  still.api.dispose();

  const loaded = open({ "*": { theme: theme("lilac"), look: live("theme") } });
  const anims = () => loaded.dom.running().filter(item => item.options?.pseudoElement);
  loaded.win.__reducedMotion = true;
  loaded.inner.heartbeatTick?.();
  assert.deepEqual(anims().map(item => item.options.duration), [34000, 45000]);
  send(loaded, { theme: theme("blue") });
  loaded.inner.heartbeatTick?.();
  assert.deepEqual(anims().map(item => item.options.duration), [22000, 29000], "тема без своего рисунка — прежние слои");
  assert.match(loaded.dom.sheets(), /@keyframes myclaude-aurora-a \{/);
  loaded.api.dispose();
});
