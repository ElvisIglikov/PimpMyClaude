// Ряд номеров с прокруткой вбок (WF85, #7356, план К8). Слово Элвиса 24.09:
// «когда workflow много, нужно сделать прокрутку горизонтальную и желательно
// показывать под номер последнего с многоточием… Нельзя же столько по высоте
// занимать». Ряд — одна строка высотой 12; не влез и после слияния «1–k» —
// справа хвост «… N», номера едут translateX под колесом, с пружиной у краёв.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const TAIL = "#myclaude-progress-tail";
const px = (node, name) => Number(node.style.getPropertyValue(name).replace("px", ""));
const barOf = loaded => loaded.dom.query("#myclaude-progress-bar");
const tailOf = loaded => loaded.dom.query(TAIL);
const scrollOf = loaded => plain(loaded.api.status().progress.scroll);
const line = (wf, of = 34, word = "идёт 💭") => `⚪[PimpMyClaude](docs/status.md) · WF ${wf} из ${of} · ${word}`;

// Поле шириной width, редактор на 10 от края рамки: ряд = width − 20.
const narrow = (width, text = line(2)) => loadInject({
  title: "PimpMyClaude", geometry: { viewport: { width: width + 20, height: 800 } },
  html: dom => {
    const parts = dom.composer({ top: 620, left: 10, width });
    const answer = dom.document.body.add("div", {
      attrs: { "data-testid": "assistant-message" },
      rect: { left: 10, top: 200, width, height: 300 },
      text: `Готово.\n\n${text}`,
    });
    return { ...parts, answer };
  },
});
// Ряд 430, 34 номера: 34 × 18 + 33 × 3 = 711; хвост «… 34» — 28; окно номеров
// 430 − 28 − 3 − 3 = 396; предел сдвига 711 − 396 = 315.
const WIDE = 450;
const NEED = 711;
const VIEW = 396;
const MAX = NEED - VIEW;

const wheelCount = loaded => (loaded.document.__listeners?.get("wheel") ?? []).length;
const wheel = (loaded, init, at = null) => {
  const bar = barOf(loaded);
  const point = at ?? { clientX: px(bar, "left") + 50, clientY: px(bar, "top") + 6 };
  return loaded.document.dispatchEvent({ type: "wheel", deltaX: 0, deltaY: 0, deltaMode: 0, ...point, ...init });
};
// Прогнать кадры, пока ряд не встанет (потолок — чтобы не зациклиться).
const settle = loaded => {
  for (let round = 0; round < 200 && loaded.dom.count("raf") > 0; round += 1) loaded.dom.fireKind("raf");
};
// Пружина — таймер 140 мс после последнего колеса.
const springIds = loaded => [...loaded.dom.timers.entries()]
  .filter(([, item]) => item.kind === "timeout" && item.ms === 140).map(([id]) => id);
const release = loaded => {
  for (const id of springIds(loaded)) {
    const item = loaded.dom.timers.get(id);
    loaded.win.clearTimeout(id);
    item.fn();
  }
  settle(loaded);
};
const press = (loaded, x) => loaded.document.dispatchEvent({ type: "pointerdown", clientX: x, clientY: px(barOf(loaded), "top") + 1 });
// Левый край номера index на экране — с учётом сдвига ряда.
const badgeLeft = (loaded, index) => {
  const bar = barOf(loaded);
  let x = px(bar, "left") - scrollOf(loaded).x;
  for (let order = 0; order < index; order += 1) x += px(bar.children[order], "width") + px(bar, "gap");
  return x;
};

