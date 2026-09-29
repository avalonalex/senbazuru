#!/bin/sh
# Second batch: tag the U edges too (the 30 degree wing-root hinge in the spread shapes).
Y=$(cd "$(dirname "$0")" && pwd); cd "$Y"
P=../X3-crane-opening/venv/bin/python
S=spread/crane-spreading
run() { echo "=== $*"; /usr/bin/time -p $P smooth_test.py "$@" 2>&1; }
run curved-U $S/curved.fold 2 4 s0 MVFBU
run curved-s1-U $S/curved.fold 2 4 s1 MVFBU
run fine-U $S/fine.fold 2 4 s0 MVFBU
echo finished
