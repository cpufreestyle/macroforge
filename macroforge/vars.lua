-- vars.lua -- named variables shared across macros.
--
-- BTT keeps a global variable table every action can read and write; Macroforge
-- had no equivalent, so a macro could not remember anything between runs or
-- pass a value to a nested macro. This module is that table.
--
-- The state is intentionally not persisted: it lives for as long as
-- Hammerspoon runs, which is what most triggers need ("what did I last
-- launch?"). Persisting it would raise the question of when to flush, and a
-- stale file is worse than a fresh start.

local vars = {}

-- Values are stored by exact key. Keys are trimmed but not case-folded: a
-- macro that sets "LastApp" and reads "lastapp" is a typo, and silently
-- matching it hides the typo.
local store = {}

local function key(name)
  return tostring(name or "")
end

function vars.set(name, value)
  store[key(name)] = value
  return value
end

function vars.get(name)
  return store[key(name)]
end

-- Return the value, or `fallback` when unset. A stored nil is the same as
-- unset, so there is no way to distinguish "never set" from "set to nothing".
function vars.getOr(name, fallback)
  local value = store[key(name)]
  if value == nil then return fallback end
  return value
end

-- Text actions interpolate values into templates. Only a well-formed
-- {{name}} is substituted; anything else is left exactly as typed so that
-- surrounding text survives a typo.
function vars.expand(text, resolver)
  if type(text) ~= "string" then return text end
  local resolve = resolver or vars.get
  return (text:gsub("{{%s*([%w_%-%.]+)%s*}}", function(name)
    local value = resolve(name)
    if value == nil then return "{{" .. name .. "}}" end
    return tostring(value)
  end))
end

function vars.clear(name)
  if name == nil then
    store = {}
    return
  end
  store[key(name)] = nil
end

-- Sorted key/value pairs, for choosers and the editor.
function vars.list()
  local names = {}
  for name in pairs(store) do names[#names + 1] = name end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    out[#out + 1] = { name = name, value = store[name] }
  end
  return out
end

return vars

