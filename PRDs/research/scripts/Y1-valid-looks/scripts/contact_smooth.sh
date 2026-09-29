#!/bin/sh
# Smoothing contact sheet (ImageMagick montage).
Y=$(cd "$(dirname "$0")/.." && pwd); cd "$Y"
FONT=/System/Library/Fonts/Helvetica.ttc
montage -font $FONT -pointsize 17 -background white \
 -label "curved spread, layers 1.1t apart (S1), unsmoothed" renders/curved-upright-paper.png \
 -label "same, Catmull-Clark L2, crease 1.0 on M/V/F/B + walls" renders/curved-cc-upright-paper.png \
 -label "CC: new crossing sub-triangle pairs (red)" diff/curved-s1-cc-upright-cross.png \
 -label "Phong a=0.75: new crossing pairs (red)" diff/curved-s1-phong-upright-cross.png \
 -label "head crop: unsmoothed | CC (black slots)" crops/cmp-curved-upright-head.png \
 -label "closed crane body crop, oblique: unsmoothed | CC" crops/cmp-before-oblique-body.png \
 -label "closed crane S1, CC: new crossing pairs" diff/before-s1-cc-upright-cross.png \
 -label "Line Art on CC-smoothed curved spread" svg/curved-cc-upright-lineart.png \
 -tile 4x2 -geometry 600x500+5+5 PNG24:smoothing-sheet.png
