# Specification

This document is the contract. It states what Macroforge promises, in enough
detail that a change is either inside the contract or a deliberate change to it.
`docs/catalog.md` lists the vocabulary, `docs/macro-format.md` is the JSON
schema quick reference; this file describes behaviour, invariants and limits.

## Scope

Macroforge runs inside Hammerspoon on macOS. It is a Lua library plus one static
HTML page. There is no build step, no package manager, no network dependency and
no background daemon of its own — if Hammerspoon is not running, nothing is
served on port 8099 and `http://127.0.0.1:8099/macroforge/` fails to connect.

## Modules and the dependency rule

Fifteen modules under `macroforge/`, 2945 lines total:

| module | lines | responsibility |
| --- | --- | --- |
| `init.lua` | 549 | the only module that touches Hammerspoon: adapters, lifecycle, logging |
| `catalog.lua` | 339 | the vocabulary: action and trigger definitions |
| `json.lua` | 284 | JSON encode/decode with a NULL sentinel |
| `model.lua` | 264 | normalization and validation of macro documents |
| `actions.lua` | 251 | built-in action implementations |
| `engine.lua` | 210 | execution: ordering, failure policy, re-entry guard |
| `router.lua` | 187 | the local HTTP API behind the editor |
| `conditions.lua` | 169 | predicates behind `if` |
| `store.lua` | 141 | macro persistence behind an injectable `fs` |
| `triggers.lua` | 134 | hot key, typed string, app launch, focus, timer wiring |
| `chooser.lua` | 124 | `hs.chooser` palettes |
| `hsfs.lua` | 112 | filesystem adapter, atomic writes |
| `util.lua` | 62 | shared helpers |
| `vars.lua` | 74 | the shared variable table and `{{name}}` expansion |
| `editor.lua` | 45 | `hs.httpserver` wiring, pinned to loopback |

Only `init.lua` knows Hammerspoon exists. Everything else is plain Lua, which is
what lets the whole suite run under `lua` alone.

`assets/editor.html` is 2221 lines of HTML, CSS and script with no framework and
no build step. It is served from the project root, not from `macroforge/`.

### Editor teaching layer

The form is the whole onboarding surface, because there is no separate tutorial
and no wizard. Three pieces carry it:

- **Field tips.** Every parameter label renders a `?` badge and a one-line
  explanation built from the catalog: the parameter type, whether it is
  required, its placeholder, and a note for well-known names (`app`, `mods`,
  `into`, `command`, …). The tips are generated, so a new catalog entry cannot
  ship without one.
- **One shared bubble.** `#tip` is a single fixed-position node for the page.
  A bubble nested inside a field would be clipped by the sidebar's and the
  editor's scroll containers, which is where the labels sit. Native `title`
  attributes are folded into the same bubble on first hover, so the page never
  shows two competing tooltip systems.
- **Quick start.** A four-step card above the first card explains the order to
  do things in: pick a macro, pick a trigger, add actions, save then run. It is
  dismissible and the dismissal is remembered in `localStorage` under
  `macroforge.quickstart.dismissed`; a missing or throwing `localStorage`
  (a `file://` page) is treated as "not dismissed" rather than fatal.

Trigger and action definitions carry the vocabulary twice. `label` and
`description` are the stable English text used by the docs, the console and the
tests; `zh` and `zh_desc` are what the editor displays. A definition without the
Chinese fields falls back to the English ones, so a user-added action stays
readable instead of rendering blank — which is why the Chinese names are
required of the shipped catalog but optional for third-party additions.

## Macro documents

A macro is one JSON file in `macros/`, named after its id. Canonical fields are
`id`, `name`, `enabled`, `trigger` and `actions`. Normalization coerces editor
strings (`enabled: "false"`, numbers as text) before validation runs, so a file
hand-edited in a text editor still loads.

Validation rejects rather than guessing: a macro with no actions, an unknown
action or trigger type, or a parameter the definition does not declare is
refused, logged, and skipped. A rejected file never stops the others from
loading — `store.load()` returns the good macros plus a list of `{file, error}`
pairs, and the editor shows both.

## Execution semantics

1. **Order.** Actions run in array order. Each action receives `done`; the chain
   advances only when `done()` is called, so a delay genuinely suspends that
   macro instead of blocking Hammerspoon's main thread.