test("34 номера в ряду 430: одна строка высотой 12, хвост «… 34», есть куда ехать (К8.1–2)", () => {
  const loaded = narrow(WIDE);
  const bar = barOf(loaded);
  const progress = plain(loaded.api.status().progress);
  assert.equal(progress.badges.length, 34, "слияния нет — готовый впереди один");
  assert.equal(bar.children.length, 34, "номера — дети ряда, как и были");
  assert.equal(bar.style.getPropertyValue("height"), "12px", "ряд одной строкой, высота 12");
  assert.notEqual(bar.style.getPropertyValue("flex-wrap"), "wrap", "не переносится");
  assert.equal(px(bar, "width"), VIEW, "ряд режет окно номеров");
  assert.equal(bar.style.getPropertyValue("overflow"), "clip");
  assert.equal(plain(loaded.api.status().progress).room, 18, "место под ряд прежнее");
  const tail = tailOf(loaded);
  assert.equal(tail.textContent, "…\u202F34", "многоточие, узкий неразрывный пробел, последний номер");
  assert.equal(tail.style.getPropertyValue("display"), "block");
  assert.equal(tail.style.getPropertyValue("position"), "fixed");
  assert.equal(tail.style.getPropertyValue("pointer-events"), "none", "хвост прозрачен для мыши");
  assert.equal(px(tail, "width"), 28);
  assert.equal(px(tail, "left"), px(bar, "left") + 430 - 28, "хвост у правого края ряда");
  assert.equal(px(tail, "top"), px(bar, "top"));
  assert.equal(tail.style.getPropertyValue("box-shadow").startsWith("inset 0 0 0 1px"), true, "вид номера 34 — «впереди», контуром");
  assert.deepEqual(scrollOf(loaded), { x: 0, max: MAX, tail: true, user: false });
  assert.equal(wheelCount(loaded), 1, "в режиме прокрутки слушатель колеса висит");
});

test("вне режима прокрутки: хвоста нет, слушателя колеса нет, scroll по контракту (К8.6, В6)", () => {
  const loaded = narrow(1000, line(3, 8));
  assert.deepEqual(scrollOf(loaded), { x: 0, max: 0, tail: false, user: false });
  assert.equal(tailOf(loaded).style.getPropertyValue("display"), "none");
  assert.equal(wheelCount(loaded), 0, "не-пассивного wheel на документе нет");
  assert.equal(wheel(loaded, { deltaY: 40 }), true, "колесо над рядом — ленте, не нам");
  assert.equal(barOf(loaded).children[0].style.getPropertyValue("transform"), "", "номера не сдвинуты");
});

test("колесо двигает ряд плавно; deltaY и deltaX оба работают, строки ×16 (К8.3)", () => {
  const loaded = narrow(WIDE);
  assert.equal(wheel(loaded, { deltaY: 100 }), false, "колесо над рядом наше: preventDefault");
  assert.equal(loaded.dom.count("raf") > 0, true, "едет кадрами");
  loaded.dom.fireKind("raf");
  const first = scrollOf(loaded).x;
  assert.equal(first > 0 && first < 100, true, `первый кадр — доля пути (${first})`);
  settle(loaded);
  assert.equal(scrollOf(loaded).x, 100);
  assert.equal(scrollOf(loaded).user, true, "последний сдвиг — от колеса");
  assert.equal(barOf(loaded).children[5].style.getPropertyValue("transform"), "translateX(-100px)");
  // Трекпад вбок: deltaX больше deltaY — берётся он.
  wheel(loaded, { deltaX: 50, deltaY: 5 });
  settle(loaded);
  assert.equal(scrollOf(loaded).x, 150, "deltaX");
  wheel(loaded, { deltaX: -2, deltaY: -3, deltaMode: 1 });
  settle(loaded);
  assert.equal(scrollOf(loaded).x, 150 - 48, "три строки назад — 48 точек");
  // Мимо ряда колесо не наше.
  const bar = barOf(loaded);
  assert.equal(wheel(loaded, { deltaY: 40 }, { clientX: px(bar, "left") + 50, clientY: px(bar, "top") - 20 }), true);
  assert.equal(scrollOf(loaded).x, 102);
});

