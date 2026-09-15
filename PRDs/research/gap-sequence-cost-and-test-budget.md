# Gap 3.5 — Sequence cost and test budget

Researched 2026-09-14 against `568dcb6` (branch `docs/prds-sequence-language`).
The repository was not modified. All builds and runs happened in two `git clone`s
outside the repository (one pristine clone, and one that adds a scratch driver `bench/Bench.hs`, kept as
[`scripts/SequenceBench.hs`](scripts/SequenceBench.hs),
and one executable stanza), so no build lock was shared with other agents.

Machine: Apple M1 Max, 10 cores, Stack 3.11.1, stack-managed GHC 9.6.7. **The
machine was not quiet.** The load average stayed between 7.4 and 10.7 on 10
cores throughout, from other agents and apps. Every number below carries its run
count and the load it was measured under. CPU (`user`) time is reported next to
wall time because it is less sensitive to contention.

**The measurement is incomplete, and this file says exactly where.** Task (a)
finished for `BlintzSequenceSpec` (5 runs) and `HelmetSequenceSpec` (3 runs).
The timing script was still running `CraneWingSpec` and `CheckedBirdSpec`, and
then the `stack test --match` runs, when this report was due. Task (b) was not
run: the driver and cabal stanza were written, but the plain and profiled
builds were never started. So no per-stage or cost-centre numbers exist for
`checkFlap` on the crane. Task (c) is therefore a method plus a code-derived
work count, not a measurement. Task (d) is complete, because it is design
work checked against code.

## Summary

A test run's cost is dominated by work nobody can filter out. hspec's `runIO` runs while the spec tree is built, before `--match`. So
every filtered run pays the whole suite's fixture setup: **19.03, 19.59 and
20.95 s wall (15.91, 15.76, 16.92 s user) for 0 examples** (3 runs). hspec's
own "Finished in" line reports 0.0003 s or less for those runs.

`BlintzSequenceSpec` alone took 14.8–21.2 s wall and 14.6–15.7 s user over 5
runs, of which hspec timed 0.010–0.014 s. `HelmetSequenceSpec` took 14.9 s wall
and 14.6 s user over 3 runs, of which hspec timed 0.022–0.024 s. The
`--match NAME` method the brief proposed therefore **cannot** isolate one
fixture's cost. Its signal is buried under about 15 s of shared setup, and the
blintz and helmet recipes, with their five and three checked flaps, are too
small to see there.

From the code, one checked step calls `foldFrameWith` (and so
`withPlanarFaces`) about seven times, and runs `checkFlap`. `checkFlap` does an
all-pairs triangle contact check at both endpoints, plus an interval walk capped
at 4096 intervals.

The PRDs should:

- budget per step in counted work (intervals, re-folds), not seconds;
- build expensive fixtures in `beforeAll`, not `runIO`, so a slow tag actually
  skips them;
- compare FOLD topology, angles and orders exactly and coordinates within
  1e-12;
- pin SVG and GLB bytes as goldens, knowing which bytes trigonometry can move.

## Findings

### Measured

1. **A filtered test run still pays for every module's `runIO` setup.** I ran
   the compiled binary
   (`.stack-work/dist/aarch64-osx/ghc-9.6.7/build/senbazuru-test/senbazuru-test`)
   directly with `--match "/NoSuchSpecAnywhere/"`, 3 times, under load
   8.6–9.3. The results were 19.03 / 19.59 / 20.95 s wall, 15.91 / 15.76 /
   16.92 s user, 1.26–1.62 s sys and 45.8 MB max RSS. hspec printed "0
   examples" and "Finished in 0.0003 / 0.0001 / 0.0000 seconds".

   The work is fixture construction inside `runIO`. Fourteen spec files use
   it: `CheckedPetalSpec` 6 times, then `CheckedBirdSpec`, `BirdSequenceSpec`
   and `BasicBaseSpec` 4 each, and `HelmetSequenceSpec`, `CraneWingSpec`,
   `BlintzSequenceSpec` and others 3 each (`grep -c runIO`). The forcing is
   visible in the code: `moves <- runIO (right (buildBlintzSequence
   (keyFrame source)))` (`test/BlintzSequenceSpec.hs:31`) pattern-matches the
   `Either`, which runs every `prepareFlap … >>= checkFlap` in the recipe
   (`study/fold-material/BlintzSequence.hs:57-73`) before any `it` starts.
   `CraneWingSpec.hs:32` does the same with `buildCraneWing`, and
   `CheckedBirdSpec.hs:40` with `prepareBird`.

