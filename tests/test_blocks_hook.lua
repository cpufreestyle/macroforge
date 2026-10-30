-- test_blocks_hook.lua -- the env handed to actions must carry a live block
-- counter, not the no-op stub init.lua installs as a default.
--
-- init.lua builds ONE env for the whole session and installs a no-op
-- `env.skipUntilEndIf` on it (a guard for a bare action call from the
-- console). The engine used to publish its own setter as
-- `engine.skipUntilEndIf` and never write it into the env it passes to
-- actions, so every production if/endIf called the no-op and skipped
-- nothing. These tests assert the engine installs a working hook per run
-- and that concurrent runs each get their own.

local engineMod = require("macroforge.engine")
local model      = require("macroforge.model")

local function marker(tag)
  return { type = "notify", parameters = { title = tag, text = tag } }
end

local idleProbe = function()
  return { runningApps = function() return {} end }
end

local function doc(id, app)
  return {
    id = id, name = id, enabled = true,
    trigger = { type = "hotkey", parameters = { mods = "cmd", key = "x" } },
    actions = {
      { type = "if", parameters = { condition = "appRunning", app = app } },
      marker(id .. "-body"),
      { type = "endIf", parameters = {} },
      marker(id .. "-tail"),
    },
  }
end

test("blocks hook: the env passed to actions gets a working skip hook", function()
  local eng = engineMod.new({ schedule = function(_, fn) fn() end, notify = function() end })
  local calls = {}
  -- The stub init.lua installs. It must be replaced by the engine, not left in
  -- place, because actions receive this very table.
  local env = {
    notify = function(_, m) calls[#calls + 1] = tostring(m) end,
    probe = idleProbe,
    skipUntilEndIf = function() end,
  }
  local started, done = eng:playMacro(doc("a", "Safari"), { env = env })
  eq(true, started)
  -- Safari is not running, so the false branch must skip the body.
  eq({ "a-tail" }, calls)
end)

test("blocks hook: a true branch still runs the body through the hook", function()
  local eng = engineMod.new({ schedule = function(_, fn) fn() end, notify = function() end })
  local calls = {}
  local env = {
    notify = function(_, m) calls[#calls + 1] = tostring(m) end,
    probe = function() return { runningApps = function() return { "Safari" } end } end,
    skipUntilEndIf = function() end,
  }
  eng:playMacro(doc("a", "Safari"), { env = env })
  eq({ "a-body", "a-tail" }, calls)
end)

test("blocks hook: a nested macro uses its own counter, not the parent's", function()
  local eng = engineMod.new({ schedule = function(_, fn) fn() end, notify = function() end })
  local calls = {}
  local env = {
    notify = function(_, m) calls[#calls + 1] = tostring(m) end,
    probe = idleProbe,
    skipUntilEndIf = function() end,
  }
  local inner = doc("inner", "Safari")
  local outer = {
    id = "outer", name = "outer", enabled = true,
    trigger = { type = "hotkey", parameters = { mods = "cmd", key = "x" } },
    actions = {
      { type = "playMacro", parameters = { macro = "inner" } },
      marker("outer-tail"),
    },
  }
  local function play(reference, callbacks)
    callbacks = callbacks or {}
    return eng:playMacro(reference, {
      env = env,
      resolve = function(name) return name == "inner" and inner or nil end,
      playMacro = play,
      onComplete = callbacks.onComplete,
      onError = callbacks.onError,
    })
  end
  local startedOuter = play(outer)
  eq(true, startedOuter)
  eq({ "inner-tail", "outer-tail" }, calls)
end)

-- Two runs alive at once. `a` suspends in a delay with its block still ahead of
-- it, `b` runs its own false branch to completion in that window, and only then
-- does `a` resume. The env is one session-wide table, so the only thing that can
-- tell these two apart is which run the hook forwards to: a hook that reached the
-- wrong run would leave `a` skipping a body it never entered, or `b` skipping
-- none. The two continuations are kept in separate queues so `a` really is still
-- suspended while `b` finishes -- one queue would fire `a`'s timer first.
test("blocks hook: a suspended run keeps its own block state", function()
  -- Two queues on purpose. `schedule` carries engine continuations and
  -- env.timerAfter carries deferred work, exactly as hs.timer.doAfter does in
  -- production, so pumping one leaves the other untouched.
  local steps, timers = {}, {}
  local eng = engineMod.new({
    schedule = function(_, fn) steps[#steps + 1] = fn end,
    notify = function() end,
  })
  local function step()
    local fn = table.remove(steps, 1)
    if fn then fn() end
  end
  local function fireTimer()
    local fn = table.remove(timers, 1)
    if fn then fn() end
  end
  local function runToSettle()
    local guard = 0
    while #steps > 0 do
      guard = guard + 1
      assert(guard < 64, "the chain never settled")
      step()
    end
  end

  local calls = {}
  local env = {
    notify = function(_, m) calls[#calls + 1] = tostring(m) end,
    probe = idleProbe,
    timerAfter = function(_, fn) timers[#timers + 1] = fn end,
    skipUntilEndIf = function() end,
  }

  local a = {
    id = "a", name = "a", enabled = true,
    trigger = { type = "hotkey", parameters = { mods = "cmd", key = "a" } },
    actions = {
      { type = "delay", parameters = { seconds = 0.1 } },
      { type = "if", parameters = { condition = "appRunning", app = "Safari" } },
      marker("a-body"),
      { type = "endIf", parameters = {} },
      marker("a-tail"),
    },
  }
  local b = doc("b", "Safari")

  eq(true, eng:playMacro(a, { env = env }))
  step()
  eq({}, calls, "a is suspended in the delay, so nothing has run yet")
  truthy(eng:isRunning("a"), "a is still live while suspended")

  -- b runs to completion inside that window, with a still held open.
  eq(true, eng:playMacro(b, { env = env }))
  runToSettle()
  eq({ "b-tail" }, calls, "b skips its own false body while a is suspended")
  truthy(eng:isRunning("a"), "b finishing does not release a's guard")

  -- a's timer fires last and its own block is still ahead of it.
  fireTimer()
  runToSettle()
  eq({ "b-tail", "a-tail" }, calls, "a resumes and skips its own false body")
  falsy(eng:isRunning("a"))
end)
