# Review L1: code feasibility of the design spine

> **Historical record.** Part of the design review of the PRD series, kept so its citations resolve. Line numbers cite the draft named in the file; the current decisions are [../../decisions.md](../../decisions.md).

Reviewer lens: are D1–D17 and the §4 type sketches buildable against the source
at `568dcb6`, are cited functions described correctly, and does any decision
need a larger change than it says. Nothing was compiled. Evidence is `path:line`
read in this session, `jq` on fixtures, or research-note sections. A claim I
worked out from the code but did not run is marked **[reasoned]**.

Severity: critical = a PRD written from the decision would be wrong or
unbuildable; major = materially wrong or missing something the PRDs need;
minor = wording, naming, small gaps.

---

## Objections

### L1-1 (major) · D5, §1 layer order: the turn-over axis "in page axes" puts `Render.Camera` inside `Sequence.Run`, and makes written FOLD depend on `--view` and on later steps

**Claim.** D5 builds the presentation `Rigid` about an axis "through the centre
of the model's projected extent **in page axes**, with the camera basis chosen
from the unturned frames". That basis is `Render.CreasePattern.basisFor`
(`CreasePattern.hs:509-510`) over `Render.Camera` (`Camera.hs:74-79, 106-136`).
Three problems follow.

1. **Layering.** §1 orders `… → Sequence → Render → app` and says `Sequence.Run`
   runs "over Fold.* and Origami.* only". It cannot import `Render.Camera`.
2. **Look-ahead.** With no view named, the basis is `isometric` if *any* frame
   has relief, else `topDown` (`CreasePattern.hs:521-524`; `Steps.hs:107`
   chooses from all frames together). So a turn at step 3 depends on whether
   step 20 leaves the plane. D4's argument for the state rule is "needs no
   look-ahead, so a failing step can be reported before later steps run". That
   argument does not survive here.
3. **Display leaks into data.** D13 offers `--view` only for `-o .svg`, and D14
   says display parameters are "never sequence data". Yet the coordinates in
   `run -o x.fold` would depend on a camera choice. A `--view top` page and the
   written `.fold` would disagree whenever the auto view is isometric.

**Evidence.** `src/Senbazuru/Render/CreasePattern.hs:509-524`;
`src/Senbazuru/Render/Steps.hs:106-107`; spine §1 lines 62, 79-80; D4 "Why";
gap-step-annotation-channel F14–F15, where the note itself says the basis must
be fixed first and "depends on the vertices".

**Proposal.** Replace D5's axis bullet with a model-intrinsic rule computed in
`Sequence.Run` from `Geometry` alone:

> `turn over left-right` is a half turn about the line parallel to model **+y**
> through `(cx, cy, cz)`. `turn over top-bottom` is the same about model **+x**.
> `rotate` turns about model **+z** through the same point. `cx` and `cy` are
> the centre of the current state's xy bounding box; `cz` is the middle of its
> z range. The camera is not consulted.

Under `topDown`, `basisRight = +x`, `basisUp = +y` and `basisForward = −z`
(worked from `Camera.hs:91-98, 106-107`). So for flat models this is exactly the
page-axis turn in gap-step-annotation F14, including its "extent unchanged"
property. For isometric pages, say that the page extent may change, and stop
claiming otherwise. A half turn about model y or x keeps every axis span, so
`hasRelief` (and with it the auto basis) cannot flip because of a turn over.

---

### L1-2 (major) · D5 + D4: presented flat frames need a `frame_classes` rule, or `render --fold` and `crease` on a written file build the mirror model

**Claim.** D5 writes frames **presented**. The spine never says which
`frame_classes` those frames carry.

- **If** a presented but unfolded sheet (all angles 0, turned over) is written
  `creasePattern`, as `examples/quarter-fold-steps.fold` writes its key frame:
  - its coordinates are the sheet mirrored in x, with z still 0;
  - `foldFrameWith` re-winds every ring counter-clockwise and lifts a valley's
    child towards +z (`Folding.hs:39-54, 436-447, 650-653`);
  - but on the turned sheet the top side faces −z.
  
  So `render --fold`, `export --fold` or `crease` on that frame folds the
  reflection through the sheet's plane, i.e. **the mirror model** **[reasoned]**.
  AGENTS.md warns about exactly this: "A wrong flip folds perfectly well and is
  the mirror model."
- **If** instead every frame comes out `foldedForm`, as `surfaceFromFolded`
  topology does (`Folding.hs:386, 398-400`; `Surface.hs:201-210`), two things
  change:
  - the step-1 figure is drawn in `FoldedFormNotation`, not crease-pattern
    notation (`CreasePattern.hs:546-548`);
  - `crease FILE` on that frame is refused with `SheetIsFolded` (`Faces.hs:184`).
  
  Both are changes from how `quarter-fold-steps.fold` behaves today.

**Evidence.**

- `jq` on `examples/quarter-fold-steps.fold`: top level `["creasePattern"]`,
  file frames `["foldedForm"]` twice.
