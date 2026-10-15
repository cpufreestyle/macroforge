-- fake_env.lua -- a recording stand-in for the Hammerspoon environment.
--
-- Mirrors the `env` table built in macroforge/init.lua: plain dot-style
-- closures, so actions can call env.foo(...) exactly as in production.
-- Timers run their callback immediately unless autoTimers is disabled,
-- which keeps unit-test ordering deterministic.

local fake = {}

function fake.new()
  local env = {
    calls = {},
    clipboard = nil,
    autoTimers = true,
    rect = { x = 100, y = 100, w = 600, h = 400 },
    screen = { x = 0, y = 0, w = 1440, h = 900 },
  }

  local function record(name, ...)
    env.calls[#env.calls + 1] = { name = name, args = { ... } }
  end

  env.launchOrFocus = function(app) record("launchOrFocus", app) end
  env.activate = function(app) record("activate", app) end
  env.quit = function(app) record("quit", app) end
  env.openURL = function(url) record("openURL", url) end
  env.openFile = function(path) record("openFile", path) end
  env.typeText = function(text) record("typeText", text) end
  env.paste = function() record("paste") end
  env.pressKeys = function(mods, key) record("pressKeys", table.concat(mods, "+"), key) end
  env.screenRect = function()
    local s = env.screen
    return { x = s.x, y = s.y, w = s.w, h = s.h }
  end
  env.focusedWindowRect = function()
    local r = env.rect
    return { x = r.x, y = r.y, w = r.w, h = r.h }
  end
  env.setFocusedWindowRect = function(rect)
    record("setFocusedWindowRect", rect.x, rect.y, rect.w, rect.h)
    return true
  end
  env.runShell = function(command) record("runShell", command) end
  env.runAppleScript = function(script) record("runAppleScript", script) end
  env.notify = function(title, text) record("notify", title, text) end
  env.getClipboard = function() return env.clipboard end
  env.setClipboard = function(text)
    env.clipboard = text
    record("setClipboard", text)
  end
  env.timerAfter = function(seconds, fn)
    record("timerAfter", seconds)
    if env.autoTimers then fn() end
  end

  -- Variables: the fake keeps its own table so a test can seed a value and
  -- observe what an action stored, exactly like the shared table in vars.lua.
  env.variables = {}
  env.setVariable = function(name, value)
    env.variables[name] = value
    record("setVariable", name, value)
  end
  env.getVariable = function(name) return env.variables[name] end

  -- Conditions read the machine through this probe. Tests set env.probeFacts to
  -- whatever the scenario needs; an empty table answers "no" everywhere, which
  -- is what a bare fake does by default.
  env.probeFacts = {}
  env.probe = function()
    local facts = env.probeFacts
    return {
      runningApps = function() return facts.runningApps or {} end,
      frontmostApp = function() return facts.frontmostApp or "" end,
      screenCount = function() return facts.screenCount or 1 end,
      batteryLevel = function() return facts.batteryLevel end,
      minutesOfDay = function() return facts.minutesOfDay or 0 end,
      networkReachable = function(host) return facts.reachableHost == host end,
      getVariable = function(name) return env.variables[name] end,
    }
  end

  -- A recorded HTTP call. The response is configurable per test so both the
  -- success and the failure path can be exercised without a network.
  env.httpCalls = {}
  env.httpResponse = { status = 200, body = "ok" }
  env.httpRequest = function(opts, callback)
    env.httpCalls[#env.httpCalls + 1] = opts
    record("httpRequest", opts.url, opts.method)
    local response = env.httpResponse
    if env.httpError then
      callback(nil, env.httpError)
      return
    end
    callback(response.body, response.status >= 400 and ("HTTP " .. response.status) or nil)
  end

  -- Installed by the engine in production; a no-op here keeps a bare action
  -- call from crashing.
  env.skipUntilEndIf = function() end

  function env:names()
    local names = {}
    for _, call in ipairs(self.calls) do names[#names + 1] = call.name end
    return names
  end

  function env:reset()
    self.calls = {}
    self.clipboard = nil
    self.variables = {}
    self.httpCalls = {}
    self.probeFacts = {}
    self.httpResponse = { status = 200, body = "ok" }
    self.httpError = nil
  end

  return env
end

return fake
