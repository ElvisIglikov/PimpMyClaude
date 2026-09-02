-- claude_autoallow.lua — auto-press "Allow" in Claude Desktop permission dialogs.
--
-- Why: some Claude Code tools (e.g. scheduled-tasks "create routine") are marked
-- requiresUserInteraction and prompt in EVERY permission mode; no settings.json rule,
-- PreToolUse or PermissionRequest hook can suppress them (docs: code.claude.com/docs/en/mcp,
-- "Require approval for a specific tool"). The only way to auto-accept is from outside the app.
--
-- How: a 1.5 s timer walks the accessibility tree of Claude.app windows, finds an
-- AXButton whose text matches one of buttonPatterns, and presses it (AXPress).
-- No event taps — a plain timer, so it never stalls input (see init.lua rule).
-- Only the dialog that is actually rendered on screen is visible to it: a prompt in a
-- session that is not shown in the window will not be pressed until you open it.
--
-- Install:
--   cp claude_autoallow.lua ~/.hammerspoon/
--   add to ~/.hammerspoon/init.lua:   pcall(function() require("claude_autoallow") end)
--   then reload Hammerspoon (hs -c 'hs.reload()').
--
-- Controls:
--   ctrl+alt+cmd+A                    toggle on/off (menubar icon: 🤖✓ / 🤖✗, click also toggles)
--   hs -c 'return require("claude_autoallow").status()'
--   hs -c 'return require("claude_autoallow").history()'
--   hs -c 'return require("claude_autoallow").scanNow()'

local M = {}

M.enabled = true
M.interval = 1.5          -- seconds between scans
M.maxScanSeconds = 0.4    -- abort a scan that takes longer (keeps HS responsive)
M.appNames = { "Claude" }
-- Button text to press (Lua patterns, matched against title/description + child text).
M.buttonPatterns = { "^Allow once", "^Allow$", "^Allow for this", "^Allow always", "^Yes, allow" }
-- Dialog headings that must NEVER be auto-approved (Lua patterns). Empty = approve all.
-- Example: { "rm %-rf", "git push", "delete" }
M.blockHeadingPatterns = {}

local timer, menubar, hotkey = nil, nil, nil
local log, MAX_LOG = {}, 50
local lastPressAt = 0

local function now() return hs.timer.secondsSinceEpoch() end

