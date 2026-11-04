#!/bin/sh
# Macroforge one-command installer. Idempotent: safe to re-run to update.
#
#   sh scripts/install.sh
#
# What it does:
#   1. copies macroforge/, assets/, macros/ and the root init.lua wrapper
#      into ~/.hammerspoon/macroforge (or $HAMMERSPOON_DIR/macroforge),
#   2. appends the idempotent bootstrap block to ~/.hammerspoon/init.lua
#      if it is not already there,
#   3. prints the two manual steps that remain (Accessibility permission,
#      reload Hammerspoon).
set -e

SRC="$(cd "$(dirname "$0")/.." && pwd)"
HS_DIR="${HAMMERSPOON_DIR:-$HOME/.hammerspoon}"
DEST="$HS_DIR/macroforge"
BOOT="$HS_DIR/init.lua"

if [ ! -d "$HS_DIR" ]; then
  echo "error: $HS_DIR not found -- install Hammerspoon first (brew install --cask hammerspoon)" >&2
  exit 1
fi

echo "==> copying Macroforge into $DEST"
mkdir -p "$DEST"
for item in macroforge assets macros init.lua; do
  rm -rf "$DEST/$item"
  cp -R "$SRC/$item" "$DEST/$item"
done

echo "==> wiring the bootstrap into $BOOT"
touch "$BOOT"
if grep -q 'require("macroforge").start()' "$BOOT" 2>/dev/null; then
  echo "    bootstrap already present, skipping"
else
  cat >> "$BOOT" <<'BLOCK'

-- >>> macroforge (managed by scripts/install.sh; do not edit by hand) >>>
require("macroforge").start()
-- <<< macroforge <<<
BLOCK
fi

cat <<'NEXT'

Done. Two manual steps remain:

  1. If macOS asks for Accessibility permission, grant it to Hammerspoon
     (System Settings -> Privacy & Security -> Accessibility).
  2. Reload Hammerspoon (menu bar icon -> Reload Config).

Then: menu-bar hammer (or Ctrl+Cmd+Alt+M) opens the palette,
      Ctrl+Cmd+Alt+E opens the web editor.
NEXT
