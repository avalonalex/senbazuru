#!/bin/bash
# Repeat one deck 3x single-threaded, time each (wall, user, sys), and compare the .dat outputs byte for byte.
# usage: ./repeat.sh NAME   (runs/NAME.inp must exist)
cd "$(dirname "$0")/runs"
n=$1
for i in 1 2 3; do
  cp $n.inp rep-$n-$i.inp
  /usr/bin/time -p env OMP_NUM_THREADS=1 CCX_NPROC_EQUATION_SOLVER=1 ../env/bin/ccx -i rep-$n-$i > ../logs/rep-$n-$i.log 2> ../logs/rep-$n-$i.time
  echo "run $i: $(tr '\n' ' ' < ../logs/rep-$n-$i.time) increments=$(grep -c 'increment size=' ../logs/rep-$n-$i.log) finished=$(grep -c 'Job finished' ../logs/rep-$n-$i.log)"
done
cmp rep-$n-1.dat rep-$n-2.dat && cmp rep-$n-1.dat rep-$n-3.dat && echo "all three .dat files byte-identical"
