local fake = require("tests.fake_env")
local actions = require("macroforge.actions")

local function runAction(actionType, params)
  local env = fake.new()
  local def = assert(actions.definition(actionType), "no action " .. actionType)
  local done = false
  def.run(env, params, function() done = true end, function() end)
  return env, done
end

test("actions: snapWindow uses screen fractions", function()
  local env = runAction("snapWindow", { position = "left" })
  eq({ "setFocusedWindowRect", 0, 0, 720, 900 }, { env.calls[1].name, unpack(env.calls[1].args) })
end)

test("actions: snapWindow center is centered", function()
  local env = runAction("snapWindow", { position = "center" })
  eq({ "setFocusedWindowRect", 144, 90, 1152, 720 }, { env.calls[1].name, unpack(env.calls[1].args) })
end)

test("actions: snapWindow activates an app first", function()
  local env = runAction("snapWindow", { position = "right", app = "Safari" })
  eq({ "activate", "setFocusedWindowRect" }, env:names())
  eq({ "setFocusedWindowRect", 720, 0, 720, 900 }, { env.calls[2].name, unpack(env.calls[2].args) })
end)

test("actions: moveWindow maps percentages onto the screen", function()
  local env = runAction("moveWindow", { x = 10, y = 20, width = 30, height = 40 })
  eq({ "setFocusedWindowRect", 144, 180, 432, 360 }, { env.calls[1].name, unpack(env.calls[1].args) })
end)

test("actions: pasteText replaces and restores the clipboard", function()
  local env = fake.new()
  env.clipboard = "previous"
  local def = assert(actions.definition("pasteText"))
  def.run(env, { text = "signature", restore = true }, function() end, function() end)
  eq({ "setClipboard", "paste", "timerAfter", "setClipboard" }, env:names())
  eq(0.4, env.calls[3].args[1])
  eq("previous", env.clipboard)
end)

test("actions: pasteText can keep the new clipboard", function()
  local env = fake.new()
  local def = assert(actions.definition("pasteText"))
  def.run(env, { text = "keep me", restore = false }, function() end, function() end)
  eq({ "setClipboard", "paste" }, env:names())
  eq("keep me", env.clipboard)
end)

test("actions: delay defers completion through the timer", function()
  local env = fake.new()
  env.autoTimers = false
  local completed = false
  local def = assert(actions.definition("delay"))
  def.run(env, { seconds = 2 }, function() completed = true end, function() end)
  falsy(completed, "completion must wait for the timer")
  eq(2, env.calls[1].args[1])
end)

test("actions: playMacro chains into another macro", function()
  local env = fake.new()
  local played = nil
  local completed = false
  local def = assert(actions.definition("playMacro"))
  def.run(env, { macro = "Other macro" }, function() completed = true end,
    function(name, callbacks)
      played = name
      callbacks.onComplete()
    end)
  eq("Other macro", played)
  truthy(completed, "chained macro completion should finish the action")
end)

test("actions: runShell and runAppleScript pass through", function()
  local env = runAction("runShell", { command = "say hi" })
  eq("runShell", env.calls[1].name)
  eq("say hi", env.calls[1].args[1])
  local env2 = runAction("runAppleScript", { script = 'tell application "Music" to next track' })
  eq("runAppleScript", env2.calls[1].name)
end)

test("actions: pressKeys normalises modifiers", function()
  local env = runAction("pressKeys", { mods = "cmd, alt,cmd", key = "v" })
  eq({ "pressKeys", "alt+cmd", "v" }, { env.calls[1].name, unpack(env.calls[1].args) })
end)

test("actions: custom actions can be registered", function()
  actions.register("sayHello", { run = function(env, params, done)
    env.notify(params.title, "hello")
    done()
  end })
  local env = runAction("sayHello", { title = "Hi" })
  eq("notify", env.calls[1].name)
  eq("hello", env.calls[1].args[2])
end)
