local fake = require("tests.fake_env")
local engineMod = require("macroforge.engine")
local actions = require("macroforge.actions")
local catalog = require("macroforge.catalog")

-- Runtime-registered actions still have to pass model validation, so the
-- vocabulary is extended before the tests run.
catalog.addAction({ type = "boom", label = "Boom (test)", params = {} })
actions.register("boom", { run = function() error("kaboom") end })

local function simpleMacro(id, actionTypes)
  local macro = { id = id, name = id, enabled = true, actions = {} }
  for _, t in ipairs(actionTypes) do
    macro.actions[#macro.actions + 1] = {
      type = t,
      parameters = ({
        delay = { seconds = 0.5 },
        notify = { title = "t", text = "x" },
        launch = { app = "Safari" },
        pasteText = { text = "t", restore = false },
        pressKeys = { mods = "cmd", key = "v" },
        boom = {},
      })[t] or {},
    }
  end
  return macro
end

test("engine: runs the action chain in order and completes", function()
  local engine = engineMod.new({ notify = function() end })
  local env = fake.new()
  local completed = false
  local ok = engine:playMacro(simpleMacro("m1", { "launch", "delay", "notify" }), {
    env = env,
    playMacro = function() end,
    onComplete = function() completed = true end,
  })
  truthy(ok, "macro should start")
  truthy(completed, "macro should complete synchronously with the fake timer")
  eq({ "launchOrFocus", "timerAfter", "notify" }, env:names())
  eq(0.5, env.calls[2].args[1])
  eq(1, engine:runCount())
end)

test("engine: an unknown action is caught by validation and never runs", function()
  local engine = engineMod.new({ notify = function() end })
  local env = fake.new()
  local reason
  local ok = engine:playMacro({
    id = "m2", name = "m2",
    actions = { { type = "launch", parameters = { app = "X" } },
                { type = "bogus", parameters = {} } },
  }, { env = env, playMacro = function() end, onError = function(r) reason = r end })
  falsy(ok, "unknown action must abort the macro")
  truthy(reason and reason:find("bogus") ~= nil, "expected unknown action reason, got: " .. tostring(reason))
  eq({}, env:names())
end)

test("engine: failing action can be skipped when continueOnError is set", function()
  local engine = engineMod.new({ notify = function() end })
  local env = fake.new()
  local macro = simpleMacro("m3", { "boom", "notify" })
  macro.continueOnError = true
  engine:playMacro(macro, { env = env, playMacro = function() end })
  eq({ "notify" }, env:names())
end)

test("engine: a failing action stops the macro by default", function()
  local engine = engineMod.new({ notify = function() end })
  local env = fake.new()
  local stopped = false
  engine:playMacro(simpleMacro("m4", { "boom", "notify" }), {
    env = env,
    playMacro = function() end,
    onComplete = function() stopped = true end,
  })
  falsy(stopped, "macro must not complete when an action fails")
  eq({}, env:names())
end)

test("engine: re-entry of the same macro is refused", function()
  local pending = nil
  local engine = engineMod.new({
    notify = function() end,
    schedule = function(_, fn) pending = fn end,
  })
  local env = fake.new()
  local macro = simpleMacro("m5", { "delay", "notify" })
  local ok = engine:playMacro(macro, { env = env, playMacro = function() end })
  local second, reason = engine:playMacro(macro, { env = env, playMacro = function() end })
  truthy(ok, "first run should start")
  falsy(second, "second run must be refused")
  truthy(reason == "macro is already running", "got: " .. tostring(reason))
  truthy(engine:isRunning("m5"))
  local steps = 0
  while pending do
    local step = pending
    pending = nil
    step()
    steps = steps + 1
    if steps > 50 then break end
  end
  falsy(engine:isRunning("m5"))
end)

test("engine: invalid macros never run", function()
  local engine = engineMod.new({ notify = function() end })
  local env = fake.new()
  local ok, reason = engine:playMacro({ id = "bad", name = "bad", actions = {} },
    { env = env, playMacro = function() end })
  falsy(ok)
  truthy(reason ~= nil)
  eq({}, env:names())
end)

test("engine: nested playMacro actions chain", function()
  local engine = engineMod.new({ notify = function() end })
  local env = fake.new()
  local inner = simpleMacro("inner", { "notify" })
  local outer = {
    id = "outer", name = "outer", enabled = true,
    actions = {
      { type = "launch", parameters = { app = "Safari" } },
      { type = "playMacro", parameters = { macro = "inner" } },
    },
  }
  local chained
  engine:playMacro(outer, {
    env = env,
    playMacro = function(name, callbacks)
      chained = { name = name, started = engine:playMacro(inner, callbacks) }
    end,
  })
  eq("inner", chained.name)
  truthy(chained.started, "nested macro should run")
  eq({ "launchOrFocus", "notify" }, env:names())
end)
