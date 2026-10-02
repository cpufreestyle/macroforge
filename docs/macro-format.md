# Macro format

Each macro is one JSON file in `~/.hammerspoon/macroforge/macros/`. The file
name is ignored (the `id` field is the key), so pick a readable one.

## Schema

```jsonc
{
  "id": "typed-timestamp",       // required, matches ^[%w][%w%-_%.]*$ (no "/", no "..")
  "name": "Type timestamp",      // required, <= 80 characters
  "enabled": true,               // optional, default true
  "continueOnError": false,      // optional: keep going when an action fails
  "trigger": {                   // optional; without one the macro runs from the chooser/editor
    "type": "typed",             // see docs/catalog.md
    "parameters": { "string": ";now", "delete": true }
  },
  "actions": [                   // required, at least one action
    {
      "type": "runShell",
      "parameters": { "command": "date '+%Y-%m-%d %H:%M' | tr -d '\\n' | pbcopy" }
    }
  ]
}
```

Type names and parameter names are case-insensitive on load, choices are
lower-cased, string numbers are coerced to numbers, and defaults are filled in
— so hand-written JSON does not have to be exact, but invalid values are
reported instead of silently ignored.

## Validation rules

`Macroforge.model.validate` rejects, with a readable message:

- an id that is empty, `.`, `..` or contains characters outside
  `[A-Za-z0-9-_.]`,
- a missing or over-long name,
- an unknown trigger type,
- an empty action list,
- an unknown action type,
- a missing required parameter or a parameter of the wrong type
  (number/boolean/choice).

Invalid macros are never registered, so a typo in one file cannot break the
rest of the setup: `store:load` reports the file and leaves the macro out of
the chooser, the editor and every trigger binding. You see the problem as a
banner in the editor and a notification on reload, not as a run-time failure.
During development watch the Hammerspoon console.

## Referencing other macros

`playMacro` takes a `macro` parameter that resolves the target by `id` first,
then by display `name`. Cycles are caught: a macro that is already running
refuses re-entry, which also protects a hot key you hold down.

```json
{ "type": "playMacro", "parameters": { "macro": "typed-timestamp" } }
```

## Settings

`~/.hammerspoon/macroforge/settings.json`:

```json
{
  "editorPort": 8099
}
```

| key | default | effect |
| --- | --- | --- |
| `editorPort` | `8099` | Port of the local web editor. |

## Failure policy

Engine behaviour on a failing action:

- default: abort the macro, post a notification, log to the console;
- `continueOnError: true`: log, keep running, and report at the end;
- `delay` and `playMacro` are asynchronous — the action returns, the macro
  resumes when the nested macro (or the timer) finishes.
