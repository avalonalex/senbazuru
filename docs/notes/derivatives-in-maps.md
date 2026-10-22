# A derivative kept in a map costs most of the crane solve

Terms are in [the glossary](../glossary.md). The [quick tier](quick-tier.md)
settles the crane's wing at nine base angles. Each settle is a Gauss-Newton
solve: at every step it measures how far each pair of paper layers is from
crossing, takes the derivative of those gaps with respect to every vertex,
and solves one linear system
([snap-edges-along-a-clip-line](snap-edges-along-a-clip-line.md) describes the
step). On 2026-10-22 the quick tier's solve was profiled, to see where its time
goes, with the code of [#614](https://github.com/avalonalex/senbazuru/pull/614),
whose only change to the solve is the clip's band. Most of the time is not the
linear algebra. One profiled run, with a cost centre on every top-level
function:

| Where the time goes | Time | Allocation |
| --- | ---: | ---: |
| Measuring the gaps: clipping one triangle's shadow by another's, 7.0 million times | 63% | 80% |
| …of which multiplying and subtracting the derivative type, `D` | 33% | 58% |
| Factorising the linear system (`factorNormal`) | 9% | 7% |
| Solving it by conjugate gradients | 0.8% | 1% |
| Checking the final shape's contact, which runs twice | 9.5% | 4.6% |
| Everything else, mostly building the refined mesh (9.5%) | about 18% | about 7% |

The check runs twice because `rootAccepted` checks contact as part of
accepting the shape, and the quick tier then calls `spreadCheck` again for its
report: 4.7% and 4.8% of the time.

Without the profiler, three runs of the same program took 104.5, 104.0 and
101.7 CPU seconds, 22% of each in garbage collection. Each allocated 553 GB in
total, the same to the byte, while never holding more than 152 MB at once: the
solve makes a vast number of short-lived objects, not a large heap. The whole
quick tier, which also draws its page, took 113.4 and 113.6 CPU seconds, and
129.8 while other work shared the machine.

## Why a map

The gap at a clipped corner is computed from the coordinates of six vertices,
the two triangles' corners. Its derivative is the 18 numbers that say how the gap
moves with each of their coordinates. `SurfaceContact` carries them along
with the value in a small forward-mode type:

```haskell
data D = D {value :: !Double, derivative :: !(IM.IntMap V3)}

D a da * D b db = D (a * b) (IM.unionWith (^+^) (IM.map (b *^) da) (IM.map (a *^) db))
```

The derivative is a map from vertex id to a three-vector. That reads like
vector arithmetic, and it is correct, but each `*` builds two new maps from
`IM.map` and a third from `IM.unionWith`: dozens of heap objects to multiply
two numbers. The clip does dozens of these per triangle pair, and the solve
clips 7 million pairs. That is where most of the allocation comes from, 58% of
it in the profile. The arithmetic underneath is a few dozen multiplications and
additions, on numbers that could sit side by side in memory.

Nothing in the source shows the cost. In a language with explicit heap
allocation the maps would be visible where they are built; here the only way
to see them is to measure. The repair is a representation, not a language:
give each contact pair's six vertices fixed slots, and keep the derivative as
18 unboxed `Double`s
([#615](https://github.com/avalonalex/senbazuru/issues/615)).

## Measuring it again

The profile needs a profiled build of the library, in its own work directory so
the ordinary build is left alone, and a small program that runs the solve:

```bash
stack --work-dir .stack-work-profile build --profile senbazuru:lib
```

```haskell
module Main (main) where

import CraneRoot (RootControl (..), craneRootAt, rootAccepted, rootSpread)
import CraneSpread (spreadCheck)
import CraneWing (wingRoot)
import FoldRelaxation (Settings (..))
import RigidBase (BaseSearch (..), searchNear, spreadSolve, startingTurn)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (keyFrame)
import System.Exit (die)

-- The quick tier's solve and checks, without the page that draws them.
main :: IO ()
main = do
  file <- loadFoldFile "examples/crane.fold" >>= either (die . show) pure
  let source = keyFrame file
  hinge <- either (die . show) pure (wingRoot source)
  study <- either (die . show) pure (craneRootAt hinge source 3 FlatRoot)
  centre <- either (die . show) pure (startingTurn study)
  (found, _) <- either (die . show) pure (searchNear (spreadSolve (Settings 40 1e-5)) centre study)
  accepted <- either (die . show) pure (rootAccepted (baseStudy found) (baseResult found) (baseMesh found))
  contact <- either (die . show) pure (spreadCheck (rootSpread (baseStudy found)) (baseMesh found))
  -- Compared with itself only so that the whole check is run.
  print (baseDegrees found, accepted, contact == contact)
```

```bash
stack --work-dir .stack-work-profile --profile exec -- ghc -O2 -prof -fprof-auto-top -rtsopts \
  -XGHC2021 -XOverloadedStrings -XDerivingStrategies -XLambdaCase -XRecordWildCards \
  -istudy/fold-material -odir /tmp/solve-prof -hidir /tmp/solve-prof SolveProf.hs -o /tmp/solve-prof/run
/tmp/solve-prof/run +RTS -p -RTS
```

Profile this program, not `writeCraneQuick` itself. That pulls in
`CraneSpreadGallery`, and compiling that module with `-prof` on an Apple-silicon
Mac fails in the assembler with `fixup value out of range`: its code is too
long for a conditional branch to reach. That happens at `-O2` and `-O1`, and
with cost centres on every binding or only on top-level ones. The solve's own
modules compile. The unprofiled figures come from the same program built
without `--profile`, `-prof` and `-fprof-auto-top`, and run with `+RTS -s`.