2. **Failure policy.** An error honours `continueOnError`; without it the run
   stops and the re-entry guard is still released, so a failed macro can be
   retried.
3. **Re-entry guard.** A macro that is already running refuses a second trigger
   rather than running two copies that interleave writes to shared state.
4. **Nesting.** `playMacro` takes a macro id or name, resolved through
   `callbacks.resolve`. A nested macro has its own engine frame, so its
   variables and its re-entry guard are independent of the parent's. A nested
   macro runs to completion before the parent's chain resumes.
5. **Concurrency.** There is no queue. Two different macros triggered at the
   same moment run in parallel, each with its own frame. This is deliberate: a
   long `runShell` macro must not delay an unrelated hot key.
6. **Blocks.** `if`/`endIf` with `else` and nested blocks. A false branch is
   skipped, the chain resumes at the matching `endIf`, and a macro that ends
   inside a skipped block still completes cleanly. An unknown condition is
   reported and the body still runs.
7. **Variables.** `setVariable` writes a value the next action can read;
   `{{name}}` in action parameters is expanded at run time, and an unknown
   placeholder is left in place rather than blanked.

## Triggers

Hot keys, typed strings, app launch, window focus and timers are bound on start
and rebuilt on reload. Binding is best-effort per trigger: a failure to bind one
is logged and does not prevent the rest from binding.

## The HTTP API

Base path `/macroforge`, default port 8099, bound to `127.0.0.1` only — the API
runs shell commands and edits files, so it must not be reachable from other
machines on the network.

| method | path | purpose |
| --- | --- | --- |
| GET | `/macroforge/api/catalog` | the vocabulary for building forms |
| GET | `/macroforge/api/macros` | list macros plus load errors |
| POST/PUT | `/macroforge/api/macros` | create or update, 400 on validation errors |
| GET | `/macroforge/api/macros/{id}` | read one macro |
| DELETE | `/macroforge/api/macros/{id}` | delete one macro |
| POST | `/macroforge/api/reload` | re-read macros from disk |
| POST | `/macroforge/api/run` | run a macro |

### Origin policy

Every API path refuses a request whose `Origin` is not loopback, with
`403 {"error":"refused: this API only accepts requests from the local editor"}`.
A request with no `Origin` is allowed, because only browsers send one — absence
means a local caller such as `curl` or the Hammerspoon console.

This is enforced by checking the header, not by omitting CORS headers. Removing
`Access-Control-Allow-Origin` only stops the *response* from being readable, and
that is not the actual problem: a "simple request" (a POST or DELETE with a
`text/plain` body) needs no preflight and no permission to read the answer, so
any webpage could otherwise make the user's browser run a `runShell` macro or
delete and rewrite macro files. The check accepts `http` and `https` on
`127.0.0.1`, `localhost` and `[::1]`, with or without a port, case-insensitively;
it rejects `file://`, malformed values, and lookalikes such as
`http://127.0.0.1.evil.example`.

### Three transport details that are easy to get wrong

- `hs.httpserver.new()` takes a boolean, not a callback; install the handler
  afterwards with `server:setCallback(fn)`.
- The listen address is set with `server:setInterface("loopback")`, and it has to
  be set *before* `server:start()`. There is no `setAddress`, and the server
  listens on every interface by default, so a misspelled or missing call leaves
  the API — which runs shell commands and rewrites macro files — reachable from
  every machine on the LAN. `editor.start` raises rather than start a server it
  cannot pin, because a call to a method the server object does not have would
  otherwise fail silently.
- The callback receives `(method, path, headers, body)` but must **return
  `(body, status, headers)`**, the reverse of the router's convention.
- libwebserver answers a bodyless POST with `400 Bad Request` before the
  callback runs. Every POST endpoint must therefore be called with a JSON body
  such as `{}`; a bodyless `POST /api/reload` returns an empty 400 that never
  reaches the router. The editor always sends a body, so this is a caller
  contract, not a bug.

## Error reporting

The router never returns a bare status code. Every failure carries a JSON `error`
string that names the cause ("macro not found", "invalid JSON body: ...",
"macro needs at least one action"). The editor surfaces that text in a toast.

## Non-goals

Macroforge does not queue, schedule across sessions, or sync macros between
machines. It does not authenticate, because it binds to loopback and refuses
foreign Origins; anything that widens the listen address reopens the question.
