-- test_vars.lua -- the shared variable table.

local vars = require("macroforge.vars")

test("vars: set and get round-trips a value", function()
  vars.clear()
  vars.set("lastApp", "Safari")
  eq("Safari", vars.get("lastApp"))
end)

test("vars: getOr falls back only when unset", function()
  vars.clear()
  eq("none", vars.getOr("missing", "none"))
  vars.set("count", 3)
  eq(3, vars.getOr("count", 0))
  -- A stored false is a value, not an absence.
  vars.set("flag", false)
  eq(false, vars.getOr("flag", true))
end)

test("vars: expand substitutes {{name}} and leaves typos alone", function()
  vars.clear()
  vars.set("app", "Xcode")
  eq("open Xcode now", vars.expand("open {{app}} now"))
  -- Inner spaces are accepted and trimmed, so {{ app }} also resolves.
  eq("open Xcode now", vars.expand("open {{ app }} now"))
  -- Spaced braces are a different spelling; do not silently accept it.
  eq("open {{nope}} now", vars.expand("open {{nope}} now"))
  -- Non-string input passes through untouched.
  eq(nil, vars.expand(nil))
end)

test("vars: expand accepts an injected resolver", function()
  local seen = {}
  local out = vars.expand("{{a}}-{{b}}", function(name)
    seen[#seen + 1] = name
    return name:upper()
  end)
  eq("A-B", out)
  eq({ "a", "b" }, seen)
end)

test("vars: clear removes one key or everything", function()
  vars.clear()
  vars.set("a", 1)
  vars.set("b", 2)
  vars.clear("a")
  eq(nil, vars.get("a"))
  eq(2, vars.get("b"))
  vars.clear()
  eq(nil, vars.get("b"))
end)

test("vars: list is sorted by name", function()
  vars.clear()
  vars.set("zeta", 1)
  vars.set("alpha", 2)
  local names = {}
  for _, entry in ipairs(vars.list()) do names[#names + 1] = entry.name end
  eq({ "alpha", "zeta" }, names)
end)

test("vars: keys are case-sensitive", function()
  vars.clear()
  vars.set("LastApp", "Mail")
  eq(nil, vars.get("lastapp"))
end)

