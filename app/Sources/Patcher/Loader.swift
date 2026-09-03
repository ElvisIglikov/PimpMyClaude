// Сгенерировано из claude-patch/patch-claude.mjs (const LOADER, String.raw) — строка перенесена дословно.
// Правится только там: смена текста лоадера = смена версии v6 в patch-claude.mjs и здесь.

/// Лоадер MyClaude v6 — вставляется в начало главного сценария Claude (app.asar → package.json "main").
let claudeLoaderSource = #"""
/* [MyClaude:v6:start] */
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
fs.writeFileSync(statusPath,JSON.stringify({at:new Date().toISOString(),loader:6,config:readConfig(),desiredMinWidth:limits.desired,windows:wins,webContents:list},null,2))}catch(e){log(e)}}
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
log("loader v6 ready");
}catch(e){console.error("[MyClaude]",e)}})();
/* [MyClaude:v6:end] */

"""#
