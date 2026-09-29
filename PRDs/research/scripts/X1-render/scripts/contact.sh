#!/bin/sh
# Contact sheets from the renders (ImageMagick montage).
X=$(cd "$(dirname "$0")/.." && pwd)
cd "$X"
FONT=/System/Library/Fonts/Helvetica.ttc
M="montage -font $FONT -pointsize 20 -background white"
# Main sheet: rows = models, columns = today / baseline / paper / paper+lines
$M \
  -label "flat crane (valid, 72 faces): today, render --fold (top view)" ref/crane-flat-today.png \
  -label "1 baseline: viewer-style flat facets" renders/craneflat-1-baseline.png \
  -label "2 paper (Cycles, 0.1 mm)" renders/craneflat-2-paper.png \
  -label "3 paper + Freestyle lines" renders/craneflat-3-lines.png \
  -label "square twist (valid rigid 3D): today, --view iso" ref/twist-iso-today.png \
  -label "1 baseline" renders/twist-1-baseline.png \
  -label "2 paper" renders/twist-2-paper.png \
  -label "3 paper + lines" renders/twist-3-lines.png \
  -label "closed crane, 448 tri (valid): today, gallery SVG" ref/before-today.png \
  -label "1 baseline" renders/before-1-baseline.png \
  -label "2 paper" renders/before-2-paper.png \
  -label "3 paper + lines" renders/before-3-lines.png \
  -label "More tucked sketch (invalid): today, book SVG" ref/spread0-today.png \
  -label "1 baseline" renders/spread0-1-baseline.png \
  -label "2 paper" renders/spread0-2-paper.png \
  -label "3 paper + lines" renders/spread0-3-lines.png \
  -tile 4x4 -geometry 600x500+6+6 PNG24:contact-sheet.png
# Variants: thickness and normals, on valid closed crane and invalid sketch
$M \
  -label "closed crane: no thickness" renders/before-2b-paper-nothick.png \
  -label "0.1 mm (6.7e-4 side)" renders/before-2-paper.png \
  -label "0.4 mm (2.7e-3 side)" renders/before-2c-paper-thick04.png \
  -label "0.1 mm, flat triangle normals" renders/before-2d-paper-flatnormals.png \
  -label "sketch: no thickness" renders/spread0-2b-paper-nothick.png \
  -label "0.1 mm" renders/spread0-2-paper.png \
  -label "0.4 mm" renders/spread0-2c-paper-thick04.png \
  -label "0.1 mm, flat triangle normals" renders/spread0-2d-paper-flatnormals.png \
  -tile 4x2 -geometry 600x500+6+6 PNG24:variants-sheet.png
# Line drawings: today's book drawing vs Line Art SVG vs Line Art with intersections
for n in spread0-lineart spread0-lineart-intersections spread0-lineart-intersections-nobridge before-lineart-intersections-nobridge; do rsvg-convert -w 1200 svg/$n.svg -o svg/$n.png; done
$M \
  -label "today: book drawing (full)" ref/spread0-today.png \
  -label "today: two-sided colours" ref/spread0-colours-today.png \
  -label "Line Art SVG: contour + creases" svg/spread0-lineart.png \
  -label "Line Art SVG + mesh intersections" svg/spread0-lineart-intersections-nobridge.png \
  -tile 4x1 -geometry 600x500+6+6 PNG24:lines-sheet.png
# Close-ups of the body (same crop in every image): thickness and normals
for n in spread0-2b-paper-nothick spread0-2-paper spread0-2c-paper-thick04 spread0-2d-paper-flatnormals spread0-1-baseline spread0-3-lines; do
  magick renders/$n.png -crop 560x420+330+480 +repage crops/$n-body.png
  magick renders/$n.png -crop 420x420+560+260 +repage crops/$n-wing.png
done
$M \
  -label "body: no thickness" crops/spread0-2b-paper-nothick-body.png \
  -label "body: 0.1 mm" crops/spread0-2-paper-body.png \
  -label "body: 0.4 mm" crops/spread0-2c-paper-thick04-body.png \
  -label "body: 0.1 mm, flat normals" crops/spread0-2d-paper-flatnormals-body.png \
  -label "body: baseline" crops/spread0-1-baseline-body.png \
  -label "body: paper + lines" crops/spread0-3-lines-body.png \
  -tile 3x2 -geometry 560x420+6+6 PNG24:crops-sheet.png
