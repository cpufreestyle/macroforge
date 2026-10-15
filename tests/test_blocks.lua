-- test_blocks.lua -- if/endIf block skipping in the engine.

local engine = require("macroforge.engine")
local model  = require("macroforge.model")

-- The marker action is `notify`, a built-in the validator already knows, so a
-- macro document built here passes model.validate exactly like a real one.
-- Recording happens in env.notify, which keeps the assertion on what the
-- engine actually did.
local function marker(tag)
  return { type = "notify", parameters = { title = tag, text = tag } }
end

-- The recorder hands out an env that mirrors what init.lua builds. The
-- skipUntilEndIf hook is wired to the engine under test in run(), because a
-- no-op here would silently disable every block assertion.
local function recorder(overrides)
  local env = { calls = {} }
  env.notify = function(_, message) env.calls[#env.calls + 1] = tostring(message) end
  for k, v in pairs(overrides or {}) do env[k] = v end
  return env
end

-- A probe where nothing is running, so every condition is false.
local idleProbe = function()
  return { runningApps = function() return {} end }
end

local function run(actions_, env)
  local doc = {
    id = "m", name = "m", enabled = true,
    trigger = { type = "hotkey", parameters = { mods = "cmd", key = "m" } },
    actions = actions_,
  }
  -- The document must be valid, or the engine refuses it before any action
  -- runs and every assertion below would pass for the wrong reason.
  local problems = model.validate(doc)
  if #problems > 0 then
    error("test macro is invalid: " .. problems[1])
  end
  local eng = engine.new({ schedule = function(_, fn) fn() end, notify = function() end })
  -- Install the engine's block hook exactly as init.lua does, so the if/endIf
  -- actions move the counter of the run that is executing them.
  env.skipUntilEndIf = function(take) eng.skipUntilEndIf(take) end
  local done, err = false, nil
  local started = eng:playMacro(doc, {
    env = env,
    onComplete = function() done = true end,
    onError = function(e) err = e end,
  })
  return started, done, err
end

test("blocks: a false if skips its body and resumes after endIf", function()
  local env = recorder({ probe = idleProbe })
  local started, done = run({
    marker("before"),
    { type = "if", parameters = { condition = "appRunning", app = "Safari" } },
    marker("body"),
    { type = "endIf", parameters = {} },
    marker("after"),
  }, env)
  eq(true, started)
  eq(true, done)
  eq({ "before", "after" }, env.calls)
end)

test("blocks: a true if runs its body", function()
  local env = recorder({ probe = function()
    return { runningApps = function() return { "Safari" } end }
  end })
  local _, done = run({
    { type = "if", parameters = { condition = "appRunning", app = "Safari" } },
    marker("body"),
    { type = "endIf", parameters = {} },
  }, env)
  eq(true, done)
  eq({ "body" }, env.calls)
end)

test("blocks: negate inverts the branch", function()
  local env = recorder({ probe = idleProbe })
  run({
    { type = "if", parameters = { condition = "appRunning", app = "Safari", negate = true } },
    marker("body"),
    { type = "endIf", parameters = {} },
  }, env)
  eq({ "body" }, env.calls)
end)

test("blocks: nested blocks keep their balance", function()
  local env = recorder({ probe = idleProbe })
  local _, done = run({
    { type = "if", parameters = { condition = "appRunning", app = "Safari" } },
    marker("outer"),
    { type = "if", parameters = { condition = "appRunning", app = "Safari" } },
    marker("inner"),
    { type = "endIf", parameters = {} },
    marker("still-outer"),
    { type = "endIf", parameters = {} },
    marker("tail"),
  }, env)
  eq(true, done)
  -- Both bodies are skipped, but the tail still runs: the inner endIf closed
  -- the inner block, not the outer one.
  eq({ "tail" }, env.calls)
end)

test("blocks: a stray endIf does not disturb the chain", function()
  local env = recorder({ probe = idleProbe })
  run({
    marker("before"),
    { type = "endIf", parameters = {} },
    marker("after"),
  }, env)
  eq({ "before", "after" }, env.calls)
end)

test("blocks: a macro that ends inside a skipped block still completes", function()
  local env = recorder({ probe = idleProbe })
  local started, done, err = run({
    marker("before"),
    { type = "if", parameters = { condition = "appRunning", app = "Safari" } },
    marker("never"),
  }, env)
  eq(true, started)
  eq(true, done)
  eq(nil, err)
  eq({ "before" }, env.calls)
end)

test("blocks: an unknown condition is reported and the body still runs", function()
  -- The if action reports through env.notify, the same channel the marker uses,
  -- so both land in env.calls and the order is what matters.
  local env = recorder({ probe = function() return {} end })
  run({
    { type = "if", parameters = { condition = "nope" } },
    marker("body"),
    { type = "endIf", parameters = {} },
  }, env)
  eq(2, #env.calls)
  truthy(env.calls[1]:find("unknown condition", 1, true), env.calls[1])
  eq("body", env.calls[2])
end)

test("blocks: the re-entry guard is released after a skipped run", function()
  local env = recorder({ probe = idleProbe })
  local doc = {
    id = "m", name = "m", enabled = true,
    trigger = { type = "hotkey", parameters = { mods = "cmd", key = "m" } },
    actions = {
      { type = "if", parameters = { condition = "appRunning", app = "Safari" } },
      marker("body"),
      { type = "endIf", parameters = {} },
    },
  }
  local eng = engine.new({ schedule = function(_, fn) fn() end, notify = function() end })
  eq(true, eng:playMacro(doc, { env = env }))
  -- A second run must be allowed: the guard must not be stuck from the first.
  eq(true, eng:playMacro(doc, { env = env }))
end)

test("blocks: {{name}} is expanded in action parameters", function()
  local vars = require("macroforge.vars")
  vars.clear()
  vars.set("target", "Xcode")
  local env = recorder({ getVariable = function(name) return vars.get(name) end })
  run({ marker("{{target}}") }, env)
  eq({ "Xcode" }, env.calls)
end)

test("blocks: an unknown placeholder is left in place", function()
  local env = recorder({ getVariable = function() return nil end })
  run({ marker("{{missing}}") }, env)
  eq({ "{{missing}}" }, env.calls)
end)

test("blocks: setVariable stores a value the next action can read", function()
  local vars = require("macroforge.vars")
  vars.clear()
  local seen = {}
  local env = recorder({
    setVariable = function(name, value) vars.set(name, value) end,
    getVariable = function(name) return vars.get(name) end,
    notify = function(_, message) seen[#seen + 1] = tostring(message) end,
  })
  env.calls = seen
  run({
    { type = "setVariable", parameters = { name = "greeting", value = "hello" } },
    marker("{{greeting}}"),
  }, env)
  eq({ "hello" }, env.calls)
end)