- `src/Senbazuru/Origami/Folding.hs:39-54, 386`.
- `src/Senbazuru/Render/CreasePattern.hs:546-548`.

**Proposal.** Add to D4's "Every frame `Sequence.Write` emits":

> - `frame_classes` is `foldedForm` for every state frame whose presentation is
>   not the identity, and for every frame with a non-zero angle. Only an
>   unpresented, all-zero-angle frame may be written `creasePattern`. A writer
>   test folds each `creasePattern` frame it wrote and compares the result with
>   the run's own state. The change that turns it red is writing a turned sheet
>   as `creasePattern`.

---

### L1-3 (major) · D3 invariant 5: "re-anchor jump-free because the new root is aligned to its current placement" has nowhere to live in `FoldState`, and conflicts with D5's exact presentation

**Claim.**

- **Why a hold jumps.** `foldFrameWith` always places the first face at
  `identity`, i.e. at its flat material position (`Folding.hs:577-585`). After
  `hold P` puts a moved face first, the refold puts that face back flat, and
  the whole model jumps by that face's old placement. Being jump-free needs a
  stored *alignment* motion, applied to every later refold.
- **No field for it.** The §4 `FoldState` lists only "anchor, presentation". The
  alignment cannot be folded into `presentation`: D5 says that `Rigid` is
  "built from exact ±1 matrices". A face's placement after a 90° wing turn or a
  175° petal is built with `rotationAbout`, from `cos` and `sin`
  (`Rigid.hs:114-129`).
- **Flap refuses an aligned start.** Flap rejects any start whose positions are
  not an untouched `foldFrameWith` within 1e-9 × span (`Flap.hs:171-181`,
  `FlapStartMismatch`). So the alignment must be applied *outside* Flap, to its
  output surfaces. `transformSurface` then drops `frameExtras`
  (`Surface.hs:287-296`), so material coordinates must be put back afterwards.
- **The join check.** Invariant 6 has to compare positions *after* alignment.

