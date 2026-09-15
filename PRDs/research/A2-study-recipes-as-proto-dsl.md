# A2 — The study's hand-written recipes as a proto sequence language

> **Erratum (from [Z-critic](Z-critic.md), spot check 31).** Implication 12
> says `render --steps` consumes per-state angle tables. It does not: `stepPage`
> draws folded frames, and `--steps` refuses `--fold`
> (`app/Senbazuru/Cli.hs:843-851`). An angle table can still be an internal
> intermediate form; the CLI does not read one.

Researcher slice: the de facto sequence "language" already written by hand in
`study/fold-material/`. Nothing in the repository was modified or compiled.
Three small numeric checks were run with `python3` on this Mac (not GHC); they
are marked as such where used. Line numbers are against branch
`docs/prds-sequence-language` at `568dcb6`.

## Summary

The study contains four different ways of writing a folding sequence down,
and none of them is a language yet:

1. **Angle tables** (`cases.json` read by `StudyCase`): every state is a
   complete list of fold angles, one per source edge, by position.
2. **Flap recipes** (`BlintzSequence`, `HelmetSequence`, `CraneWing`,
   `FlapGallery`): each move is `(title, EdgeId or [EdgeId], moving FaceId,
   signed travel)` against a *reordered, cut* pattern, driven through the
   library's `Origami.Flap`.
3. **Certified coupled recipes** (`CheckedPetal`, `CheckedBird`): a stage enum
   plus a progress fraction goes through a closed-form formula to a full
   angle list. Each pose is compared with an exact per-stage certificate.
4. **Flat checkpoints** (`BasicBases` frog guide): material crease segments
   per milestone, with no motion implied.

The flap and certified recipes repeat one handoff policy almost verbatim:
carry angles and orders onto the material pattern, anchor once, check every
join. An interpreter could own that policy. The manifest cannot express
motion, per-stage contact, creasing, stacking choice or holds.

There are also two surprises that bear on acceptance tests:

- The two in-repo blintz routes fold the corners in **opposite directions**.
- Some literal angles in the manifest are **not bit-reproducible** from the
  formulas that are documented beside them.

## Findings

### (a) What each recipe does, and how each move is specified

**F1. Four specification styles coexist.**

- **Angle tables.** `StudyCase` says a case "supplies a complete angle list
  for each named state, in that source file's edge order". It keeps the study
  "out of the business of inferring a folding sequence"
  (`study/fold-material/StudyCase.hs:5-9`). A pose is a label plus angles
  (`StudyCase.hs:78-85`), and a list whose length differs from the edge count
  is refused (`StudyCase.hs:152-153`).
- **Flap moves.** The library entry point takes "Crease id, incident face on
  the moving side, signed travel in degrees, and a folding result". Its ids
  belong to the returned cut pattern (`src/Senbazuru/Origami/Flap.hs:152-155`,
  `:9-13`).
- **Certified stages.** `data BirdStage = SquareCollapse | FrontPetal |
  BackPetal | PressPetals` (`CheckedBird.hs:48`). Progress becomes hinge
  angles (`CheckedBird.hs:83-87`), and those become full angle lists by
  formula (`CheckedBird.hs:107-114`, `CheckedPetal.hs:101-110`).
- **Flat checkpoints.** `frogMilestones` are "Flat checkpoints for a human
  folding guide, not samples of a continuous motion"
  (`BasicBases.hs:130-141`). Each is a `[(V2, V2, Assignment)]` crease list
  generated from counts of squashes and petals (`BasicBases.hs:146-183`).

**F2. Blintz: five flap moves, raw ids.**

The fixture `examples/blintz-base.fold` has 8 vertices, 12 edges and no
`faces_vertices` (checked with jq). Edges 8–11 are the corner creases:

| Edge | Segment | Corner | Assignment | Angle in file |
| --- | --- | --- | --- | --- |
| 8 | (0.5,0)–(1,0.5) | lower-right | M | −180 |
| 9 | (1,0.5)–(0.5,1) | upper-right | M | −180 |
| 10 | (0.5,1)–(0,0.5) | upper-left | M | −180 |
| 11 | (0,0.5)–(0.5,0) | lower-left | M | −180 |

How the recipe sets up and runs:

- It folds the fixture with every angle zeroed to trace faces
  (`BlintzSequence.hs:42`).
- It expects exactly five rings of lengths `[3,3,3,3,4]` and rotates the
  square to the front, giving `[centre, a, b, c, d]`
  (`BlintzSequence.hs:44-47`).
- The recipe table (`BlintzSequence.hs:50-56`) has four rows of
  `(EdgeId 8..11, FaceId 2/3/4/1, -180)` and a reopening row
  `(EdgeId 8, FaceId 2, 180)`.
- Which face goes with which edge exists only in that table. The test
  re-encodes the same pairing by hand (`test/BlintzSequenceSpec.hs:73`).
  The only guard on the ids is the ring-length pattern.
- Illustrations are "Eleven poses": the start, then progress 0.5 and the
  endpoint of each move (`BlintzSequence.hs:75-87`).

**F3. The two blintz routes fold in opposite directions.**

- The flap recipe travels −180, matching the fixture's `M`. Its gallery
  notes that mountain folds "go below its original xy plane, so view its
  underside" (`BlintzGallery.hs:3-4`).
- The manifest's `blintz` case folds the same edges to **+90/+175**
  (`cases.json:64-71`) and declares the centre *below* each corner along +z
  (`cases.json:51-60`). `StudyCaseSpec` confirms the first corner rises to
  z = +√0.125 at +90 (`test/StudyCaseSpec.hs:112-116`).
