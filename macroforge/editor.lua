-- editor.lua -- serves the Macroforge web editor through hs.httpserver.
--
-- The hs.httpserver callback signature is (method, path, headers, body), but the
-- values it must return are (body, status, headers), which is the reverse of the
-- router's (status, body, headers) convention, so this file also swaps the order.
-- hs.httpserver.new only accepts a boolean, not a callback, so the callback is
-- installed afterwards with setCallback.

local editor = {}

function editor.start(opts)
  local hs = assert(opts and opts.hs, "editor.start requires opts.hs")
  local router = assert(opts and opts.router, "editor.start requires opts.router")

  local server = hs.httpserver.new()
  -- Serve only on loopback: the API runs shell commands and edits files, so it
  -- must not be reachable from other machines on the network.
  if server.setAddress then server:setAddress("127.0.0.1") end
  server:setCallback(function(method, path, headers, body)
    local status, respBody, respHeaders = router:route(method, path, body)
    return tostring(respBody or ""), status, respHeaders or {}
  end)

  server:setPort(opts.port or 8099)
  server:start()
  return server
end

return editor
