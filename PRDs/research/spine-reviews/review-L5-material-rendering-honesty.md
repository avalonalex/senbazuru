# Review L5: material consumption and realistic rendering

> **Historical record.** Part of the design review of the PRD series, kept so its citations resolve. Line numbers cite the draft named in the file; the current decisions are [../../decisions.md](../../decisions.md).

Lens: D14, D15, the fidelity ladder, the "production-feasible now" claims, the
`StepRecord` → `settleStep` contract, G1 animation, the W1 wireframe, M6–M8
ordering, and D17.

Read-only review against `568dcb6`. Nothing was built or run. Evidence is either
a `file:line` I read, a command I ran (`gh issue view`, `git ls-files`, `grep`),
or a research-note section. Where I could not check something, I say so and the
severity is at most minor.

---

## Objections

### L5-1 (critical) — W1 as specified would refuse the only bent meshes the study produces

**Decision:** D14 "SVG wireframe"; the ladder's W1.

**Claim.** The spine removes hidden lines "via `Render.Projected` on refined
convex triangles", and wherever `Projected` declines it refuses by name. The
accepted crane meshes already fail that path today. W1 as written would
therefore refuse the M6 fixture, which is the one G3 output that exists.

**Evidence.**
- **The study already draws these meshes through the same path.** The crane
  spread and crane root SVGs go through
  `stepPage` → `creasePatternFrom` → `layerOrderFor` → `visibleForm` → (`PaperInTheAir`)
  → `projectedForm`. The call is at `CraneSpreadGallery.hs:125-130`, and
  `CraneRootGallery.hs:77` reuses `spreadSvg`. The dispatch is
  `CreasePattern.hs:215-240`.
- **`Projected` declined on them.** When `projectedForm` returns `Nothing`, the
  fallbacks draw every crease, buried or not (`CreasePattern.hs:222-224`, `:249-254`).
  The docs record exactly that outcome on accepted meshes: "The SVG outline path
  also retains some buried crease lines here" (`docs/usage.md:464-465`;
  `docs/tour.md:596-597`). Triangles are convex, so the `ConcaveFace` branch
  does not apply. The fallback was reached because `Projected` declined.
- **The tolerances disagree by a factor of 100.** `Projected` treats any pair
  whose depth gaps change sign by more than `hair = 1e-9 × scale` as
  intersecting and declines (`Projected.hs:56`, `:149-154`). Contact acceptance
  uses `panelTolerance = 1e-7` (`Origami/Contact.hs:83-84`). B finding 15
  records a real crossing of −6.21e-9 that passes acceptance, which is beyond
  `Projected`'s hair.
- **The same code also refuses outright.** `Projected`'s coverage guard returns
  `ImpossibleStacking`. #206 (open) records it on an *accepted* crane-root mesh
  of 4,312 triangles, through `PaperMesh.visiblePaper` → `projectedForm`
  (`PaperMesh.hs:137-141`).
- **The glTF path is more lenient.** The visible glTF scene groups coplanar
  panels at the export quantum, `1e-6 × span` (`PaperMesh.hs:106-112`;
  `Gltf.hs` `quantumFor`), a thousand times looser. So "the GLB visible scene
  works" is not evidence that the SVG will.
- **The architecture already says this.** "Corrected meshes use the
  depth-buffered viewer because the SVG painter assumes the very layer order
  those meshes can violate" (`docs/architecture.md:402-404`). Z-critic §6
  raised the same risk, and the spine did not answer it.

**Proposal.** Replace the W1 bullet in D14 with:

