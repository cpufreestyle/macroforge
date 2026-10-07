-- macroforge/init.lua -- Hammerspoon runtime wiring.
--
-- Public API (from ~/.hammerspoon/init.lua):
--   require("macroforge").start()            -- idempotent bootstrap
--   Macroforge.showChooser()                 -- the macro palette
--   Macroforge.openEditor()                  -- open the web editor
--   Macroforge.reload()                      -- re-read macros + re-bind triggers
--   Macroforge.playMacro(macroOrIdOrName)
--   Macroforge.showManageChooser()
--   Macroforge.stop()
--   Macroforge.state()                       -- internals, for power users

local Macroforge = {}

local VERSION = "0.1.0"

local json       = require("macroforge.json")
local util       = require("macroforge.util")
local model      = require("macroforge.model")
local catalog    = require("macroforge.catalog")
local actionsMod = require("macroforge.actions")
local triggersMod = require("macroforge.triggers")
local storeMod   = require("macroforge.store")
local engineMod  = require("macroforge.engine")
local chooserMod = require("macroforge.chooser")
local editorMod  = require("macroforge.editor")
local hsfs       = require("macroforge.hsfs")

Macroforge.version     = VERSION
Macroforge.catalog     = catalog
Macroforge.actions     = actionsMod
Macroforge.triggers    = triggersMod
Macroforge.model       = model
Macroforge.storeModule = storeMod
Macroforge.engineModule = engineMod

local state = nil

local function requireHs()
  local hsInstance = rawget(_G, "hs")
  if not hsInstance then
    error("Macroforge needs the Hammerspoon runtime (global `hs` is missing). " ..
          "Run it from within Hammerspoon.")
  end
  return hsInstance
end

local function paths(hsInstance)
  local root = hsInstance.configdir .. "/macroforge"
  return {
    root = root,
    macrosDir = root .. "/macros",
    settingsPath = root .. "/settings.json",
    editorPath = root .. "/assets/editor.html",
  }
end

