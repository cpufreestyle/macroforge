local model = require("macroforge.model")
local json  = require("macroforge.json")

test("model: normalize derives id and trims name", function()
  local macro = model.normalize({ name = "  Open   Stack  " })
  eq("open-stack", macro.id)
  eq("Open   Stack", macro.name)
  eq(true, macro.enabled)
end)

test("model: normalize coerces editor strings", function()
  local macro = model.normalize({
    name = "Snap",
    trigger = { type = "hotkey", parameters = { mods = "cmd, alt", key = "left" } },
    actions = {
      { type = "MoveWindow", parameters = { x = "10", y = "5", width = "80", height = "90" } },
      { type = "pasteText", parameters = { text = "hi", restore = "false" } },
    },
  })
  eq("moveWindow", macro.actions[1].type)
  eq(10, macro.actions[1].parameters.x)
  eq(90, macro.actions[1].parameters.height)
  eq(false, macro.actions[2].parameters.restore)
  eq("left", macro.trigger.parameters.key)
end)

test("model: choice defaults are applied", function()
  local macro = model.normalize({ name = "Snap", actions = { { type = "snapWindow", parameters = {} } } })
  eq("left", macro.actions[1].parameters.position)
end)

test("model: number params get their declared default", function()
  local macro = model.normalize({ name = "Wait", actions = { { type = "delay", parameters = {} } } })
  eq(1, macro.actions[1].parameters.seconds)
  eq(0, #model.validate(macro))
end)

test("model: normalize keeps a bad name empty so validation explains it", function()
  local macro = model.normalize({ id = "../evil", name = "" })
  eq("", macro.name)
  local errors = model.validate(macro)
  truthy(table.concat(errors, "|"):find("name is required") ~= nil, "name error missing: " .. table.concat(errors, "|"))
  truthy(table.concat(errors, "|"):find("invalid macro id") ~= nil, "id error missing")
end)

test("model: validate accepts a good macro", function()
  local macro = model.normalize({
    name = "Good",
    trigger = { type = "hotkey", parameters = { mods = "cmd", key = "k" } },
    actions = { { type = "launch", parameters = { app = "Safari" } } },
  })
  eq(0, #model.validate(macro))
end)

test("model: validate catches unknown trigger and actions", function()
  local macro = model.normalize({
    id = "../evil",
    name = "",
    trigger = { type = "nope", parameters = {} },
    actions = {
      { type = "launch", parameters = {} },
      { type = "wat", parameters = {} },
    },
  })
  local joined = table.concat(model.validate(macro), "|")
  truthy(joined:find("invalid macro id") ~= nil, joined)
  truthy(joined:find("name is required") ~= nil, joined)
  truthy(joined:find("unknown trigger") ~= nil, joined)
  truthy(joined:find("unknown type") ~= nil, joined)
  truthy(joined:find("missing required parameter") ~= nil, joined)
end)

test("model: validate rejects invalid choices", function()
  local macro = model.normalize({
    name = "Bad choice",
    actions = { { type = "snapWindow", parameters = { position = "sideways" } } },
  })
  local errors = model.validate(macro)
  eq(1, #errors)
  truthy(errors[1]:find("sideways") ~= nil, errors[1])
end)

test("model: summarize reads trigger and actions", function()
  local macro = model.normalize({
    name = "Snap",
    trigger = { type = "typed", parameters = { string = ";date" } },
    actions = { { type = "launch", parameters = { app = "X" } } },
  })
  truthy(model.summarize(macro):find('type ";date"') ~= nil, "summary: " .. model.summarize(macro))
end)

-- A JSON null decodes into the NULL sentinel table. Everything that compares
-- by identity used to break once the document was deep-copied, so nulls leaked
-- into string parameters as a table address and passed validation.
test("model: a null parameter is treated as absent, not stringified", function()
  local macro = model.normalize({
    name = "Nulls",
    trigger = { type = "hotkey", parameters = { mods = "cmd", key = "k" } },
    actions = {
      { type = "typeText", parameters = { text = json.NULL } },
      { type = "delay", parameters = { seconds = json.NULL } },
      { type = "snapWindow", parameters = { position = json.NULL } },
    },
  })
  local problems = model.validate(macro)
  truthy(#problems >= 1, "a null for a required string must be reported, got: "
    .. table.concat(problems, " | "))
  truthy(table.concat(problems, "|"):find("json.null", 1, true) == nil,
    "the sentinel must never be stringified into a message: " .. table.concat(problems, " | "))
  eq(1, macro.actions[2].parameters.seconds)
  eq("left", macro.actions[3].parameters.position)
end)

test("model: a null trigger means no trigger", function()
  local macro = model.normalize({
    name = "Null trigger",
    trigger = json.NULL,
    actions = { { type = "notify", parameters = { title = "t", text = "x" } } },
  })
  truthy(macro.trigger == nil, "a null trigger should normalise to no trigger")
  eq(0, #model.validate(macro))
end)

test("model: a null name derives an id instead of stringifying the sentinel", function()
  local macro = model.normalize({
    name = json.NULL,
    actions = { { type = "notify", parameters = { title = "t", text = "x" } } },
  })
  truthy(type(macro.name) == "string", "name must be a string, got " .. type(macro.name))
  truthy(macro.name:find("json.null", 1, true) == nil,
    "the sentinel leaked into the name: " .. tostring(macro.name))
  truthy(macro.id:find("json.null", 1, true) == nil,
    "the sentinel leaked into the id: " .. tostring(macro.id))
end)

test("model: null elements in the actions array are dropped", function()
  local macro = model.normalize({
    name = "Hole",
    actions = {
      json.NULL,
      { type = "notify", parameters = { title = "t", text = "x" } },
    },
  })
  eq(1, #macro.actions)
  eq("notify", macro.actions[1].type)
  eq(0, #model.validate(macro))
end)

test("util: deepCopy preserves the json.NULL sentinel identity", function()
  local util = require("macroforge.util")
  local copied = util.deepCopy({ trigger = json.NULL })
  truthy(copied.trigger == json.NULL,
    "deepCopy must not clone the NULL sentinel or identity comparisons break")
end)