> **SVG wireframe (W1)** is a *line* drawing, not filled regions. Candidate
> segments are:
> - source creases and boundaries, by provenance (`strokeFor Join = Nothing`
>   already hides triangulation edges, `Style.hs:280-281`);
> - silhouette segments, meaning J edges where the sign of `normal · view`
>   changes (#104's rule).
>
> A segment's visibility comes from point-sampled depth tests against the
> refined triangles. Every test uses **the contact acceptance tolerance**
> (`Origami.Contact.panelTolerance`), never `Projected`'s hair: a point within
> that tolerance of a covering triangle counts as lying on it. So a mesh that
> passes the independent contact check always draws. A drawing with filled
> regions through `Render.Projected` is an optional extra, attempted only when
> `Projected` accepts. When it declines, output falls back to the line drawing,
> which is labelled.
>
> Acceptance: on the accepted crane-spread meshes (`curved`, 392 triangles, and
> `fine`, 1,192), no hidden crease line is drawn. The change that turns this red
> is switching the visibility test back to `Projected`'s `1e-9` hair. Cost is
> counted as segment samples × candidate triangles and measured (3–5 compiled
> runs) at 392, 1,192 and 4,312 triangles before any size is promised.

---

### L5-2 (major) — "G0/G1 + A1/A2 + W1" adds almost nothing visible to a rigid sequence

**Decision:** D14 "Realistic for an arbitrary sequence".

**Claim.** The spine calls G0/G1 + A1/A2 + W1 "production-feasible, no new
physics" realism for any sequence. On rigid states, most of that list changes
nothing a viewer can see:
- **A1.** Normals averaged within a *planar* panel and split at creases are the
  panel's flat normal. Viewers already compute exactly that.
- **W1 silhouettes.** On planar panels a silhouette can only lie on a crease or
  boundary, and those are already drawn.

What a user actually gets for an arbitrary sequence at M7 is animation, UVs
(textures only if L5-3 is resolved) and possibly lines.

**Evidence.**
- Viewers already compute flat normals, and the module says why that is enough:
  "No normals are written. The specification requires a viewer to compute flat
  normals ... and flat is exactly right for paper" (`Gltf.hs:49-50`; G finding 1).
- G finding 21: on planar panels, the sign of `normal · view` changes only
  between panels.
- Measured on the crane: dropping non-silhouette edges removed 6 of 242 edge
  copies (`docs/notes/layer-numbers.md:111-115`).
- Bent-panel rendering is recorded as "a study-to-production gap"
  (`docs/roadmap.md:62`).

**Proposal.** Replace that paragraph with:

> **What M7 changes for a rigid sequence:**
> - G1 animation of checked routes;
> - `TEXCOORD_0` from material coordinates, which is invisible until a texture
>   exists;
> - optionally, crease lines (L5-3).
>
> A1 normals and W1 silhouettes are *identical to today's picture* on planar
> panels. They matter only for bent (G3) meshes. The first time a reader sees
> paper that is not flat is a G3 settle: study output at M6, production at M8.
> The PRD must not describe M7 output of a rigid sequence as "realistic paper".

---

### L5-3 (major) — A2 textures and glTF LINES are not "production-feasible now"

**Decision:** D14 appearance axis A2; "Realistic glTF ... optional LINES primitives".

**Claim.** Each of these hides a cost or an unverified assumption:
- **Textures need image data** in the GLB. The library has no image encoder
  and no dependency that could provide one. Nothing in the repo generates an
  image. A "fibre texture" is either a vendored asset, which needs provenance
  and a licence, or a procedural PNG, which needs a hand-rolled deflate/CRC
  writer or a new dependency.
- **Lines may not display.** LINES primitives lie exactly on the triangles, and
  glTF has no polygon offset. Origami Simulator needs `polygonOffset` to keep
  its lines visible. Whether Blender and three.js display coincident LINES at
  all is unverified.

**Evidence.**
- `senbazuru.cabal:152-159`: the library depends on aeson, base, bytestring,
  containers, filepath, tagsoup and text only.
- G finding 10: Origami Simulator pushes the paper behind its lines with
  `polygonOffset` (`model.js:83-111`).
- C open question 8: support for LINES and sheen in generic viewers is "Needs a
  measured check".
- I did not run any viewer, so the rendering part of this objection is
  unverified.

**Proposal.**
- In D14, split A2 into **A2a** (`TEXCOORD_0` from material coordinates; cheap,
  M7) and **A2b** (textures; blocked on an owner decision between a vendored
  image with provenance and a PNG writer or a new dependency).
- Make LINES a **spike with a measured result** before it becomes a
  requirement: validator issue count, and a screenshot from three.js
  (`study/gltf/viewer.html`) and from headless Blender.
- If lines are kept, offset them along the averaged normal by a named *display*
  epsilon recorded in extras, never written into `extras.senbazuru.frame`.

---

### L5-4 (major) — `recordBefore` is ambiguous for a fold that adds a crease, and the settle contract needs the creased, unturned state

**Decision:** D14 `StepRecord`; §4 sketch.

**Claim.** In D8 a single `Fold` step may crease and then turn, which is two
library moves. `CraneSpread` refines the state *after creasing and before
turning*, and its hinge ids exist only in that numbering. The sketch has
`recordBefore`, `recordAfter` and `recordNewCreases`, but it never says:
- whether `recordBefore` is the uncreased or the creased state;
- which numbering `recordHinge`, `recordMoving`, `recordStationary`,
  `fst recordAngles` and `recordOrders` use.

If `recordBefore` is the uncreased state, the hinge ids do not exist in it.
Material segments cannot stand in for them: the settle needs `EdgeId`s in the
refined surface's source numbering (`FoldBending.hs` `hingesForSurface` keys
rest angles by `EdgeId`).

**Evidence.**
- The start is the creased, re-folded state with its chosen orders:
  `CraneWing.hs:61-85` (`creased <- creaseAllAlong`, `folded <- foldFrameWith creased`,
  `start = folded {…orders}`).
- The hinge is taken from that frame (`:65-66`).
- `CraneSpread.hs:85` refines `surfaceFromFolded (craneStart wing)`.
- `:91` looks hinge ids up in that same numbering.
- Gap-study F7: a crease-adding step's before and after states number the same
  paper differently.

**Proposal.** Add to D14 and the §4 sketch:

