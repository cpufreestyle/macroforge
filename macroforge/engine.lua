-- engine.lua -- the macro execution engine.
--
-- Runs a macro's action chain. Actions are executed one at a time; an action
-- signals completion through the `done` callback. Long actions (delay) use
-- env.timerAfter so the Hammerspoon main loop is never blocked.

local engine = {}
engine.__index = engine

local actions = require("macroforge.actions")
local model = require("macroforge.model")

function engine.new(opts)
  opts = opts or {}
  return setmetatable({
    schedule = opts.schedule or function(_, fn) fn() end,
    notify = opts.notify or function() end,
    _running = {},
    _runs = 0,
  }, engine)
end

-- playMacro(macro, callbacks)
--   callbacks.env       environment table passed to actions (required)
--   callbacks.playMacro function(nameOrMacro, callbacks) for chained macros
--   callbacks.onComplete, callbacks.onError
-- Returns (started, reason).
function engine:playMacro(macro, callbacks)
  callbacks = callbacks or {}
  if type(macro) ~= "table" then
    return false, "macro must be a table"
  end

  local problems = model.validate(macro)
  if #problems > 0 then
    local reason = problems[1]
    self:notify("Macroforge", string.format("%s: %s", macro.name or "macro", reason))
    if callbacks.onError then callbacks.onError(reason) end
    return false, reason
  end

  local id = macro.id or macro.name or "?"
  if self._running[id] then
    local reason = "macro is already running"
    if callbacks.onError then callbacks.onError(reason) end
    return false, reason
  end
  self._running[id] = true
  self._runs = self._runs + 1

  local chain = macro.actions
  local index = 1
  local finished = false

  local function fail(reason)
    finished = true
    self._running[id] = nil
    self:notify("Macroforge", string.format("%s: %s", macro.name, tostring(reason)))
    if callbacks.onError then callbacks.onError(reason) end
  end

  local function step()
    if finished then return end
    if index > #chain then
      finished = true
      self._running[id] = nil
      if callbacks.onComplete then callbacks.onComplete() end
      return
    end
    local action = chain[index]
    index = index + 1
    local def = actions.definition(action.type)
    if not def then
      fail(string.format("unknown action %q", tostring(action.type)))
      return
    end
    local ok, err = pcall(def.run, callbacks.env, action.parameters or {}, function()
      self.schedule(0, step)
    end, callbacks.playMacro)
    if not ok then
      if macro.continueOnError then
        self.schedule(0, step)
      else
        fail(err)
      end
    end
  end

  self.schedule(0, step)
  return true
end

local function macroid(macroOrId)
  if type(macroOrId) == "table" then
    return macroOrId.id or macroOrId.name or tostring(macroOrId)
  end
  return tostring(macroOrId)
end

function engine:isRunning(macroOrId)
  local id = macroid(macroOrId)
  return not not self._running[id]
end

function engine:runCount()
  return self._runs
end

return engine
