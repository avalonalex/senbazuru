#!/bin/sh
# Repeat one full 25-step sweep (spread-0, 3D pull, fixed bending 1e-3, 448 triangles) three times, one after another.
cd "$(dirname "$0")"
for k in 1 2 3; do
  /usr/bin/time -p ../X2-inflation/venv/bin/python src/sweep.py spread-0 all3d 1e-3 0 -timing$k > logs/timing$k.log 2>&1
  echo "run $k: $(grep real logs/timing$k.log) $(grep user logs/timing$k.log) load $(uptime | sed 's/.*averages: //')"
done
