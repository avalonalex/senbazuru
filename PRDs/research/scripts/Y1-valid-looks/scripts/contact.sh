#!/bin/sh
# Contact sheets for Y1 (ImageMagick montage).
Y=$(cd "$(dirname "$0")/.." && pwd); cd "$Y"
FONT=/System/Library/Fonts/Helvetica.ttc
M="montage -font $FONT -pointsize 17 -background white"
S=study-png; R=renders; C=composite; L=svg
$M \
 -label "rigid wing 30 deg (valid, 392 tri): study comparison.svg" $S/study-rigid-oblique.png -label "Cycles paper, oblique" $R/rigid-oblique-paper.png -label "paper + Line Art (red = intersections)" $C/rigid-oblique-paper-lineart.png -label "Cycles paper, upright" $R/rigid-upright-paper.png -label "Line Art SVG, upright" $L/rigid-upright-lineart.png \
 -label "curved wing 50 deg grip (valid, 392 tri): study" $S/study-curved-oblique.png -label "Cycles paper, oblique" $R/curved-oblique-paper.png -label "paper + Line Art" $C/curved-oblique-paper-lineart.png -label "Cycles paper, upright" $R/curved-upright-paper.png -label "Line Art SVG, upright" $L/curved-upright-lineart.png \
 -label "curved wing, fine (valid, 1192 tri): study refinement.svg" $S/study-fine-oblique.png -label "Cycles paper, oblique" $R/fine-oblique-paper.png -label "paper + Line Art" $C/fine-oblique-paper-lineart.png -label "Cycles paper, upright" $R/fine-upright-paper.png -label "Line Art SVG, upright" $L/fine-upright-lineart.png \
 -label "X3 IPC tip grips s=0.5 (torn, stitched)" $S/none-x3.png -label "Cycles paper, oblique (no Solidify)" $R/x3tip05-oblique-paper.png -label "paper + Line Art" $C/x3tip05-oblique-paper-lineart.png -label "Cycles paper, upright" $R/x3tip05-upright-paper.png -label "Line Art SVG, upright" $L/x3tip05-upright-lineart.png \
 -label "#394 body specimen: senbazuru render --view iso" $S/body-iso.png -label "Cycles paper, same iso direction" $R/body-iso-paper.png -label "paper + Line Art, oblique (close-up)" $C/body-oblique-paper-lineart.png -label "Cycles paper, upright (close-up)" $R/body-upright-paper.png -label "Line Art SVG, upright (close-up)" $L/body-upright-lineart.png \
 -label "before, closed crane (valid control): gallery oblique" $S/before-oblique-colours-trim.png -label "Cycles paper, oblique" $R/before-oblique-paper.png -label "paper + Line Art" $C/before-oblique-paper-lineart.png -label "Cycles paper, upright" $R/before-upright-paper.png -label "Line Art SVG, upright" $L/before-upright-lineart.png \
 -label "spread-0 More tucked sketch (invalid): gallery oblique" $S/spread-0-oblique-colours-trim.png -label "Cycles paper, oblique" $R/spread0-oblique-paper.png -label "paper + Line Art" $C/spread0-oblique-paper-lineart.png -label "Cycles paper, upright" $R/spread0-upright-paper.png -label "Line Art SVG, upright" $L/spread0-upright-lineart.png \
 -tile 5x7 -geometry 480x400+5+5 PNG24:contact-sheet.png
