-- triggers.lua -- trigger matching and binding.
--
-- Matching logic is pure and unit-tested; binding goes through an injected
-- `api` so the same code runs under Hammerspoon and under the test harness.

local triggers = {}

local catalog = require("macroforge.catalog")
local util = require("macroforge.util")

local MAX_BUFFER = 64

-- Pure typed-string matching.
--   state:    { buffer = "..."}
--   keyName:  single-character key name (e.g. "d"), or nil/other for special keys
--   modifiers: array of held modifiers, nil when none
--   entries:  { { string = ";date", delete = true, macro = <payload> } }
-- Returns (newState, matches) where each match is { macro, charsToDelete }.
function triggers.feedTyped(state, keyName, modifiers, entries)
  local newState = { buffer = (state and state.buffer) or "" }
  if modifiers and #modifiers > 0 then
    newState.buffer = ""
    return newState, {}
  end
  if type(keyName) ~= "string" or #keyName ~= 1 then
    newState.buffer = ""
    return newState, {}
  end
  newState.buffer = newState.buffer .. keyName
  if #newState.buffer > MAX_BUFFER then
    newState.buffer = newState.buffer:sub(-MAX_BUFFER)
  end
  local matches = {}
  for _, entry in ipairs(entries or {}) do
    local text = tostring(entry.string or "")
    if #text > 0 and #newState.buffer >= #text and newState.buffer:sub(-#text) == text then
      matches[#matches + 1] = {
        macro = entry.macro,
        charsToDelete = (entry.delete == false) and 0 or #text,
      }
      newState.buffer = ""
    end
  end
  return newState, matches
end

function triggers.describe(trigger)
  if type(trigger) ~= "table" or not trigger.type then return "no trigger" end
  local p = trigger.parameters or {}
  if trigger.type == "hotkey" then
    return (p.mods and p.mods ~= "" and (p.mods .. "+" .. tostring(p.key)) or tostring(p.key))
  elseif trigger.type == "typed" then
    return 'type "' .. tostring(p.string) .. '"'
  elseif trigger.type == "appLaunch" then
    return tostring(p.app) .. " launches"
  elseif trigger.type == "windowFocused" then
    return tostring(p.app) .. " focused"
  elseif trigger.type == "interval" then
    return "every " .. tostring(p.minutes) .. " minutes"
  end
  return trigger.type
end

local function stopHandle(handle)
  if not handle then return end
  if type(handle) == "function" then
    handle()
  elseif handle.delete then
    handle:delete()
  elseif handle.stop then
    handle:stop()
  end
end

-- Bind a single trigger. `api` provides:
--   api.hotkeyBind(mods, key, fn)
--   api.applicationWatcher(fn)   -- fn(appName, eventName)
--   api.windowWatcher(appName, fn)
--   api.timerEvery(seconds, fn)
-- Returns { stop = function() }.
function triggers.bind(trigger, fire, api)
  if type(trigger) ~= "table" or not trigger.type then
    return { stop = function() end }
  end
  local p = trigger.parameters or {}
  if trigger.type == "hotkey" then
    local mods = util.splitMods(p.mods)
    local handle = api.hotkeyBind(mods, tostring(p.key or ""), fire)
    return { stop = function() stopHandle(handle) end }
  elseif trigger.type == "interval" then
    local seconds = math.max(1, math.floor((tonumber(p.minutes) or 30) * 60))
    local handle = api.timerEvery(seconds, fire)
    return { stop = function() stopHandle(handle) end }
  elseif trigger.type == "appLaunch" then
    local handle = api.applicationWatcher(function(appName, eventName)
      if eventName == "launched" and tostring(appName):lower() == tostring(p.app):lower() then
        fire()
      end
    end)
    return { stop = function() stopHandle(handle) end }
  elseif trigger.type == "windowFocused" then
    local handle = api.windowWatcher(tostring(p.app), fire)
    return { stop = function() stopHandle(handle) end }
  end
  return { stop = function() end }
end

-- One shared eventtap serves every typed-string trigger.
--   api.eventtap(fn) -- fn(keyName, modifiers)
--   fire(macro, charsToDelete)
function triggers.bindTyped(entries, fire, api)
  if not entries or #entries == 0 then
    return { stop = function() end }
  end
  local state = { buffer = "" }
  local handle = api.eventtap(function(keyName, modifiers)
    local matches
    state, matches = triggers.feedTyped(state, keyName, modifiers, entries)
    for _, match in ipairs(matches) do
      fire(match.macro, match.charsToDelete)
    end
  end)
  return { stop = function() stopHandle(handle) end }
end

return triggers
