// status() из файлов-разделов (WF248 П4): поле регистрирует файл своей фичи (statusPart), порядок полей —
// прежний, до разреза страницы (STATUS_ORDER раздела 17). Поле новой фичи встаёт в конец само; переставить,
// переименовать или снять старое — поправить и список ниже, и STATUS_ORDER. Четыре поля читает приложение
// (ChatProbe.swift): cashout, newWindow, send, attention.want — их вид закреплён здесь же.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const ORDER = [
  "version", "url", "stage", "height", "ceiling", "natural", "cssOk", "cssViolations", "watching", "editor", "shell",
  "composerBlock", "composerFont", "composerImageUndo", "attachUndo", "modelRow", "collapsedNodes", "hideTools",
  "cleanAnswers", "pinnedLook", "jumps", "escapesBlocked", "handleVisible", "superVisible", "superBottomVisible",
  "handleCovered", "mic", "gallery", "pmp", "wide", "restored", "autoAllow", "trust", "layout", "run", "send",
  "sendDelay", "corner", "head", "htmlChrome", "photo", "bypassChats", "mention", "openInChrome", "usage", "limits",
  "working", "autoContinue", "layoutRuns", "mutationBatches", "mutationSkipped", "scrollRuns", "timeRuns",
  "timeWatched", "cashout", "progress", "statusFeed", "workflow", "newWindow", "continue", "chat", "restore",
  "chatKey", "sessionKey", "theme", "font", "size", "wait", "attention", "dim", "say", "nazh", "folds", "userFold", "read",
  "seen", "heic", "chapters", "work", "signal", "look", "lookStill", "scrollFades", "live", "preview",
  "raw", "rawMain", "dragStrip",
  "attachDup", "composerScroll", "ourLinks", "externalLinks", "autoRetry", "contextRing", "dock", "dockShot", "chatMedia", "modeHint", "waitPhrases", "waitFiles", "runningTasks", "hideCode",
  "airdrop", "draftCarry", "chCenter", "chHost", "chain", "seam", "userFoldMd", "reveal",
];

test("status(): поля в прежнем порядке, поля для приложения на месте", () => {
  const loaded = loadInject({ html: "composer" });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const status = plain(loaded.api.status());
  assert.deepEqual(Object.keys(status), ORDER);
  assert.equal(typeof status.cashout?.delivery, "string", "cashout.delivery — слово доезда «Обкэшить»");
  assert.equal(status.newWindow, null, "newWindow — null, пока «Новое окно» не запускали");
  assert.deepEqual(Object.keys(status.send).slice(0, 4), ["id", "state", "at", "sends"]);
  assert.equal(status.attention.want, false, "attention.want — ждёт ли чат слова");
  loaded.api.dispose();
});
