-- claude_minimize_menu.lua — hover the minimize (yellow) button of a Claude window to get a
-- small menu: Обкэшить / Новый чат / Свернуть / Развернуть / Расставить / Показать / Прокрутить.
--
-- Why: the input handle inside Claude (claude-patch/inject.js) can collapse/expand the composer
-- and stash the last answer, but a chat window has no native place to trigger that. The traffic
-- lights are always there, so the menu hangs off them — the same gesture as in ElvisOS.
--
-- How: a 0.125 s timer (8 Hz) reads hs.mouse.absolutePosition() and compares it with the frames
-- of Claude's windows. Only when the cursor sits in the top 30 px of a frame do we ask the
-- accessibility API for AXMinimizeButton → AXPosition/AXSize (cached 0.5 s per window). Cursor
-- inside that rect for 0.3 s pops up hs.menubar.new(false):popupMenu() next to the button; the
-- menu is not shown again until the cursor leaves the button.
-- No event taps: init.lua forbids taps on mouseMoved/scrollWheel/keyDown/flagsChanged. A timer
-- is fine, and hs.eventtap.keyStroke only posts events — it does not install a tap.
--
-- The menu talks to the page through ~/Library/Application Support/MyClaude/command.json
-- (written atomically: tmp file in the same directory + os.rename), which the app patch turns
-- into a `myclaude-command` window event in every Claude page. The page acts on it only while it
-- has focus, hence w:focus() and a short delay before every write. The exception is `scroll`: it
-- is meant for every window at once, so it is written without focusing anything.
--
-- TEMPORARY (loader v5): the installed loader has no command.json channel — it only re-runs
-- probe.js in every page whenever that file changes (mtime+size, polled each 2 s). So every
-- command is ALSO written to probe.js as a one-line dispatch of the same event; the loader picks
-- it up on its next poll (≤ 2 s) and drops the return value into probe-result.json, overwriting
-- whatever diagnostic probe was there. Once loader v6 is installed set M.commandChannel = "json":
-- with both channels live the page gets each command twice (inject.js does not dedupe by id),
-- which collapse/expand/scroll survive but `cashout` would run twice.
--
-- Install:
--   cp claude_minimize_menu.lua ~/.hammerspoon/
--   add to ~/.hammerspoon/init.lua:   pcall(function() require("claude_minimize_menu") end)
--   then reload Hammerspoon (hs -c 'hs.reload()').
--
-- Controls (no hotkeys by design):
--   hs -c 'return require("claude_minimize_menu").status()'
--   hs -c 'return require("claude_minimize_menu").stop()'
--   hs -c 'require("claude_minimize_menu").enabled = false'   -- pause without stopping the timer
--   hs -c 'require("claude_minimize_menu").commandChannel = "json"'   -- after loader v6

local M = {}

M.enabled = true
M.interval = 0.125             -- cursor poll, 8 Hz
M.appName = "Claude"
M.topBand = 48                 -- px below the top of a window frame where the button can live
                               -- (button sits at frame.y+16..34; 30 clipped its bottom — сверка 03.09)
M.hoverSeconds = 0.3           -- cursor must rest on the button this long
M.buttonCacheSeconds = 0.5     -- AXMinimizeButton geometry cache, per window
M.windowCacheSeconds = 1.0     -- window list cache (frames are still read every tick)
M.focusDelay = 0.1             -- focus → command, so document.hasFocus() is true in the page
M.cashoutNewChatDelay = 0.4    -- cashout command → ⌘N
M.probeLagSeconds = 2.5        -- probe channel only: the loader re-reads probe.js on a 2 s poll + page walk
M.probeTtlSeconds = 15         -- probe channel only: a stale probe.js must not replay on loader start
M.minCellWidth = 360           -- «Расставить»: narrower cells drop a column (patch minWindowWidth)
M.iconSize = 18                -- px, side of the square an emoji menu icon is drawn into
M.iconColor = { white = 0.5 }  -- only monochrome glyphs (▦) take it; canvas text is white by
                               -- default, i.e. invisible on a light menu. Mid grey reads on both,
                               -- and a baked image cannot follow a later dark/light switch.
M.commandChannel = "both"      -- "both" | "json" (loader v6) | "probe" (loader v5 only)
M.commandPath = os.getenv("HOME") .. "/Library/Application Support/MyClaude/command.json"
M.probePath = os.getenv("HOME") .. "/Library/Application Support/MyClaude/probe.js"