- Both end in the same flat positions. "At signed 180 degrees the rigid
  geometry is identical on either side" (`test/StudyCaseSpec.hs:74-75`).
- Newcomer trap: "fold the corner to the centre" does not say which way.
  Two recipes in this repo already read it differently.

**F4. Helmet: one physical hinge made of several edge ids.**

- The fixture records six faces. The recipe checks ring lengths
  `[3,4,3,3,4,3]` and moves the quad at index 1 to the front
  (`HelmetSequence.hs:41-44`).
- Moves (`HelmetSequence.hs:47-51`): `([8,9], FaceId 5, 180)`,
  `([10,12], FaceId 1, 180)`, `([13,11], FaceId 2, 180)`.
- The first id in each list sets the sign. The operation derives the other
  segments' signs from their stationary faces (`Flap.hs:157-161`,
  `Flap.hs:208-216`).
- In the fixture, 10 and 13 are `V` while 12 and 11 are `M` (jq). So
  `[13, 11]` deliberately lists the valley first.
- The note explains that edge 10 closes to +180 while edge 12 closes to −180
  for the same physical turn. Giving both +90 would tear the sheet
  (`docs/notes/aligned-crease-hinges.md:18-27`).
- Moving faces are `[3,4,5]`, `[1,5]`, `[2,3]`
  (`test/HelmetSequenceSpec.hs:81`).
- Illustration policy has a special case: move 1 is drawn at 120°, not 90°,
  because at this camera the 90° pose "has the open sheet's silhouette"
  (`HelmetSequence.hs:70-84`).

**F5. Crane wing: ids are *computed*, not written.**

- It checks the anchor by a sorted material ring and a face count of 72
  (`CraneWing.hs:56-58`).
- It clips the folded line y = 1/4 to four hand-picked faces `[2,3,6,7]`. It
  maps each clip back to material space by the inverse fold transform
  (`CraneWing.hs:87-101`) and adds the result with `creaseAllAlong`
  (`CraneWing.hs:60`).
- It then recovers ids from the result:
  - the anchor, by matching the sorted ring (`:61-63`);
  - the hinge, as every `Unassigned` edge, expecting exactly 4 (`:65-66`);
  - the moving side, as the one face containing both hinge vertices and
    `VertexId 2` (`:72-74`).
- It picks stacking **index** `[2]` of five valid orders (`:75-79`).
- It travels +90 and *requires* −90 to be refused with `FlapEndpointOrder`
  (`:80-84`).
- Poses are 0, 30, 60, 90 (`:103-108`).
- The module comment states the rule that ids "are then selected from their
  result, never carried across that boundary" (`CraneWing.hs:11-12`).

**F6. FlapGallery hands off onto the source frame, not `foldedPattern`.**

- Examples: `reopening = singleFlap {edgesFoldAngle = …, faceOrders = …}`
  (`FlapGallery.hs:40`), and likewise at `:46` and `:50`.
- This is correct only because the `FlapExample` frames record their own
  faces and have no crossings (`FlapExample.hs:1-16`).
- The blintz and helmet recipes write onto `foldedPattern start` instead
  (`BlintzSequence.hs:63`, `HelmetSequence.hs:58`), as the Folding docs
  require (`Folding.hs:286-292`).
- The recipes are therefore not consistent about which frame receives the
  handoff.

**F7. Manifest cases store coupled formulas as pasted literals, and repeat
held values.**

- Cases: `single`, `double`, `kite`, `blintz`, `square`, `waterbomb`,
  `rabbit-ear`, `bird-petal` (`cases.json`).
- Square and waterbomb store valley values such as `41.5071419673696`
  (`cases.json:95-100`, `:124-129`). Rabbit ear: `:153-166`. Bird petal:
  `:219-234`.
