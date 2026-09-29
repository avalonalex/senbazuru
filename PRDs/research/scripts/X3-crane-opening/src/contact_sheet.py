"""Compose the contact sheet from Blender renders (rotated 180 deg so the
wings point up, as in the study's book drawings)."""
import sys
from PIL import Image, ImageDraw, ImageFont
from crane import EXP

cols = sys.argv[1].split(',')        # obj basenames
labels = sys.argv[2].split('|')
views = sys.argv[3].split(',')
out = sys.argv[4]
s = 0.42
ims = {}
for c in cols:
    for v in views:
        im = Image.open(f'{EXP}/render/{c}-{v}.png').convert('RGB').rotate(180)
        ims[(c, v)] = im.resize((int(im.width * s), int(im.height * s)))
w, h = next(iter(ims.values())).size
top = 46; left = 70
S = Image.new('RGB', (left + w * len(cols), top + h * len(views)), 'white')
dr = ImageDraw.Draw(S)
try:
    font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 15)
except Exception:
    font = ImageFont.load_default()
for i, c in enumerate(cols):
    for j, v in enumerate(views):
        S.paste(ims[(c, v)], (left + i * w, top + j * h))
    lines = labels[i].split('\\n')
    for k, ln in enumerate(lines):
        dr.text((left + i * w + 6, 4 + 18 * k), ln, fill='black', font=font)
for j, v in enumerate(views):
    dr.text((4, top + j * h + h // 2), v, fill='black', font=font)
S.save(out)
print(S.size)