local timer, popup = nil, nil
local app, appCheckedAt = nil, 0
local windows, windowsAt = {}, 0
local buttons = {}                              -- [window id] = { rect = rect|false, at = time }
local hoverId, hoverSince, suppressed = nil, 0, false
local menuOpen = false
local shows, lastCommand = 0, "(none)"

local function now() return hs.timer.secondsSinceEpoch() end

local function log(fmt, ...)
  print("[claude_minimize_menu] " .. string.format(fmt, ...))
end

local function claudeApp()
  if app and not app:isRunning() then app = nil end
  if not app and now() - appCheckedAt >= 2 then    -- don't re-scan the app list every tick
    appCheckedAt = now()
    app = hs.application.get(M.appName)
  end
  return app
end

local function claudeWindows()
  if now() - windowsAt < M.windowCacheSeconds then return windows end
  local a = claudeApp()
  windows = a and a:visibleWindows() or {}
  windowsAt = now()
  return windows
end

-- Screen rect of the window's minimize button, or nil. Cached (misses too) for buttonCacheSeconds,
-- so the AX round-trip happens at most twice a second and only for a window under the cursor.
local function minimizeRect(w)
  local id = w:id()
  local hit = id and buttons[id]
  if hit and now() - hit.at < M.buttonCacheSeconds then return hit.rect or nil end

  local rect = false
  local ax = hs.axuielement.windowElement(w)
  local btn = ax and ax:attributeValue("AXMinimizeButton")
  if btn then
    local p = btn:attributeValue("AXPosition")
    local s = btn:attributeValue("AXSize")
    local bw = s and (s.w or s.width)
    local bh = s and (s.h or s.height)
    if p and p.x and p.y and bw and bh then
      rect = { x = p.x, y = p.y, w = bw, h = bh }
    end
  end
  if id then buttons[id] = { rect = rect, at = now() } end
  return rect or nil
end

local function inside(pt, r)
  return pt.x >= r.x and pt.x <= r.x + r.w and pt.y >= r.y and pt.y <= r.y + r.h
end

-- tmp file next to the target, then os.rename: the loader polls these files and must never see a
-- half-written one. The tmp has to live in the same directory for the rename to be atomic.
local function writeAtomic(path, body)
  local dir = path:match("^(.*)/[^/]+$")
  local tmp = path .. ".tmp"

  local f = io.open(tmp, "w")
  if not f and dir then
    hs.fs.mkdir(dir)                              -- app patch not run yet: no MyClaude directory
    f = io.open(tmp, "w")
  end
  if not f then
    log("cannot write %s", tmp)
    return false
  end
  f:write(body)
  f:close()

  local ok, err = os.rename(tmp, path)
  if not ok then
    os.remove(tmp)
    log("rename failed: %s", tostring(err))
    return false
  end
  return true
end

