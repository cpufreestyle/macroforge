-- test_conditions.lua -- the predicates behind the if action.

local conditions = require("macroforge.conditions")

local function probe(overrides)
  local base = {
    runningApps = function() return { "Safari", "Xcode" } end,
    frontmostApp = function() return "Safari" end,
    screenCount = function() return 2 end,
    batteryLevel = function() return 42 end,
    minutesOfDay = function() return 10 * 60 end,
    networkReachable = function(host) return host == "example.com" end,
    getVariable = function(name)
      if name == "mode" then return "work" end
      if name == "empty" then return "" end
      return nil
    end,
  }
  -- A nil override removes the probe, which is how "the OS cannot answer"
  -- is expressed. Assigning nil would be the same as not overriding at all.
  for k, v in pairs(overrides or {}) do
    if v == nil then base[k] = nil else base[k] = v end
  end
  return base
end

local function check(typeStr, params, overrides)
  local result, reason = conditions.evaluate(
    { type = typeStr, parameters = params }, probe(overrides))
  return result, reason
end

test("conditions: appRunning matches case-insensitively", function()
  eq(true, check("appRunning", { app = "safari" }))
  eq(true, check("appRunning", { app = "XCODE" }))
  eq(false, check("appRunning", { app = "Mail" }))
end)

test("conditions: a missing probe answers false, not an error", function()
  -- Lua cannot store nil in a table, so "the OS cannot answer" is expressed by
  -- a probe table that simply lacks the key. Removing it here (rather than
  -- assigning nil) is what makes the override real.
  local base = probe()
  base.runningApps = nil
  local result, reason = conditions.evaluate(
    { type = "appRunning", parameters = { app = "Safari" } }, base)
  eq(false, result)
  eq(nil, reason)
end)

test("conditions: frontmostApp compares the front app", function()
  eq(true, check("frontmostApp", { app = "Safari" }))
  eq(false, check("frontmostApp", { app = "Xcode" }))
end)

test("conditions: screenCount honours every operator", function()
  eq(true, check("screenCount", { op = "equals", count = 2 }))
  eq(false, check("screenCount", { op = "equals", count = 1 }))
  eq(true, check("screenCount", { op = "greaterThan", count = 1 }))
  eq(true, check("screenCount", { op = "lessOrEqual", count = 2 }))
  eq(false, check("screenCount", { op = "lessThan", count = 2 }))
end)

test("conditions: numeric comparison rejects non-numbers", function()
  local result, reason = check("screenCount", { op = "greaterThan", count = "abc" })
  eq(false, result)
  eq(nil, reason)
end)

test("conditions: variable reads through the probe", function()
  eq(true, check("variable", { name = "mode", op = "equals", value = "work" }))
  eq(true, check("variable", { name = "mode", op = "contains", value = "wor" }))
  eq(false, check("variable", { name = "mode", op = "notEquals", value = "work" }))
  -- An empty string is a value that differs from "work".
  eq(true, check("variable", { name = "empty", op = "notEquals", value = "work" }))
  -- An unset variable only equals another unset value.
  eq(true, check("variable", { name = "nope", op = "equals", value = "" }) == false)
end)

test("conditions: batteryLevel is absent on a desktop", function()
  eq(false, check("batteryLevel", { op = "lessThan", level = 20 },
    { batteryLevel = function() return nil end }))
  eq(true, check("batteryLevel", { op = "lessThan", level = 50 }))
end)

test("conditions: timeOfDay covers a plain window and a midnight wrap", function()
  eq(true, check("timeOfDay", { after = "09:00", before = "11:00" }))
  eq(false, check("timeOfDay", { after = "11:00", before = "12:00" }))
  -- A window that wraps midnight (22:00 to 06:00) must not invert: 10:00 is
  -- outside it, and 23:00 is inside it.
  eq(false, check("timeOfDay", { after = "22:00", before = "06:00" }))
  eq(true, check("timeOfDay", { after = "22:00", before = "06:00" },
    { minutesOfDay = function() return 23 * 60 end }))
  eq(true, check("timeOfDay", { after = "22:00", before = "06:00" },
    { minutesOfDay = function() return 2 * 60 end }))
  -- The same window spelled the other way round excludes 23:00.
  eq(false, check("timeOfDay", { after = "06:00", before = "22:00" },
    { minutesOfDay = function() return 23 * 60 end }))
end)

test("conditions: an unparsable time is false, not an error", function()
  eq(false, check("timeOfDay", { after = "noon", before = "11:00" }))
end)

test("conditions: networkReachable takes the host as an argument", function()
  eq(true, check("networkReachable", { host = "example.com" }))
  eq(false, check("networkReachable", { host = "other.com" }))
end)

test("conditions: an unknown type is reported as a reason", function()
  local result, reason = check("nope", {})
  eq(false, result)
  truthy(reason and reason:find("unknown condition", 1, true), "expected a reason, got " .. tostring(reason))
end)

test("conditions: a missing type is a reason, not a crash", function()
  local result, reason = conditions.evaluate(nil, probe())
  eq(false, result)
  truthy(reason, "expected a reason")
end)

test("conditions: a throwing probe is caught and reported", function()
  local result, reason = conditions.evaluate(
    { type = "appRunning", parameters = { app = "Safari" } },
    { runningApps = function() error("boom") end })
  eq(false, result)
  truthy(reason and reason:find("boom", 1, true), "expected the error text, got " .. tostring(reason))
end)

test("conditions: types are listed for the editor", function()
  local names = conditions.types()
  local seen = {}
  for _, name in ipairs(names) do seen[name] = true end
  truthy(seen.appRunning, "appRunning missing from " .. table.concat(names, ","))
  truthy(seen.variable, "variable missing from " .. table.concat(names, ","))
  -- The list must be sorted so the editor shows a stable order.
  local sorted = {}
  for i, name in ipairs(names) do sorted[i] = name end
  table.sort(sorted)
  eq(sorted, names)
end)

