-- catalog.lua -- the Macroforge macro vocabulary.
--
-- Single source of truth for action types, trigger types and their parameter
-- shapes. The engine, validator, web editor API and tests all read from here.

local catalog = {}

catalog.PARAM_TYPES = {
  string   = "string",
  text     = "string",   -- multi-line string
  number   = "number",
  boolean  = "boolean",
  choice   = "choice",
  macro    = "macro",    -- reference to another macro, by name or id
}

catalog.actions = {
  {
    type = "launch",
    label = "Launch or focus app",
    description = "Activate an app, launching it if needed.",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Safari" },
    },
  },
  {
    type = "activate",
    label = "Activate app",
    description = "Bring an already-running app to the front.",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Mail" },
    },
  },
  {
    type = "quit",
    label = "Quit app",
    description = "Quit a running app.",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Xcode" },
    },
  },
  {
    type = "openURL",
    label = "Open URL",
    description = "Open a URL in the default browser.",
    params = {
      { name = "url", type = "string", required = true, placeholder = "https://example.com" },
    },
  },
  {
    type = "openFile",
    label = "Open file or folder",
    description = "Open a file, folder or document with its default app.",
    params = {
      { name = "path", type = "string", required = true, placeholder = "~/Documents/notes.md" },
    },
  },
  {
    type = "typeText",
    label = "Type text",
    description = "Type text as individual keystrokes.",
    params = {
      { name = "text", type = "text", required = true },
    },
  },
  {
    type = "pasteText",
    label = "Paste text",
    description = "Paste text via the clipboard, optionally restoring the previous contents.",
    params = {
      { name = "text", type = "text", required = true },
      { name = "restore", type = "boolean", default = true, label = "Restore previous clipboard" },
    },
  },
  {
    type = "pressKeys",
    label = "Press keys",
    description = "Simulate a keyboard shortcut in the frontmost app.",
    params = {
      { name = "mods", type = "string", placeholder = "cmd,alt" },
      { name = "key", type = "string", required = true, placeholder = "left" },
    },
  },
  {
    type = "snapWindow",
    label = "Snap window",
    description = "Move the focused window to a screen region.",
    params = {
      { name = "position", type = "choice", required = true, default = "left",
        choices = { "left", "right", "top", "bottom", "max", "fill", "center" } },
      { name = "app", type = "string", placeholder = "optional: app to activate first" },
    },
  },
  {
    type = "moveWindow",
    label = "Move and resize window",
    description = "Set the focused window frame as percentages of the screen.",
    params = {
      { name = "x", type = "number", required = true, default = 10 },
      { name = "y", type = "number", required = true, default = 10 },
      { name = "width", type = "number", required = true, default = 80 },
      { name = "height", type = "number", required = true, default = 80 },
    },
  },
  {
    type = "runShell",
    label = "Run shell script",
    description = "Execute a shell command in /bin/sh.",
    params = {
      { name = "command", type = "text", required = true, placeholder = "say 'hello'" },
    },
  },
  {
    type = "runAppleScript",
    label = "Run AppleScript",
    description = "Execute an AppleScript snippet.",
    params = {
      { name = "script", type = "text", required = true, placeholder = 'tell application "Music" to next track' },
    },
  },
  {
    type = "notify",
    label = "Show notification",
    description = "Post a macOS notification.",
    params = {
      { name = "title", type = "string", required = true, default = "Macroforge" },
      { name = "text", type = "string", required = true },
    },
  },
  {
    type = "setClipboard",
    label = "Set clipboard",
    description = "Replace the clipboard contents with text.",
    params = {
      { name = "text", type = "text", required = true },
    },
  },
  {
    type = "delay",
    label = "Delay",
    description = "Pause the macro for a number of seconds.",
    params = {
      { name = "seconds", type = "number", required = true, default = 1 },
    },
  },
  {
    type = "playMacro",
    label = "Run another macro",
    description = "Execute another macro as part of this one.",
    params = {
      { name = "macro", type = "macro", required = true },
    },
  },
}

catalog.triggers = {
  {
    type = "hotkey",
    label = "Hot key",
    description = "A keyboard shortcut, e.g. cmd+alt+K.",
    params = {
      { name = "mods", type = "string", default = "cmd,ctrl", placeholder = "cmd,ctrl" },
      { name = "key", type = "string", required = true, placeholder = "k" },
    },
  },
  {
    type = "typed",
    label = "Typed string",
    description = "Fires when a short string is typed, e.g. ;date",
    params = {
      { name = "string", type = "string", required = true, placeholder = ";date" },
      { name = "delete", type = "boolean", default = true, label = "Erase the typed string" },
    },
  },
  {
    type = "appLaunch",
    label = "App launches",
    description = "Fires when a specific app is launched.",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Spotify" },
    },
  },
  {
    type = "windowFocused",
    label = "Window focused",
    description = "Fires when a window of the given app gains focus.",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Safari" },
    },
  },
  {
    type = "interval",
    label = "Timer",
    description = "Fires every N minutes while Hammerspoon runs.",
    params = {
      { name = "minutes", type = "number", required = true, default = 30 },
    },
  },
}

catalog.actionDef = function(actionType)
  local key = tostring(actionType or ""):lower()
  for _, def in ipairs(catalog.actions) do
    if def.type:lower() == key then return def end
  end
  return nil
end

catalog.triggerDef = function(triggerType)
  local key = tostring(triggerType or ""):lower()
  for _, def in ipairs(catalog.triggers) do
    if def.type:lower() == key then return def end
  end
  return nil
end

-- Power users can extend the vocabulary; both actions and triggers are
-- plain data so the editor picks them up on reload.
function catalog.addAction(def)
  assert(type(def) == "table" and type(def.type) == "string" and def.type ~= "",
    "catalog.addAction needs { type = ... }")
  assert(catalog.actionDef(def.type) == nil, "action type already exists: " .. def.type)
  catalog.actions[#catalog.actions + 1] = def
  return def
end

-- Compute a window frame for a named snap position within a screen frame.
-- frame = {x, y, w, h}; returns {x, y, w, h}.
function catalog.snapFrame(position, frame)
  position = tostring(position or "left"):lower()
  local x, y, w, h = frame.x, frame.y, frame.w, frame.h
  if position == "left" then
    return { x = x, y = y, w = math.floor(w / 2), h = h }
  elseif position == "right" then
    return { x = x + math.floor(w / 2), y = y, w = math.floor(w / 2), h = h }
  elseif position == "top" then
    return { x = x, y = y, w = w, h = math.floor(h / 2) }
  elseif position == "bottom" then
    return { x = x, y = y + math.floor(h / 2), w = w, h = math.floor(h / 2) }
  elseif position == "max" then
    return { x = x, y = y, w = w, h = h }
  elseif position == "fill" then
    local fw, fh = math.floor(w * 0.94), math.floor(h * 0.94)
    return { x = x + math.floor((w - fw) / 2), y = y + math.floor((h - fh) / 2), w = fw, h = fh }
  elseif position == "center" then
    local cw, ch = math.floor(w * 0.8), math.floor(h * 0.8)
    return { x = x + math.floor((w - cw) / 2), y = y + math.floor((h - ch) / 2), w = cw, h = ch }
  end
  -- unknown position: fall back to the current screen
  return { x = x, y = y, w = w, h = h }
end

return catalog
