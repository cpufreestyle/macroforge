-- Macroforge bootstrap for Hammerspoon.
--
-- Install: copy or symlink this repo to ~/.hammerspoon/macroforge and make
-- sure your ~/.hammerspoon/init.lua contains:
--     require("macroforge").start()
-- The start() call is idempotent, so loading this file alone is enough.

local dir = hs.configdir .. "/macroforge"
package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path

local ok, result = pcall(function()
  return require("macroforge").start()
end)
if not ok then
  hs.showError("Macroforge failed to start: " .. tostring(result))
end
