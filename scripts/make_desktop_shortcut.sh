#!/bin/sh
# make_desktop_shortcut.sh -- install "Macroforge AI.app" on the Desktop.
#
# The launcher opens the editor on the AI translate macro and fires it once.
# The icon is drawn from the page's brand mark (blue gradient, white bolt), so
# the shortcut does not depend on artwork that does not exist in the repo.
#
# Usage: scripts/make_desktop_shortcut.sh

set -eu

DEST="$HOME/Desktop/Macroforge AI.app"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

python3 - "$WORK" <<'PY'
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1]
S = 1024
PAD = 100
RADIUS = 225

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

top = (111, 215, 251)
mid = (10, 132, 255)
bottom = (94, 92, 230)

grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    t = y / (S - 1)
    if t < 0.52:
        color = lerp(top, mid, t / 0.52)
    else:
        color = lerp(mid, bottom, (t - 0.52) / 0.48)
    gd.line([(0, y), (S, y)], fill=color + (255,))

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([PAD, PAD, S - PAD, S - PAD], radius=RADIUS, fill=255)

tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
tile.paste(grad, (0, 0), mask)

shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle(
    [PAD, PAD + 18, S - PAD, S - PAD + 18], radius=RADIUS, fill=(0, 0, 0, 70)
)

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))
img.alpha_composite(tile)

# The bolt path from the editor's brand mark (viewBox 0 0 24 24).
bolt = [(13, 2), (4.5, 13.5), (11, 13.5), (9.8, 22), (19.5, 10), (13, 10)]
scale = 29
center = S / 2
poly = [(center + (x - 12) * scale, center + (y - 12) * scale) for x, y in bolt]

bolt_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(bolt_shadow).polygon(
    [(x, y + 10) for x, y in poly], fill=(0, 30, 80, 80)
)
img.alpha_composite(bolt_shadow.filter(ImageFilter.GaussianBlur(10)))
ImageDraw.Draw(img).polygon(poly, fill=(255, 255, 255, 255))

highlight = ImageDraw.Draw(img)
highlight.rounded_rectangle(
    [PAD + 8, PAD + 8, S - PAD - 8, S - PAD - 8],
    radius=RADIUS - 6,
    outline=(255, 255, 255, 46),
    width=3,
)

iconset = os.path.join(out, "Macroforge.iconset")
os.makedirs(iconset, exist_ok=True)
for size in (16, 32, 128, 256, 512):
    img.resize((size, size), Image.LANCZOS).save(
        os.path.join(iconset, "icon_%dx%d.png" % (size, size))
    )
    img.resize((size * 2, size * 2), Image.LANCZOS).save(
        os.path.join(iconset, "icon_%dx%d@2x.png" % (size, size))
    )
PY

iconutil -c icns "$WORK/Macroforge.iconset" -o "$WORK/applet.icns"

APP="$WORK/Macroforge AI.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/applet.icns" "$APP/Contents/Resources/applet.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Macroforge AI</string>
  <key>CFBundleDisplayName</key><string>Macroforge AI</string>
  <key>CFBundleIdentifier</key><string>local.macroforge.launcher</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>run</string>
  <key>CFBundleIconFile</key><string>applet.icns</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

cat > "$APP/Contents/MacOS/run" <<'RUN'
#!/bin/sh
open "http://127.0.0.1:8099/macroforge/?id=ai-translate"
HS="/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs"
if ! pgrep -xq Hammerspoon; then
  open -a Hammerspoon
  sleep 5
fi
"$HS" -c 'Macroforge.playMacro("ai-translate")' >/dev/null 2>&1
osascript -e 'display notification "AI 翻译已触发，几秒后系统通知会弹出英文译文。" with title "Macroforge"' >/dev/null 2>&1
RUN
chmod +x "$APP/Contents/MacOS/run"

# Replace only this launcher; keep a copy of a previous build inside $WORK.
if [ -e "$DEST" ]; then
  mv "$DEST" "$WORK/previous.app"
fi
ditto "$APP" "$DEST"
touch "$DEST"
echo "installed: $DEST"