2. **`BlintzSequenceSpec`, 5 runs through the binary with
   `--match /BlintzSequence/`** (load at start 7.7, 7.9, 7.4, 10.5, 10.7):

   | Run | Wall (s) | User (s) | Sys (s) | hspec "Finished in" (s) |
   | --- | ---: | ---: | ---: | ---: |
   | 1 | 21.24 | 15.72 | 2.00 | 0.0141 |
   | 2 | 19.63 | 15.36 | 1.54 | 0.0121 |
   | 3 | 18.92 | 15.25 | 1.26 | 0.0096 |
   | 4 | 14.81 | 14.59 | 0.12 | 0.0098 |
   | 5 | 14.88 | 14.60 | 0.16 | 0.0099 |

   Every run reported 11 examples and 0 failures. `--print-slow-items` on
   run 1 named the golden page as the slowest item at 6 ms (`:125`), the
   round-trip at 2 ms (`:117`), and a per-move sample at 1 ms.

3. **`HelmetSequenceSpec`, 3 runs** (load at start 9.5, 8.7, 7.4): 14.87 /
   14.92 / 14.89 s wall, 14.61 / 14.63 / 14.60 s user, and hspec 0.0243 /
   0.0222 / 0.0238 s, with 18 examples and 0 failures. Runs 4–5 had not
   finished when this was written.

   Note that the user time is **not** above the zero-match baseline (14.6 s
   against 15.8–16.9 s), although both include the helmet setup. The
   difference between the batches is contention noise larger than the helmet
   fixture. Contention was even visible in sys time, 1.3–2.0 s under heavier
   I/O against 0.12–0.18 s later.

4. **`CraneWingSpec`, `CheckedBirdSpec` and the `stack test --match` runs:
   not measured.** The script ([`scripts/time-specs.sh`](scripts/time-specs.sh)) was still running; the addendum at the end records what it later measured. See Unverified.

5. **A cold build of the pristine clone** (`stack build --test
   --no-run-tests`, 1 run, load 8.3–10.2) took 222.59 s wall, 164.25 s user
   and 25.51 s sys. For comparison, #208's table gives CI a 1m13s–2m00s
   compile step on `ubuntu-latest` (`gh issue view 208`); that was a
   different machine and cache state.

### From reading the code (counts, not timings)

6. **One checked step folds the whole pattern about seven times.**
   `foldFrameWith` starts with `withPlanarFaces` (`Origami/Folding.hs:351`).
   A frame that records faces skips the cutting (`Fold/Crossings.hs:128`), but
   it is still read, oriented and walked. Per step:

   - `prepareFlapAlong` folds once itself (`Origami/Flap.hs:175`), then calls
     `surfaceAt` at progress 1 and 0.5 (`:237-238`).
   - Every `surfaceAt` folds again (`:345`).
   - `checkFlap` calls `checkEndpointOrder` at 0 and 1 (`:277`), and each of
     those calls `surfaceAt` (`:305`).
   - The recipe's `flapAt motion 1` is one more (`:292`).
   - The join check is one more (`BlintzSequence.hs:64`).

   That totals **7 `foldFrameWith` per step** (1 + 2 + 2 + 1 + 1), plus one
   `refineSurface` (`Flap.hs:219`). A step that adds a crease also pays
   `creaseAllAlong`, which re-cuts and re-traces the pattern
   (`Fold/Creasing.hs:159`). The crane recipe also solves a layer order
   (`CraneWing.hs:78`), for which `Stacking.hs:180-183` claims "about 60ms" on
   the crane. That is the owner's figure, not re-measured here.

