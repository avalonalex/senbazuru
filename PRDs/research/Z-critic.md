# Z — Critic: completeness and accuracy of the research sweep

Reviewed 2026-09-14 against the repository at `568dcb6`
(branch `docs/prds-sequence-language`, clean). Inputs: A1, A2, B, C, D, E1, E2,
F, G in this directory. Nothing in the repository was modified, built or
tested. Evidence used: `sed`/`grep` on cited lines, `jq` on fixtures,
`gh issue view 95` and `104`, the vendored `lts-22.44.cabal.config`, and one
`python3` evaluation of a documented formula.

## Verdict in one paragraph

The code claims are unusually accurate: 30 of 32 spot checks hold at the cited
lines. The two that fail both matter for the PRDs. A2 says `render --steps`
consumes per-state angle tables. It consumes folded frames, and refuses
`--fold`. C says #95's half turn keeps the model's centre fixed. #95's formula
turns about x = 0, so the quarter fold moves across the page. The larger
problems are between files. Three designs of turn-over, three conventions for
an unbent crease, and "the step page is just a composition" all conflict.
Several topics every PRD will need are also uncovered: folding only the top
layers of folded paper, the channel that carries move intent to the page,
exact landmarks, measured cost, and the study's input contract.

## 1. Spot checks

| # | Claim (file) | Verdict | Evidence |
| --- | --- | --- | --- |
| 1 | `Folded` has exactly `foldedFrame`, `foldedPattern`, `foldedPlacements :: IntMap Rigid`; `foldFrameWith :: Frame -> Either FoldingError Folded` (A1, C, G) | confirmed | `Origami/Folding.hs:283-331` |
| 2 | With no `edges_foldAngle`, every M/V edge folds to ∓180 at once (A1) | confirmed | `foldAnglesOf`, `Folding.hs:507-532` (`fromAssignment`) |
| 3 | The walk holds the first face still, "`faces !! 0`" (A1) | confirmed (wording) | Root is the first face, but the code is a total pattern match `(f : _)`, not `!!` (`Folding.hs:577-588`). The claim is right and the quote is a paraphrase. |
| 4 | `creaseAllAlong` clears `facesVertices`, `faceOrders`, `frameExtras`; new M/V creases get ±180 when an angle array exists (A1, E2) | confirmed | `Fold/Creasing.hs:252-268`, `280-320` (`flatAngleFor`) |
| 5 | `motionsBetween` refuses frames whose `edges_vertices` or `faces_vertices` differ (A1, C, D) | confirmed | `Origami/Step.hs:88-96`, `118-126` |
| 6 | `prepareFlapAlong` rebuilds the start and refuses `FlapStartMismatch`; travel ≤ 360; hinge must be M/V/U, so an `F` edge is `FlapNotHinge` (A1, A2) | confirmed | `Origami/Flap.hs:161-195` |
| 7 | `creaseThroughLayers :: V2 -> V2 -> Assignment -> Frame -> Either ThroughError Frame`, points read in folded coordinates, assignment named from +z, returns a pattern (A1, E2) | confirmed | `Origami/ThroughLayers.hs:216-227` |
| 8 | GLB `extras.senbazuru.frame` keeps only `senbazuru:material_coords`, `source_panels`, `source_edges`; any other vendor key is dropped (C) | confirmed | `Render/Gltf.hs:237-242` |
| 9 | `surfaceDiagram = creasePatternAuto theme budget view . surfaceFrame` (C, B) | confirmed | `Render/CreasePattern.hs:152-157` |
| 10 | `stepPage :: Theme -> Budget -> Grid -> View -> Bool -> [Frame] -> Either StepError (Maybe Diagram)`; skips frames with no vertices; arrows from `motionsBetween` (A1, C) | confirmed | `Render/Steps.hs:90-129` |
| 11 | Blintz recipe rows `(EdgeId 8..11, FaceId 2/3/4/1, -180)` plus reopen `(EdgeId 8, FaceId 2, 180)`; handoff writes angles and orders onto `foldedPattern start` (A1, A2, E2, F) | confirmed | `study/fold-material/BlintzSequence.hs:50-63` |
| 12 | Helmet moves `([8,9],5,180)`, `([10,12],1,180)`, `([13,11],2,180)` after moving the quad to the front (A2) | confirmed | `HelmetSequence.hs:41-51` |
| 13 | The manifest's blintz folds the corners to +90/+175, and the flap recipe folds them to −180 (A2 F3) | confirmed | `cases.json:61-71` vs `BlintzSequence.hs:51-54`. The manifest's orders put the centre below each corner along +z. |
| 14 | `--steps` refuses `--frame`, `--fold`, `--stacking` (C, D) | confirmed | `app/Senbazuru/Cli.hs:843-851` |
| 15 | `decodeFile` decodes any unrecognised extension as FOLD, so a scheme passed to an existing verb fails as JSON (C) | confirmed | `Fold/Load.hs:102-106` |
| 16 | `StudyCase` resolves panels and `fixedPanel` by a material point strictly inside exactly one face, tolerance `1e-10` (A2, E2, F) | confirmed | `StudyCase.hs:139-143`, `165-170` |
| 17 | `Surface` constructor is hidden; `transformSurface` and `withFaceOrders` drop `frameExtras`; `materialFrame` adds `senbazuru:material_coords`; thickness not serialised there (A1, B) | confirmed | `Origami/Surface.hs:26-27`, `242-263`, `284-296` |
| 18 | `Rigid (..)` is exported and nothing checks it is a rotation (A1) | confirmed | `Geometry/Rigid.hs:24-36` |
| 19 | `ContactError` is a `newtype` over `Text` (A1) | confirmed | `Origami/Contact.hs:77` |
| 20 | `quarter-fold-steps.fold`: three frames, all `BBBBBBBBMVMM`, 12 edges, 4 faces, no `faceOrders`; angles on edges 8-11 go 0 → `[-180,0,-180,0]` → `[-180,180,-180,-180]` (C, D C1/C3) | confirmed | `jq` on `examples/quarter-fold-steps.fold` |
| 21 | lts-22.44 pins megaparsec 9.5.0, parser-combinators 1.3.0, prettyprinter 1.7.1 (C, F) | confirmed | `lts-22.44.cabal.config:1917`, `2214`, `2345` |
| 22 | The solver's `ContactMode` includes `PacketContact FoldCase`; `relaxPinnedHinges` pins are keyed by refined mesh vertex id (B) | confirmed | `FoldRelaxation.hs:297`, `244-252` |
| 23 | Rest angles are never defaulted from `edges_foldAngle` (B) | confirmed | `FoldBending.hs:138-145` |
| 24 | No library module reads `frameTitle` (C) | confirmed | `grep frameTitle src` outside `Fold/Types.hs` finds nothing |
| 25 | Library errors carry CLI flag names (`creaseEndFlag` → `--from`) (F) | confirmed | `Fold/Query.hs:68-70`; used at `ThroughLayers.hs:195` |
| 26 | #104 cites `docs/notes/inflate-outside-draw-inside.md`, which does not exist (G) | confirmed | #104 body, paragraph 2; no such file in `docs/notes/` |
| 27 | Manifest rabbit-ear literal at m = 30 is not bit-reproducible from the documented formula; `175*(90/175)` is `89.99999999999999` (A2 F8, F32) | confirmed (in Python) | `docs/notes/rabbit-ear-motion.md:39-41` formula gives `97.58514830800294`, manifest has `…293`; m = 15, 60, 175 match. GHC not run. |
| 28 | The glossary defines rest angle twice, differently (D) | confirmed | `docs/glossary.md:19` and `:83` |
| 29 | The crane-wing recipe finds its hinge as "every `Unassigned` edge" after `creaseAllAlong`, and picks stacking index `[2]` (A2 F5) | confirmed | `CraneWing.hs:60-79`. Consequence no file draws out: the new hinge is **U at angle 0**, a third convention for an unbent crease (see contradiction 3). |
| 30 | Test suite compiles the study (D A20, B) | confirmed | `senbazuru.cabal:193` `hs-source-dirs: test, study/fold-material` |
| 31 | "A resolved per-state full angle list is what … the CLI's `render --steps` already consume" (A2 implication 12, citing `docs/architecture.md:436-441`) | **wrong** | Those lines say `buildCaseSequence` writes folded frames with coplanar `faceOrders`. `stepPage` draws positions, and `--steps` refuses `--fold` (`Cli.hs:844`). An angle table can be an internal intermediate form, but the CLI does not read one. |
| 32 | "#95's proposed half-turn keeps the centre fixed too", so no arrow (C finding 27) | **wrong** | #95 specifies `(x, y, z) ↦ (−x, y, −z)`, a half turn about the page axis at x = 0. The quarter fold's final frame spans x ∈ [0.5, 1] (`jq`), so its centre moves to x ≈ −0.75 and `Step` would report a translation. D C5 has this right. |

