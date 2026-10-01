-- hsfs.lua -- the Hammerspoon filesystem bridge.
--
-- store.lua only needs { list, read, write, remove }, but Hammerspoon's hs.fs
-- exposes native directory helpers (dir, attributes, mkdir) and no
-- read/write/remove, so those are built on Lua's standard io/os. Without an
-- hs object (tests, plain Lua) the bridge falls back to shell helpers, which
-- keeps it exercisable outside Hammerspoon.

local util = require("macroforge.util")

local hsfs = {}

local function readFile(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local content = handle:read("*a")
  handle:close()
  return content
end

local function isDir(hs, path)
  if hs and hs.fs and hs.fs.attributes then
    local attrs = hs.fs.attributes(path)
    return attrs ~= nil and attrs.mode == "directory"
  end
  local ok = os.execute("test -d " .. util.shellQuote(path))
  return ok == true or ok == 0
end

local function listDir(hs, dir)
  local items = {}
  if hs and hs.fs and hs.fs.dir then
    local iter, dirObj = hs.fs.dir(dir)
    if not iter then return nil end
    for name in iter, dirObj do
      local attrs = hs.fs.attributes(dir .. "/" .. name)
      if attrs and attrs.mode == "file" then
        items[#items + 1] = name
      end
    end
    return items
  end
  local pipe = io.popen("ls -1 " .. util.shellQuote(dir) .. " 2>/dev/null")
  if not pipe then return items end
  for line in pipe:lines() do
    if line ~= "" and not isDir(hs, dir .. "/" .. line) then
      items[#items + 1] = line
    end
  end
  pipe:close()
  return items
end

local function ensureDir(hs, dir)
  if not dir or dir == "" then return end
  if isDir(hs, dir) then return end
  if hs and hs.fs and hs.fs.mkdir then
    hs.fs.mkdir(dir)
  else
    os.execute("mkdir -p " .. util.shellQuote(dir))
  end
end

-- Drop-in replacement for the hs.fs.read call sites.
function hsfs.readFile(path)
  return readFile(path)
end

-- Drop-in replacement for the hs.fs.write call sites.
function hsfs.writeFile(hs, path, content)
  local dir = path:match("^(.*)/[^/]*$")
  ensureDir(hs, dir)
  local handle = io.open(path, "wb")
  if not handle then return false end
  handle:write(content)
  handle:close()
  return true
end

-- Drop-in replacement for the hs.fs.remove call sites.
function hsfs.removeFile(path)
  return os.remove(path) and true or false
end

-- The store-compatible filesystem table.
function hsfs.new(hs)
  return {
    list = function(dir) return listDir(hs, dir) end,
    read = readFile,
    write = function(path, content) return hsfs.writeFile(hs, path, content) end,
    remove = hsfs.removeFile,
  }
end

return hsfs