> A step that creases and then moves emits **two records** under one
> `recordPath`:
> - a `NoMotion` crease record, whose `recordAfter` is the creased, unturned
>   state;
> - a motion record whose `recordBefore` *is* that creased state.
>
> Invariant: every id in a record (`recordHinge`, `recordMoving`,
> `recordStationary`, `fst recordAngles`, `recordOrders`) is in
> `recordBefore`'s numbering, except `snd recordAngles`, which is in
> `recordAfter`'s. A test pins this on the crane wing: the hinge ids of the
> motion record equal `craneHinge`, and its `recordBefore` refines to the same
> triangle count as `CraneSpread`. The change that turns it red is a runner
> that folds before recording the crease.

---

### L5-5 (major) — the record carries a pose only for swept hinges, but settle and G1 both need poses at chosen progress

**Decision:** D14 grip targets `rigid-pose p`; G1 "loop-closing creases checked
at sampled midpoints"; D10 `Sampled SampleReport`.

**Claim.** Only a swept hinge carries a pose function:
- For `SweptHinge CheckedFlap`, `flapAt` gives a `Surface V2` at any progress.
- `Sampled SampleReport` holds a report, not poses.
- `StateOnly`, `NoMotion` and `Presented` have no route at all.

So `rigid-pose p` on a macro step, and G1's midpoint loop check, cannot be
built from `StepRecord` as sketched. There is a second gap: `flapAt` returns
positions, not per-face `Rigid`s. G1's node transforms need placements, so each
animation key means re-folding the angle list, which is a counted cost.

**Evidence.**
- `Flap.hs:285-294`: `flapAt :: CheckedFlap -> Double -> Either FlapError (Surface V2)`.
- `foldedPlacements` exists only on `Folded` (`Folding.hs:283-322`).
- Gap-study (a) sketch: `SweepChecked CheckedFlap -- gives flapAt`.
- Gap-sequence-cost F6: about 7 folds per checked step, read from code.

**Proposal.** Add a field to the sketch:
`recordPoseAt :: Rational -> Either MoveFailure Pose`, where
`Pose = Pose { poseAngles :: [Double], poseSurface :: Surface V2, posePlacements :: IntMap Rigid }`.
Define it per evidence type:
- **`SweptHinge`:** refold at `flapAt`'s angles.
- **`Sampled`:** evaluate the macro's role formulas at the parameter, then refold.
- **`StateOnly`, `NoMotion`, `Presented`:** `Left NoRoute`.

Rules that follow:
- `rigid-pose p` resolves through `recordPoseAt` and is refused by name on steps
  with no route.
- G1 key density is a `RunSettings` value, separate from the author's
  illustration `sample` list.
- `--report` counts the refolds.

---

### L5-6 (major) — no rest-angle policy is specified, and the one sketched is either id-based or a no-op

**Decision:** D14 `SettleSpec.settleRest :: RestAngles`; D4 consequences.

**Claim.** `RestAngles` is never defined. B's sketch offers two forms, and
neither works:
- `Explicit (Map EdgeId Double)` names creases by id, which D14 forbids.
- `AchievedAngles` is a no-op by B finding 6.

What `CraneSpread` actually does is "the hinge rests at the pose angle; every
other crease rests at ±π by assignment". The spine names that nowhere.

It also never says which assignments the record's `Surface`s carry:
- **Working-pattern intent (M/V at 0 for precreases).** `surfaceFeatures` then
  marks those creases active, and `FoldBending` demands a rest angle for each.
- **The state rule (F at 0).** Precreases are then not creases to the solver.
  They get `PanelBend` with rest 0 and *panel* stiffness, so a precrease resists
  bending like uncreased paper.

Either choice silently changes the physics.

**Evidence.**
- `CraneSpread.hs:90-94` is the rest rule.
- `Surface.hs` `surfaceFeatures`: a crease is active if it is B/M/V/U/C or its
  angle exceeds 1e-10.
- `FoldBending.hs` `hingesForSurface` (read at `:156-183`): a rest angle is
  required for every active non-border crease, the sign must match M/V, and a
  segment with no control is classified `PanelBend, 0`.
- Spine D4 says the consumer takes rest intent "from the StepRecord" but gives
  no field for it.

**Proposal.** Define:

> `data RestAngles = RestAtPose Rational | RestAtPoseExcept Rational [(CreaseLine, Rational)]`
>
> Every active crease rests at its angle in `recordPoseAt p`. Exceptions name
> creases by material segment, in degrees, as the reader sees them. There is no
> `EdgeId` form and no "achieved" form, because a settle must state what differs
> (B finding 6).

Also:
- Record surfaces carry **state-rule** assignments.
- Intent lives in a separate field, `recordIntent :: [(MaterialSegment, Sense)]`.
- The PRD states the precrease policy explicitly: *a crease flat at the pose
  gets crease stiffness with rest 0, not panel stiffness*. This is a decision
  for the owner, marked open.

Acceptance: the crane spread's `RestAtPose (1/3)` produces the same `targets`
map as `CraneSpread.hs:94`. The change that turns it red is a
`Mountain → +π` sign slip.