- The formulas live in notes and code:
  - collapse: `docs/notes/symmetric-base-collapse.md` ("valley = 2
    atan2(√2 sin(m/2), cos(m/2))"), and `CheckedBird.hs:110-114`;
  - rabbit ear: `docs/notes/rabbit-ear-motion.md:40`;
  - petal: `CheckedPetal.hs:104-110`.
- A held earlier stage is expressed by copying its angles into every later
  state. Examples: the first ear's `178.8261303053405` values in all
  second-ear states (`cases.json:160-166`), and the first petal's 175° values
  in all second-petal states (`cases.json:227-233`).

**F8. Several literals are not bit-reproducible from the documented
formulas.**

Method: Python 3 on this Mac, evaluating the same expressions as the code or
notes, compared the results with the JSON literals.

| Family | Matches | Mismatch |
| --- | --- | --- |
| Square collapse | 6/6 | none |
| Bird petal side angle | 6/7 | t = 175: literal `-166.98236060695527`, formula `-166.98236060695518` |
| Rabbit ear | 6/7 | m = 30: literal `97.58514830800293`, formula `97.58514830800294` |

This matters for (f), because `BirdSequenceSpec` compares angles exactly (F31).

**F9. The certified bird route is formulas plus hand-built exact paths,
bound to one fixture.**

- **Id and topology guards.**
  - `preparePetal` requires the fixture's material vertices within 1e-12
    (`CheckedPetal.hs:49-50`).
  - It requires the cut faces to equal `petalFaces` and the edge list to
    equal a literal 28-pair `expectedEdges` (`CheckedPetal.hs:51-52`,
    `:62`).
  - It requires `fixedPanel == Just (0.58, 0.4)` (`:53`).
- **Crease roles are positional.** Each is a slot in the list returned by
  `birdAngles` (`CheckedPetal.hs:110`). Against the edge list and material
  coordinates (`CheckedPetal.hs:62`, `PetalCertificate.hs:145`):
  - 8, 9: the diagonal valleys through the centre;
  - 11, 15: the opening folds P–(0.5,0) and Q–(1,0.5);
  - 12, 13, 16, 17: the side creases;
  - 26: the hinge P–Q (matches `docs/notes/petal-fold-motion.md:13-15`,
    `:52-54`);
  - 19, 20, 21, 23, 24, 25, 27: the same roles for the back petal
    (`docs/notes/two-petals.md:18-22`).
- **Newcomer trap: one "midline ray" is two edges with two behaviours.**
  - During collapse the ray centre→P→(0.5,0) is two collinear segments at the
    same angle `-v` (edges 10 and 11 in `collapseAngles`, `CheckedBird.hs:114`;
    `docs/notes/checked-square-collapse.md:12-13`).
  - During the petal, edge 10 stays at −180 while edge 11 opens as `t-180`
    (`CheckedPetal.hs:110`).
- **Certificates.** Each stage's certificate uses rational vertex paths
  written for these vertex indices:
  - `paths` with its tip and shoulder formulas (`PetalCertificate.hs:162-179`);
  - `secondVertices = [(3,1),(6,5),(7,4)]` (`:198-213`);
  - `collapsePaths` (`:236-258`).

  They are not derived from the angle formulas. `CheckedBird` compares each
  angle-derived pose with them within 1e-12 (`CheckedBird.hs:120-129`).
- **Route shape.** The route uses the first 0–175 of each full 0–180
  petal certificate and the last 175–180 of the press certificate
  (`CheckedBird.hs:8-12`; `docs/notes/checked-bird-base.md:44-46`).
- **What it takes from, and ignores in, the manifest.** `CheckedBird` uses
  the `bird-petal` case's `fixedPanel` and `contact`, but **not its steps**:
  poses come from `birdPose`, not `caseSteps`
  (`CheckedBird.hs:123`, `PetalGallery.hs:54-56`).
- **Sampling.** 23 figures (`CheckedBird.hs:164-166`). This is not the same
  as the manifest's 16. For example, the manifest has a 15° front-petal state
  and `birdStates` does not.

**F10. The frog guide is checkpoints plus a presentation rule.**

- Each milestone is rebuilt from crease segments, so face ids differ from
  milestone to milestone.
- The gallery orients each packet using material landmarks `[0,0]` and
  `[0.5,0.5]`, with a turnover chosen by milestone *key name*
  (`BasicBaseGallery.hs:110-128`).
- Layer order is the stacking solver's first answer
  (`BasicBaseGallery.hs:74-75`). The milestones say "no motion is implied
  between checkpoints" (`BasicBases.hs:144`).

### (b) The shared handoff policy: invariants an interpreter must enforce

**F11. Carry angles AND face orders onto the material pattern; never folded
coordinates.**

- Code: `nextPattern = (foldedPattern start) {edgesFoldAngle = edgesFoldAngle
  accepted, faceOrders = faceOrders accepted, frameExtras = mempty}`
  (`BlintzSequence.hs:63`; identical at `HelmetSequence.hs:58`).
- Why: feeding folded coordinates back "would fold the already folded sheet a
  second time" (`BlintzSequence.hs:10-12`). Re-solving the layer order "could
  silently choose a different stack" (`docs/notes/chaining-checked-folds.md`,
  second paragraph).
- Library backstop: `foldFrameWith` refuses a frame classified as folded
  (`Folding.hs:338-339`).

**F12. Drop what the move invalidates.**

- The recipes clear `frameExtras` (`BlintzSequence.hs:42`, `:63`).
- The flap operation itself rebuilds from angles with `faceOrders = []` and
  `frameExtras = mempty` (`Flap.hs:172`, `Flap.hs:344`).
- This matches the repo rule that a move "must drop what it invalidates"
  (AGENTS.md, Conventions).

**F13. Anchor once, before any motion, and never let the anchor move.**

- `spanningWalk` starts from the root face, the first face
  (`Folding.hs:571-578`), and "The root face is held still"
  (`Folding.hs:239-240`).
- Each recipe therefore reorders faces once:
  - blintz: `BlintzSequence.hs:6-8`, `:44-47`;
  - helmet: `HelmetSequence.hs:8-9`, `:41-44`;
  - crane: keeps the original face zero first, `CraneWing.hs:14-15`, `:61-63`.
- Why it matters (`docs/notes/chaining-checked-folds.md`, third paragraph):
  - `flapAt` holds the flap's stationary face still (`Flap.hs:346-348`).
  - An independent refold holds face 0 still.
  - If those differ, joining the two inserts a whole-sheet rotation.
- The invariant, which the recipes enforce only indirectly through F14:
  **the anchor face must be stationary in every move**. Evidence it holds:
  the helmet's moving sets never include face 0 (F4), and the blintz test
  checks face 0 against material positions (`BlintzSequenceSpec.hs:64-68`).
- A second anchoring mechanism exists: `fixedPanel`, "A point strictly inside
  the panel held in its original position" (`StudyCase.hs:69-70`). It is
  resolved against material faces and applied by inverse placement
  (`StudyCase.hs:161-172`). Without it, the largest panel is held still, with
  a lowest-then-leftmost tie-break (`StudyCase.hs:242-248`).
- Newcomer trap: a petal's largest panel is its **moving** tip
  (`docs/notes/petal-fold-motion.md:60-64`).

**F14. Check every join, and there are two strengths of check.**

