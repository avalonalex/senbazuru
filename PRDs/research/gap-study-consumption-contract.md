# Gap: the study's consumption contract — what a sequence run hands the material study, and how existing recipes migrate

Follow-up slice for critic gap 3.6 (`Z-critic.md`). Read-only: nothing in the
repository was modified, built or run. Line numbers are against
the repository at `568dcb6` (branch
`docs/prds-sequence-language`). GitHub facts come from `gh api` and `gh issue
view`; web pages were read through a summarising fetch and are cited by URL.
This file extends A2 (recipe styles and handoff invariants), B (mechanics and
the proposed `settle`), E2 (reference vocabulary) and G (rendering ladder). It
does not repeat them.

## Summary

The study already consumes more than a `Surface V2`. `CraneSpread`, the only
rigid-to-material path, takes a *move*: its start `Folded`, its opaque
`CheckedFlap`, hinge ids, moving faces and a rigid pose at a chosen progress.
It derives rest angles from assignments and picks holds by a start-pose
coordinate band. So `settle :: SettleSpec -> Surface V2` is too narrow. PRD 3 needs a per-step record defined in
the library, which the study imports. Route evidence in that record should be
the evidence value itself, not a Boolean. Holds should be named by what the move
already provides: the stationary side, the moving side, bands measured from the
hinge in the start pose, the panels across the hinge, and crease lines named by
material segment. None of these is an id. Certificates can attach after the run,
through a study-side registry keyed by macro name *and* fixture fingerprint.
Blintz and helmet become sequences first. Crane wing, bird, frog and most of
`cases.json` stay as fixtures until named library work lands. Driving external
solvers out of process is outside AGENTS.md's vendoring rules. Codim-IPC's
default build links GPL code, and ipc-toolkit is a library, not a solver.

## Findings

### (a) What the study takes from a move today

**1. The one rigid-to-material path consumes a move, not a surface.**
`craneSpreadWith` (`study/fold-material/CraneSpread.hs:80-115`) uses five
things from `CraneWing`'s move:

- the start state: `surfaceFromFolded (craneStart wing)` (`:85`);
- a rigid pose at progress 30/90: `flapAt (craneOpening wing) (30 / 90)` (`:86`);
- the moving faces: `flapMovingFaces (craneOpening wing)` (`:88`);
- the hinge edge ids: `craneHinge wing` (`:91`, `:97`);
- the start state's accepted `faceOrders` (`:108-114`).

`CraneWing` carries exactly these fields: `craneStart`, `craneHinge`,
`craneSide`, `craneOpening :: CheckedFlap` and `craneRefusal`
(`CraneWing.hs:43-49`). A `Surface V2` has lost the hinge, the moving side and
the path, so B's `settle` signature cannot be the whole interface.

**2. The library does not export the stationary side of a checked flap.**
`FlapMotion` has `movingFaces`, `stationaryFace` and `creaseTravels` fields
(`src/Senbazuru/Origami/Flap.hs:81-91`). The module exports only
`flapMovingFaces`, `flapCheck` and `flapAt` for a `CheckedFlap`
(`Flap.hs:49-59`, `:282-294`). A record that names the stationary seed
therefore needs either a new accessor or the runner to keep what it resolved.

**3. Two kinds of order reach the study, and they must not be merged.**

- *Coplanar FOLD orders.* `withFaceOrders` stores these. Directional
  requirements for open panels "remain separate", even for the same pair
  (`Surface.hs:257-263`).
- *Directional requirements* are `surfaceLayerRequirements :: Maybe (V3,
  [(FaceId, FaceId)])` (`Surface.hs:152`). `StudyCase` attaches them from
  named panels (`StudyCase.hs:125-127`).
- `CraneSpread` turns the first kind into lower/upper pairs along +z. It uses
  the sign of each relative face's normal (`CraneSpread.hs:108-114`). On
  export it re-signs every triangle order against the *upper* triangle's
  normal (`:185-207`).

Newcomer trap: a FOLD order is relative to one face's normal, not to world +z.
Paper that has turned over flips its meaning.

**4. Rest angles are derived from assignments, which breaks under a different
unbent-crease convention.**

- **The rule.** The hinge gets the reference pose's angle; every other
  non-border crease gets −π if `Mountain`, otherwise +π
  (`CraneSpread.hs:90-94`).
- **Why this is safe today.** `surfaceFeatures` lists a crease as active if it
  is B/M/V/U/C, or if its angle exceeds 1e-10 (`Surface.hs:278`). The
  bending builder demands an explicit rest angle for every active crease and
  never defaults one from `edges_foldAngle` (`FoldBending.hs:138-145`,
  `:177-182`). The crane has `F`=20 edges and no `edges_foldAngle` (`jq` on
  `examples/crane.fold`), so no flat guide is active.
- **Where it breaks.** Suppose a sequence writes an unbent crease as M/V at
  angle 0, which is A1's convention (b) and contradiction 3 in the critic.
  That crease is then active, and `CraneSpread.hs:92` would give it a rest
  angle of ±π: a spring pulling open paper shut.

