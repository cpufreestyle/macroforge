-- test_ui.lua -- regression tests for the Apple-style editor page.
--
-- assets/editor.html is a single file of markup, CSS and script with no
-- framework and no testable entry points, so what can silently break is the
-- wiring *between* the three. These tests read the shipped file and pin that
-- wiring. Two of them guard real bugs found while restyling the page:
--
--   1. \`.empty { display: flex }\` overrode the UA \`[hidden] { display: none }\`,
--      so the empty-state overlay kept covering the form after a macro was
--      selected. The fix is the global guard below, and this test refuses to
--      pass if someone later "solves" the overlap by deleting the overlay
--      instead of keeping it guarded;
--   2. the toolbar title is written from renderStatus(), so losing the
--      #window-title anchor throws on the very first render and leaves the
--      sidebar empty.

local EDITOR_PATH = "assets/editor.html"

local function readEditor()
  local fh = assert(io.open(EDITOR_PATH, "r"), EDITOR_PATH .. " must exist")
  local html = fh:read("*a")
  fh:close()
  return html
end

-- Every element id the script looks up, in order of first appearance.
local function jsLookupIds(html)
  local seen, ids = {}, {}
  for id in html:gmatch("%$%(%s*'([%w_%-]+)'%s*%)") do
    if not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  return ids
end

-- Ids the script builds at runtime, so the markup cannot contain them.
local RUNTIME_IDS = {
  ["macro-id-list"] = true, -- ensureDatalist() appends the <datalist> itself
}

-- Ids the script must definitely look up; they keep jsLookupIds honest, so a
-- broken pattern cannot make the test below pass vacuously.
local REQUIRED_LOOKUPS = {
  "window-title", "macro-list", "btn-save", "status-count", "form-wrap", "json-view",
}

test("ui: the toolbar title is anchored once and written by renderStatus", function()
  local html = readEditor()
  eq(1, select(2, html:gsub('id="window%-title"', "")),
    "#window-title must appear exactly once in the toolbar")
  truthy(html:find("function renderStatus()", 1, true), "renderStatus() is missing")
  truthy(html:find("%$%('window%-title'%)", 1, false) ~= nil,
    "renderStatus() should write the current macro name into #window-title")
end)

test("ui: the window chrome ships three traffic lights", function()
  local html = readEditor()
  truthy(html:find('class="traffic-lights"', 1, true), ".traffic-lights wrapper is missing")
  for _, colour in ipairs({ "close", "min", "zoom" }) do
    truthy(html:find('class="tl ' .. colour .. '"', 1, true),
      "traffic light ." .. colour .. " is missing")
  end
  truthy(html:find("%.traffic%-lights%s*{", 1, false), "the traffic lights need styling")
  truthy(html:find("%.traffic%-lights:hover", 1, false) ~= nil,
    "traffic lights should reveal their glyphs on hover")
end)

test("ui: a global hidden guard keeps the empty state from covering the form", function()
  local html = readEditor()
  -- The offending rule has to still be there: the bug is guarded, not avoided
  -- by deleting the overlay.
  truthy(html:find("%.empty%s*{", 1, false), ".empty must still be styled")
  truthy(html:find("%.empty%s*{[^}]*display%s*:%s*flex", 1, false),
    ".empty must still be a flex overlay; do not hide the bug by removing it")
  truthy(html:find("%[hidden%]%s*{%s*display%s*:%s*none%s*!important%s*;%s*}", 1, false),
    "[hidden] { display: none !important } is required to beat .empty's display")
end)

test("ui: every trigger type in the catalog has a sidebar icon", function()
  local catalog = require("macroforge.catalog")
  local html = readEditor()
  for _, def in ipairs(catalog.triggers) do
    truthy(html:find(def.type .. ": '<svg", 1, true),
      "trigger type '" .. def.type .. "' has no icon in TRIGGER_ICONS")
  end
  truthy(html:find("manual: '<svg", 1, true),
    "TRIGGER_ICONS needs the 'manual' fallback for unknown triggers")
  truthy(html:find("function triggerIconSVG(type)", 1, true),
    "triggerIconSVG() should map a trigger type onto its icon")
  truthy(html:find('class="mi%-icon"', 1, false) == nil,
    "list rows should build their icons from TRIGGER_ICONS, not inline markup")
  truthy(html:find("mi%-icon", 1, false) ~= nil, "list rows should carry the mi-icon class")
end)

test("ui: every element id looked up from the script exists in the markup", function()
  local html = readEditor()
  local ids = jsLookupIds(html)
  truthy(#ids >= #REQUIRED_LOOKUPS, "expected to find the script's lookups, got " .. #ids)

  local lookup = {}
  for _, id in ipairs(ids) do lookup[id] = true end
  for _, must in ipairs(REQUIRED_LOOKUPS) do
    truthy(lookup[must], "the script should look up #" .. must)
  end

  local missing = {}
  for _, id in ipairs(ids) do
    if not RUNTIME_IDS[id] and not html:find('id="' .. id .. '"', 1, true) then
      missing[#missing + 1] = id
    end
  end
  eq({}, missing, "ids the script looks up but that no element declares: "
    .. table.concat(missing, ", "))
end)

test("ui: light and dark palettes are both defined", function()
  local html = readEditor()
  for _, chrome in ipairs({ ".toolbar", ".sidebar", ".statusbar" }) do
    truthy(html:find(chrome .. "%s*{", 1, false) ~= nil, chrome .. " needs styling")
  end
  truthy(html:find("blur%(", 1, false) ~= nil, "the toolbar and panels should use a blur material")
  truthy(html:find("saturate%(", 1, false) ~= nil, "the glass material should saturate its backdrop")
  truthy(html:find("@media %(prefers%-color%-scheme: dark%)", 1, false) ~= nil,
    "a dark palette is required")
  for _, token in ipairs({ "--panel", "--card", "--accent", "--fill", "--separator" }) do
    local _, count = html:gsub(token .. ":", "")
    truthy(count >= 2, token .. " should be declared for both palettes, found " .. count)
  end
end)

test("ui: the running editor serves the restyled page", function()
  -- Macroforge.startEditor() reads assets/editor.html and hand it to the
  -- router as editorHTML; Hammerspoon then keeps that copy in memory for the
  -- life of the process, so what a browser receives can drift from the file
  -- on disk. This reproduces that wiring instead of trusting the file.
  local storeMod = require("macroforge.store")
  local routerMod = require("macroforge.router")
  local router = routerMod.new({
    store = storeMod.new({ fs = {
      list = function() return {} end,
      read = function() return nil end,
      write = function() return true end,
      remove = function() return false end,
    }, macrosDir = "/macros" }),
    editorHTML = readEditor(),
    reload = function() return true end,
    run = function() return true end,
  })
  local status, body = router:route("GET", "/macroforge/", "")
  eq(200, status)
  truthy(body:find('class="traffic-lights"', 1, true),
    "the served page should carry the macOS window chrome")
  truthy(body:find("%[hidden%]%s*{%s*display%s*:%s*none%s*!important%s*;%s*}", 1, false) ~= nil,
    "the served page should carry the [hidden] guard")
  truthy(body:find("function triggerIconSVG(type)", 1, true),
    "the served page should carry the sidebar icons")
end)