- **Flap recipes.** Refold `nextPattern` and require every vertex within
  `1e-12 * modelSpan` of the accepted endpoint
  (`BlintzSequence.hs:64-70`, `HelmetSequence.hs:59-65`). This is kept
  "Check the join anyway, so a changed fixture cannot silently insert a rigid
  jump" (`BlintzSequence.hs:13-15`).
- **`CheckedBird.checkJoin`.** It compares all of the following
  (`CheckedBird.hs:139-146`):
  - positions within 1e-12;
  - *exactly equal* angles, edge lists and face rings;
  - equal resolved orders;
  - equal material-coordinate extras.

  It runs at three joins (`CheckedBird.hs:68-76`).
- **Tests.** Join tests assert matching orders (`shouldMatchList`), exact
  angles, exact material ids, and positions within 1e-12
  (`BlintzSequenceSpec.hs:89-96`, `HelmetSequenceSpec.hs:143-150`).

**F15. The flap start must be an untouched `foldFrameWith` result.**

- `prepareFlapAlong` rebuilds the angle state and returns
  `FlapStartMismatch` in any of these cases (`Flap.hs:169-181`):
  - the angle count differs;
  - the face rings differ;
  - any position differs by more than 1e-9 of the span.
- Why: "Folded's constructor is public" (`Flap.hs:169-170`).
- An interpreter must therefore re-fold after every handoff rather than patch
  a `Folded` value.

**F16. Endpoint angles are exact sums, and endpoint orders are computed.**

- Pose angles are `angle + progress * travel` (`Flap.hs:343`), so endpoints
  are exactly representable here: −180 + 180 = 0.
- The tests pin exact lists, e.g. `[-180, 0, 0, 0]` …
  `[0, -180, -180, -180]` (`BlintzSequenceSpec.hs:37-38`;
  `HelmetSequenceSpec.hs:82-83`).
- Orders at a pose are retained stack orders plus endpoint contacts
  (`Flap.hs:290-294`). Starting orders are checked against departure
  (`Flap.hs:303-312`).
- Order counts per endpoint: blintz `[1,2,3,4,3]`
  (`BlintzSequenceSpec.hs:39`); helmet `[3,7,11]`
  (`HelmetSequenceSpec.hs:84`).

**F17. Resolve ids after every topology change.**

- The rule appears three times:
  - cutting "can renumber the input" (`Flap.hs:9-10`);
  - transforms are keyed by the *cut* pattern (`Folding.hs:286-292`);
  - crane ids are re-selected after creasing (`CraneWing.hs:11-12`,
    `:61-74`).
- Material rings or points survive renumbering, and the tests use them for
  that reason (`test/CraneWingSpec.hs:63-68`; `StudyCase.hs:117-118`).

**F18. Orders for touching stacks are mandatory input, not optional
metadata.**

- The operation "does not infer a stack from coincident positions"
  (`Flap.hs:33-34`).
- The helmet test strips the carried orders and expects refusal
  (`HelmetSequenceSpec.hs:47-51`).
- So an interpreter that forgets to carry orders fails loudly. That is good,
  but it means orders are part of the state, not decoration.

**F19. Choosing among valid stackings is a recipe decision, and an index is
fragile.**

- The crane picks index 2 so the tail is tucked (`CraneWing.hs:15-19`,
  `:75-79`).
- The test checks the geometric meaning, not the index, and shows the first
  order fails it (`test/CraneWingSpec.hs:56-81`).

**F20. Expected refusals are part of the recipes.**

- Blintz: reopening through the centre is refused
  (`BlintzSequenceSpec.hs:110-115`).
- Crane: −90 must be refused (`CraneWing.hs:81-84`).
- Helmet: the body-side reopening is refused
  (`HelmetSequenceSpec.hs:164-175`).
- Bird: a reflected collapse and reversed orders are refused
  (`CheckedBirdSpec.hs:97-104`).

### (c) The `cases.json` manifest schema, and what it cannot express

**F21. Schema, as parsed.**

The file is a top-level JSON array of cases. Each case (`StudyCase.hs:63-76`):

| Key | Required | Type | Parsed as |
| --- | --- | --- | --- |
| `id` | yes | string | `caseId` |
| `title` | yes | string | `caseTitle` |
| `source` | yes | path relative to the repository root | `caseSource` |
| `description` | yes | string | `caseDescription` |
| `steps` | yes | array of `{label: string, angles: [number]}` | `caseSteps` (`StudyCase.hs:84-85`) |
| `fixedPanel` | no | 2-element array `[u, v]` | `Maybe (Double, Double)` |
| `contact` | no | object | `Maybe ContactSpec` |

`contact` has three required keys (`ContactSpec.hs:24-33`):

- `direction`: exactly `[x, y, z]`.
- `panels`: array of `{name, at: [u, v]}`. Any other length for `at` fails
  with "panel at needs two material coordinates" (`ContactSpec.hs:13-19`).
- `orders`: array of `[lower, upper]` name pairs.

Validation beyond parsing:

- **Ids** must be unique, non-empty, and made of lowercase ASCII, digits and
  `-`. `steps` must be non-empty (`Main.hs:95-96`, `:174-175`).
- **Angles**: one per source edge (`StudyCase.hs:152-153`).
- **Folded material**:
  - lies in the unit square at z = 0;
  - covers area 1 within 1e-9;
  - every panel is convex (`StudyCase.hs:158-160`, `:257-263`).
- **Subdivision level** is 0–5 (`StudyCase.hs:151`).
- **Panel names**:
  - each `at` must lie strictly inside exactly one material face, with
    tolerance 1e-10 (`StudyCase.hs:139-143`);
  - every material panel must be named exactly once. The reason given: "an
    omitted flap could escape all contact checks" (`StudyCase.hs:117-120`,
    `:131-134`).