**5. Hinges are found by assignment, which breaks the same way.**

- `CraneWing` recovers its hinge as "every `Unassigned` edge"
  (`CraneWing.hs:65-66`).
- `CraneRoot` finds the root edges by the same test
  (`CraneRoot.hs:60`).
- Neither survives a sequence that assigns the new crease M or V.

**6. The repository has four strengths of evidence about the motion between
states.** A single Boolean would erase the difference between them.

| Evidence | Where | What it establishes |
| --- | --- | --- |
| None: state only | `StudyCase` angle tables (`docs/architecture.md:421-422`); frog milestones "no motion is implied between checkpoints" (`BasicBases.hs:144`) | endpoints pass contact; nothing between |
| Interval sweep | `checkFlap` returns an opaque `CheckedFlap`; every pose is re-folded and compared with the checked hinge path (`Flap.hs:19-25`, `:249-280`) | the whole single-hinge turn, up to HingeSweep's conservative refusals |
| Exact ideal-path certificate | `PetalCertificate` bounds the ideal sheet; `CheckedBird` compares Double poses within 1e-12 (`PetalCertificate.hs:1-15`, `CheckedBird.hs:120-129`) | the ideal path of one fixture |
| Not a motion at all | a static boundary-value solve whose iterates "are allowed to stretch and cross paper" (`CraneSpread.hs:11-12`) | an endpoint only |

**7. Ids are valid only inside one pattern.** Folding keys transforms to the
*cut* pattern (`Folding.hs:286-301`). `CraneWing` re-selects ids after
creasing (`CraneWing.hs:11-12`, `:61-74`). `StudyCase` names panels by material
point so that renumbering "cannot silently change an order's meaning"
(`StudyCase.hs:117-118`). A crease-adding step's before and after states
therefore number the same paper differently.

**8. The dependency already runs one way, and a file cannot carry a record.**

- **Direction.** The study executable `build-depends` on `senbazuru`
  (`senbazuru.cabal:179-189`). "The library imports no study code"
  (`docs/architecture.md:201`, again `:405`). The study already calls library
  moves directly (`BlintzSequence.hs:27-30`, `CraneWing.hs:30-41`).
- **The existing handoff runs study → CLI**, through ordinary FOLD
  (`study/fold-material/Main.hs:141-151`; `docs/architecture.md:436-441`).
- **What a file loses.** `materialFrame` does not serialise thickness or
  directional requirements (`Surface.hs:242-247`). The GLB keeps only three
  `senbazuru:` extras keys (`Render/Gltf.hs:238-242`). A `CheckedFlap` is
  opaque and has no serialised form (`Flap.hs:19-20`).

### (b) How holds, grips and contact panels are chosen today

**9. `CraneSpread` chooses every hold with coordinate tests on its own
geometry.** All of the following are in `CraneSpread.hs:95-107`:

- **Refinement.** `WingOnly` refines the moving faces.
  `WingAndRootNeighbours` also refines every owner of a hinge segment
  (`:95-97`).
- **Body.** The vertices of triangles whose source panel is *not* moving
  (`:101`). This includes hinge vertices shared with the wing.
- **Selected.** The vertices of triangles whose source panel *is* moving
  (`:102`).
- **The band coordinate.** `fraction p = (0.25 − y) / 0.25`, where y is the
  sample's **start-pose world coordinate** (`:103`). It is not a material
  coordinate. The root is folded y = 1/4, and the wing runs towards
  decreasing y (`:117-119`).
- **Grip.** Selected vertices with `fraction ≥ 0.875 − 1e-8` (`:104`).
- **Held set.** Body, plus selected vertices with `fraction ≤ 0.125 + 1e-8`
  (the root strip), plus the grip (`:106`).
- **Targets.** Every selected, non-body vertex is moved by `bentPoint`
  (`:105`). That rotates the root strip rigidly by a hard-coded 30°. It
  places the grip at 30° plus the extra angle, at the end of a circular arc
  (`:120-134`). The grip's target is therefore a *curve rule*, not a rigid
  pose of the flap.

Why folded coordinates: the four wing faces lie "folded onto two layers",
and the hinge is "a bent chain on the OPEN sheet" (`CraneWing.hs:8-10`). One
straight strip in the folded wing is several unrelated regions of the sheet.

**10. `CraneRoot` builds four controls from those sets** (`CraneRoot.hs:56-78`):

- `roots` are the `Unassigned` edges and their owners. `nearby` is the owners
  minus the wing (`:60-63`); the test pins these as `FaceId`s `[7, 8, 27, 43]`
  (`test/CraneRootSpec.hs:34`).
- `distant` is every vertex of a triangle outside wing ∪ nearby (`:67`). The
  header states the rule: vertices of any *other* panel stay held even when a
  released panel shares them (`:52-55`).
- Holds: `HeldRoot` keeps every pin. The other controls keep only the grip
  plus body (`ReleasedRoot`, `WeakerRoot`, `FlatRoot`), or the grip plus
  distant (`FreeBody`) (`:68-69`).
