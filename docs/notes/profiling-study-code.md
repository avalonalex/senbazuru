# Profile study code through a small program

AGENTS.md says to measure performance with `stack build --profile` and
`+RTS -p`. For the material study that fails on an Apple-silicon Mac:
compiling `CraneSpreadGallery` with `-prof` stops in the assembler with
`fixup value out of range`, because the module's code grows too long for a
conditional branch to reach its target. On 2026-10-22 it failed at `-O2` and
`-O1`, with cost centres on every binding (`-fprof-auto`) and on top-level
functions only (`-fprof-auto-top`). The modules a settle needs compile. So
profile a small program that imports only those, against a profiled build of
the library alone. A *cost centre* is a label the profiler charges time and
allocation to; `stack build --profile` gives the library one on every binding.

This program is the quick tier's settles and checks
([crane-solve-profile](crane-solve-profile.md)), copied from
`writeCraneQuick` without the page it draws, since `CraneQuick` imports
`CraneSpreadGallery`. In `craneRootAt hinge source 3 FlatRoot` the `3` is the
mesh's refinement level, and `Settings 40 1e-5` allows 40 iterations per
penalty stage with a length tolerance of 1e-5. If `writeCraneQuick` changes,
copy it again. Save it as `/tmp/solve-prof/SolveProf.hs`:

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
  contact <- either (die . show) pure (spreadCheck (rootSpread (baseStudy found)) (baseMesh found))
  accepted <- either (die . show) pure (rootAccepted (baseStudy found) (baseResult found) (baseMesh found) contact)
  -- Compared with itself only so that the whole check is run.
  print (baseDegrees found, accepted, contact == contact)
```

From the repository root, which the program's `examples/crane.fold` and the
`-istudy/fold-material` below both assume, build the profiled library in a work
directory of its own, so the ordinary build is left alone, then the program
against it, and run it:

```bash
stack --work-dir .stack-work-profile build --profile senbazuru:lib
stack --work-dir .stack-work-profile --profile exec -- ghc -O1 -prof -fprof-auto-top -rtsopts \
  -XGHC2021 -XOverloadedStrings -XDerivingStrategies -XLambdaCase -XRecordWildCards \
  -istudy/fold-material -odir /tmp/solve-prof/prof -hidir /tmp/solve-prof/prof \
  /tmp/solve-prof/SolveProf.hs -o /tmp/solve-prof/profiled
/tmp/solve-prof/profiled +RTS -p -po/tmp/solve-prof/solve -RTS
```

The report is `/tmp/solve-prof/solve.prof`. The `-X` flags are the cabal file's
language and default extensions; copy them again if those change. `-O1` is the
level `stack run` builds the study at, since the cabal file sets none.

The unprofiled figures come from the ordinary build. `.stack-work-profile` has
only the profiled library, so leave out `--work-dir` as well as the profiling
flags, and read the totals from `+RTS -s`:

```bash
stack build senbazuru:lib
stack exec -- ghc -O1 -rtsopts \
  -XGHC2021 -XOverloadedStrings -XDerivingStrategies -XLambdaCase -XRecordWildCards \
  -istudy/fold-material -odir /tmp/solve-prof/plain -hidir /tmp/solve-prof/plain \
  /tmp/solve-prof/SolveProf.hs -o /tmp/solve-prof/plain-run
/tmp/solve-prof/plain-run +RTS -s -RTS
```

To try a change to one module without editing the checkout, put the changed
copy in a directory of its own and name that directory first, as in
`-i/tmp/solve-prof/variant -istudy/fold-material`, with an `-odir` of its own.
GHC takes the first module of each name it finds.

[internal-crease-diagnostic](internal-crease-diagnostic.md) profiled another
crane solve the same way, with cost centres on every binding and the ordinary
work directory.
