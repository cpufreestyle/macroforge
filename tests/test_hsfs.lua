-- test_hsfs.lua -- regression tests for the Hammerspoon filesystem bridge.
--
-- The bridge once called hs.fs.read/write/remove, which do not exist in
-- Hammerspoon, so Macroforge.start() died at loadSettings with "attempt to
-- call a nil value (field 'read')". These tests run against a real temp
-- directory and cover both the native hs.fs path and the plain-Lua fallback.

local util = require("macroforge.util")
local hsfs = require("macroforge.hsfs")

local root = (os.getenv("TMPDIR") or "/tmp") .. "/macroforge-hsfs-test"

os.execute("rm -rf " .. util.shellQuote(root))
os.execute("mkdir -p " .. util.shellQuote(root))

test("hsfs: read returns nil for a missing file", function()
  eq(nil, hsfs.readFile(root .. "/nope.json"))
end)

test("hsfs: write creates parent dirs and read returns the content", function()
  local fs = hsfs.new(nil)
  local path = root .. "/nested/deep/demo.json"
  truthy(fs.write(path, '{"hello": 1}'), "write should succeed")
  eq('{"hello": 1}', fs.read(path))
end)

test("hsfs: list sees files and skips directories", function()
  local fs = hsfs.new(nil)
  fs.write(root .. "/listing/a.json", "a")
  fs.write(root .. "/listing/b.json", "b")
  fs.write(root .. "/listing/sub/c.json", "c")
  local names = fs.list(root .. "/listing")
  table.sort(names)
  eq({ "a.json", "b.json" }, names)
end)

test("hsfs: remove deletes a file and reports failure when it is gone", function()
  local fs = hsfs.new(nil)
  local path = root .. "/remove/doomed.json"
  fs.write(path, "bye")
  truthy(fs.remove(path), "remove should report success")
  falsy(fs.remove(path), "removing twice should fail")
  eq(nil, fs.read(path))
end)

test("hsfs: native hs.fs path lists files and asks mkdir for parents", function()
  local created = {}
  local entries = { ["x.json"] = "file", ["skipped-dir"] = "directory" }
  local fakeHs = {
    fs = {
      attributes = function(path)
        local name = path:match("[^/]+$")
        local mode = entries[name]
        if mode then return { mode = mode } end
        return nil
      end,
      dir = function()
        local index, names = 0, {}
        for name in pairs(entries) do names[#names + 1] = name end
        return function()
          index = index + 1
          return names[index]
        end
      end,
      mkdir = function(dir) created[#created + 1] = dir end,
    },
  }
  local fs = hsfs.new(fakeHs)
  eq({ "x.json" }, fs.list("/somewhere"))
  local path = root .. "/wrote.json"
  truthy(fs.write(path, "data"), "write should succeed")
  eq(1, #created)
  eq(root, created[1])
  eq("data", fs.read(path))
end)