- **Orders** naming an unknown panel, and cyclic orders, are refused
  (`src/Senbazuru/Origami/Contact.hs:130-134`).
- **Order meaning** is lower/upper along `direction`. The collapse note
  measures along the fixed face's +z, "independently of the camera"
  (`docs/notes/symmetric-base-collapse.md`, last paragraph).

The manifest "is read by the study executable; it is not a new library input
format" (`docs/architecture.md:409-413`).

**F22. What the manifest cannot express.** Each item has evidence.

1. **Motion between states.** There is no path and no certificate; "they do
   not change the prescribed pose or certify motion between states"
   (`docs/architecture.md:421-422`).
2. **Contact orders that change during a sequence.** Orders are per case.
   - Rabbit ear: its moving panels swap order mid-turn, so the case declares
     only the stable relations and leaves overlaps at closure to a separate
     spec (`StudyCaseSpec.hs:64-67`; `docs/notes/rabbit-ear-motion.md:75-83`).
   - Bird: `CheckedBird` has to strip `panelOrders` in code for the
     unfinished collapse, because a landing order "is not an order between
     shadows cast by tilted panels" (`CheckedBird.hs:131-137`).
3. **Named crease roles.** Angles are positional. A reordered edge list needs
   a reversed angle list (`StudyCaseSpec.hs:83-89`).
4. **Parameters and formulas.** Only literals, which can drift from the
   formula (F8).
5. **Holds.** An earlier stage's values must be repeated in every later
   state (F7).
6. **Topology changes.** `source` is fixed, so creasing (as in `CraneWing`)
   is out of reach.
7. **Stacking choice** (F19) and **expected refusals** (F20).
8. **Fold direction.** Nothing flags that the manifest's blintz is the
   reverse of the fixture's assignment (F3).
9. **Presentation.** No camera, and no illustration choices such as
   "halfway" or the helmet's 120° exception.
10. **Fixture guards.** No expected edge list, like `CheckedPetal`'s
    `expectedEdges`.
11. **One anchor per case**, and convex panels of a unit square only
    (`StudyCase.hs:19-20`).

**F23. Its FOLD export differs from the flap recipes' export.**

- `buildCaseSequence` writes `surfaceFrame`-based frames (`StudyCase.hs:187-226`).
  Separately, `buildCaseFrame` rewrites any `Flat` crease with a nonzero angle
  to `M` or `V` (`StudyCase.hs:207-210`).
- `examples/bird-base-sequence.fold` frames indeed carry no
  `senbazuru:material_coords` key (jq on frame keys).
- Flap recipes export `materialFrame`, which adds that key
  (`Surface.hs:242-252`, `BlintzSequence.hs:99`).
- `CheckedBird` adds it by hand (`CheckedBird.hs:156`).

### (d) Single-hinge vs coupled moves

**F24. Single hinge: what `Origami.Flap` covers.**

- A flap is "the set of faces reached after removing the selected creases";
  the segments must "lie on one line in the CURRENT folded shape"
  (`Flap.hs:1-6`).
- Anything else is refused as `FlapCoupled` (`Flap.hs:196-199`). The helmet
  test covers this: a single diagonal segment `[8]` is refused
  (`HelmetSequenceSpec.hs:40`).
- In the recipes this covers blintz, helmet, the crane wing and the flap
  gallery. In the manifest it covers `single`, `double`, `kite` and `blintz`.
  Those four are the cases outside the `coupledCreases` list
  (`StudyCaseSpec.hs:122-123`).

**F25. Coupled moves: several angles tied by one parameter.**

| Move | Parameter | Tied angles | Source |
| --- | --- | --- | --- |
| Square or waterbomb collapse | mountain magnitude m | valleys `2·atan2(√2 sin(m/2), cos(m/2))` | `docs/notes/symmetric-base-collapse.md` |
| Rabbit ear | mountain m | PC = +m; PA and PE share `v(m)` | `docs/notes/rabbit-ear-motion.md:22-42` |
| Petal | hinge t | sides `-s(t)`; opening folds `t-180` | `docs/notes/petal-fold-motion.md:45-54`; `CheckedPetal.hs:104-110` |
| Press both petals | one t for both | `(t, t)` | `CheckedBird.hs:87` |
| Collapse on the bird fixture | same as the square collapse, signs reversed | — | `docs/notes/checked-square-collapse.md:9-17` |

Evidence that naive interpolation is wrong:

- Halving the final angles, or nudging one crease by 1°, is refused
  (`CheckedBirdSpec.hs:105-109`).
- At t = 90 the petal's side creases are at about 41.882°, not 90°
  (`docs/notes/petal-fold-motion.md:48-50`).

**F26. Every coupled move in the repo has the same five parts:**

1. one scalar parameter over an interval;
2. a closed-form map from the parameter to each crease *role*;
3. a binding of roles to edge ids;
4. a branch or sign choice. The reflected collapse "preserves all lengths and
   reaches exactly the same flat coordinates, but fails" on approach order
   (`docs/notes/checked-square-collapse.md:47-50`;
   `CheckedBirdSpec.hs:97-104`). Back and front petals use the *same* signed
   angles on opposite sides (`CheckedPetal.hs:101-102`;
   `docs/notes/two-petals.md:23-26`);
5. optionally, a certificate.

The rabbit-ear note ties part 2 to the angles between creases on the flat
sheet at a degree-4 vertex (`docs/notes/rabbit-ear-motion.md:16-27`). Part 5 is
*not* derivable from part 2 today: the certificates are per-fixture
polynomial vertex paths (F9).

### (e) Sketches (hypothetical, not a proposal)

