-- editor.lua -- serves the Macroforge web editor through hs.httpserver.
--
-- The hs.httpserver callback signature is (method, path, headers, body), but the
-- values it must return are (body, status, headers), which is the reverse of the
-- router's (status, body, headers) convention, so this file also swaps the order.
-- hs.httpserver.new only accepts a boolean, not a callback, so the callback is
-- installed afterwards with setCallback. The server binds to loopback through
-- setInterface (there is no setAddress), and that is the only reason the API is
-- not reachable from the LAN.

local editor = {}

function editor.start(opts)
  local hs = assert(opts and opts.hs, "editor.start requires opts.hs")
  local router = assert(opts and opts.router, "editor.start requires opts.router")

  local server = hs.httpserver.new()
  -- Serve only on loopback: the API runs shell commands and edits files, so it
  -- must not be reachable from other machines on the network.
  --
  -- The method is `setInterface`, NOT `setAddress`. hs.httpserver listens on
  -- every interface by default (lsof shows *:PORT, not 127.0.0.1:PORT), and a
  -- call to a non-existent method on the server object would be a no-op error,
  -- so this must be spelled correctly or the API stays LAN-reachable.
  -- `setInterface` accepts an IP address of one of the machine's interfaces,
  -- `localhost`, or `loopback`; nil (the default) means all interfaces.
  if type(server.setInterface) == "function" then
    server:setInterface("loopback")
  else
    error("editor.start: hs.httpserver has no setInterface; the API would be "
      .. "reachable from the network. Refusing to start it that way.")
  end
  server:setCallback(function(method, path, headers, body)
    -- The router needs the request headers to tell a request from the local
    -- editor apart from a cross-site one that names a foreign Origin.
    local status, respBody, respHeaders = router:route(method, path, body, headers)
    return tostring(respBody or ""), status, respHeaders or {}
  end)

  server:setPort(opts.port or 8099)
  server:start()
  return server
end

return editor