-- {"id","action","at"} → command.json (loader v6) and/or probe.js (loader v5, see the header).
-- The probe file carries the same JSON inside a dispatch call plus the id as a trailing comment,
-- so two commands in the same second still change the file the loader stamps by mtime+size.
local function writeCommand(action)
  local id = string.format("%d-%04d", math.floor(now() * 1000), math.random(0, 9999))
  local json = string.format('{"id":"%s","action":"%s","at":"%s"}',
    id, action, os.date("!%Y-%m-%dT%H:%M:%SZ"))

  local done = {}
  if M.commandChannel == "both" or M.commandChannel == "json" then
    if writeAtomic(M.commandPath, json) then done[#done + 1] = "json" end
  end
  if M.commandChannel == "both" or M.commandChannel == "probe" then
    -- Self-expiring: the loader replays the last probe.js on every start (probeStamp begins
    -- empty), so an old command must become a no-op. mtimeMs makes the stamp unique; the id
    -- comment is only a readable label.
    local expires = math.floor((now() + M.probeTtlSeconds) * 1000)
    if writeAtomic(M.probePath,
      "if (Date.now() < " .. expires .. ") "
      .. "window.dispatchEvent(new CustomEvent('myclaude-command',{detail:" .. json .. "}));\n"
      .. "// " .. id .. "\n") then done[#done + 1] = "probe" end
  end
  if #done == 0 then return false end

  lastCommand = string.format("%s @ %s", action, os.date("%H:%M:%S"))
  log("command %s id=%s via %s", action, id, table.concat(done, "+"))
  return true
end

local function newChat(w)
  -- focus() is asynchronous; ⌘N right after it can land in the wrong Claude window.
  if w then w:focus() end
  hs.timer.doAfter(M.focusDelay, function() hs.eventtap.keyStroke({ "cmd" }, "n", 0, claudeApp()) end)
end

local function stageAction(w, action)
  if not w then return end
  w:focus()
  hs.timer.doAfter(M.focusDelay, function() writeCommand(action) end)
end

local function cashout(w)
  if not w then return end
  w:focus()
  hs.timer.doAfter(M.focusDelay, function()
    writeCommand("cashout")
    -- the page stashes the answer, then a fresh chat picks the stash up. Through probe.js the
    -- command waits for the loader's next poll, so ⌘N has to wait for that too — otherwise the
    -- new chat is already open by the time the old one gets told to stash anything.
    local delay = M.cashoutNewChatDelay
    if M.commandChannel ~= "json" then delay = delay + M.probeLagSeconds end
    hs.timer.doAfter(delay, function() newChat(w) end)
  end)
end

-- Columns for n windows; rows = ceil(n/cols), so this gives 1 | 2 | 2×2 | 3×2 | 4×2 and a square-ish
-- grid beyond 8. A column is dropped while a cell would be narrower than minCellWidth.
local function gridColumns(n, width)
  local cols
  if n <= 1 then cols = 1               -- n = 0 never reaches here, but a 0-column grid divides by 0
  elseif n <= 4 then cols = 2
  elseif n <= 6 then cols = 3
  elseif n <= 8 then cols = 4
  else cols = math.ceil(math.sqrt(n)) end
  while cols > 1 and width / cols < M.minCellWidth do cols = cols - 1 end
  return cols
end

-- Even grid over the main screen. Deliberately simpler than ElvisOS: no search for the largest
-- empty rectangle, no windows of other apps, no per-space filtering — just Claude's own windows
-- (hs.window.filter is avoided on purpose: it installs watchers).
local function arrange()
  local a = claudeApp()
  local screen = hs.screen.mainScreen()
  local wins = {}
  for _, w in ipairs(a and a:allWindows() or {}) do
    if w:isVisible() and not w:isMinimized() then wins[#wins + 1] = w end
  end
  if #wins == 0 or not screen then
    log("arrange: nothing to do (%d windows, screen=%s)", #wins, tostring(screen ~= nil))
    return
  end

  local f = screen:frame()                        -- usable area: menu bar and dock already excluded
  local cols = gridColumns(#wins, f.w)
  local rows = math.ceil(#wins / cols)
  for i, w in ipairs(wins) do
    -- edges from fractions of the frame, so the cells tile it without gaps or rounding drift
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local x0 = f.x + math.floor(col * f.w / cols + 0.5)
    local x1 = f.x + math.floor((col + 1) * f.w / cols + 0.5)
    local y0 = f.y + math.floor(row * f.h / rows + 0.5)
    local y1 = f.y + math.floor((row + 1) * f.h / rows + 0.5)
    pcall(w.setFrame, w, { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }, 0)   -- 0: no animation
  end
  buttons = {}                                    -- windows moved: cached button rects are stale
  log("arrange: %d windows, %d×%d", #wins, cols, rows)
end

-- All Claude windows in front of other apps, then focus back to the window the menu came from.
local function showAll(w)
  local a = claudeApp()
  if not a then return end
  a:activate(true)                                -- true: every window of the app, not just one
  for _, win in ipairs(a:allWindows()) do
    if win:isVisible() and not win:isMinimized() then pcall(win.raise, win) end
  end
  -- activate/raise are asynchronous; give them a tick before taking the focus back.
  if w then
    hs.timer.doAfter(M.focusDelay, function()
      pcall(w.raise, w)
      pcall(w.focus, w)
    end)
  end
end

-- hs.menubar wants an hs.image per item and there is no emoji→image call, so each emoji is drawn
-- once into a square canvas and cached. Misses are cached as false too: a canvas that fails is not
-- retried on every popup, the menu just loses its pictures — never its items.
local icons = {}

local function icon(emoji)
  local hit = icons[emoji]
  if hit ~= nil then return hit or nil end

  local size = M.iconSize
  local ok, image = pcall(function()
    local c = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
    if not c then return nil end
    c:appendElements({
      type = "text",
      text = emoji,
      textSize = math.floor(size * 0.78),         -- the glyph box is taller than the glyph itself
      textAlignment = "center",
      textColor = M.iconColor,
      frame = { x = 0, y = 0, w = size, h = size },
    })
    local img = c:imageFromCanvas()
    c:delete()                                    -- the canvas is never shown: free it right away
    return img
  end)
  if not ok then log("icon %s failed: %s", emoji, tostring(image)) end

  icons[emoji] = (ok and image) or false
  return icons[emoji] or nil
end

local function menuItems(w)
  return {
    { title = "Обкэшить",   image = icon("💰"), fn = function() cashout(w) end },
    { title = "Новый чат",  image = icon("💬"), fn = function() newChat(w) end },
    { title = "-" },
    { title = "Свернуть",   image = icon("⬇️"), fn = function() stageAction(w, "collapse") end },
    { title = "Развернуть", image = icon("⬆️"), fn = function() stageAction(w, "expand") end },
    { title = "-" },
    { title = "Расставить", image = icon("▦"),  fn = function() arrange() end },
    { title = "Показать",   image = icon("👀"), fn = function() showAll(w) end },
    -- scroll goes to every window, so no focus() first
    { title = "Прокрутить", image = icon("⏬"), fn = function() writeCommand("scroll") end },
  }
end

local function showMenu(w, rect)
  if popup then popup:delete(); popup = nil end   -- previous popup is long closed by now
  popup = hs.menubar.new(false)                   -- false: never appears in the menu bar
  if not popup then
    log("hs.menubar.new failed")
    return
  end
  popup:setMenu(menuItems(w))
  shows = shows + 1
  log("menu for window %s at %.0f,%.0f", tostring(w:id()), rect.x, rect.y)

  -- popupMenu blocks Lua until the menu closes; the timer survives that, and menuOpen keeps a
  -- tick that does slip through from doing any work.
  menuOpen = true
  local ok, err = pcall(function()
    popup:popupMenu({ x = rect.x, y = rect.y + rect.h + 2 })
  end)
  menuOpen = false
  if not ok then log("popupMenu error: %s", tostring(err)) end
end

local function tick()
  if not M.enabled or menuOpen then return end

  local pt = hs.mouse.absolutePosition()
  if not pt then return end

  local target, rect
  for _, w in ipairs(claudeWindows()) do
    local okf, f = pcall(w.frame, w)   -- a window closed within the 1 s cache makes frame() throw
    if okf and f and pt.x >= f.x and pt.x <= f.x + f.w and pt.y >= f.y and pt.y <= f.y + M.topBand then
      local r = minimizeRect(w)
      if r and inside(pt, r) then target, rect = w, r end
      break                    -- windows overlap: the frontmost frame under the cursor decides
    end
  end

  if not target then
    hoverId, hoverSince, suppressed = nil, 0, false
    return
  end

  local id = target:id()
  if hoverId ~= id then
    hoverId, hoverSince, suppressed = id, now(), false
    return
  end
  if suppressed then return end                   -- shown already; wait for the cursor to leave
  if now() - hoverSince >= M.hoverSeconds then
    suppressed = true                             -- set before the blocking popup, not after
    showMenu(target, rect)
  end
end

function M.status()
  return string.format(
    "enabled=%s running=%s interval=%.3fs app=%s windows=%d hover=%s menus=%d lastCommand=%s",
    tostring(M.enabled), tostring(timer ~= nil and timer:running()), M.interval,
    tostring(app ~= nil), #windows, tostring(hoverId), shows, lastCommand)
end

function M.start()
  if timer then timer:stop() end
  math.randomseed(os.time())
  timer = hs.timer.doEvery(M.interval, function()
    local ok, err = pcall(tick)
    if not ok then log("error: %s", tostring(err)) end
  end)
  log("started (%.3fs poll, no event taps)", M.interval)
  return M
end

function M.stop()
  if timer then timer:stop(); timer = nil end
  if popup then popup:delete(); popup = nil end
  windows, windowsAt, buttons = {}, 0, {}
  icons = {}                                      -- so iconSize/iconColor changes take effect on restart
  hoverId, hoverSince, suppressed, menuOpen = nil, 0, false, false
  log("stopped")
end

return M.start()
