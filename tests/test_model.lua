local model = require("macroforge.model")

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
