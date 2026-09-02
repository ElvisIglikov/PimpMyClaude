-- claude_noquit.lua — ⌘Q does nothing while Claude is frontmost.
--
-- Why: ⌘Q sits right next to ⌘W and ⌘A, and quitting Claude Desktop throws away every open chat
-- window at once. Claude has no "confirm before quit" setting of its own.
--
-- How: one hs.hotkey for ⌘Q, created at start and immediately disabled, plus an
-- hs.application.watcher that enables it when Claude activates and disables it when Claude goes
-- to the background. So the hotkey is live only while Claude is the frontmost app — every other
-- app keeps its normal ⌘Q. Pressing it inside Claude only shows an alert; nothing else happens.
-- No event taps: init.lua forbids taps on mouseMoved/scrollWheel/keyDown/flagsChanged, and
-- hs.hotkey/hs.application.watcher are not taps.
--
-- Quitting on purpose still works: menu Claude → Quit (menu items are not routed through
-- hs.hotkey), `hs -c 'require("claude_noquit").stop()'` and then ⌘Q, or Force Quit.
--
-- Install:
--   cp claude_noquit.lua ~/.hammerspoon/
--   add to ~/.hammerspoon/init.lua:   pcall(function() require("claude_noquit") end)
--   then reload Hammerspoon (hs -c 'hs.reload()').
--
-- Controls (no hotkeys of its own by design):
--   hs -c 'return require("claude_noquit").status()'
--   hs -c 'return require("claude_noquit").stop()'
--   hs -c 'return require("claude_noquit").start()'

local M = {}

M.appName = "Claude"
M.bundleID = "com.anthropic.claudefordesktop"
M.message = "⌘Q в Claude заблокирован — выход через меню Claude → Quit"
M.alertSeconds = 1.5

local hotkey, watcher = nil, nil
local armed = false
local blocks, lastBlock = 0, "(none)"

local function log(fmt, ...)
  print("[claude_noquit] " .. string.format(fmt, ...))
end

-- Bundle id first (survives a renamed app), name as the fallback; `name` is what the watcher
-- reports and is the only thing left when the app object is already gone.
local function isClaude(appObject, name)
  if appObject then
    local okb, bid = pcall(appObject.bundleID, appObject)
    if okb and bid == M.bundleID then return true end
    local okn, n = pcall(appObject.name, appObject)
    if okn and n == M.appName then return true end
  end
  return name == M.appName
end

local function arm(on)
  on = on and true or false
  if on == armed or not hotkey then return end
  if on then armed = hotkey:enable() ~= nil else hotkey:disable(); armed = false end
end

local function onPress()
  blocks = blocks + 1
  lastBlock = os.date("%H:%M:%S")
  hs.alert.show(M.message, M.alertSeconds)
end

local function onApp(name, event, appObject)
  local w = hs.application.watcher
  if event == w.activated then
    arm(isClaude(appObject, name))
  elseif event == w.deactivated then
    if isClaude(appObject, name) then arm(false) end
  elseif event == w.terminated then
    -- a terminated app object answers nothing useful; ask who is in front now instead
    arm(isClaude(hs.application.frontmostApplication(), nil))
  end
end

function M.status()
  return string.format("armed=%s watching=%s app=%s blocks=%d last=%s",
    tostring(armed), tostring(watcher ~= nil), M.appName, blocks, lastBlock)
end

function M.start()
  M.stop()
  -- hs.hotkey.bind enables the hotkey at once, so disable it in the same breath: ⌘Q is global for
  -- the microseconds in between and never after that.
  hotkey = hs.hotkey.bind({ "cmd" }, "q", onPress)
  hotkey:disable()
  armed = false

  watcher = hs.application.watcher.new(onApp)
  watcher:start()
  arm(isClaude(hs.application.frontmostApplication(), nil))   -- Claude may be in front already

  log("started (⌘Q blocked only while %s is frontmost, armed=%s)", M.appName, tostring(armed))
  return M
end

function M.stop()
  local was = hotkey ~= nil or watcher ~= nil
  if hotkey then hotkey:delete(); hotkey = nil end
  if watcher then watcher:stop(); watcher = nil end
  armed = false
  if was then log("stopped (⌘Q back to normal)") end   -- start() calls stop() first: stay quiet
  return M
end

return M.start()
