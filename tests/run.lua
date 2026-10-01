-- run.lua -- a tiny, dependency-free test runner for Macroforge.
--
-- Usage:  lua tests/run.lua          (from the repository root)
-- Exit code is 0 when every test passes.

package.path = "./?.lua;./?/init.lua;" .. package.path

-- Lua 5.1 used a global `unpack`; Lua 5.2+ moved it to table.unpack.
unpack = table.unpack or unpack

local tests = {}
local failures = 0

function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

function eq(expected, actual, message)
  local util = require("macroforge.util")
  if not util.deepEqual(expected, actual) then
    error(string.format("%s\n  expected: %s\n  actual:   %s",
      message or "values differ",
      tostring(expected),
      tostring(actual)), 2)
  end
end

function truthy(value, message)
  if not value then
    error(message or "expected a truthy value", 2)
  end
end

function falsy(value, message)
  if value then
    error(message or "expected a falsy value", 2)
  end
end

local files = {
  "test_json",
  "test_model",
  "test_store",
  "test_hsfs",
  "test_actions",
  "test_engine",
  "test_triggers",
  "test_router",
  "test_editor",
  "test_editor_runtime",
  "test_ui",
  "test_macros",
}

for _, name in ipairs(files) do
  local loaded, err = loadfile("tests/" .. name .. ".lua")
  if not loaded then
    io.write("LOAD ERROR tests/" .. name .. ".lua: " .. tostring(err) .. "\n")
    failures = failures + 1
  else
    local ok, runErr = pcall(loaded)
    if not ok then
      io.write("LOAD ERROR tests/" .. name .. ".lua: " .. tostring(runErr) .. "\n")
      failures = failures + 1
    end
  end
end

print("running " .. #tests .. " tests\n")
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    io.write("ok   " .. t.name .. "\n")
  else
    io.write("FAIL " .. t.name .. ": " .. tostring(err) .. "\n")
    failures = failures + 1
  end
end

print(string.format("\n%d passed, %d failed (%d total)", #tests - failures, failures, #tests))
os.exit(failures == 0 and 0 or 1)