local function buildEnv(hsInstance, notify)
  local env = {}

  local function expandHome(path)
    local home = os.getenv("HOME") or ""
    return (tostring(path or ""):gsub("^~", home))
  end

  env.notify = notify
  env.launchOrFocus = function(app) hsInstance.application.launchOrFocus(app) end
  env.activate = function(app)
    local appObject = hsInstance.application.get(app)
    if appObject then appObject:activate(true) end
  end
  env.quit = function(app)
    local appObject = hsInstance.application.get(app)
    if appObject then appObject:kill() end
  end
  env.openURL = function(url)
    hsInstance.execute("/usr/bin/open " .. util.shellQuote(url))
  end
  env.openFile = function(path)
    hsInstance.execute("/usr/bin/open " .. util.shellQuote(expandHome(path)))
  end
  env.typeText = function(text)
    hsInstance.eventtap.keyStrokes(text)
  end
  env.paste = function()
    hsInstance.eventtap.keyStroke({ "cmd" }, "v", 0)
  end
  env.pressKeys = function(mods, key)
    hsInstance.eventtap.keyStroke(mods, key, 0)
  end
  env.screenRect = function()
    local frame = hsInstance.screen.mainScreen():frame()
    return { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
  end
  env.focusedWindowRect = function()
    local win = hsInstance.window.focusedWindow()
    if not win then return nil end
    local frame = win:frame()
    return { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
  end
  env.setFocusedWindowRect = function(rect)
    local win = hsInstance.window.focusedWindow()
    if not win then return false end
    win:setFrame(rect)
    return true
  end
  env.runShell = function(command)
    hsInstance.execute(command)
  end
  env.runAppleScript = function(script)
    hsInstance.osascript.applescript(script)
  end
  env.getClipboard = function()
    if hsInstance.pasteboard and hsInstance.pasteboard.readContents then
      return hsInstance.pasteboard.readContents()
    end
    return nil
  end
  env.setClipboard = function(text)
    if hsInstance.pasteboard and hsInstance.pasteboard.writeContents then
      hsInstance.pasteboard.writeContents(text)
    end
  end
  env.timerAfter = function(seconds, fn)
    hsInstance.timer.doAfter(seconds, fn)
  end
  return env
end

local function defaultSettings()
  return {
    chooserHotkey = { mods = { "cmd", "ctrl", "alt" }, key = "m" },
    editorHotkey  = { mods = { "cmd", "ctrl", "alt" }, key = "e" },
    reloadHotkey  = { mods = { "cmd", "ctrl", "alt" }, key = "r" },
    editorPort    = 8099,
  }
end

local function loadSettings(hsInstance)
  local settings = defaultSettings()
  local raw = hsfs.readFile(paths(hsInstance).settingsPath)
  if raw then
    local decoded, err = json.decode(raw)
    if decoded then
      for key, value in pairs(decoded) do
        if value ~= json.NULL then settings[key] = value end
      end
    else
      print("[Macroforge] settings.json could not be parsed: " .. tostring(err))
    end
  end
  return settings
end

local function buildApi(hsInstance)
  return {
    hotkeyBind = function(mods, key, fn)
      return hsInstance.hotkey.bind(mods, key, fn)
    end,
    applicationWatcher = function(fn)
      return hsInstance.application.watcher.new(fn)
    end,
    windowWatcher = function(appName, fn)
      local filter = hsInstance.window.filter.new(false):setAppFilter(appName, {})
      filter:subscribe(hsInstance.window.filter.windowFocused, fn)
      return filter
    end,
    timerEvery = function(seconds, fn)
      return hsInstance.timer.doEvery(seconds, fn)
    end,
    eventtap = function(fn)
      local tap = hsInstance.eventtap.new({ hsInstance.eventtap.event.types.keyDown },
        function(ev)
          local key = hsInstance.keycodes.map[ev:getKeyCode()]
          local flags = ev:getFlags()
          local mods = {}
          if flags.cmd then mods[#mods + 1] = "cmd" end
          if flags.ctrl then mods[#mods + 1] = "ctrl" end
          if flags.alt then mods[#mods + 1] = "alt" end
          if flags.shift then mods[#mods + 1] = "shift" end
          if flags.fn then mods[#mods + 1] = "fn" end
          fn(key, mods)
          return false
        end)
      tap:start()
      return tap
    end,
  }
end

local function bindSettingHotkey(hsInstance, setting, fn)
  local conf = state.settings[setting]
  if type(conf) ~= "table" or conf.key == false or not conf.key then return end
  local handle = hsInstance.hotkey.bind(conf.mods or {}, conf.key, fn)
  if not handle then
    print(string.format("[Macroforge] could not bind %s (already taken?)", setting))
    return
  end
  state.handles[#state.handles + 1] = { stop = function() handle:delete() end }
end

function Macroforge.bindTriggers()
  if not state then return nil, {} end
  local hsInstance = state.hs

  for _, handle in ipairs(state.handles) do handle.stop() end
  state.handles = {}
  state.typedEntries = {}

  local api = state.api
  local macros, errors = state.store:load()

  for _, macro in ipairs(macros) do
    local trigger = macro.trigger
    if macro.enabled and trigger and trigger.type ~= "" and trigger.type ~= "typed" then
      local handle = triggersMod.bind(trigger, function()
        Macroforge.playMacro(macro)
      end, api)
      state.handles[#state.handles + 1] = handle
    end
  end

  for _, macro in ipairs(macros) do
    local trigger = macro.trigger
    if macro.enabled and trigger and trigger.type == "typed" then
      local params = trigger.parameters or {}
      state.typedEntries[#state.typedEntries + 1] = {
        string = params.string,
        delete = params.delete ~= false,
        macro = macro,
      }
    end
  end
  state.handles[#state.handles + 1] = triggersMod.bindTyped(state.typedEntries,
    function(macro, charsToDelete)
      Macroforge.playMacro(macro)
      for _ = 1, charsToDelete do
        hsInstance.eventtap.keyStroke({}, "delete", 0)
      end
    end, api)

  bindSettingHotkey(hsInstance, "chooserHotkey", function() Macroforge.showChooser() end)
  bindSettingHotkey(hsInstance, "editorHotkey", function() Macroforge.openEditor() end)
  bindSettingHotkey(hsInstance, "reloadHotkey", function() Macroforge.reload() end)

  state.errors = errors or {}
  return macros, state.errors
end

function Macroforge.startEditor()
  if not state then return nil end
  local hsInstance = state.hs
  local p = paths(hsInstance)
  local html = hsfs.readFile(p.editorPath)
  if not html then
    print("[Macroforge] editor.html not found at " .. p.editorPath)
    return nil
  end
  state.router = require("macroforge.router").new({
    store = state.store,
    editorHTML = html,
    reload = function() return Macroforge.reload() end,
    run = function(macro) return Macroforge.playMacro(macro) end,
  })
  state.server = editorMod.start({
    hs = hsInstance,
    router = state.router,
    port = state.settings.editorPort or 8099,
  })
  print(string.format("[Macroforge] editor ready at http://127.0.0.1:%d/macroforge/",
    state.settings.editorPort or 8099))
  return state.server
end

function Macroforge.start(opts)
  opts = opts or {}
  local hsInstance = requireHs()
  if state then
    Macroforge.reload()
    return state
  end

  local p = paths(hsInstance)
  hsInstance.fs.mkdir(p.root)
  hsInstance.fs.mkdir(p.macrosDir)

  local notify = function(title, text)
    hsInstance.notify.new({ title = title, informativeText = text }):send()
  end

  local env = buildEnv(hsInstance, notify)
  local engine = engineMod.new({
    schedule = function(seconds, fn) hsInstance.timer.doAfter(seconds, fn) end,
    notify = notify,
  })
  local store = storeMod.new({ fs = hsfs.new(hsInstance), macrosDir = p.macrosDir })

  local function play(macro, callbacks)
    callbacks = callbacks or {}
    return engine:playMacro(macro, {
      env = env,
      -- A nested playMacro action carries the target as a string (id or
      -- name); the engine resolves it through this hook, so chooser, console
      -- and nesting all run on the same code path.
      resolve = Macroforge.resolve,
      playMacro = play,
      onComplete = callbacks.onComplete,
      onError = callbacks.onError,
    })
  end

  state = {
    hs = hsInstance,
    env = env,
    engine = engine,
    store = store,
    settings = loadSettings(hsInstance),
    paths = p,
    api = buildApi(hsInstance),
    handles = {},
    typedEntries = {},
    errors = {},
    play = play,
  }

  Macroforge.bindTriggers()

  state.watcher = hsInstance.pathwatcher.new(p.macrosDir, function()
    Macroforge.reload()
  end):start()

  if not opts.noEditor then
    Macroforge.startEditor()
  end

  local macros, errors = state.store.macros, state.errors
  print(string.format("[Macroforge] %s started: %d macros, %d problem file(s)",
    VERSION, #macros, #errors))
  return state
end

function Macroforge.reload()
  if not state then return false end
  local macros, errors = Macroforge.bindTriggers()
  if state.chooser then state.chooser:refresh() end
  local html = hsfs.readFile(state.paths.editorPath)
  if html and state.router then state.router.editorHTML = html end
  if #errors > 0 then
    Macroforge.notify("Macroforge", string.format(
      "reloaded %d macros (%d file(s) have problems)", #macros, #errors))
  else
    print(string.format("[Macroforge] reloaded %d macros", #macros))
  end
  return true
end

function Macroforge.resolve(macroOrId)
  if not state then return nil end
  if type(macroOrId) == "table" then return macroOrId end
  return state.store:byId(macroOrId) or state.store:byName(macroOrId)
end

function Macroforge.playMacro(macroOrId)
  if not state then return false, "Macroforge is not started" end
  local macro = Macroforge.resolve(macroOrId)
  if not macro then
    return false, "macro not found: " .. tostring(macroOrId)
  end
  return state.play(macro)
end

function Macroforge.showChooser()
  if not state then return nil end
  if not state.chooser then
    state.chooser = chooserMod.new({
      hs = state.hs,
      store = state.store,
      onRun = function(id)
        local macro = state.store:byId(id)
        if macro then Macroforge.playMacro(macro) end
      end,
      onCommand = function(command)
        if command == "editor" then
          Macroforge.openEditor()
        elseif command == "manage" then
          Macroforge.showManageChooser()
        elseif command == "reload" then
          Macroforge.reload()
        end
      end,
    })
  end
  state.chooser:show()
end

function Macroforge.showManageChooser()
  if not state then return nil end
  local rows = chooserMod.manageRows(state.store)
  chooserMod.simple(state.hs, rows, function(choice)
    if choice.kind == "action" and choice.command == "editor" then
      Macroforge.openEditor()
      return
    end
    if choice.kind == "action" and choice.command == "reload" then
      Macroforge.reload()
      return
    end
    if choice.kind == "macro" then
      local macro = state.store:byId(choice.id)
      if macro then
        macro.enabled = not macro.enabled
        local saved, err = state.store:save(macro)
        if saved then
          Macroforge.reload()
        else
          Macroforge.notify("Macroforge", tostring(err))
        end
      end
    end
  end)
end

function Macroforge.openEditor()
  if not state then return nil end
  local port = state.settings.editorPort or 8099
  local url = string.format("http://127.0.0.1:%d/macroforge/", port)
  state.env.openURL(url)
  return url
end

function Macroforge.notify(title, text)
  if state then state.env.notify(title, text) end
end

function Macroforge.state()
  return state
end

function Macroforge.stop()
  if not state then return end
  for _, handle in ipairs(state.handles) do handle.stop() end
  state.handles = {}
  if state.watcher then state.watcher:stop() end
  if state.server then
    state.server:stop()
    state.server = nil
  end
  state = nil
end

return Macroforge
