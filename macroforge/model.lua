-- model.lua -- normalization and validation of macro documents.
--
-- A macro document is a plain table:
--   { id = "open-dev-stack",
--     name = "Open dev stack",
--     enabled = true,
--     continueOnError = false,
--     trigger = { type = "hotkey", parameters = { mods = "cmd,ctrl", key = "d" } },
--     actions = { { type = "launch", parameters = { app = "Safari" } } } }

local model = {}

local util = require("macroforge.util")
local json    = require("macroforge.json")
local catalog = require("macroforge.catalog")

local ID_PATTERN = "^[%w][%w%-_%.]*$"

local function isSafeId(id)
  return type(id) == "string" and id:match(ID_PATTERN) ~= nil
    and id ~= "." and id ~= ".."
end

local function canonicalType(typeStr, def)
  if def then return def.type end
  return tostring(typeStr or ""):lower()
end

-- macroforge/json decodes a JSON `null` into a sentinel table so the distinction
-- between null and absent survives a round trip. Treat it as absent here:
-- otherwise tostring() turns it into a table address in string parameters
-- (which then passes validation and is typed straight into the frontmost app),
-- and the same `null` is silently turned into a default for numbers.
local function isNull(value)
  return value == nil or value == json.NULL
end

function model.normalizeParams(params, def)
  local out = {}
  for k, v in pairs(params or {}) do
    if isNull(v) then v = nil end
    out[tostring(k)] = v
  end
  if not def then return out end
  for _, p in ipairs(def.params or {}) do
    local value = out[p.name]
    if p.type == "number" then
      if type(value) == "string" then
        local num = tonumber(value)
        if num then out[p.name] = num end
      end
      if type(out[p.name]) ~= "number" and p.default ~= nil then
        out[p.name] = p.default
      end
    elseif p.type == "boolean" then
      if type(value) == "string" then
        local lowered = value:lower()
        if lowered == "true" or lowered == "1" or lowered == "yes" then out[p.name] = true end
        if lowered == "false" or lowered == "0" or lowered == "no" then out[p.name] = false end
      end
      if type(out[p.name]) ~= "boolean" and p.default ~= nil then
        out[p.name] = p.default
      end
    elseif p.type == "choice" then
      if type(out[p.name]) == "string" then
        out[p.name] = out[p.name]:lower()
      end
      if isNull(out[p.name]) then out[p.name] = nil end
      if out[p.name] == nil and p.default ~= nil then
        out[p.name] = p.default
      end
    else -- string / text / macro
      if out[p.name] ~= nil then out[p.name] = tostring(out[p.name]) end
    end
  end
  return out
end

-- Derive a slug that does not collide with anything already registered.
-- `taken` is a set of ids; without it the caller can only be told "macro-N".
function model.uniqueSlug(name, taken)
  local base = util.slugify(name)
  if base ~= "macro" and not (taken and taken[base]) then return base end
  local n = 1
  while taken and taken[base .. "-" .. n] do n = n + 1 end
  return base .. "-" .. n
end

function model.normalize(data, taken)
  local macro = util.deepCopy(type(data) == "table" and data or {})

  -- A JSON null decodes into the NULL sentinel, which is a table, so trim()
  -- stringifies it into the literal "json.null" -- a string that then passes
  -- every validation check and leaks into ids and names. Treat null as absent
  -- before anything derives from these two fields.
  if isNull(macro.id) then macro.id = nil end
  if isNull(macro.name) then macro.name = nil end
  macro.id = util.trim(macro.id)
  -- Two nameless macros both slugify to the literal "macro", which is not a
  -- unique file name: the second save silently overwrites the first. Derive a
  -- unique id per document instead. Callers that already know the used ids can
  -- pass them in via the optional second argument.
  if macro.id == "" then
    macro.id = model.uniqueSlug(macro.name, taken)
  end
  macro.name = util.trim(macro.name)
  if macro.name == "" and isSafeId(macro.id) then macro.name = macro.id end
  macro.enabled = macro.enabled ~= false
  if isNull(macro.enabled) then macro.enabled = true end

  -- A JSON null decodes to the NULL sentinel table, which is "a table", so a
  -- `"trigger": null` document used to be normalised into a trigger of type
  -- "" and rejected with a confusing "unknown trigger type" message. Treat it
  -- as "no trigger" instead.
  if isNull(macro.trigger) then macro.trigger = nil end

  if type(macro.trigger) == "table" then
    local triggerType = tostring(macro.trigger.type or ""):lower()
    macro.trigger = {
      type = canonicalType(triggerType, catalog.triggerDef(triggerType)),
      parameters = model.normalizeParams(macro.trigger.parameters, catalog.triggerDef(triggerType)),
    }
  else
    macro.trigger = nil
  end

  if isNull(macro.actions) then macro.actions = nil end
  if type(macro.actions) ~= "table" then macro.actions = {} end
  local actions = {}
  for _, action in ipairs(macro.actions) do
    -- A null element in the actions array decodes to the NULL sentinel, which
    -- is "a table", so it used to become an action with an empty type that
    -- validation then rejected as malformed. Drop null elements the same way
    -- non-table elements are dropped.
    if not isNull(action) and type(action) == "table" then
      local actionType = tostring(action.type or ""):lower()
      local def = catalog.actionDef(actionType)
      actions[#actions + 1] = {
        type = canonicalType(actionType, def),
        parameters = model.normalizeParams(action.parameters, def),
      }
    end
  end
  macro.actions = actions
  return macro
