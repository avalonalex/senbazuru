#!/bin/bash
# usage: ./run.sh NAME [gen.py options...]   -> runs/NAME.{inp,dat,frd}, logs/NAME.log, runs/NAME.result.json
set -u
cd "$(dirname "$0")"
PY=../X2-inflation/venv/bin/python
name=$1; shift
$PY gen.py "$name" "$@" > /dev/null || exit 1
cd runs
start=$(python3 -c 'import time;print(time.time())')
OMP_NUM_THREADS=${NT:-4} CCX_NPROC_EQUATION_SOLVER=${NT:-4} ../env/bin/ccx -i "$name" > "../logs/$name.log" 2>&1
rc=$?
end=$(python3 -c 'import time;print(time.time())')
cd ..
wall=$(python3 -c "print(round($end-$start,2))")
echo "{\"name\":\"$name\",\"rc\":$rc,\"wall_s\":$wall}" > "runs/$name.wall.json"
$PY post.py "$name" > /dev/null 2>&1
echo "$name rc=$rc wall=${wall}s $(cat runs/$name.result.json 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print("t=%.3f V=%.4f thick=%.4f comp5=%.2f maxdih=%.1f res=%s"%(d["step_time_reached"],d["V"],d["thickness"],d["area_frac_compressed_5pct"],d["max_dihedral_deg"],d["z_residual_vs_5x5_mean"]))' 2>/dev/null)"
