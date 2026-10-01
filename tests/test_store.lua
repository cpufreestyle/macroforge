local storeMod = require("macroforge.store")
local json = require("macroforge.json")

local function memoryFs(files)
  return {
    list = function(dir)
      local names = {}
      for name in pairs(files) do names[#names + 1] = name end
      return names
    end,
    read = function(path)
      local name = path:match("[^/]+$")
      return files[name]
    end,
    write = function(path, content)
      local name = path:match("[^/]+$")
      files[name] = content
      return true
    end,
    remove = function(path)
      local name = path:match("[^/]+$")
      local existed = files[name] ~= nil
      files[name] = nil
      return existed
    end,
  }
end

test("store: load reads valid macros and reports broken files", function()
  local files = {
    ["good.json"] = json.encode({ name = "Good", actions = { { type = "notify", parameters = { title = "t", text = "x" } } } }),
    ["broken.json"] = "{ this is not json",
    ["disabled.json"] = json.encode({ name = "Off", enabled = false, actions = { { type = "notify", parameters = { title = "t", text = "x" } } } }),
  }
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  local macros, errors = store:load()
  eq(2, #macros)
  eq(1, #errors)
  truthy(errors[1].file == "broken.json", "broken file should be reported")
  local good = store:byName("good")
  truthy(good ~= nil and good.id == "good")
  truthy(store:byName("Off") ~= nil, "byName should find disabled macros too")
end)

test("store: save normalizes, validates and writes JSON", function()
  local files = {}
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  local saved, err = store:save({
    name = "My Macro",
    actions = { { type = "PasteText", parameters = { text = "hello", restore = "false" } } },
  })
  truthy(saved and not err, "save should succeed: " .. tostring(err))
  eq("my-macro.json", saved.file)
  local written = files["my-macro.json"]
  truthy(written ~= nil, "file should be written")
  local decoded = json.decode(written)
  eq("pasteText", decoded.actions[1].type)
  eq(false, decoded.actions[1].parameters.restore)
  eq(1, #store.macros)
end)

test("store: save rejects invalid macros", function()
  local files = {}
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  local saved, err = store:save({ name = "Broken", actions = { { type = "launch", parameters = {} } } })
  truthy(saved == nil and err ~= nil, "invalid macro should be rejected")
  local count = 0
  for _ in pairs(files) do count = count + 1 end
  eq(0, count)
end)

test("store: delete removes files and rejects unsafe ids", function()
  local files = { ["a.json"] = "{}" }
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  truthy(store:delete("a"))
  falsy(store:delete("a"), "deleting a missing macro should report false")
  local _, err = store:delete("../secrets")
  truthy(err ~= nil, "path traversal ids must be refused")
end)
