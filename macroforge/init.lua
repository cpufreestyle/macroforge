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
local vars       = require("macroforge.vars")
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

  -- Variables, conditions and HTTP are the three capabilities Macroforge was
  -- missing next to every comparable tool. They all reach Hammerspoon here and
  -- nowhere else, so the engine and the actions stay plain Lua.

  -- A no-op default: the engine replaces this with its dispatch hook on the
  -- env of every run it starts, so if/endIf reach the counter of that run. The
  -- default matters only for a bare action call (from the console, say) with no
  -- run in flight, which would otherwise crash on a nil.
  env.skipUntilEndIf = function() end

  env.setVariable = function(name, value)
    vars.set(name, value)
    return value
  end
  env.getVariable = function(name)
    return vars.get(name)
  end

  -- Conditions ask the OS through this table. Each entry is a function so a
  -- probe that cannot answer is distinguishable from one that answered no.
  env.probe = function()
    return {
      runningApps = function()
        local names = {}
        for _, app in ipairs(hsInstance.application.runningApplications() or {}) do
          local title = app:title()
          if title then names[#names + 1] = title end
        end
        return names
      end,
      frontmostApp = function()
        local app = hsInstance.application.frontmostApplication()
        return app and app:title() or ""
      end,
      screenCount = function()
        return #(hsInstance.screen.allScreens() or {})
      end,
      batteryLevel = function()
        if hsInstance.battery then
          local pct = hsInstance.battery.percentage()
          return pct and pct * 100 or nil
        end
        return nil
      end,
      minutesOfDay = function()
        local d = hsInstance.timer.secondsSinceEpoch() % 86400
        return math.floor(d / 60)
      end,
      networkReachable = function()
        -- Conservative by design: a macro must not take a slow branch because a
        -- probe was still in flight. Anything unreachable reports false.
        return false
      end,
      getVariable = function(name)
        return vars.get(name)
      end,
    }
  end

  env.httpRequest = function(opts, callback)
    -- hs.http is async, which is what keeps the Hammerspoon main loop free.
    -- The body comes back as a string so a macro can store or parse it.
    -- Like aiChat, the request settles once -- the first of the HTTP callback
    -- or the timeout budget wins; a wedged server releases the macro.
    local settled = false
    local function finish(body, err)
      if settled then return end
      settled = true
      hsInstance.timer.doAfter(0, function()
        callback(body, err)
      end)
    end
    hsInstance.timer.doAfter(env.httpTimeoutSeconds or 30, function()
      finish(nil, "请求超时（" .. tostring(env.httpTimeoutSeconds or 30) .. "s）")
    end)
    hsInstance.http.doAsyncRequest(opts.url, opts.method or "GET",
      opts.body and vars.expand(opts.body, vars.get) or nil, nil, function(status, body)
      if status < 200 or status >= 300 then
        finish(body, "HTTP " .. tostring(status))
        return
      end
      finish(body, nil)
    end)
  end

  -- Chat with the OpenAI-compatible endpoint configured in settings.json
  -- (ai.endpoint / ai.model / ai.apiKey). The key is composed only here, so
  -- it never appears in a macro file. callback(replyText, err).
  env.aiChat = function(opts, callback)
    local ai = env.ai or {}
    if type(ai.endpoint) ~= "string" or ai.endpoint == "" then
      callback(nil, "settings.json 未配置 ai.endpoint")
      return
    end
    -- Whichever lands first -- the HTTP callback or this timeout -- settles
    -- the action exactly once; the other is a no-op afterwards.
    local settled = false
    local function settle(reply, err)
      if settled then return end
      settled = true
      callback(reply, err)
    end
    local budget = env.httpTimeoutSeconds or 30
    hsInstance.timer.doAfter(budget, function()
      settle(nil, "AI 请求超时（" .. tostring(budget) .. "s）")
    end)
    local json = require("macroforge.json")
    local messages = {}
    if opts.system and opts.system ~= "" then
      messages[#messages + 1] = { role = "system", content = opts.system }
    end
    messages[#messages + 1] = { role = "user", content = opts.prompt or "" }
    local headers = { ["Content-Type"] = "application/json" }
    if type(ai.apiKey) == "string" and ai.apiKey ~= "" then
      headers.Authorization = "Bearer " .. ai.apiKey
    end
    hsInstance.http.doAsyncRequest(ai.endpoint, "POST", json.encode({
      model = (opts.model and opts.model ~= "") and opts.model or ai.model,
      messages = messages,
    }), headers, function(status, body)
      hsInstance.timer.doAfter(0, function()
        if status < 200 or status >= 300 then
          settle(nil, "HTTP " .. tostring(status) .. ": "
            .. tostring(body and body:sub(1, 200) or ""))
          return
        end
        local data = json.decode(body or "")
        local reply = data and data.choices and data.choices[1]
          and data.choices[1].message and data.choices[1].message.content
        if type(reply) ~= "string" then
          settle(nil, "AI 响应格式异常")
          return
        end
        settle(reply, nil)
      end)
    end)
  end

  return env
end

local function defaultSettings()
  return {
    chooserHotkey = { mods = { "cmd", "ctrl", "alt" }, key = "m" },
    editorHotkey  = { mods = { "cmd", "ctrl", "alt" }, key = "e" },
    reloadHotkey  = { mods = { "cmd", "ctrl", "alt" }, key = "r" },
    editorPort    = 8099,
    menubar       = true,
    requestTimeoutSeconds = 30,
    ai            = { endpoint = "", model = "", apiKey = "" },
  }
end

-- "cmd+ctrl+alt+m"-style display of a hotkey setting, for user-facing text.
local function hotkeyText(conf)
  if type(conf) ~= "table" or not conf.key then return "?" end
  local mods = {}
  for _, m in ipairs(conf.mods or {}) do mods[#mods + 1] = m end
  return table.concat(mods, "+") .. "+" .. tostring(conf.key)
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
    -- The console line is for debugging; the notification is what a user
    -- actually sees, since "the hot key did nothing" is otherwise silent.
    local labels = {
      chooserHotkey = "打开面板",
      editorHotkey = "打开编辑器",
      reloadHotkey = "重新载入",
    }
    local label = labels[setting] or setting
    print(string.format("[Macroforge] could not bind %s (already taken?)", setting))
    Macroforge.notify("Macroforge", "「" .. label .. "」快捷键绑定失败（可能被其他应用占用），可从菜单栏 ⚒ 进入。")
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

-- The AI macro author: turns a plain-language request into a validated macro
-- file. The catalog vocabulary is serialized into the prompt so the model can
-- only reach for actions that actually exist, and its output goes through the
-- same normalize/validate/save path as a hand-written file before touching
-- disk. Asynchronous: the reply lands as a new macro file plus a notification.
local function makeAiCreator(env, store, notify)
  local function vocabulary()
    local lines = {}
    for _, def in ipairs(catalog.actions) do
      local params = {}
      for _, p in ipairs(def.params or {}) do
        params[#params + 1] = p.name .. "(" .. p.type
          .. (p.required and ",required" or "") .. ")"
      end
      lines[#lines + 1] = def.type .. ": " .. table.concat(params, " ")
    end
    return table.concat(lines, "\n")
  end

  local function systemPrompt()
    return table.concat({
      "你是 macOS 自动化工具 Macroforge 的宏生成器。根据用户需求只输出一个 JSON 宏文档，不要输出解释或代码围栏。",
      "规则：顶层字段 id（小写字母数字连字符）、name（简短中文名）、enabled=true、actions 数组（至少一个动作）。",
      "可用动作：",
      vocabulary(),
      "触发器类型：hotkey(key,mods)、typed(string,delete)、appLaunch(app)、windowFocused(app)、interval(minutes)。无需自动触发就省略 trigger 字段。",
      "文本参数可用 {{变量名}} 引用之前 setVariable 存入的值；ai 动作把回复存进 into 指定的变量。",
      "输出形状示例（每个动作必须是 {\"type\": 动作名, \"parameters\": {参数名: 值}}，参数不许平铺在动作上）：",
      '{"id":"afternoon-water","name":"下午喝水提醒","enabled":true,"trigger":{"type":"interval","parameters":{"minutes":1440}},"actions":[{"type":"setVariable","parameters":{"name":"hour","value":"15"}},{"type":"notify","parameters":{"title":"喝水提醒","text":"现在是 {{hour}} 点，记得喝水。"}}]}',
    }, "\n")
  end

  return function(request, model)
    env.aiChat({ prompt = systemPrompt() .. "\n\n用户需求：" .. request, model = model }, function(reply, err)
      if err then
        notify("Macroforge", "AI 生成失败：" .. tostring(err))
        return
      end
      -- Strip a code fence if the model added one despite the instruction.
      local body = reply:match("^%s*```%w*%s*(.-)%s*```%s*$") or reply
      local data = json.decode(body or "")
      if type(data) ~= "table" then
        notify("Macroforge", "AI 生成失败：输出不是合法 JSON")
        return
      end
      local macro = model.normalize(data)
      local problems = model.validate(macro)
      if #problems > 0 then
        notify("Macroforge", "AI 生成未通过校验：" .. problems[1])
        return
      end
      -- Safety rail: the model can misread a request and emit destructive
      -- shell/AppleScript (seen live: an "rm -rf caches" macro for an
      -- unrelated request). Such macros are created DISABLED -- a human must
      -- read and enable them in the editor before they can ever run.
      local hasShell = false
      for _, a in ipairs(macro.actions or {}) do
        local t = tostring(a.type or ""):lower()
        if t == "runshell" or t == "runapplescript" then hasShell = true end
      end
      if hasShell then macro.enabled = false end
      local saved, saveErr = store:saveRenaming(macro)
      if not saved then
        notify("Macroforge", "保存失败：" .. tostring(saveErr))
        return
      end
      local notice = "AI 已创建宏「" .. tostring(macro.name or macro.id) .. "」"
      if hasShell then
        notice = notice .. "（含 shell/AppleScript，已默认停用——请检查后再启用）"
      end
      notify("Macroforge", notice)
    end)
  end
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
    aiCreate = makeAiCreator(state.env, state.store, Macroforge.notify),
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
    -- tostring guards the validation in hs.notify: a table slipping in here
    -- would otherwise crash the timer callback instead of showing the text.
    hsInstance.notify.new({
      title = tostring(title),
      informativeText = tostring(text),
    }):send()
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

  -- Hand the AI settings to the env bridge; aiChat reads them per call.
  env.ai = state.settings.ai
  -- Outbound HTTP (ai + httpRequest) settles within this budget; a wedged
  -- gateway must release the macro instead of leaking its re-entry guard.
  env.httpTimeoutSeconds = state.settings.requestTimeoutSeconds or 30

  Macroforge.bindTriggers()

  state.watcher = hsInstance.pathwatcher.new(p.macrosDir, function()
    -- Coalesce bursts of file events (batch saves, git operations) into one
    -- reload instead of tearing down and rebuilding every trigger per event.
    if state.reloadTimer then state.reloadTimer:stop() end
    state.reloadTimer = hsInstance.timer.doAfter(0.3, function()
      state.reloadTimer = nil
      Macroforge.reload()
    end)
  end):start()

  if not opts.noEditor then
    Macroforge.startEditor()
  end

  -- A permanent menu-bar entry point: no hotkeys to memorize, and the place
  -- a new user looks first. Off via settings.menubar = false.
  if state.settings.menubar ~= false then
    state.menubar = hsInstance.menubar.new():setTitle("⚒"):setMenu({
      { title = "打开面板", fn = function() Macroforge.showChooser() end },
      { title = "打开编辑器", fn = function() Macroforge.openEditor() end },
      { title = "-" },
      { title = "重新载入宏", fn = function() Macroforge.reload() end },
    })
  end

  -- First-run guidance: an empty macro dir means nothing is wired up yet, so
  -- say what to do next instead of starting silently. Auto-opens the editor
  -- (its teaching layer is already waiting there) once, tracked by a marker
  -- file so it never nags on every reload.
  if #state.store.macros == 0 then
    Macroforge.notify("Macroforge", "还没有宏：" ..
      hotkeyText(state.settings.chooserHotkey) .. " 打开面板，" ..
      hotkeyText(state.settings.editorHotkey) .. " 或菜单栏 ⚒ 打开编辑器。")
    local marker = p.root .. "/.onboarded"
    if not hsfs.readFile(marker) then
      hsfs.writeFile(hsInstance, marker, "1")
      Macroforge.openEditor()
    end
  end

  local macros, errors = state.store.macros, state.errors
  print(string.format("[Macroforge] %s started: %d macros, %d problem file(s)",
    VERSION, #macros, #errors))
  return state
end

function Macroforge.reload()
  if not state then return false end
  -- Stale re-entry guards belong to the previous macro generation; without
  -- this cleanup a macro whose chain was interrupted could never run again
  -- until a full Hammerspoon reload. Chains still in flight keep running on
  -- their old macro tables (see engine:clearRunning).
  if state.engine then state.engine:clearRunning() end
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
  -- A pending debounce timer must not fire after stop() and reload against a
  -- torn-down state.
  if state.reloadTimer then state.reloadTimer:stop() end
  if state.menubar then state.menubar:delete() end
  if state.watcher then state.watcher:stop() end
  if state.server then
    state.server:stop()
    state.server = nil
  end
  state = nil
end

return Macroforge
