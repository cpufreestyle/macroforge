-- router.lua -- the editor's HTTP API and static endpoints.
--
-- Pure and framework-free: `route(method, path, body)` returns
-- (status, body, headers). The Hammerspoon wiring lives in editor.lua.

local router = {}
router.__index = router

local json = require("macroforge.json")
local catalog = require("macroforge.catalog")
local conditions = require("macroforge.conditions")

local BASE = "/macroforge"

-- Loopback hosts. A request that names one of these in its Origin came from
-- the editor itself, which is served from the same origin as the API.
local LOOPBACK_HOSTS = {
  ["127.0.0.1"] = true,
  ["[::1]"] = true,
  ["localhost"] = true,
}

-- Cross-site requests are refused by Origin, not by omitting CORS headers.
-- Removing Access-Control-Allow-Origin only stops the *response* from being
-- readable, which is not the problem: a "simple request" (POST or DELETE with
-- a text/plain body) needs no preflight and no permission to read back, so any
-- webpage could still make the user's browser run a runShell macro or delete
-- and rewrite macro files. Browsers send Origin on same-origin non-GET
-- requests too, so a real Origin that is not loopback is always someone else.
local function originIsLoopback(origin)
  if type(origin) ~= "string" or origin == "" then return true end
  local scheme, host = origin:lower():match("^([a-z][a-z0-9+.-]*)://([^/]+)$")
  if not scheme or not host then return false end
  if scheme ~= "http" and scheme ~= "https" then return false end
  -- Strip a :port. IPv6 literals arrive bracketed, so only cut at the last
  -- colon when the remainder has no colon left.
  if host:sub(1, 1) == "[" then
    host = host:match("^%[.-%]") or host
  else
    host = host:match("^([^:]+)") or host
  end
  return LOOPBACK_HOSTS[host:lower()] == true
end

local function header(headers, name)
  if type(headers) ~= "table" then return nil end
  for k, v in pairs(headers) do
    if type(k) == "string" and k:lower() == name then return v end
  end
  return nil
end

local function send(status, body, contentType)
  -- No Access-Control-Allow-Origin: the editor is same-origin with the API it
  -- calls, so it never needs CORS. A wildcard here would let any website read
  -- the API's answers, and the Origin check below is what actually refuses the
  -- request in the first place.
  return status, body, {
    ["Content-Type"] = contentType or "application/json",
  }
end

local FORBIDDEN = 403

function router.new(opts)
  opts = opts or {}
  assert(opts.store, "router.new requires opts.store")
  return setmetatable({
    store = opts.store,
    editorHTML = opts.editorHTML,
    reload = opts.reload or function() return true end,
    run = opts.run,
    aiCreate = opts.aiCreate,
    aiModels = opts.aiModels,
  }, router)
end

-- route(method, path, body, headers)
--   headers  the request headers as hs.httpserver passes them, so the Origin
--            check below can see who is asking. Optional: a caller with no
--            browser in the picture has nothing to check.
function router:route(method, path, body, headers)
  method = (method or "GET"):upper()
  path = tostring(path or "/"):gsub("%?.+$", "")
  if #path > 1 and path:sub(-1) == "/" then path = path:sub(1, -2) end

  -- Every path is refused here, not just the API ones: a top-level navigation
  -- to the editor sends no Origin, so this costs the editor itself nothing,
  -- while a fetch or subresource load from another site is turned away before
  -- it can reach the store. Nothing below this line can run shell commands or
  -- rewrite files on a cross-site request's behalf.
  if not originIsLoopback(header(headers, "origin")) then
    return send(FORBIDDEN, json.encode({
      error = "refused: this API only accepts requests from the local editor",
    }))
  end

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
    return send(200, json.encode({
      actions = catalog.actions,
      triggers = catalog.triggers,
      -- The editor uses this list to suggest condition names for the if action,
      -- so it stays in step with conditions.lua instead of a hand-kept copy.
      conditions = conditions.types(),
    }))
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
    -- The editor knows the id it loaded, so a renamed macro arrives with the
    -- new id and the id of the file it came from. Hand that previous id to the
    -- store, or the old file stays on disk and the macro appears twice.
    local previousId = (type(data) == "table" and type(data.previousId) == "string")
      and data.previousId or nil
    local saved, saveErr = self.store:saveRenaming(macro, previousId)
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

  -- AI macro creation is asynchronous by design: the model round trip takes
  -- seconds, so the endpoint acknowledges immediately (202) and the result
  -- arrives as a new macro file -- the pathwatcher reloads, the editor list
  -- refreshes, and a notification reports success or failure.
  if method == "POST" and path == BASE .. "/api/ai/create" then
    if not self.aiCreate then
      return send(501, json.encode({ error = "AI macro creation is not configured" }))
    end
    local data = json.decode(body or "")
    local request = data and type(data.request) == "string" and data.request or ""
    if request:match("^%s*(.-)%s*$") == "" then
      return send(400, json.encode({ error = "missing request text" }))
    end
    -- An optional per-creation model override; empty/whitespace means "use
    -- the settings default". An optional id turns the request into an EDIT
    -- of that existing macro instead of a fresh creation.
    local model = data and type(data.model) == "string" and data.model or nil
    if model and model:match("^%s*(.-)%s*$") == "" then model = nil end
    local editId = data and type(data.id) == "string" and data.id or nil
    if editId and editId:match("^%s*(.-)%s*$") == "" then editId = nil end
    self.aiCreate(request, model, editId)
    return send(202, json.encode({ started = true }))
  end

  -- Model discovery for the editor's AI-create dropdown. Served from the
  -- injected fetcher (loopback gateway, fetched on demand).
  if method == "GET" and path == BASE .. "/api/ai/models" then
    if not self.aiModels then
      return send(501, json.encode({ error = "AI model discovery is not configured" }))
    end
    return send(200, json.encode({ models = self.aiModels() }))
  end

  return send(404, json.encode({ error = "not found: " .. method .. " " .. path }))
end

return router