- Springs on root edges: stiffness × 0.1 for `WeakerRoot`, rest 0 for
  `FlatRoot` and `FreeBody` (`:70-76`).
- The test also pins `length spreadOrders == 902` (`CraneRootSpec.hs:40`).

**11. The other crane fixtures add named creases by raw id.**

- **`CraneBody`.** It takes the two `CandidateOpening` creases of the
  `CranePocket` map that touch the root neighbours (`CraneBody.hs:66`,
  `:74`). The map's regions and roles are hand-made fixture data
  (`CranePocket.hs:1-13`, `:46-50`).
- **`CraneInternal`.** It hard-codes `EdgeId 26` and `51` (`CraneInternal.hs:55`).
  Its extra holds are the vertices of those creases' refined segments
  (`:62-64`). Tests pin 9 vertices per line, one of them already held, and
  exactly 16 added holds (`test/CraneInternalSpec.hs:30-31`, `:50`).

**12. The uncreased controls hold material regions; the two-layer control
copies by index.**

- `WingBending` holds `materialU ≤ 0.125` and `≥ 0.875` (`WingBending.hs:62-64`).
  Its header says the root and grip "occupy fixed material regions at every
  mesh resolution" (`:7`).
- `WingLayers` copies the pins onto the reflected layer through an index map
  (`WingLayers.hs:61-67`). It builds its own mesh, not a `Surface`, so it
  stays outside any sequence.

**13. Refinement already carries everything a region name needs.**

- `RefinedSurface` keeps `refinedPanels :: [FaceId]` per triangle and
  `refinedEdges :: [(EdgeId, (Int, Int))]` (`Surface.hs:103-104`).
- A midpoint sample averages the material coordinates of its endpoints
  (`Surface.hs:380`).
- A split segment keeps its source `EdgeId` (`Surface.hs:398`).

So ownership and material position survive any refinement level. Mesh vertex
ids, which `relaxPinnedHinges` keys on (`FoldRelaxation.hs:244-247`), do not.

**14. A seed mechanism already exists.** `PanelTag {tagName, tagAt :: V2}`
(`ContactSpec.hs:10`) resolves a material point strictly inside exactly one
material face, with tolerance 1e-10 (`StudyCase.hs:139-143`). `fixedPanel`
anchors the same way (`:161-172`).

**15. Contact panels are derived, not named.** Orders are transitively closed
*before* pairs with no free vertex are dropped (`CraneSpread.hs:141-150`). The
test proves the order matters: A below B and B below C must still produce A
below C (`CraneRootSpec.hs:59-61`). The independent check still uses every
source order (`CraneSpread.hs:165-168`).

### (c) Certificates

**16. A certificate is a study function bound to one fixture's indices.**

- **Signatures.** `certifyCollapse`, `certifyPetal`, `certifySecondPetal` and
  `certifyPress` all have type `Bool -> [(Int, Int)] -> Either Text
  PetalCertificate` (`PetalCertificate.hs:262-291`).
- **Fixed indices.** The order check hard-codes 16 panels (`:295`). The edge
  set spans vertices 0–12 (`:315`).
- **Binding guards.** `CheckedPetal` requires all of these
  (`CheckedPetal.hs:49-53`, `:62`):
  - the fixture's material vertices, within 1e-12;
  - the literal cut faces and a 28-pair edge list;
  - `fixedPanel == Just (0.58, 0.4)`.
- **Runtime input.** The orders fed to the three later certificates come from
  the first petal's accepted pose at 175° (`CheckedBird.hs:61-66`).
- **Pose comparison.** Every pose is compared with the ideal path within 1e-12
  (`CheckedBird.hs:126-127`, `:148-149`).
- **Progress.** A stage's progress is a fraction of 175° (`:83-87`).
- **Contact during the collapse.** Landing orders are stripped until the
  collapse lands (`:131-137`).
- **Hidden constructor.** The bird's constructor is hidden, so certificates
  cannot outlive their inputs (`:13-14`, `:51-53`).

**17. The CLI cannot reach certificates, and the study has one entry point.**
The study's `main` is a flag dispatch over galleries (`Main.hs:62-89`). The
`bird-petal` manifest case also feeds `CheckedBird`'s named contact panels
(`CheckedBird.hs:123`; `PetalGallery.hs:53-56`).

### (d) What guards each recipe

**18. The test suite compiles study modules by name, and seven specs read the
manifest.**

- **Compiling.** `hs-source-dirs: test, study/fold-material`
  (`senbazuru.cabal:193`), with recipe and gallery modules listed among the
  test's `other-modules` (`:215-256`).
- **Reading the manifest.** `cases.json` is read by `StudyCaseSpec:25`,
  `BaseCollapseSpec:30`, `RabbitEarSpec:40`, `PetalFoldSpec:38`,
  `CheckedPetalSpec:35`, `CheckedBirdSpec:37` and `BirdSequenceSpec:33`. It is
  also read by the study's `Main` (`:94`, `:147`) and `PetalGallery` (`:53`),
  and is listed in `extra-source-files` (`senbazuru.cabal:27`, `:50`).