---

### L5-7 (major) — "settle from that step's rigid state" is not what CraneSpread does, and the crane example's settle-only step has no referent

**Decision:** D14 "Settles are independent per step from that step's rigid
state"; §5 crane example; §4 `StepHeader.stepSettle`.

**Claim.**
1. **`CraneSpread` starts from the flat before state, not the after state.** It
   refines the flat wing at 0°, takes contact orders from that state's
   *coplanar* `faceOrders`, and pins grips at rigid poses of 30° and 30° + extra.
   Settling from the after state (the wing at 90°) is not supported:
   - its `faceOrders` contain no wing–body pairs, so contact would not be
     modelled;
   - `SurfaceContact` refuses any pair whose triangles both stand parallel to
     the fixed direction (`UncheckableContactPair`);
   - B lists "a flap raised to 90° is not supported".
2. **The crane example's settle has no move to resolve against.** `step "Spread the wing." settle …`
   has no move. The §4 AST has no settle-only `Step`: `stepSettle` hangs off a
   header that must carry one. Its holds say `side moving` and
   `rigid-pose 1/3`, but a step with no move has no moving side and no route.

**Evidence.**
- `CraneSpread.hs:85-86`, `:108-114`, `:138`.
- `SurfaceContact.hs:189-191`: `if max lowerAlignment upperAlignment <= 1e-8 then Left (UncheckableContactPair i j)`.
- B "Not yet general" bullet 1.
- Spine §4, lines 659-673 (no settle constructor); §5, lines 811-816.

**Proposal.** Replace the D14 bullet with:

> A `settle` block attaches to the **moving step it illustrates**. It resolves
> every region against that step's motion record (L5-4). It starts from
> `recordBefore`, which must be flat: one plane, with coplanar `faceOrders`.
> Otherwise it is refused as `SettleStartNotFlat`, naming the step. Grips target
> `recordPoseAt p`. The settled surface depicts *pose p of that step with the
> named grips*, not the step's accepted end state.

Then rewrite the example so the settle sits under the fold step:
```text
step wing "Fold one wing down along the line."
  fold valley 90 model (0, 1/4)-(2, 1/4) flap containing (0.02, 0.97)
  settle
    refine moving 3
    hold closed side stationary
    hold band moving 0..1/32 at rigid-pose 1/3     # unverified equivalence, see L5-19
    grip band moving 7/32.. arc-grip 30 50
```

---

### L5-8 (major) — per-step settles make a sequence contradict itself unless settled geometry is declared an illustration

**Decision:** D14 "nothing settled is carried into the next step"; failure
policy; M6/M8 outputs.

**Claim.** Settling each step independently is the only thing the study
supports (B, "Sequencing across steps"). But the spine never says where the
settled result goes. If it replaces step k's figure or key:
- **The next rigid figure snaps back.** Step k+1 shows a flat wing again.
- **Arrows break.** A refined settled frame has different faces, so
  `motionsBetween` refuses it. `motionsAcross` would yield one motion per bent
  triangle: its vertex-id prefix holds, because `subdivide` appends midpoints.
- **The page scale moves.** The one shared page basis would be chosen partly
  from settled positions.
- **Animation breaks.** A refined mesh has a different topology from the
  rigid node hierarchy, and morph targets need equal vertex counts.

The spine also leaves open whether one `Diagnostic` refuses the whole run output
or only that step's artefact (B open question 5).

**Evidence.**
- `Step.hs:88-96`: equal `edges_vertices` and `faces_vertices` required.
- `Steps.hs:107`: one basis from all frames.
- `Surface.hs` `subdivide`: `points ++ added`.
- G finding 18c: morph deltas are per attribute over a fixed count.
- B open question 5.

**Proposal.** Add to D14:

> **Settled geometry is an illustration, never state.**
> - A settle produces a *separate artefact*: an extra GLB scene named "Settled:
>   step k at p", beside the rigid scenes, and a separate SVG page or figure.
> - It never replaces a rigid figure or key.
> - It never enters `motionsAcross`, the page basis, animation keys or any later
>   step.
> - Only steps with a `settle` block are settled. There is no default settle,
>   because a rigid state is already settled (B finding 6).
> - A `Diagnostic` refuses **that artefact only**. The rigid outputs are still
>   written, and the CLI exits nonzero naming each refused step.
> - `--rigid-fallback` substitutes nothing into the rigid outputs. It only
>   records that the settled artefact is absent.

---

### L5-9 (major) — G1 has no rule for steps that add creases

**Decision:** D14 G1; M7 "glTF animation of checked routes"; D13 `--animate`.

**Claim.** Nested nodes follow one spanning walk over one cut pattern, and
placements are keyed by that pattern's `FaceId`s. A crease-adding step
re-cuts the pattern, so step k+1's faces do not exist in step k's hierarchy.
The spine does not say what an animation across such a step is.

**Evidence.**
- Placements are keyed by the cut pattern (`Folding.hs:283-322`), and the walk
  roots at the first face (`:581-584`).
