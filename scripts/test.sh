#!/bin/sh
# Run the Macroforge test suite. Requires Lua 5.3+ on PATH (LUA=lua5.4 to override).
set -e
cd "$(dirname "$0")/.."
LUA_BIN="${LUA:-lua}"
command -v "$LUA_BIN" >/dev/null 2>&1 || {
  echo "error: '$LUA_BIN' not found. Install Lua 5.3+ or set LUA=/path/to/lua" >&2
  exit 127
}
exec "$LUA_BIN" tests/run.lua
