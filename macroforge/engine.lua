-- engine.lua -- the macro execution engine.
--
-- Runs a macro's action chain. Actions are executed one at a time; an action
-- signals completion through the `done` callback. Long actions (delay) use
-- env.timerAfter so the Hammerspoon main loop is never blocked.

local engine = {}
engine.__index = engine

local actions = require("macroforge.actions")
local model = require("macroforge.model")
local vars = require("macroforge.vars")

function engine.new(opts)
  opts = opts or {}
  local self = setmetatable({
    schedule = opts.schedule or function(_, fn) fn() end,
    notify = opts.notify or function() end,
    _running = {},
    _runs = 0,
    -- Runs with an action executing right now, innermost last. if/endIf move
    -- the counter of the run on top, so a nested macro and a macro the event
    -- loop interleaved with it never move each other's depth.
    _active = {},
  }, engine)

  -- The one skip hook for the whole engine. The env is a single session-wide
  -- table shared by every run, so it cannot hold "the run that is executing":
  -- it holds this instead, which forwards to whichever run is running an
  -- action. With nothing active it does nothing, exactly like the no-op
  -- default init.lua installs for a bare action call.
  self.skipUntilEndIf = function(take)
    local run = self._active[#self._active]
    if run then run.skip(take) end
  end

  return self
end

-- playMacro(macro, callbacks)
--   callbacks.env       environment table passed to actions (required)
--   callbacks.resolve   function(idOrName) -> macro table, for string references
--   callbacks.playMacro function(reference, callbacks) for chained macros
--   callbacks.onComplete, callbacks.onError
-- Returns (started, reason).
function engine:playMacro(macro, callbacks)
  callbacks = callbacks or {}
  -- A nested playMacro action carries its target as a string (id or name).
  -- Resolve it here so every entry point shares one code path, and report an
  -- unresolvable reference through onError: a silent (false, reason) return
  -- would strand the calling action's `done` and leak the re-entry guard.
  if type(macro) ~= "table" and callbacks.resolve then
    local resolved = callbacks.resolve(macro)
    if type(resolved) == "table" then macro = resolved end
  end
  if type(macro) ~= "table" then
    local reason = type(macro) == "string" and ("macro not found: " .. tostring(macro))
        or "macro must be a table"
    if callbacks.onError then callbacks.onError(reason) end
    return false, reason
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
  -- Re-entry is refused above, so no other run of this macro is in flight and
  -- the depth always starts at zero here.
  local skipDepth = 0

  local chain = macro.actions
  local index = 1
  local finished = false

  local function fail(reason)
    finished = true
    self._running[id] = nil
    self:notify("Macroforge", string.format("%s: %s", macro.name, tostring(reason)))
    if callbacks.onError then callbacks.onError(reason) end
  end

  -- The actions call this through env; it mutates the local skipDepth, which
  -- is why the engine owns the block logic instead of the actions themselves.
  -- Re-entry is refused above, so the depth always starts at zero here and one
  -- counter per macro run is enough: blocks are strictly nested and every
  -- if/endIf pair balances within one chain, so it cannot drift.
  local function envSkip(take)
    if take then skipDepth = skipDepth + 1 else skipDepth = math.max(0, skipDepth - 1) end
  end

  -- Point the env at the engine's dispatch hook for this run. The env is built
  -- once per session and shared by every run, so this is what makes if/endIf
  -- reach the counter of the run that is actually executing them; without it
  -- they call the no-op default and skip nothing.
  if callbacks.env then callbacks.env.skipUntilEndIf = self.skipUntilEndIf end

  -- Text parameters are expanded here rather than in each action, so every
  -- string field supports {{name}} without the action knowing about variables.
  local getVariable = callbacks.env and callbacks.env.getVariable
  local function expandParams(params)
    if not getVariable then return params end
    local out = {}
    for k, v in pairs(params or {}) do
      out[k] = type(v) == "string" and vars.expand(v, getVariable) or v
    end
    return out
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
    -- While a block is being skipped, only its own if/endIf markers are
    -- interpreted: they keep the nesting balanced, and every other action is
    -- dropped without being run. Skipping is synchronous -- the chain advances
    -- through the block in one go -- so a skipped action can never leave the
    -- macro stuck waiting for a done() that will not come.
    if skipDepth > 0 then
      local type = tostring(action.type or ""):lower()
      if type == "if" then
        envSkip(true)
      elseif type == "endif" then
        envSkip(false)
      end
      step()
      return
    end
    local def = actions.definition(action.type)
    if not def then
      fail(string.format("unknown action %q", tostring(action.type)))
      return
    end
    -- Publish this run while the action executes so the dispatch hook forwards
    -- to it. Truncating back to `depth` instead of assuming we are still on top
    -- keeps the stack honest when a nested chain ran to completion inside done.
    local depth = #self._active
    self._active[depth + 1] = { skip = envSkip }
    local ok, err = pcall(def.run, callbacks.env, expandParams(action.parameters), function()
      self.schedule(0, step)
    end, callbacks.playMacro)
    while #self._active > depth do self._active[#self._active] = nil end
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
