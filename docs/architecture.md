# Architecture

## Modules

| module | responsibility |
| --- | --- |
| `catalog.lua` | vocabulary: action and trigger definitions, parameter types, `snapFrame` geometry. Pure data + assertions. |
| `json.lua` | JSON encode/decode with a `NULL` sentinel so `nil` values survive round trips. |
| `util.lua` | deep copy/compare, trim, modifier splitting, slugify, shell quoting. |
| `model.lua` | turns user JSON into a canonical macro document and validates it. |
| `store.lua` | reads/writes/deletes `macros/*.json` behind an injectable `fs` interface (`list`, `read`, `write`, `remove`). |
| `engine.lua` | runs a macro: ordering, failure policy, re-entry guard, nesting. |
| `actions.lua` | built-in action implementations, registered into the catalog at load time. |
| `triggers.lua` | binds hot keys, typed strings, app launch/focus and timers to the engine. |
| `router.lua` | dependency-free HTTP API that backs the web editor. |
| `conditions.lua` | the predicates behind `if`: app state, screens, battery, clock, variables, network. Pure, driven by a probe table. |
| `vars.lua` | the shared variable table actions read and write, plus `{{name}}` expansion. |
| `chooser.lua` | `hs.chooser` palettes: run, manage, reload. |
| `editor.lua` | serves `assets/editor.html` for the base path. |
| `init.lua` | the only module that touches Hammerspoon: adapters, lifecycle (`start/reload/stop`), console logging. |

The dependency rule: only `init.lua` knows that Hammerspoon exists. Everything
else is plain Lua, which is why the whole suite runs under `lua` with no
plugins.

## Startup

```
init.lua (Hammerspoon) ── require("macroforge").start()
   ├─ assert the hs runtime is present
   ├─ read settings.json (editorPort, default 8099)
   ├─ build the fs adapter on hs.fs
   ├─ store.load() → one JSON file per macro
   ├─ model.normalize + model.validate (rejections are logged and skipped)
   ├─ triggers.bindAll() → hs.hotkey, eventtap for typed strings, app watchers, timers
   ├─ chooser + router on the configured port
   └─ pay-per-reload: Macroforge.reload() unwinds triggers and rebuilds
```

## Runtime

```
trigger fires → engine.playMacro(macro)
   ├─ string references (nested playMacro) resolve via callbacks.resolve
   ├─ re-entry guard: refuse if the macro is already running
   ├─ for each action in order:
   │    ├─ resolve def from the catalog
   │    ├─ action.run(env, params, done, playMacro)
   │    └─ done() resumes the chain; errors honour continueOnError
   └─ finishes → releases the re-entry guard; concurrent triggers run in parallel (no queue)
```

## The `env` bridge

Actions never call `hs` directly; they call the environment that `init.lua`
builds (`tests/fake_env.lua` implements the same interface for tests):

`launchOrFocus(app)`, `activate(app)`, `quit(app)`, `openURL(url)`,
`openFile(path)`, `typeText(text)`, `paste()`, `pressKeys(mods, key)`,
`screenRect()`, `focusedWindowRect()`, `setFocusedWindowRect(rect)`,
`runShell(command)`, `runAppleScript(script)`, `notify(title, text)`,
`getClipboard()`, `setClipboard(text)`, `timerAfter(seconds, fn)`.

Adding a macOS capability therefore means: adapter in `init.lua`, action in
`actions.lua`, definition in `catalog.lua` — and the editor, the palettes and
the validator pick it up for free.

## Editor HTTP API

Base path `/macroforge` (default port 8099, `http://127.0.0.1:8099/macroforge/`):

| method | path | purpose |
| --- | --- | --- |
| GET | `/macroforge/api/catalog` | the vocabulary for building forms |
| GET | `/macroforge/api/macros` | list macros |
| POST/PUT | `/macroforge/api/macros` | create or update (returns 400 on validation errors) |
| GET | `/macroforge/api/macros/{id}` | read one macro |
| DELETE | `/macroforge/api/macros/{id}` | delete one macro |
| POST | `/macroforge/api/reload` | re-read macros from disk |
| POST | `/macroforge/api/run` | run a macro (used by the editor's Run button) |

The editor is a single static file (`assets/editor.html`) with no build step
and no framework, so it works offline from any browser on the same machine.

The editor file lives at the **project root** (`assets/editor.html`), not inside
`macroforge/`: runtime paths resolve against the project root, so `macroforge/`
is the Lua module directory only.

Every API path refuses a request whose `Origin` is not loopback with
`403 {"error":"refused: this API only accepts requests from the local editor"}`.
A request with no `Origin` is allowed, because only browsers send one. This is
checked rather than worked around with CORS headers, because a "simple request"
(a POST or DELETE with a `text/plain` body) needs no preflight and no permission
to read the response, so omitting `Access-Control-Allow-Origin` would not stop a
webpage from running a `runShell` macro or rewriting macro files.

Four `hs.httpserver` contract details that are easy to get wrong:

- `hs.httpserver.new()` takes a boolean, not a callback. Install the handler
  afterwards with `server:setCallback(fn)`.
- The callback receives `(method, path, headers, body)` but must **return
  `(body, status, headers)`** — the reverse of the router's `(status, body, headers)`
  convention, so `editor.lua` performs that swap.
- libwebserver answers a bodyless POST with `400 Bad Request` before the callback
  runs, so every POST endpoint (`/api/reload`, `/api/run`) must be called with a
  JSON body such as `{}`.
- The listen address is `server:setInterface("loopback")` — there is no
  `setAddress` — and it must be set before `server:start()`. The default is every
  interface, which puts the API on the LAN; `editor.start` raises instead of
  starting a server it cannot pin.

## Tests

```sh
./scripts/test.sh        # lua 5.3+, default binary name lua (override with LUA=...)
```

153 tests, 0 failures. The runner is `tests/run.lua`, the fake Hammerspoon
environment is `tests/fake_env.lua`, and the Node-based stub-DOM smoke test is
`tests/editor_smoke.mjs` driven by `tests/test_editor_runtime.lua`. See
[`HARNESS.md`](HARNESS.md) for the file-by-file inventory, the env-contract
check, and the mutation testing that proves the suite has teeth.

To add a test, create `tests/test_<area>.lua` using the global `test(name, fn)`
helper, `eq(expected, actual, message)` and `truthy(value, message)`, then add it
to the hardcoded `files` list in `tests/run.lua`.

## Roadmap to Keyboard Maestro parity

Done: hot key / typed string / app launch / window focus / timer triggers,
application and window control, keyboard and clipboard input, shell and
AppleScript scripting, delays, notifications, macro nesting, custom actions,
palettes, enable/disable management, web editor, hot reload.

Not yet implemented (highest value first):

1. **File and folder triggers** — "when a file appears in X" via `hs.pathwatcher`.
2. **Conditional actions** — `if`/`else`, "if application is frontmost", which
   the engine can already express as a new action type.
3. **Variables and clipboard history** — named values persisted via
   `hs.settings`, plus a clipboard stack.
4. **Conflict palette** — `hs.chooser` per conflict when two bindings collide,
   replacing the current "priority or nothing".
5. **Wireless-network and USB-device triggers** via `hs.wifi`/`hs.usb` watchers.
6. **Editor polish** — drag-and-drop reordering, duplicate macro, import/export
   of the whole macro folder.

Compatibility note: the code targets Lua 5.4/5.5 as well as the Lua bundled with
Hammerspoon. In particular, generic `for` loop variables are const from 5.4 on
and must not be reassigned (this bit `util.splitMods` once).
