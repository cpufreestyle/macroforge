-- test_editor_runtime.lua -- drive the editor page's script in a stub DOM.
--
-- Everything else in Macroforge can be tested in Lua, but the editor page is
-- HTML, CSS and script that only does its job inside a browser. This test
-- builds exactly what the HTTP API answers -- the catalog plus every macro
-- shipped in macros/ -- and hands them to tests/editor_smoke.mjs, which runs
-- the page's own script against a minimal DOM and asserts on the result.
--
-- Without Node on PATH the test reports a skip rather than a failure, so the
-- suite stays dependency-free.

local store  = require("macroforge.store")
local catalog = require("macroforge.catalog")
local json    = require("macroforge.json")

local root = (arg[0] or ""):gsub("tests/run%.lua$", "")

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

local function hasNode()
  local pipe = io.popen("command -v node 2>/dev/null")
  if not pipe then return false end
  local found = pipe:read("*l")
  pipe:close()
  return found ~= nil and found ~= ""
end

local function exitCode(pipe)
  local ok, _, code = pipe:close()
  if type(code) == "number" then return code end
  return ok and 0 or 1
end

if not hasNode() then
  io.write("--   editor script smoke: skipped (node is not on PATH)\n")
else
  test("editor: the page's script renders the sidebar, title and mode switch", function()
    local macros, errors = store.new({ fs = fs, macrosDir = root .. "macros" }):load()
    local problems = {}
    for _, e in ipairs(errors or {}) do
      problems[#problems + 1] = { file = e.file, error = tostring(e.error) }
    end
    truthy(#macros >= 5, "expected the shipped examples to load, got " .. #macros)
    eq(0, #problems, "macro files must load cleanly: " .. json.encode(problems))

    local fixture = {
      catalog = { actions = catalog.actions, triggers = catalog.triggers },
      macros = macros,
      errors = problems,
    }
    local tmp = os.tmpname()
    local fh = assert(io.open(tmp, "w"), "cannot write " .. tmp)
    fh:write(json.encode(fixture))
    fh:close()

    local cmd = string.format("node %q %q %q 2>&1",
      "tests/editor_smoke.mjs", tmp, root .. "assets/editor.html")
    local pipe = assert(io.popen(cmd), "cannot launch node")
    local output = pipe:read("*a") or ""
    local code = exitCode(pipe)
    os.remove(tmp)

    if code ~= 0 then
      error("the editor page's script did not behave (node exit " .. code .. "):\n" .. output)
    end
    truthy(output:find("all assertions passed", 1, true) ~= nil,
      "the smoke harness reported no result:\n" .. output)
  end)
end

