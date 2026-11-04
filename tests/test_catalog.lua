-- test_catalog.lua -- the action-picker grouping contract.
--
-- The editor groups the action type picker by catalog.lua's GROUPS mapping.
-- These tests pin that every BUILT-IN action is grouped within the known
-- set and that no group in the picker order is empty. Assertions run against
-- catalog.builtinActionTypes (the pre-registration snapshot), so the tests
-- stay valid regardless of which test files register custom actions first.

local catalog = require("macroforge.catalog")

local KNOWN = {
  ["应用"] = true,
  ["打开"] = true,
  ["文本"] = true,
  ["窗口"] = true,
  ["脚本"] = true,
  ["流程"] = true,
}

test("catalog: every built-in action declares a known picker group", function()
  for _, def in pairs(catalog.builtinActionTypes) do
    truthy(def.group ~= nil, "action " .. def.type .. " has no group")
    truthy(KNOWN[def.group] ~= nil,
      "action " .. def.type .. " uses unknown group " .. tostring(def.group))
  end
end)

test("catalog: no group in the picker order is empty", function()
  -- Mirror of the editor's ACTION_GROUP_ORDER; keeps the two sides in sync.
  local ORDER = { "应用", "打开", "文本", "窗口", "脚本", "流程" }
  local byGroup = {}
  local total = 0
  for _, def in pairs(catalog.builtinActionTypes) do
    byGroup[def.group] = (byGroup[def.group] or 0) + 1
    total = total + 1
  end
  for _, name in ipairs(ORDER) do
    truthy((byGroup[name] or 0) > 0, "group " .. name .. " has no actions")
  end
  eq(total, 21, "the built-in vocabulary is 21 actions")
end)
