-- test_util.lua -- the AI-generation safety helpers.
--
-- dangerousCommand gates AI-generated content before it can touch disk;
-- uniqueId keeps an AI macro from shadowing a user macro that shares its id.

local util = require("macroforge.util")

test("util: dangerousCommand catches destructive patterns", function()
  truthy(util.dangerousCommand("rm -rf ~/Library/Caches/*") ~= nil, "rm -rf must match")
  truthy(util.dangerousCommand("tell application \"Finder\" to Empty Trash") ~= nil, "empty trash must match")
  truthy(util.dangerousCommand("sudo dd if=/dev/zero of=/dev/disk0") ~= nil, "sudo dd must match")
  truthy(util.dangerousCommand("mkfs.apfs /dev/disk1") ~= nil, "mkfs must match")
end)

test("util: dangerousCommand passes harmless commands", function()
  falsy(util.dangerousCommand("df -h / | awk 'NR==2 {print $4}'"), "df -h is harmless")
  falsy(util.dangerousCommand("say hello"), "say is harmless")
  falsy(util.dangerousCommand("brew list --versions"), "brew list is harmless")
  falsy(util.dangerousCommand(nil), "nil input is clean")
end)

test("util: uniqueId suffixes until the id is free", function()
  local taken = { ["demo"] = true, ["demo-ai"] = true }
  eq("demo-ai-ai", util.uniqueId("demo", function(id) return taken[id] == true end))
  eq("fresh", util.uniqueId("fresh", function(id) return taken[id] == true end))
  eq("demo-ai", util.uniqueId("demo", function(id) return id == "demo" end))
end)
