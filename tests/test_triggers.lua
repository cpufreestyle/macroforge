local triggers = require("macroforge.triggers")

test("triggers: typed string fires on suffix match", function()
  local entries = { { string = ";date", delete = true, macro = "M1" } }
  local state = { buffer = "" }
  state, matches = triggers.feedTyped(state, ";", nil, entries)
  eq(0, #matches)
  for _, key in ipairs({ "d", "a", "t", "e" }) do
    state, matches = triggers.feedTyped(state, key, nil, entries)
  end
  eq(1, #matches)
  eq("M1", matches[1].macro)
  eq(5, matches[1].charsToDelete)
  eq("", state.buffer)
end)

test("triggers: typed string can keep the typed characters", function()
  local entries = { { string = "zz", delete = false, macro = "M" } }
  local state = { buffer = "" }
  state, matches = triggers.feedTyped(state, "z", nil, entries)
  state, matches = triggers.feedTyped(state, "z", nil, entries)
  eq(1, #matches)
  eq(0, matches[1].charsToDelete)
end)

test("triggers: modifiers and special keys reset the buffer", function()
  local entries = { { string = ";x", delete = true, macro = "M" } }
  local state = { buffer = ";x" }
  state, matches = triggers.feedTyped(state, "k", { "cmd" }, entries)
  eq(0, #matches)
  eq("", state.buffer)
  state = { buffer = ";x" }
  state, matches = triggers.feedTyped(state, "space", nil, entries)
  eq(0, #matches)
  eq("", state.buffer)
end)

test("triggers: several typed triggers can coexist", function()
  local entries = {
    { string = ";mail", delete = true, macro = "A" },
    { string = ";time", delete = true, macro = "B" },
  }
  local state = { buffer = "" }
  for _, key in ipairs({ ";", "t", "i", "m", "e" }) do
    state, matches = triggers.feedTyped(state, key, nil, entries)
  end
  eq(1, #matches)
  eq("B", matches[1].macro)
end)

test("triggers: long buffers are truncated", function()
  local entries = {}
  local state = { buffer = "" }
  for i = 1, 100 do
    state = triggers.feedTyped(state, "a", nil, entries)
  end
  truthy(#state.buffer <= 64, "buffer should be bounded, got " .. #state.buffer)
end)

test("triggers: hotkey binding wires through the api", function()
  local bound = nil
  local fired = 0
  local api = {
    hotkeyBind = function(mods, key, fn)
      bound = { mods = mods, key = key, fn = fn }
      return { delete = function() end }
    end,
  }
  local handle = triggers.bind({ type = "hotkey", parameters = { mods = "cmd,ctrl", key = "k" } },
    function() fired = fired + 1 end, api)
  truthy(bound ~= nil, "hotkey should be bound")
  eq({ "ctrl", "cmd" }, bound.mods)
  eq("k", bound.key)
  bound.fn()
  eq(1, fired)
  handle.stop()
end)

test("triggers: interval uses seconds", function()
  local every = nil
  local api = { timerEvery = function(seconds) every = seconds; return { stop = function() end } end }
  triggers.bind({ type = "interval", parameters = { minutes = 5 } }, function() end, api)
  eq(300, every)
end)

test("triggers: appLaunch only fires on launched events for the right app", function()
  local handler = nil
  local api = { applicationWatcher = function(fn) handler = fn; return { stop = function() end } end }
  local fired = 0
  triggers.bind({ type = "appLaunch", parameters = { app = "zoom.us" } },
    function() fired = fired + 1 end, api)
  handler("zoom.us", "launched")
  handler("zoom.us", "activated")
  handler("Safari", "launched")
  eq(1, fired)
end)

test("triggers: bindTyped dispatches from a shared eventtap", function()
  local handler = nil
  local tap = { start = function() end, stop = function() end }
  local api = { eventtap = function(fn) handler = fn; return tap end }
  local fired, deleted = {}, 0
  local entries = { { string = ";hi", delete = true, macro = "M" } }
  triggers.bindTyped(entries, function(macro, chars)
    fired[#fired + 1] = macro
    deleted = chars
  end, api)
  handler(";", nil)
  handler("h", nil)
  handler("i", nil)
  eq({ "M" }, fired)
  eq(3, deleted)
end)

test("triggers: bindTyped with no entries is a no-op", function()
  local handle = triggers.bindTyped({}, function() end, { eventtap = function() error("should not be called") end })
  handle.stop()
end)