- **Goldens** (grep of `goldenText`):

| Golden | Test |
| --- | --- |
| `checked-blintz.svg` | `BlintzSequenceSpec.hs:127` |
| `checked-helmet.svg` | `HelmetSequenceSpec.hs:187` |
| `checked-crane.svg` | `CraneWingSpec.hs:145` |
| `checked-bird-above.svg`, `checked-bird-below.svg` | `CheckedBirdSpec.hs:173` |
| `checked-petal.svg` | `CheckedPetalSpec.hs:138` |
| `bird-sequence-iso.svg`, `bird-sequence-bottom.svg` | `BirdSequenceSpec.hs:84` |
| `frog-sequence.svg` | `BasicBaseSpec.hs:220` |
| `bent-strip.svg` | `WingBendingSpec.hs:100` |

**19. Exact non-golden pins that a migration touches.**

- **Frog.**
  - The exported frame must equal the folded frame with its solved stacking,
    coordinates aside (`BasicBaseSpec.hs:199`).
  - Landmarks must sit at the origin and at (0, 1/√2, 0) (`:203-206`).
  - The completed milestone must expose the lifted petal from both sides
    (`:170-182`).
- **Bird sequence.** The regenerated file must equal
  `examples/bird-base-sequence.fold` exactly, apart from coordinates
  (`BirdSequenceSpec.hs:39-51`).
- **Crane spreading.** Each spec pins resolved `FaceId`s, `EdgeId`s and
  counts (findings 10-11). `CraneSpreadSpec` also requires exact held-position
  error 0 (`:34`) and exactly 4 moving panels (`:31`).
- **Flap recipes and certificates.** A2 F28-F31 lists the rest.

**20. Test time is already a constraint.** #208's body records 626 s of hspec
over 1,387 examples. Its log timestamps put `CraneRoot` at about 164.87 s and
`CraneSpread` at 97.48 s (`gh issue view 208`). A migration that runs an old
and a new crane solve side by side doubles the most expensive groups.

### (e) Licences for driving external solvers

**21. AGENTS.md's rule is written for material that enters the repository.**

- **The table and the rules.** "Third-party material" (`AGENTS.md:127-155`)
  says anything *vendored* must be MIT-compatible, with provenance in
  `examples/README.md`. GPL implementations are "research only, never
  vendored". The source table (`:140-147`) has a `Use` column covering
  vendoring, attribution and reading.
- **What it omits.** It does not mention running a program and reading its
  output files.
- **Related projects.** `docs/related-projects.md:22` lists Origami Simulator
  as MIT, and as what #53 will read. It has no row for IPC, ipc-toolkit or
  Codim-IPC.
- **#53's plan.** It is manual: export FOLD from the simulator, run
  `senbazuru info` on it, and note provenance if a file is kept
  (`gh issue view 53`, Approach steps 1-3).

**22. Origami Simulator — MIT, confirmed.**

- **Licence.** `gh api repos/amandaghassaei/OrigamiSimulator/license` reports
  SPDX `MIT`. The LICENSE header reads "Copyright (c) 2018 Amanda Ghassaei".
