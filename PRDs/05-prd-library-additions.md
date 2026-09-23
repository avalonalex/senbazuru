# 05 — Library additions the runner needs

Written 2026-09-15 against `568dcb6`. Nothing here is implemented. Code links
are to lines read at that commit. [00](00-overview.md) starts the series;
[02](02-language-semantics.md) owns what a move *means*; this file owns the
changes to `src/Senbazuru/` that let a program perform it.

Decisions are cited from [decisions.md](decisions.md), the current decision
record; where this file and that record disagree, the record wins. The decisions
this file rests on:

| Decision | Title | Items here |
| --- | --- | --- |
| [D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs) | The runner owns the state, its start and the handoffs | L7, L10 |
| [D4](decisions.md#d4-written-frames-follow-the-state-rule) | Written frames follow the state rule | L1 |
| [D5](decisions.md#d5-presentation-and-the-readers-side) | Presentation and the reader's side | L3, L14 |
| [D6](decisions.md#d6-crease-graphs-grow-between-frames) | Crease graphs grow between frames | L5 |
| [D8](decisions.md#d8-folding-some-layers) | Folding some layers | L2, L7–L11 |
| [D9](decisions.md#d9-macro-moves-as-named-angle-relations) | Macro-moves as named angle relations | L13 |
| [D10](decisions.md#d10-assurance-as-evidence-values) | Assurance as evidence values | L4, L13, L14 |
| [D11](decisions.md#d11-stacking-choices-are-relations) | Stacking choices are relations | L12 |
| [D14](decisions.md#d14-material-consumption) | Material consumption | L4 |
| [D15](decisions.md#d15-graduation-from-study-to-library) | Graduation from study to library | L13 |
| [D16](decisions.md#d16-testing-and-acceptance) | Testing and acceptance | L3, L13 |
| [D19](decisions.md#d19-realistic-rendering) | Realistic rendering | L15 |
| [D20](decisions.md#d20-errors) | Errors | L6, [Errors](#errors) |
| [D22](decisions.md#d22-figures-holding-several-moves) | Figures holding several moves | L8 |
| [D23](decisions.md#d23-the-sequence-modules-and-where-run-lives) | The Sequence modules and where Run lives | L4 |

## Summary

The *runner* ([glossary-additions](glossary-additions.md#running-a-sequence))
performs a sequence move by move over the existing fold solver. Today the solver
creases, folds and checks one turn about a *hinge*, the line paper turns about
([glossary-additions](glossary-additions.md#origami)), but only for a caller already holding
raw edge and *face* (flat region between creases) ids of a *cut pattern*: the
[crease pattern](../docs/glossary.md#origami) after crossing creases are split
and faces traced, the only numbering folding's results refer to
([`Folding.hs:286-302`](../src/Senbazuru/Origami/Folding.hs#L286-L302)). Fifteen
small additions close the gap. Two are new modules; the rest sit beside the
function they extend. **None changes an existing output**, and each item says
why.

| # | Addition | Module | Decision | Milestone |
| --- | --- | --- | --- | --- |
| [L1](#l1-at-rest-foldqueryatrest-and-assignmentatrest) | `atRest`, `assignmentAtRest` | `Fold.Query` | [D4](decisions.md#d4-written-frames-follow-the-state-rule) | M2, before the writer |
| [L2](#l2-creaseallalongwith-and-newcreaseangle) | `creaseAllAlongWith`, `NewCreaseAngle` | `Fold.Creasing`, `Fold.Crossings` | [D8](decisions.md#d8-folding-some-layers) | M2 |
| [L3](#l3-fitrigid-proper-rotations-and-the-whole-model-classification) | `fitRigid`, `isProperRotation`, whole-model classification | `Geometry.Rigid`, `Origami.Step` | [D5](decisions.md#d5-presentation-and-the-readers-side) | M2 |
| [L4](#l4-flapstationaryface-flapposeat-and-routepose) | `flapStationaryFace`, `flapPoseAt`, `RoutePose` | `Origami.Flap`, `Origami.Route` (new) | [D10](decisions.md#d10-assurance-as-evidence-values), [D14](decisions.md#d14-material-consumption) | M2 / M6 or M7b |
| [L5](#l5-motionsacross-creasestocome-and-a-non-convex-point-test) | `motionsAcross`, `creasesToCome`, `insideRing` | `Origami.Step`, `Geometry.Polygon` | [D6](decisions.md#d6-crease-graphs-grow-between-frames) | M3 |
| [L6](#l6-linestopsonthemodel-carries-its-point) | `LineStopsOnTheModel` carries its point | `Origami.ThroughLayers`, `Fold.Query` | [D20](decisions.md#d20-errors) | before M4 |
| [L7](#l7-the-untouched-fold-check-shared) | `untouchedFold`, `StartError` | `Origami.Folding` | [D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs), [D8](decisions.md#d8-folding-some-layers) | M4 |
| [L8](#l8-creaselayersthrough) | `creaseLayersThrough`, `Creased` | `Origami.ThroughLayers` | [D8](decisions.md#d8-folding-some-layers) | M4 |
| [L9](#l9-ordered-cover) | `orderedCover` | `Origami.Visible` | [D8](decisions.md#d8-folding-some-layers) | M4 |
| [L10](#l10-carryorders) | `carryOrders` | `Origami.ThroughLayers` | [D8](decisions.md#d8-folding-some-layers) | M4 |
| [L11](#l11-the-selection-rule-lives-in-the-library) | `selectLayers` | `Origami.ThroughLayers` | [D8](decisions.md#d8-folding-some-layers) | M4 |
| [L12](#l12-stackingwhere) | `stackingWhere` | `Origami.Stacking` | [D11](decisions.md#d11-stacking-choices-are-relations) | M4 |
| [L13](#l13-origamimacro-checkedmacro-and-macroposeat) | `CheckedMacro`, `macroPoseAt` | `Origami.Macro` (new) | [D9](decisions.md#d9-macro-moves-as-named-angle-relations), [D10](decisions.md#d10-assurance-as-evidence-values) | M5 |
| [L14](#l14-eq-on-flap-values-and-prepareflaptoward) | `Eq` on `FlapMotion` and `CheckedFlap`; `prepareFlapToward`, `Toward` | `Origami.Flap` | [D5](decisions.md#d5-presentation-and-the-readers-side), [D10](decisions.md#d10-assurance-as-evidence-values) | M2 |
| [L15](#l15-foldedwalk) | `foldedWalk` | `Origami.Folding` | [D19](decisions.md#d19-realistic-rendering) | M7b |

## Problem and evidence

Each line is something a runner cannot do with today's exports.

- **Creasing returns no ids.** `creaseAllAlong` returns a `Frame`
  ([`Creasing.hs:138`](../src/Senbazuru/Fold/Creasing.hs#L138)); cutting replaces
  each cut edge in place by its pieces, shifting later ids
  ([`Crossings.hs:343-347`](../src/Senbazuru/Fold/Crossings.hs#L343-L347)). The
  one precedent writes its new creases as `U` and finds its new hinge as
  "every `Unassigned` edge", and checks there are four
  ([`CraneWing.hs:65-66`](../study/fold-material/CraneWing.hs#L65-L66)).
- **Creasing folds new creases at once**: a new mountain or valley gets ±180
  whenever the angle array exists
  ([`Creasing.hs:290-292`](../src/Senbazuru/Fold/Creasing.hs#L290-L292),
  [`:316-320`](../src/Senbazuru/Fold/Creasing.hs#L316-L320)). The *working
  pattern* keeps a new crease at 0 with its *intent assignment*, the M or V it
  was made as ([glossary-additions](glossary-additions.md#the-fold-format)).
- **Creasing through layers takes every layer and folds its own input**
  ([`ThroughLayers.hs:56-61`](../src/Senbazuru/Origami/ThroughLayers.hs#L56-L61),
  [`:227-229`](../src/Senbazuru/Origami/ThroughLayers.hs#L227-L229)), so faces
  chosen from the caller's own fold may be numbered differently.
- **Layer orders are lost across a crease.** FOLD's `faceOrders` say which of
  two overlapping faces lies above; creasing empties them
  ([`Creasing.hs:266`](../src/Senbazuru/Fold/Creasing.hs#L266)), and the crane
  recipe re-solves and picks index 2 of five
  ([`CraneWing.hs:75-78`](../study/fold-material/CraneWing.hs#L75-L78)).
- **Step inference refuses a growing graph and counts a turn-over as a motion**
  ([`Step.hs:94-96`](../src/Senbazuru/Origami/Step.hs#L94-L96),
  [`:30-34`](../src/Senbazuru/Origami/Step.hs#L30-L34)).
- **Flap gives positions, not per-face motions, and hides its stationary face**
  ([`Flap.hs:290-294`](../src/Senbazuru/Origami/Flap.hs#L290-L294),
  [`:49-59`](../src/Senbazuru/Origami/Flap.hs#L49-L59)).
- **Flap's travel sign depends on that hidden face.** Travel is the change in the
  *first* listed segment's angle, and each other segment's sign follows its own
  stationary face's ring ([`Flap.hs:14-16`](../src/Senbazuru/Origami/Flap.hs#L14-L16),
  [`:208-216`](../src/Senbazuru/Origami/Flap.hs#L208-L216)), so a caller holding
  only "valley" cannot choose it (L14).
- **Flap's values cannot be compared**: `FlapMotion` and `CheckedFlap` derive only
  `Show` ([`Flap.hs:93`](../src/Senbazuru/Origami/Flap.hs#L93),
  [`:96`](../src/Senbazuru/Origami/Flap.hs#L96)).
- **Folding discards its tree**: `spanningWalk` returns placements and not which
  face placed which
  ([`Folding.hs:572-577`](../src/Senbazuru/Origami/Folding.hs#L572-L577)).
- **A library message names a CLI flag**
  ([`ThroughLayers.hs:194-195`](../src/Senbazuru/Origami/ThroughLayers.hs#L194-L195)).
- **Nothing checks a rigid motion is a rotation**: `Rigid` "will hold any 3×3
  matrix … and nothing here checks"
  ([`Rigid.hs:24-26`](../src/Senbazuru/Geometry/Rigid.hs#L24-L26)).

## Goals

1. Every addition the runner needs, each with a signature, its reason in the
   code, semantics, refusals and acceptance tests that name what turns them red.
2. One policy per question, in the module that already owns it.
3. Existing outputs unchanged: the tracked *goldens*, whole outputs compared
   byte for byte, counted and checked as in
   [09 §1.2](09-testing-and-acceptance.md#12-tracked-goldens-stay-byte-identical),
   plus `crease` and `render --steps`.

## Non-goals

| Out of scope | Where it lives |
| --- | --- |
| What references, moves, selectors and relations mean | [02](02-language-semantics.md) |
| `StepNote`, arrow heads, `Symbol` | [06](06-prd-step-diagrams.md) |
| Settles, holds, rest angles | [07](07-prd-material-consumption.md) |
| Unifying "hair" tolerances; `existingAt` first-versus-nearest | follow-up issues, [decisions §10](decisions.md#10-corrections) items 13 and 17 and [10](10-roadmap-risks-questions.md); each item here names the tolerance it reuses |
| Moving `foldAnglesOf` into `Fold.Query` | [#111](https://github.com/avalonalex/senbazuru/issues/111) |
| A general coupled-angle solver | [#55](https://github.com/avalonalex/senbazuru/issues/55) |

## Users and scenarios

Users: `Sequence.Run` (every item); `Render.Sequence` (L3, L5,
[06](06-prd-step-diagrams.md)); the study consumer and animated glTF (L4, L13,
L15, [07](07-prd-material-consumption.md), [08](08-prd-realistic-rendering.md));
`senbazuru crease --folded` ([`Cli.hs:761`](../app/Senbazuru/Cli.hs#L761)),
unchanged except L6's wording.

The scenario using most of them is "fold the top flap down along this line" on a
*flat state*, every face in one plane
([glossary-additions](glossary-additions.md#words-the-prds-narrow)):

1. L9 orders the faces under the line from the *reader's side*
   ([glossary-additions](glossary-additions.md#running-a-sequence));
2. L11 picks faces;
3. L8 creases them at 0 (L2) and returns ids;
4. L10 carries layer orders onto the new faces;
5. the runner refolds and hands `Flap` the ids and the side the paper turns
   towards (L14);
6. L4 names the face that stayed still.

## Requirements and design

Three rules hold for every item:

- **R-05-1.** Every tracked golden is byte-identical after each PR, checked as in
  [09 §1.2](09-testing-and-acceptance.md#12-tracked-goldens-stay-byte-identical).
- **R-05-2.** Every new error type or constructor gets its `Explain` wording in
  its defining module, as a lower-case fragment with no full stop
  ([`Explain.hs:62-68`](../src/Senbazuru/Explain.hs#L62-L68)). Wrappers call
  `explain` on what they wrap ([`:41-43`](../src/Senbazuru/Explain.hs#L41-L43)).
  See [Errors](#errors).
- **R-05-3.** No item introduces a tolerance; each names the one it reuses.

---

### L1. At rest: `Fold.Query.atRest` and `assignmentAtRest`

**Module.** `Senbazuru.Fold.Query`, where #111 wants "what a file means" decided.

```haskell
-- SKETCH
atRest :: Double                 -- τ, in degrees
atRest = 1e-10

assignmentAtRest :: Assignment -> Double -> Assignment
assignmentAtRest a angle = case a of
  Border -> Border
  Cut -> Cut
  Join -> Join
  _ | angle < negate atRest -> Mountain
    | angle > atRest -> Valley
    | otherwise -> Flat
```

**Why.** The *state rule* writes each crease's assignment from its angle
([glossary-additions](glossary-additions.md#the-fold-format);
[D4](decisions.md#d4-written-frames-follow-the-state-rule), owned by
[02](02-language-semantics.md)). Its threshold exists twice, unnamed:
[`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278) counts a crease as a
feature when `abs angle > 1e-10`, and
[`StudyCase.hs:208`](../study/fold-material/StudyCase.hs#L208) runs the rule the
other way, turning `F` beyond 1e-10 into M or V. What it corrects, from
`python3 -c 'import json;d=json.load(open("examples/quarter-fold-steps.fold"));[print(i,[e for e,(a,g) in enumerate(zip(f["edges_assignment"],f["edges_foldAngle"])) if a in "MV" and g==0]) for i,f in enumerate([d]+d["file_frames"])]'`:
M or V at angle 0 on edges 8–11 of the key frame and 9, 11 of frame 1.

**Semantics.**

- **R-05-4.** `B`, `C`, `J` pass through; `M`, `V`, `F`, `U` become `M` below
  −τ, `V` above τ, `F` otherwise. Angles are FOLD degrees
  ([`Folding.hs:488-490`](../src/Senbazuru/Origami/Folding.hs#L488-L490)).
- **R-05-5.** τ = 1e-10°, equal to both literals, so migrating either later
  changes no comparison ([D4](decisions.md#d4-written-frames-follow-the-state-rule),
  [C29](decisions.md#changes-since-draft-v2)).
- Total, so `NaN` becomes `F`. The writer refuses non-finite angles first
  ([#58](https://github.com/avalonalex/senbazuru/issues/58) item 3).

**The line that looks wrong.** The writer writes `F` with its angle as *exactly*
0, even when the working angle was 5e-11 ([02](02-language-semantics.md)). That
keeps `Stacking.creaseDirections`
([`Stacking.hs:705-727`](../src/Senbazuru/Origami/Stacking.hs#L705-L727)), with
its exact `d > 0` test, agreeing with the rule: it reads 0 and falls back to
`F`, which names no direction. Its header gains a sentence saying so.

**Refusals.** None.

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| Property over every `Assignment` and finite angle: `B`/`C`/`J` exactly when the input is; otherwise `M` iff < −τ, `V` iff > τ | `U` passes through, or τ is applied to `B` |
| `quarter-fold-steps.fold`'s key frame: edges 8–11 map to `F` | M/V at 0 is kept |
| On a frame rewritten by the rule with `F` angles set to 0, `creaseDirections` gives `Just` on every `M` or `V` edge and `Nothing` on every `F` edge (borders give `Nothing` too, [`Stacking.hs:719-726`](../src/Senbazuru/Origami/Stacking.hs#L719-L726), so they are not asserted) | rule and direction reader drift |

**Outputs unchanged.** Nothing existing calls it. Migrating the two literals
([01 §4.6](01-architecture.md#46-111)) at τ = 1e-10 is a rename.

---

### L2. `creaseAllAlongWith` and `NewCreaseAngle`

**Modules.** `Fold.Creasing`; `Fold.Crossings` gains a tracked variant.

```haskell
-- SKETCH
data NewCreaseAngle = AtRest | FlatForAssignment

creaseAllAlongWith ::
  NewCreaseAngle -> [(V2, V2, Assignment)] -> Frame -> Either FoldError (Frame, [[EdgeId]])

creaseAllAlong segments = fmap fst . creaseAllAlongWith FlatForAssignment segments

-- Fold.Crossings: each input edge id to its pieces, in order from its first end
withPlanarFacesTracked :: Frame -> Either FoldError (Frame, IntMap [EdgeId])
```

**Why.** The ids must come from the cutting's own chains
([`Crossings.hs:343-347`](../src/Senbazuru/Fold/Crossings.hs#L343-L347)), because
counts cannot say which piece belongs to which request. On
`examples/diagonal-cp.fold`, `jq -c '.vertices_coords, .edges_vertices'` prints
`[[0,0],[1,0],[1,1],[0,1]]` and `[[0,1],[1,2],[2,3],[3,0],[3,1]]`: four borders,
then the valley diagonal as edge 4. Batch: a valley (0, 1/2)→(1/2, 0), a mountain
(0, 0)→(1, 1).

**The line that looks like a typo** is the last row: the file's own diagonal,
edge 4, comes out as edges 6 and 7, because every edge cut before it pushes its
pieces along. In the "rebuild" row, `a→[…]` reads "input edge *a* became these
edges".

| Stage | Result | Code |
| --- | --- | --- |
| look up each end | (0, 1/2) and (1/2, 0) are not existing vertices, so they become vertices 4 and 5; (0, 0) and (1, 1) are vertices 0 and 2 | [`Creasing.hs:231-241`](../src/Senbazuru/Fold/Creasing.hs#L231-L241) |
| append | edge 5 = vertices 4–5, edge 6 = vertices 0–2 | [`:252-255`](../src/Senbazuru/Fold/Creasing.hs#L252-L255) |
| crossings | edge 4 (vertices 3–1) meets edge 6 at (1/2, 1/2): vertex 6; edge 5 meets edge 6 at (1/4, 1/4): vertex 7 | [`Crossings.hs:180-213`](../src/Senbazuru/Fold/Crossings.hs#L180-L213) |
| cut, edge by edge | edge 0 at vertex 5; edge 3 at vertex 4; edge 4 at vertex 6; edge 5 at vertex 7; edge 6 at vertices 7 then 6 | [`:267-271`](../src/Senbazuru/Fold/Crossings.hs#L267-L271) |
| rebuild | 0→[0,1], 1→[2], 2→[3], 3→[4,5], 4→[6,7], 5→[8,9], 6→[10,11,12] | [`:343-347`](../src/Senbazuru/Fold/Crossings.hs#L343-L347) |

The valley is `[8, 9]`, the mountain `[10, 11, 12]`: 13 edges, 5 new pieces,
and nothing in the counts says 2 + 3 rather than 3 + 2. Evidence:
derived from the cited lines and reproduced by a Python re-implementation of
them (not senbazuru); **UNVERIFIED in Haskell** until the first test runs.

**Semantics.**

- **R-05-6.** `FlatForAssignment` is today's code path, byte for byte.
- **R-05-7.** `AtRest` writes every new piece at 0 with its requested
  assignment. Pieces of cut *old* edges keep their parent's angle, as now
  ([`Crossings.hs:352-358`](../src/Senbazuru/Fold/Crossings.hs#L352-L358)).
- **R-05-8.** `AtRest` on a frame without `edges_foldAngle` writes the whole
  array: existing edges get what `foldAnglesOf` reads for an absent array (M
  −180, V +180, else 0,
  [`Folding.hs:507-532`](../src/Senbazuru/Origami/Folding.hs#L507-L532)), new
  pieces 0. Leaving it absent would fold the new valley to 180
  ([C30](decisions.md#changes-since-draft-v2)).
- **R-05-9.** List *i* holds request *i*'s pieces from its first end. When
  nothing is cut the pieces are the appended ids
  ([`Crossings.hs:137-138`](../src/Senbazuru/Fold/Crossings.hs#L137-L138)); an
  empty batch returns `(fr, [])`
  ([`Creasing.hs:152-156`](../src/Senbazuru/Fold/Creasing.hs#L152-L156)).

**Refusals.** Today's `FoldError`s, in today's order.

**Rejected.** Ids from counts (above). The U-edge marker, writing new creases as
`U` so they can be found afterwards, as `CraneWing` does: it breaks on any file
that already has a `U` edge
([10 §7.2](10-roadmap-risks-questions.md#72-new-issues-to-file), row 14).
Changing `creaseAllAlong`'s own angle to 0:
it moves [`CreasingSpec.hs:109-114`](../test/Senbazuru/Fold/CreasingSpec.hs#L109-L114)
and "The creases are written at plus or minus 180"
([`ThroughLayersSpec.hs:134-135`](../test/Senbazuru/Origami/ThroughLayersSpec.hs#L134-L135)).

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| The batch above returns `[[8,9],[10,11,12]]` | ids come from counts, or chains are regrouped |
| `creaseAllAlong` equals `fst <$> creaseAllAlongWith FlatForAssignment` on every `CreasingSpec` and `ThroughLayersSpec` input | the refactor moves an angle or id |
| Under `AtRest`, every returned id has angle 0 and its requested assignment, every other edge its parent's angle | a cut old crease is zeroed |
| Under `AtRest`, on every `CreasingSpec` and `ThroughLayersSpec` input that folds: folding the output places the input's vertices as folding the input does, within `sheetTolerance` ([`Folding.hs:847-848`](../src/Senbazuru/Origami/Folding.hs#L847-L848)), after the output's faces are reordered so that a face whose every vertex lies in the input's face 0 comes first | a new crease gets ±180, or an absent array stays absent |

The reordering in the last row is not optional. Folding holds its first face
still ([`Folding.hs:583-585`](../src/Senbazuru/Origami/Folding.hs#L583-L585)),
and creasing re-traces faces in edge order
([`Faces.hs:375-384`](../src/Senbazuru/Fold/Faces.hs#L375-L384)). On
`quarter-fold.fold`, `jq -c '.edges_vertices[0], .faces_vertices[0]'` prints
`[0,4]` and `[8,4,1,5]`: the first traced face is the one beside edge 0, not
the file's face 0, so without it the two folds differ by a rigid motion of the
whole model. `CraneWing` reorders for the same reason
([`CraneWing.hs:61-63`](../study/fold-material/CraneWing.hs#L61-L63)).

**Outputs unchanged.** `crease` and `creaseThroughLayers` still reach
`creaseAllAlong`; no golden is produced by creasing.

**Milestone.** M2 ([D8](decisions.md#d8-folding-some-layers),
[C27](decisions.md#changes-since-draft-v2)). M2 already folds along new
constructions on the flat sheet, and today's `creaseAllAlong` writes such a crease
at ±180, already folded, with no ids to find it by (see
[Problem and evidence](#problem-and-evidence)), which leaves `Flap` nothing to
turn and nothing to name.

---

### L3. `fitRigid`, proper rotations, and the whole-model classification

**Modules.** `Geometry.Rigid`; `Origami.Step`.

```haskell
-- SKETCH, Senbazuru.Geometry.Rigid
isProperRotation :: Mat3 -> Bool        -- rows orthonormal and det = +1, each within 1e-12
fitRigid :: [(V3, V3)] -> Maybe Rigid

-- SKETCH, Senbazuru.Origami.Step
wholeModelMotion :: Frame -> Frame -> Either FoldError (Maybe Rigid)
```

**Why.** *Presentation*, the rigid motion turning the whole model for the reader
([glossary-additions](glossary-additions.md#running-a-sequence)), must be a
*proper rotation*: a mirrored model folds fine and is the wrong model
([glossary-additions](glossary-additions.md#geometry)). `Rigid(..)` and
`Mat3(..)` are exported unchecked
([`Rigid.hs:27-41`](../src/Senbazuru/Geometry/Rigid.hs#L27-L41)); nothing fits a
motion to point pairs; and `Step`'s header counts a turn-over as a motion
([`Step.hs:30-34`](../src/Senbazuru/Origami/Step.hs#L30-L34)), so a written
turn-over would get an arrow.

**Semantics.**

- **R-05-10.** `isProperRotation m`: `mᵀm` is the identity and `det m = 1`, each
  within 1e-12. The determinant alone would accept `diag(2, 1/2, 1)`.
- **R-05-11.** `fitRigid`: take `a` the first source point, `b` the farthest
  from `a`, `c` the farthest from line `ab` (`Nothing` if either distance is
  within tol). Build an orthonormal basis F from `a`, `b`, `c` and a basis G
  from their target points, each with its third axis the cross product of its
  first two; `R = G·Fᵀ` turns F's axes onto G's. Accept only if every pair maps
  within tol and `isProperRotation R`. Tol = `1e-9 × max 1 (modelSpan sources)`,
  [`Step.hs:141`](../src/Senbazuru/Origami/Step.hs#L141)'s, where `modelSpan` is
  the points' largest extent along any axis
  ([`V3.hs:72-73`](../src/Senbazuru/Geometry/V3.hs#L72-L73)). Built by the same
  right-handed rule on both sides, `R` always has determinant +1, so inside
  `fitRigid` the `isProperRotation` check only catches a construction bug; its
  real use is on a `Rigid` built elsewhere, since `Rigid(..)` is exported
  unchecked.
- **The line that looks like a typo.** On a flat model at z = 0, the mirror
  (x, y, z) ↦ (−x, y, z) and the half turn (x, y, z) ↦ (−x, y, −z) give identical
  coordinates. The cross-product axis makes `fitRigid` return the half turn, which
  is right: paper cannot make the mirror.
- **R-05-12′** ([D5](decisions.md#d5-presentation-and-the-readers-side),
  [C26](decisions.md#changes-since-draft-v2)). `motionsBetween` returns `[]` for a
  presentation change: **some** vertex moves by more than tol, and one proper
  rigid motion (`fitRigid`) maps every vertex within tol. Identical frames still
  give `[]`, since nothing moves. `wholeModelMotion` exposes the motion for pages
  ([06](06-prd-step-diagrams.md)).
- **Why "some" vertex and not "every".** A turn-over leaves the vertices on its
  own axis where they were. D5's `left-right` turn-over maps (x, y, z) to
  (2cx − x, y, 2cz − z), so a flat vertex with x = cx does not move, and
  `python3 -c 'import json;[print(f,sum(v[0]==(min(u[0] for u in V)+max(u[0] for u in V))/2 for v in V),len(V)) for f in ["quarter-fold-steps","quarter-fold","bird-base","blintz-base"] for V in [json.load(open("examples/%s.fold"%f))["vertices_coords"]]]'`
  prints `quarter-fold-steps 3 9`, `quarter-fold 3 9`, `bird-base 5 13` and
  `blintz-base 2 8`: vertices on x = cx, of all vertices. A rule asking every
  vertex to move would give the runner's own turn-overs of these sheets arrows,
  and is rejected. A flap turn cannot qualify under "some": its stationary face
  keeps three non-collinear vertices still
  ([`Flap.hs:346-348`](../src/Senbazuru/Origami/Flap.hs#L346-L348)), so the only
  fit is the identity, which the moved vertices contradict.
- **R-05-13.** [`Step.hs:30-34`](../src/Senbazuru/Origami/Step.hs#L30-L34) is
  replaced in the same PR by
  [01 §4.13](01-architecture.md#413-srcsenbazuruorigamistephs30-34)'s paragraph,
  which says "When some vertex moves", as R-05-12′ does
  ([decisions §3](decisions.md#3-recorded-text-this-design-changes) row 13).

**Refusals.** None: a failed fit is `Nothing`.

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| `fitRigid` recovers a quarter turn, an in-plane half turn and an eighth turn from `rotationAbout` of `quarter-fold-steps.fold`'s key frame (2D, so flat) | only G's third axis is flipped: on a flat frame that mirror still maps every pair, and only the `isProperRotation R` guard refuses it |
| A frame of `bird-base-sequence.fold` that is not flat, reflected x ↦ −x, gives `Nothing`. Its non-flat frames are `file_frames[1]` to `[14]` (`--frame 2` to `15`): `python3 -c 'import json;d=json.load(open("examples/bird-base-sequence.fold"));print([k for k,f in enumerate(d["file_frames"]) if max(v[2] for v in f["vertices_coords"])-min(v[2] for v in f["vertices_coords"])>1e-9])'` prints `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]` | the every-pair check is dropped, so the fit returns a rotation instead of `Nothing` |
| `isProperRotation` is false for `diag(2, 1/2, 1)` and for a mirror | only the determinant is checked |
| `motionsBetween f f == Right []` ([`StepSpec.hs:92`](../test/Senbazuru/Origami/StepSpec.hs#L92), kept) | the identity is classified |
| The quarter fold turned over left-right by D5's formula gives `[]` | the rule asks every vertex to move, so the three axis vertices block classification |

**Outputs unchanged.** Any rigid motion keeps every pairwise distance, and
`python3 -c 'import json,glob,math,itertools as I;[print(p,sum(any(math.dist(x,y)>t for x,y in zip(P,Q)) and all(abs(math.dist(P[i],P[j])-math.dist(Q[i],Q[j]))<=2*t for i,j in I.combinations(range(len(P)),2)) for a,b in zip(F,F[1:]) for P,Q in [([v+[0]*(3-len(v)) for v in a["vertices_coords"]],[v+[0]*(3-len(v)) for v in b["vertices_coords"]])] for t in [1e-9*max(1,max(max(x[i] for x in P)-min(x[i] for x in P) for i in range(3)))]),len(F)-1) for p in sorted(glob.glob("examples/*.fold")) for d in [json.load(open(p))] if "file_frames" in d for F in [[f for f in [d]+d["file_frames"] if f.get("vertices_coords")]]]'`
prints `0 15` for `bird-base-sequence.fold` and `0 2` for
`quarter-fold-steps.fold`: no consecutive pair keeps every distance while
something moves. The goldens drawn with inferred arrows are `checked-flap`,
`checked-flat-flap`, `checked-stack-flap` and `checked-aligned-stack`
([`FlapSpec.hs:292`](../test/Senbazuru/Origami/FlapSpec.hs#L292),
[`:312`](../test/Senbazuru/Origami/FlapSpec.hs#L312),
[`:322`](../test/Senbazuru/Origami/FlapSpec.hs#L322)) and `quarter-fold-steps`
([`SvgSpec.hs:133`](../test/Senbazuru/Render/SvgSpec.hs#L133)). Each pair in them
is a flap turn with a stationary face held still, so the rule does not classify
it. No existing golden draws `bird-base-sequence.fold` with arrows, so a PR before
this one pins `bird-base-sequence-arrows.svg`, drawn by today's code; this item's
PR keeps it and `quarter-fold-steps.svg` byte-identical and compares
`render --steps --arrows` on both multi-frame examples by hand with `cmp`
([D16](decisions.md#d16-testing-and-acceptance),
[C70](decisions.md#changes-since-draft-v2),
[09 §1.3](09-testing-and-acceptance.md#13-multi-frame-examples-draw-the-same-step-pages)).

**Milestone.** M2.

---

### L4. `flapStationaryFace`, `flapPoseAt` and `RoutePose`

**Modules.** `Origami.Flap`; a new `Origami.Route` holding one type. `RoutePose`
lives there, not in `Sequence.Record`, because `Origami.Flap` may not import
`Sequence.*` ([decisions §2](decisions.md#2-shape), rows 4 and 6); `Sequence.Record`
re-exports it ([D10](decisions.md#d10-assurance-as-evidence-values),
[D23](decisions.md#d23-the-sequence-modules-and-where-run-lives),
[C28](decisions.md#changes-since-draft-v2)).

```haskell
-- SKETCH, Senbazuru.Origami.Route
data RoutePose = RoutePose
  { routeAngles :: [Double], routeSurface :: Surface V2, routePlacements :: IntMap Rigid }

-- SKETCH, Senbazuru.Origami.Flap
flapStationaryFace :: CheckedFlap -> FaceId
flapPoseAt :: CheckedFlap -> Double -> Either FlapError RoutePose
flapAt checked progress = routeSurface <$> flapPoseAt checked progress
```

**Why.** A *move record* names the face a move held still
([glossary-additions](glossary-additions.md#running-a-sequence),
[D14](decisions.md#d14-material-consumption));
`FlapMotion` stores it ([`Flap.hs:85`](../src/Senbazuru/Origami/Flap.hs#L85),
chosen at [`:195`](../src/Senbazuru/Origami/Flap.hs#L195)) and nothing exports
it. Animation keys and `rigid-pose` grips need one rigid motion per face along
the route ([D10](decisions.md#d10-assurance-as-evidence-values)); `surfaceAt` computes them
([`:345`](../src/Senbazuru/Origami/Flap.hs#L345)) and discards them, and
re-deriving them adds a `foldFrameWith` call to the roughly seven a checked step
already makes
([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
"From reading the code (counts, not timings)", finding 6).

**Semantics.**

- **R-05-14.** `flapStationaryFace` returns `stationaryFace`, numbered as the
  `Folded` given to `prepareFlapAlong`
  ([`Flap.hs:9-10`](../src/Senbazuru/Origami/Flap.hs#L9-L10)).
- **R-05-15.** `surfaceAt` becomes one internal function returning its angles
  ([`:343`](../src/Senbazuru/Origami/Flap.hs#L343)), fold
  ([`:345`](../src/Senbazuru/Origami/Flap.hs#L345)) and *stationary correction*:
  refolding puts the faces somewhere new, and the correction is the rigid motion
  that puts the held face back where it was before the refold
  (``before `after` inverse afterPose``,
  [`:346-348`](../src/Senbazuru/Origami/Flap.hs#L346-L348)). `flapPoseAt`
  returns those angles, `flapAt`'s surface with its orders
  ([`:292-294`](../src/Senbazuru/Origami/Flap.hs#L292-L294)), and every placement
  composed as ``correction `after` placement``. One `foldFrameWith` per call, as `flapAt`;
  progress outside [0, 1] refused as today
  ([`:340`](../src/Senbazuru/Origami/Flap.hs#L340)).

**Refusals.** Existing `FlapError`s only.

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| For every face *f* and vertex (u, v) of *f*, `applyRigid (placements ! f) (V3 u v 0)` equals that vertex's surface position within 1e-12 × `modelSpan` (the join tolerance, [`BlintzSequence.hs:69`](../study/fold-material/BlintzSequence.hs#L69)) | placements lack the correction |
| On each blintz turn, `flapStationaryFace` is face 0, the central square the recipe lists first ([`BlintzSequence.hs:44-47`](../study/fold-material/BlintzSequence.hs#L44-L47)) | the moving face is returned |
| `FlapSpec`, `BlintzSequenceSpec`, `HelmetSequenceSpec`, `CraneWingSpec` unchanged | a pose moves |

**Outputs unchanged.** `flapAt` keeps its fold and transform, so goldens drawn
through it (`checked-flap`, `checked-flat-flap`, `checked-stack-flap`,
`checked-aligned-stack`, `checked-blintz`, `checked-helmet`, `checked-crane`)
do not move.

**Milestone.** `flapStationaryFace` and `Origami.Route` at M2, for records
([decisions §8](decisions.md#8-milestones)); `flapPoseAt` with its first consumer,
M6 or M7b.

---

### L5. `motionsAcross`, `creasesToCome`, and a non-convex point test

**Modules.** `Origami.Step`; `Geometry.Polygon`.

```haskell
-- SKETCH
motionsAcross :: Frame -> Frame -> Either FoldError [Motion]
creasesToCome :: Frame -> Frame -> Either FoldError [(EdgeId, V3, V3)]
insideRing :: Double -> [V2] -> V2 -> Bool   -- Geometry.Polygon: any simple ring, either winding
```

**Why.** A book draws a move's arrow and fold-here line on the figure *before*
it ([`Step.hs:17-21`](../src/Senbazuru/Origami/Step.hs#L17-L21)), and a move that
creases gives the next frame more edges than that figure. `motionsBetween`
refuses unequal graphs ([`:94-96`](../src/Senbazuru/Origami/Step.hs#L94-L96)) and
compares angles by edge index ([`:150-159`](../src/Senbazuru/Origami/Step.hs#L150-L159)),
which L2's example shows is wrong after a cut. `strictlyInside` is for convex
anticlockwise polygons only
([`Polygon.hs:351-357`](../src/Senbazuru/Geometry/Polygon.hs#L351-L357)), and a
crease pattern's faces need not be convex.

**Semantics** ([D6](decisions.md#d6-crease-graphs-grow-between-frames); design B of
[gap-step-annotation-channel](research/gap-step-annotation-channel.md) "(c) Two
designs for a crease graph that grows"). Material coordinates come through
`surfaceFromFrame`: `senbazuru:material_coords`, or a flat crease pattern's own
x, y ([`Surface.hs:179-195`](../src/Senbazuru/Origami/Surface.hs#L179-L195)).
Material comparisons use the `Fold.Faces.tolerance` formula, 1e-9 × the bounding
box's diagonal ([`Faces.hs:248-251`](../src/Senbazuru/Fold/Faces.hs#L248-L251)),
on material points.

- **R-05-16.** Equal `edges_vertices` and `faces_vertices`: return
  `motionsBetween`; no material coordinates needed.
- **R-05-17.** Otherwise `before`'s vertices are a prefix of `after`'s, with
  exactly equal material coordinates; vertices are never renumbered
  ([`Crossings.hs:73-75`](../src/Senbazuru/Fold/Crossings.hs#L73-L75),
  [`Creasing.hs:254`](../src/Senbazuru/Fold/Creasing.hs#L254)).
- **R-05-18.** An added vertex on a `before` edge's material segment takes the
  interpolated position; one strictly inside exactly one `before` face's material
  ring (`insideRing`) takes that face's *affine map* (linear map plus shift) from
  material to position, built from three non-collinear corners, exact for a
  rigid face.
- **R-05-19.** Movement uses [`Step.hs:141`](../src/Senbazuru/Origami/Step.hs#L141)'s
  tolerance; faces and groups are `after`'s
  ([`:180-192`](../src/Senbazuru/Origami/Step.hs#L180-L192)). `motionCreases`
  holds `after` edges whose angle differs from the `before` edge whose material
  segment contains both ends; an unmatched edge is new, never "changed".
- **R-05-20.** `creasesToCome` returns unmatched `after` edges at `before`
  positions.

**Refusals** (new `FoldError` constructors): `MaterialCoordinatesMissing`,
`VerticesNotAPrefix VertexId`, `AddedVertexOffPaper VertexId`.

**Rejected.** Backfill, writing the final graph into every frame, which draws the
crane's every crease on step 1 (same note, "(c)").

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| `motionsAcross == motionsBetween` on consecutive pairs of `quarter-fold-steps.fold` and of `FlapSpec`'s material-frame sequences (the note's "D. When the crease graph grows", finding 18) | the equal-graph branch is bypassed |
| Before `diagonal-cp.fold`, after L2's batch under `AtRest`: no motions; `creasesToCome` lists edges 8–12 at their material ends | cut old pieces 6, 7 count as new |
| Vertex 7 at (1/4, 1/4) lies on no edge, inside `before`'s face [0,1,3], and is placed at (1/4, 1/4, 0) | only edge interpolation exists |
| `insideRing` on an L-shaped ring: notch outside, arm inside | the convex test is reused |

**Outputs unchanged.** New functions; `motionsBetween` changes only by L3.

**Milestone.** M3.

---

### L6. `LineStopsOnTheModel` carries its point

**Modules.** `Origami.ThroughLayers`; `Fold.Query`.

```haskell
LineStopsOnTheModel !CreaseEnd !V2 !FaceId     -- SKETCH; was !CreaseEnd !FaceId
```

**Why.** Its message starts with `creaseEndFlag end`, `--from` or `--to`
([`ThroughLayers.hs:194-201`](../src/Senbazuru/Origami/ThroughLayers.hs#L194-L201),
[`Query.hs:68-71`](../src/Senbazuru/Fold/Query.hs#L68-L71)); a runner has no
flags. `CreaseEndMeetsNothing` already names the point and "deliberately /not/"
the end ([`Query.hs:160-165`](../src/Senbazuru/Fold/Query.hs#L160-L165),
[`:312-318`](../src/Senbazuru/Fold/Query.hs#L312-L318)).

**Semantics.**

- **R-05-21.** The message names the end by the point given, through `coord`
  ([`Query.hs:423-430`](../src/Senbazuru/Fold/Query.hs#L423-L430), now exported).
  SKETCH, for `ThroughLayersSpec`'s end (0.2, 0.2) on `diagonal-cp.fold`
  ([`ThroughLayersSpec.hs:263`](../test/Senbazuru/Origami/ThroughLayersSpec.hs#L263)): *"the end at (0.2, 0.2) is inside face 0 of
  the folded model rather than on that face's edge, so that layer would be creased
  only part of the way across. Each layer the line reaches has to be creased right
  across, so move this end onto an edge or clear of the paper"*.
- **R-05-22.** `CreaseEnd` stays (tested at
  [`ThroughLayersSpec.hs:279-285`](../test/Senbazuru/Origami/ThroughLayersSpec.hs#L279-L285)).
  `creaseEndFlag` is deleted: `grep -rn creaseEndFlag app src test docs study`
  finds only `Query` and `ThroughLayers`. If `app/` wants flags back, it maps
  `CreaseEnd` itself.
- **R-05-23.** Two texts change in the same PR. The pinned sentence
  ([`ThroughLayersSpec.hs:271-275`](../test/Senbazuru/Origami/ThroughLayersSpec.hs#L271-L275))
  becomes "the end at (0.2, 0.2) is inside face 0 …". The example in
  [`usage.md:866-872`](../docs/usage.md), a separate run on
  `bird-base.cp`, becomes "the end at (-200.0, 150.0) is inside face 12 …".
  Only the first is pinned by a test. The digits are `coord`'s ("gives back
  `0.01` and `3.0`").

**Acceptance.** The new sentence pinned verbatim (red if a flag name remains);
the carried point equals the given end, not a clipped one (red if the wrong point
is carried); the `ToEnd` test unchanged (red if the end is dropped).

**Outputs unchanged.** No golden. `crease --folded`'s stderr wording changes on
purpose; stdout does not.

**Milestone.** Its own follow-up issue, before M4
([D20](decisions.md#d20-errors);
[decisions §3](decisions.md#3-recorded-text-this-design-changes) row 17).

---

### L7. The untouched-fold check, shared

**Module.** `Origami.Folding`.

```haskell
-- SKETCH
data StartError = StartFolding FoldingError | StartGeometry FoldError | StartMismatch
untouchedFold :: Folded -> Either StartError Folded      -- the fresh refold on success
```

**Why.** An *untouched* fold is a `Folded` equal to what `foldFrameWith` returns
for its own pattern and angles: one nobody edited afterwards. `Folded`'s
constructor is public, so `Flap` rebuilds the state rather than trust one
([`Flap.hs:169-181`](../src/Senbazuru/Origami/Flap.hs#L169-L181)).
L8 takes a `Folded` for the same reason, and a copy would drift. The check
ignores orders, which is why the runner puts orders on the working pattern before
folding ([02 §2.4, invariant 3](02-language-semantics.md#24-the-seven-invariants);
[D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)).

**Semantics.**

- **R-05-24.** `untouchedFold` is
  [`Flap.hs:171-173`](../src/Senbazuru/Origami/Flap.hs#L171-L173) and
  [`:175-181`](../src/Senbazuru/Origami/Flap.hs#L175-L181) verbatim: rebuild the
  pattern with the folded angles and no orders, refuse a length mismatch, refold,
  compare rings, then positions within 1e-9 × `modelSpan`.
- **R-05-25.** `Flap` maps the constructors to `FlapFolding`, `FlapGeometry`,
  `FlapStartMismatch`, and runs its surface check
  ([`:174`](../src/Senbazuru/Origami/Flap.hs#L174)) immediately after. Only a
  `Folded` failing *both* the surface check and a start check after the length
  test changes its reported reason: from `FlapSurface` to `FlapFolding`,
  `FlapGeometry` or `FlapStartMismatch`, because the surface check now runs
  second;
  `grep -rn "FlapStartMismatch\|FlapSurface\|FlapGeometry" test study` finds no
  test naming any of them.

**Acceptance.** A new `FlapSpec` case moves one vertex of `foldedFrame` by 1e-6
and expects `FlapStartMismatch` (red if the check is dropped); L8 has the twin.

**Outputs unchanged.** A pure extraction.

**Milestone.** M4.

---

### L8. `creaseLayersThrough`

**Module.** `Origami.ThroughLayers`.

```haskell
-- SKETCH
data Creased = Creased { creasedPattern :: !Frame, creasedEdges :: ![[EdgeId]] }

creaseLayersThrough ::
  NewCreaseAngle -> [(Set FaceId, V2, V2, Assignment)] -> Folded -> Either ThroughError Creased

creaseThroughLayers from to assignment fr = do          -- existing signature, kept
  folded <- first CannotFold (foldFrameWith fr)
  creasedPattern <$> creaseLayersUnchecked FlatForAssignment [(everyFace folded, from, to, assignment)] folded
```

**Why.** See "Problem and evidence", and AGENTS.md's batch rule: several lines in
one figure (both diagonals, [D22](decisions.md#d22-figures-holding-several-moves))
must be one cut-and-trace, or the cost is cubic
([`Creasing.hs:93-102`](../src/Senbazuru/Fold/Creasing.hs#L93-L102),
[#77](https://github.com/avalonalex/senbazuru/issues/77)). **A batch never spans
figures** ([C16](decisions.md#changes-since-draft-v2)): in the crane opening of
[decisions §7](decisions.md#7-examples), the `diagonals` step's two lines are one
batch and the `midlines` step, a later figure after a turn-over, is another,
because a batch across figures would show a later figure's creases on an earlier
one.

**Semantics.**

- **R-05-26.** The export runs `untouchedFold` (L7) first. `creaseThroughLayers`
  calls the unchecked worker, having just folded, so `crease --folded` gains no
  fold.
- **R-05-27.** Per request, in order:
  1. `LineWithoutLength` ([`:237`](../src/Senbazuru/Origami/ThroughLayers.hs#L237));
  2. each id a face of the fold, else `LayerNotInThisFold`; an empty set is
     `NoLayersChosen`;
  3. the ends test ([`:241-247`](../src/Senbazuru/Origami/ThroughLayers.hs#L241-L247))
     and `LayerNotPlaced` over **selected** faces only;
  4. *shares* for selected faces, with `shareFor`'s three guards
     ([`:285-297`](../src/Senbazuru/Origami/ThroughLayers.hs#L285-L297)). A
     share is the piece of the line crossing one face, carried back onto the
     unfolded sheet with the assignment it gets there (`LayerCrease`,
     [`:266-273`](../src/Senbazuru/Origami/ThroughLayers.hs#L266-L273));
  5. `NoPaperUnderTheLine` when none has a share.

  A selected face the line misses is skipped, as every uncrossed face is today,
  so "every face" is exactly `creaseThroughLayers`.
- **R-05-28.** All shares of all requests go to **one** `creaseAllAlongWith`
  call on `foldedPattern`; `creasedEdges` regroups its lists per request.
- **R-05-29.** Each share's assignment is flipped on face-down layers as now
  ([`:296`](../src/Senbazuru/Origami/ThroughLayers.hs#L296),
  [`:327-340`](../src/Senbazuru/Origami/ThroughLayers.hs#L327-L340)). **This
  looks wrong and is not:** under `AtRest` a requested valley is written M at 0
  on face-down layers. Mountain and valley are named from the side the pattern
  is drawn on, and a face-down layer shows the reader its other side, so the
  fold that opens towards the reader is a mountain on that layer
  ([Through all layers](../docs/glossary.md#origami),
  [creasing-through-layers](../docs/notes/creasing-through-layers.md)). `U` cannot
  encode "at rest": `theOtherWay` leaves `U` as `U` and the alternation is lost.
  The line is in raw (unpresented) coordinates; the runner converts the reader's
  sense ([D5](decisions.md#d5-presentation-and-the-readers-side)).
- **R-05-30.** In a batch of two or more requests a refusal is wrapped as
  `RequestRefused i err`; single requests stay bare, so
  `ThroughLayersSpec`'s `Left NoPaperUnderTheLine` cases hold
  ([C31](decisions.md#changes-since-draft-v2)).

**Rejected.** Refusing a selected face the line misses: `creaseThroughLayers`
would then have to precompute crossed faces, duplicating `shareFor`; L11
guarantees crossing and its tests check it. One line per call: against the batch
rule.

**Refusals** (new `ThroughError` constructors): `NotTheWorkingFold StartError`,
carrying L7's result with any of its three constructors; `LayerNotInThisFold
FaceId`; `NoLayersChosen`; `RequestRefused Int ThroughError`, with the request
counted from 1.

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| Every face selected equals `creaseThroughLayers` byte for byte on every `ThroughLayersSpec` input | the flip or a guard differs |
| `crane.fold`, faces {2, 3, 6, 7}, line (0, 1/4)–(2, 1/4), `FlatForAssignment`, `Unassigned`: four ids equal to `CraneWing`'s U-edge hinge, 76 faces after tracing ([`CraneWing.hs:65-66`](../study/fold-material/CraneWing.hs#L65-L66)) | restricted shares differ from the hand clip |
| `AtRest` on [`ThroughLayersSpec.hs:104-120`](../test/Senbazuru/Origami/ThroughLayersSpec.hs#L104-L120)'s line: new pieces at 0, V and M as that test lists | alternation lost, or `U` written |
| Two requests in one call equal one `creaseAllAlongWith` over the concatenated shares | requests are creased in turn |
| A moved vertex gives `NotTheWorkingFold`; face 99 gives `LayerNotInThisFold` | a check is missing |

**Outputs unchanged.** `crease --folded` keeps its path and single fold; no golden
creases.

**Milestone.** M4. Evidence status ([D8](decisions.md#d8-folding-some-layers)):
the restricted selection matching `CraneWing` rests on Python; the second row
reproduces it in Haskell.

---

### L9. Ordered cover

**Module.** `Origami.Visible`.

```haskell
-- SKETCH
data CoverStretch = CoverStretch
  { stretchFrom, stretchTo :: !Double   -- parameters along the line, 0 to 1
  , stretchFaces :: ![FaceId] }         -- nearest the viewer first
data CoverError = CoverFlat FlatError | UnorderedCover FaceId FaceId V2 | CyclicCover [FaceId] V2
orderedCover :: Bool -> Frame -> [FaceOrder] -> (V2, V2) -> Either CoverError [CoverStretch]
```

**Why.** An *ordered cover* lists the faces over each stretch of a line, nearest
first ([glossary-additions](glossary-additions.md#geometry)). "Top N layers" is
counted at each point, not by [layer number](../docs/glossary.md#origami), the
longest chain of faces below a face: on the crane that chain is 31 long where
the thickest point holds 24 sheets
([gap-layer-selective-folds](research/gap-layer-selective-folds.md) "What
exists", finding 9). `nearness` already combines FOLD's sign rule, winding and
viewer side ([`Visible.hs:211-270`](../src/Senbazuru/Origami/Visible.hs#L211-L270)),
but is not exported ([`:100-106`](../src/Senbazuru/Origami/Visible.hs#L100-L106))
and answers "neither nearer" for an unrecorded pair
([`:226-229`](../src/Senbazuru/Origami/Visible.hs#L226-L229)), right only when
the faces do not overlap.

**Semantics.**

- **R-05-31.** `flatSheet`, then cut the segment at every panel-boundary
  crossing. A stretch's faces are those whose interior strictly contains its
  midpoint, by `strictlyInside` with `sheetHair`, the sheet's length tolerance
  ([`Flat.hs:113`](../src/Senbazuru/Origami/Flat.hs#L113)), as `shareFor` does.
  Faces meeting along a stretch that runs down their edge do not cover it.
- **R-05-32.** Sort by `nearness fromAbove`, true for a viewer on raw +z (the
  runner passes the reader's side). A pair ordered neither way is
  `UnorderedCover` at the midpoint. Otherwise every pair is ordered, and each
  face's *rank* is how many faces over the stretch are nearer than it. Without a
  cycle (a nearer than b, b than c, c than a) the ranks are 0 … n−1; two equal
  ranks mean a cycle, refused as `CyclicCover` with its faces.

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| Folded `quarter-fold.fold` with its solved stacking, line (0.5, 0)–(1, 0.5): faces 2, 1, 0, 3 from +z; 3, 0, 1, 2 from −z. That is the order forced by [tacos](../docs/glossary.md#origami), two faces joined along a crease and folded back onto each other ([`Stacking.hs:44-52`](../src/Senbazuru/Origami/Stacking.hs#L44-L52)), per [gap-layer-selective-folds](research/gap-layer-selective-folds.md) "A second and third fixture (script)", finding 15; **UNVERIFIED in Haskell** | the sign is read against the first face's normal, or `fromAbove` is ignored |
| Removing one order between overlapping crossed faces gives `UnorderedCover` naming them | a missing order reads as "neither nearer" |

**Outputs unchanged.** `nearness` and `visibleForm` untouched.

**Milestone.** M4.

---

### L10. `carryOrders`

**Module.** `Origami.ThroughLayers`.

```haskell
-- SKETCH: parent = untouched fold of the working pattern, accepted orders on its foldedFrame;
--         child  = untouched fold of creaseAllAlongWith AtRest's output
carryOrders :: Folded -> Folded -> Either ThroughError [FaceOrder]
```

**Why.** A *stacking* is one complete layer order where a model has several
([glossary-additions](glossary-additions.md#running-a-sequence)); the crane has
five ([`StackingSpec.hs:376`](../test/Senbazuru/Origami/StackingSpec.hs#L376)).
The runner may never choose among them silently
([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)
invariant 7, [D11](decisions.md#d11-stacking-choices-are-relations)), but creasing
drops orders and `layerOrderFor` re-solves exactly then
([`Stacking.hs:386-400`](../src/Senbazuru/Origami/Stacking.hs#L386-L400)).

**Semantics.**

Material comparisons here use the `Fold.Faces.tolerance` formula, 1e-9 × the
bounding box's diagonal ([`Faces.hs:248-251`](../src/Senbazuru/Fold/Faces.hs#L248-L251)),
on material points, as L5 does.

- **R-05-33.** Refuse `CreasedNotAtRest e` unless each child edge lies in one
  parent edge's material segment, within that tolerance, with an equal angle, or
  in none with angle 0. The carry is exact only then, since a crease at 0 moves
  no paper.
- **R-05-34.** A child face's parent is the parent face whose material ring
  contains the child's material centroid strictly inside, by more than that
  tolerance. Every face here is convex, so the centroid is inside its own face:
  the sheet tolerance R-05-35 uses comes from `flatSheet`, which refuses a
  concave face ([`Flat.hs:126-128`](../src/Senbazuru/Origami/Flat.hs#L126-L128)).
  L5's `insideRing` is for crease patterns that never pass through `flatSheet`.
  None or several is `ChildOutsideParents c`.
- **R-05-35.** Children with different parents that overlap by more than
  `sheetSpeck`, the sheet's area tolerance
  ([`Flat.hs:117`](../src/Senbazuru/Origami/Flat.hs#L117); the test at
  [`Visible.hs:304`](../src/Senbazuru/Origami/Visible.hs#L304)), take their
  parents' order, faces and orders both read from `foldedFrame`
  ([`Folding.hs:303-308`](../src/Senbazuru/Origami/Folding.hs#L303-L308));
  unordered parents are `ParentsUnordered p q`. Children of one parent never
  overlap.
- **The line that looks like a typo:** the sign is copied unchanged although the
  child is a different face. FOLD reads it against the second face's normal, and
  a child keeps its parent's: nothing moved, and traced rings are anticlockwise
  ([`Faces.hs:98`](../src/Senbazuru/Fold/Faces.hs#L98)). Orders are returned
  against the child's `foldedPattern` winding, so refolding re-signs any re-wound
  ring as usual ([`Folding.hs:385`](../src/Senbazuru/Origami/Folding.hs#L385)).

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| Crane creased by L8 under `AtRest`. The parent orders are the stacking of `crane.fold`, among its five, under which the tail relations of [`CraneWingSpec.hs:56-81`](../test/CraneWingSpec.hs#L56-L81) hold, resolved through material rings as that test does. Carried, the relations hold on the child without `solveStackingAs [2]`. That index 2 on the *creased* 76-face frame ([`CraneWing.hs:75-78`](../study/fold-material/CraneWing.hs#L75-L78)) is the same stacking on the uncreased one is **UNVERIFIED**, so the parent is chosen by relation, not by index | a pair is lost |
| Every rule of `stackingRules child` holds under the carried orders | a sign flips |
| A `FlatForAssignment` child gives `CreasedNotAtRest` | the exactness guard is skipped |

**Milestone.** M4.

---

### L11. The selection rule lives in the library

**Module.** `Origami.ThroughLayers`: both front ends need it, so no caller
restates it.

```haskell
-- SKETCH; selector meaning is 02's, refusals are the research note's
data Selector = FlapContaining V2 | TopLayers Int | TopFlap | AllLayers   -- seeds are material points
selectLayers ::
  Selector ->
  V2 ->         -- moving side: a material point on the paper that moves, for TopLayers and TopFlap
  (V2, V2) ->   -- the fold line, in raw coordinates
  Bool ->       -- True for a reader on raw +z, as L9's fromAbove
  Folded ->
  Either SelectionError (Set FaceId)
```

**Semantics.** Specified in [02 §6.3](02-language-semantics.md#63-which-layers) from
[gap-layer-selective-folds](research/gap-layer-selective-folds.md) "(a) A rule
from line + selector to a face set": cut the crossed faces, take the *seed*'s
component ([glossary-additions](glossary-additions.md#references)), count depth
with L9, then refuse a selection that is *coupled*, still joined to paper that
must stay ([glossary-additions](glossary-additions.md#running-a-sequence)), or
*covered* (`FlapCovered`): a stationary face lies nearer than a selected face, over
the same stretch, on the side the flap turns towards. That check runs before
`Flap`'s sweep ([D8](decisions.md#d8-folding-some-layers)). `SelectionError`
takes that note's "Refusal list".

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| `crane.fold`, line (0, 1/4)–(2, 1/4): `FlapContaining (0.02, 0.97)` gives {2, 3, 6, 7}, `FlapContaining (0.97, 0.02)` gives {0, 1, 4, 5} (finding 12, Python; the Haskell reproduction [D8](decisions.md#d8-folding-some-layers) requires) | the rule and `CraneWing`'s hand list diverge |
| Same line: the coupling check (02 §6.3 step 3) on the restricted set {6, 7}, the set a one-layer selection of that wing gives, is refused as coupled, naming face 2 or 6 (finding 13). Which `Selector` and moving side yield {6, 7} is **UNVERIFIED** | the separation check is dropped |
| `quarter-fold.fold`, line (0.5, 0)–(1, 0.5): `FlapContaining` with a seed near (1, 0) is refused as covered, since faces 1 and 2 cover it from above and face 3 from below (finding 15) | orders are ignored |

**Milestone.** M4.

---

### L12. `stackingWhere`

**Module.** `Origami.Stacking`, beside `layerOrderFor` and #110's
`withLayerOrder`, where "which order" policy lives.

```haskell
-- SKETCH
stackingWhere :: Budget -> [(FaceId, FaceId)] -> Frame -> Either StackingError Stackings
-- new constructors
  | RelationOnOneFace !FaceId
  | RelationNotOverlapping !FaceId !FaceId
  | RelationsContradict ![(FaceId, FaceId)] ![FaceId]
```

**Why.** A *stacking relation* picks among stackings
([glossary-additions](glossary-additions.md#running-a-sequence),
[D11](decisions.md#d11-stacking-choices-are-relations)). Filtering
after enumeration meets the budget cap, which is per *component*: groups of
undecided face pairs no rule joins, searched separately
([`Stacking.hs:766-770`](../src/Senbazuru/Origami/Stacking.hs#L766-L770),
[`:437-449`](../src/Senbazuru/Origami/Stacking.hs#L437-L449)). Starting the
solver from the relations as *pre-decided pairs* costs one solve. ("Pre-decided"
rather than "seeded": a *seed* in this series is a material point naming what
moves, L11.)

**Semantics.**

- **R-05-36.** (f, g) means "f on the +z side of g", the solver's sense
  ([`Stacking.hs:462-463`](../src/Senbazuru/Origami/Stacking.hs#L462-L463)).
  **It is not FOLD's `faceOrders` sign**, which is read against g's normal. The
  runner maps "above, from the reader's side" into it.
- **R-05-37.** `analyse`; refuse `f == g` and a pair not among the analysis
  pairs; enter each relation as a decided pair, disagreeing duplicates being
  `RelationsContradict`; then `solutionSpace` with propagation starting from
  those pairs instead of `M.empty`
  ([`:839`](../src/Senbazuru/Origami/Stacking.hs#L839)). **The entry that looks
  like a typo:** (f, g) is stored under key `(min f g, max f g)` with value
  `f < g`. The solver keeps each pair once, keyed (lower id, higher id), with
  `True` when the lower-id face is above
  ([`Stacking.hs:728-730`](../src/Senbazuru/Origami/Stacking.hs#L728-L730)), so
  "f above g" is `True` exactly when f is the lower id.
- **R-05-38.** If the solve from pre-decided pairs reports `Unstackable`, whether
  propagation failed or the search found no state for some component
  ([`:880-886`](../src/Senbazuru/Origami/Stacking.hs#L880-L886)), run the
  solve without them. If that fails too, `Unstackable` as today; otherwise
  `RelationsContradict`, naming the relations and the faces the first solve
  named.
- **R-05-39.** An exhausted budget is `GaveUpStacking`
  ([`:885`](../src/Senbazuru/Origami/Stacking.hs#L885)), never "ambiguous".
- **R-05-40.** `stackingWhere b [] == stackingSpace b` for every frame.
  `layerOrderFor`'s exhaustive match
  ([`:390-399`](../src/Senbazuru/Origami/Stacking.hs#L390-L399)) gains the new
  constructors as unreachable declines.
- **Counting is the runner's, not the library's**
  ([D11](decisions.md#d11-stacking-choices-are-relations),
  [C32](decisions.md#changes-since-draft-v2)). `StackingError` gains only what
  face ids alone show: a relation on one face, faces that do not overlap,
  relations that contradict. `stackingWhere` returns every surviving stacking,
  however many; whether two or more is a refusal is policy, so `StillAmbiguous`
  (relations leave two or more) and `SeveralStackings` (no relations and more than
  one) belong to `Sequence.Error`'s `StackingChoiceError`, which wraps
  `StackingError`.

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| R-05-40 on every `StackingSpec` fixture | pre-decided pairs alter propagation without them |
| Crane: a relation fixing one open pair leaves fewer than today's 5 states ([`StackingSpec.hs:376`](../test/Senbazuru/Origami/StackingSpec.hs#L376), [`:387-388`](../test/Senbazuru/Origami/StackingSpec.hs#L387-L388)), returned as `Right` | the relations are ignored, or several survivors are refused here |
| (f, g) with (g, f) gives `RelationsContradict` | reported as `Unstackable` |
| Relations that survive propagation but leave a component with no state in the search give `RelationsContradict` (fixture **UNVERIFIED**: to be found at M4) | reported as `Unstackable` |
| Non-overlapping faces give `RelationNotOverlapping` | silently kept |
| D11's crane relations leave exactly today's index 2, and dropping either leaves two or more (**UNVERIFIED**; an M4 acceptance test per [D11](decisions.md#d11-stacking-choices-are-relations)) | the relations are wrong |

**Outputs unchanged.** `solveStacking`, `layerOrderFor` and `stackingSpace`
pass no pre-decided pairs; `crane-folded` and every stacked golden stay.

**Milestone.** M4.

---

### L13. `Origami.Macro`: `CheckedMacro` and `macroPoseAt`

**Placement.** A new `Senbazuru.Origami.Macro`, sibling of `Origami.Flap`,
knowing angles, faces and ids but no material references or step names. Binding
by material point (`MacroBinding`, `MacroBindError`) stays in `Sequence.*`
([02](02-language-semantics.md),
[D9](decisions.md#d9-macro-moves-as-named-angle-relations)), and so does a
`together` move's list of bindings: one record carrying
`recordMacros :: [MacroBinding]`, each binding naming the line of continuations it
belongs to ([C12](decisions.md#changes-since-draft-v2)). The certificate registry
stays in the study ([D15](decisions.md#d15-graduation-from-study-to-library)).
`Sampled CheckedMacro SampleReport` is a library value
([D10](decisions.md#d10-assurance-as-evidence-values)), so the type cannot live in
the study.

```haskell
-- SKETCH
data CheckedMacro          -- opaque; only checkMacro builds one, as with CheckedFlap (Flap.hs:95-96);
                           -- deriving stock (Eq, Show) from the start (D10)
data SampleReport          -- the parameters checked and the checks run at each; Eq, Show
data MacroError            -- Explain in this module
checkMacro :: MacroSpec -> [Rational] -> Folded -> Either MacroError CheckedMacro
macroPoseAt :: CheckedMacro -> Rational -> Either MacroError RoutePose
```

**Why.** A *macro-move* turns several creases at rates fixed by one *driving
parameter* ([glossary-additions](glossary-additions.md#macro-moves)). The study's
checked routes are bound to one fixture: `preparePetal` demands the bird
fixture's material vertices, cut faces, edge ids and anchor
([`CheckedPetal.hs:48-60`](../study/fold-material/CheckedPetal.hs#L48-L60)).
Grips and animation keys need poses anywhere on the route
([D10](decisions.md#d10-assurance-as-evidence-values)).

**Semantics.**

- **R-05-41.** A `MacroSpec` names each *role*'s edge ids, one formula per role
  (a Haskell function shared with the tests), the parameter range in exact
  degrees, and the stationary face.
- **R-05-42.** `checkMacro` checks both endpoints and every parameter it is
  given. **The runner gives it more than the author's samples**
  ([D9](decisions.md#d9-macro-moves-as-named-angle-relations),
  [C38](decisions.md#changes-since-draft-v2)): the authored `sample` parameters
  plus `RunSettings.macroChecks` evenly spaced interior parameters, a count fixed
  with evidence in M5's PR. So evidence never depends on which poses an author
  chose to draw, and a macro written with no `sample` still earns `Sampled`. Only
  authored samples become written states
  ([D24](decisions.md#d24-states-figures-and-their-numbers)); `SampleReport`
  records every parameter checked. At each one:
  - angles from the formulas, with endpoints *pinned*: at each end of the range
    a role's angle is written as its exact value instead of computed through
    trigonometry, as
    [`CheckedPetal.hs:107`](../study/fold-material/CheckedPetal.hs#L107) writes
    180 at 180;
  - `foldFrameWith`'s torn-vertex and loop checks;
  - *static contact*, the check of one pose on its own (not the path between
    poses) that no two panels cross, by `checkPanelContact`
    ([`Contact.hs:123`](../src/Senbazuru/Origami/Contact.hs#L123)). Layer orders
    are given to it only at flat endpoints, because orders for paper in the air
    cannot come from the landing stack
    ([gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md)
    "C. What can be certified, and how angles should be compared", finding 16).
- **R-05-43.** `macroPoseAt t` refuses `t` outside the range
  (`MacroParameterOutOfRange`), else evaluates, refolds and applies the stationary
  correction as `Flap` does. A pose at an unsampled `t` is a pose, not evidence.
- Formula angles are compared within the 1e-12 of
  [`RabbitEarSpec.hs:49`](../test/RabbitEarSpec.hs#L49) until the tolerance issue
  lands ([D16](decisions.md#d16-testing-and-acceptance)): literals in the study's
  manifest, `study/fold-material/cases.json`, sit one or more *ulps*, steps between
  adjacent `Double`s, from their formulas (same note, finding 18;
  [decisions §10](decisions.md#10-corrections) item 16).

**Acceptance** (written at M5 on `examples/bird-base.fold`).

| Test | Turns red if |
| --- | --- |
| Collapse poses at the samples equal `CheckedBird.collapseAngles` within 1e-12 (**UNVERIFIED** role mapping) | a role takes another's formula |
| `macroPoseAt` at a sample equals the checked pose within 1e-12 × `modelSpan` | the stationary correction is skipped |
| `checkMacro spec [] q` still checks both endpoints, and its `SampleReport` lists them | an empty parameter list checks nothing |

**Milestone.** M5.

---

### L14. `Eq` on flap values, and `prepareFlapToward`

**Module.** `Origami.Flap`.

*Superseded in part* by [D5](decisions.md#d5-presentation-and-the-readers-side)'s
amendment (owner decision 13, 2026-09-23): `prepareFlapToward` is to read the
*moving* face beside each hinge segment, not the first stationary face, with
`FlapMovingNotFlat` and `FlapMovesBothWays` in place of `FlapStationaryNotFlat`
(**SKETCH**). #344 shipped this section as
`data Toward = TowardPlusZ | TowardMinusZ`,
`FlapStationaryNotFlat !FaceId !Double` (the face's spread in z, judged by
`hasRelief`) and `FlapInvalidTurn` for a bad size. The sketch, R-05-45 to
R-05-47 and the acceptance rows below are rewritten with that change.

```haskell
-- SKETCH
data FlapMotion = FlapMotion { … }          -- fields unchanged (Flap.hs:81-92)
  deriving stock (Eq, Show)                 -- was Show only (Flap.hs:93)
data CheckedFlap = CheckedFlap !FlapMotion !SweepCheck
  deriving stock (Eq, Show)                 -- was Show only (Flap.hs:96)

data Toward = TowardRawPlusZ | TowardRawMinusZ
  deriving stock (Eq, Show)

prepareFlapToward :: [EdgeId] -> FaceId -> Double -> Toward -> Folded -> Either FlapError FlapMotion

-- new FlapError constructor
  | FlapStationaryNotFlat !FaceId !V3       -- the face, and its displayed normal
```

**Why the sign needs the library, concretely.** Quarter-fold step 2 is one valley
fold, "fold the top half down in front", and the fixture writes it as edge 9 at
+180 and edge 11 at −180: `jq -c '.file_frames[1].edges_foldAngle[8:12]' examples/quarter-fold-steps.fold`
prints `[-180,180,-180,-180]` for edges 8–11 (in this fixture the key frame is the
flat sheet, `file_frames[0]` the state after step 1 and `file_frames[1]` after
step 2). **Opposite signs for one valley is not a typo.** `Flap`'s *travel* is the
signed change in the *first* listed segment's fold angle; every other segment
takes `travel` or `−travel` by comparing its own stationary face's ring direction
along the hinge with the first's
([`Flap.hs:14-16`](../src/Senbazuru/Origami/Flap.hs#L14-L16),
[`:201-216`](../src/Senbazuru/Origami/Flap.hs#L201-L216)). The face held still
beside edge 9 is face 0, lying top up; the one beside edge 11 is face 3, which
step 1 turned over: in `file_frames[0]`, face 3's ring `[8,7,0,4]` has signed
area −0.25 in written x, y
(`python3 -c 'import json;d=json.load(open("examples/quarter-fold-steps.fold"));V=d["file_frames"][0]["vertices_coords"];print([sum(V[r[i]][0]*V[r[i-1]][1]-V[r[i-1]][0]*V[r[i]][1] for i in range(len(r)))/-2 for r in d["faces_vertices"]])'`
prints `[0.25, 0.25, -0.25, -0.25]`). So with edge 9 listed first the valley is
travel +180, and with edge 11 first the same valley is −180
([01 §5.5](01-architecture.md#55-raw-sense-and-travel),
[§5.6](01-architecture.md#56-travel-per-segment)). A caller holding "valley"
cannot pick the sign without knowing which way up that first stationary face
lies, and `Flap` chooses that face
([`Flap.hs:195`](../src/Senbazuru/Origami/Flap.hs#L195)) without exporting it
([`:49-59`](../src/Senbazuru/Origami/Flap.hs#L49-L59)). Way-up decisions stay in
the library, where `Flap` already holds the face's ring
([D5](decisions.md#d5-presentation-and-the-readers-side),
[C5](decisions.md#changes-since-draft-v2)).

**Why `Eq`.** Move records derive `Eq`, and a record holds `SweptHinge CheckedFlap`
([D10](decisions.md#d10-assurance-as-evidence-values),
[C4](decisions.md#changes-since-draft-v2)). Every field type already derives it:
`Folded` ([`Folding.hs:324`](../src/Senbazuru/Origami/Folding.hs#L324)),
`HingeSweep` and `SweepCheck`
([`HingeSweep.hs:89`](../src/Senbazuru/Origami/HingeSweep.hs#L89),
[`:101`](../src/Senbazuru/Origami/HingeSweep.hs#L101)), `FaceOrder`
([`Types.hs:357`](../src/Senbazuru/Fold/Types.hs#L357)), `EdgeId` and `FaceId`
([`:284`](../src/Senbazuru/Fold/Types.hs#L284),
[`:289`](../src/Senbazuru/Fold/Types.hs#L289)) and `V3`
([`V3.hs:32`](../src/Senbazuru/Geometry/V3.hs#L32)).

**Semantics.**

- **R-05-44.** `FlapMotion` and `CheckedFlap` gain `deriving stock (Eq)`. Both stay
  opaque: the export list names the types without constructors
  ([`Flap.hs:50-51`](../src/Senbazuru/Origami/Flap.hs#L50-L51)).
- **R-05-45.** `prepareFlapToward eids side magnitude toward q` is
  `prepareFlapAlong eids side travel q`
  ([`Flap.hs:162-239`](../src/Senbazuru/Origami/Flap.hs#L162-L239)) with `travel`
  chosen once the first segment's stationary face is known (`fixed`,
  [`:195`](../src/Senbazuru/Origami/Flap.hs#L195)). Read that face's placement in
  the refolded start (`start`, [`:175`](../src/Senbazuru/Origami/Flap.hs#L175)),
  not in the supplied `Folded`, whose constructor is public; its displayed normal
  is n = M · ẑ, with M the placement's `rigidLinear`
  ([`Rigid.hs:76-77`](../src/Senbazuru/Geometry/Rigid.hs#L76-L77)). Then:

  | `toward` | n = +ẑ, the face shows its top | n = −ẑ, the face shows its back |
  | --- | --- | --- |
  | `TowardRawPlusZ` (a raw valley) | travel = +magnitude (edge 9 in step 2) | travel = −magnitude (edge 11 in step 2) |
  | `TowardRawMinusZ` (a raw mountain) | travel = −magnitude (edges 8, 10 in step 1) | travel = +magnitude (the crane wing's accepted `behind`, [D5](decisions.md#d5-presentation-and-the-readers-side), reasoned) |

  Both entries share one internal worker, so `prepareFlapToward` adds no
  `foldFrameWith` call to the roughly seven a checked step makes
  ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
  "From reading the code (counts, not timings)").
- **R-05-46.** A first stationary face whose n is not within 1e-12 of +ẑ or −ẑ in
  every component, the tolerance `isProperRotation` uses (L3), is refused as
  `FlapStationaryNotFlat`: with that face standing in the air there is no way up
  to read, and the refusal says so rather than guessing. Only the first segment's
  face is read; the other segments keep today's relative rule. A magnitude that is
  negative, non-finite or above 360 is `FlapInvalidTravel`, as a travel is today
  ([`:165`](../src/Senbazuru/Origami/Flap.hs#L165)).
- **R-05-47.** `prepareFlap` and `prepareFlapAlong` are unchanged, and existing
  callers keep passing signed travels. The runner passes `TowardRawPlusZ` for a
  raw valley and `TowardRawMinusZ` for a raw mountain; what the raw sense is
  belongs to [02 §5.3](02-language-semantics.md#53-one-conversion-for-the-whole-model).

**Refusals.** `FlapStationaryNotFlat` (new); otherwise `prepareFlapAlong`'s, in its
order.

**Rejected.** One raw sense setting the sign of travel, whatever the first
stationary face's way up (it gives edge 11 first the wrong sign, above). The runner
reading that face's way up and signing travel itself: way-up decisions stay in the
library, where `Flap` already holds the face's ring, and an entry taking a side
does the same work there
([Proposals not adopted](decisions.md#proposals-not-adopted)).

**Acceptance.** On `quarter-fold-steps.fold`, q1 is `foldFrameWith` of the key
frame with `file_frames[0]`'s angles. Ids and signs are from the fixture and from
[01 §5.6](01-architecture.md#56-travel-per-segment)'s Python re-implementation of
`Flap`'s sign; **UNVERIFIED in Haskell** until the first test runs.

| Test | Turns red if |
| --- | --- |
| `prepareFlapToward [9, 11] (FaceId 1) 180 TowardRawPlusZ q1 == prepareFlapAlong [9, 11] (FaceId 1) 180 q1` (face 0, top up, beside edge 9) | the table is inverted, so a top-up face gives −magnitude for a raw valley |
| `prepareFlapToward [11, 9] (FaceId 2) 180 TowardRawPlusZ q1 == prepareFlapAlong [11, 9] (FaceId 2) (-180) q1` (face 3, back up, beside edge 11). By [01 §5.6](01-architecture.md#56-travel-per-segment), that motion ends with edge 11 at −180 and edge 9 at +180, as `file_frames[1]` has them | travel is signed from the raw side alone |
| Key frame with edges 8 and 10 at −90 and 9, 11 at 0, halfway through step 1: `prepareFlapToward [8, 10] (FaceId 0) 90 TowardRawPlusZ` is `FlapStationaryNotFlat` naming face 3, which stands upright; `prepareFlapToward [8, 10] (FaceId 3) 90 TowardRawPlusZ` on the same fold, whose first stationary face is face 0, lying flat, is accepted | the normal test is skipped, or reads a face other than the first stationary one |
| `FlapSpec`, `BlintzSequenceSpec`, `HelmetSequenceSpec`, `CraneWingSpec` unchanged | an existing entry's travel moves |

**Outputs unchanged.** `Eq` adds instances; `prepareFlapToward` is a new entry
over the same preparation, and no existing caller reaches it.

**Milestone.** M2 ([decisions §8](decisions.md#8-milestones)): records derive `Eq`
from their first PR, and M2's runner turns hinges.

---

### L15. `foldedWalk`

**Module.** `Origami.Folding`.

```haskell
-- SKETCH
data Folded = Folded
  { foldedFrame :: !Frame,
    foldedPattern :: !Frame,
    foldedPlacements :: !(IM.IntMap Rigid),
    foldedWalk :: !(IM.IntMap (FaceId, EdgeId))   -- new: each face but the first, to its parent and the crease crossed
  }
  deriving stock (Eq, Show)
```

**Why.** An animated glTF gives each face a hinge node under its parent face's
node, turning about the crease between them
([D19](decisions.md#d19-realistic-rendering) G1,
[08](08-prd-realistic-rendering.md#g1-animating-checked-rigid-routes)). Which face
is a face's parent is decided by folding's *spanning walk*, a tree of crossings
from the first face that places each face once: for each face it reaches it
composes ``parent `after` turn``
([`Folding.hs:619-624`](../src/Senbazuru/Origami/Folding.hs#L619-L624)), keeps
the first arrival ([`:609`](../src/Senbazuru/Origami/Folding.hs#L609)), and
returns only the placements
([`:572-577`](../src/Senbazuru/Origami/Folding.hs#L572-L577)). `Folding` insists
on "one spanning walk and not two implementations of it that can drift"
([`:328-330`](../src/Senbazuru/Origami/Folding.hs#L328-L330)), so the tree must
come out of that walk, not a second one in the exporter
([C45](decisions.md#changes-since-draft-v2)).

**Semantics.**

- **R-05-48.** `spanningWalk` returns, beside each placement, the face it was
  reached from and the id of the crease crossed (the crease map already holds the
  id, [`Folding.hs:628-630`](../src/Senbazuru/Origami/Folding.hs#L628-L630)),
  under the same first-arrival rule, so tree and placements come from one pass.
  The first face, the root ([`:583-585`](../src/Senbazuru/Origami/Folding.hs#L583-L585)),
  has no entry; every other face has exactly one. Ids are `foldedPattern`'s, as
  the placements' are ([`:286-302`](../src/Senbazuru/Origami/Folding.hs#L286-L302)).
- **R-05-49.** `foldFrameWith` stores it in `foldedWalk`. `Folded` is built only
  there ([`:378-392`](../src/Senbazuru/Origami/Folding.hs#L378-L392)); elsewhere
  it is changed by record update, which a new field does not break:
  `grep -rn "{foldedFrame = \|Folded {$" src test study app` finds four,
  `FlapSpec.hs:351`, `SurfaceSpec.hs:73`, `BasicBaseGallery.hs:76` and
  `CraneWing.hs:79`.

**The line that looks like a typo.** A face's placement is its parent's placement
`after` the turn, not the turn after the parent: the turn is built from the parent
face's corners in flat pattern coordinates, where the crease lies
([`Folding.hs:650-652`](../src/Senbazuru/Origami/Folding.hs#L650-L652)), so it is
applied first and the result then carried to wherever the parent went. This is
AGENTS.md's `M[parent] · R_flat`, and a glTF child node, whose transform is applied
inside its parent's, composes the same way.

**Rejected.** A function re-running `spanningWalk` on a `Folded`'s pattern: it
could fail on a hand-built `Folded`, whose constructor is public, where a field
filled by `foldFrameWith` is total. A walk in `Render.Gltf`: the drift `Folding`
warns against.

**Acceptance.**

| Test | Turns red if |
| --- | --- |
| On `crane.fold` and each state of `quarter-fold-steps.fold`: one entry per face but the first, and following parents from any face reaches the first without revisiting one | a face is missed, or a cycle is recorded |
| For every entry f ↦ (p, e): e lies on both faces' rings, and `foldedPlacements ! f` equals, exactly, ``(foldedPlacements ! p) `after` rotationAbout a (b − a) (−θ)``, with a → b the crease's direction in p's counter-clockwise ring and θ its fold angle in radians, converted as `creaseIndex` converts it, degrees × π / 180 ([`Folding.hs:552-554`](../src/Senbazuru/Origami/Folding.hs#L552-L554)) | the entry names a parent or crease other than the one that placed the face |
| Every existing `FoldingSpec` case passes unchanged | recording the tree changes the walk's order or its first-arrival rule |

**Outputs unchanged.** No renderer reads the field before M7b, and placements come
from the same pass.

**Milestone.** M7b, with G1 animation ([decisions §8](decisions.md#8-milestones)).

## Errors

Messages are **SKETCH**, pinned by a test when each lands. Ids in the new
messages are written "(internal face 99)", as [D20](decisions.md#d20-errors) asks,
because the runner wraps these errors and never rewords them, so the library's
words are what a sequence author reads. **Existing library messages keep their
words in v1**, L6's included, so `FlapError` ids reach authors bare: changing them
would move sentences pinned by specs and quoted in docs, and is a follow-up issue
([D20](decisions.md#d20-errors), [C67](decisions.md#changes-since-draft-v2)).

| Type or constructor | Module | Example message |
| --- | --- | --- |
| `StartError` (3) | `Origami.Folding` | "the folded model given is not the unmodified result of folding its own crease pattern and angles" |
| `LineStopsOnTheModel` (changed) | `Origami.ThroughLayers` | R-05-21 |
| `NotTheWorkingFold e` | `Origami.ThroughLayers` | `explain` of the `StartError` it carries |
| `LayerNotInThisFold f`, `NoLayersChosen` | `Origami.ThroughLayers` | "(internal face 99) is not a face of this folded model, which has 5" |
| `RequestRefused i e` | `Origami.ThroughLayers` | "line 2 of this batch: " <> `explain e` |
| `CreasedNotAtRest e` | `Origami.ThroughLayers` | "(internal edge 7) changed angle when creasing, so layer orders cannot be carried across it" |
| `ChildOutsideParents f`, `ParentsUnordered f g` | `Origami.ThroughLayers` | "(internal faces 2 and 6) overlap but have no layer order to carry" |
| `SelectionError` | `Origami.ThroughLayers` | per the research refusal list |
| `CoverError` (3) | `Origami.Visible` | "(internal faces 1 and 2) overlap at (0.75, 0.25) with no layer order between them" |
| `RelationOnOneFace`, `RelationNotOverlapping`, `RelationsContradict` | `Origami.Stacking` | "(internal faces 10 and 27) do not overlap, so no layer order relates them" |
| `MaterialCoordinatesMissing`, `VerticesNotAPrefix`, `AddedVertexOffPaper` | `Fold.Query` (`FoldError`) | "(internal vertex 7) of the later frame lies on no edge and in no face of the earlier one" |
| `MacroError` | `Origami.Macro` | "parameter 181 is outside the checked range 0 to 180" |
| `FlapStationaryNotFlat f n` | `Origami.Flap` | "(internal face 3), held still beside the first hinge segment, is not lying flat, so which way is towards the reader cannot be read from it"; to be replaced by `FlapMovingNotFlat` ([D5](decisions.md#d5-presentation-and-the-readers-side)'s amendment) |

`StillAmbiguous` and `SeveralStackings` are not library errors; they are the
runner's `StackingChoiceError` in `Sequence.Error` (L12,
[D11](decisions.md#d11-stacking-choices-are-relations)).

## Acceptance criteria

The per-item tables are the criteria. Across all items:

- R-05-1 on every PR, and `render --steps --arrows` byte-identical over every
  multi-frame file in `examples/` (L3,
  [09 §1.3](09-testing-and-acceptance.md#13-multi-frame-examples-draw-the-same-step-pages)).
  Red if any golden or example page changes.
- `stack clean && stack build --test` is warning-free, since repeated builds hide
  warnings (AGENTS.md,
  [09 §1.4](09-testing-and-acceptance.md#14-the-build-is-warning-free-from-cold)).
  A match that misses a new constructor shows as an `-Wincomplete-patterns`
  warning (part of `-Wall`,
  [`senbazuru.cabal:100-108`](../senbazuru.cabal#L100-L108)) in a cold build.
  Nothing fails on it: the flags have no `-Werror`, and CI's test job only builds
  and tests ([`ci.yml:33-34`](../.github/workflows/ci.yml#L33-L34)). So the PR
  author pastes the warning-free cold-build log, and the wildcard matchers that
  would silently absorb a constructor are reviewed by hand.

## Dependencies

| Item | Needs | Issues |
| --- | --- | --- |
| L1 | #58 item 3 in the writer | related to [#111](https://github.com/avalonalex/senbazuru/issues/111), not blocked |
| L2 | — | [#77](https://github.com/avalonalex/senbazuru/issues/77) batch rule kept |
| L3 | the bird arrows golden pinned first ([D16](decisions.md#d16-testing-and-acceptance)) | [01 §4.13](01-architecture.md#413-srcsenbazuruorigamistephs30-34) |
| L5 | L2 | [#36](https://github.com/avalonalex/senbazuru/issues/36), [#94](https://github.com/avalonalex/senbazuru/issues/94) through 06 |
| L7 → L8 | L2, L6 | [#70](https://github.com/avalonalex/senbazuru/issues/70) revisited |
| L9, L10, L11 | L8 | — |
| L12 | — | beside [#110](https://github.com/avalonalex/senbazuru/issues/110) |
| L13 | L4's `RoutePose` | [#54](https://github.com/avalonalex/senbazuru/issues/54); [#55](https://github.com/avalonalex/senbazuru/issues/55) unblocked, not required |
| L14 | — | — |
| L15 | — | [#56](https://github.com/avalonalex/senbazuru/issues/56), which closes at M7b through [08](08-prd-realistic-rendering.md) |

## Risks

| Risk | Mitigation |
| --- | --- |
| L3 classifies as presentation a pair a reader should see as a move | only a whole-model rigid motion qualifies, and a flap turn cannot (R-05-12′); no consecutive pair in either multi-frame example keeps every distance while something moves (0 of 15, 0 of 2) |
| L8, L9, L11 face ids come from Python, whose tracer may number faces differently ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) "Unverified") | the first M4 PR reproduces them in Haskell |
| L2 `AtRest` writes an angle array a file lacked | it is the claim folding already made; the runner never hits it |
| L7 and L8 add a refold per checked crease | counted by `--report`; measured before caching ([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)) |
| L13 formula angles differ by an ulp across platforms | named tolerance; exact only for driving parameters ([D16](decisions.md#d16-testing-and-acceptance)) |
| L14 refuses a hinge turn whose first stationary face is not flat, which `prepareFlapAlong` with a hand-signed travel could perform | a refusal, never a guess; `pose` sets such angles as `StateOnly` ([D9](decisions.md#d9-macro-moves-as-named-angle-relations)) |

## Open questions for the owner

1. **[10 §6](10-roadmap-risks-questions.md#6-owner-decisions), decision 12:**
   crane-sized tests for L8, L10, L11, L12 in default CI or the slow job.
   [decisions §9](decisions.md#9-owner-decisions) recommends a separate slow job
   that is a required check.

The questions this file raised earlier are decided: τ = 1e-10°
([C29](decisions.md#changes-since-draft-v2)), some-vertex classification
([C26](decisions.md#changes-since-draft-v2)), `creaseAllAlongWith` at M2
([C27](decisions.md#changes-since-draft-v2)), `RoutePose` in `Origami.Route`
([C28](decisions.md#changes-since-draft-v2)), and existing library messages keeping
bare ids in v1 ([D20](decisions.md#d20-errors)).

## Research links

- [gap-layer-selective-folds](research/gap-layer-selective-folds.md): "What
  exists", "Re-deriving CraneWing by rule (script)", "(c) Smallest library
  addition, and what the interpreter does itself", "Refusal list".
- [gap-step-annotation-channel](research/gap-step-annotation-channel.md): "D. When
  the crease graph grows", "(c) Two designs for a crease graph that grows".
- [gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md):
  "C. What each consumer reads", "Recommendation".
- [gap-study-consumption-contract](research/gap-study-consumption-contract.md):
  "(a) The per-step record, and who imports what".
- [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md):
  "C. What can be certified, and how angles should be compared".
- [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md):
  "From reading the code (counts, not timings)".
- [A1](research/A1-library-fold-solver.md): "(c) Identifiers that do not survive,
  and the ones that do".