- A1 (c) and gap-study F7: creasing renumbers faces.
- G finding 18d: glTF can switch pieces only through TRS, for example a
  STEP-keyed scale of 0/1. `KHR_node_visibility` is unsupported in three.js and
  Blender.

**Proposal.** Add to D14 G1:

> **Build one hierarchy for the whole run**, over the **final cut pattern**, so
> every crease the run ever makes has its node from the first key.
> - **Placing earlier states.** Each earlier state places a final face with the
>   `Rigid` of the face that contains it. This is exact for rigid states,
>   because cutting only subdivides and vertex ids survive (D6).
> - **Not-yet-made creases.** They sit at angle 0 and are invisible in
>   triangles. LINES for them are either omitted or STEP-scaled in at their
>   crease step.
> - **Why this is not the backfill D6 rejected.** D6 rejected backfill for
>   pages, where unborn creases get *drawn*. Here nothing unborn is drawn.
>
> Acceptance: the blintz sequence animates, and at every key time each final
> face's world transform equals that state's placement within `1e-12 × span`.
> The change that turns it red is keying placements by the earlier state's
> `FaceId`.

---

### L5-10 (major) — G1 has no rule for re-anchoring, turn-overs or steps with no route

**Decision:** D14 G1; D3 invariant 5 (`hold P`); D5 presentation; D10 evidence
kinds.