- **What it is.** The README
  (<https://github.com/amandaghassaei/OrigamiSimulator>, fetched) describes a
  WebGL browser app. It imports SVG and FOLD and exports FOLD, STL and OBJ.
  The README mentions no command-line or headless mode.
- **Its dependencies** (Three.js, numeric.js, earcut, cdt2d and others) keep
  their own licences.
- **Consequence.** "Driving it out of process" means a person exporting files,
  or browser automation. It does not mean a subprocess call.

**23. ipc-toolkit — MIT, confirmed, but it is a library, not a solver.**

- **Licence.** `gh api` reports SPDX `MIT`, with copyright "2020–2025 Zachary
  Ferguson".
- **What it is.** The README (<https://github.com/ipc-sim/ipc-toolkit>,
  fetched) describes a C++ library with Python bindings. Its purpose is to add
  contact handling to an existing simulation, and it states that it is not a
  full simulator. It points to PolyFEM or Rigid IPC for that. The authors ask
  for a citation.
- **Dependencies.** CMake fetches them; its `cmake/recipes` directory lists
  abseil, catch2, eigen, libigl, onetbb, spdlog, tight_inclusion and others
  (`gh api` directory listing). Their licences were not checked.
- **Consequence.** Using it out of process means writing and maintaining our
  own C++ or Python driver program. That is a toolchain decision more than a
  licence one.

**24. Codim-IPC — Apache-2.0, confirmed, but its default build links a GPL
module.**

- **Licence.** `gh api` reports SPDX `Apache-2.0`; the LICENSE file is the
  Apache License 2.0 text.
- **Build.** The README (<https://github.com/ipc-sim/Codim-IPC>, fetched)
  builds with Python scripts and CMake. Examples run through
  `Projects/FEMShell/batch.py`; the README specifies no mesh file interface.
- **The GPL link.**
  - The top-level `CMakeLists.txt` defaults `LINEAR_SOLVER` to `CHOLMOD`
    (line 9) and includes a `suitesparse` recipe in that case (lines 42-46,
    53-54).
  - `CMake/suitesparse.cmake` opens with a warning that the GPL
    `Cholmod/Supernodal` module is on by default and can be disabled
    (`WITH_GPL`, `WITH_SUPERNODAL` default `ON`) (fetched raw via `gh api`).
  - SuiteSparse's CHOLMOD licence file lists Supernodal, MatrixOps and Modify
    as GPL, and Check, Cholesky, Utility and Partition as LGPL
    (<https://raw.githubusercontent.com/DrTimothyAldenDavis/SuiteSparse/dev/CHOLMOD/Doc/License.txt>,
    fetched).
- **What Apache-2.0 itself says**
  (<https://www.apache.org/licenses/LICENSE-2.0>, fetched):
  - "Derivative Works" excludes works that remain separable from, or merely
    link or bind by name to, the Work.
  - Redistribution requires a copy of the licence, retained notices,
    change marking and NOTICE contents (section 4).

**25. G's implication 9 needs two corrections.** G says MIT and Apache-2.0
tools "can be driven" (G lines 632-636).

- ipc-toolkit cannot be driven as it stands: there is no program to drive
  (finding 23).
- A Codim-IPC binary built with its defaults is not Apache-2.0-only
  (finding 24).

This is the licence form of AGENTS.md's own warning that a repository
licence is not a design licence (`AGENTS.md:149-155`): a repository's licence
label is not the licence of the binary its default build produces.

## Implications for the design

### (a) The per-step record, and who imports what

Define the record **in the library** (an `Origami.*` module, since it knows
paper and not drawing; `docs/architecture.md:150-153`). The study imports the
library runner, as it already imports `Origami.Flap`. The study consumes the
**sequence source** (an EDSL value, or a file parsed by the library) and runs
it itself. It must never parse rendered FOLD or GLB back, because those drop
the evidence and the directional requirements (finding 8).

Sketch (names illustrative):

```haskell
data StepRecord = StepRecord
  { stepLabel      :: Text
  , stepPath       :: [Text]                -- enclosing macro names, outermost first
  , stepMove       :: MoveKind              -- Crease | Flap | Coupled MacroName | Checkpoint | Present
  , stepBefore     :: Surface V2            -- exactly what the move started from, orders included
  , stepAfter      :: Surface V2            -- accepted endpoint, in the anchor's frame
  , stepRoute      :: RouteEvidence
  , stepHinge      :: [(MaterialSegment, [EdgeId])]  -- seed, and ids resolved in stepBefore's numbering
  , stepMoving     :: [(MaterialPoint, [FaceId])]    -- one seed per moving component or macro role
  , stepStationary :: (MaterialPoint, FaceId)        -- the side the move held still (finding 2)
  , stepNewCreases :: [(MaterialSegment, Assignment)] -- for Crease steps: the bridge between numberings
  , stepAngles     :: ([Double], [Double])  -- before/after, each in its own state's edge numbering
  , stepOrders     :: [FaceOrder]           -- accepted coplanar orders of stepAfter
  , stepRequirements :: Maybe (V3, [(FaceId, FaceId)])  -- directional, kept separate (finding 3)
  , stepStacking   :: Maybe StackingChoice  -- the predicate or index that chose among valid stackings
  , stepAnchor     :: MaterialPoint
  , stepPresentation :: Rigid               -- turn-over etc., applied after checks (A1)
  }

data RouteEvidence
  = StateOnly                        -- checkpoints, angle tables
  | NoMotion                         -- a crease added at fixed positions
  | SweepChecked CheckedFlap         -- the opaque library value; gives flapAt
  | Sampled [Double] SampleReport    -- coupled macro checked at poses only
```

Why each choice:

- **Evidence, not a Boolean.**
  - `SweepChecked` carries the `CheckedFlap` itself. It is opaque, so only
    `checkFlap` can make one (`Flap.hs:19-20`). `CraneSpread` needs `flapAt`
    at 30/90 from it (finding 1).
  - A Boolean can be set by hand; it cannot give a pose.
  - `Certified` is deliberately missing from the library type (see (c)).
- **Seeds and resolved ids together.** The seeds survive re-cutting. The ids
  are what today's fixtures consume (`flapMovingFaces`, `craneHinge`). They
  hold only within the named state (finding 7).
- **Angles as data.** The study must take rest angles from `stepAngles` (or
  `flapAt p`), never from assignments. Remove the derivation at
  `CraneSpread.hs:90-94` and the `Unassigned` searches (findings 4-5).
- **The evidence gates nothing in a static settle.** B finding 6 shows a rigid
  state is already an equilibrium. A static solve needs `stepBefore`, the
  seeds and a stated difference (a released hold or a turned grip). It does
  not need a route. Keep `stepRoute` in the settle report so a render can say
  "state only".
- **A thinner study entry point.** Keep B's `settle` as the kernel, and add a
  study-side `settleStep :: SettleSpec -> StepRecord -> Either SettleError
  Settled` that resolves the holds in (b) against the record.
- **What a file-authored sequence needs.** It needs nothing extra: the study
  runs the same library runner on the parsed source. PRD 2's parser must
  therefore be library code, not CLI code in `app/`.

### (b) Hold, grip and contact names that survive refinement and re-cutting

Every name resolves against **one step's record**. A name resolves to a
**region**: a set of source panels, or a predicate on samples. That region
becomes mesh vertex ids only after refinement. Ownership comes from
`refinedPanels` and `refinedEdges` (finding 13). Position predicates run on
each refined sample's material coordinates, or on its position in the start
pose. No `FaceId`, `EdgeId` or mesh id appears in a name.

Proposed vocabulary (sketch):

| Name | Resolves to |
| --- | --- |
| `side Stationary`, `side Moving` | panels on that side of the step's move, from `stepStationary` / `stepMoving` |
| `acrossHinge s` | panels on side `s` that own a hinge segment |
| `closed r` | every vertex of every triangle owned by region `r`, shared boundary vertices included (the `CraneRoot.hs:52-55` rule) |
| `band s (d0, d1)` | samples on side `s` whose start-pose distance from the hinge line, measured in the hinge's plane, lies in `[d0, d1]` sheet units, with 1e-8 slack (`CraneSpread.hs:104-106`) |
| `materialBand (u0, u1)` / `materialRegion polygon` | samples by material coordinate (the `WingBending` style) |
| `creaseLine seg` | every refined vertex on the segments of the creases lying along material segment `seg` (E2 rule 2) |
| `minus`, `union` | set operations on regions |
| `layer Upper/Lower of r` | the part of `r` on one side of a pair in `stepOrders`; needed because a folded-pose band selects coincident layers together |

Grip *targets* are not names. `bentPoint` is a curve rule (finding 9), so a
target is either `rigidPose p` (the region's positions in `flapAt p`) or a
study-registered generator such as `arcGrip root extra`. Register generators
the same way as certificates in (c).

**Mapping every existing crane hold onto the scheme**, with move `m` = the
wing flap:

| Existing | Code | Scheme |
| --- | --- | --- |
| refine wing | `CraneSpread.hs:95-96` | `refine (side Moving)` |
| refine wing + root neighbours | `:97` | `refine (side Moving ∪ acrossHinge Stationary)` |
| body | `:101` | `closed (side Stationary)` |
| selected | `:102` | `closed (side Moving)` |
| root strip, 30° | `:103-106`, `bentPoint` root | `band Moving (0, 1/32)` held at `rigidPose (1/3)` (unverified equivalence, see below) |
| tip grip | `:104-105` | `band Moving (7/32, ∞)` with target `arcGrip 30 θ` |
| contact pairs | `:108-114`, `:141-150` | not named: `stepOrders` closed, then kept only where a triangle has a free vertex |
| root edges | `CraneRoot.hs:60` | `hinge m`, never "the `Unassigned` edges" |
| root neighbours `[7,8,27,43]` | `:60-63` | `acrossHinge Stationary` |
| distant | `:67` | `closed (side Stationary minus acrossHinge Stationary)` |
| `HeldRoot` | `:69` | body ∪ root strip ∪ grip |
| `ReleasedRoot` / `WeakerRoot` / `FlatRoot` | `:68-76` | body ∪ grip; spring changes on `hinge m` |
| `FreeBody` | `:68-74` | distant ∪ grip; rest 0 on `hinge m` |
| two opening creases | `CraneBody.hs:66` | `creaseLine` for each, named by material segment; `CranePocket` roles stay fixture data |
| internal crease lines 26, 51 | `CraneInternal.hs:55`, `:62-64` | `creaseLine seg26 ∪ creaseLine seg51` |
| crossed upper grip | `CraneSpread.hs:155-163` | `layer Upper of band Moving (7/32, ∞)`, then offset |

Three cautions for the PRD:

- **A hold is not the anchor.** The anchor fixes the rigid reference frame
  (`StudyCase.hs:161-172`). A hold is a constraint inside one solve, and the
  two need not coincide.
- **Coincident is not shared.** A folded-pose band picks both layers. A grip on
  one layer needs `layer`, as `crossedGrip` does through orders
  (`CraneSpread.hs:161`).
- **Spec assertions will change.** Moving the fixtures to names should turn
  the pinned `FaceId`s (`CraneRootSpec.hs:34`) and `EdgeId`s
  (`CraneInternalSpec.hs:27`) into material-seed assertions. Keep the resolved
  counts (902 orders, 16 held vertices) as regression checks that the scheme
  resolves to the same sets. That is a reviewed test change, not a free one.

### (c) Certificates attach after the run, in the study

Recommend a **post-run registry** in the study executable, not hooks passed
into the library runner:

```haskell
-- study/fold-material only
data CertificateEntry = CertificateEntry
  { entryMacro   :: MacroName                                  -- e.g. "petal"
  , entryBind    :: StepRecord -> Either Unbound Binding       -- fingerprint: material vertices,
                                                               --   cut faces, edge list, anchor
  , entryCertify :: Binding -> [(Int, Int)] -> Either Text PetalCertificate
  , entryPath    :: Binding -> Double -> [V3]                  -- ideal poses for the 1e-12 comparison
  }
certificates :: Map MacroName [CertificateEntry]
attachCertificates :: [StepRecord] -> [(StepRecord, CertificateOutcome)]
data CertificateOutcome = Certified PetalCertificate | NoCertificateFor Unbound | Refused Text
```

Why:

- **Key on macro name and fingerprint.** A name alone is not enough: the
  certificate indices belong to one fixture (finding 16). `entryBind` is
  `preparePetal`'s guards turned into data. A pattern the entry was not
  written for gives `NoCertificateFor`, never `Refused`.
- **Post-run input is available.** The first petal's accepted orders feed the
  later certificates (`CheckedBird.hs:61-66`), and they are in `stepOrders`.
- **Hooks rejected.** Runner hooks (`RunHooks { certify :: … }`) would respect
  the import rule, because a function value is not an import. But the CLI
  would pass none. The same sequence would then produce a different record in
  the CLI than in the study, and the record could not say why.
- **What the CLI reports.** It runs the same macros and reports `Sampled`.
  Its output must say "sampled, not certified", as A2 implication 6 asks.
- **Refused is never downgraded.** A `Refused` outcome is never rendered as
  `Sampled`. Follow the study's discipline that failures are labelled, never
  silently replaced (B finding 16).
- **Arithmetic trap.** Samples must be stated in the macro's own parameter.
  `CheckedBird` uses `175 * fraction` (`:85`), and A2 F32 shows that
  absolute angles produce different Doubles.

### (d) Migration table

Nothing is removed in the first PRD. Each "becomes a sequence" row lands as
two PRs:

1. **Equivalence.** Add the sequence beside the recipe. Add an equivalence
   spec that compares records with A2's F28 and F29 bars, using exact angle
   lists, `shouldMatchList` on orders and positions within 1e-12. Build both
   once in `beforeAll` (finding 20). Goldens must stay byte-identical, and any
   diff must be read before accepting it.
2. **Deletion.** Delete the recipe module from both cabal stanzas
   (`senbazuru.cabal:179`, `:195-256`), and point the gallery at the sequence.

| Recipe | Fate | Blocking work | Guards |
| --- | --- | --- | --- |
| `BlintzSequence` | **becomes a sequence** (first) | runner, flap step with material seeds, an anchor rule | `BlintzSequenceSpec.hs:35-39`, `41-96`, `110-127`; `checked-blintz.svg` |
| `HelmetSequence` | **becomes a sequence** (second) | a hinge named by one material line resolving to several edges (`[8,9]`, `[10,12]`, `[13,11]`; `HelmetSequence.hs:48-50`); a 120° illustration rule as presentation (`:70-84`) | `HelmetSequenceSpec.hs:40`, `47-51`, `79-84`, `143-150`, `164-175`, `187`; `checked-helmet.svg`. Moving-face ids (`:81`) depend on the face reorder and may need material rings. |
| `CraneWing` | **stays a fixture recipe**; later a sequence prefix | layer-selective crease (hand-picked faces `[2,3,6,7]`, `CraneWing.hs:93`), stacking by predicate instead of index `[2]` (`:78`), an expected-refusal step (`:81-84`), and an unbent-crease convention that is not `U` (finding 5) | `CraneWingSpec.hs:56-81`, `83-134`, `145`; `checked-crane.svg`; and every crane spec below, since they build from it (`CraneSpread.hs:84`) |
| `CraneSpread`, `CraneRoot`, `CraneBody`, `CraneInternal` | **stay fixtures**; holds re-expressed with (b) in a behaviour-preserving PR | a study-side region resolver; rest angles from the record | `CraneSpreadSpec.hs:25-84`, `CraneRootSpec.hs:24-61`, `CraneBodySpec`, `CraneInternalSpec.hs:24-50` |
| `CheckedPetal`, `CheckedBird` | **become a study-authored sequence of coupled macros**; modules shrink to registry entries | library collapse and petal macros (sampled), macro parameters, stage-activated landing orders (`CheckedBird.hs:131-137`), the registry | `CheckedBirdSpec.hs:44`, `97-109`, `159`, `169-173`; `CheckedPetalSpec.hs:125`, `135-138`; `PetalFoldSpec` |
| `BasicBases` six endpoints | **stay fixtures** | none; they are endpoint constructions that regenerate `examples/*-base.fold` | `BasicBaseSpec` per base (`:51`) |
| frog guide (`frogMilestones`, `writeFrogGuide`) | **stays a fixture** | squash and petal on a frog, a turnover as presentation instead of by key name (`BasicBaseGallery.hs:126`), stacking choice (`:74`) | `BasicBaseSpec.hs:170-220`; `frog-sequence.svg` |
| `cases.json` `single`, `double`, `kite` | **stay** as state-only controls | none | `StudyCaseSpec.hs:26-116` |
| `cases.json` `blintz` | **stays**, after deciding which direction is canonical (A2 F3) | a decision, not code | `StudyCaseSpec.hs:55-95`, `108-116` |
| `cases.json` `square`, `waterbomb`, `rabbit-ear` | **stay** until collapse and rabbit-ear macros exist, then are generated from them | macros; literal drift (A2 F8) | `BaseCollapseSpec.hs:33-75`, `RabbitEarSpec.hs:43-183` |
| `cases.json` `bird-petal` | **stays**: the source of `examples/bird-base-sequence.fold` (`examples/README.md:224-231`) and of `CheckedBird`'s 16 named panels | an exact regeneration path, or a reviewed change to the fixture | `BirdSequenceSpec.hs:39-84`; `bird-sequence-iso.svg`, `bird-sequence-bottom.svg` |

### (e) Licence position for PRD 3

1. **Rule to propose.** Running an external program and reading its output
   files is not vendoring. It needs no MIT compatibility, but it does need:
   - a row in `docs/related-projects.md` stating the licence of the
     *program as built*;
   - provenance in `examples/README.md` for any output kept as a fixture;
   - no CI or test dependency on the tool (finding 20).

   The PRD should propose this wording for AGENTS.md "Third-party material".
   It should not edit the file.
2. **Origami Simulator.** It is usable, by manual or browser-automated export,
   as #53 already plans. Keep the design-licence rule for the patterns fed to
   it (`AGENTS.md:149-155`).
3. **ipc-toolkit.** The MIT licence permits a driver. But the driver would be
   new C++ or Python in or beside the repo. Decide that as a toolchain
   question, and cite the toolkit as its authors request.
4. **Codim-IPC.**
   - Treat it as user-installed and never shipped.
   - If a GPL-free binary matters, the PRD should require
     `LINEAR_SOLVER=EIGEN` or `WITH_GPL=OFF`.
   - Reading its source for ideas is fine. Copying from it would bring Apache
     section 4 obligations, and those are not the same as MIT's.
5. **Precedence.** None of these belongs ahead of the in-repo solver path B
   lays out. Each is a comparison oracle, as #53 frames Origami Simulator.

## Open questions

1. **Band measure.** Should `band` use absolute sheet units, as proposed here,
   or a fraction of the side's extent? The crane uses a fraction of a constant
   0.25 (`CraneSpread.hs:103`).
2. **Where `layer Upper/Lower` resolves.** Against `stepOrders` only, or also
   against directional requirements for a non-flat start?
3. **Stationary side.** Should the runner expose `stationaryFace` through a new
   `Flap` accessor, or record the seed it resolved?
4. **Crease steps.** Is `stepNewCreases`, material segments, enough to relate
   the before and after numberings? Or does the study also need
   `refinedEdges`-style source ids across a re-cut?
5. **Certificate evidence types.** Should registry outcomes stay
   `PetalCertificate`-typed, or become a small study-side sum type once a
   second certificate family exists?
6. **The blintz manifest case.** Once the blintz sequence exists, is the
   manifest case, which folds the other way, a deliberate control or a
   duplicate to delete?
7. **External-tool rule.** Does the repository owner want the rule in
   (e)1 in AGENTS.md, or only in `related-projects.md`?

## Unverified

- **Whether 0.25 is the wing's full extent** from the root line, that is,
  whether the tip lies at folded y = 0 in the start pose. Not computed. The
  band endpoints in the mapping table (1/32, 7/32) follow the constant, not a
  measurement.
- **Whether `bentPoint 0` equals the rigid pose `flapAt (craneOpening wing)
  (1/3)`.** `CraneSpreadSpec.hs:59-64` compares the solve with the initial
  guess, not with `flapAt`. The `rigidPose (1/3)` entry is a proposal, not
  equivalence.
- **Whether the proposed region rules reproduce `CraneSpread`'s and
  `CraneRoot`'s pin sets exactly.** Nothing was run.
- **The helmet moving-face ids.** That they would change under material-point
  anchoring is inferred from A2 F13 and `HelmetSequence.hs:41-44`, not run.
- **Licence conclusions are a reading, not legal advice.**
  - Whether running a GPL-linked Codim-IPC binary as a separate process
    creates any obligation for senbazuru was not checked against a primary
    source such as the FSF's aggregation FAQ.
  - The Apache and CHOLMOD statements come from summarising fetches of the
    URLs cited.
  - That `include(suitesparse)` resolves to `CMake/suitesparse.cmake` is
    inferred from the directory listing; CMake's module path was not checked.
- **Unchecked dependency licences.**
  - ipc-toolkit's fetched dependencies.
  - Codim-IPC's `Externals` (`flat_hash_map`, `meta`, `pybind11`), Kokkos,
    cabana and amgcl.
  - Origami Simulator's bundled libraries.
- **Origami Simulator headless mode.** Its absence rests on the README
  summary; the source was not read.
- **Timings.** #208's are approximate single CI runs, quoted as the issue
  records them.