> **SKETCH ONLY.** None of these names exist in senbazuru. Each sketch shows
> which facts a language would have to obtain; it is not a syntax proposal.

**Blintz**, embedded-Haskell flavour:

```haskell
blintz :: Sequence
blintz = sequenceOn "examples/blintz-base.fold" "Blintz base, then reopen one corner" $ do
  anchorAt (0.5, 0.5)                          -- material point in the central diamond
  let corner name (a, b) tip = flapAlong name [segment a b] (sideContaining tip)
  lr <- corner "lower-right" ((0.5, 0), (1, 0.5)) (0.9, 0.1)
  ur <- corner "upper-right" ((1, 0.5), (0.5, 1)) (0.9, 0.9)
  ul <- corner "upper-left"  ((0.5, 1), (0, 0.5)) (0.1, 0.9)
  ll <- corner "lower-left"  ((0, 0.5), (0.5, 0)) (0.1, 0.1)
  step "Fold the first corner to the centre"  $ fold lr (mountain 180)
  step "Fold the second corner to the centre" $ fold ur (mountain 180)
  step "Fold the third corner to the centre"  $ fold ul (mountain 180)
  step "Fold the last corner: blintz base"    $ fold ll (mountain 180)
  step "Reopen the first corner"              $ unfold lr
  illustrate [Start, EachMove [Halfway, End]]
```

Still missing from the sketch:

- **Direction.** "mountain" is an assumption: the fixture says `M`
  (F2), while the manifest folds the other way (F3).
- **Sign convention.** `mountain 180` must mean "travel −180 from the current
  angle". For a multi-segment hinge the first segment sets the sign (F4).
- **Face resolution.** `sideContaining` needs the traced faces, which exist
  only after `foldFrameWith` (F2, F17). The face numbering (FaceId 2 for the
  lower-right corner) cannot be read from the fixture file.
- **Illustration arithmetic.** `Halfway` must be `flapAt 0.5`, so that angles
  come out as `angle + 0.5 * travel` (`Flap.hs:343`).
- **Anchor rule.** Either reorder faces as the recipe does, or anchor by
  material point as `StudyCase` does (F13). The two are different code paths.

**Bird route**, file-format flavour:

```text
# SKETCH ONLY
sheet examples/bird-base.fold
anchor at 0.58 0.4
contact direction 0 0 1 { panels ...16 named points from cases.json:177-194... }

stage collapse "Square base" param m 0..180:
  valleys  (0,0)-(0.5,0.5)-(1,1)                      = m
  mountains rays centre->(0.5,0) centre->(1,0.5)
            centre->(0.5,1) centre->(0,0.5)           = -collapseValley(m)
  orders active at landing only                       # CheckedBird.hs:131-137
  branch below                                         # certifyCollapse True
  certificate bird.collapse
  show m at 0 30 60 90 120 150 175 180

stage front-petal param t 0..175 of 0..180:
  petal hinge P-Q tip (1,0) branch above
  certificate bird.front-petal
  show t at 30 60 90 120 150 175

stage back-petal param u 0..175 of 0..180 hold front-petal:
  petal hinge (0.5,0.7929)-(0.2071,0.5) tip (0,1) branch below
  certificate bird.back-petal
  show u at 15 30 60 90 120 150 175

stage press param t 175..180 of 0..180:
  together front-petal back-petal
  certificate bird.press
  show t at 177.5 180
```

Still missing from this sketch:

- **Irrational material coordinates.** P = (0.5, 0.2071…) is 0.5·(√2 − 1)
  off the edge; typed decimals would miss the exact vertex. So roles must be
  named by existing vertices, by snapping, or by expressions
  (`PetalCertificate.hs:145` builds them in Q(√2)).
- **Role split.** A "midline ray" is one role during collapse but two edges
  with different angles during a petal (F9).
- **Formulas.** `collapseValley` and the petal's side and opening formulas
  have to live in a built-in macro library, which also chooses the exact
  arithmetic, because literals drift (F8).
- **Certificates.** The names `bird.*` refer to Haskell values in the study
  (`PetalCertificate.hs:262-291`). The library imports no study code
  (`docs/architecture.md:201`), so a CLI file cannot reach them.
- **Orders.** The 20 declared lower/upper pairs are still hand-written. The
  collapse note says flat landing orders come from the approach, not from
  geometry at the endpoint (`docs/notes/checked-square-collapse.md:44-50`).
- **Sampling.** `show t at 90` should give hinge 90, but `CheckedBird`
  computes `175 * (90/175)`. In Python that is `89.99999999999999` (F32).

### (f) Candidate acceptance tests, and whether they would pass byte-for-byte

**F27. SVG goldens compare exact text.**

- `goldenText` passes only if `expected == actual`
  (`test/Test/Golden.hs:38-60`).
- Every coordinate is printed through `formatNumber` with 3 decimals and
  signed zero normalised (`src/Senbazuru/Render/Svg.hs:332-345`).
- So Doubles that differ in the last bits usually print identically, unless
  a value sits on a 0.0005 rounding boundary.
- The page title comes from `fileTitle`, so titles must match too
  (`BlintzGallery.hs:41`).

