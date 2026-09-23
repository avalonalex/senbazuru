# Run independent material tests on several CPUs

The [#330 CI run](https://github.com/avalonalex/senbazuru/actions/runs/35813111052)
spent 19m36s in its build/test job: 1m36s setting up the toolchain, 3m31s
compiling and 14m23s in `stack test`. Hspec itself reported 840.9406 seconds
for 1,800 examples. The dependency cache hit. The latest body-direction
gallery was not running there; older material regressions account for most
of the test time. This is the bounded scheduling experiment for
[#208](https://github.com/avalonalex/senbazuru/issues/208).

Approximate group times from that run's log put `CraneRoot` at 159 seconds,
`FoldRelaxation` at 141, `CraneSpread` at 98, `WingBending` at 85 and
`CraneInternal` at 80. Log timestamps bracket output rather than measure CPU
cost; Hspec's `--print-slow-items=20` now records individual example times
in CI so we can find the next bottleneck without relying on those gaps.

[Hspec's parallel execution](https://hspec.github.io/parallel-spec-execution.html)
needs two settings: `parallel` marks an example as safe to overlap,
and the threaded Haskell runtime lets workers execute on different CPUs.
`--jobs=4` bounds concurrent parallelizable examples; `+RTS -N4 -RTS` supplies
four runtime capabilities (the number of CPUs Haskell can use at once). Merely linking with
`-threaded`, or merely passing `--jobs`, does not make a CPU-bound serial test
suite run on four CPUs.

Nine measured material spec modules opt in, plus the independent `beforeAll`
solve groups in `WingBendingSpec`. Each example has its own solver state.
Shared fixtures are immutable values, prepared once by Hspec's `beforeAll`;
no worker mutates a shared mesh. The wing golden stays outside those groups.
File-writing tests and other golden comparisons remain serial. New spec modules
stay serial unless explicitly marked. A test added inside a parallel group
must preserve that independence, or move outside it.

The same examples, mesh sizes, iteration budgets and acceptance checks still
run on every PR. CI still builds project sources cold and caches only Stack's
dependencies. Ordinary local `stack test` keeps one worker. The worker cap is
explicit even on a machine with more CPUs; extra simultaneous solves consume
more memory.

On 2026-09-22, the compiled baseline at `4abb4ad` and this change ran on the
same Apple M4 Pro (12 CPUs, 24 GiB memory), both with QuickCheck seed 208 (the
number that fixes generated test inputs). `/usr/bin/time -l` measured each
executable directly from the repository root, with no concurrent build:

| Measurement | Original serial executable | Four workers |
| --- | ---: | ---: |
| Hspec elapsed time | 406.4003 s | 160.6356 s |
| Whole process elapsed time | 417.26 s | 170.77 s |
| User + system CPU time | 415.48 s | 475.88 s |
| Maximum resident memory | 485.6 MiB | 864.5 MiB |
| Examples / failures | 1,800 / 0 | 1,800 / 0 |

The suite's elapsed time fell 60.5%; total CPU time rose 14.5%, and peak memory
rose 78%. Concurrency saves waiting time by using CPUs that were idle, while
adding scheduling and runtime overhead. The example and property output was
identical. Removing only the annotations and their comments also reproduced
the original test sources byte for byte. Formatting, HLint 3.10, the JavaScript
checks and a cold warning-free build passed.

Individual parallel timings include time waiting for shared setup and CPU
resources: the wing export example can appear slow while waiting for the same
`beforeAll` solve as its neighboring material assertion. Do not add these
overlapping times and call the sum a CPU profile. Further CPU reductions,
such as sharing repeated crane preparation, remain separate work.

To compare serial and parallel execution on the current tree, build once and
run the complete suite with the same seed:

```bash
stack build --test --no-run-tests
stack test --test-arguments="--seed=208 --jobs=1 --print-slow-items=20 +RTS -N1 -RTS"
stack test --test-arguments="--seed=208 --jobs=4 --print-slow-items=20 +RTS -N4 -RTS"
```

Compare Hspec's elapsed times, keeping other CPU-heavy work stopped. Compare
CI runs separately: different GitHub hosts and compiler setup costs mean a
local test speedup is not automatically the same end-to-end CI speedup.