7. **`checkFlap` is quadratic in triangles before it subdivides anything.**
   Each endpoint (`HingeSweep.hs:248-253`) inspects **all** triangle pairs
   (`pairs`, `:261`) with `Panel.checkPanelContact` (`:435-441`). The interval
   walk (`:454-474`) only considers `movingPairs` (`:263`). For each interval,
   `separated` tries up to 5 + 9 + 3 + 3 = 20 candidate axes per pair (`:380`).
   The walk stops at `sweepBudget` intervals (`:455`), with depth 20 and budget
   4096 (`defaultSweepSettings`, `:94-95`).

   Before the sweep, `checkFlap` builds `contacts` and `resting` with nested
   list comprehensions over `triangleOwners` squared. Each candidate pair does
   a linear `find` over faces and a coplanarity test (`Flap.hs:253-269`), so
   that part is O(T²·F). On the crane the start has 76 faces after the new
   crease (`CraneWing.hs:66`) and 63 vertices (`CraneWingSpec.hs:39`). The
   triangle count was not printed, because the driver never ran.

8. **The interval count is already exposed and deterministic.** `SweepCheck`
   carries `sweepIntervals` (`HingeSweep.hs:100`), and the galleries report it
   (`CraneGallery.hs:24`, `BlintzGallery.hs:25`). Unlike seconds, it is the same
   on every machine, given identical floating-point bits. That is the same
   argument `Stacking.hs:150-156` makes for counting guesses rather than timing.