| Recipe | Golden | Test |
| --- | --- | --- |
| Blintz | `test/golden/checked-blintz.svg` | `BlintzSequenceSpec.hs:125-127` |
| Helmet | `test/golden/checked-helmet.svg` | `HelmetSequenceSpec.hs:185-187` |
| Crane wing | `test/golden/checked-crane.svg` | `CraneWingSpec.hs:144-145` |
| Bird (certified) | `checked-bird-above.svg`, `checked-bird-below.svg` | `CheckedBirdSpec.hs:169-173` |
| First petal | `checked-petal.svg` | `CheckedPetalSpec.hs:135-138` |
| Manifest bird | `bird-sequence-iso.svg`, `bird-sequence-bottom.svg` | `BirdSequenceSpec.hs:78-84` |
| Flap examples | `checked-flap.svg`, `checked-flat-flap.svg`, `checked-stack-flap.svg`, `checked-aligned-stack.svg` | `test/Senbazuru/Origami/FlapSpec.hs:294-316` |
| Quarter fold | `quarter-fold-steps.svg`, rendered from `test/fixtures/quarter-fold-steps.fold` (byte-identical to the `examples/` copy by `cmp`) | `test/Senbazuru/Render/SvgSpec.hs:379-380` |

**F28. Exact, non-golden assertions a re-expression must reproduce.**

- End angle lists and order counts (`BlintzSequenceSpec.hs:37-39`,
  `HelmetSequenceSpec.hs:81-84`).
- Moving faces, which depend on face numbering, so on the anchor reorder
  (`HelmetSequenceSpec.hs:81`).
- Certificate counts `PetalCertificate 1 120 32 28`, …
  (`CheckedBirdSpec.hs:44`).
- `map edgesFoldAngle frames == map petalAngles petalStates`
  (`CheckedPetalSpec.hs:125`). This uses Haskell `Eq`, under which
  `-0.0 == 0.0`.
- Frame counts: 11 for blintz (`BlintzSequenceSpec.hs:35`), 7 for helmet
  (`HelmetSequenceSpec.hs:79`), 23 for the bird (`CheckedBirdSpec.hs:159`).

**F29. Sampled geometric checks tolerate bit-level differences.**

These checks use tolerances, not exact values: 1e-12 material error, per-face
vertex placement, achieved angles within 1e-9 or 1e-8, and contact passing.
Examples: `BlintzSequenceSpec.hs:41-87`, `CraneWingSpec.hs:83-134` (1e-10 and
1e-11 because the fixture starts at 1.4e-11), and `CheckedBirdSpec.hs:127-143`.
They would pass for any correct re-expression.

**F30. Generated FOLD sequences are not committed, except the manifest bird.**

- `checked-blintz/sequence.fold` and the other recipe outputs are written
  under `build/` by the galleries (`BlintzGallery.hs:45-51`, and similar).
  No `build/fold-material` directory exists in this checkout.
- The recipe tests round-trip in memory only
  (`BlintzSequenceSpec.hs:117-123`).
- Frog: the checkpoints are exported to a temporary directory and compared
  with coordinates cleared exactly and positions within 1e-12
  (`test/BasicBaseSpec.hs:181-205`).

**F31. `examples/bird-base-sequence.fold` is compared exactly except for
coordinates.**

- `withoutCoordinates fixture shouldBe withoutCoordinates file`
  (`BirdSequenceSpec.hs:39-51`). This covers angles, orders, topology and
  metadata exactly. Coordinates allow 1e-12, because trigonometry "on macOS
  and Linux differs in the last few bits" (`:43-45`).
- `GltfSpec` only checks that its 16 frames export
  (`test/Senbazuru/Render/GltfSpec.hs:479-485`).
- Consequence: a re-expression that computes petal angles by formula instead
  of pasting the literals would, going by F8's Python evaluation, change the
  175° state's side angles. That fails this exact comparison unless the
  angles come through the manifest literals or the test gains a tolerance.

**F32. Progress fractions can move "round" angles.**

- Evaluated in Python, `175 * (90/175)` is `89.99999999999999`. The other
  sampled bird fractions round-trip (15, 30, 60, 120, 150, 175), as do the
  helmet's `(120/180)*180` and the crane's `(30/90)*90` and `(60/90)*90`.
- `birdStates` and `birdHinges` compute exactly this (`CheckedBird.hs:85`,
  `:166`), while labels print one decimal (`CheckedBird.hs:116-118`).
- A DSL that states "front petal at 90°" as an absolute angle yields
  different Doubles from the recipe. The SVG golden probably survives F27's
  rounding, but angle equality against the recipe's own formula would not.

## Implications for the design

1. **The interpreter owns the handoff (F11–F18); the language does not
   expose it.** Recipes should never write `nextPattern`. The PRD should
   list these as interpreter invariants:
   - carry angles and orders onto the cut material pattern;
   - drop `frameExtras` and stale faces;
   - re-fold rather than patch a `Folded` value;
   - re-resolve ids after any topology change;
   - refuse any move whose moving set contains the anchor;
   - run the stricter `CheckedBird`-style join check (positions, exact
     angles, topology, orders, material map) at every join.
2. **Choose one anchoring rule.** Prefer a material point (`fixedPanel`),
   which survives renumbering and does not depend on face order, over
   reordering faces (F13). The PRD should decide whether a move may declare
   its own stationary side, and what happens when it differs from the anchor.
3. **Address creases and faces geometrically; treat raw ids as resolved
   output, not input.** There are three precedents:
   - `at: [u, v]` panel names (F21);
   - `crease --from X,Y --to X,Y` (`docs/usage.md:773-790`);
   - `CraneWing`'s material segments (F5).

   The language needs an answer for irrational landmarks, such as snapping
   to existing vertices, expressions, or naming a vertex by its incident
   creases (sketch in (e)). Recipes should also be able to state their
   fixture guards (`expectedEdges`-style) when they rely on topology.
4. **Make direction explicit and hard to omit.** Accept `mountain` and
   `valley`, or a signed travel, but never a bare "fold". Document that at
   ±180 both give the same positions while order and approach differ (F3,
   F26). For multi-segment hinges, define the sign by *physical side*, and
   let the interpreter derive per-segment FOLD signs as `prepareFlapAlong`
   does (F4).
