-- test_editor.lua -- regression tests for the hs.httpserver adapter.
--
-- Two real bugs are pinned here:
--   1. hs.httpserver.new rejects a function (its first argument is a boolean),
--      so the callback has to be installed with setCallback afterwards;
--   2. hs.httpserver callbacks must return (body, status, headers), which is the
--      reverse of the router's (status, body, headers) convention. Returning them
--      in the router's order made every request answer 503.
--   3. The server must be pinned to loopback with setInterface. There is no
--      setAddress, so a typo there silently left the API listening on every
--      interface (lsof showed *:8099) while the docs claimed loopback-only.

local editor = require("macroforge.editor")

local function fakeHs(opts)
  opts = opts or {}
  local calls = {
    newCounts = {},
    newFirstIsFunction = {},
    callbacks = {},
    ports = {},
    interfaces = {},
    started = 0,
  }
  local hs = {}
  hs.httpserver = {}
  hs.httpserver.new = function(...)
    calls.newCounts[#calls.newCounts + 1] = select("#", ...)
    calls.newFirstIsFunction[#calls.newFirstIsFunction + 1] =
      select("#", ...) > 0 and type((...)) == "function"
    local server = {}
    if not opts.noSetInterface then
      server.setInterface = function(_, iface)
        calls.interfaces[#calls.interfaces + 1] = iface
      end
    end
    server.setCallback = function(_, fn) calls.callbacks[#calls.callbacks + 1] = fn end
    server.setPort = function(_, port) calls.ports[#calls.ports + 1] = port end
    server.start = function() calls.started = calls.started + 1 end
    return server
  end
  return hs, calls
end

test("editor: new is called without a function and the callback goes through setCallback", function()
  local hs, calls = fakeHs()
  local server = editor.start({ hs = hs, router = { route = function() end } })
  truthy(server, "start should return the server")
  eq({ 0 }, calls.newCounts)
  falsy(calls.newFirstIsFunction[1], "new's first argument must not be a function")
  eq(1, #calls.callbacks)
  eq("function", type(calls.callbacks[1]))
end)

test("editor: the port is taken from the options and start runs once", function()
  local hs, calls = fakeHs()
  editor.start({ hs = hs, port = 8123, router = { route = function() end } })
  eq({ 8123 }, calls.ports)
  eq(1, calls.started)
end)

test("editor: callbacks return body first, then the status, then the headers", function()
  local hs, calls = fakeHs()
  local seen = {}
  local router = {
    route = function(_, method, path, body)
      seen.method, seen.path, seen.body = method, path, body
      return 201, "router-body", { ["X-Macroforge"] = "test" }
    end,
  }
  editor.start({ hs = hs, router = router })
  local fn = calls.callbacks[1]
  local body, status, headers = fn("POST", "/macroforge/api/macros", {}, "{}")
  eq("POST", seen.method)
  eq("/macroforge/api/macros", seen.path)
  eq("{}", seen.body)
  eq("router-body", body)
  eq(201, status)
  eq({ ["X-Macroforge"] = "test" }, headers)
end)

test("editor: a nil body from the router becomes an empty string", function()
  local hs, calls = fakeHs()
  local router = { route = function() return 204, nil, nil end }
  editor.start({ hs = hs, router = router })
  local body, status, headers = calls.callbacks[1]("OPTIONS", "/macroforge", {}, nil)
  eq("", body)
  eq(204, status)
  eq({}, headers)
end)


test("editor: the server is pinned to loopback with setInterface", function()
  local hs, calls = fakeHs()
  local server = editor.start({ hs = hs, router = { route = function() end } })
  truthy(server, "start should return the server")
  eq({"loopback"}, calls.interfaces)
  eq(1, calls.started)
end)

test("editor: the loopback binding happens before start, not after", function()
  local hs, calls = fakeHs()
  local order = {}
  hs.httpserver.new = function(...)
    local server = {}
    server.setInterface = function() order[#order + 1] = "setInterface" end
    server.setCallback = function() order[#order + 1] = "setCallback" end
    server.setPort = function() order[#order + 1] = "setPort" end
    server.start = function() order[#order + 1] = "start" end
    return server
  end
  editor.start({ hs = hs, port = 8099, router = { route = function() end } })
  -- hs.httpserver binds on start, so the interface must already be set by then.
  local startAt
  for i, step in ipairs(order) do
    if step == "start" then startAt = i end
  end
  truthy(startAt, "start must be called")
  truthy(startAt > 1, "something must precede start")
  eq("setInterface", order[1])
  for i = 2, startAt - 1 do
    truthy(order[i] ~= "start", "nothing between setInterface and start")
  end
end)

test("editor: start refuses to run without setInterface", function()
  -- A server object that cannot be pinned to loopback would serve an API that
  -- runs shell commands to the whole network, so start must fail loudly instead
  -- of quietly starting on every interface.
  local hs = fakeHs({ noSetInterface = true })
  local ok, err = pcall(editor.start, { hs = hs, router = { route = function() end } })
  falsy(ok, "start must fail when setInterface is missing")
  truthy(type(err) == "string" and err:find("setInterface", 1, true),
    "the error must name setInterface, got: " .. tostring(err))
end)
