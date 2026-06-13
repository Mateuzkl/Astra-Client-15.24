--[[
  Scripting tab for AstraClient (3rd script of game_helper).
  --------------------------------------------------------
  A place for players to write their own Lua scripts. Each script's CODE BODY is
  run on a loop (every ~200ms) while the script is ENABLED ("loaded"), inside a
  sandbox that exposes the shared `bot` API (game + cavebot + helper) and a
  per-script persistent `storage` table.

  UI: the tab is just two lists -- "Available" (disabled) and "Running" (enabled).
  Load/Unload move a script between them. The code editor and the debug console
  (script print()s + errors) are separate windows.

  Mounted as a tab in the helper window (Scripting.init(window), like Cavebot).
  Persisted per character at /characterdata/<id>/scripts.json.

  The full `bot` API is documented in mods/game_helper/SCRIPTING_API.md (wiki).
]]

Scripting = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local helperWindow = nil
local panel        = nil
local disabledListW = nil   -- "Available" list (enabled == false)
local enabledListW  = nil   -- "Running" list (enabled == true)
local statusLabel   = nil

local editorWindow = nil    -- transient code-editor window
local editName     = nil    -- script being edited
local debugWindow  = nil    -- transient debug console window
local debugListW   = nil    -- the debug console's row list (nil while closed)
local debugScrollW = nil    -- its scrollbar (for auto-scroll)

local loopEvent  = nil
local scripts    = {}      -- name -> { name, code, enabled, fn, nextRun, errors, storage }
local order      = {}      -- display/run order of names
local selName    = nil     -- selected script (in either list)
local runningScript = nil  -- the script currently executing (for bot.delay/log)
local MAX_ERRORS = 5       -- auto-disable a script after this many runtime errors

local debugLines = {}      -- ring buffer of { text, color } for the debug console
local DEBUG_MAX  = 300

