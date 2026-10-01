-- test_macros.lua -- smoke tests for the example macros shipped in macros/.
--
-- These read the real files (read-only) so a broken example fails the suite
-- instead of failing on the user's desktop the first time Hammerspoon loads.

local store   = require("macroforge.store")
local model   = require("macroforge.model")
local catalog = require("macroforge.catalog")

-- Resolve the repository root from the runner's path so the tests also work
-- when invoked with an absolute path from another directory.
local root = (arg[0] or ""):gsub("tests/run%.lua$", "")
local macrosDir = root .. "macros"

local fs = {
  list = function(dir)
    local pipe = io.popen(string.format("ls -1 %q 2>/dev/null", dir))
    if not pipe then return {} end
    local out, line = {}, pipe:read("*l")
    while line do
      out[#out + 1] = line
      line = pipe:read("*l")
    end
    pipe:close()
    return out
  end,
  read = function(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local content = handle:read("*a")
    handle:close()
    return content
  end,
}

local macros, errors = store.new({ fs = fs, macrosDir = macrosDir }):load()

test("macros: shipped examples load without validation errors", function()
  local detail = {}
  for _, e in ipairs(errors) do
    detail[#detail + 1] = e.file .. ": " .. tostring(e.error)
  end
  eq(0, #errors, table.concat(detail, "\n"))
  truthy(#macros >= 5, "expected at least 5 example macros, got " .. #macros)
end)

test("macros: ids are unique and every type resolves in the catalog", function()
  local seen = {}
  for _, macro in ipairs(macros) do
    truthy(type(macro.id) == "string" and macro.id ~= "", "a macro file has no usable id")
    truthy(seen[macro.id] == nil, "duplicate macro id: " .. tostring(macro.id))
    seen[macro.id] = true
    truthy(type(macro.name) == "string" and macro.name ~= "", macro.id .. " has no name")
    truthy(#macro.actions > 0, macro.id .. " has no actions")
    for _, action in ipairs(macro.actions) do
      truthy(catalog.actionDef(action.type) ~= nil,
        macro.id .. " uses unknown action " .. tostring(action.type))
    end
    if macro.trigger then
      truthy(catalog.triggerDef(macro.trigger.type) ~= nil,
        macro.id .. " uses unknown trigger " .. tostring(macro.trigger.type))
    end
    local problems = model.validate(macro)
    eq(0, #problems, macro.id .. ": " .. table.concat(problems, "; "))
  end
end)

test("macros: every shipped example uses a documented trigger shape", function()
  local withTrigger = 0
  for _, macro in ipairs(macros) do
    if macro.trigger then
      withTrigger = withTrigger + 1
      local def = catalog.triggerDef(macro.trigger.type)
      local params = macro.trigger.parameters or {}
      for _, p in ipairs(def.params or {}) do
        if p.required then
          truthy(params[p.name] ~= nil,
            macro.id .. " trigger " .. macro.trigger.type .. " is missing " .. p.name)
        end
      end
    end
  end
  truthy(withTrigger >= 4, "expected most examples to carry a trigger, got " .. withTrigger)
end)
