#!/bin/sh
# usage: batch2.sh JOBFILE PARALLEL   (lines: MODEL VARIANT KB LEVELS TAG)
cd "$(dirname "$0")"
cat "$1" | xargs -P "$2" -L 1 sh -c 'n="$0-$1-kb$2-L$3$4"; /usr/bin/time -p ../X2-inflation/venv/bin/python src/sweep.py "$0" "$1" "$2" "$3" "$4" > logs/$n.log 2>&1'
