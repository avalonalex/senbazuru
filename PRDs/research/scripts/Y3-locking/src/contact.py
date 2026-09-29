"""Stack the experiment figures into one contact sheet."""
import sys
from PIL import Image, ImageDraw, ImageFont
IMG = sys.argv[1]
names = sys.argv[2:]
W = 2400
tiles = []
for n in names:
    im = Image.open(f"{IMG}/{n}").convert("RGB")
    h = int(im.height * W / im.width)
    tiles.append(im.resize((W, h), Image.LANCZOS))
H = sum(t.height for t in tiles) + 40 * len(tiles)
sheet = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(sheet)
y = 0
for n, t in zip(names, tiles):
    d.text((10, y + 10), n, fill="black")
    y += 40
    sheet.paste(t, (0, y))
    y += t.height
sheet.save(f"{IMG}/../contact-sheet.png")
print(sheet.size)
