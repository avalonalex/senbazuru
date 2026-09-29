#!/bin/sh
# Render every Y1 configuration once (paper renders, then Line Art SVGs).
# Skips a configuration whose log already holds its STATS line (rerun-safe).
Y=$(cd "$(dirname "$0")/.." && pwd)
B=/Applications/Blender.app/Contents/MacOS/Blender
cd "$Y"
for c in configs/*-paper.json configs/*-lineart.json configs/*-lineart-overlay.json; do
  n=$(basename "$c" .json)
  [ -n "$ONLY" ] && case "$n" in $ONLY) ;; *) continue ;; esac
  grep -q '^STATS' "logs/$n.log" 2>/dev/null && continue
  /usr/bin/time -p $B -b --factory-startup --python scripts/render_y1.py -- "$c" > "logs/$n.log" 2>&1 || echo "FAILED $n"
  echo "$n $(grep -o '"render_seconds": [0-9.]*' logs/$n.log) $(grep '^real' logs/$n.log)"
done
