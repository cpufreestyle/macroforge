# Test harness

Macroforge's suite is dependency-free: it needs Lua 5.3+ and nothing else. No
framework, no plugins, no network, and no test ever touches the real desktop.
The one Node-based test skips itself when Node is absent, so the suite still
passes on a bare Lua install.

## Running

```sh
./scripts/test.sh          # uses `lua` from PATH
LUA=/opt/homebrew/bin/lua ./scripts/test.sh
lua tests/run.lua          # direct
```

Current result: **145 tests, 0 failures.** The runner prints one `ok` or `FAIL`
line per test and exits non-zero on any failure, so it works as a CI gate.

## How the runner works

`tests/run.lua` is the whole harness. It defines three globals, then loads each
test file and executes every registered test in order:

- `test(name, fn)` — register a test. A test passes when `fn` returns without
  raising; anything raised is a failure and its message is printed.
- `eq(expected, actual, message)` — deep-compare, printing both values on
  mismatch.
- `truthy(value, message)` / `falsy(value, message)`.

`tests/run.lua` holds a hardcoded file list, so **a new test file must be added
to that list or it will not run.** This is deliberate: a silently ignored test
file is worse than an explicit list to maintain.

## Layout

| file | tests | what it pins |
| --- | --- | --- |
| `test_model.lua` | 16 | normalization of editor strings, validation rejections |
| `test_conditions.lua` | 14 | every `if` predicate against a probe table |
| `test_router.lua` | 13 | each API route, status codes, Origin policy |
| `test_triggers.lua` | 12 | hot key, typed string, app launch, focus, timer binding |
| `test_blocks.lua` | 11 | if/else/endIf, nesting, skip and resume |
| `test_actions.lua` | 11 | each action against the fake env |
| `test_engine.lua` | 10 | ordering, failure policy, re-entry guard |
| `test_ui.lua` | 9 | the page's markup, CSS and id wiring |
| `test_store.lua` | 9 | load/save/delete through an in-memory `fs` |
| `test_json.lua` | 8 | round trips, the NULL sentinel, number and string edges |
| `test_vars.lua` | 7 | variable storage and `{{name}}` expansion |
| `test_hsfs.lua` | 5 | the filesystem adapter, directories skipped |
| `test_env_contract.lua` | 5 | the fake env matches the real one exactly |
| `test_editor.lua` | 7 | the `hs.httpserver` wiring, argument order, loopback bind |
| `test_blocks_hook.lua` | 4 | the `skip` hook passed to actions |
| `test_macros.lua` | 3 | the shipped examples in `macros/` load cleanly |
| `test_editor_runtime.lua` | 1 | drives the page's script through Node (below) |

`tests/fake_env.lua` is a recording Hammerspoon stub. It exposes the same env
bridge the real `init.lua` builds (`launchOrFocus`, `typeText`, `runShell`,
`notify`, `timerAfter`, the http request, the probe table, …) and records every
call in `env.calls`, so tests assert on what an action *did* rather than on its
implementation.

## The env contract test

`tests/test_env_contract.lua` greps `env.([%w_]+)%s*=` out of
`macroforge/init.lua` and asserts the fake exposes exactly those hooks and
nothing more. This is what keeps the fake honest: adding an adapter to `init.lua`
without adding it to `fake_env.lua` fails the suite.

## The one Node test

`assets/editor.html` is the only part of Macroforge whose behaviour Lua cannot
observe — it renders the sidebar, writes the dynamic window title and switches
between the form and JSON views. `tests/test_editor_runtime.lua` builds the exact
payload the HTTP API answers (the catalog plus every macro in `macros/`) and
hands it to `tests/editor_smoke.mjs`, which runs the page's own script against a
minimal stub DOM and asserts on the result.

The test is skipped, not failed, when `node` is not on PATH. To run the Node
harness directly you need the *API payload*, not a macro file:

```sh
lua -e 'package.path="./?.lua;./?/init.lua;"..package.path
local s=require("macroforge.store"); local c=require("macroforge.catalog")
local fs={list=function(d) local p=io.popen("ls -1 "..d.." 2>/dev/null"); local o,l={},p:read("*l"); while l do o[#o+1]=l; l=p:read("*l") end; p:close(); return o end,
 read=function(x) local h=io.open(x,"rb"); if not h then return nil end; local c2=h:read("*a"); h:close(); return c2 end}
local m,e=s.new({fs=fs,macrosDir="./macros"}):load()
print(require("macroforge.json").encode({macros=m,catalog={actions=c.actions,triggers=c.triggers},errors={}}))' > /tmp/fx.json
node tests/editor_smoke.mjs /tmp/fx.json assets/editor.html
```

## Verifying the harness has teeth

A suite that passes no matter what the code does is worthless, so the suite was
mutation-tested. Three mutations were each introduced into `engine.lua` and
reverted:

| mutation | result |
| --- | --- |
| make the nested-macro counter shared instead of per frame | 1 test fails |
| read the wrong engine stack frame | several tests fail |
| drop the frame push on entry | 6 tests fail |
| drop `setInterface("loopback")` from `editor.start` | 2 tests fail |
| re-guard `setInterface` behind `if server.setInterface then` | 1 test fails |

Each mutation produced failures, and restoring the code returned the suite to
145 green. The tests observe real behaviour, not mocked outcomes.

## Adding a test

1. Create `tests/test_<area>.lua` using the global `test(name, fn)` and
   `eq`/`truthy`.
2. Add the bare module name (no `tests/`, no `.lua`) to the `files` list in
   `tests/run.lua`.
3. If the area needs a new env hook, add it to `macroforge/init.lua` **and**
   `tests/fake_env.lua` in the same change — `test_env_contract.lua` enforces it.
4. Run the suite and confirm the new test both passes when the behaviour is
   right and fails when it is wrong. A test that cannot fail is not a test.

## Known limits

- The suite is offline by design. It cannot prove that a hot key reaches macOS,
  that a window actually moves, or that the editor page works in a real browser;
  those need a running Hammerspoon and a browser. Mutation testing plus the
  stub-DOM smoke test are the strongest offline evidence available.
- `tests/editor_smoke.mjs` covers rendering, the window title, the mode switch
  and the JSON-mode save path (it asserts that saving posts the edited object and
  that a real id clash is still rejected). It does not exercise the form-to-JSON
  conversion, deletion, or anything that needs a real browser and a real
  Hammerspoon behind it.
