#!/bin/sh
# usage: batch.sh JOBFILE PARALLEL
cd "$(dirname "$0")"
PY=../X2-inflation/venv/bin/python
cat "$1" | xargs -P "$2" -L 1 sh -c 'n="$0-$1-kb$2-L$3"; /usr/bin/time -p '"$PY"' src/sweep.py "$0" "$1" "$2" "$3" > logs/$n.log 2>&1'
