#!/bin/sh
# Render every configuration once, then repeat two paper renders twice more for timing.
X=$(cd "$(dirname "$0")/.." && pwd)
B=/Applications/Blender.app/Contents/MacOS/Blender
cd "$X"
for c in configs/*-[123]*.json; do
  n=$(basename "$c" .json)
  $B -b --factory-startup --python scripts/render.py -- "$c" > "logs/$n.log" 2>&1 || echo "FAILED $n"
  echo "$n $(grep -o '"render_seconds": [0-9.]*' logs/$n.log)"
done
for run in 2 3; do
  for n in spread0-2-paper before-2-paper twist-2-paper; do
    $B -b --factory-startup --python scripts/render.py -- configs/$n.json > logs/$n-run$run.log 2>&1
    echo "$n run$run $(grep -o '"render_seconds": [0-9.]*' logs/$n-run$run.log)"
  done
done