**Claim.** Three cases are unhandled:
1. **Re-anchoring moves the root about an axis away from its origin.** The
   spanning walk roots at the anchor face. After `hold P`, the former root must
   turn about a hinge that does not pass through its node origin. With LINEAR
   translation that hinge drifts between keys, by d at a half turn (G finding
   18a's derivation).
2. **A turn-over between two keys has no defined direction.** A 180° rotation
   gives quaternions with dot product 0, so slerp can go either way. Presentation
   also rotates about the D5 axis point, not the node origin.
3. **Some steps have no route to animate.** `StateOnly` steps (`start folded`,
   `pose`, checkpoints) and `ExpectRefused` have none, so "animated along
   checked routes" gives nothing between those keys.

**Evidence.**
- `Folding.hs:581-584` (root = first face).
- G finding 18a, conditions 1-2.
- G open question "Hierarchy re-rooting".
- Spine D3.5 and D5.

**Proposal.** Add:
- **Presentation.** It is a separate top node whose origin is at the D5 axis
  point, keyed with at least 3 keys per half turn.
- **Anchors.** Each anchor segment gets its own sub-hierarchy under that
  presentation node. At a `hold` key the segments switch with STEP scale 0/1,
  and the new root's rest transform equals its current placement, so the switch
  is jump-free.
- **Steps with no route.** `StateOnly` transitions are keyed `STEP`, never
  `LINEAR`, and recorded as "state only" in `extras.senbazuru.keys`.
- **Refusals.** Any key pair that turns a tree crease by 180° or more is
  subdivided through `recordPoseAt` (L5-5), or refused if there is no route.
- **Test.** Pin a blintz variant with a `hold` between corners. At the midpoint
  between keys, the stationary face's world position moves by less than
  `1e-9 × span`. The change that turns it red is dropping the per-segment
  hierarchy.

---

### L5-11 (major) — G2 "labelled schematic" repeats a mistake the repository has already undone

**Decision:** D14 ladder G2; "Realistic … in order of availability … G2 only as
a labelled schematic"; the §3 table puts G2 in R.

**Claim.** G2 fails on nearly every real model:
- It stretches wherever a fold wraps an already-bent stack.
- Shrinking the radius does not help.
- It has no rule at vertices.
- It needs a display exaggeration of roughly 45× to be visible.

The project already shipped a display spacing named `--thickness`, which
confused a drawing aid with a physical property, and removed it. D14 lists G2
among what is available, while §3 files it as research. The `material` block
also accepts `thickness`, which nothing interprets. A "labelled schematic" that
looks like physical paper invites the same confusion, and the label does not
travel with a screenshot.

**Evidence.**
- `docs/notes/paper-thickness.md:1-17`: the spacing was removed, and why.
- `docs/notes/two-bends-need-more-than-radii.md` (read in full): 200% extension
  in the upper band, which "does not shrink when `r` is reduced"; "a controlled
  counterexample, not a double-fold physics model".
- G finding 7: about 45× exaggeration, and the vertex rule is undefined.
- `Surface.hs:21-24` and `withPhysicalThickness`: no renderer interprets
  thickness.
- Spine §2 D14 against the §3 table row R.

**Proposal.**
- Delete G2 from "Realistic … in order of availability".
- Restate the ladder as **independent axes** instead of rungs, so G3 is not read
  as requiring G2 (G's table lists G3's data as "G2 plus …"; the study's G3 has
  no thickness):
  - geometry: rigid | bent zero-thickness (study) | thickness offsets (research);
  - motion: static | animated rigid | animated flexible (research).
- In the grammar, `material { thickness … }` is either omitted in v1 or parsed
  and recorded as "stored, not interpreted" in `--report`.
- Stiffness presets are named `illustrative` (B finding 9).
- Any future offset uses a parameter named `display-exaggeration`, never
  `thickness`.

---

### L5-12 (major) — the milestone order has a missing edge, an unnecessary edge, and an unstated first deliverable

**Decision:** §3 order constraints; M6, M7.

**Claim.**
- **M6 depends on M4, but the constraints omit it.** M6 re-expresses crane
  spreading through records. The crane prefix needs `start folded` with
  relations, `flap containing` and folding some layers, which is M4 ("crane-wing
  prefix as a sequence"; D16 "crane wing waits for D8"). The constraints say only
  M2 → M6.
- **M3 → M7 is unnecessary.** Animation needs records (M2), not step-page
  plumbing. A1 normals need neither.
- **The first realistic output is never named.** It is *study-only at M6*. The
  existing crane-spread GLB can gain smooth shading as soon as a normals mode
  exists, because the gallery already exports that mesh through
  `renderSurfaceGlb VisiblePaper`.

**Evidence.**
- Spine §3 table and "Order constraints" (lines 626-627).
- §5 crane example.
- D16 migration bullet.
- `CraneSpreadGallery.hs:103-105` (accepted spread GLB exported today).
- L5-2 (A1 is invisible on rigid panels).

**Proposal.** Order constraints become:
`M1 → M2 → {M3, M4} → M5; M4 → M6 → M8; M2 → M7b; M7a free-standing; #208 gate before M6 (L5-13) and before M8`.
Split M7:
- **M7a — normals mode.** A new GLB mode with A1 normals and `TEXCOORD_0`. It
  depends on nothing new, and is demonstrated on the existing crane-spread and
  wing-bending meshes. **This is the smallest realistic deliverable a user can
  see.**
- **M7b — animation and wireframe.** G1 animation (L5-9, L5-10) and the W1 line
  drawing (L5-1).

Add a sentence: "No bent paper is reachable from the `senbazuru` CLI before M8;
before then it comes only from `senbazuru-material-study --sequence`."

---

### L5-13 (major) — the #208 gate sits after the milestone that doubles the costly test groups

**Decision:** §3 "#208 gate before M8"; D15 gates.

**Claim.** The gate protects graduation, but CI time is consumed by M6. Its
equivalence PRs (gap-study (d)) build the recipe and the sequence side by side.
The groups they touch are already the two most expensive in the suite, so M6
roughly doubles them before the gate applies.

**Evidence.**
- `gh issue view 208`: hspec 626 s over 1,387 examples; `CraneRoot` about
  164.87 s and `CraneSpread` 97.48 s (log timestamps, single runs).
- Gap-study finding 20: running old and new crane solves together doubles the
  most expensive groups.

**Proposal.**
- Move the gate: "#208's value-only line search lands before M6's crane
  equivalence PR."
- Alternatively, M6's default-CI equivalence compares **resolved hold sets
  without re-solving**: pin ids and positions, 902 orders, hinge list, refined
  triangle count. It solves once, in the slow job only.
- State the counted budget: default-CI settle ≤ 392 triangles (the accepted
  `curved` control), and larger sizes only in the slow job.

---

### L5-14 (major) — the spine never says whether record surfaces are presented, and the solver's order conversion assumes the anchor's +z

**Decision:** D5 "Written frames are presented"; D14 `recordBefore`/`recordAfter`,
`recordPresentation`.

**Claim.** `CraneSpread` converts FOLD orders to lower/upper pairs by the sign
of each face normal's z, and solves contact along `V3 0 0 1`. D11's relations
are "along the anchor's +z". If `recordBefore` arrives already turned over,
every converted pair inverts.

Separately, presenting a surface through `transformSurface` wipes its frame
extras. That removes `senbazuru:source_panels` and `source_edges`, which A1's
per-panel averaging and the GLB provenance rely on for settled meshes.

**Evidence.**
- `CraneSpread.hs:108-114` (`above = (orderStacking pair == Above) == (z > 0)`)
  and `:138` (`V3 0 0 1`).
- `Surface.hs` `transformSurface`: `frameExtras = mempty`.
- `Gltf.hs` `renderSurfaceGlb`: the extras whitelist keeps exactly those keys.

**Proposal.** Add to D14:

> Record surfaces are **unpresented**: in the anchor's frame, with +z the
> anchor's normal. `recordPresentation` is applied only by writers and renderers
> — as a camera or root-node transform for glTF and SVG, and after all checks
> and settles.
>
> Test: a sequence with `turn over` before a settled step produces the same
> contact pair list as without it. The change that turns it red is applying
> presentation inside the runner's record.

---

### L5-15 (minor) — "recorded in SVG metadata" has no carrier today

**Decision:** D14 "each output records its level"; failure policy "records the
fallback in glTF extras and SVG metadata".

**Claim.** `Render.Svg` emits only `<title>`; `Page` has no description or
metadata field. glTF's `extras.senbazuru` holds a fixed set of keys. Both
records need a new, optional field that is absent by default.

**Evidence.**
- `Render/Svg.hs:91-92`, `:143-145` (`pageTitle` → `<title>`; nothing else).
- `Gltf.hs` `renderSurfaceGlb`: `metadata` keys are version, frame,
  physicalThickness and layerRequirements.

**Proposal.**
- Add `pageDescription :: Maybe Text`, emitted as `<desc>` only when set.
- Add `extras.senbazuru.fidelity` (geometry, motion, appearance, evidence per
  key) only in the new export mode.
- Acceptance: every one of the 33 goldens is unchanged (`git ls-files test/golden | wc -l` = 33).

---

### L5-16 (minor) — M7 "closes #104" conflicts with D16's unchanged goldens

**Decision:** §3 M7 "Closes #56, #104"; D16.

**Claim.** #104 adds a silhouette pass to the *default* render path for paper in
the air. Its done-when explicitly allows `simple.fold` and `squaretwist.fold`
under `--view iso` to change. Those are tracked goldens (`simple-iso.svg`,
`squaretwist-iso.svg`). `bent-strip.svg` is a bent mesh drawn through the same
path. D16 says all 33 goldens stay byte-identical. #104's premise also cites a
note that does not exist (spine §6 item 6). Whether the bytes would actually
change was not checked.

**Evidence.**
- `gh issue view 104`, "Done when" bullet 3.
- `git ls-files test/golden`: 33 files, including `simple-iso.svg`,
  `squaretwist-iso.svg` and `bent-strip.svg`.
- `test/WingBendingSpec.hs:94-100`, and `WingBendingGallery.hs:42` rendering it
  through `stepPage`.

**Proposal.** M7 *advances* #104 rather than closing it. Silhouettes appear only
in the new W1 mode (L5-1). #104's done-when is amended to "the default render is
byte-identical; `--lines` draws the dome outline". Any default-path change is its
own reviewed PR that names every golden it moves.

---

### L5-17 (minor) — D17 drops parts of gap-study (e)

**Decision:** D17.

**Claim.** The licence facts stated agree with gap-study findings 22-24. D17
omits these:
- where kept outputs' provenance goes (`examples/README.md`, (e)1);
- that copying from Codim-IPC brings Apache §4 obligations, which differ from
  MIT's ((e)4);
- that ipc-toolkit's authors ask for citation, and a driver is a toolchain
  decision ((e)3);
- that the design-licence rule applies to patterns fed to Origami Simulator
  ((e)2);
- that none of these tools precedes the in-repo solver path, and each is a
  comparison oracle only ((e)5).

It also omits G finding 13's scope limit: IPC-family solvers cannot start from a
zero-thickness flat stack. That limits the oracle to open states.

**Evidence.** Gap-study (e)1-5 and findings 21-25; G finding 13; spine D17
lines 584-596.

**Proposal.** Append to D17:
- "Kept outputs get provenance in `examples/README.md`."
- "Reading Codim-IPC is fine; copying brings Apache-2.0 §4 obligations."
- "Cite ipc-toolkit as its authors request; a driver is new non-Haskell code, a
  toolchain decision."
- "The design-licence rule applies to patterns fed to any external tool."
- "External solvers are comparison oracles and never precede the in-repo path.
  IPC-family tools need a thickness offset before they can start from a flat
  stack, so they apply only to open states."

---

### L5-18 (minor) — D15 graduates barrier rows that no graduated solver uses, and names no triangle budget

**Decision:** D15 stage 4, "a stated triangle budget per settle".

**Claim.** The directional barrier is wired only into the local-history mode.
`relaxPinnedContact`, which stage 5 graduates, uses the penalty rows. Graduating
barrier rows in stage 4 therefore puts unused numerics into the library. The
"stated budget" is also never stated.

**Evidence.**
- B finding 11: the barrier is "wired only into the local-history mode, not into
  `relaxPinnedContact`".
- `FoldRelaxation.hs:257-261`: `relaxPinnedContact` uses `SurfaceOrder contact`.
- Accepted sizes and single-run CPU times: 392 triangles 5.76 s, 1,192 triangles
  64.30 s (`docs/notes/spreading-connected-wing.md` table).

**Proposal.**
- Stage 4 graduates the **penalty** rows only. Barrier rows stay in the study
  until a pinned barrier mode is accepted on the crane.
- Budget: "`run --settle` refuses a refined surface above N triangles, with
  N = 1,192 until measured otherwise (3–5 compiled runs after #208)".

---

### L5-19 (minor) — the crane example presents an unverified hold mapping as settled

**Decision:** §5 crane example; D14 hold vocabulary.

**Claim.** `hold band moving 0..1/32 at rigid-pose 1/3` and
`grip band moving 7/32.. arc-grip 30 50` reproduce `CraneSpread`'s constants.
The gap note marks both equivalences unverified: that `bentPoint 0` equals
`flapAt (1/3)`, and that 0.25 is the wing's full extent. `bentPoint` rotates the
root strip towards negative z by a hard-coded 30°. Whether that matches the sign
of `flapAt` for a +90 fold was not checked.

**Evidence.**
- `CraneSpread.hs:103-106`, `:120-134`.
- Gap-study "Unverified", bullets 1-2 and 3.

**Proposal.**
- Annotate the example lines `# unverified equivalence (gap-study-consumption-contract, Unverified)`.
- Make M6's first acceptance test that the resolved pin set equals `spreadPins`:
  same vertex ids, positions within `1e-12`. The change that turns it red is a
  band measured in material rather than start-pose coordinates.

---

### L5-20 (minor) — "SVG wireframe" is redefined without asking the owner

**Decision:** D14 "SVG wireframe"; the user's request (3).

**Claim.** The user asked for an "SVG wireframe". W1 is a hidden-line *line
drawing* (creases, boundaries, silhouettes) that suppresses every mesh edge.
On a gently bent wing that picture barely differs from the rigid one (L5-2). A
conventional wireframe shows the triangulation, which is what reveals curvature
in 2D. The spine changes the meaning silently.

**Evidence.**
- `Style.hs:280-281`: `Join -> Nothing`.
- The repo already has a lighter weight for buried sheets, a third of a crease
  (G finding 4; `CreasePattern.hs:69-76`).
- Spine §0 item 3 against D14.

**Proposal.** Add an open question for the owner: "Does 'SVG wireframe' mean
feature lines only, or should mesh edges show?" Offer
`--lines features|mesh` in W1. `mesh` draws visible J edges at the buried-sheet
weight, with the same visibility test as L5-1. `features` is the default.

---

## Confirmations

- **B finding 6 is true.** A rigid state is already settled: the rigid 30° crane
  control solves to edge error 1.39e-11 and panel energy 1.44e-27
  (`docs/notes/spreading-connected-wing.md` table), so "settle must state what
  differs" is correct.
- **Gap-study F1 is exact.** `CraneSpread` consumes the start `Folded`,
  `flapAt (craneOpening wing) (30/90)`, `flapMovingFaces`, `craneHinge` ids and
  the start state's `faceOrders` (`CraneSpread.hs:84-114`).
- **F2 holds.** `Flap` exports no stationary-side accessor: the export list has
  `flapAt`, `flapCheck`, `flapMovingFaces` (`Flap.hs:49-59`), while
  `stationaryFace` is a record field at `:85`. The spine's
  `recordStationary :: Maybe (MaterialPoint, FaceId)` therefore needs the
  runner to keep what it resolved.
- **F4 holds.** `FoldBending` never defaults rest angles from `edges_foldAngle`,
  demands one for every active interior crease, and checks the M/V sign
  (`FoldBending.hs` `hingesForSurface` and its `validate`).
- **The glTF baseline is as the spine describes.** No normals, lines or
  animation (`Gltf.hs:49-55`); two materials, set by base colour, metallic and
  roughness only; extras whitelist exactly
  `senbazuru:material_coords`/`source_panels`/`source_edges` (`Gltf.hs`
  `renderSurfaceGlb`, `materialKey`). So "a new mode, never a change to the
  default bytes" is achievable.
- **Refined triangles are fine for glTF.** `PaperNotPlanar` is judged per face
  (`PaperMesh.hs:99-105`), so refined triangles always pass. The visible glTF
  scene of the 392-triangle crane spread is exported today
  (`CraneSpreadGallery.hs:103-105`). Its failure mode is #206's
  `ImpossibleStacking` on 4,312 triangles, not planarity.
- **Triangulation edges already vanish from SVG.** `strokeFor` returns `Nothing`
  for `Join` (`Style.hs:280-281`), and `surfaceFeatures` never lists mesh
  diagonals (`Surface.hs` `surfaceFeatures`). "Feature edges by provenance"
  therefore needs no dihedral threshold.
- **`Projected` behaves as described.** It compares every pair of panels
  (`Projected.hs:70`) and declines non-planar or non-convex faces
  (`:120-121`) and mixed-sign gaps (`:149-154`). The spine's "measure before
  promising sizes" is warranted.
- **G1's starting point is correct.** `spanningWalk` roots at the first face and
  placements are keyed against the cut pattern (`Folding.hs:283-322`,
  `:572-584`), so nested nodes along that walk are available without new
  folding code.
- **The D17 facts check out.** Origami Simulator is MIT with no documented
  headless mode, ipc-toolkit is a library rather than a solver, and Codim-IPC's
  default CHOLMOD build links GPL Supernodal (`WITH_GPL`). All match gap-study
  findings 22-24. Spine and gap note agree that nothing is to be edited in
  AGENTS.md now.
- **The failure policy matches practice.** Keeping diagnostics out of the SVG
  painter matches `docs/architecture.md:402-404` and the study
  (`CraneRootGallery.hs:78-90` writes SVG and GLB only for accepted meshes).
- **D15 matches B.** The graduation order and the stays-in-study list agree with
  B's "Graduation order", and #208 is open with the timings quoted.
