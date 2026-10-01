-- store.lua -- macro persistence with an injectable filesystem.
--
-- The filesystem interface (fs) needs three methods:
--   fs.list(dir)      -> array of file names in dir (directories excluded)
--   fs.read(path)     -> string or nil
--   fs.write(path, s) -> void
--   fs.remove(path)   -> boolean
-- The production implementation lives in macroforge/hsfs.lua (hs.fs + io);
-- tests pass a plain in-memory table.

local store = {}
store.__index = store

local json = require("macroforge.json")
local model = require("macroforge.model")
local util = require("macroforge.util")

local function joinPath(dir, name)
  if not dir or dir == "" then return name end
  if dir:sub(-1) == "/" then return dir .. name end
  return dir .. "/" .. name
end

function store.new(opts)
  assert(opts and opts.fs, "store.new requires opts.fs")
  return setmetatable({
    fs = opts.fs,
    dir = opts.macrosDir,
    macros = {},
    errors = {},
  }, store)
end

function store:load()
  local names = self.fs.list(self.dir) or {}
  local macros, errors = {}, {}
  for _, name in ipairs(names) do
    if name:sub(-5) == ".json" and name:sub(1, 1) ~= "." then
      local content = self.fs.read(joinPath(self.dir, name))
      if not content then
        errors[#errors + 1] = { file = name, error = "file could not be read" }
      else
        local data, decodeErr = json.decode(content)
        if not data then
          errors[#errors + 1] = { file = name, error = decodeErr }
        else
          local macro = model.normalize(data)
          macro.file = name
          local problems = model.validate(macro)
          if #problems > 0 then
            errors[#errors + 1] = {
              file = name,
              error = table.concat(problems, "; "),
              macro = macro,
            }
          end
          macros[#macros + 1] = macro
        end
      end
    end
  end
  table.sort(macros, function(a, b)
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  self.macros, self.errors = macros, errors
  return macros, errors
end

function store:byId(id)
  self:load()
  for _, macro in ipairs(self.macros) do
    if macro.id == id then return macro end
  end
  return nil
end

function store:byName(name)
  self:load()
  local lowered = tostring(name or ""):lower()
  for _, macro in ipairs(self.macros) do
    if macro.name:lower() == lowered or macro.id:lower() == lowered then
      return macro
    end
  end
  return nil
end

function store:save(macro)
  local normalized = model.normalize(macro)
  local problems = model.validate(normalized)
  if #problems > 0 then
    return nil, table.concat(problems, "; ")
  end
  local path = joinPath(self.dir, normalized.id .. ".json")
  self.fs.write(path, json.encode(normalized, true) .. "\n")
  self:load()
  local reloaded = self:byId(normalized.id)
  return reloaded or normalized
end

function store:delete(id)
  if type(id) ~= "string" or not id:match("^[%w][%w%-_%.]*$") or id == "." or id == ".." then
    return nil, "invalid macro id"
  end
  local removed = self.fs.remove(joinPath(self.dir, id .. ".json"))
  self:load()
  return removed
end

return store
