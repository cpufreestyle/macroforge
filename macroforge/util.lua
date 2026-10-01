-- util.lua -- small shared helpers.

local util = {}

function util.deepCopy(t)
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

function util.contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
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

function util.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function util.now()
  return os.time()
end

return util
