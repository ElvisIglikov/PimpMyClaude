#!/usr/bin/env node
// MyClaude — патч Claude Desktop: узкие окна + узкие поля по бокам.
//
// Что делает: в главный сценарий Claude (app.asar → package.json "main") дописывает
// сверху небольшой лоадер. Лоадер читает ~/Library/Application Support/MyClaude/claude.json
// и на лету: (1) понижает минимальную ширину всех окон до minWindowWidth,
// (2) вставляет CSS с полями sidePadding в страницы claude.ai. Настройки читаются
// с диска при каждом изменении файла — Claude перезапускать не нужно.
//
// Патч меняет app.asar и Info.plist, поэтому Claude переподписывается локальной
// (ad-hoc) подписью. После первого патча macOS один раз заново спросит разрешения
// (микрофон, экран, доступ). После обновления Claude патч слетает — запусти снова.
//
// Команды:
//   node patch-claude.mjs            поставить/обновить патч (закроет и снова откроет Claude)
//   node patch-claude.mjs status     что стоит сейчас
//   node patch-claude.mjs restore    вернуть оригинал из бэкапа
//   node patch-claude.mjs selftest   прогнать патч на копии app.asar, приложение не трогать
//
// Значения по умолчанию взяты из ElvisOS (настройки 👾 Элвиса): ширина 360, поля 16.

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP = process.env.CLAUDE_APP_PATH || "/Applications/Claude.app";
const ASAR_RELATIVE = "Contents/Resources/app.asar";
const INFO_RELATIVE = "Contents/Info.plist";
const ENTITLEMENTS = path.join(HERE, "entitlements.plist");
const SUPPORT = path.join(os.homedir(), "Library", "Application Support", "MyClaude");
const CONFIG = path.join(SUPPORT, "claude.json");
const BACKUPS = path.join(SUPPORT, "backups");
const BUNDLE_ID = "com.anthropic.claudefordesktop";
const LOADER_VERSION = 6;
const MARK_START = `/* [MyClaude:v${LOADER_VERSION}:start] */`;
const MARK_END = `/* [MyClaude:v${LOADER_VERSION}:end] */`;
const DEFAULTS = { minWindowWidth: 360, sidePadding: 16 };

// ---------------------------------------------------------------- utils
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const run = (exe, args, opts = {}) => execFileSync(exe, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...opts });
const say = (message) => process.stdout.write(`${message}\n`);
const fail = (message) => { process.stderr.write(`Ошибка: ${message}\n`); process.exit(1); };
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function appVersion(appPath = APP) {
  return run("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleShortVersionString", path.join(appPath, INFO_RELATIVE)]).trim();
}

function ensureConfig() {
  fs.mkdirSync(SUPPORT, { recursive: true });
  if (!fs.existsSync(CONFIG)) fs.writeFileSync(CONFIG, `${JSON.stringify(DEFAULTS, null, 2)}\n`);
  try { return JSON.parse(fs.readFileSync(CONFIG, "utf8")); } catch { return DEFAULTS; }
}

// ---------------------------------------------------------------- asar
function readAsar(archivePath) {
  const archive = fs.readFileSync(archivePath);
  const headerSize = archive.readUInt32LE(4);
  const jsonSize = archive.readUInt32LE(12);
  const headerJson = archive.subarray(16, 16 + jsonSize);
  return { archive, header: JSON.parse(headerJson.toString("utf8")), headerJson, dataOffset: 8 + headerSize };
}

function buildAsarPrefix(header) {
  const headerJson = Buffer.from(JSON.stringify(header));
  const padding = (4 - ((8 + headerJson.length) % 4)) % 4;
  const headerSize = 8 + headerJson.length + padding;
  const prefix = Buffer.alloc(16 + headerJson.length + padding);
  prefix.writeUInt32LE(4, 0);
  prefix.writeUInt32LE(headerSize, 4);
  prefix.writeUInt32LE(headerSize - 4, 8);
  prefix.writeUInt32LE(headerJson.length, 12);
  headerJson.copy(prefix, 16);
  return { prefix, headerJson };
}

