-- Macroforge bootstrap for Hammerspoon.
--
-- Install: copy or symlink this repo to ~/.hammerspoon/macroforge and make
-- sure your ~/.hammerspoon/init.lua contains:
--     require("macroforge").start()
-- The start() call is idempotent, so loading this file alone is enough.

local dir = hs.configdir .. "/macroforge"
package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path

local ok, result = pcall(function()
  -- Expose the module as a global so the README's console examples work:
  -- Macroforge.reload(), Macroforge.playMacro("id"), Macroforge.state()...
  -- The global holds the MODULE (with methods), not the return of start()
  -- (which is the internal state table).
  local mf = require("macroforge")
  mf.start()
  Macroforge = mf
end)
if not ok then
  hs.showError("Macroforge failed to start: " .. tostring(result))
end
