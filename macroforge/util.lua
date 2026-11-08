-- util.lua -- small shared helpers.

local util = {}

function util.deepCopy(t)
  -- The json.NULL sentinel is compared by identity everywhere else, so it must
  -- never be cloned: a copy would silently stop being NULL.
  local json = require("macroforge.json")
  if t == json.NULL then return json.NULL end
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[util.deepCopy(k)] = util.deepCopy(v) end
  return out
end

function util.deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not util.deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function util.trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split "cmd,alt" into a canonical, de-duplicated modifier list.
function util.splitMods(s)
  local out, seen = {}, {}
  for raw in tostring(s or ""):gmatch("[^,%s]+") do
    local token = raw:lower()
    if not seen[token] then
      seen[token] = true
      out[#out + 1] = token
    end
  end
  local order = { ctrl = 1, alt = 2, shift = 3, cmd = 4, fn = 5 }
  table.sort(out, function(a, b)
    return (order[a] or 9) < (order[b] or 9)
  end)
  return out
end

function util.slugify(text)
  local slug = tostring(text or ""):lower()
  slug = slug:gsub("[^%w%-_]+", "-")
  slug = slug:gsub("%-%-+", "-")
  slug = slug:gsub("^%-+", ""):gsub("%-+$", "")
  if slug == "" then slug = "macro" end
  return slug
end

function util.shellQuote(s)
  return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

-- Danger patterns for AI-generated macro content, checked case-insensitively.
-- A misread request once produced an "rm -rf caches" macro for an unrelated
-- ask; content matching any of these is refused at generation time instead of
-- merely being created disabled.
local DANGEROUS_COMMANDS = {
  "rm%s*%-rf",
  "empty%s+trash",
  "sudo%s+dd",
  "mkfs",
  "diskutil%s+erase",
}

-- Returns the first matching danger pattern, or nil when clean.
function util.dangerousCommand(text)
  local haystack = tostring(text or ""):lower()
  for _, pattern in ipairs(DANGEROUS_COMMANDS) do
    if haystack:find(pattern) then return pattern end
  end
  return nil
end

-- Returns id, or id suffixed with "-ai" until exists(candidate) is false.
-- Used when an AI-generated macro would otherwise shadow a user macro that
-- shares the id: two files with one id make runtime behaviour depend on load
-- order (verified live).
function util.uniqueId(id, exists)
  local candidate = tostring(id or "")
  while exists(candidate) do
    candidate = candidate .. "-ai"
  end
  return candidate
end

return util
