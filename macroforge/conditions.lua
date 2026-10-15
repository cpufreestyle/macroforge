-- conditions.lua -- the predicate layer behind the `if` action.
--
-- Macroforge used to offer only `continueOnError`, a single switch applied to
-- the whole chain. That cannot express "do this only when Safari is running",
-- which is the single most requested branch in every macro tool: BTT ships a
-- whole conditions document (docs/1400_conditions.html) for exactly this.
--
-- Evaluation is pure: every probe the OS is asked comes in through `probe`,
-- so the whole matrix is testable without a desktop.

local conditions = {}

-- Comparison operators. Shared by the numeric and string comparisons so both
-- get the same coercion rules.
local function compare(op, left, right)
  if op == "equals" or op == "==" or op == "=" then
    return left == right
  end
  if op == "notEquals" or op == "!=" or op == "not" then
    return left ~= right
  end
  if op == "contains" then
    return type(left) == "string" and type(right) == "string"
      and left:find(right, 1, true) ~= nil
  end
  -- Everything below needs numbers.
  local l, r = tonumber(left), tonumber(right)
  if not l or not r then return false end
  if op == "greaterThan" or op == ">" then return l > r end
  if op == "greaterOrEqual" or op == ">=" then return l >= r end
  if op == "lessThan" or op == "<" then return l < r end
  if op == "lessOrEqual" or op == "<=" then return l <= r end
  return false
end

-- `probe` supplies the facts. Each entry is a function so a missing probe is
-- distinguishable from a probe that answered "no".
local defs = {}

defs.appRunning = {
  params = { { name = "app", type = "string", required = true } },
  evaluate = function(p, probe)
    local running = probe.runningApps and probe.runningApps() or {}
    local wanted = tostring(p.app or ""):lower()
    for _, name in ipairs(running) do
      if tostring(name):lower() == wanted then return true end
    end
    return false
  end,
}

defs.frontmostApp = {
  params = { { name = "app", type = "string", required = true } },
  evaluate = function(p, probe)
    local front = probe.frontmostApp and probe.frontmostApp() or ""
    return tostring(front):lower() == tostring(p.app or ""):lower()
  end,
}

defs.screenCount = {
  params = {
    { name = "op", type = "choice", required = true, default = "equals",
      choices = { "equals", "notEquals", "greaterThan", "lessThan",
                  "greaterOrEqual", "lessOrEqual" } },
    { name = "count", type = "number", required = true, default = 1 },
  },
  evaluate = function(p, probe)
    local count = probe.screenCount and probe.screenCount() or 0
    return compare(p.op, count, p.count)
  end,
}

defs.variable = {
  params = {
    { name = "name", type = "string", required = true },
    { name = "op", type = "choice", required = true, default = "equals",
      choices = { "equals", "notEquals", "contains", "greaterThan", "lessThan",
                  "greaterOrEqual", "lessOrEqual" } },
    { name = "value", type = "string", required = true },
  },
  evaluate = function(p, probe)
    local read = (probe.getVariable or function() return nil end)
    return compare(p.op, read(p.name), p.value)
  end,
}

defs.batteryLevel = {
  params = {
    { name = "op", type = "choice", required = true, default = "lessThan",
      choices = { "equals", "notEquals", "greaterThan", "lessThan",
                  "greaterOrEqual", "lessOrEqual" } },
    { name = "level", type = "number", required = true, default = 20 },
  },
  evaluate = function(p, probe)
    local level = probe.batteryLevel and probe.batteryLevel() or nil
    if level == nil then return false end
    return compare(p.op, level, p.level)
  end,
}

-- "after" and "before" are wall-clock times as "HH:MM". A window that wraps
-- midnight (22:00 to 06:00) is the common night case and must not invert.
defs.timeOfDay = {
  params = {
    { name = "after", type = "string", default = "00:00" },
    { name = "before", type = "string", default = "23:59" },
  },
  evaluate = function(p, probe)
    local now = probe.minutesOfDay and probe.minutesOfDay() or 0
    local function parse(value)
      local h, m = tostring(value or ""):match("^(%d+):(%d+)$")
      if not h then return nil end
      return (tonumber(h) or 0) * 60 + (tonumber(m) or 0)
    end
    local from, to = parse(p.after), parse(p.before)
    if not from or not to then return false end
    if from <= to then return now >= from and now <= to end
    return now >= from or now <= to
  end,
}

defs.networkReachable = {
  params = { { name = "host", type = "string", required = true } },
  evaluate = function(p, probe)
    local reach = probe.networkReachable or function() return false end
    return not not reach(p.host)
  end,
}

-- Negate is handled by the caller (`if` with negate = true), not by every
-- condition, so each predicate stays a plain question.
-- Conditions are registered in camelCase (appRunning) but the editor and the
-- action layer both lowercase what they find, so look up by folded key. A
-- linear scan keeps the registration table readable and the set is tiny.
local byLowerKey = {}
for name in pairs(defs) do byLowerKey[name:lower()] = defs[name] end

function conditions.definition(typeStr)
  return byLowerKey[tostring(typeStr or ""):lower()]
end

function conditions.types()
  local names = {}
  for name in pairs(defs) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- Evaluate one condition table: { type = "...", parameters = {...} }.
-- Returns (result, reason). reason is non-nil when the condition could not be
-- evaluated at all, which is different from evaluating to false.
function conditions.evaluate(condition, probe)
  probe = probe or {}
  if type(condition) ~= "table" or not condition.type then
    return false, "condition needs a type"
  end
  local def = conditions.definition(condition.type)
  if not def then
    return false, "unknown condition type: " .. tostring(condition.type)
  end
  local ok, result = pcall(def.evaluate, condition.parameters or {}, probe)
  if not ok then
    return false, "condition " .. tostring(condition.type) .. " failed: " .. tostring(result)
  end
  return not not result, nil
end

return conditions