-- ---------------------------------------------------------------------------
-- Debug console buffer (errors + script print()/bot.log). Survives the window
-- being closed; opening it replays the buffer.
-- ---------------------------------------------------------------------------
local function debugAppend(text, color)
  text = '[' .. os.date('%H:%M:%S') .. '] ' .. tostring(text)
  color = color or '#cfcfcf'
  debugLines[#debugLines + 1] = { text = text, color = color }
  if #debugLines > DEBUG_MAX then table.remove(debugLines, 1) end
  if debugListW then
    local row = g_ui.createWidget('ScriptDebugRow', debugListW)
    row:setText(text)
    row:setColor(color)
    local kids = debugListW:getChildren()
    if #kids > DEBUG_MAX then
      local first = debugListW:getChildByIndex(1)
      if first then first:destroy() end
    end
    pcall(function() if debugScrollW then debugScrollW:setValue(debugScrollW:getMaximum()) end end)
  end
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------
local function configPath()
  if not LoadedPlayer or not LoadedPlayer:isLoaded() then return nil end
  return '/characterdata/' .. LoadedPlayer:getId() .. '/scripts.json'
end

local function save()
  local p = configPath()
  if not p then return end
  local out = { order = order, scripts = {}, selected = selName }
  for name, s in pairs(scripts) do
    out.scripts[name] = { code = s.code or '', enabled = s.enabled and true or false }
  end
  local ok, res = pcall(function() return json.encode(out, 2) end)
  if ok and res then g_resources.writeFileContents(p, res) end
end

local function setStatus(text, color)
  if not statusLabel then return end
  statusLabel:setText(text or '')
  if color then statusLabel:setColor(color) end
end

-- ---------------------------------------------------------------------------
-- Shared bot API (documented in SCRIPTING_API.md). Read it before changing keys.
-- ---------------------------------------------------------------------------
local function lp() return g_game.getLocalPlayer() end

local bot = {}

-- player / state ------------------------------------------------------------
function bot.player() return lp() end
function bot.online() return g_game.isOnline() and lp() ~= nil end
function bot.pos() local p = lp(); return p and p:getPosition() or nil end
function bot.name() local p = lp(); return p and p:getName() or '' end
function bot.hp() local p = lp(); return p and p:getHealth() or 0 end
function bot.maxhp() local p = lp(); return p and p:getMaxHealth() or 0 end
function bot.hpp() local p = lp(); if not p then return 0 end local m = p:getMaxHealth(); return m > 0 and math.floor(p:getHealth() / m * 100) or 0 end
function bot.mp() local p = lp(); return p and p:getMana() or 0 end
function bot.maxmp() local p = lp(); return p and p:getMaxMana() or 0 end
function bot.mpp() local p = lp(); if not p then return 0 end local m = p:getMaxMana(); return m > 0 and math.floor(p:getMana() / m * 100) or 0 end
function bot.cap() local p = lp(); if not p then return 0 end local ok, c = pcall(function() return p:getFreeCapacity() end); return (ok and c) or 0 end
function bot.skull() local p = lp(); return p and p:getSkull() or 0 end

-- movement ------------------------------------------------------------------
function bot.walk(pos) local p = lp(); if p and pos then p:autoWalk(pos) end end
function bot.stopWalk() local p = lp(); if p and p:isAutoWalking() then p:stopAutoWalk() end end
function bot.walking() local p = lp(); return p ~= nil and p:isAutoWalking() end
function bot.dist(a, b)
  a = a or bot.pos()
  if not a or not b then return 9999 end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- world ---------------------------------------------------------------------
function bot.tile(pos) return pos and g_map.getTile(pos) or nil end
local function spectators(range, want)
  local p = lp(); if not p then return {} end
  local list = g_map.getSpectatorsInRange(p:getPosition(), false, range or 7, range or 7) or {}
  local r = {}
  for _, c in ipairs(list) do
    if c and not c:isLocalPlayer() and c:getHealthPercent() > 0 then
      if (want == 'monster' and c:isMonster()) or (want == 'player' and c:isPlayer()) then
        r[#r + 1] = c
      end
    end
  end
  return r
end
function bot.creatures(range) return spectators(range, 'monster') end
function bot.players(range) return spectators(range, 'player') end
function bot.target() return g_game.getAttackingCreature() end
function bot.attack(c) if c then g_game.attack(c) end end

-- items / actions -----------------------------------------------------------
function bot.itemCount(id) local p = lp(); return (p and id) and p:getInventoryCount(id) or 0 end
function bot.useItem(id) if id then g_game.useInventoryItem(id) end end
function bot.useItemOn(id, target) if id and target then g_game.useInventoryItemWith(id, target, 0) end end
function bot.use(pos)
  local t = pos and g_map.getTile(pos)
  local th = t and t:getTopUseThing()
  if th then g_game.use(th) end
end
function bot.say(text) if text ~= nil then g_game.talk(tostring(text)) end end

-- timing / logging ----------------------------------------------------------
function bot.now() return g_clock.millis() end
-- Pause THIS script for `ms` (it won't run again until then). Use it to throttle.
function bot.delay(ms) if runningScript then runningScript.nextRun = g_clock.millis() + (tonumber(ms) or 0) end end
function bot.log(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
  debugAppend((runningScript and (runningScript.name .. ': ') or '') .. table.concat(parts, ' '), '#cfe0ff')
end

-- cavebot control -----------------------------------------------------------
bot.cavebot = {
  enabled = function() return Cavebot ~= nil and Cavebot.isEnabled() end,
  enable  = function() if Cavebot then Cavebot.setEnabled(true) end end,
  disable = function() if Cavebot then Cavebot.setEnabled(false) end end,
  toggle  = function() if Cavebot then Cavebot.setEnabled(not Cavebot.isEnabled()) end end,
  gotoTab = function(name) return Cavebot ~= nil and Cavebot.gotoTab(name) end,
  tab     = function() return Cavebot and Cavebot.currentTab() or '' end,
  tabs    = function() return Cavebot and Cavebot.listTabs() or {} end,
  status  = function() return Cavebot and Cavebot.getStatus() or '' end,
}

-- helper control (pcall-guarded against the helper's globals) ---------------
bot.helper = {
  enabled = function() return hotkeyHelperStatus == true end,
  shooter = function() return helperConfig ~= nil and helperConfig.magicShooterEnabled == true end,
  target  = function() return helperConfig ~= nil and helperConfig.autoTargetEnabled == true end,
  setShooter = function(on)
    pcall(function()
      local cb = shooterPanel:recursiveGetChildById('enableMagicShooter')
      cb:setChecked(on and true or false); toggleMagicShooter(cb)
    end)
  end,
  setTarget = function(on)
    pcall(function()
      local cb = shooterPanel:recursiveGetChildById('enableAutoTarget')
      cb:setChecked(on and true or false); toggleAutoTarget(cb)
    end)
  end,
}

-- ---------------------------------------------------------------------------
-- Compile / run
-- ---------------------------------------------------------------------------
local moduleEnv = (type(getfenv) == 'function') and getfenv(1) or _G

local function compile(s)
  s.fn = nil
  if not s.code or #s.code == 0 then return true end
  local fn, err = loadstring(s.code, '@' .. s.name)
  if not fn then
    debugAppend(s.name .. ' compile error: ' .. tostring(err), '#ff6666')
    return false, err
  end
  -- Sandbox: expose `bot`, a persistent `storage`, and `print`=bot.log; fall back
  -- to the module env (g_game, g_map, math, string, ...) for everything else.
  if setfenv then
    setfenv(fn, setmetatable({ bot = bot, storage = s.storage, print = bot.log },
                             { __index = moduleEnv }))
  end
  s.fn = fn
  return true
end

local function runOne(s, now)
  if not s.fn or now < (s.nextRun or 0) then return end
  runningScript = s
  local ok, err = pcall(s.fn)
  runningScript = nil
  if not ok then
    s.errors = (s.errors or 0) + 1
    debugAppend(s.name .. ' runtime error: ' .. tostring(err), '#ff6666')
    if s.errors >= MAX_ERRORS then
      s.enabled = false
      debugAppend(s.name .. ' disabled after ' .. MAX_ERRORS .. ' errors', '#ffaa55')
      Scripting.refreshLists()
      save()
    end
  end
end

local function loop()
  if not g_game.isOnline() then return end
  local now = g_clock.millis()
  for _, name in ipairs(order) do
    local s = scripts[name]
    if s and s.enabled then runOne(s, now) end
  end
end

-- ---------------------------------------------------------------------------
-- Enable / disable (= load / unload)
-- ---------------------------------------------------------------------------
local function setEnabled(s, on)
  on = on and true or false
  if on then
    s.errors = 0
    local ok = compile(s)
    if not ok then
      if modules.game_textmessage then
        modules.game_textmessage.displayFailureMessage(tr('Script has a syntax error; see Debug. Not loaded.'))
      end
      return false
    end
    s.nextRun = 0
  end
  s.enabled = on
  save()
  return true
end

-- ---------------------------------------------------------------------------
-- The two lists
-- ---------------------------------------------------------------------------
local function makeRow(listW, name, running)
  if not listW then return end
  local row = g_ui.createWidget('ScriptListRow', listW)
  row:setText(name)
  row:setColor(running and '#9fe08a' or '#cccccc')
  row:setOn(name == selName)
  row.scriptName = name
  row.onClick = function() Scripting.selectScript(name) end
  row.onDoubleClick = function()
    local s = scripts[name]
    if s then setEnabled(s, not s.enabled); Scripting.refreshLists() end
  end
  row.onMousePress = function(_, mp, btn)
    if btn == MouseRightButton then Scripting.scriptMenu(name, mp); return true end
    return false
  end
end

function Scripting.refreshLists()
  if disabledListW then disabledListW:destroyChildren() end
  if enabledListW then enabledListW:destroyChildren() end
  for _, name in ipairs(order) do
    local s = scripts[name]
    if s then
      if s.enabled then makeRow(enabledListW, name, true)
      else makeRow(disabledListW, name, false) end
    end
  end
end

function Scripting.selectScript(name)
  if not scripts[name] then return end
  selName = name
  for _, listW in ipairs({ disabledListW, enabledListW }) do
    if listW then
      for _, c in ipairs(listW:getChildren()) do c:setOn(c.scriptName == name) end
    end
  end
  save()
end

-- ---------------------------------------------------------------------------
-- Load / unload (move between the boxes)
-- ---------------------------------------------------------------------------
function Scripting.loadSelected()
  local s = selName and scripts[selName]
  if not s then setStatus(tr('Select a script first.'), '#cc4444'); return end
  if s.enabled then return end
  if setEnabled(s, true) then
    Scripting.refreshLists()
    setStatus(tr('Loaded "%s"', selName), '#44ad25')
  else
    setStatus(tr('Syntax error — see Debug.'), '#cc4444')
  end
end

function Scripting.unloadSelected()
  local s = selName and scripts[selName]
  if not s then setStatus(tr('Select a script first.'), '#cc4444'); return end
  if not s.enabled then return end
  setEnabled(s, false)
  Scripting.refreshLists()
  setStatus(tr('Unloaded "%s"', selName), '#c0c0c0')
end

-- ---------------------------------------------------------------------------
-- New / edit / delete
-- ---------------------------------------------------------------------------
local function uniqueName(base)
  local n, name = 0, base
  while scripts[name] do n = n + 1; name = base .. ' ' .. n end
  return name
end

function Scripting.newScript()
  local name = uniqueName('Script')
  scripts[name] = { name = name, enabled = false, storage = {},
    code = '-- ' .. name .. '\n-- Runs every ~200ms while loaded. Use print(...) to debug.\n-- See SCRIPTING_API.md for the full bot.* API.\n\n' }
  table.insert(order, name)
  selName = name
  Scripting.refreshLists()
  save()
  Scripting.openEditor(name)
end

function Scripting.editSelected()
  if not selName or not scripts[selName] then setStatus(tr('Select a script first.'), '#cc4444'); return end
  Scripting.openEditor(selName)
end

function Scripting.deleteSelected()
  local name = selName
  if not name or not scripts[name] then setStatus(tr('Select a script first.'), '#cc4444'); return end
  local box
  local function close() if box then box:destroy(); box = nil end end
  box = displayGeneralBox(tr('Delete Script'), tr('Delete "%s"?', name),
    { { text = tr('Yes'), callback = function()
          scripts[name] = nil
          for i, n in ipairs(order) do if n == name then table.remove(order, i); break end end
          if selName == name then selName = order[1] end
          if editName == name and editorWindow then editorWindow:destroy(); editorWindow = nil; editName = nil end
          Scripting.refreshLists(); save(); close()
        end },
      { text = tr('No'), callback = close } }, nil, close)
end

function Scripting.scriptMenu(name, mousePos)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  local s = scripts[name]
  menu:addOption((s and s.enabled) and tr('Unload') or tr('Load'), function()
    Scripting.selectScript(name)
    if s and s.enabled then Scripting.unloadSelected() else Scripting.loadSelected() end
  end)
  menu:addOption(tr('Edit'), function() Scripting.selectScript(name); Scripting.openEditor(name) end)
  menu:addOption(tr('Rename'), function() Scripting.renameScript(name) end)
  menu:addOption(tr('Delete'), function() Scripting.selectScript(name); Scripting.deleteSelected() end)
  menu:display(mousePos)
end

function Scripting.renameScript(old)
  local box = UIInputBox.create(tr('Rename Script'), function(name)
    if not name or #name == 0 or name == old or scripts[name] then return end
    local s = scripts[old]; scripts[old] = nil; s.name = name; scripts[name] = s
    for i, n in ipairs(order) do if n == old then order[i] = name end end
    if selName == old then selName = name end
    if editName == old then editName = name end
    Scripting.refreshLists()
    save()
  end, nil)
  box:addLineEdit(tr('New name'), old, 200)
  box:display()
end

-- ---------------------------------------------------------------------------
-- Editor window
-- ---------------------------------------------------------------------------
function Scripting.openEditor(name)
  local s = scripts[name]
  if not s then return end
  if editorWindow then editorWindow:destroy(); editorWindow = nil end
  local w = g_ui.createWidget('ScriptEditorWindow', g_ui.getRootWidget())
  editorWindow = w
  editName = name
  w:setText(tr('Script Editor') .. ' - ' .. name)

  local code = w:recursiveGetChildById('codeEdit')
  if code then code:setText(s.code or '') end
  local estatus = w:recursiveGetChildById('editorStatus')
  local function setE(t, c) if estatus then estatus:setText(t or ''); if c then estatus:setColor(c) end end end

  local function close()
    if editorWindow then editorWindow:destroy(); editorWindow = nil; editName = nil end
  end
  w:recursiveGetChildById('closeBtn').onClick = close

  w:recursiveGetChildById('saveBtn').onClick = function()
    if code then s.code = code:getText() end
    s.errors = 0
    if s.enabled then
      local ok = compile(s)
      if not ok then setE(tr('Saved (syntax error — see Debug)'), '#cc4444')
      else s.nextRun = 0; setE(tr('Saved & recompiled'), '#44ad25') end
    else
      setE(tr('Saved'), '#44ad25')
    end
    save()
  end

  w:recursiveGetChildById('runBtn').onClick = function()
    if code then s.code = code:getText() end
    local ok = compile(s)
    if not ok then setE(tr('Syntax error — see Debug'), '#cc4444'); return end
    if not s.fn then setE(tr('Nothing to run (empty)'), '#c0c0c0'); return end
    runningScript = s
    local pok, perr = pcall(s.fn)
    runningScript = nil
    if pok then setE(tr('Ran once OK'), '#44ad25')
    else setE(tr('Runtime error — see Debug'), '#cc4444'); debugAppend(name .. ' run: ' .. tostring(perr), '#ff6666') end
  end
end

-- ---------------------------------------------------------------------------
-- Debug console window
-- ---------------------------------------------------------------------------
function Scripting.openDebug()
  if debugWindow then debugWindow:raise(); debugWindow:focus(); return end
  local w = g_ui.createWidget('ScriptDebugWindow', g_ui.getRootWidget())
  debugWindow = w
  debugListW   = w:recursiveGetChildById('debugList')
  debugScrollW = w:recursiveGetChildById('debugScroll')
  if debugListW then
    for _, line in ipairs(debugLines) do
      local row = g_ui.createWidget('ScriptDebugRow', debugListW)
      row:setText(line.text); row:setColor(line.color)
    end
  end
  pcall(function() if debugScrollW then debugScrollW:setValue(debugScrollW:getMaximum()) end end)

  local function close()
    debugListW = nil; debugScrollW = nil
    if debugWindow then debugWindow:destroy(); debugWindow = nil end
  end
  w:recursiveGetChildById('closeBtn').onClick = close
  w:recursiveGetChildById('clearBtn').onClick = function()
    debugLines = {}
    if debugListW then debugListW:destroyChildren() end
  end
end

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
local function load()
  scripts, order, selName = {}, {}, nil
  local p = configPath()
  if p and g_resources.fileExists(p) then
    local ok, res = pcall(function() return json.decode(g_resources.readFileContents(p)) end)
    if ok and type(res) == 'table' then
      for _, name in ipairs(res.order or {}) do
        local sc = res.scripts and res.scripts[name]
        if sc then
          scripts[name] = { name = name, code = sc.code or '', enabled = false, storage = {} }
          table.insert(order, name)
        end
      end
      selName = res.selected
      -- compile + re-enable any that were enabled
      for _, name in ipairs(order) do
        local saved = res.scripts[name]
        if saved and saved.enabled then setEnabled(scripts[name], true) end
      end
    end
  end
  if #order == 0 then
    scripts['Example'] = { name = 'Example', enabled = false, storage = {},
      code = '-- Example: print your HP% every 5s (open Debug to see it).\nprint("HP", bot.hpp() .. "%")\nbot.delay(5000)\n' }
    table.insert(order, 'Example')
  end
  if not selName or not scripts[selName] then selName = order[1] end
end

-- ---------------------------------------------------------------------------
-- UI mounting (mirrors Cavebot: a panel in the helper content area)
-- ---------------------------------------------------------------------------
local function mountUI(window)
  local contentPanel = window.contentPanel
  panel = g_ui.createWidget('ScriptingPanel', contentPanel)
  if not panel then
    consoleln('[Scripting] ScriptingPanel style not loaded; aborting mount')
    return false
  end
  panel:setId('scriptingPanel')
  panel:addAnchor(AnchorTop, 'optionsTabBar', AnchorBottom)
  panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  panel:addAnchor(AnchorRight, 'parent', AnchorRight)
  panel:setMarginTop(5)
  panel:hide()

  disabledListW = panel:recursiveGetChildById('disabledList')
  enabledListW  = panel:recursiveGetChildById('enabledList')
  statusLabel   = panel:recursiveGetChildById('scriptingStatus')
  return true
end

-- ---------------------------------------------------------------------------
-- Lifecycle (called by helper.lua)
-- ---------------------------------------------------------------------------
function Scripting.init(window)
  helperWindow = window
  if not window or not window.contentPanel then return end
  mountUI(window)
end

function Scripting.online()
  load()
  Scripting.refreshLists()
  setStatus(tr('Ready'), '#c0c0c0')
  if loopEvent then removeEvent(loopEvent) end
  loopEvent = cycleEvent(loop, 200)
end

function Scripting.offline()
  if loopEvent then removeEvent(loopEvent); loopEvent = nil end
  save()
end

function Scripting.terminate()
  if loopEvent then removeEvent(loopEvent); loopEvent = nil end
  if editorWindow then editorWindow:destroy(); editorWindow = nil end
  if debugWindow then debugWindow:destroy(); debugWindow = nil end
  debugListW, debugScrollW = nil, nil
  helperWindow = nil
  panel = nil
end

function Scripting.showPanel() if panel then panel:show() end end
function Scripting.hidePanel() if panel then panel:hide() end end

-- Register styles before helper.lua displays its UI.
g_ui.importStyle('styles/scripting')