Not checked: external-source claims (papers, Khronos READMEs, licences on
GitHub/SourceForge), recorded study timings, and the literature numbers in B
and G. Each file already lists these as unverified.

## 2. Contradictions between files

1. **Where the turn-over axis passes.** C (finding 27) says #95's half turn
   keeps the centre fixed. D (C5) says it turns about x = 0 and moves the
   model. #95's formula supports D (spot check 32). PRDs must fix the axis,
   for example through the model's centre, and must not cite C here.
2. **Is turn-over a frame move or presentation?** #95, D (it "closes #95,
   since `TurnOver` becomes one constructor") and F's sketch (`TurnOver` as a
   core `Step`) treat it as `apply :: Move -> Frame -> Frame`. A1 says
   turn-over is "not a move": a `Rigid` kept outside the pattern and applied
   at export. A1 gives the reason. The next `foldFrameWith` re-anchors face 0
   at its pattern position, and refuses a folded-form frame (`AlreadyFolded`),
   so a turn written into coordinates is lost or refused at the next step. A1
   also says "valley" in a later step must be mapped back through that
   presentation, which a frame-level `TurnOver` loses.
3. **What an existing but unbent crease is written as.** Four conventions
   appear, and no file puts them side by side:
   - A1 (b): keep M/V and set the angle to 0, so `Flap` accepts it later.
   - E1's move table and `docs/notes/precreases-and-target-states.md`: `F` at
     0. But `Flap` refuses `F` as a hinge (spot check 6).
   - `Creasing.hs` ("a valley with an angle of zero is not a valley") and
     PR #72 via D C3: M/V at 0 is wrong. Yet `quarter-fold-steps.fold` uses
     exactly that (spot check 20).
   - `CraneWing.hs:60-66`: `U` at 0 (spot check 29).
