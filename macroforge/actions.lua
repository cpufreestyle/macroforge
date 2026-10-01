-- actions.lua -- action implementations.
--
-- Every action has the signature:
--   run(env, params, done, playMacro)
-- `done` must be invoked when the action has finished; it may be called
-- synchronously. `playMacro(nameOrMacro, callbacks)` chains into another macro.
--
-- `env` abstracts the Hammerspoon API so the engine stays unit-testable:
--   env.launchOrFocus(app), env.activate(app), env.quit(app)
--   env.openURL(url), env.openFile(path), env.typeText(text)
--   env.paste(), env.pressKeys(mods, key)
--   env.screenRect() -> {x, y, w, h} of the main screen
--   env.focusedWindowRect() -> {x, y, w, h} or nil
--   env.setFocusedWindowRect(rect) -> boolean
--   env.runShell(command), env.runAppleScript(script)
--   env.notify(title, text)
--   env.getClipboard(), env.setClipboard(text)
--   env.timerAfter(seconds, fn)

local actions = {}

local catalog = require("macroforge.catalog")
local util = require("macroforge.util")

local defs = {}

local function sync(run)
  return function(env, params, done)
    run(env, params)
    done()
  end
end

defs.launch = {
  run = sync(function(env, params)
    env.launchOrFocus(params.app)
  end),
}

defs.activate = {
  run = sync(function(env, params)
    env.activate(params.app)
  end),
}

defs.quit = {
  run = sync(function(env, params)
    env.quit(params.app)
  end),
}

defs.openurl = {
  run = sync(function(env, params)
    env.openURL(params.url)
  end),
}

defs.openfile = {
  run = sync(function(env, params)
    env.openFile(params.path)
  end),
}

defs.typetext = {
  run = sync(function(env, params)
    env.typeText(params.text)
  end),
}

defs.pastetext = {
  run = sync(function(env, params)
    local previous = env.getClipboard and env.getClipboard()
    env.setClipboard(params.text or "")
    env.paste()
    if params.restore ~= false and previous ~= nil then
      env.timerAfter(0.4, function()
        env.setClipboard(previous)
      end)
    end
  end),
}

defs.presskeys = {
  run = sync(function(env, params)
    env.pressKeys(util.splitMods(params.mods), params.key)
  end),
}

defs.snapwindow = {
  run = sync(function(env, params)
    if params.app and util.trim(params.app) ~= "" then
      env.activate(params.app)
    end
    local current = env.focusedWindowRect and env.focusedWindowRect()
    if not current then
      env.notify("Macroforge", "No window is focused")
      return
    end
    local screen = env.screenRect()
    env.setFocusedWindowRect(catalog.snapFrame(params.position, screen))
  end),
}

defs.movewindow = {
  run = sync(function(env, params)
    local screen = env.screenRect()
    local rect = {
      x = screen.x + math.floor(screen.w * (tonumber(params.x) or 0) / 100),
      y = screen.y + math.floor(screen.h * (tonumber(params.y) or 0) / 100),
      w = math.floor(screen.w * (tonumber(params.width) or 0) / 100),
      h = math.floor(screen.h * (tonumber(params.height) or 0) / 100),
    }
    env.setFocusedWindowRect(rect)
  end),
}

defs.runshell = {
  run = sync(function(env, params)
    env.runShell(params.command)
  end),
}

defs.runapplescript = {
  run = sync(function(env, params)
    env.runAppleScript(params.script)
  end),
}

defs.notify = {
  run = sync(function(env, params)
    env.notify(params.title or "Macroforge", params.text)
  end),
}

defs.setclipboard = {
  run = sync(function(env, params)
    env.setClipboard(params.text)
  end),
}

defs.delay = {
  run = function(env, params, done)
    env.timerAfter(tonumber(params.seconds) or 0.1, done)
  end,
}

defs.playmacro = {
  run = function(env, params, done, playMacro)
    if not playMacro then
      done()
      return
    end
    playMacro(params.macro, {
      onComplete = done,
      onError = function(reason)
        env.notify("Macroforge", tostring(reason))
        done()
      end,
    })
  end,
}

function actions.definition(actionType)
  return defs[tostring(actionType or ""):lower()]
end

-- Escape hatch for power users: register custom actions from init.lua.
function actions.register(actionType, impl)
  defs[tostring(actionType):lower()] = impl
end

return actions
