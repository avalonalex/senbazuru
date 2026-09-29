#!/bin/sh
# Smoothing-safety runs: zero-thickness (s0) and layer-separated (s1) meshes.
Y=$(cd "$(dirname "$0")" && pwd); cd "$Y"
P=../X3-crane-opening/venv/bin/python
G=../../gallery/whole-crane; S=spread/crane-spreading
run() { echo "=== $*"; /usr/bin/time -p $P smooth_test.py "$@" 2>&1; }
run before $G/before.fold 2 4 s0
run curved $S/curved.fold 2 4 s0
run before-s1 $G/before.fold 2 4 s1
run curved-s1 $S/curved.fold 2 4 s1
echo finished