end

function model.validateParams(def, params, prefix, errors)
  params = params or {}
  for _, p in ipairs(def.params or {}) do
    local value = params[p.name]
    if p.required and (value == nil or (type(value) == "string" and util.trim(value) == "")) then
      errors[#errors + 1] = string.format("%s: missing required parameter %q", prefix, p.name)
    elseif value ~= nil then
      if p.type == "number" then
        if type(value) ~= "number" then
          errors[#errors + 1] = string.format("%s: %q must be a number", prefix, p.name)
        end
      elseif p.type == "boolean" then
        if type(value) ~= "boolean" then
          errors[#errors + 1] = string.format("%s: %q must be a boolean", prefix, p.name)
        end
      elseif p.type == "choice" then
        if type(value) ~= "string" or not util.contains(p.choices or {}, value) then
          -- %q on a table shows its address ("table: 0x..."), which leaks an
          -- unstable pointer into user-facing errors; show the type instead.
          local shown = type(value) == "string" and value or ("<" .. type(value) .. ">")
          errors[#errors + 1] = string.format("%s: %q (%q) must be one of: %s",
            prefix, p.name, shown, table.concat(p.choices or {}, ", "))
        end
      end
    end
  end
end

function model.validate(macro)
  local errors = {}
  if type(macro) ~= "table" then
    errors[#errors + 1] = "macro must be a table"
    return errors
  end
  if type(macro.id) ~= "string" or not macro.id:match(ID_PATTERN) then
    errors[#errors + 1] = string.format("invalid macro id %q", tostring(macro.id))
  elseif macro.id == "." or macro.id == ".." then
    errors[#errors + 1] = "invalid macro id"
  end
  if type(macro.name) ~= "string" or macro.name == "" then
    errors[#errors + 1] = "macro name is required"
  elseif #macro.name > 80 then
    errors[#errors + 1] = "macro name must be 80 characters or fewer"
  end

  if macro.trigger ~= nil then
    if type(macro.trigger) ~= "table" then
      errors[#errors + 1] = "trigger must be a table"
    else
      local def = catalog.triggerDef(macro.trigger.type)
      if not def then
        errors[#errors + 1] = string.format("unknown trigger type %q", tostring(macro.trigger.type))
      else
        model.validateParams(def, macro.trigger.parameters, "trigger", errors)
      end
    end
  end

  if type(macro.actions) ~= "table" then
    errors[#errors + 1] = "actions must be an array"
  else
    if #macro.actions == 0 then
      errors[#errors + 1] = "macro needs at least one action"
    end
    for i, action in ipairs(macro.actions) do
      if type(action) ~= "table" or type(action.type) ~= "string" then
        errors[#errors + 1] = string.format("action %d is malformed", i)
      else
        local def = catalog.actionDef(action.type)
        if not def then
          errors[#errors + 1] = string.format("action %d: unknown type %q", i, action.type)
        else
          model.validateParams(def, action.parameters,
            string.format("action %d (%s)", i, action.type), errors)
        end
      end
    end
  end
  return errors
end

-- Short one-line summary shown in the chooser and editor lists.
function model.summarize(macro)
  local parts = {}
  local t = macro.trigger
  if t and t.type ~= "" then
    local p = t.parameters or {}
    if t.type == "hotkey" then
      parts[#parts + 1] = (p.mods and p.mods ~= "" and (p.mods .. "+" .. tostring(p.key)) or tostring(p.key))
    elseif t.type == "typed" then
      parts[#parts + 1] = 'type "' .. tostring(p.string) .. '"'
    elseif t.type == "appLaunch" then
      parts[#parts + 1] = "on launch " .. tostring(p.app)
    elseif t.type == "windowFocused" then
      parts[#parts + 1] = "focus " .. tostring(p.app)
    elseif t.type == "interval" then
      parts[#parts + 1] = "every " .. tostring(p.minutes) .. "m"
    else
      parts[#parts + 1] = t.type
    end
  else
    parts[#parts + 1] = "no trigger"
  end
  local state = macro.enabled and "" or " (disabled)"
  parts[#parts + 1] = #macro.actions .. " actions" .. state
  return table.concat(parts, " · ")
end

return model
