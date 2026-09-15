#!/bin/zsh
# Time four spec modules, five runs each, through the compiled test binary,
# then three runs each through `stack test --test-arguments '--match ...'`.
# Full logs go to $LOGS (default /tmp/senbazuru-spec-timings); the summary goes to stdout.
# Research script for PRDs/research/gap-sequence-cost-and-test-budget.md. Run from a
# checkout whose test binary is already built (stack build --test --no-run-tests).
cd "$(git rev-parse --show-toplevel)" || exit 1
L=${LOGS:-/tmp/senbazuru-spec-timings}
mkdir -p $L
B=.stack-work/dist/aarch64-osx/ghc-9.6.7/build/senbazuru-test/senbazuru-test
for name in BlintzSequence HelmetSequence CraneWing CheckedBird; do
  for i in 1 2 3 4 5; do
    log=$L/bin-$name-$i.log
    echo "load-before $(uptime | sed 's/.*averages: //')" > $log
    /usr/bin/time -p $B --match "/$name/" --print-slow-items=20 >> $log 2>&1
    echo "load-after $(uptime | sed 's/.*averages: //')" >> $log
    echo "binary $name run $i: $(grep -E '^Finished' $log) | $(grep -E 'examples,' $log) | $(grep -E '^(real|user|sys)' $log | tr '\n' ' ') | $(grep load-before $log)"
  done
done
for name in BlintzSequence HelmetSequence CraneWing CheckedBird; do
  for i in 1 2 3; do
    log=$L/stack-$name-$i.log
    echo "load-before $(uptime | sed 's/.*averages: //')" > $log
    /usr/bin/time -p stack test --test-arguments "--match /$name/" >> $log 2>&1
    echo "stack test $name run $i: $(grep -E '^Finished' $log) | $(grep -E 'examples,' $log) | $(grep -E '^(real|user|sys)' $log | tr '\n' ' ') | $(grep load-before $log)"
  done
done
echo "done $(date) $(uptime | sed 's/.*averages: //')"
