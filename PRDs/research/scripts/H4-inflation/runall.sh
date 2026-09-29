#!/bin/bash
PY=/Applications/Blender.app/Contents/Resources/4.4/python/bin/python3.11
cd "$(dirname "$0")"
run() { $PY pillow.py "$1" "$2" "$3" > "res_$1_$2_$3.json" 2> "err_$1_$2_$3.txt"; }
run disc 12 tfield &
run square 8 tfield &
run square 16 tfield &
run square 12 tfield &
run square 12 sym &
run square 12 edge1 &
wait