local function text(el)
  local parts = {}
  for _, attr in ipairs({ "AXTitle", "AXDescription", "AXValue" }) do
    local v = el:attributeValue(attr)
    if type(v) == "string" and v ~= "" then parts[#parts + 1] = v end
  end
  return table.concat(parts, " ")
end

-- Text of the element plus its descendants (2 levels), whitespace-collapsed.
local function deepText(el)
  local parts = { text(el) }
  for _, c in ipairs(el:attributeValue("AXChildren") or {}) do
    parts[#parts + 1] = text(c)
    for _, cc in ipairs(c:attributeValue("AXChildren") or {}) do
      parts[#parts + 1] = text(cc)
    end
  end
  local s = table.concat(parts, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- Heading of the dialog that owns a button: walk up a few parents, take the first
-- static text that looks like a question ("Allow Claude to use X?").
local function heading(btn)
  local el = btn
  for _ = 1, 6 do
    el = el and el:attributeValue("AXParent")
    if not el then break end
    local queue, seen = { el }, 0
    while #queue > 0 and seen < 80 do
      local cur = table.remove(queue, 1)
      seen = seen + 1
      if cur:attributeValue("AXRole") == "AXStaticText" then
        local t = text(cur)
        if t:match("^Allow") or t:match("wants to") or t:match("%?$") then return t end
      end
      for _, c in ipairs(cur:attributeValue("AXChildren") or {}) do queue[#queue + 1] = c end
    end
  end
  return ""
end

local function matchesAny(s, patterns)
  for _, p in ipairs(patterns) do
    if s:match(p) then return true end
  end
  return false
end

local function findButtons(root, deadline)
  local found = {}
  local function walk(el, depth)
    if depth > 80 or now() > deadline then return end
    if el:attributeValue("AXRole") == "AXButton" then
      local t = deepText(el)
      if matchesAny(t, M.buttonPatterns) then found[#found + 1] = { el = el, text = t } end
      return
    end
    for _, c in ipairs(el:attributeValue("AXChildren") or {}) do walk(c, depth + 1) end
  end
  walk(root, 0)
  return found
end

local preparedPids = {}

local function scan()
  if not M.enabled then return end
  for _, name in ipairs(M.appNames) do
    local app = hs.application.get(name)
    if app then
      local pid = app:pid()
      local ax = hs.axuielement.applicationElement(app)
      -- Electron only exposes its AX tree while AXManualAccessibility is on, and
      -- Claude drops the flag after restarts (seen 03.09: tree shrank to 45 nodes,
      -- flag read back false). Re-assert it whenever it is off — one cheap read per tick.
      if ax:attributeValue("AXManualAccessibility") ~= true then
        ax:setAttributeValue("AXManualAccessibility", true)
        ax:setAttributeValue("AXEnhancedUserInterface", true)
        -- Claude answers false on every read even after a successful set (03.09), so
        -- this runs each tick; two AX calls, no logging.
        preparedPids[pid] = true
      end
      local deadline = now() + M.maxScanSeconds
      for _, win in ipairs(ax:attributeValue("AXWindows") or {}) do
        for _, hit in ipairs(findButtons(win, deadline)) do
          local h = heading(hit.el)
          if #M.blockHeadingPatterns > 0 and matchesAny(h, M.blockHeadingPatterns) then
            print(string.format("[claude_autoallow] BLOCKED: %s | %s", h, hit.text))
          elseif now() - lastPressAt > 0.7 then
            local ok = hit.el:performAction("AXPress")
            lastPressAt = now()
            local entry = { at = os.date("%H:%M:%S"), heading = h, button = hit.text, ok = ok and true or false }
            table.insert(log, 1, entry)
            if #log > MAX_LOG then table.remove(log) end
            print(string.format("[claude_autoallow] pressed '%s' for '%s' ok=%s", hit.text, h, tostring(entry.ok)))
            hs.alert.show("Auto-allow: " .. (h ~= "" and h or hit.text), 1.2)
            return
          end
        end
      end
    end
  end
end

local function updateMenubar()
  if menubar then menubar:setTitle(M.enabled and "🤖✓" or "🤖✗") end
end

function M.setEnabled(on)
  M.enabled = on and true or false
  updateMenubar()
  hs.alert.show("Claude auto-allow: " .. (M.enabled and "ON" or "OFF"))
end

function M.toggle() M.setEnabled(not M.enabled) end

function M.status()
  return string.format("enabled=%s running=%s interval=%.1fs presses=%d",
    tostring(M.enabled), tostring(timer ~= nil and timer:running()), M.interval, #log)
end

function M.history()
  local lines = {}
  for _, e in ipairs(log) do
    lines[#lines + 1] = string.format("%s  %s  [%s] ok=%s", e.at, e.heading, e.button, tostring(e.ok))
  end
  return #lines > 0 and table.concat(lines, "\n") or "(no presses yet)"
end

function M.scanNow()
  local t0 = now()
  scan()
  return string.format("scan took %.3fs", now() - t0)
end

function M.start()
  if timer then timer:stop() end
  timer = hs.timer.doEvery(M.interval, function()
    local ok, err = pcall(scan)
    if not ok then print("[claude_autoallow] error: " .. tostring(err)) end
  end)
  if not menubar then
    menubar = hs.menubar.new()
    menubar:setClickCallback(M.toggle)
    menubar:setTooltip("Claude auto-allow (click to toggle)")
  end
  updateMenubar()
  if not hotkey then hotkey = hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "A", M.toggle) end
  return M
end

function M.stop()
  if timer then timer:stop(); timer = nil end
  if menubar then menubar:delete(); menubar = nil end
  if hotkey then hotkey:delete(); hotkey = nil end
end

return M.start()
