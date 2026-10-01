-- router.lua -- the editor's HTTP API and static endpoints.
--
-- Pure and framework-free: `route(method, path, body)` returns
-- (status, body, headers). The Hammerspoon wiring lives in editor.lua.

local router = {}
router.__index = router

local json = require("macroforge.json")
local catalog = require("macroforge.catalog")

local BASE = "/macroforge"

local function send(status, body, contentType)
  return status, body, {
    ["Content-Type"] = contentType or "application/json",
    ["Access-Control-Allow-Origin"] = "*",
    ["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS",
    ["Access-Control-Allow-Headers"] = "Content-Type",
  }
end

function router.new(opts)
  opts = opts or {}
  assert(opts.store, "router.new requires opts.store")
  return setmetatable({
    store = opts.store,
    editorHTML = opts.editorHTML,
    reload = opts.reload or function() return true end,
    run = opts.run,
  }, router)
end

function router:route(method, path, body)
  method = (method or "GET"):upper()
  path = tostring(path or "/"):gsub("%?.+$", "")
  if #path > 1 and path:sub(-1) == "/" then path = path:sub(1, -2) end

  if method == "OPTIONS" then
    return send(204, "")
  end

  if method == "GET" and (path == BASE or path == BASE .. "/index.html") then
    if not self.editorHTML then
      return send(404, json.encode({ error = "editor assets are missing" }))
    end
    return send(200, self.editorHTML, "text/html; charset=utf-8")
  end

  if method == "GET" and path == BASE .. "/api/catalog" then
    return send(200, json.encode({ actions = catalog.actions, triggers = catalog.triggers }))
  end

  if method == "GET" and path == BASE .. "/api/macros" then
    local macros, errors = self.store:load()
    local problems = {}
    for _, e in ipairs(errors or {}) do
      problems[#problems + 1] = { file = e.file, error = e.error }
    end
    return send(200, json.encode({ macros = macros, errors = problems }))
  end

  if (method == "POST" or method == "PUT") and path == BASE .. "/api/macros" then
    local data, err = json.decode(body or "")
    if not data then
      return send(400, json.encode({ error = "invalid JSON body: " .. tostring(err) }))
    end
    local macro = (type(data) == "table" and data.macro) or data
    local saved, saveErr = self.store:save(macro)
    if not saved then
      return send(400, json.encode({ error = saveErr }))
    end
    self.reload()
    return send(200, json.encode({ macro = saved }))
  end

  local id = path:match("^" .. BASE .. "/api/macros/([^/]+)$")
  if id then
    if method == "GET" then
      local macro = self.store:byId(id)
      if not macro then
        return send(404, json.encode({ error = "macro not found" }))
      end
      return send(200, json.encode({ macro = macro }))
    elseif method == "DELETE" then
      local removed, delErr = self.store:delete(id)
      if not removed then
        return send(404, json.encode({ error = delErr or "macro not found" }))
      end
      self.reload()
      return send(200, json.encode({ deleted = id }))
    end
  end

  if method == "POST" and path == BASE .. "/api/reload" then
    local ok = self.reload()
    return send(200, json.encode({ reloaded = not not ok }))
  end

  if method == "POST" and path == BASE .. "/api/run" then
    if not self.run then
      return send(501, json.encode({ error = "running macros is disabled" }))
    end
    local data, err = json.decode(body or "")
    if not data then
      return send(400, json.encode({ error = "invalid JSON body: " .. tostring(err) }))
    end
    local macro = self.store:byId(tostring(data.id)) or self.store:byName(tostring(data.id or data.name))
    if not macro then
      return send(404, json.encode({ error = "macro not found" }))
    end
    local started, reason = self.run(macro)
    return send(200, json.encode({ started = not not started, reason = reason }))
  end

  return send(404, json.encode({ error = "not found: " .. method .. " " .. path }))
end

return router
