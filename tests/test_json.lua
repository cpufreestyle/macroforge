local json = require("macroforge.json")

test("json: compact encoding is stable", function()
  eq([[{"a":1,"b":{"c":["x","y"]}}]], json.encode({ a = 1, b = { c = { "x", "y" } } }))
end)

test("json: pretty encoding is indented", function()
  local pretty = json.encode({ a = 1 }, true)
  truthy(pretty:find('\n  "a"') ~= nil, "expected indented output:\n" .. pretty)
end)

test("json: round trip preserves data", function()
  local data = {
    id = "m1", enabled = true, ratio = 0.5,
    trigger = { type = "hotkey", parameters = { mods = "cmd,ctrl", key = "k" } },
    actions = { { type = "launch", parameters = { app = "Safari" } } },
  }
  eq(data, json.decode(json.encode(data)))
end)

test("json: unicode and escapes survive round trip", function()
  local text = 'quote " backslash \\ newline \n tab \t 中文 😀'
  eq(text, json.decode(json.encode({ text = text })).text)
end)

test("json: decode errors are descriptive", function()
  local value, err = json.decode("{bad}")
  truthy(value == nil and type(err) == "string" and err:find("byte") ~= nil, "got: " .. tostring(err))
  local _, err2 = json.decode("[1,2")
  truthy(err2 ~= nil, "unterminated array should fail")
  local _, err3 = json.decode("{} garbage")
  truthy(err3 and err3:find("trailing") ~= nil, "got: " .. tostring(err3))
end)

test("json: surrogate pairs decode to a single UTF-8 character", function()
  -- U+1F600 (😀) is encoded in JSON as the pair \uD83D\uDE00. Decoding
  -- each half separately used to produce two invalid 3-byte sequences.
  local decoded = json.decode([==[{"emoji": "\uD83D\uDE00"}]==])
  eq("\u{1F600}", decoded.emoji)
  truthy(#decoded.emoji == 4, "expected 4-byte UTF-8, got " .. #decoded.emoji)
  -- Unpaired halves are rejected instead of silently becoming mojibake.
  local bad, err = json.decode([==[{"x": "\uD83Dabc"}]==])
  truthy(bad == nil, "lone high surrogate should fail to decode")
  truthy(err and err:find("surrogate") ~= nil, "error should mention the surrogate")
end)

test("json: null becomes the NULL sentinel", function()
  local decoded = json.decode([[{"a": null}]])
  truthy(decoded.a == json.NULL, "null should decode to the sentinel")
  truthy(json.decode("null") == nil, "top-level null returns nil with an error")
end)

test("json: numbers keep integer form", function()
  eq("42", json.encode(42))
  eq("true", json.encode(true))
  eq("null", json.encode(nil))
  eq(-3, json.decode("[-3]")[1])
end)
