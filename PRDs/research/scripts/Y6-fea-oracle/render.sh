#!/bin/bash
# usage: ./render.sh NAME [key=value ...]  -> img/NAME.png  (uses X2's bl_render.py unchanged)
cd "$(dirname "$0")"
n=$1; shift
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python ../X2-inflation/bl_render.py -- runs/$n.npz img/$n.png "$@" > logs/render-$n.log 2>&1
grep RENDERED logs/render-$n.log
