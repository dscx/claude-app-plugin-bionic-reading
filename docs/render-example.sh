#!/bin/sh
# Regenerate docs/example.png, the strength comparison used in the README.
#
#     docs/render-example.sh
#
# Rebuilds the page through assets/bionic.js, shoots it with headless Chrome at
# 2x, then trims the trailing whitespace so the image cannot end up clipped or
# padded when the text changes length. Needs node, Google Chrome and Pillow.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHROME=${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}

node "$ROOT/docs/build-example.js"

"$CHROME" --headless --disable-gpu --hide-scrollbars \
	--screenshot="$ROOT/docs/example.png" \
	--window-size=780,900 --force-device-scale-factor=2 \
	--default-background-color=FFFFFFFF \
	"file://$ROOT/docs/example.html" 2>/dev/null

python3 - "$ROOT/docs/example.png" <<'PY'
import sys
from PIL import Image, ImageChops

path = sys.argv[1]
im = Image.open(path).convert("RGB")
bg = Image.new("RGB", im.size, (255, 255, 255))
box = ImageChops.difference(im, bg).getbbox()
if box:
    pad = 32                                   # 16pt at 2x
    left, top, right, bottom = box
    im = im.crop((0, 0, im.width, min(im.height, bottom + pad)))
im.save(path, optimize=True)
print("docs/example.png", im.size[0], "x", im.size[1])
PY
