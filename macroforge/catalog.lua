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
    zh = "启动或聚焦应用",
    description = "Activate an app, launching it if needed.",
    zh_desc = "需要时启动应用，已经在运行就直接切到前台。",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Safari" },
    },
  },
  {
    type = "activate",
    label = "Activate app",
    zh = "切换到应用",
    description = "Bring an already-running app to the front.",
    zh_desc = "只在应用已运行时把它切到前台。",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Mail" },
    },
  },
  {
    type = "quit",
    label = "Quit app",
    zh = "退出应用",
    description = "Quit a running app.",
    zh_desc = "请求正在运行的应用退出。",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Xcode" },
    },
  },
  {
    type = "openURL",
    label = "Open URL",
    zh = "打开网址",
    description = "Open a URL in the default browser.",
    zh_desc = "用默认浏览器打开网址。",
    params = {
      { name = "url", type = "string", required = true, placeholder = "https://example.com" },
    },
  },
  {
    type = "openFile",
    label = "Open file or folder",
    zh = "打开文件或文件夹",
    description = "Open a file, folder or document with its default app.",
    zh_desc = "用默认应用打开文件、文件夹或文档，支持 ~。",
    params = {
      { name = "path", type = "string", required = true, placeholder = "~/Documents/notes.md" },
    },
  },
  {
    type = "typeText",
    label = "Type text",
    zh = "键入文字",
    description = "Type text as individual keystrokes.",
    zh_desc = "逐个字符模拟键盘输入。",
    params = {
      { name = "text", type = "text", required = true },
    },
  },
  {
    type = "pasteText",
    label = "Paste text",
    zh = "粘贴文字",
    description = "Paste text via the clipboard, optionally restoring the previous contents.",
    zh_desc = "经由剪贴板粘贴，默认用完恢复原内容。",
    params = {
      { name = "text", type = "text", required = true },
      { name = "restore", type = "boolean", default = true, label = "用完恢复原剪贴板" },
    },
  },
  {
    type = "pressKeys",
    label = "Press keys",
    zh = "按键组合",
    description = "Simulate a keyboard shortcut in the frontmost app.",
    zh_desc = "在前台应用里模拟一次快捷键。",
    params = {
      { name = "mods", type = "string", placeholder = "cmd,alt" },
      { name = "key", type = "string", required = true, placeholder = "left" },
    },
  },
  {
    type = "snapWindow",
    label = "Snap window",
    zh = "吸附窗口",
    description = "Move the focused window to a screen region.",
    zh_desc = "把当前窗口移到屏幕的某个区域。",
    params = {
      { name = "position", type = "choice", required = true, default = "left",
        choices = { "left", "right", "top", "bottom", "max", "fill", "center" } },
      { name = "app", type = "string", placeholder = "optional: app to activate first" },
    },
  },
  {
    type = "moveWindow",
    label = "Move and resize window",
    zh = "移动并缩放窗口",
    description = "Set the focused window frame as percentages of the screen.",
    zh_desc = "按屏幕百分比设置窗口的位置和大小。",
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
    zh = "运行 Shell 脚本",
    description = "Execute a shell command in /bin/sh.",
    zh_desc = "在 /bin/sh 中执行命令，会阻塞主线程，请保持简短。",
    params = {
      { name = "command", type = "text", required = true, placeholder = "say 'hello'" },
    },
  },
  {
    type = "runAppleScript",
    label = "Run AppleScript",
    zh = "运行 AppleScript",
    description = "Execute an AppleScript snippet.",
    zh_desc = "执行一段 AppleScript。",
    params = {
      { name = "script", type = "text", required = true, placeholder = 'tell application "Music" to next track' },
    },
  },
  {
    type = "notify",
    label = "Show notification",
    zh = "显示通知",
    description = "Post a macOS notification.",
    zh_desc = "发一条 macOS 通知。",
    params = {
      { name = "title", type = "string", required = true, default = "Macroforge" },
      { name = "text", type = "string", required = true },
    },
  },
  {
    type = "setClipboard",
    label = "Set clipboard",
    zh = "设置剪贴板",
    description = "Replace the clipboard contents with text.",
    zh_desc = "用文字替换剪贴板内容。",
    params = {
      { name = "text", type = "text", required = true },
    },
  },
  {
    type = "delay",
    label = "Delay",
    zh = "延迟",
    description = "Pause the macro for a number of seconds.",
    zh_desc = "暂停这个宏若干秒，不阻塞 Hammerspoon。",
    params = {
      { name = "seconds", type = "number", required = true, default = 1 },
    },
  },
  {
    type = "playMacro",
    label = "Run another macro",
    zh = "运行另一个宏",
    description = "Execute another macro as part of this one.",
    zh_desc = "把另一个宏当作这一步来运行。按 ID 优先、其次按名称查找。",
    params = {
      { name = "macro", type = "macro", required = true },
    },
  },
  {
    type = "if",
    label = "If condition",
    zh = "条件判断",
    description = "Run the following actions only when the condition holds. Every action between this and the matching endIf is skipped when it does not.",
    zh_desc = "条件成立时才运行到匹配的「结束条件」为止；不成立就整段跳过。",
    params = {
      { name = "condition", type = "string", required = true, placeholder = "appRunning" },
      { name = "negate", type = "boolean", default = false, label = "条件取反" },
    },
  },
  {
    type = "setVariable",
    label = "Set variable",
    zh = "设置变量",
    description = "Store a value under a name. Other actions read it with {{name}} in any text field.",
    zh_desc = "按名字存一个值，其他动作可用 {{名字}} 读取。",
    params = {
      { name = "name", type = "string", required = true, placeholder = "lastApp" },
      { name = "value", type = "string", required = true, placeholder = "Safari" },
    },
  },
  {
    type = "endIf",
    label = "End if",
    zh = "结束条件",
    description = "Close an if block. Actions after this always run.",
    zh_desc = "结束 if 块，其后的动作总是会运行。",
    params = {},
  },
  {
    type = "httpRequest",
    label = "HTTP request",
    zh = "HTTP 请求",
    description = "Call a URL and store the response body in a variable. Use it to trigger a webhook or read a JSON endpoint.",
    zh_desc = "请求一个网址并把响应体存进变量，可用于触发 webhook 或读取 JSON。",
    params = {
      { name = "url", type = "string", required = true, placeholder = "https://example.com/hook" },
      { name = "method", type = "choice", required = true, default = "GET",
        choices = { "GET", "POST", "PUT", "DELETE" } },
      { name = "body", type = "text", placeholder = [[{"key": "value"}]] },
      { name = "into", type = "string", placeholder = "httpBody" },
    },
  },
}