4. **What `render --steps` consumes.** A2 implication 12 says angle tables. C
   (finding 16, contract (iii)) says already-folded frames. C is right (spot
   check 31).
5. **"The step page is a composition."** F (finding 5 and `stepFrames ::
   [StepResult] -> [Frame]`) presents run → project → `stepPage` as
   straightforward. A1 (c) and C (findings 25, contract (i)-(ii)) show that
   `motionsBetween` refuses any pair whose crease graph differs. Every
   crease-adding step then breaks arrows, unless later creases are backfilled
   into earlier frames. Backfilling draws future creases at step 1.
6. **Whether an SVG wireframe of relaxed paper is feasible.** B (finding 12)
   and `docs/architecture.md:402-407` say relaxed meshes stay out of SVG
   deliberately, because the painter assumes a layer order they can violate.
   G (finding 22, implication 7) treats a refined bent panel as a set of
   convex planar faces that `Visible`/`Projected` already handle. C (finding
   5) notes `Projected` declines intersecting panels. B (finding 15) records
   accepted meshes that cross within tolerance (−6.21e-9 passes a 1e-7
   check). So G's route may decline or fall back on exactly the meshes PRD 3
   produces.
7. **How the anchor is named.** A2 (implication 2) and E2 say anchor by a
   material point and never store a `FaceId` across steps. G (implication 3
   and ladder row G0) lists "the anchor face" as per-state data. A1's sketch
   caches both a first-face-anchored `Folded` and a `V2` anchor, and asks
   whether that is one representation too many.
8. **Whether #114's component invariant is met.** D (C8) says #146's
   done-when 2 met it. G (finding 2) says glTF graphics indices are still one
   component per face, so a test must count material components through
   extras.
9. **Evidence for megaparsec's version.** C (finding 23) warns that
   `stackage.org/lts-22.44/package/megaparsec` served an LTS 24.59 page
   (9.7.0) and is not evidence. F (finding 18) cites that page as its
   evidence. Both conclude 9.5.0, and the vendored cabal.config confirms it
   (spot check 21). PRDs should cite the cabal.config, not the package page.
10. **Doodle's licence.** E1 reports GPLv2 from SourceForge. C, D and F say
    "not checked" or unverified, matching `docs/related-projects.md:38`. E1 is
    the only file that looked; treat Doodle as GPL for ideas only.