5. **Contact and order declarations belong to stages, with activation.**
   There are orders stable throughout, orders active only at landing, and
   orders that change mid-motion. The per-case manifest block cannot say
   this, and two cases already work around it (F22.2).
6. **Coupled moves as built-in named macros** with the five parts of F26:
   parameter, role formula, role binding, branch, optional certificate.
   Suggested set: `collapse`, `rabbitEar`, `petal`, and `together` for
   simultaneous stages.
   - Offer a validated escape hatch `coupled { param; role = f(param) }` for
     the embedded DSL. Label its result plainly as sampled (folding's
     `TornAt` and `loopsClose` plus pose contact), **not** certified.
   - The file format can name only registered macros. Certificates currently
     live in the study, and the library may not import it
     (`docs/architecture.md:201`), so the PRD must either register
     certificates from the study side or scope certified routes out of the
     CLI language.
7. **State carries holds.** A stage changes only the roles it names;
   everything else keeps the previous accepted value (F7). The manifest's
   copy-paste is exactly where drift creeps in (F8).
8. **Choose stackings by predicate, not index** (F19). An index is acceptable
   only as a resolved, reported value.
9. **Expected refusals are first-class** (F20), for example
   `expectRefused (fold lr (valley 180))`. Tests already depend on them, and
   they document which direction is the physical one.
10. **Separate motion from illustration.** Poses to draw, cameras and page
    titles are presentation. Keep the motion identical across views. Specify
    pose arithmetic (`start + progress × travel`) so that "halfway" and "90°"
    have one meaning (F16, F32).
11. **Acceptance strategy.**
    - Use F28 and F29 unchanged as the bar for re-expressing blintz, helmet,
      crane and the certified bird.
    - Use F27 goldens as a strong but not guaranteed byte-for-byte bar. Any
      golden diff must be read before accepting, per AGENTS.md.
    - For `bird-base-sequence.fold`, decide up front: keep the literal angles
      in the re-expression, regenerate the fixture from formulas (a reviewed
      change of angles), or relax the exact angle comparison. F8 says the
      formula route changes at least one state.
12. **Keep the angle-table level as a compilation target.** A resolved,
    per-state full angle list is what `StudyCase`, `buildCaseSequence` and
    the CLI's `render --steps` already consume (`docs/architecture.md:436-441`).
    The DSL could compile down to it, which gives a debuggable intermediate
    form.

## Open questions

1. Which blintz direction is canonical: the fixture's mountains (flap
   recipe) or the manifest's upward folds? Should one route be changed so
   the repo stops disagreeing with itself (F3)?
2. Should a stage be able to move the anchor, for instance a turnover as in
   the frog guide (`BasicBaseGallery.hs:126`)? Or is re-orientation always
   presentation, applied after the check?
3. How should the file language name vertices at irrational coordinates
   without exposing ids (F9, (e))?
4. How does a macro bind roles on an arbitrary pattern rather than a known
   fixture? Is "degree-4 vertex plus which ray is the mountain" enough for
   rabbit ears and collapses (`docs/notes/rabbit-ear-motion.md:16-27`)?
5. Should `cases.json` be replaced by the file language, or kept as the
   compiled angle-table form (implication 12)?
6. How should landing-only orders be declared, and can they be derived from
   the approach instead of written (`docs/notes/checked-square-collapse.md:44-50`)?
7. Is there a route to certificates generated from a macro's formula, or do
   certified routes stay study-only?
8. The flap recipes export `materialFrame` and the manifest exports
   `surfaceFrame` plus reassigned creases (F23). Which should the CLI
   language produce?

## Unverified

- **Why the manifest literals differ from the formulas at petal t = 175 and
  rabbit ear m = 30 (F8).** Candidates: generation on another platform, a
  different but equivalent expression, or different evaluation order. None
  was checked. The comparison ran in Python 3 on this Mac, not GHC. Whether
  GHC's `sin`/`atan2` give the same bits as Python's here was not tested.
- **Whether GHC gives `89.99999999999999` for `175 * (90/175)` (F32).** Only
  Python was run. IEEE binary64 multiplication and division are correctly
  rounded, so GHC is expected to agree, but no Haskell was compiled or run.
- **Negative zero in certified exports.**
  - `birdAngles t 0` evaluates `-v` with `v = 0.0`, and `collapseAngles 0`
    evaluates `-v` likewise. That should give `-0.0` entries.
  - Python gives `-0.0` for the same expression.
  - Whether aeson then writes `-0.0` into `checked-petal/sequence.fold`, and
    whether a DSL writing `0` would differ textually in exported FOLD, was
    not checked: no build output exists locally.
  - Tests compare with `Eq`, where `-0.0 == 0.0` holds (AGENTS.md gotcha).
- **Byte-identical SVG goldens for a re-expression.** F27's rounding argument
  is reasoning, not a run.
- **The Foschi, Hull and Ku paper** is cited only through
  `docs/notes/rabbit-ear-motion.md:22-27`. I did not fetch it.
- **Extra JSON keys.** I assume unknown keys in `cases.json` entries are
  silently ignored, based on the aeson `withObject` / `.:` parser shape
  (`StudyCase.hs:75-76`, `ContactSpec.hs:28-33`). No test was run to confirm.
- **Traced face order.** The mapping from traced blintz face indices to
  manifest panel names ("lower-right" and so on) was inferred from the edge
  table and the spec's pairing (`BlintzSequenceSpec.hs:73`). The tracer was
  not run.
