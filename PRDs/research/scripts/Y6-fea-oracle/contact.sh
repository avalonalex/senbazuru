#!/bin/bash
# Build contact-sheet.png from the renders and figures (ImageMagick montage).
cd "$(dirname "$0")"
X2=../X2-inflation/img
tiles=()
add() { [ -f "$1" ] && tiles+=(-label "$2" "$1"); }
add img/s4-n32-iso-static.png "S4 shell, kb=1e-3, static, 32x32\nV=0.108 (plain isotropic)"
add img/s4-n48-iso-dyn.png "S4 shell, kb=1e-3, damped dynamics\n+ imperfection, 48x48: V=0.111"
add img/s4-n64-kb1e-3-dyn.png "S4 shell, kb=1e-3, dynamics,\n64x64: V=0.114 (still a slab)"
add img/s4-n48-kb1e-2-dyn.png "S4 shell, kb=1e-2, dynamics,\n48x48: V=0.078"
add img/s4-n64-kb1e-4-dyn.png "S4 shell, kb=1e-4, dynamics, 64x64,\nseed 0: V=0.184 (breaks out, folds)"
add img/s4-n64-kb1e-4-dyn-high.png "same, seen from 40 degrees"
add img/s4-n64-kb1e-4-dyn-seed1.png "S4 shell, kb=1e-4, 64x64, seed 1:\nV=0.184, different shape"
add img/m3d4-n32-iso-dyn.png "M3D4 membrane, isotropic,\n32x32: V=0.145 (mesh-scale folds)"
add img/m3d4-n32-tension-dyn.png "M3D4 membrane, TENSION ONLY,\n32x32: V=0.2023"
add img/m3d4-n48-tension-dyn.png "M3D4 membrane, TENSION ONLY,\n48x48: V=0.2021"
add $X2/own-teabag-r24-tf-kb1e-4.png "X2 own tension-field solver,\nkb=1e-4 (reference): V=0.1995"
add $X2/bl-teabag-r24-tf.png "X2 Blender cloth, compression 0.1\n(reference): V=0.203"
KB4V=$(python3 -c "import json;print('%.3f'%json.load(open('runs/s4-n64-kb1e-4-dyn.result.json'))['V'])" 2>/dev/null || echo "n/a")
for i in "${!tiles[@]}"; do tiles[$i]="${tiles[$i]//KB4V/$KB4V}"; done
montage -font /System/Library/Fonts/Supplemental/Arial.ttf "${tiles[@]}" -tile 4x -geometry 420x315+6+6 -pointsize 15 -background white img/_renders.png
magick img/profiles.png -resize 1260x img/_prof.png
magick img/maps.png -resize 1260x img/_maps.png
magick img/stack.png -resize 1260x img/_stack.png
magick -size 1728x60 xc:white -font /System/Library/Fonts/Supplemental/Arial.ttf -pointsize 24 -gravity center -annotate +0+0 \
  "Y6: square tea bag in CalculiX 2.23 (unit side, p = 1, ks = 1e3), against X2 references" img/_title.png
magick img/_title.png img/_renders.png \( img/_prof.png img/_maps.png -gravity center -background white -append \) \
  img/_stack.png -gravity center -background white -append +repage -depth 8 contact-sheet.png
rm -f img/_*.png
echo wrote contact-sheet.png
