# Macroforge

Open-source macro automation for macOS, built on top of
[Hammerspoon](https://www.hammerspoon.org/). It reimplements the core of
**Keyboard Maestro 11** (US$ 36 one-time, macOS-only) as a small,
dependency-free Lua engine plus a JSON config format and a local web editor.

## Why

Keyboard Maestro is the classic Mac-only paid automation tool, and there is no
free desktop equivalent that a non-programmer can drive. Hammerspoon already
provides the hard part — a maintained, open-source runtime with event taps,
window management, clipboard and shell access — but its API is a Lua library,
not an editor. Macroforge fills that gap:

- a **vocabulary** layer (actions, triggers, parameters),
- a validated **JSON macro format**,
- a **rule engine** that chains actions, handles failures and nesting,
- **trigger wiring** (hot key, typed string, app launch, window focus, timer),
- **palette chooser** and **local web editor** with an **Apple-style macOS UI**
  (window chrome with traffic lights, light/dark materials),
- a dependency-free **test suite** for all of the above.

Everything you add is plain text in a git repo you own, and the whole thing is
about 2 900 lines of Lua.

## Requirements

- macOS 12 or later
- [Hammerspoon](https://www.hammerspoon.org/) (open source, free)
- Lua 5.3+ *only* to run the tests (Lua ships inside Hammerspoon for normal use)

## Install

1. Get Hammerspoon: `brew install --cask hammerspoon`, then grant Accessibility
   permission when it asks.
2. Point Hammerspoon at this repo:

   ```sh
   mv ~/Downloads/macroforge ~/.hammerspoon/macroforge   # or: git clone <this repo> ~/.hammerspoon/macroforge
   ```

3. Append the bootstrap to `~/.hammerspoon/init.lua`:

   ```lua
   require("macroforge").start()
   ```

4. Reload Hammerspoon (menu bar icon -> Reload Config).

The root `init.lua` is only a convenience wrapper: placing this folder inside
`~/.hammerspoon/macroforge` is enough, because `start()` is idempotent.

## Quick start

`~/.hammerspoon/macroforge/macros/` holds one JSON file per macro. Create
`macros/hello.json`:

```json
{
  "id": "hello",
  "name": "Say hello",
  "trigger": { "type": "hotkey", "parameters": { "mods": "cmd,ctrl,alt", "key": "h" } },
  "actions": [
    { "type": "launch", "parameters": { "app": "Safari" } },
    { "type": "notify", "parameters": { "title": "Macroforge", "text": "hi" } }
  ]
}
```

Then:

- Press **Ctrl+Cmd+Alt+H** — the macro runs.
- `Macroforge.reload()` picks up hand-written files without restarting.
- `Macroforge.showChooser()` — the palette; type to filter, Return to run.
- `Macroforge.openEditor()` — web editor at `http://127.0.0.1:8099/macroforge/`.
- `Macroforge.showManageChooser()` — enable/disable/delete macros.
- From the Hammerspoon console: `Macroforge.playMacro("hello")`.

Five working examples ship in [`macros/`](macros/) (typed timestamp, window
snapping, dev-stack launcher, e-mail signature, hourly stretch reminder).

## Feature map: Keyboard Maestro -> Macroforge

| Keyboard Maestro | Macroforge |
| --- | --- |
| Editor with one macro per entry | `macros/*.json`, one file per macro |
| Trigger: hot key | `trigger.type = "hotkey"` |
| Trigger: typed string | `trigger.type = "typed"` |
| Trigger: application launches/activates | `trigger.type = "appLaunch"` |
| Trigger: application window focuses | `trigger.type = "windowFocused"` |
| Trigger: periodic timer | `trigger.type = "interval"` |
| Activate / Launch / Quit application | `launch`, `activate`, `quit` |
| Type keystroke / insert text | `pressKeys`, `typeText`, `pasteText` |
| Set clipboard to text | `setClipboard` |
| Pause | `delay` |
| Execute shell script | `runShell` |
| Execute AppleScript | `runAppleScript` |
| Manipulate window (move / resize / halves) | `moveWindow`, `snapWindow` |
| Notification / alert | `notify` |
| Execute another macro | `playMacro` (nesting supported) |
| Custom actions via plugins | `Macroforge.actions.register(name, def)` |
| Macro palette, enable/disable, editing | chooser, manage chooser, web editor |
| Conflict palette, semi-automatic groups, file/USB triggers | roadmap, see `docs/architecture.md` |

## Documentation

- [`docs/macro-format.md`](docs/macro-format.md) — JSON schema, settings, examples.
- [`docs/catalog.md`](docs/catalog.md) — every action and trigger with parameters.
- [`docs/architecture.md`](docs/architecture.md) — module map, extension points,
  test strategy and the roadmap toward Keyboard Maestro parity.

## Project layout

```
init.lua                 Hammerspoon bootstrap (require("macroforge").start())
macroforge/init.lua      runtime wiring: hs adapters, triggers, chooser, editor
macroforge/catalog.lua   the vocabulary: action and trigger definitions
macroforge/model.lua     normalization + validation of macro documents
macroforge/store.lua     macro persistence behind an injectable filesystem
macroforge/engine.lua    execution: ordering, failure policy, re-entry guard
macroforge/actions.lua   action implementations on top of the env bridge
macroforge/triggers.lua  hot key / typed / app launch / focus / timer wiring
macroforge/router.lua    local HTTP API that backs the web editor
macroforge/chooser.lua   hs.chooser palettes
macroforge/editor.lua    serves assets/editor.html
macroforge/json.lua      JSON encoder/decoder with a NULL sentinel
macroforge/util.lua      shared helpers
macros/                  example macros
tests/                   dependency-free test suite
tests/editor_smoke.mjs   stub-DOM smoke test for the editor page (Node)
scripts/test.sh          runs the suite
```

## Tests

```sh
brew install lua        # 5.5 works; 5.3+ required
./scripts/test.sh      # or: lua tests/run.lua
```

The suite covers JSON round trips, model validation, the action environment,
engine ordering and failure policy, every trigger type, and the HTTP router —
all against a fake Hammerspoon environment (`tests/fake_env.lua`), so nothing
touches your real desktop.

The web editor is covered too: `tests/test_ui.lua` pins the page's markup, CSS and
id wiring (Apple UI chrome, the `[hidden]` guard, trigger icons, both palettes),
and `tests/test_editor_runtime.lua` runs the page's own script in a stub DOM
through Node to check the sidebar, the dynamic window title and the form/JSON
switch. The Node part skips itself when Node is absent.

## Status

v0.1.0 — engine, triggers, chooser and editor work and are covered by tests.
Remaining Keyboard Maestro parity items (file triggers, USB-device triggers,
conflict palette, macro groups) are tracked in `docs/architecture.md`.
