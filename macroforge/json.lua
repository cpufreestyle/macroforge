-- json.lua -- Minimal, dependency-free JSON codec for Macroforge.
--
-- Hammerspoon ships `hs.json`, but the engine, store and router are designed
-- to run head-less (unit tests, CLI tooling), so this module provides a
-- portable encoder/decoder covering the subset of JSON that Macroforge macros
-- use: strings, numbers, booleans, arrays and flat objects, with full UTF-8
-- pass-through.

local json = {}

-- Sentinel returned for JSON `null` values so the information is not lost.
-- Consumers that prefer Lua `nil` semantics should check for this value.
json.NULL = setmetatable({}, { __tostring = function() return "json.null" end })

local escapes = {
  ['"']  = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

local function isDenseArray(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  if count == 0 then return true, true end
  for i = 1, count do
    if t[i] == nil then return false, false end
  end
  return true, false
end

local function encodeString(str)
  local buf = { '"' }
  for i = 1, #str do
    local c = str:sub(i, i)
    local esc = escapes[c]
    if esc then
      buf[#buf + 1] = esc
    elseif c:byte() < 0x20 then
      buf[#buf + 1] = string.format('\\u%04x', c:byte())
    else
      buf[#buf + 1] = c
    end
  end
  buf[#buf + 1] = '"'
  return table.concat(buf)
end

local encodeValue

local function encodeTable(value, pretty, level)
  local isArr, isEmpty = isDenseArray(value)
  if isEmpty then return "[]" end
  local items = {}
  if isArr then
    for _, item in ipairs(value) do
      local encoded = encodeValue(item, pretty, level + 1)
      if pretty then
        items[#items + 1] = string.rep(" ", (level + 1) * 2) .. encoded
      else
        items[#items + 1] = encoded
      end
    end
    if pretty then
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. string.rep(" ", level * 2) .. "]"
    end
    return "[" .. table.concat(items, ",") .. "]"
  end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local encoded = encodeString(k) .. ":" .. (pretty and " " or "") ..
      encodeValue(value[k], pretty, level + 1)
    if pretty then
      items[#items + 1] = string.rep(" ", (level + 1) * 2) .. encoded
    else
      items[#items + 1] = encoded
    end
  end
  if pretty then
    return "{\n" .. table.concat(items, ",\n") .. "\n" .. string.rep(" ", level * 2) .. "}"
  end
  return "{" .. table.concat(items, ",") .. "}"
end

function encodeValue(value, pretty, level)
  local t = type(value)
  if value == nil then
    return "null"
  elseif t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "null"
    elseif math.floor(value) == value and math.abs(value) < 1e15 then
      return string.format("%d", value)
    end
    return tostring(value)
  elseif t == "boolean" then
    return tostring(value)
  elseif t == "string" then
    return encodeString(value)
  elseif t == "table" then
    if value == json.NULL then return "null" end
    return encodeTable(value, pretty, level)
  end
  return "null"
end

function json.encode(value, pretty)
  return encodeValue(value, not not pretty, 0)
end

local function skipWhitespace(str, pos)
  local _, e = str:find("^[ \t\r\n]*", pos)
  return e + 1
end

local function decodeError(pos, msg)
  return nil, string.format("%s (at byte %d)", msg, pos)
end

local parseValue

local function parseString(str, pos)
  if str:sub(pos, pos) ~= '"' then
    return decodeError(pos, "expected a string")
  end
  pos = pos + 1
  local buf = {}
  while true do
    local c = str:sub(pos, pos)
    if c == "" then
      return decodeError(pos, "unterminated string")
    elseif c == '"' then
      return table.concat(buf), pos + 1
    elseif c == "\\" then
      local nxt = str:sub(pos + 1, pos + 1)
      local simple = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f",
                       ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
      if simple[nxt] then
        buf[#buf + 1] = simple[nxt]
        pos = pos + 2
      elseif nxt == "u" then
        local hex = str:sub(pos + 2, pos + 5)
        if #hex < 4 or not hex:match("^%x%x%x%x$") then
          return decodeError(pos, "invalid \\u escape")
        end
        local code = tonumber(hex, 16)
        if code < 0x80 then
          buf[#buf + 1] = string.char(code)
        elseif code < 0x800 then
          buf[#buf + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
        else
          buf[#buf + 1] = string.char(0xE0 + math.floor(code / 4096),
                                      0x80 + math.floor(code / 64) % 64,
                                      0x80 + code % 64)
        end
        pos = pos + 6
      else
        return decodeError(pos, "invalid escape sequence")
      end
    else
      buf[#buf + 1] = c
      pos = pos + 1
    end
  end
end

local function parseNumber(str, pos)
  local text = str:match("^%-?%d+%.?%d*[eE][%+%-]?%d+", pos) or
               str:match("^%-?%d+%.%d+", pos) or
               str:match("^%-?%d+", pos)
  if not text then
    return decodeError(pos, "invalid number")
  end
  local num = tonumber(text)
  if num == nil then
    return decodeError(pos, "invalid number")
  end
  return num, pos + #text
end

function parseValue(str, pos)
  local c = str:sub(pos, pos)
  if c == "{" then
    local obj = {}
    pos = skipWhitespace(str, pos + 1)
    if str:sub(pos, pos) == "}" then return obj, pos + 1 end
    while true do
      pos = skipWhitespace(str, pos)
      local key, keyPos = parseString(str, pos)
      if key == nil then return nil, keyPos end
      pos = skipWhitespace(str, keyPos)
      if str:sub(pos, pos) ~= ":" then return decodeError(pos, "expected ':'") end
      pos = skipWhitespace(str, pos + 1)
      local val, valPos = parseValue(str, pos)
      if val == nil then return nil, valPos end
      pos = valPos
      obj[key] = (val == json.NULL) and json.NULL or val
      pos = skipWhitespace(str, pos)
      local sep = str:sub(pos, pos)
      if sep == "}" then return obj, pos + 1 end
      if sep ~= "," then return decodeError(pos, "expected ',' or '}'") end
      pos = pos + 1
    end
  elseif c == "[" then
    local arr = {}
    pos = skipWhitespace(str, pos + 1)
    if str:sub(pos, pos) == "]" then return arr, pos + 1 end
    while true do
      pos = skipWhitespace(str, pos)
      local val, valPos = parseValue(str, pos)
      if val == nil then return nil, valPos end
      pos = valPos
      arr[#arr + 1] = val
      pos = skipWhitespace(str, pos)
      local sep = str:sub(pos, pos)
      if sep == "]" then return arr, pos + 1 end
      if sep ~= "," then return decodeError(pos, "expected ',' or ']'") end
      pos = pos + 1
    end
  elseif c == '"' then
    return parseString(str, pos)
  elseif c == "t" then
    if str:sub(pos, pos + 3) == "true" then return true, pos + 4 end
    return decodeError(pos, "invalid literal")
  elseif c == "f" then
    if str:sub(pos, pos + 4) == "false" then return false, pos + 5 end
    return decodeError(pos, "invalid literal")
  elseif c == "n" then
    if str:sub(pos, pos + 3) == "null" then return json.NULL, pos + 4 end
    return decodeError(pos, "invalid literal")
  else
    if c == "-" or (c >= "0" and c <= "9") then
      return parseNumber(str, pos)
    end
    return decodeError(pos, "unexpected character " .. string.format("%q", c))
  end
end

function json.decode(str)
  if type(str) ~= "string" then
    return nil, "json.decode expects a string"
  end
  local value, pos = parseValue(str, skipWhitespace(str, 1))
  if value == nil then return nil, pos end
  pos = skipWhitespace(str, pos)
  if pos <= #str then
    return nil, string.format("trailing characters (at byte %d)", pos)
  end
  if value == json.NULL then
    return nil, "top-level null is not a valid macro document"
  end
  return value
end

return json
