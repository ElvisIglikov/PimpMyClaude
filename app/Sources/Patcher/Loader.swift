// Сгенерировано из claude-patch/patch-claude.mjs (const LOADER, String.raw), побайтно.
// Смена лоадера требует перепатча Claude по явному разрешению.

/// Лоадер MyClaude v8: источник всех страниц удостоверяется Chromium.
let claudeLoaderSource = #"""
/* [MyClaude:v8:start] */
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
function desiredMinWidth(){const v=Number(readConfig().minWindowWidth);if(!Number.isFinite(v)||v<=0)return null;return Math.max(200,Math.round(v))}
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
// Один допуск CSS, inject, probe и команд: URL недостаточно для about:blank.
// mainFrame.origin — значение Chromium, а не утверждение JavaScript страницы;
// blank наследует origin создавшей его страницы. file/data/blob/чужие origin не допускаются.
const claudeOrigin="https://claude.ai",navigationEpoch=new WeakMap();
const diagnosticURL=u=>String(u||"").startsWith("data:")?"data:[redacted]":String(u||"").slice(0,512);
// Главная страница claude.ai — WebContentsView внутри BrowserWindow; fromWebContents для такого вида
// бывает null (сам Claude страхуется так же) — тогда владелец ищется обходом дерева видов окон.
const holdsView=(v,c)=>{try{return !!v&&(v.webContents===c||(v.children||[]).some(k=>holdsView(k,c)))}catch{return false}};
function nativeOwner(c){let owner=null,windowId;try{owner=BrowserWindow.fromWebContents(c)||BrowserWindow.getAllWindows().find(w=>!w.isDestroyed()&&holdsView(w.contentView,c))||null;const raw=owner?.getMediaSourceId(),m=typeof raw==="string"&&/^window:([1-9][0-9]*):[0-9]+$/.exec(raw);if(m){const n=Number(m[1]);if(Number.isSafeInteger(n)&&n<=4294967295)windowId=n}}catch{}return {owner,windowId}}
function claudeSource(c){try{if(c.isDestroyed())return null;const frame=c.mainFrame,u=c.getURL()||"";
if(!frame||frame.origin!==claudeOrigin)return null;
if(u!=="about:blank"&&u!==""){const parsed=new URL(u);if(parsed.protocol!=="https:"||parsed.origin!==claudeOrigin||parsed.username||parsed.password)return null}
const {owner,windowId}=nativeOwner(c);return {frame,owner,epoch:navigationEpoch.get(c)||0,metadata:{loader:8,origin:frame.origin,url:u,processId:frame.processId,routingId:frame.routingId,...(windowId===undefined?{}:{windowId})}}}catch{return null}}
const isClaudePage=c=>!!claudeSource(c);
function sameSource(c,source){const current=claudeSource(c);return !!current&&current.frame===source.frame&&current.owner===source.owner&&current.metadata.windowId===source.metadata.windowId&&current.epoch===source.epoch&&current.metadata.url===source.metadata.url}
// CSS живёт в документе, а не в URL и не в окне: ему хватает того же кадра и той же эпохи.
function sameDocument(c,source){const current=claudeSource(c);return !!current&&current.frame===source.frame&&current.epoch===source.epoch}
// Эпоху двигает только переход на новый документ: pushState роутера claude.ai (смена чата) документ не меняет.
app.on("web-contents-created",(_,c)=>{try{c.on("did-start-navigation",(details,url,inPlace,isMainFrame)=>{if((details.isMainFrame??isMainFrame)&&!(details.isSameDocument??inPlace))navigationEpoch.set(c,(navigationEpoch.get(c)||0)+1)})}catch(e){log(e)}});
async function applyCss(c,force){const source=claudeSource(c);if(!source)return;try{const text=cssText();const prev=cssState.get(c);
// Сорвалось на переходе — запись снимается (если её не сменил вызов свежее), и следующий dom-ready или reapply вставит лист заново.
const drop=()=>{if(cssState.get(c)===prev)cssState.delete(c)};
if(!force&&prev&&prev.text===text)return;
if(prev&&prev.key){try{await c.removeInsertedCSS(prev.key)}catch{}}
if(!sameDocument(c,source))return drop();
const key=text?await c.insertCSS(text,{cssOrigin:"user"}):null;
if(!sameDocument(c,source)){if(key){try{await c.removeInsertedCSS(key)}catch{}}return drop()}
cssState.set(c,{text,key})}catch(e){log(e);try{if(sameDocument(c,source))cssState.set(c,{text:null,key:null,error:String(e)})}catch{}}}
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
function writeStatus(){try{const list=[];for(const c of webContents.getAllWebContents()){if(c.isDestroyed())continue;const st=cssState.get(c);list.push({id:c.id,url:diagnosticURL(c.getURL()),css:st?(st.error?"error: "+st.error:(st.key?"inserted":"none")):"untouched",inject:injected.get(c)||"none"})}
const wins=BrowserWindow.getAllWindows().filter(w=>!w.isDestroyed()).map(w=>({id:w.id,min:w.getMinimumSize(),size:w.getSize()}));
fs.writeFileSync(statusPath,JSON.stringify({at:new Date().toISOString(),loader:8,config:readConfig(),desiredMinWidth:limits.desired,windows:wins,webContents:list},null,2))}catch(e){log(e)}}
async function runProbe(){try{const s=stampOf(probePath);if(!s||s===probeStamp)return;probeStamp=s;const code=fs.readFileSync(probePath,"utf8");const results=[];
for(const c of webContents.getAllWebContents()){const source=claudeSource(c);if(!source)continue;try{const result=await source.frame.executeJavaScript(code,true);if(sameSource(c,source))results.push({id:c.id,url:source.metadata.url,source:source.metadata,result})}catch(e){if(sameSource(c,source))results.push({id:c.id,url:source.metadata.url,source:source.metadata,error:String(e).slice(0,512)})}}
fs.writeFileSync(probeResultPath,JSON.stringify({at:new Date().toISOString(),results},null,2))}catch(e){log(e)}}
setInterval(()=>{runProbe();writeStatus()},2000);
// --- живой инжект и команды. inject.js рядом с настройками выполняется в каждой
// странице при dom-ready и заново при каждом изменении файла (скрипт обязан быть
// идемпотентным: сам снимает прошлый экземпляр). command.json {id, action, …}
// доставляется во все страницы событием window "myclaude-command".
const injectPath=path.join(supportDir,"inject.js"),commandPath=path.join(supportDir,"command.json");
const injected=new WeakMap();
async function applyInject(c,force){try{const source=claudeSource(c);if(!source)return;const s=stampOf(injectPath);if(!s)return;if(!force&&injected.get(c)===s)return;injected.set(c,s);
const code=fs.readFileSync(injectPath,"utf8");await source.frame.executeJavaScript(code,true)}catch(e){log("inject",e)}}
const reinjectAll=()=>{for(const c of webContents.getAllWebContents())applyInject(c,false)};
let lastCommandId="";
function runCommand(){try{const cmd=JSON.parse(fs.readFileSync(commandPath,"utf8"));if(!cmd||!cmd.id||cmd.id===lastCommandId)return;lastCommandId=String(cmd.id);
const js="window.dispatchEvent(new CustomEvent('myclaude-command',{detail:"+JSON.stringify(cmd)+"}));";
for(const c of webContents.getAllWebContents()){const source=claudeSource(c);if(!source)continue;source.frame.executeJavaScript(js,true).catch(e=>log("command",e))}}catch{}}
app.on("web-contents-created",(_,c)=>{try{c.on("dom-ready",()=>applyInject(c,true))}catch(e){log(e)}});
fs.watchFile(injectPath,{interval:1000},reinjectAll);
fs.watchFile(commandPath,{interval:500},runCommand);
log("loader v8 ready");
}catch(e){console.error("[MyClaude]",e)}})();
/* [MyClaude:v8:end] */

"""#
