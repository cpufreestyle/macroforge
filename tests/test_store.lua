local storeMod = require("macroforge.store")
local json = require("macroforge.json")
local Q = string.char(34) .. "file" .. string.char(34)

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

test("store: save never writes the internal file field into the document", function()
  local files = {}
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  local saved = assert(store:save({ id = "k", name = "K",
    actions = { { type = "notify", parameters = { title = "t", text = "x" } } } }))
  local written = files["k.json"]
  truthy(written ~= nil, "the macro file should be written")
  truthy(written:find(Q, 1, true) == nil,
    "the serialised document must not carry the store's internal file field")
  local decoded = json.decode(written)
  eq(nil, decoded.file, "decoded documents must not expose a file key")
  truthy(saved.file ~= nil, "the in-memory macro still knows its file name")
end)

test("store: renaming the id removes the previous file instead of duplicating", function()
  local files = {}
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  store:save({ id = "old-name", name = "Old name",
    actions = { { type = "notify", parameters = { title = "t", text = "x" } } } })
  local before = store:byId("old-name")
  local after = store:saveRenaming({ id = "new-name", name = "Old name",
    actions = { { type = "notify", parameters = { title = "t", text = "x" } } } }, before.id)
  truthy(after, "the renamed macro should be saved")
  eq("new-name", after.id)
  eq(nil, files["old-name.json"], "the file for the previous id must be gone")
  truthy(files["new-name.json"] ~= nil, "the file for the new id must exist")
  local names = {}
  for name in pairs(files) do names[#names + 1] = name end
  eq(1, #names, "a rename must not leave two files behind, got: "
    .. table.concat(names, ", "))
end)

test("store: saveRenaming refuses unsafe previous ids", function()
  local files = {}
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  local first = store:save({ id = "keep", name = "K",
    actions = { { type = "notify", parameters = { title = "t", text = "x" } } } })
  local saved = store:saveRenaming({ id = "keep", name = "K",
    actions = { { type = "notify", parameters = { title = "t", text = "x" } } } }, "../secrets")
  truthy(saved, "a bogus previous id must not break the save")
  eq("keep", first.id)
  truthy(files["keep.json"] ~= nil, "the real macro file must survive")
end)


test("store: two macros with no explicit id get distinct files", function()
  local files = {}
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  local first = store:save({ actions = { { type = "notify", parameters = { title = "t", text = "A" } } } })
  local second = store:save({ actions = { { type = "notify", parameters = { title = "t", text = "B" } } } })
  truthy(first ~= nil and second ~= nil, "both saves should succeed")
  truthy(first.id ~= second.id,
    "a nameless macro must not reuse another macro's id, got " .. tostring(first.id)
    .. " twice")
  eq(2, (function() local n = 0 for _ in pairs(files) do n = n + 1 end return n end)())
  truthy(files[first.id .. ".json"] ~= nil, "the first macro must still have its file")
  truthy(files[second.id .. ".json"] ~= nil, "the second macro must have its own file")
  eq(2, #store:load())
end)

test("store: invalid macros are reported and left out of the loaded list", function()
  -- A macro that fails validation used to stay in store.macros, so it showed up
  -- in the chooser and the editor and could be toggled although save() would
  -- then refuse it.
  local files = {
    ["good.json"] = json.encode({ name = "Good",
      actions = { { type = "notify", parameters = { title = "t", text = "x" } } } }),
    ["invalid.json"] = json.encode({ id = "one", name = "One",
      trigger = { type = "hotkey", parameters = { key = "k" } },
      actions = { { type = "launch", parameters = {} } } }),
  }
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  local macros, errors = store:load()
  eq(1, #macros)
  eq("good", macros[1].id)
  eq(1, #errors)
  truthy(errors[1].file == "invalid.json", "the broken file should be named")
  truthy(tostring(errors[1].error):find("app", 1, true) ~= nil,
    "the reason should mention the missing parameter: " .. tostring(errors[1].error))
  truthy(store:byId("one") == nil,
    "an invalid macro must not be addressable from the loaded list")
end)