## 3. Gaps, most important first

### 3.1 `layer-selective-folds` — folding only some layers of already-folded paper

Most book steps after the first few are "fold the top flap along this line".
No file works this through with real calls:

- E2 notes `ThroughLayers` creases every layer.
- A1 leaves top-layers-only as an open question.
- D (A17) says the move has no implementation.

`CraneWing.hs:55-120` is a hand-written instance: it clips a line to
hand-picked faces `[2,3,6,7]`, maps it back with inverse placements, creases
with `U`, recovers the hinge, and picks a stacking index. Nobody has turned it
into a rule. **Brief** in the index.

### 3.2 `assignment-at-rest-convention` — how an unbent crease is written in every frame

Contradiction 3 shows four conventions. The choice decides three things: FOLD
validity, whether `Flap` can later turn the crease, and whether the
quarter-fold-steps golden moves. D lists the FOLD-spec question as
unverified. **Brief** in the index.

### 3.3 `step-annotation-channel` — how move intent reaches the page

C and D establish what `Step` cannot infer: turn-over, rotation, arrow kind,
precrease, and top layers versus all. They also say vendor keys will not carry
it. Nobody specifies:

- the typed value itself;
- where it enters `Diagram` or `Layout` under the two-unit rule;
- how a page handles a crease graph that grows between frames;
- which goldens stay byte-identical.

**Brief** in the index.

### 3.4 `exact-landmarks-and-macro-binding` — exact references, and coupled macros on arbitrary patterns

F's sketch types fractions as `Rational`. The bird base's petal vertices
are irrational (0.5·(√2−1)), and `PetalCertificate` works in Q(√2). E2
requires refusing near-miss decimals. A2 and E1 both say macros must bind
crease roles, but every existing binding is a fixture's positional edge list.
No file says how landmarks are represented exactly, or how a
petal/rabbit-ear/collapse finds its roles on a pattern it was not written for.
**Brief** in the index.

### 3.5 `sequence-cost-and-test-budget` — measured per-step cost and an end-to-end test plan

No file measured what a rigid interpreter costs per step:
`withPlanarFaces` + `foldFrameWith` + `prepareFlapAlong` + `checkFlap`, on a
crane-sized pattern over a 20-step sequence. A1 says so under Unverified, and
the repo rule is to measure. CI already spends 10m48s in `stack test` (#208).
Test ideas exist in A2 (F27-F31), C and F (round-trip property), but no file
assembles text → run → FOLD/SVG/GLB acceptance with platform-sensitive bytes
named. **Brief** in the index.

### 3.6 `study-consumption-contract` — what PRD 3 receives, and how existing recipes migrate

B proposes `settle :: SettleSpec -> Surface V2 -> Either SettleError Settled`
and leaves hold naming open. A2 notes certificates are study values the
library cannot import. No file specifies:

- the per-step record a run hands the study;
- how holds, grips and contact panels are named from a scheme;
- how certificates attach to stages;
- which of the blintz, helmet, crane-wing, bird, frog and `cases.json`
  recipes become schemes;
- whether driving an Apache-2.0 solver out of process fits AGENTS.md's
  third-party rules, which are written for vendored material.

**Brief** in the index.

## 4. Smaller accuracy notes for PRD authors

- The Blintz module comment says its illustration poses are "90 degrees and
  the endpoint". The code uses `flapAt 0.5`, labelled "halfway". For a −180
  travel these agree. F32's warning about progress arithmetic applies when a
  scheme states absolute angles.
- `docs/related-projects.md` still says "not checked" for Doodle and "GPL (not
  checked)" for ReferenceFinder. E1 and E2 supply GPLv2 and GPL-2.0. A PRD
  that relies on either should cite E1/E2's URLs, not the repo table.
- #56's claim that per-face transforms are discarded is stale, because
  `foldedPlacements` exists (C, confirmed via spot check 1). #94's "nothing
  reads `frame_title`" is half stale: the CLI reads it (`Cli.hs:779, 879`)
  and the library does not (spot check 24).
- G's animation analysis (nested nodes along `spanningWalk`, slerp exact under
  180° per key) is derived, not measured. Loop-closing creases between keys
  are unmeasured. That belongs with gap 3.5, not a separate gap.
