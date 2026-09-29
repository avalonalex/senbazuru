#!/bin/sh
# Third batch: before-s1 again (walls tagged sharp), U-tagged variants, fine mesh.
Y=$(cd "$(dirname "$0")" && pwd); cd "$Y"
while pgrep -f run_smooth.sh > /dev/null; do sleep 5; done
P=../X3-crane-opening/venv/bin/python
G=../../gallery/whole-crane; S=spread/crane-spreading
run() { echo "=== $*"; /usr/bin/time -p $P smooth_test.py "$@" 2>&1; }
run before-s1 $G/before.fold 2 4 s1
run curved-U $S/curved.fold 2 4 s0 MVFBU
run curved-s1-U $S/curved.fold 2 4 s1 MVFBU
run fine $S/fine.fold 2 4 s0
run fine-U $S/fine.fold 2 4 s0 MVFBU
echo finished
