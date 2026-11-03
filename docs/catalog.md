# Catalog reference

`macroforge/catalog.lua` is the single source of truth for the macro
vocabulary. The engine, the validator, the web editor API
(`GET /catalog`) and the tests all read from it, so adding an action or a
trigger once makes it available everywhere.

A definition looks like this (all types are validated at load time, not at
macro-run time):

```lua
catalog.addAction({
  type = "toggleMute",
  label = "Toggle microphone mute",
  description = "Mutes or unmutes the default input device.",
  params = {
    { name = "notify", type = "boolean", default = true },
  },
})
```

Allowed parameter types: `string`, `text` (multi-line string), `number`,
`boolean`, `choice` (needs `choices`), `macro` (reference to another macro).
`required = true` makes the validator reject a macro that omits the parameter,
and `default` is filled in during normalization.

## Actions

### Application control

| type | parameters | effect |
| --- | --- | --- |
| `launch` | `app` (required) | Launch an app if needed, otherwise focus it. |
| `activate` | `app` (required) | Bring an already-running app to the front. |
| `quit` | `app` (required) | Ask a running app to quit. |

`app` is a bundle name as shown in `/Applications` (e.g. `Safari`, `Xcode`,
`Visual Studio Code`).

### Opening

| type | parameters | effect |
| --- | --- | --- |
| `openURL` | `url` (required) | Open a URL in the default browser. |
| `openFile` | `path` (required) | Open a file, folder or document. Supports `~`. |

### Text input

| type | parameters | effect |
| --- | --- | --- |
| `typeText` | `text` (required) | Send the text as individual keystrokes. |
| `pasteText` | `text` (required), `restore` (bool, default true) | Paste via the clipboard, restoring the previous contents by default. |
| `pressKeys` | `key` (required), `mods` (e.g. `cmd,alt`) | Simulate a shortcut in the frontmost app. Modifiers are normalized and de-duplicated (`cmd, alt,cmd` becomes `alt+cmd`). |
| `setClipboard` | `text` (required) | Replace the clipboard contents. |

Use `typeText` only for short strings that must go through the keyboard
(accessibility fields, terminal prompts); prefer `pasteText` for anything long.

### Window management

| type | parameters | effect |
| --- | --- | --- |
| `snapWindow` | `position` (required), `app` (optional) | Move the focused window to a region of the screen. |
| `moveWindow` | `x`, `y`, `width`, `height` (required, percentages of the screen) | Set an explicit window frame. |

`snapWindow` positions (`catalog.snapFrame`) are `left`, `right`, `top`,
`bottom`, `max`, `fill` (94% of the screen, centered) and `center` (80%). An
unknown position falls back to the whole screen instead of failing.

### Scripting and system

| type | parameters | effect |
| --- | --- | --- |
| `runShell` | `command` (required) | Run through `/bin/sh`. `hs.execute` blocks the Hammerspoon main thread until the command exits, so keep commands short. |
| `runAppleScript` | `script` (required) | Run an AppleScript snippet. |
| `notify` | `title`, `text` (required) | Post a macOS notification. |
| `delay` | `seconds` (required, number) | Pause the macro. Non-blocking: the macro resumes on a timer. |

### Flow

| type | parameters | effect |
| --- | --- | --- |
| `playMacro` | `macro` (required) | Run another macro as part of this one. The reference is resolved by id first, then by name. |
| `if` | `condition` (required), `negate` (bool, default false) | Run the actions up to the matching `endIf` only when the condition holds. |
| `endIf` | | Close an `if` block. Actions after it always run. |
| `setVariable` | `name`, `value` (required) | Store a value under a name. Read it back with `{{name}}` in any text field. |
| `httpRequest` | `url`, `method` (required), `body`, `into` | Call a URL and store the response body in the variable named by `into`. Asynchronous, so the Hammerspoon main loop stays free. A failed request aborts the chain unless `continueOnError` is set, like any other failing action. |

## Triggers

| type | parameters | effect |
| --- | --- | --- |
| `hotkey` | `key` (required), `mods` (default `cmd,ctrl`) | Bind a keyboard shortcut through `hs.hotkey`. |
| `typed` | `string` (required), `delete` (bool, default true) | Fire when a string is typed (suffix match). Modifiers and special keys reset the buffer, and the typed characters are erased when `delete` is true. When one trigger is a prefix of another (`;m` vs `;mail`), the exact match fires immediately and clears the buffer, so the longer one can still be typed from scratch afterwards. |
| `appLaunch` | `app` (required) | Fire when the given app is launched. |
| `windowFocused` | `app` (required) | Fire when a window of the given app gains focus. |
| `interval` | `minutes` (required, default 30) | Fire every N minutes while Hammerspoon runs. |

`hs.hotkey` conflicts with system or Hammerspoon bindings silently; check the
Hammerspoon console for `Macroforge` messages when a hot key does nothing.

## Conditions

The `if` action takes a condition name. All of them are plain questions about
the machine, so a macro behaves the same way every time it is asked:

| condition | parameters | true when |
| --- | --- | --- |
| `appRunning` | `app` | An app with that name is running (case-insensitive). |
| `frontmostApp` | `app` | The frontmost app has that name. |
| `screenCount` | `op`, `count` | The number of screens satisfies the comparison. |
| `variable` | `name`, `op`, `value` | A stored variable satisfies the comparison. |
| `batteryLevel` | `op`, `level` | The battery percentage satisfies the comparison. False on a desktop, where there is no battery to ask. |
| `timeOfDay` | `after`, `before` | The current time is inside the `HH:MM` window. A window that crosses midnight (`22:00` to `06:00`) wraps instead of inverting. |
| `networkReachable` | `host` | The host is reachable. Conservative: an unreachable host reports false rather than leaving the branch undecided. |

`op` is one of `equals`, `notEquals`, `contains`, `greaterThan`, `lessThan`,
`greaterOrEqual`, `lessOrEqual`. A condition that cannot be answered — an
unknown name, or a probe that is missing — is reported as a notification and
the body runs, because silently treating a typo as "false" would hide it.

## Registering your own action

```lua
Macroforge.actions.register("muteZoom", {
  run = function(env, params, done)
    env.runShell("osascript -e 'set volume with output muted'")
    if params.beep then env.notify("Macroforge", "muted") end
    done()
  end,
})
```

The `run` callback receives the environment bridge, the (already normalized)
parameters, and a `done()` continuation you must call — that is what lets the
engine support asynchronous actions such as `delay` and `playMacro`. Place the
`register` call in an init-time hook after `require("macroforge").start()`.