test("за краем — сопротивление и не дальше 32 точек, пружина возвращает в границы (К8.3)", () => {
  const loaded = narrow(WIDE);
  wheel(loaded, { deltaY: -40 });
  settle(loaded);
  assert.equal(scrollOf(loaded).x, -14, "40 за край × 0,35");
  wheel(loaded, { deltaY: -1000 });
  settle(loaded);
  assert.equal(scrollOf(loaded).x, -32, "дальше 32 не тянется");
  release(loaded);
  assert.equal(scrollOf(loaded).x, 0, "140 мс без колеса — пружина к краю");
  assert.equal(barOf(loaded).children[0].style.getPropertyValue("transform"), "", "на нуле сдвига нет");

  wheel(loaded, { deltaY: MAX + 100 });
  settle(loaded);
  assert.equal(scrollOf(loaded).x, MAX + 32, "правый край: тот же потолок");
  assert.equal(scrollOf(loaded).tail, false, "у конца хвост гаснет");
  assert.equal(tailOf(loaded).style.getPropertyValue("opacity"), "0");
  assert.equal(tailOf(loaded).style.getPropertyValue("display"), "block", "слот остаётся — ряд не прыгает");
  release(loaded);
  assert.equal(scrollOf(loaded).x, MAX);
  // Колесо обратно от края идёт без сопротивления — переход через край ровный.
  wheel(loaded, { deltaY: -100 });
  settle(loaded);
  assert.equal(scrollOf(loaded).x, MAX - 100);
  assert.equal(scrollOf(loaded).tail, true);
  assert.equal(tailOf(loaded).style.getPropertyValue("opacity"), "0.85");
});

test("клик по хвосту — плавно к концу, хвост гаснет; клик по номеру после сдвига — ЕГО карточка (К8.5)", () => {
  const loaded = narrow(WIDE);
  const tail = tailOf(loaded);
  assert.equal(press(loaded, px(tail, "left") + 5), false, "клик по хвосту наш");
  assert.equal(plain(loaded.api.status().progress.tip).open, false, "карточку хвост не открывает");
  loaded.dom.fireKind("raf");
  assert.equal(scrollOf(loaded).x > 0 && scrollOf(loaded).x < MAX, true, "едет, а не прыгает");
  settle(loaded);
  assert.deepEqual(scrollOf(loaded), { x: MAX, max: MAX, tail: false, user: false });

  // Номер 30 (индекс 29) после сдвига на 315 стоит в окне — клик открывает его.
  const left = badgeLeft(loaded, 29);
  assert.equal(left > px(barOf(loaded), "left"), true, "номер 30 в окне");
  press(loaded, left + 2);
  const tip = plain(loaded.api.status().progress.tip);
  assert.equal(tip.open, true);
  assert.equal(tip.segment, 29);
  assert.match(tip.card, /^Воркфлоу 30/, "карточка своего номера, сдвиг учтён один раз");
});

test("номер за краем окна не ловится, мимо номеров — ничего; открытая карточка закрывается колесом", () => {
  const loaded = narrow(WIDE);
  wheel(loaded, { deltaY: 100 });
  settle(loaded);
  release(loaded);
  const bar = barOf(loaded);
  // Номер 1 уехал за левый край (его место — левее ряда): клик у левого края
  // ряда попадает в номер 6, видный в окне, а не в спрятанный.
  press(loaded, px(bar, "left") + 1);
  let tip = plain(loaded.api.status().progress.tip);
  assert.equal(tip.open, true);
  assert.notEqual(tip.segment, 0, "уехавший за край номер 1 не ловится");
  assert.equal(badgeLeft(loaded, tip.segment) < px(bar, "left") + 1 + 2, true, "пойман видный номер под курсором");
  // Колесо над рядом закрывает карточку: она стоит, номера уезжают.
  wheel(loaded, { deltaY: 10 });
  assert.equal(plain(loaded.api.status().progress.tip).open, false, "первое колесо закрыло карточку");
  settle(loaded);
  release(loaded);

  // Номер наполовину за правым краем окна — клик правее окна номеров уже хвост.
  const viewRight = px(bar, "left") + px(bar, "width");
  const before = scrollOf(loaded).x;
  press(loaded, viewRight + 2);
  assert.equal(plain(loaded.api.status().progress.tip).open, false, "правее окна — не номер");
  settle(loaded);
  assert.equal(scrollOf(loaded).x > before, true, "а хвост: ряд поехал к концу");
});

