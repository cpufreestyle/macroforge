-- chooser.lua -- the macro palette, built on hs.chooser.

local model = require("macroforge.model")

local chooser = {}
chooser.__index = chooser

function chooser.new(opts)
  return setmetatable({
    hs = opts.hs,
    store = opts.store,
    onRun = opts.onRun or function() end,
    onCommand = opts.onCommand or function() end,
    _impl = nil,
  }, chooser)
end

function chooser.manageRows(store)
  local macros = store.macros
  local rows = {}
  for _, macro in ipairs(macros) do
    rows[#rows + 1] = {
      text = (macro.enabled and "\u{2714}  " or "\u{2716}  ") .. macro.name,
      subText = model.summarize(macro),
      kind = "macro",
      id = macro.id,
    }
  end
  rows[#rows + 1] = {
    text = "\u{270E}  Open visual editor\u{2026}",
    subText = "Create, reorder and refine macros in the browser",
    kind = "action",
    command = "editor",
  }
  rows[#rows + 1] = {
    text = "\u{21BB}  Reload macros from disk",
    subText = "~/.hammerspoon/macroforge/macros",
    kind = "action",
    command = "reload",
  }
  return rows
end

function chooser:_macroRows()
  local rows = {}
  for _, macro in ipairs(self.store.macros) do
    if macro.enabled then
      rows[#rows + 1] = {
        text = "\u{25B6}  " .. macro.name,
        subText = model.summarize(macro),
        kind = "macro",
        id = macro.id,
      }
    end
  end
  rows[#rows + 1] = {
    text = "\u{270E}  Open visual editor\u{2026}",
    subText = "Build macros without writing code",
    kind = "action",
    command = "editor",
  }
  rows[#rows + 1] = {
    text = "\u{2699}  Manage macros\u{2026}",
    subText = "Enable or disable macros",
    kind = "action",
    command = "manage",
  }
  rows[#rows + 1] = {
    text = "\u{21BB}  Reload macros from disk",
    subText = "~/.hammerspoon/macroforge/macros",
    kind = "action",
    command = "reload",
  }
  return rows
end

function chooser:show()
  if not self._impl then
    self._impl = self.hs.chooser.new(function(choice)
      if not choice then return end
      if choice.kind == "macro" then
        self.onRun(choice.id)
      elseif choice.kind == "action" then
        self.onCommand(choice.command)
      end
    end)
  end
  local rows = self:_macroRows()
  self._impl:choices(rows)
  self._impl:rows(math.min(12, #rows))
  self._impl:show()
end

function chooser:refresh()
  if self._impl then
    self._impl:choices(self:_macroRows())
  end
end

-- Generic one-shot chooser used for the "manage macros" panel.
function chooser.simple(hs, rows, onChoose)
  rows = rows or {}
  if #rows == 0 then
    rows[1] = { text = "(no macros yet)", kind = "empty" }
  end
  local impl = hs.chooser.new(function(choice)
    if choice and type(onChoose) == "function" then onChoose(choice) end
  end)
  impl:choices(rows)
  impl:rows(math.min(12, #rows))
  impl:show()
  return impl
end

return chooser
