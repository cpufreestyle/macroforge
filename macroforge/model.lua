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

function model.normalizeParams(params, def)
  local out = {}
  for k, v in pairs(params or {}) do out[tostring(k)] = v end
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
      if out[p.name] == nil and p.default ~= nil then
        out[p.name] = p.default
      end
    else -- string / text / macro
      if out[p.name] ~= nil then out[p.name] = tostring(out[p.name]) end
    end
  end
  return out
end

function model.normalize(data)
  local macro = util.deepCopy(type(data) == "table" and data or {})

  macro.id = util.trim(macro.id)
  if macro.id == "" then macro.id = util.slugify(macro.name) end
  macro.name = util.trim(macro.name)
  if macro.name == "" and isSafeId(macro.id) then macro.name = macro.id end
  macro.enabled = macro.enabled ~= false

  if type(macro.trigger) == "table" then
    local triggerType = tostring(macro.trigger.type or ""):lower()
    macro.trigger = {
      type = canonicalType(triggerType, catalog.triggerDef(triggerType)),
      parameters = model.normalizeParams(macro.trigger.parameters, catalog.triggerDef(triggerType)),
    }
  else
    macro.trigger = nil
  end

  if type(macro.actions) ~= "table" then macro.actions = {} end
  local actions = {}
  for _, action in ipairs(macro.actions) do
    if type(action) == "table" then
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
          errors[#errors + 1] = string.format("%s: %q (%q) must be one of: %s",
            prefix, p.name, tostring(value), table.concat(p.choices or {}, ", "))
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