9. **The repo already has a pattern for fixtures that are skipped when
   filtered.** `beforeAll load` wraps the heavy crane-material specs:
   `CraneRootSpec.hs:23`, `CraneSpreadSpec.hs:24`, `CraneBodySpec.hs:23`,
   `CranePocketSpec.hs:22`, `CraneInternalSpec.hs:23`, and `WingBendingSpec.hs:54,65`.
   hspec runs a `beforeAll` action only when an item under it runs. That is why
   those specs (#208's 164.87 s `CraneRoot` group) add nothing to the
   zero-match baseline in finding 1, while the rigid-sequence specs do.
   hspec 2.11.12 is pinned (`lts-22.44.cabal.config:1528`); the binary's
   `--help` lists `--match`, `--skip`, `--times` and `--print-slow-items`.

10. **CI runs one undifferentiated `stack test`** (`.github/workflows/ci.yml`:
    `stack build --test --no-run-tests`, then `stack test`). #208 records
    10m48s for the test step and "626.2452 seconds for 1,387 examples". There
    is no tag mechanism today; hspec has none built in, only `--skip PATTERN`.

11. **`CheckedBirdSpec` does not exercise the rigid interpreter.**
    `CheckedBird` imports neither `Flap` nor `HingeSweep`. It certifies stages
    with exact `PetalCertificate` checks (`certifyCollapse`,
    `certifySecondPetal`, `certifyPress` at `CheckedBird.hs:64-66`). Its cost
    says nothing about a `Flap`-based sequence and should not be used to
    budget one.

### Platform-sensitive bytes (for task d)

12. **Trigonometry.** Rotations come from `cos theta` and `sin theta` in
    Rodrigues' formula (`Geometry/Rigid.hs:119-129`), and every folded
    position goes through them. The repo records that the same trigonometry
    differs between macOS and Linux in the last few bits
    (`test/BirdSequenceSpec.hs:43-45`). The checked-in fixture shows the
    residue: `examples/bird-base-sequence.fold` frame 0 contains
    `-6.123233995736766E-17`, which is cos(π/2) in double precision (`jq`).

    Two notes record discrete consequences. `docs/notes/closed-path-starts.md`
    describes a Linux-only SVG golden failure, where clipping returned a
    different first corner. `docs/notes/checking-numerical-corrections.md:66-73`
    describes a solver that converges on Linux CI and not on macOS.

13. **The SVG number format.** `formatNumber` writes 3 decimals with
    `showFFloat (Just 3)`, strips trailing zeros and maps `-0` to `0`
    (`Render/Svg.hs:332-345`). It is a pure function of the bits, so a
    platform difference reaches the SVG only if it moves a coordinate across a
    0.0005 rounding boundary.

    The larger risk is discrete. Clipping can change which polygon corner comes
    first, and `closedPathData` now normalises that by taking the smallest
    rotation of the *formatted* strings (`Svg.hs:281-294`). Formatting happens
    before the comparison, so sub-print noise cannot choose the start.

14. **GLB positions.** Positions are rounded to `quantumFor span = 1e-6 *
    span` through an `Integer`, then narrowed to `Float` (`Render/Gltf.hs:261-264`,
    `311-314`). Only a coordinate within float noise of a half-quantum boundary
    can flip. `canonicalPiece` picks each clipped piece's first corner by
    packed position (`:386-399`); two corners that pack equal keep input
    order, so a tie is still order-sensitive. Material weights are rounded at
    1e-10 (`:402-406`).

15. **GLB JSON numbers that are *not* rounded.** The JSON chunk embeds
    `extras.senbazuru.frame` (`Gltf.hs:236-243`), and some of its numbers go
    out raw:

    - `storedFrame` replaces `vertices_coords` with packed points, but keeps
      `edges_foldAngle` as it is. It also keeps `senbazuru:material_coords`,
      `source_panels` and `source_edges` from `frameExtras` (`:241-242`).
    - `layerRequirements` writes its `direction` vector raw (`:236`), and
      `transformSurface` rotates that vector with the rigid motion
      (`Origami/Surface.hs` `transformSurface`), so it can carry trig bits.
    - Material coordinates are exact source numbers for the blintz, helmet and
      bird. They are **trig-derived** wherever a crease was mapped back through
      `applyRigid (inverse placement)`, as in `CraneWing.hs:99-100`.

    So an exact GLB golden of a creased-through-layers step can differ across
    platforms in its JSON chunk even when every packed position agrees.

16. **FOLD output.** `encodeFoldFile` is aeson `encode` plus a newline
    (`Fold/Load.hs:182-183`). Doubles go through `toJSON` (a `Scientific`),
    which drops negative zero (`Fold/Types.hs:585-596`). Given identical bits
    the text is deterministic, so every coordinate is platform-sensitive, and
    so is any angle or material coordinate computed with trig. Angles a flap
    step writes are `angle + progress * travel` (`Flap.hs:343`). That is basic
    IEEE arithmetic on the author's numbers, so it is identical across
    platforms, whereas petal-stage angles (`birdHinges`) involve trig.

17. **The reference comparison to follow** (`test/BirdSequenceSpec.hs:39-51`)
    clears `verticesCoords` (`withoutCoordinates`, `:84-92`) and compares the
    rest exactly. Coordinates must agree in count and within an absolute
    `1e-12`. It then checks `eitherDecode (encode file) == Right file`. It does
    **not** relax `frameExtras`, which is safe for the bird because nothing in
    it is trig-derived (finding 15).

18. **Plumbing that exists today.**
    - `goldenText` and `goldenBytes` write `.actual.svg` / `.actual.glb` next
      to the golden and report the first differing line or byte
      (`test/Test/Golden.hs:38-125`). `.gitignore` excludes those files.
    - GLB goldens are made by folding a fixture, then `renderGlb defaultBudget
      VisiblePaper` (`test/Senbazuru/Render/GltfSpec.hs:70-77`, `644-658`).
    - `stepPage` has signature `Theme -> Budget -> Grid -> View -> Bool ->
      [Frame]` (`Render/Steps.hs:90-100`). With arrows on, it calls
      `motionsBetween`, which refuses a pair whose `edges_vertices` or
      `faces_vertices` differ (`Origami/Step.hs:88-96`).
    - The CLI's `--steps` refuses `--frame`, `--fold` and `--stacking`
      (`app/Senbazuru/Cli.hs:843-851`).
    - No test invokes the CLI (a grep of `test/` finds no `Senbazuru.Cli`,
      `readProcess` or `callProcess`). `Senbazuru.Cli` is in `app/`, outside
      the test suite's `hs-source-dirs`.

## Implications for the design

**Budgets: count work, then attach a time only as a CI guard.**

- **Per step,** the runner should return a cost record with each checked step:
  - `sweepIntervals`, against the 4096 budget;
  - the number of re-folds;
  - the triangle count, and the pair count at the endpoints.

  A PRD can then set a deterministic per-step budget, and a step that reaches
  it must fail the way `SweepUnresolved` already does (`HingeSweep.hs:455`).
  The runner must not quietly raise the budget. `Stacking`'s counted-guesses
  argument applies unchanged.
- **Per sequence,** the budget is the sum of step records plus an explicit
  crease-and-stacking entry for each step that adds a crease (finding 6).
- **Wall-clock budgets are proposals only until measured.** A reasonable
  starting guard: a 20-step crane-sized sequence must stay within the
  zero-match setup cost measured here (about 15–20 s of wall on this M1 Max
  under load). Adopt it only once the unfinished measurements (Unverified 1–3)
  show a single crane step is well below 1 s. If a crane `checkFlap` turns out
  to cost seconds, the PRD should reduce redundant re-folds before adding
  budget. Finding 6 shows a step folding the same start twice, once in
  `prepareFlapAlong` and again at progress 0 in `checkEndpointOrder`.

**Test placement.**

- **Default CI** gets one small end-to-end sequence and the negative controls:
  blintz- or helmet-sized, 5 steps, text → run → FOLD/SVG/GLB. The
  blintz/helmet recipes' item cost is milliseconds (findings 2–3), so the
  whole cost is the fixture build.
- **Crane-sized sequences (72+ faces) go behind a slow tag:** a
  `describe "slow"` group run by a separate CI job, with `--skip /slow/` on the
  default job. This is only real if their fixtures live in `beforeAll`, not
  `runIO`: finding 1 shows a skipped `runIO` still costs its full setup.
  The PRD should also say whether the existing
  `BlintzSequenceSpec`/`HelmetSequenceSpec`/`CraneWingSpec` fixtures move to
  `beforeAll` when they become sequence texts. #208's "retain representative
  accepted and rejected material cases on every PR" constrains the split.
- **Keep `CheckedBirdSpec` out of the rigid-interpreter budget discussion**
  (finding 11).
- **PRD 2 should put the parser in the library** (e.g. `Senbazuru.Sequence.Parse`)
  so the acceptance test runs without spawning the CLI, which no test does
  today (finding 18). A CLI smoke test of `--steps`/`export` on the written
  FOLD can then stay thin.

**The end-to-end acceptance test (task d).** One fixture pair: `examples/<name>.seq`
(sequence text) and `examples/<name>-sequence.fold` (checked-in expected
output), plus `test/golden/<name>-steps.svg` and `test/golden/<name>-final.glb`.
Assertions, each with the change that turns it red:

| # | Assertion | Change that turns it red |
| --- | --- | --- |
| E1 | Parsing the text gives an exact AST; `parse (pretty ast) == Right ast` | Parser drops a sign on travel; pretty-printer writes `90` for `-90`; a keyword renamed on one side only |
| E2 | Running gives the expected step count, every `sweepOutcome == SweepClear`, and each step's `sweepIntervals` equals a recorded count | Hinge `side` resolved to the other face; `defaultSweepSettings` budget lowered below the recorded count; a change to `separated` altering how many intervals are needed |
| E3 | Join: each accepted endpoint refolds within `1e-12 * modelSpan` (`BlintzSequence.hs:69`) | Runner feeds folded coordinates back as the material pattern (the pitfall named at `BlintzSequence.hs:10-12`); face orders taken from `foldedPattern` instead of the accepted frame |
| E4 | FOLD: `withoutCoordinates expected == withoutCoordinates actual` exactly (topology, `edges_foldAngle`, `faceOrders`, titles, classes, attributes, file metadata) | `Folding.reorient` removed (#78's sign bug); `creaseAllAlong` renumbering edges; a step title changed in the text; `frame_inherit` written as `false` |
| E5 | FOLD coordinates: same counts, each within absolute `1e-12` on a unit sheet (`BirdSequenceSpec.hs:47-50`); for steps that crease through layers, `senbazuru:material_coords` compared the same way rather than exactly (finding 15) | Anchoring changed to a different first face (whole model moves); a rotation sign flipped (mirror model) |
| E6 | `eitherDecode (encode file) == Right file` | A new field written but not read back; negative zero reintroduced by encoding through `toEncoding` (`Types.hs:585-596`) |
| E7 | SVG golden: `stepPage` over the file's frames, then `renderSvg`, byte-exact against the golden | Theme stroke width; camera basis choice; arrows toggled; `formatNumber` decimals; a crease drawn in an earlier frame (backfill) |
| E8 | GLB golden, `renderSurfaceGlb VisiblePaper` on the final state, byte-exact | `toGltfAxes` changed to `(x, z, y)`; `quantumFor` changed; colour conversion changed; face orders not stored in extras |
| E9 | Cross-writer check: the frame decoded from the GLB's `extras.senbazuru.frame` equals the FOLD's last frame, exactly in topology and orders and within one quantum in positions | GLB export drops or reorders `faceOrders`; the FOLD writer and GLB writer diverge on which state is "final" |
| E10 | Negative control: the same text with one travel sign reversed is refused with `FlapEndpointOrder`, and the error names the step's source line | Runner catching `Left` and continuing; parser discarding source positions |

For platform stability:

- Keep E7 and E8 exact, following the owner's practice of fixing the
  serialisation rather than loosening a golden (`closed-path-starts.md`).
- Choose the default-CI fixture so no step creases through layers, which keeps
  finding 15's raw trig numbers out of the GLB JSON.
- If a Linux-only golden difference appears, first diff the frame decoded from
  E9 to see whether it is a position quantum, a raw JSON number, or a discrete
  clipping choice.

**Avoid:**

- timing tests in hspec items, whose times exclude `runIO` (findings 1–2);
- a slow tag whose fixtures are built in `runIO`;
- exact comparison of trig-derived numbers anywhere, FOLD or GLB JSON;
- budgets written in seconds inside library code.

## Open questions

1. Should the sequence runner cache one `foldFrameWith` result per state
   instead of re-folding? `Flap.prepareFlapAlong` deliberately rebuilds the
   start from angles (`Flap.hs:169-181`), so caching needs the library to
   accept a trusted value. Does that weaken the `FlapStartMismatch` guarantee?
2. Should per-step budgets live in the sequence text (author-visible), in the
   runner's defaults, or only in tests?
3. Which existing recipe becomes the default-CI acceptance fixture, blintz or
   helmet? The crane is the natural slow one, but it creases through layers.
   That triggers finding 15's GLB JSON sensitivity, unless material
   coordinates are rounded like `packedWeight`.
4. Should `extras.senbazuru.frame`'s raw doubles (angles, material coordinates,
   layer directions) be rounded at export the way material weights are
   (`Gltf.hs:402-406`)? That would change existing goldens, against the
   keep-default-output rule, so it would need its own issue.
5. Does moving `BlintzSequenceSpec`/`HelmetSequenceSpec`/`CraneWingSpec`/`CheckedBirdSpec`
   fixtures from `runIO` to `beforeAll` belong to #208 or to the sequence PRDs?

## Unverified

1. **Per-spec timings for `CraneWingSpec` (5 runs), `CheckedBirdSpec` (5
   runs), `HelmetSequenceSpec` runs 4–5, and all `stack test --test-arguments
   '--match /NAME/'` runs (3 each).** The script was still running. Its logs
   appear in the addendum below for the binary runs; the `stack test` runs never started.
   [`scripts/time-specs.sh`](scripts/time-specs.sh) reproduces them.
2. **Task (b), the profile of one crane `checkFlap`.** Not built or run. The
   driver is [`scripts/SequenceBench.hs`](scripts/SequenceBench.hs) (never built). It times each
   stage separately:

   - `withPlanarFaces` with faces recorded and dropped, and `foldFrameWith`;
   - `creaseAllAlong` and `solveStackingAs [2]`;
   - the refused −90° step;
   - a 20-step open/close sequence, with `prepareFlapAlong`, `checkFlap`,
     `flapAt 1`, the join re-fold and the join compare timed per step, and
     `sweepIntervals` printed;
   - render (`stepPage`+`renderSvg`, `renderSurfaceGlb`);
   - `preparePetal`, `prepareBird`, `buildCaseSequence`.

   It forces each value through `show` and subtracts a second `show`; `Main`
   is at `-O0` so the demand analyser cannot evaluate a timed argument early.
   The intended commands, from that clone, are:

   - `stack build senbazuru:exe:senbazuru-bench`, then `stack exec senbazuru-bench -- 10 +RTS -s`, 5 runs;
   - `stack build --profile --work-dir .stack-work-prof senbazuru:exe:senbazuru-bench`, then run it `+RTS -p`.

   Whether the 20-step open/close sequence is accepted at all is unknown: the
   closing step lands flat on the other wing and needs endpoint orders.
3. **Task (c), the 20-step crane estimate.** There is no measured number. The
   per-step work count (finding 6) is derived from code. The crane's triangle
   count and interval counts were not printed.
4. **That GHC's `sin`/`cos` on `Double` call the platform C maths library, and
   so differ between macOS and glibc.** I did not read GHC's primop
   implementation, and did not run on Linux, because pulling a Docker image
   was not authorised. The repo's own evidence (finding 12) is the owner's
   observation, not a controlled comparison.
5. **Whether `hasRelief` (which sets the `2D`/`3D` frame attribute,
   `Folding.hs:387`) uses a tolerance.** Not checked. If it compares z against
   exactly 0, it would make E4's exact attribute comparison platform-sensitive.
6. **The crane stacking figure of "about 60ms"** (`Stacking.hs:180-183`) is
   the repository's claim, not re-measured.
7. **Whether hspec runs `beforeAll` lazily only when an item underneath is
   selected.** This is inferred from the 0-example baseline together with the
   crane-material specs using `beforeAll`, not from hspec's documentation or a
   controlled run.

## Addendum — runs that finished after this note was written

The timing script kept running after the note above was submitted. Its logs
(same binary, same `--match /NAME/` method, same machine) add the following.
The method caveat from finding 1 still applies: each figure includes the
~15 s of `runIO` setup that every filtered run pays, so only the difference
from the zero-match baseline says anything about one fixture.

| Spec | Runs | Wall (s) | User (s) | Load after run (1-min) |
| --- | ---: | --- | --- | --- |
| `CraneWingSpec` | 5 | 16.00–16.14 | 15.74–15.80 | 5.6–6.8 |
| `CheckedBirdSpec` | 4 complete (a fifth was cut off) | 27.36–27.50 | 26.81–26.85 | 5.5–6.2 |
| `HelmetSequenceSpec` runs 4–5 | 2 | 14.86, 15.00 | 14.60, 14.65 | 6.2–6.6 |

hspec's own "Finished in" line, which excludes the shared `runIO` setup,
reports **1.21–1.25 s** for `CraneWingSpec` (5 runs) and **12.50–12.52 s** for
`CheckedBirdSpec` (the 3 runs whose logs kept that line). Against the
zero-match baseline (15.76–16.92 s user, measured under heavier load),
`CraneWingSpec`'s total user time is not distinguishable from the baseline,
and `CheckedBirdSpec` adds roughly 10–11 s. So the crane wing's items take
about a second on top of a fixture build that the shared setup already
paid for. `CheckedBird` uses exact
certificates, not `Flap`/`HingeSweep` (finding 11), so that cost says nothing
about a rigid sequence runner. The per-stage crane profile (task b) was still
not run, and the `stack test --match` runs never started.