catalog.triggers = {
  {
    type = "hotkey",
    label = "Hot key",
    zh = "热键",
    description = "A keyboard shortcut, e.g. cmd+alt+K.",
    zh_desc = "按下组合键就运行。若组合冲突，Hammerspoon 会静默让位，请看它的控制台。",
    params = {
      { name = "mods", type = "string", default = "cmd,ctrl", placeholder = "cmd,ctrl" },
      { name = "key", type = "string", required = true, placeholder = "k" },
    },
  },
  {
    type = "typed",
    label = "Typed string",
    zh = "键入字符串",
    description = "Fires when a short string is typed, e.g. ;date",
    zh_desc = "在任何输入框里敲出这串字符就会触发，例如 ;now。默认会先删掉这串字符。",
    params = {
      { name = "string", type = "string", required = true, placeholder = ";date" },
      { name = "delete", type = "boolean", default = true, label = "触发后删除这串字符" },
    },
  },
  {
    type = "appLaunch",
    label = "App launches",
    zh = "应用启动",
    description = "Fires when a specific app is launched.",
    zh_desc = "只在应用新启动时触发；应用已经在运行再点开不会重复触发。",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Spotify" },
    },
  },
  {
    type = "windowFocused",
    label = "Window focused",
    zh = "窗口聚焦",
    description = "Fires when a window of the given app gains focus.",
    zh_desc = "每次切到该应用的窗口都会触发，触发频率可能很高，动作要短。",
    params = {
      { name = "app", type = "string", required = true, placeholder = "Safari" },
    },
  },
  {
    type = "interval",
    label = "Timer",
    zh = "定时器",
    description = "Fires every N minutes while Hammerspoon runs.",
    zh_desc = "Hammerspoon 运行期间循环触发；退出 Hammerspoon 就停，重启后重新计时。",
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
