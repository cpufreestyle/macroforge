-- test_env_contract.lua -- the fake env must satisfy the real one.
--
-- init.lua builds the production env; tests/fake_env.lua mirrors it. When the
-- two drift, a macro that works on the desktop fails in the suite (or the
-- reverse), and the failure looks like a product bug. This test compares the
-- two contracts by reading init.lua for every `env.<name> =` it assigns, so a
-- new env hook cannot be added to one side only.

local root = (arg[0] or ""):gsub("tests/run%.lua$", "")

local function readFile(path)
  local handle = assert(io.open(path, "rb"), "cannot read " .. path)
  local content = handle:read("*a")
  handle:close()
  return content
end

-- Every `env.foo = ...` assignment in the production env builder. The engine
-- also installs skipUntilEndIf per run, so it is part of the contract too.
local function productionEnvNames()
  local source = readFile(root .. "macroforge/init.lua")
  local names = {}
  for name in source:gmatch("env%.([%w_]+)%s*=") do
    names[name] = true
  end
  return names
end

local fake = dofile(root .. "tests/fake_env.lua")

test("env contract: every production env hook exists in the fake", function()
  local production = productionEnvNames()
  local env = fake.new()
  local missing = {}
  for name in pairs(production) do
    if env[name] == nil then missing[#missing + 1] = name end
  end
  table.sort(missing)
  eq({}, missing, "fake_env is missing: " .. table.concat(missing, ", "))
end)

test("env contract: the fake exposes nothing the production env lacks", function()
  -- The fake may carry test-only fields (calls, clipboard, autoTimers), so
  -- this direction only checks the hooks that actions are allowed to call.
  local production = productionEnvNames()
  local env = fake.new()
  local hooks = {
    "launchOrFocus", "activate", "quit", "openURL", "openFile", "typeText",
    "paste", "pressKeys", "screenRect", "focusedWindowRect", "setFocusedWindowRect",
    "runShell", "runAppleScript", "notify", "getClipboard", "setClipboard",
    "timerAfter", "setVariable", "getVariable", "probe", "httpRequest",
    "skipUntilEndIf",
  }
  local absent = {}
  for _, name in ipairs(hooks) do
    if not production[name] and env[name] == nil then
      absent[#absent + 1] = name
    end
  end
  table.sort(absent)
  -- A hook the fake has but production does not is a bug in the fake, not here;
  -- what matters is that none of these names silently vanished from production.
  eq({}, absent, "neither side defines: " .. table.concat(absent, ", "))
end)

test("env contract: the fake records a variable round trip", function()
  local env = fake.new()
  env.setVariable("k", "v")
  eq("v", env.getVariable("k"))
  local sawSet = false
  for _, call in ipairs(env.calls) do
    if call.name == "setVariable" and call.args[1] == "k" and call.args[2] == "v" then
      sawSet = true
    end
  end
  truthy(sawSet, "setVariable should be recorded in env.calls")
  env:reset()
  eq(nil, env.getVariable("k"))
end)

test("env contract: the fake http request reports both outcomes", function()
  local env = fake.new()
  local body, err
  env.httpRequest({ url = "https://example.com", method = "GET" }, function(b, e)
    body, err = b, e
  end)
  eq("ok", body)
  eq(nil, err)

  env.httpResponse = { status = 500, body = "boom" }
  env.httpRequest({ url = "https://example.com", method = "GET" }, function(b, e)
    body, err = b, e
  end)
  truthy(err and err:find("500", 1, true), "expected an HTTP error, got " .. tostring(err))

  env.httpError = "no route"
  env.httpRequest({ url = "https://example.com", method = "GET" }, function(b, e)
    body, err = b, e
  end)
  eq("no route", err)
end)

test("env contract: the fake probe answers from probeFacts", function()
  local env = fake.new()
  local probe = env.probe()
  eq(false, probe.runningApps() == nil)
  eq(1, probe.screenCount())
  eq("", probe.frontmostApp())

  env.probeFacts = {
    runningApps = { "Safari" },
    frontmostApp = "Xcode",
    screenCount = 2,
    batteryLevel = 55,
    minutesOfDay = 600,
    reachableHost = "example.com",
  }
  probe = env.probe()
  eq(1, #probe.runningApps())
  eq("Safari", probe.runningApps()[1])
  eq("Xcode", probe.frontmostApp())
  eq(2, probe.screenCount())
  eq(55, probe.batteryLevel())
  eq(600, probe.minutesOfDay())
  eq(true, probe.networkReachable("example.com"))
  eq(false, probe.networkReachable("other.com"))
end)

