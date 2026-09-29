#!/bin/zsh
cd /private/tmp/claude-501/-Users-yuhanhao-Project-senbazuru/a9814e9f-3bd8-46c3-897f-77c8e8d977fa/scratchpad/experiments/X2-inflation
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1
cat jobs2.txt | xargs -P 3 -L 1 zsh -c 'venv/bin/python run.py $0 $1 $2 $3 $4 > logs/$0-$2-r$1-ks$3-kb$4.log 2>&1'
echo ALLDONE
