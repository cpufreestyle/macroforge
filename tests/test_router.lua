local storeMod = require("macroforge.store")
local routerMod = require("macroforge.router")
local json = require("macroforge.json")

local function memoryFs(files)
  return {
    list = function()
      local names = {}
      for name in pairs(files) do names[#names + 1] = name end
      return names
    end,
    read = function(path) return files[path:match("[^/]+$")] end,
    write = function(path, content) files[path:match("[^/]+$")] = content; return true end,
    remove = function(path)
      local name = path:match("[^/]+$")
      local existed = files[name] ~= nil
      files[name] = nil
      return existed
    end,
  }
end

local function makeRouter(files, override)
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  local reloads, runs = 0, 0
  local router = routerMod.new({
    store = store,
    editorHTML = "<html>editor</html>",
    reload = function() reloads = reloads + 1; return true end,
    run = function() runs = runs + 1; return true end,
  })
  local opts = override or {}
  return router, {
    reloads = function() return reloads end,
    runs = function() return runs end,
  }
end

test("router: GET /api/macros lists stored macros", function()
  local files = {
    ["a.json"] = json.encode({ name = "A", actions = { { type = "notify", parameters = { title = "t", text = "x" } } } }),
  }
  local router = makeRouter(files)
  local status, body, headers = router:route("GET", "/macroforge/api/macros", "")
  eq(200, status)
  truthy(headers["Content-Type"]:find("json") ~= nil)
  local payload = json.decode(body)
  eq(1, #payload.macros)
  eq("A", payload.macros[1].name)
end)

test("router: GET /catalog exposes the vocabulary", function()
  local router = makeRouter({})
  local status, body = router:route("GET", "/macroforge/api/catalog", "")
  eq(200, status)
  local catalog = json.decode(body)
  local found = false
  for _, a in ipairs(catalog.actions) do
    if a.type == "launch" then found = true end
  end
  truthy(found, "catalog should include the launch action")
end)

test("router: POST /api/macros saves and reloads", function()
  local files = {}
  local router, counts = makeRouter(files)
  local status, body = router:route("POST", "/macroforge/api/macros", json.encode({
    macro = { name = "Greet", actions = { { type = "notify", parameters = { title = "t", text = "hi" } } } },
  }))
  eq(200, status)
  local saved = json.decode(body).macro
  eq("greet", saved.id)
  eq("Greet", saved.name)
  truthy(files["greet.json"] ~= nil, "macro file should be written")
  eq(1, counts.reloads())
end)

test("router: invalid payload is rejected with 400", function()
  local router = makeRouter({})
  eq(400, router:route("POST", "/macroforge/api/macros", "{not json"))
  local status2 = router:route("POST", "/macroforge/api/macros",
    json.encode({ macro = { name = "Bad", actions = { { type = "launch", parameters = {} } } } }))
  eq(400, status2)
end)

test("router: single macro GET and DELETE", function()
  local files = {
    ["a.json"] = json.encode({ name = "A", actions = { { type = "notify", parameters = { title = "t", text = "x" } } } }),
  }
  local router = makeRouter(files)
  local status, body = router:route("GET", "/macroforge/api/macros/a", "")
  eq(200, status)
  eq("A", json.decode(body).macro.name)
  eq(200, router:route("DELETE", "/macroforge/api/macros/a", ""))
  truthy(files["a.json"] == nil, "file should be gone")
  eq(404, router:route("GET", "/macroforge/api/macros/a", ""))
  local badDelete = router:route("DELETE", "/macroforge/api/macros/..%2Fsecret", "")
  truthy(badDelete == 404 or badDelete == 400, "unsafe ids must not delete files")
end)

test("router: editor html is served as html", function()
  local router = makeRouter({})
  local status, body = router:route("GET", "/macroforge/", "")
  eq(200, status)
  truthy(body:find("editor") ~= nil)
  eq(200, router:route("GET", "/macroforge", ""))
end)

test("router: api/run starts macros through the injected hook", function()
  local files = {
    ["r.json"] = json.encode({ name = "Run me", actions = { { type = "notify", parameters = { title = "t", text = "x" } } } }),
  }
  local router, counts = makeRouter(files)
  local status, body = router:route("POST", "/macroforge/api/run", json.encode({ id = "Run me" }))
  eq(200, status)
  truthy(json.decode(body).started)
  eq(1, counts.runs())
  eq(404, router:route("POST", "/macroforge/api/run", json.encode({ id = "nope" })))
end)

test("router: OPTIONS and 404 fallbacks", function()
  local router = makeRouter({})
  eq(204, router:route("OPTIONS", "/macroforge/api/macros", ""))
  eq(404, router:route("GET", "/macroforge/unknown", ""))
end)

-- Dropping the CORS header is not enough on its own. A "simple request" -- POST
-- or DELETE carrying a text/plain body -- is sent without a preflight and the
-- response never has to be readable for the damage to be done, so a foreign
-- Origin must be refused outright. Browsers attach Origin to same-origin
-- non-GET requests too, so a loopback Origin stays legitimate.
test("router: a foreign Origin is refused on every API path", function()
  local files = {
    ["m.json"] = json.encode({
      id = "m", name = "m", enabled = true,
      actions = { { type = "runShell", parameters = { command = "true" } } },
    }),
  }
  local foreign = { Origin = "https://evil.example" }
  local router = makeRouter(files)

  local status, body = router:route("POST", "/macroforge/api/run", json.encode({ id = "m" }), foreign)
  eq(403, status)
  truthy(body:find("local editor", 1, true), "the refusal says why")

  eq(403, router:route("GET", "/macroforge/api/macros", "", foreign))
  eq(403, router:route("DELETE", "/macroforge/api/macros/m", "", foreign))
  eq(403, router:route("POST", "/macroforge/api/macros", json.encode({ id = "m" }), foreign))
  eq(403, router:route("POST", "/macroforge/api/reload", "", foreign))

  local _, after = makeRouter(files)
  eq(0, after.runs(), "no macro was started by the refused request")
end)

test("router: a loopback Origin is accepted", function()
  local files = {
    ["m.json"] = json.encode({
      id = "m", name = "m", enabled = true,
      actions = { { type = "notify", parameters = { title = "t", text = "x" } } },
    }),
  }
  for _, origin in ipairs({
    "http://127.0.0.1:8099",
    "http://localhost:8099",
    "http://[::1]:8099",
    "https://127.0.0.1",
    "HTTP://127.0.0.1:8099",
  }) do
    local router, probe = makeRouter(files)
    local status = router:route("POST", "/macroforge/api/run", json.encode({ id = "m" }), { Origin = origin })
    eq(200, status, "accepted " .. origin)
    eq(1, probe.runs())
  end
end)

test("router: a malformed Origin is refused, a missing one is allowed", function()
  local files = {
    ["m.json"] = json.encode({
      id = "m", name = "m", enabled = true,
      actions = { { type = "notify", parameters = { title = "t", text = "x" } } },
    }),
  }
  local router = makeRouter(files)
  -- Only a browser ever sends Origin, so its absence means a local caller such
  -- as the console or curl.
  eq(200, router:route("POST", "/macroforge/api/run", json.encode({ id = "m" })))
  eq(403, router:route("POST", "/macroforge/api/run", json.encode({ id = "m" }), { Origin = "not a url" }))
  eq(403, router:route("POST", "/macroforge/api/run", json.encode({ id = "m" }), { Origin = "file:///x" }))
  eq(403, router:route("POST", "/macroforge/api/run", json.encode({ id = "m" }), { Origin = "http://127.0.0.1.evil.example:80" }))
end)

test("router: the header lookup ignores case", function()
  local files = {
    ["m.json"] = json.encode({
      id = "m", name = "m", enabled = true,
      actions = { { type = "notify", parameters = { title = "t", text = "x" } } },
    }),
  }
  local router = makeRouter(files)
  eq(403, router:route("POST", "/macroforge/api/run", json.encode({ id = "m" }), { origin = "http://evil.example" }))
  eq(403, router:route("POST", "/macroforge/api/run", json.encode({ id = "m" }), { ORIGIN = "http://evil.example" }))
end)

-- The editor is same-origin with its API, so no response needs CORS. A
-- wildcard Access-Control-Allow-Origin let any website POST /api/run (a
-- simple request, no preflight) and execute runShell macros, or read and
-- rewrite macro files. Pin the absence of the header on the run endpoint.
test("router: responses never send a wildcard CORS origin", function()
  local files = {
    ["m.json"] = json.encode({
      id = "m", name = "m", enabled = true,
      actions = { { type = "runShell", parameters = { command = "true" } } },
    }),
  }
  local router = makeRouter(files)
  local _, _, runHeaders = router:route("POST", "/macroforge/api/run", json.encode({ id = "m" }))
  eq(nil, runHeaders["Access-Control-Allow-Origin"])
  local _, _, listHeaders = router:route("GET", "/macroforge/api/macros", "")
  eq(nil, listHeaders["Access-Control-Allow-Origin"])
end)

-- AI macro creation: gated behind the injected handler, acknowledged with
-- 202, and the request text forwarded verbatim for the async round trip.
test("router: ai/create is gated and asynchronous", function()
  local files = {}
  local seen, seenModel = nil, nil
  local router, counters = makeRouter(files, {})
  local status = router:route("POST", "/macroforge/api/ai/create", json.encode({ request = "提醒我喝水" }))
  eq(501, status, "without an aiCreate handler the endpoint must refuse")
  local spy = function(request, model) seen = request; seenModel = model end
  local store = storeMod.new({ fs = memoryFs(files), macrosDir = "/macros" })
  local router2 = routerMod.new({
    store = store,
    editorHTML = "<html>editor</html>",
    aiCreate = spy,
  })
  local status2, body2 = router2:route("POST", "/macroforge/api/ai/create", json.encode({ request = "提醒我喝水", model = "claude-haiku-5" }))
  eq(202, status2, "an injected handler gets an immediate acknowledgement")
  eq("提醒我喝水", seen)
  eq("claude-haiku-5", seenModel, "an explicit model must reach the creator")
  router2:route("POST", "/macroforge/api/ai/create", json.encode({ request = "再试一次" }))
  eq(nil, seenModel, "a blank model must fall back to the settings default")
  local status3 = router2:route("POST", "/macroforge/api/ai/create", json.encode({ request = "  " }))
  eq(400, status3, "an empty request must be refused")
end)