**Evidence.** `src/Senbazuru/Origami/Folding.hs:577-585`;
`src/Senbazuru/Origami/Flap.hs:171-181, 339-352`;
`src/Senbazuru/Geometry/Rigid.hs:114-129`;
`study/fold-material/BlintzSequence.hs:5-8` ("anchoring a corner would turn the
whole model").

**Proposal.** In §4 and D3:

> `FoldState` holds `stateAlignment :: Rigid` (proper, trig-derived, identity
> until the first `hold`) and `statePresentation :: Rigid` (proper, exact ±1
> entries).
>
> - A state's displayed positions are `presentation ∘ alignment ∘ foldFrameWith
>   workingPattern`.
> - `hold P` sets `alignment := alignment ∘ placement(newAnchorFace)` from the
>   raw fold, then reorders faces and re-maps orders.
> - Flap and ThroughLayers always receive the raw fold. The runner applies
>   alignment, then presentation, to what they return.
> - The join check compares aligned positions.

---

### L1-4 (major) · D3 invariant 3: "never patch a `Folded`" forbids the only way to hand Flap its mandatory stack orders

**Claim.** Flap reads the orders it needs from the `foldedFrame` it is given
(`Flap.hs:223`: `suppliedOrders = faceOrders suppliedFrame`). It refuses a
touching stack without them (A2 F18: the helmet test strips orders and expects
refusal). Its start check compares angle count, face rings and positions
(`Flap.hs:173-181`), never orders. The only precedent sets them by patching:
`folded {foldedFrame = frame {faceOrders = orders}}` (`CraneWing.hs:79`). Read
literally, invariant 3 makes every fold on a stacked model unbuildable.

**Evidence.** `src/Senbazuru/Origami/Flap.hs:171-181, 223-235`;
`study/fold-material/CraneWing.hs:79`; A2 F15, F18.

**Proposal.** Replace invariant 3 with:

> 3. Re-fold after every handoff. Never change a `Folded`'s coordinates, faces,
>    angles or placements (`FlapStartMismatch`, `Flap.hs:173-181`). Hand
>    accepted orders to Flap only by setting `foldedFrame.faceOrders` on an
>    untouched `foldFrameWith` result (`CraneWing.hs:79`). Write them against
>    `foldedFrame`'s counter-clockwise rings, never `foldedPattern`'s
>    (`Folding.hs:303-308`).

---

### L1-5 (major) · D3, D8: intent M/V at angle 0 contradicts `creaseAllAlong`, so the "exact" `carryOrders` and the new API need an explicit angle policy

**Claim.** D3's working pattern always records explicit `edges_foldAngle`, with
intent M/V on every crease, precreases included. But `creaseAllAlong` writes
`flatAngleFor` (M → −180, V → +180) for every new crease whenever the angle
array exists (`Creasing.hs:290-292, 316-320`). It also documents this as
deliberate: "A valley with an angle of nought is not a valley"
(`Creasing.hs:281-286`). ThroughLayers passes a real M/V per layer
(`ThroughLayers.hs:296`).

So a `creaseLayersThrough … Valley` on the working pattern would fold every new
crease flat at once. D8's "exact, since a crease at angle 0 moves no paper" is
false for that output. The precedent dodges the problem by creasing `Unassigned`
and finding the hinge as "every U edge" (`CraneWing.hs:65, 101`), which is
correction 14. Changing new creases to 0 inside the shared function would in
turn change `crease --folded` (`Cli.hs:761`) and the ThroughLayers tests, which
say "The creases are written at plus or minus 180" (`ThroughLayersSpec.hs:135`).
That breaks D8's "goldens unchanged".

**Evidence.**

- `src/Senbazuru/Fold/Creasing.hs:281-292, 316-320`;
  `src/Senbazuru/Origami/ThroughLayers.hs:261-264, 296`.
- `test/Senbazuru/Origami/ThroughLayersSpec.hs:135`.
- `study/fold-material/CraneWing.hs:65, 101`.
- gap-layer-selective-folds finding 4 ("through this API an unselected layer's
  crease 'at angle 0' can only be U or F").

**Proposal.** In D8's library bullet:

> `creaseLayersThrough :: NewCreaseAngle -> Set FaceId -> V2 -> V2 ->
> Assignment -> Folded -> Either ThroughError Creased`, with
> `data NewCreaseAngle = AtRest | FlatForAssignment`.
>
> - `AtRest` writes every new piece at angle 0 with its per-layer intent
>   assignment. The runner uses it, and `carryOrders` is exact only on its
>   output.
> - `creaseThroughLayers` keeps its behaviour by passing `FlatForAssignment`.
>
> The same choice is exposed in `Fold.Creasing`, e.g. `creaseAllAlongWith`,
> because the flat-sheet runner needs it too. Record in D3 that the working
> pattern departs from `Fold.Creasing`'s "valley at 0 is not a valley" on
> purpose, and that written frames (D4) restore it.

---

### L1-6 (major) · D5 + D8: "senses as seen by the reader" has two possible implementations and the spine allows both, so a turned model gets a double flip or none

**Claim.** `ThroughLayers.facesUp` reads the placement's image of +z
(`ThroughLayers.hs:321-328`) and flips the caller's assignment on face-down
layers.

- **Case A.** Hand it a *presented* `Folded`, where a turn over sends +z to −z.
  Every layer flips, which is already the "as seen from the viewer at +z"
  mapping.
- **Case B.** D5 says "the runner maps a sense through the presentation" before
  the call. Doing that *and* passing the presented `Folded` flips twice. Doing
  neither with a raw `Folded` flips never.

D8's signature takes a `Folded` without saying which. The constructor is public,
so nothing checks (`Flap.hs:169-170`). L1-3 already requires the raw fold for
Flap, so the two moves would disagree unless this is pinned.

**Evidence.** `src/Senbazuru/Origami/ThroughLayers.hs:227-229, 285-296,
321-328`; `src/Senbazuru/Origami/Flap.hs:169-181`; spine D5 bullet 3, D8
signature, §4 `Sense`.

**Proposal.** In D8:

> The `Folded` is the untouched `foldFrameWith` result of the working pattern.
> The line is given in its (raw) coordinates, with the runner undoing alignment
> and presentation first. The `Assignment` is named from raw +z. The runner
> alone converts the reader's `Sense`: raw assignment = `Sense` negated when
> `(presentation ∘ alignment)` sends +z to −z.

Add an acceptance test: the quarter fold, turned over, then `fold valley` along
the diagonal, writes the same pattern as `fold mountain` on the unturned model.
The change that turns it red is either missing flip or a doubled one.

---

### L1-7 (major) · D10, D14 `StepRecord`: a crease-and-turn step has three numberings, and the record fields assume two

**Claim.** A step like the crane wing, "fold valley 90 … flap containing", does
three things: it creases, it re-traces, and it turns.

- **The ids live in the middle state.** Hinge ids, moving faces and the
  `CheckedFlap` exist only in the creased pattern. That is `CraneWing`'s
  `frame` after `creaseAllAlong` (`CraneWing.hs:60-80`).
- **Before and after disagree.** `recordBefore` (uncreased) numbers edges and
  faces differently from `recordAfter`. Cutting replaces old edges in place,
  shifting later ids (`Crossings.hs:310, 343-347`), and faces are re-traced.
- **So several fields cannot be built.**
  - `recordAngles :: ([Double],[Double])` cannot be index-aligned.
  - The research sketch's "ids resolved in stepBefore's numbering"
    (gap-study-consumption-contract, sketch `stepHinge`) is impossible for this
    kind of move.
  - Holds like `band S d0..d1`, "distance from the hinge in the start pose",
    need the hinge in the numbering of the pose they measure.
- **Record equality.** `CheckedFlap` derives only `Show` (`Flap.hs:95-96`), so a
  `StepRecord` holding it cannot derive `Eq`. The blintz/helmet equivalence PRs
  (D16) will need a comparison projection.
- **Duplicated state.** `recordOrders` and `recordRequirements` repeat what
  `Surface` already stores (`Surface.hs:115-122, 257-263, 306-312`). Two copies
  can disagree.

**Evidence.** `study/fold-material/CraneWing.hs:56-80`;
`src/Senbazuru/Fold/Crossings.hs:304-315, 343-358`;
`src/Senbazuru/Origami/Flap.hs:95-96`; gap-study-consumption-contract finding 7
and open question 4.

**Proposal.** In D14 and §4:

> A pattern-changing move emits **two** records sharing one caption and one
> figure pair.
>
> 1. `Crease` (`NoMotion`): before = old numbering; after = creased pattern at
>    angle 0 (identical positions); `recordNewCreases` bridges the two.
> 2. The turn (`SweptHinge`/`Sampled`/`StateOnly`): before and after both in
>    the creased numbering.
>
> Invariant: within one record, `recordBefore` and `recordAfter` have equal
> `edgesVertices` and `facesVertices`, except for `Crease` records. Orders and
> requirements are read from the surfaces, never stored twice. `StepRecord`
> has no `Eq`; tests compare `recordProjection :: StepRecord ->
> ComparableRecord`, which drops the evidence.

---

### L1-8 (major) · D3, D13, §5: the initial state from `sheet "file"` is unspecified; the blintz and bird fixtures would start already folded

**Claim.** `jq` on the fixtures:

- `examples/blintz-base.fold` records `edges_foldAngle` with −180 on edges 8–11.
- `examples/bird-base.fold` records ±180 on 20 creases.
- `examples/crane.fold` records no angles (129 assignments).

D3 says the working pattern carries "explicit `edges_foldAngle`", and D11 treats
`start folded` as the case that takes angles from the sheet. The spine never says
the file's angles are replaced by zeros for an ordinary `sheet`. The only
precedent does exactly that: `foldFrameWith source {edgesFoldAngle = replicate n
0, …}` (`BlintzSequence.hs:43`). Without the rule, §5's blintz example starts as
a finished blintz.

Also unspecified: which frame of a multi-frame file is the sheet
(`quarter-fold-steps.fold` has 2 `file_frames`; `Fold.Load.loadFile` returns a
whole `FoldFile`, `Load.hs:127`), and what to do with a file already classed
`foldedForm`.

**Evidence.** `jq` summaries above; `study/fold-material/BlintzSequence.hs:43`;
`src/Senbazuru/Fold/Load.hs:127`; `src/Senbazuru/Origami/Folding.hs:507-532`.

**Proposal.** Add to D3:

> **Initialisation.** `sheet "f"` loads `f` through `Fold.Load`.
>
> - It takes the key frame, and refuses a file whose key frame has no geometry
>   or is `foldedForm` (naming it).
> - It drops `faceOrders` and `frameExtras` and applies `withPlanarFaces`.
> - It sets **every** angle to 0.
> - It keeps each M/V assignment as intent and records F/U/B/C/J as given.
>
> `start folded` instead takes the file's `edges_foldAngle` when present, else
> ±180 from the assignments, exactly as `foldAnglesOf` does.

---

### L1-9 (major) · D2 + §5: `centre` is classified as a vertex reference, and the §5 blintz example is then refused

**Claim.** D2's rules say a "Material point as a **vertex** (`corner`, `centre`,
landmark)" must lie within tolerance of exactly one vertex, and a near miss is
refused. But `examples/blintz-base.fold` has no vertex at (0.5, 0.5). Its eight
vertices are the corners and edge midpoints. The centre lies strictly inside the
central diamond. So "fold mountain corner bottom-right to centre" is refused by
D2's own rule. The same holds for `sheet square`, the most common book start. O2
(`P to Q`) needs only a *position*, and a region point supplies one.

**Evidence.** `jq '.vertices_coords' examples/blintz-base.fold` returns
`[[0,0],[1,0],[1,1],[0,1],[0.5,0],[1,0.5],[0.5,1],[0,0.5]]`;
`study/fold-material/BlintzSequence.hs:44-46` (five faces, the diamond is the
four-cornered one).

**Proposal.** Replace the two resolution bullets with:

> A material point resolves to a **vertex** when exactly one vertex lies within
> `Fold.Faces.tolerance`. It resolves to a **region** when it lies strictly
> inside exactly one face and within tolerance of no vertex or edge. Otherwise
> it is refused, naming what was found.
>
> Constructions O1–O7 accept either kind. `crease P-Q` and landmark
> definitions require vertices.

---

### L1-10 (major) · D7 vs D5: `StepNote`'s "presentation change applied to later figures" would present the frames a second time, and the arrows switch exists twice

**Claim.** D5 writes frames already presented. D7's `StepNote` carries a
"presentation change applied to later figures", which reads as an instruction
to transform coordinates again inside `stepPageWith`.

Separately, `stepPageWith` keeps `stepPage`'s `Bool` arrows argument
(`Steps.hs:90-100`) *and* adds `InferArrows | InferArrowsAs | GivenArrows |
NoArrows` per note. A PRD has to say which wins.

Because `stepPageWith` receives presented frames, it also cannot choose "the
basis from unturned frames" (D5) unless each note carries the cumulative motion
to undo. L1-1 removes that need.

**Evidence.** `src/Senbazuru/Render/Steps.hs:90-129`; spine D5 bullet 4, D7
bullet 2.

**Proposal.** In D7:

> `StepNote.notePresentation :: Maybe PresentationChange` only places a
> `Symbol` and suppresses inference on that pair. Frames arrive presented and
> `stepPageWith` never transforms coordinates.
>
> `stepPageWith` drops the `Bool`: `stepPage … arrows = stepPageWith … . map
> (\f -> (f, noteFor arrows))`, where `noteFor True = InferArrows` and
> `noteFor False = NoArrows`.

---

### L1-11 (minor) · D6 `motionsAcross`: `motionCreases` cannot reuse `motionsBetween`'s index zip across renumbered edges

**Claim.** `Motion.motionCreases` is computed by zipping `edgesFoldAngle` of
the two frames **by index** (`Step.hs:150-159`). When the edge graph grew, old
ids shift, because each cut edge is replaced in place (`Crossings.hs:310,
343-347`). An index zip would then report the wrong creases, or none.

Placing a new vertex that lies inside a `before` face needs a point-in-ring test
in material coordinates. A crease pattern's faces need not be convex, so a
convex clip cannot be reused for it.

**Evidence.** `src/Senbazuru/Origami/Step.hs:71-80, 150-165`;
`src/Senbazuru/Fold/Crossings.hs:304-315, 343-358`.

**Proposal.** Add to D6:

> `motionsAcross` reports `motionCreases` as **after's** edge ids. It matches
> each after edge to a before edge whose material segment contains both its
> endpoints, and an unmatched edge counts as new, never as "changed". Faces are
> located by a non-convex point-in-polygon test on material rings.

---

### L1-12 (minor) · D8 "one small library addition": the new-id suffix is real, but no function returns its length, and the change touches four modules

**Claim.** The suffix claim checks out: new creases are appended last
(`Creasing.hs:255`), and cutting keeps edge order (`Crossings.hs:267-271,
310`). So every piece of every new crease comes after every old piece. But
neither `creaseAllAlong` nor `splitCrossings` reports how many pieces the old
edges became, so the suffix's start is not computable from the output alone.

Returning it needs `Fold.Crossings.rebuilt`'s `chains`, surfaced through
`Fold.Creasing`. Together with the exported cover query (`nearness` is not
exported, `Visible.hs:100-106`) and L1-5's angle policy, the "small addition"
touches `Fold.Crossings`, `Fold.Creasing`, `Origami.ThroughLayers` and
`Origami.Visible`.

**Evidence.** `src/Senbazuru/Fold/Creasing.hs:252-268`;
`src/Senbazuru/Fold/Crossings.hs:304-358`;
`src/Senbazuru/Origami/Visible.hs:100-106, 240-270`.

**Proposal.** Reword D8's library bullet to list the modules, and add:

> `Fold.Creasing.creaseAllAlongWith :: NewCreaseAngle -> [(V2,V2,Assignment)]
> -> Frame -> Either FoldError (Frame, [EdgeId])`, where the ids are the pieces
> of the requested creases, taken from `rebuilt`'s chains rather than inferred
> from counts.

---

### L1-13 (minor) · D3 invariant 6: "CheckedBird strength: positions within `1e-12 × span`" misdescribes CheckedBird

**Claim.** `CheckedBird.samePoints` uses an **absolute** `norm (a ^-^ b) <
1e-12` (`CheckedBird.hs:149`; its header says "within 1e-12 model units",
`:12`). The relative `1e-12 * scale` is Blintz's and Helmet's
(`BlintzSequence.hs:69`, `HelmetSequence.hs:64`). On a 400-unit sheet the
absolute form is 400 times stricter than the relative one.

**Evidence.** `study/fold-material/CheckedBird.hs:12, 145-149`;
`study/fold-material/BlintzSequence.hs:69`.

**Proposal.** Write invariant 6 as:

> positions within `1e-12 × modelSpan` (`BlintzSequence.hs:69`); exact angles,
> edge lists, face rings, orders and material coordinates (the checks of
> `CheckedBird.hs:145-146`).

---

### L1-14 (minor) · D5: `rotate N/D` cannot be "built from exact ±1 matrices" except for quarter turns

**Claim.** §4 has `Rotate Rational`, and D5 says every presentation `Rigid` has
exact ±1 entries. A 1/8 turn needs entries of √2/2. `Mat3` is public
(`Rigid.hs:28-35, 51`), so exact quarter turns can be built directly. Any other
fraction has to go through `cos`/`sin` (`Rigid.hs:119-120`).

**Evidence.** `src/Senbazuru/Geometry/Rigid.hs:28-40, 51, 114-129`; spine §4
`Rotate Rational`.

**Proposal.** Either:

> `rotate` takes quarter turns only in v1 (`Rotate Int`, counted anticlockwise
> as seen); other angles are refused by the static check.

or state that non-quarter rotations use `rotationAbout` and are excluded from
the exactness claim. Either way, give the proper-rotation check as
`det = +1 within 1e-12`.

---

### L1-15 (minor) · D4, D14: `surfaceFeatures` disagrees between the working pattern and the written frame on flat precreases

**Claim.** `surfaceFeatures` counts a crease as a feature when its assignment is
M/V/U/B/C, or its angle is nonzero (`Surface.hs:274-282`). A precreased-and-flat
crease is M at 0 in the working pattern (a feature) and F at 0 in the written
frame (not a feature). So D14's realistic glTF (normals split at, and `LINES`
from, feature edges) and the W1 provenance wireframe would differ depending on
the source: built from `StepRecord` surfaces, or from `export` of the written
`.fold`. That clashes with D13's "nothing downstream of a written FOLD file may
know it came from a sequence".

Two things are unaffected. The G0 GLB does not call `surfaceFeatures` today
(`rg` finds it only in `Surface.hs` and study code). Stacking reads angle first
and assignment only at angle 0 (`Stacking.hs:705-728`), and for a tortilla
(paper continuing flat across the crease, as it does at angle 0) `creaseRule`
adds nothing (`:636-639`). So layer orders are not affected.

**Evidence.** `src/Senbazuru/Origami/Surface.hs:274-282`;
`src/Senbazuru/Origami/Stacking.hs:636-639, 705-728`; `rg surfaceFeatures`
output.

**Proposal.** Add to D14:

> Realistic outputs take feature edges from the **written** state (state rule)
> plus `recordNewCreases` provenance. `run -o x.glb` and `export x.fold` must
> produce identical bytes in every mode. The acceptance test uses a precreased
> blintz corner.

---

### L1-16 (minor) · D1, D12: library dependencies and the `Explain` fragment contract

**Claim.**

- **Missing dependencies.** The library stanza's `build-depends` is aeson,
  base, bytestring, containers, filepath, tagsoup and text
  (`senbazuru.cabal`). D1's `Build a = State BuildState a` needs `mtl` or
  `transformers`, and D12 adds `megaparsec` and `parser-combinators`. Only the
  last two are named.
- **Multi-line parser text.** megaparsec's error text is multi-line: its
  unexpected/expecting lines each end in a newline. `Explain` asks for a
  lower-case fragment with no full stop that a caller puts after a colon
  (`Explain.hs:62-68`). The megaparsec behaviour is from its 9.x documentation;
  not run here.

**Evidence.** `senbazuru.cabal` library stanza; research
`lts-22.44.cabal.config:1917, 2214` (megaparsec 9.5.0 and parser-combinators
1.3.0 are present); `src/Senbazuru/Explain.hs:62-72`.

**Proposal.** In D12:

> The library adds `megaparsec`, `parser-combinators` and `transformers` (for
> `Control.Monad.Trans.State.Strict`; no `mtl`). `ParseProblem` stores a
> `Span` plus megaparsec's unexpected/expected items as data. Its `explain`
> joins them into one line (`"expected a point, found \"centre-\""`). Only
> `excerpt` emits multiple lines.

---

### L1-17 (minor) · D12: `SequenceError` cannot delegate to nested `explain`, which names CLI flags and step-local ids

**Claim.** Nested messages speak the CLI's words, not the sequence's.

- **Flag names.** `ThroughError.LineStopsOnTheModel` prints `--from`/`--to` via
  `creaseEndFlag` (`ThroughLayers.hs:194-201`, `Query.hs:68-71`).
- **Internal ids.** Flap and Folding messages name edge and face ids of the
  step-local cut pattern (`Flap.hs:130-148`; `Folding.hs:180-218`). D2 says
  those ids "never appear in the language".

So `instance Explain SequenceError` must pattern-match through `FoldError`,
`FoldingError`, `FlapError` and `ThroughError` (the flag can arrive as
`CannotCrease (CreaseEndMeetsNothing …)`). It cannot just call `explain`, and
the spine's single sentence underestimates that work.

**Evidence.** `src/Senbazuru/Origami/ThroughLayers.hs:194-209`;
`src/Senbazuru/Fold/Query.hs:68-71, 173, 312-316`;
`src/Senbazuru/Origami/Flap.hs:124-150`.

**Proposal.** In D12:

> `StepRefused` carries the step's resolved references. Its `explain` prints
> the author's reference text first, then the library reason, with ids written
> as `(internal edge 37)`. `CreaseEnd` is rendered as "the line's first/second
> end". The PRD lists every constructor that needs translating, with a golden
> error-text test each.

---

### L1-18 (minor) · D7: call-site count, silent wildcard matchers, and caption height at defaults

**Claim.**

- **Call sites.** `stepPage` has 23 call lines across 15 files, not "about
  fifteen call sites" (`rg "stepPage "` without imports).
- **Silent matchers.** Adding `Symbol` makes `-Wincomplete-patterns` flag
  `shapePoints`, `mapShapePoints` and `shapeToSvg`. It does **not** flag the
  wildcard `\case … _ ->` matchers in `LayoutSpec.hs:32-35, 42-44` and
  `CreasePatternSpec.hs:394`, which will silently ignore the new constructor
  (gap-step-annotation-channel (b)). The spine does not carry that warning.
- **Caption height.** Gutter height on the page at the defaults:
  - the inputs: page 400 wide, margin 16, `--columns 3`, `gridGutter 0.1`
    (`Svg.hs:98-106`, `Cli.hs:587-590`, `Layout.hs:95, 121`);
  - the page is 3.2 figure widths across 368 pt of content, so one figure is
    about 115 pt wide;
  - the gutter is 0.1 of that, about 11.5 pt, against `themeLabelSize = 14`
    (`Style.hs:227`).
  
  A caption in the gutter therefore overlaps its own figure at the defaults
  (my arithmetic, not rendered). The note accepts that trade; the spine does
  not mention it.

**Evidence.** Files cited above; `rg` output.

**Proposal.** Correct D7's count to "23 calls in 15 files; `stepPage` keeps its
signature, so none change". Add a D7 residue bullet:

> Captions overlap their own figure whenever `gutter × page scale <
> themeLabelSize`, which includes the default 3-column page. The PRD states
> whether that is accepted, or whether captioned pages default to a larger
> gutter.

---

### L1-19 (minor) · D11: filtering stackings by relations meets capped enumeration

**Claim.** `stackingSpace` enumerates each component only up to the budget
(`Stacking.hs:457-458`). A capped component is marked `choiceCapped`, and
`solveStackingAs` refuses rather than guess (`Stacking.hs:437-445`). "Refuse 0
or ≥2 survivors" is therefore a fact only for components whose search finished.
Filtering must also be done per component, because `stateCount` is a product
(one Flat-Folder file has 10^83, `Stacking.hs:405-407`). A relation between
faces in two different components is unsatisfiable, not ambiguous.

**Evidence.** `src/Senbazuru/Origami/Stacking.hs:402-458, 802-810`.

**Proposal.** In D11:

> Relations filter each component's `choiceStates` separately. A relation whose
> two faces are in different components, or do not overlap, is refused as
> unordered. A component still ambiguous after filtering whose enumeration was
> capped is refused as `GaveUpStacking` with the budget, never counted.
> `StackingChoice` records one index per component plus the relations.

---

### L1-20 (minor) · D5: `Origami.Step`'s header states the opposite design, and there is no rigid fit to classify with

**Claim.** `Step.hs:30-34` says "a step may move paper without changing any
angle, by turning the whole model over. The coordinates are what the reader is
looking at", so it counts a turn over as a motion. D5 reverses that without
saying the header changes.

Classifying a whole-model motion needs a rigid fit. `Origami.Step` imports only
V3 and vector-space helpers (`Step.hs:49-63`), and nothing in `Geometry.Rigid`
fits a motion to point pairs. The identity (nothing moved) must not be
classified as a presentation. For a z = 0 model, a mirror in the plane and a
half turn about an in-plane axis give identical coordinates, so the fit must
return the proper rotation.

**Evidence.** `src/Senbazuru/Origami/Step.hs:30-34, 49-63, 137-142`;
`src/Senbazuru/Geometry/Rigid.hs:27-40`.

**Proposal.** In D5:

> Add `Geometry.Rigid.fitRigid :: [(V3, V3)] -> Maybe Rigid`. It builds frames
> from three non-collinear point pairs and accepts only if every pair agrees
> within `1e-9 × max 1 modelSpan`, the tolerance of `Step.hs:141`. It returns a
> proper rotation.
>
> `motionsBetween` returns `[]` for a pair it fits, other than the identity.
> The Step header paragraph at lines 30-34 is rewritten in the same PR.

---

### L1-21 (minor) · §4 sketch inconsistencies

**Claim.**

- **Two signatures.** D1 gives `sequenceOf :: Build () -> Sequence`; §4 gives
  `sequenceOf :: SequenceHeader -> Build () -> Sequence`, and `SequenceHeader`
  is defined nowhere (§4 has `StepHeader` and `Sequence`).
- **Two anchors.** `Sequence.seqAnchor :: Point` exists, but §5's crane example
  also needs `start folded` with relations. `StartFolded [Relation]` is a
  `Step`, so the start state is split between header and first step.
- **No stationary face.** `recordStationary :: Maybe (MaterialPoint, FaceId)`
  needs Flap's stationary face, which is not exported (`Flap.hs:49-59`: no
  accessor for `stationaryFace`). The runner must recompute it the way
  `Flap.hs:193-195` does.

**Evidence.** Spine D1 line 95, §4 lines 673-680; `src/Senbazuru/Origami/Flap.hs:49-59,
193-195`.

**Proposal.**

> Use one signature, `sequenceOf :: Header -> Build () -> Sequence`, and define
> `data Header = Header { title, sheet, anchor, start :: Start, material }` with
> `data Start = StartFlat | StartFolded [Relation]`. Remove `StartFolded` from
> `Step`.
>
> For `recordStationary`, either add `flapStationaryFace :: CheckedFlap ->
> FaceId` to `Origami.Flap`, or state that the runner recomputes it as the face
> across the first hinge crease from the moving seed.

---

## Confirmations (checked and found correct)

- **D6 vertex-prefix claim holds across creasing.** `creaseAllAlong` appends
  new vertices after the existing ones (`Creasing.hs:204, 236-241, 254`), and
  reuses an existing or batch vertex within tolerance (`:231-245`).
  `splitCrossings.rebuilt` keeps every existing row untouched and appends
  crossings (`Crossings.hs:309, 334-341`). `mergedCrossings` drops a crossing
  near an existing vertex rather than moving it (`:180-185`). Across a flap turn
  or macro the graph is unchanged: Flap refolds the same pattern with only
  angles changed (`Flap.hs:343-345`). Across presentation, vertex ids are
  untouched and `transformSurface` moves positions only (`Surface.hs:287-296`).
  Re-anchoring reorders faces, not vertices (`CraneWing.hs:61-63`).
- **The new-crease pieces really are an edge-list suffix.** Old edge ids shift
  when earlier edges are cut (`Creasing.hs:255`; `Crossings.hs:267-271, 310,
  343-347`).
- **`existingAt` returns the first vertex within tolerance, not the nearest**
  (`Creasing.hs:322-327`), as D2 residue and correction 13 say. The batch path
  does take the nearest (`:243-245`).
- **`Fold.Faces.tolerance` is `1e-9 ×` the diagonal of the sheet's bounding box**
  (`Faces.hs:248-251`).
- **Flap derives per-segment travel signs from the stationary face's ring
  direction** (`Flap.hs:208-216`), as D5 cites.
- **`rotationAbout` uses `cos`/`sin`, and `Rigid(..)` and `Mat3(..)` are
  exported unchecked** (`Rigid.hs:28-40, 51, 76-79, 114-129`), so exact ±1
  quarter turns are constructible and nothing refuses a reflection.
- **`foldFrameWith` roots the walk at the first listed face**
  (`Folding.hs:577-585`) and re-signs orders whose second face was re-wound
  (`Folding.hs:482-486`). Putting the anchor face first before orders exist is
  the precedent's mechanism (`CraneWing.hs:61-63`, `BlintzSequence.hs:44-47`).
- **Stacking does not disagree between intent-M-at-0 and state-rule-F-at-0.**
  Direction comes from a nonzero angle first, else the assignment
  (`Stacking.hs:705-728`), and `creaseRule` only uses it for a taco
  (`:636-639`). An angle-0 crease is a tortilla. D4's working/written split
  changes no layer order.
- **`Visible.nearness` treats unrecorded pairs as "neither nearer", refuses
  contradictory pairs, and is not exported** (`Visible.hs:100-106, 240-270`).
  D8's "export an ordered-cover query that refuses unordered overlaps" is a
  real addition, not a re-export.
- **ArrowPath defaults can emit today's bytes.** `ArrowPath` is only ever built
  in `Style.arrowFor` (`Style.hs:364-372`), and the head is drawn in one place
  (`Svg.hs:197-238`). A default head shape that selects the existing `head'`
  code leaves goldens unchanged.
- **`stepPage` has the signature D7 extends** (`Steps.hs:90-100`), and
  `withArrows` reads only `motionFrom`/`motionTo` (`CreasePattern.hs:592-604`).
- **The GLB copies exactly three `senbazuru:` extras keys**
  (`Gltf.hs:241`), as D7/D10 say. `transformSurface` and `withFaceOrders` drop
  `frameExtras` (`Surface.hs:263, 292`), so writing material coordinates and
  assurance after the last transform (D10) is necessary.
- **Goldens and budgets.** 33 tracked goldens (`git ls-files test/golden | wc
  -l` = 33). `HingeSweep.defaultSweepSettings = SweepSettings 20 4096`
  (`HingeSweep.hs:95`), the 4096 D16 budgets against.
- **megaparsec 9.5.0 and parser-combinators 1.3.0 are in the pinned snapshot**
  (research `lts-22.44.cabal.config:1917, 2214`).
- **Every existing CLI verb goes through `withFoldFile`** (`Cli.hs:693-697`), so
  a separate `run` path is needed as D13 says.
