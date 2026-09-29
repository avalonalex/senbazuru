"""Contact sheet: columns = states, rows = gallery views.

python sheet.py OUT.png 'name1|label1;name2|label2;...' upright,head,below
Images are render/<name>-<view>.png. Labels may contain \\n.
"""
import sys
from PIL import Image, ImageDraw, ImageFont
from crane import EXP

out = sys.argv[1]
cols = [c.split('|') for c in sys.argv[2].split(';')]
views = sys.argv[3].split(',')
s = 0.4
ims = {}
for name, _ in cols:
    for v in views:
        im = Image.open(f'{EXP}/render/{name}-{v}.png').convert('RGB')
        ims[(name, v)] = im.resize((int(im.width * s), int(im.height * s)))
w, h = next(iter(ims.values())).size
top, left = 64, 64
S = Image.new('RGB', (left + w * len(cols), top + h * len(views)), 'white')
dr = ImageDraw.Draw(S)
try:
    font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 13)
except Exception:
    font = ImageFont.load_default()
for i, (name, label) in enumerate(cols):
    for j, v in enumerate(views):
        S.paste(ims[(name, v)], (left + i * w, top + j * h))
    for k, ln in enumerate(label.split('\\n')):
        dr.text((left + i * w + 4, 3 + 15 * k), ln, fill='black', font=font)
for j, v in enumerate(views):
    dr.text((4, top + j * h + h // 2), v, fill='black', font=font)
S.save(out)
print(S.size)