function lookupFile(header, posixPath) {
  let entry = header;
  for (const component of posixPath.split("/")) {
    entry = entry.files?.[component];
    if (!entry) throw new Error(`в app.asar нет файла ${posixPath}`);
  }
  if (entry.files || entry.link || entry.unpacked) throw new Error(`${posixPath} — не упакованный файл`);
  return entry;
}

function walkPackedFiles(node, callback) {
  for (const value of Object.values(node.files ?? {})) {
    if (value.files) walkPackedFiles(value, callback);
    else if (!value.link && !value.unpacked) callback(value);
  }
}

function readEntry(parsed, posixPath) {
  const entry = lookupFile(parsed.header, posixPath);
  const start = parsed.dataOffset + Number(entry.offset);
  return { entry, content: parsed.archive.subarray(start, start + Number(entry.size)) };
}

// Главный сценарий берём из package.json внутри архива: в 1.40609.1 это
// .vite/build/index.pre.js, раньше был index.js — путь не хардкодим.
function mainEntryPath(parsed) {
  const pkg = JSON.parse(readEntry(parsed, "package.json").content.toString("utf8"));
  if (!pkg.main) throw new Error("в package.json нет поля main");
  return pkg.main.replace(/^\.\//, "");
}

function loaderVersionOf(source) {
  const match = source.match(/\/\* \[MyClaude:v(\d+):start\] \*\//);
  return match ? Number(match[1]) : 0;
}

function stripLoader(source) {
  const match = source.match(/^\/\* \[MyClaude:v\d+:start\] \*\/[\s\S]*?\/\* \[MyClaude:v\d+:end\] \*\/\n?/);
  return match ? source.slice(match[0].length) : source;
}

function fileIntegrity(buffer, blockSize = 4 * 1024 * 1024) {
  const blocks = [];
  for (let offset = 0; offset < buffer.length; offset += blockSize) blocks.push(sha256(buffer.subarray(offset, offset + blockSize)));
  return { algorithm: "SHA256", hash: sha256(buffer), blockSize, blocks };
}

// String.raw — чтобы обратные слэши в регэкспах лоадера доехали как есть.
const LOADER = String.raw`${MARK_START}
"use strict";(()=>{try{
const electron=require("electron"),fs=require("node:fs"),os=require("node:os"),path=require("node:path");
const {app,BrowserWindow,webContents}=electron;
const configPath=path.join(os.homedir(),"Library","Application Support","MyClaude","claude.json");
const log=(...a)=>{try{console.log("[MyClaude]",...a)}catch{}};
const readConfig=()=>{try{return JSON.parse(fs.readFileSync(configPath,"utf8"))||{}}catch{return {}}};
// --- минимальная ширина окон. Claude создаёт окна с minWidth 600 и сам зовёт
// setMinimumSize при смене экрана, поэтому метод подменяется: всё, что выше
// желаемого, прижимается к желаемому; штатное значение помнится для отката.
const limits={desired:null,requested:new WeakMap(),native:null};
function desiredMinWidth(){const v=Number(readConfig().minWindowWidth);if(!Number.isFinite(v)||v<=0)return null;return Math.max(320,Math.round(v))}
function hookMinimumSize(){if(limits.native)return;const proto=BrowserWindow.prototype;const native=proto.setMinimumSize;if(typeof native!=="function")return;limits.native=native;
// Claude сам зовёт setMinimumSize и с 600, и с 0 (при стыковке панелей):
// ниже желаемого окно тоже не пускаем, иначе содержимое вылезает за край.
proto.setMinimumSize=function(w,h){try{if(typeof w==="number")limits.requested.set(this,[w,h]);if(typeof limits.desired==="number"&&typeof w==="number"&&w!==limits.desired)return native.call(this,limits.desired,h)}catch{}return native.call(this,w,h)}}
function applyLimits(){try{const desired=desiredMinWidth();limits.desired=desired;hookMinimumSize();
for(const win of BrowserWindow.getAllWindows()){try{if(win.isDestroyed())continue;const cur=win.getMinimumSize();if(!limits.requested.has(win))limits.requested.set(win,cur);
const orig=limits.requested.get(win)||cur;const target=desired===null?orig[0]:desired;if(target===cur[0])continue;
(limits.native||BrowserWindow.prototype.setMinimumSize).call(win,target,cur[1])}catch(e){log(e)}}}catch(e){log(e)}}
// --- поля по бокам. Штатно Claude Code держит 32px слева и 40px справа на
// контейнерах разговора и поля ввода. В 1.40609.1 это классы с
// ps-[var(--chat-gutter-start…)] / pe-[…]; старые сборки — .epitaxy-*-width.
// Плюс живой файл claude.css рядом с настройками: любые правила, без перепатча.
const cssState=new WeakMap();
const liveCssPath=path.join(path.dirname(configPath),"claude.css");
function cssText(){let out="";const v=Number(readConfig().sidePadding);
if(Number.isFinite(v)&&v>=0){const pad=Math.round(v);
out+='[class*="ps-[var(--chat-gutter"],[class*="pe-[var(--chat-gutter"],.epitaxy-transcript-width,.epitaxy-composer-width{padding-inline-start:'+pad+'px !important;padding-inline-end:'+pad+'px !important;padding-left:'+pad+'px !important;padding-right:'+pad+'px !important}\n';
// Лента разговора резервирует по 10px под полосу прокрутки с обеих сторон — на
// macOS полоса накладная, резерв только съедает ширину.
out+='[class*="scrollbar-gutter:stable_both-edges"]{scrollbar-gutter:auto !important}\n'}
try{out+=fs.readFileSync(liveCssPath,"utf8")}catch{}
return out}
// Окна «Open in new window» — это about:blank, куда страница-родитель рисует
// чат сама; внешняя рамка окна — file://…/main_window. CSS кладём во все
// страницы, кроме devtools: правила адресные и чужим страницам не мешают.
const isClaudePage=c=>{const u=c.getURL()||"";return !u.startsWith("devtools:")&&!u.startsWith("chrome-")};
async function applyCss(c,force){try{if(c.isDestroyed()||!isClaudePage(c))return;const text=cssText();const prev=cssState.get(c);
if(!force&&prev&&prev.text===text)return;
if(prev&&prev.key){try{await c.removeInsertedCSS(prev.key)}catch{}}
const key=text?await c.insertCSS(text,{cssOrigin:"user"}):null;cssState.set(c,{text,key})}catch(e){log(e);try{cssState.set(c,{text:null,key:null,error:String(e)})}catch{}}}
app.on("web-contents-created",(_,c)=>{try{c.on("dom-ready",()=>applyCss(c,true))}catch(e){log(e)}});
app.on("browser-window-created",()=>{applyLimits();setTimeout(applyLimits,400);setTimeout(applyLimits,1500)});
app.whenReady().then(()=>applyLimits()).catch(log);
const reapplyCss=()=>{for(const c of webContents.getAllWebContents())applyCss(c,false)};
fs.watchFile(configPath,{interval:1000},()=>{applyLimits();reapplyCss()});
fs.watchFile(liveCssPath,{interval:1000},reapplyCss);
// --- диагностика. status.json — что лоадер видит и куда вставил CSS.
// probe.js — любой JS; при каждом изменении файла выполняется во всех страницах
// claude.ai, ответ ложится в probe-result.json. Так снаружи видно DOM Claude.
const supportDir=path.dirname(configPath);
const statusPath=path.join(supportDir,"status.json"),probePath=path.join(supportDir,"probe.js"),probeResultPath=path.join(supportDir,"probe-result.json");
let probeStamp="";
const stampOf=f=>{try{const s=fs.statSync(f);return s.mtimeMs+":"+s.size}catch{return ""}};
function writeStatus(){try{const list=[];for(const c of webContents.getAllWebContents()){if(c.isDestroyed())continue;const st=cssState.get(c);list.push({id:c.id,url:c.getURL(),css:st?(st.error?"error: "+st.error:(st.key?"inserted":"none")):"untouched",inject:injected.get(c)||"none"})}
const wins=BrowserWindow.getAllWindows().filter(w=>!w.isDestroyed()).map(w=>({id:w.id,min:w.getMinimumSize(),size:w.getSize()}));
fs.writeFileSync(statusPath,JSON.stringify({at:new Date().toISOString(),loader:${LOADER_VERSION},config:readConfig(),desiredMinWidth:limits.desired,windows:wins,webContents:list},null,2))}catch(e){log(e)}}
async function runProbe(){try{const s=stampOf(probePath);if(!s||s===probeStamp)return;probeStamp=s;const code=fs.readFileSync(probePath,"utf8");const results=[];
for(const c of webContents.getAllWebContents()){if(c.isDestroyed()||!isClaudePage(c))continue;try{results.push({id:c.id,url:c.getURL(),result:await c.executeJavaScript(code,true)})}catch(e){results.push({id:c.id,url:c.getURL(),error:String(e)})}}
fs.writeFileSync(probeResultPath,JSON.stringify({at:new Date().toISOString(),results},null,2))}catch(e){log(e)}}
setInterval(()=>{runProbe();writeStatus()},2000);
// --- живой инжект и команды. inject.js рядом с настройками выполняется в каждой
// странице при dom-ready и заново при каждом изменении файла (скрипт обязан быть
// идемпотентным: сам снимает прошлый экземпляр). command.json {id, action, …}
// доставляется во все страницы событием window "myclaude-command".
const injectPath=path.join(supportDir,"inject.js"),commandPath=path.join(supportDir,"command.json");
const injected=new WeakMap();
async function applyInject(c,force){try{if(c.isDestroyed()||!isClaudePage(c))return;const s=stampOf(injectPath);if(!s)return;if(!force&&injected.get(c)===s)return;injected.set(c,s);
const code=fs.readFileSync(injectPath,"utf8");await c.executeJavaScript(code,true)}catch(e){log("inject",e)}}
const reinjectAll=()=>{for(const c of webContents.getAllWebContents())applyInject(c,false)};
let lastCommandId="";
function runCommand(){try{const cmd=JSON.parse(fs.readFileSync(commandPath,"utf8"));if(!cmd||!cmd.id||cmd.id===lastCommandId)return;lastCommandId=String(cmd.id);
const js="window.dispatchEvent(new CustomEvent('myclaude-command',{detail:"+JSON.stringify(cmd)+"}));";
for(const c of webContents.getAllWebContents()){if(c.isDestroyed()||!isClaudePage(c))continue;c.executeJavaScript(js,true).catch(e=>log("command",e))}}catch{}}
app.on("web-contents-created",(_,c)=>{try{c.on("dom-ready",()=>applyInject(c,true))}catch(e){log(e)}});
fs.watchFile(injectPath,{interval:1000},reinjectAll);
fs.watchFile(commandPath,{interval:500},runCommand);
log("loader v${LOADER_VERSION} ready");
}catch(e){console.error("[MyClaude]",e)}})();
${MARK_END}
`;

function patchAsarFile(archivePath) {
  const parsed = readAsar(archivePath);
  const mainPath = mainEntryPath(parsed);
  const { entry, content } = readEntry(parsed, mainPath);
  const source = content.toString("utf8");
  if (loaderVersionOf(source) === LOADER_VERSION) return { changed: false, mainPath, headerSha256: sha256(parsed.headerJson) };
  const clean = stripLoader(source);
  if (!clean.includes("require(") || !clean.includes("electron")) throw new Error(`${mainPath} не похож на главный сценарий Electron — патчить вслепую не буду`);

  const targetOffset = Number(entry.offset);
  const targetSize = Number(entry.size);
  // asar дедуплицирует одинаковые файлы: два входа могут делить одно смещение.
  // Если бы кто-то делил его с главным сценарием, его размер и хэш протухли бы.
  walkPackedFiles(parsed.header, (candidate) => {
    if (candidate === entry) return;
    const offset = Number(candidate.offset);
    if (offset >= targetOffset && offset < targetOffset + targetSize) throw new Error(`${mainPath} делит данные с другим файлом архива — патчить не буду`);
  });
  const replacement = Buffer.concat([Buffer.from(LOADER), Buffer.from(clean)]);
  const delta = replacement.length - targetSize;
  walkPackedFiles(parsed.header, (candidate) => {
    const offset = Number(candidate.offset);
    if (offset > targetOffset) candidate.offset = String(offset + delta);
  });
  entry.size = replacement.length;
  entry.integrity = fileIntegrity(replacement, entry.integrity?.blockSize);

  const { prefix, headerJson } = buildAsarPrefix(parsed.header);
  const data = parsed.archive.subarray(parsed.dataOffset);
  const rebuilt = Buffer.concat([prefix, data.subarray(0, targetOffset), replacement, data.subarray(targetOffset + targetSize)]);
  const temporary = `${archivePath}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, rebuilt);
  fs.renameSync(temporary, archivePath);

  const verify = readAsar(archivePath);
  const after = readEntry(verify, mainPath).content.toString("utf8");
  if (loaderVersionOf(after) !== LOADER_VERSION) throw new Error("после пересборки лоадер в архиве не найден");
  return { changed: true, mainPath, headerSha256: sha256(headerJson) };
}

function asarStatus(archivePath) {
  const parsed = readAsar(archivePath);
  const mainPath = mainEntryPath(parsed);
  const source = readEntry(parsed, mainPath).content.toString("utf8");
  return { mainPath, loaderVersion: loaderVersionOf(source), headerSha256: sha256(parsed.headerJson) };
}

// ---------------------------------------------------------------- app
function updateInfoIntegrity(appPath, headerSha256) {
  run("/usr/libexec/PlistBuddy", ["-c", `Set :ElectronAsarIntegrity:Resources/app.asar:hash ${headerSha256}`, path.join(appPath, INFO_RELATIVE)]);
}

function signAndVerify(appPath) {
  say("Переподписываю Claude локальной подписью…");
  run("/usr/bin/xattr", ["-cr", appPath]);
  run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", "--timestamp=none", appPath]);
  run("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", "--entitlements", ENTITLEMENTS, appPath]);
  run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
}

// Процессы именно ЭТОГО бандла, по пути: имя «Claude» носят и другие копии.
function claudeProcesses() {
  const main = [];
  const helpers = [];
  for (const line of run("/bin/ps", ["-axo", "pid=,command="]).split("\n")) {
    const match = line.match(/^\s*(\d+)\s+(.*)$/);
    if (!match) continue;
    const pid = Number(match[1]);
    const command = match[2];
    if (command.startsWith(`${APP}/Contents/MacOS/`)) main.push(pid);
    else if (command.startsWith(`${APP}/Contents/Frameworks/`) || command.startsWith(`${APP}/Contents/Helpers/`)) helpers.push(pid);
  }
  return { main, helpers };
}

const claudeRunning = () => claudeProcesses().main.length > 0;

// Этот сценарий нельзя запускать из терминала внутри самого Claude (Claude Code
// в приложении): закрытие Claude убило бы и его. Смотрим по цепочке родителей.
function refuseIfInsideClaude() {
  let pid = process.pid;
  for (let depth = 0; depth < 30 && pid > 1; depth += 1) {
    const line = (spawnSync("/bin/ps", ["-o", "ppid=,command=", "-p", String(pid)], { encoding: "utf8" }).stdout || "").trim();
    const match = line.match(/^(\d+)\s+(.*)$/);
    if (!match) break;
    if (match[2].startsWith(`${APP}/Contents/`)) fail("ты запускаешь патч изнутри Claude — он закроет сам себя. Запусти из Terminal.app");
    pid = Number(match[1]);
  }
}

function signal(pids, name) {
  for (const pid of pids) { try { process.kill(pid, name); } catch {} }
}

async function quitClaude() {
  if (!claudeRunning()) return;
  say("Закрываю Claude…");
  spawnSync("/usr/bin/osascript", ["-e", `tell application id "${BUNDLE_ID}" to quit`], { stdio: "ignore" });
  for (let i = 0; i < 80; i += 1) { if (!claudeRunning()) return; await wait(250); }
  signal(claudeProcesses().main, "SIGTERM");
  for (let i = 0; i < 40; i += 1) { if (!claudeRunning()) return; await wait(250); }
  const stubborn = claudeProcesses();
  signal([...stubborn.main, ...stubborn.helpers], "SIGKILL");
  for (let i = 0; i < 20; i += 1) { if (!claudeRunning()) return; await wait(250); }
  throw new Error("Claude не закрывается — закрой все его окна вручную и запусти снова");
}

function infoPlistHash(appPath = APP) {
  return run("/usr/libexec/PlistBuddy", ["-c", "Print :ElectronAsarIntegrity:Resources/app.asar:hash", path.join(appPath, INFO_RELATIVE)]).trim();
}

function signatureValid(appPath = APP) {
  return spawnSync("/usr/bin/codesign", ["--verify", "--deep", "--strict", appPath], { stdio: "ignore" }).status === 0;
}

function backupDir(version) { return path.join(BACKUPS, version); }

function makeBackup(version) {
  const dir = backupDir(version);
  if (fs.existsSync(path.join(dir, "app.asar")) && fs.existsSync(path.join(dir, "Info.plist"))) return dir;
  fs.mkdirSync(dir, { recursive: true });
  say(`Сохраняю оригинал Claude ${version} в ${dir}…`);
  fs.copyFileSync(path.join(APP, ASAR_RELATIVE), path.join(dir, "app.asar"));
  fs.copyFileSync(path.join(APP, INFO_RELATIVE), path.join(dir, "Info.plist"));
  return dir;
}

function relaunch() {
  spawnSync("/usr/bin/open", ["-a", APP], { stdio: "ignore" });
}

// ---------------------------------------------------------------- commands
async function commandPatch() {
  if (!fs.existsSync(APP)) fail(`нет ${APP}`);
  if (!fs.existsSync(ENTITLEMENTS)) fail(`нет ${ENTITLEMENTS}`);
  const version = appVersion();
  const config = ensureConfig();
  const before = asarStatus(path.join(APP, ASAR_RELATIVE));
  say(`Claude ${version}, главный сценарий ${before.mainPath}, лоадер сейчас: ${before.loaderVersion ? `v${before.loaderVersion}` : "нет"}`);
  say(`Настройки ${CONFIG}: ширина ${config.minWindowWidth}, поля ${config.sidePadding}`);
  refuseIfInsideClaude();
  if (before.loaderVersion === LOADER_VERSION) {
    // Лоадер есть, но прошлый прогон мог упасть между записью архива и подписью:
    // тогда хэш в Info.plist или подпись протухли, и Claude не запустится.
    if (infoPlistHash() === before.headerSha256 && signatureValid()) { say("Патч уже стоит. Ничего не меняю."); return; }
    say("Лоадер стоит, но хэш или подпись не сходятся — дочиню.");
    await quitClaude();
    updateInfoIntegrity(APP, before.headerSha256);
    signAndVerify(APP);
    relaunch();
    return;
  }

  await quitClaude();
  makeBackup(version);
  say("Ставлю лоадер в app.asar…");
  const result = patchAsarFile(path.join(APP, ASAR_RELATIVE));
  updateInfoIntegrity(APP, result.headerSha256);
  signAndVerify(APP);
  say("Готово. Открываю Claude…");
  relaunch();
  say("Если macOS заново спросит разрешения (микрофон, экран) — это из-за новой подписи, один раз.");
}

async function commandRestore() {
  const version = appVersion();
  const dir = backupDir(version);
  if (!fs.existsSync(path.join(dir, "app.asar"))) fail(`бэкапа для Claude ${version} нет в ${dir}. Переустанови Claude с claude.ai/download`);
  refuseIfInsideClaude();
  await quitClaude();
  say(`Возвращаю оригинальные app.asar и Info.plist ${version}…`);
  fs.copyFileSync(path.join(dir, "app.asar"), path.join(APP, ASAR_RELATIVE));
  fs.copyFileSync(path.join(dir, "Info.plist"), path.join(APP, INFO_RELATIVE));
  signAndVerify(APP);
  say("Готово (подпись осталась локальной; подпись Apple вернёт только переустановка). Открываю Claude…");
  relaunch();
}

function commandStatus() {
  const version = appVersion();
  const status = asarStatus(path.join(APP, ASAR_RELATIVE));
  const config = fs.existsSync(CONFIG) ? JSON.parse(fs.readFileSync(CONFIG, "utf8")) : null;
  say(`Claude ${version}`);
  say(`Лоадер MyClaude: ${status.loaderVersion ? `v${status.loaderVersion}` : "не стоит"} (нужен v${LOADER_VERSION}), главный сценарий ${status.mainPath}`);
  say(`Хэш asar в Info.plist ${infoPlistHash() === status.headerSha256 ? "совпадает" : "НЕ совпадает"} с архивом, подпись ${signatureValid() ? "валидна" : "НЕ валидна"}`);
  say(`Бэкап: ${fs.existsSync(path.join(backupDir(version), "app.asar")) ? backupDir(version) : "нет"}`);
  say(`Настройки: ${config ? JSON.stringify(config) : `нет файла ${CONFIG} (будут ${JSON.stringify(DEFAULTS)})`}`);
}

function commandSelfTest() {
  const scratch = process.env.MYCLAUDE_SCRATCH || os.tmpdir();
  const copy = path.join(scratch, `myclaude-selftest-${process.pid}.asar`);
  fs.copyFileSync(path.join(APP, ASAR_RELATIVE), copy);
  try {
    const before = asarStatus(copy);
    const result = patchAsarFile(copy);
    const after = asarStatus(copy);
    const parsed = readAsar(copy);
    // Все упакованные файлы должны читаться по своим смещениям с прежними хэшами.
    let checked = 0;
    walkPackedFiles(parsed.header, (entry) => {
      if (!entry.integrity?.hash) return;
      const start = parsed.dataOffset + Number(entry.offset);
      const content = parsed.archive.subarray(start, start + Number(entry.size));
      if (sha256(content) !== entry.integrity.hash) throw new Error("хэш файла в архиве разошёлся после сдвига смещений");
      checked += 1;
    });
    const source = readEntry(parsed, after.mainPath).content.toString("utf8");
    new Function("require", source.slice(0, source.indexOf(MARK_END) + MARK_END.length)); // лоадер — валидный JS
    say(`selftest OK: ${before.mainPath}, лоадер ${before.loaderVersion} → ${after.loaderVersion}, изменён: ${result.changed}, файлов сверено: ${checked}`);
  } finally {
    fs.rmSync(copy, { force: true });
  }
}

const command = process.argv[2] || "patch";
try {
  if (command === "patch") await commandPatch();
  else if (command === "restore") await commandRestore();
  else if (command === "status") commandStatus();
  else if (command === "selftest") commandSelfTest();
  else fail(`неизвестная команда ${command}. Есть: patch, status, restore, selftest`);
} catch (error) {
  if (error?.code === "EPERM") {
    fail("macOS не пускает Terminal менять приложения. Системные настройки → Конфиденциальность и безопасность → Управление приложениями (App Management) → включи Terminal, затем запусти снова.");
  }
  fail(error?.stderr?.toString?.() || error?.message || String(error));
}