test("текущий номер виден сам; колесо 8 с не перебивает (К8.4)", () => {
  const loaded = narrow(WIDE);
  wheel(loaded, { deltaY: 1000 });
  settle(loaded);
  release(loaded);
  assert.equal(scrollOf(loaded).x, MAX);
  // Новый воркфлоу пришёл сразу после колеса — ряд не дёргается.
  loaded.parts.answer.textContent = `Готово.\n\n${line(3)}`;
  loaded.dom.fireKind("interval");
  assert.equal(plain(loaded.api.status().progress).wf, 3);
  settle(loaded);
  // «1–2» слились (23 вместо 18 + 3 + 18): ряд короче, предел 299 — ряд у
  // конца, но к номеру 3 не поехал.
  const max = 23 + 32 * 18 + 32 * 3 - VIEW;
  assert.deepEqual(scrollOf(loaded), { x: max, max, tail: false, user: true }, "8 с после колеса ряд стоит у конца");
  // Прошло 9 с — следующий проход сам показывает номер 3 с соседями.
  loaded.run("(() => { const real = Date.now; Date.now = () => real() + 9000; })()");
  loaded.dom.fireKind("interval");
  settle(loaded);
  assert.equal(scrollOf(loaded).x, 0, "номер 3 с соседом «1–2» слева — в начале ряда");
  assert.equal(scrollOf(loaded).user, false);
  // Своё место не тянет обратно, пока ничего не менялось.
  wheel(loaded, { deltaY: 30 });
  settle(loaded);
  release(loaded);
  loaded.dom.fireKind("interval");
  settle(loaded);
  assert.equal(scrollOf(loaded).x, 30, "тот же номер, то же окно — ряд там, куда его увели");
});

test("ряд влез снова — режим прокрутки снят: сдвиг, хвост и слушатель колеса уходят", () => {
  const loaded = narrow(WIDE);
  wheel(loaded, { deltaY: 60 });
  settle(loaded);
  assert.equal(wheelCount(loaded), 1);
  // Весь марафон «готово» — сливается в один номер и влезает.
  loaded.parts.answer.textContent = `Готово.\n\n${line(34, 34, "готово ✅")}`;
  loaded.dom.fireKind("interval");
  assert.deepEqual(plain(loaded.api.status().progress).badges.map(item => item.n), ["1–34"]);
  assert.deepEqual(scrollOf(loaded), { x: 0, max: 0, tail: false, user: false });
  assert.equal(tailOf(loaded).style.getPropertyValue("display"), "none");
  assert.equal(wheelCount(loaded), 0, "слушатель колеса снят");
  assert.equal(barOf(loaded).children[0].style.getPropertyValue("transform"), "");
  assert.equal(px(barOf(loaded), "width"), 430, "ряд снова во всю ширину");
});

test("повторная инъекция и dispose в режиме прокрутки: один хвост, один слушатель, кадров нет", () => {
  const loaded = narrow(WIDE);
  wheel(loaded, { deltaY: 60 });
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.equal(loaded.dom.queryAll(TAIL).length, 1, "хвост не удвоился");
  assert.equal(wheelCount(loaded), 1, "слушатель колеса — только новой установки");
  assert.deepEqual(scrollOf(loaded), { x: 0, max: MAX, tail: true, user: false }, "новая установка — ряд на своём месте");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(TAIL).length, 0, "dispose унёс хвост");
  assert.equal(wheelCount(loaded), 0);
  assert.equal(loaded.dom.count("raf"), 0, "кадров прокрутки не осталось");
  assert.equal(springIds(loaded).length, 0, "и пружины");
});

test("ряд спрятан (режим чтения) — хвост прячется вместе с ним и слушателя нет", () => {
  const loaded = narrow(WIDE);
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  assert.equal(tailOf(loaded).style.getPropertyValue("display"), "none");
  assert.equal(wheelCount(loaded), 0);
  assert.deepEqual(scrollOf(loaded), { x: 0, max: 0, tail: false, user: false });
  loaded.api.setStage(loaded.api.stages.NORMAL);
  assert.equal(tailOf(loaded).style.getPropertyValue("display"), "block", "поле открыли — хвост вернулся");
  assert.equal(wheelCount(loaded), 1);
});
