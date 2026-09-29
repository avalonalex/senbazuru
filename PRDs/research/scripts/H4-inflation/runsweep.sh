#!/bin/bash
cd "$(dirname "$0")"
PY=/Applications/Blender.app/Contents/Resources/4.4/python/bin/python3.11
for r in 4 16 64 256 1024 4096; do $PY sweep.py 8 $r > sweep_r$r.txt 2>&1 & done
wait
