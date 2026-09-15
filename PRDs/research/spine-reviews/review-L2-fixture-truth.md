# Review L2: fixture truth of the spine's examples and fixture facts

> **Historical record.** Part of the design review of the PRD series, kept so its citations resolve. Line numbers cite the draft named in the file; the current decisions are [../../decisions.md](../../decisions.md).

Reviewer lens: every example in spine §5 and every fixture fact at the top of §5,
checked against the fixtures, the recipes and their specs. Nothing was compiled
or run in Haskell. Numbers come from `jq`/`python3` on the fixture JSON, and from
a pure-Python re-implementation of `Origami.Folding`'s walk: rotate the child by
`-angle` about the crease directed along the parent's counter-clockwise ring,
`M[child] = M[parent] · R` (Folding.hs:33-54, 641-652). Scripts are in
[`../scripts/fixture-checks/`](../scripts/fixture-checks) (`fold.py`, `quarter.py`, `quarter2.py`, `blintz.py`,
`crane.py`, `crane2.py`, `bird.py`).

The sign convention used throughout:

- `topDown = named (V3 0 0 (-1)) (V3 0 1 0)` (Camera.hs:107). The camera looks
  along −z, so the reader is on the +z side, with page right +x and page up +y.
- A positive (valley) FOLD angle lifts the child towards the parent face's
  normal (Folding.hs:46-48). Seen from +z, paper that ends at z > 0 folded
  **towards** the reader: a valley as seen. Paper at z < 0 went **behind**: a
  mountain as seen.
- To read which side a flat fold went, fold at ±179° or ±170° with the same
  signs and look at the sign of z. A flat ±180° fold is the same rigid motion
  either way (AGENTS.md gotcha).

---

## 1. `examples/quarter-fold-steps.fold`

### What the fixture does, measured

Faces (jq `.faces_vertices`): F0 `[8,4,1,5]` = material [½,1]×[0,½]
(bottom-right), F1 `[8,5,2,6]` top-right, F2 `[8,6,3,7]` top-left, F3
`[8,7,0,4]` bottom-left. The key frame's assignments are edge 8 M, 9 V, 10 M,
11 M (jq).

| step | angles 8–11 | faces that move | where they land (probe, root F0) | sense seen from +z |
| --- | --- | --- | --- | --- |
| 1 | `[-180,0,-180,0]` | F2, F3 (material x < ½) | onto x∈[½,1], z = −0.0044 at 179°, normals −z | **mountain** (behind) |
| 2 | `[-180,180,-180,-180]` | F1, F2 (material y > ½), two layers | onto y∈[0,½], z = +0.0434 at 170° (step 1 held at exactly ±180) | **valley** (in front) |

- F0's vertices 8, 4, 1, 5 have the same coordinates in all three frames (jq).
  Exact angles reproduce the file's coordinates to 1e-9 (`quarter.py`: `True`
  for both frames).
- Step 2 moves one front-up layer, F1, and one back-up layer, F2 (frame-1
  normals +1 and −1). Edge 9 joins front-up F0 to F1 at +180; edge 11 joins
  back-up F3 to F2 at −180. Mapped through each layer's way up, both are the
  same valley as seen. gap-step-annotation-channel F10 says so too: "one valley
  fold as seen".
- **The sheet's own assignments agree.** In the key frame, edge 9 is V and edge
  11 is M. Those are the signs a valley-as-seen step 2 produces. A mountain step
  2 would give edge 9 −180 (M) and edge 11 +180 (V), the opposite of the file.
- O3 at current positions works as the spine intends. In frame 1, edge top's
  two material segments are both at `(1,1)-(0.5,1)` and edge bottom's at
  `(1,0)-(0.5,0)` (`quarter.py`). The lines are y = 1 and y = 0, their O3 is
  y = ½, and the side containing edge top holds both layers, F1 and F2.
  Step 1's O3 of x = 0 and x = 1 is x = ½, and the side containing edge left is
  F2 and F3. The **lines** and **moving sides** are right; the **sense** of step 2
  and the **anchor** are wrong.

### Corrected example

```text
fseq 1
title "A square folded into quarters"
sheet "examples/quarter-fold-steps.fold"   # its creases, at angle 0
anchor (3/4, 1/4)                          # inside face [8,4,1,5], which no step moves

step half "Fold the left half behind, onto the right."
  fold mountain edge left to edge right     # x = 1/2 lies on edges 8 and 10: no new crease
                                            # faces [8,6,3,7], [8,7,0,4] end at z < 0

step quarter "Fold the top half down in front, onto the bottom."
  fold valley edge top to edge bottom       # y = 1/2 lies on edges 9 and 11: no new crease
                                            # both layers of the top half end at z > 0
```

Expected: edges 8–11 become `[-180, 0, -180, 0]`, then `[-180, 180, -180, -180]`.
Extents are x∈[½,1], y∈[0,1], then x∈[½,1], y∈[0,½]. Both match the file.

---

## 2. `examples/blintz-base.fold` with `BlintzSequence.hs`

Measured:

- **Vertices.** There are 8: four corners and four midpoints. **No vertex is at
  (½,½)**; the nearest is 0.5 away (`blintz.py`).
- **Edges 8–11.** They are `(0.5,0)-(1,0.5)`, `(1,0.5)-(0.5,1)`,
  `(0.5,1)-(0,0.5)` and `(0,0.5)-(0.5,0)`, all `M`, and **the file's
  `edges_foldAngle` is already −180 on all four** (jq). `BlintzSequence.hs`
  zeroes them before anything else (`source {edgesFoldAngle = replicate … 0}`).
- **Face ids.** After reordering, edge 8 → face 2 `[4,1,5]` (corner (1,0)),
  9 → face 3 (corner (1,1)), 10 → face 4 (corner (0,1)), 11 → face 1 (corner
  (0,0)). This is the mapping BlintzSequenceSpec measures the angle against.
  Spec order: bottom-right, top-right, top-left, bottom-left. That is the
  spine's order.
- **O2 lines.** O2 of each corner and (½,½) contains both ends of its edge
  (`blintz.py`: `[True, True]` ×4). For example, corner (1,0) gives
  x − y = ½, which is exactly edge 8. On the flat sheet that segment is the
  whole chord, so "no new crease" holds. In later states the line only touches
  earlier folded triangles at a vertex: x + y = 1.5 meets corner 1's folded
  triangle `(0.5,0),(1,0.5),(0.5,0.5)` only at (1,0.5).
- **Sense.** With the centre anchored, each −180 sends its corner to z < 0
  (probe 179°: the moved face's centroid z = −0.002 after each move, `blintz.py`).
  Seen from +z that is **mountain**, which matches the recipe and the header's
  "Mountain folds … go below its original xy plane" (BlintzGallery.hs:3-4). The
  reopen returns face 2 to z = 0.
- **The golden looks from underneath.** checked-blintz.svg is drawn with
  `basisFrom (V3 (-1) 0 1)` (BlintzGallery.hs:38). Its forward vector has +z,
  so the camera looks up from below, where the same folds read as valleys.
- **After move 4** the four material corners meet at (½,½,0)
  (BlintzSequenceSpec.hs:106-107).

The example is right about lines, order and sense seen from +z. It fails two
spine rules: `centre` resolved as a vertex (objection L2-4), and `sheet` taken
with its angles (L2-9).

### Corrected example

```text
fseq 1
title "Blintz base, then reopen one corner"
sheet "examples/blintz-base.fold"        # creases only; the file's -180 angles are not the start
anchor centre                             # a region: strictly inside the central square

step c1 "Fold the first corner behind, to the centre."
  fold mountain corner bottom-right to centre   # x - y = 1/2 is edge 8: no new crease
step c2 "Fold the second corner behind, to the centre."
  fold mountain corner top-right to centre      # edge 9
step c3 "Fold the third corner behind, to the centre."
  fold mountain corner top-left to centre       # edge 10
step c4 "Fold the last corner behind, to the centre."
  fold mountain corner bottom-left to centre    # edge 11
step "Reopen the first corner."
  unfold c1        # reverses c1's recorded hinge and moving paper: +180 on edge 8
```

The EDSL must print the same text, captions and names included (L2-12).

---

## 3. `examples/bird-base.fold` with `CheckedBird`/`CheckedPetal`

Measured, and structurally right:

- **Route.** Collapse, front petal 0→175, back petal 0→175 with front held at
  175, then both 175→180 (`birdHinges`, CheckedBird.hs:84-87). This matches the
  spine.
- **Tips.** Hinge 26 is v9–v10 and hinge 27 is v11–v12 (jq). The only sheet
  corner joined to both ends of hinge 26 is v1 = (1,0), bottom-right; for
  hinge 27 it is v3 = (0,1), top-left (`bird.py`). two-petals.md:9-10 agrees:
  "south-east corner makes the first petal. The north-west corner makes the
  second".
- **Centre.** v8 = (½,½) is a vertex. The collapse star there has sectors
  45,45,90,45,45,90, and there is exactly one collapse match on the flat bird
  (gap-exact-landmarks F9, F13). `collapse at centre` is enough.
- **Anchor.** (0.58, 0.4) is strictly inside triangle (v8, v9, v10), with
  barycentric coordinates (0.385, 0.341, 0.273). The nearest edge is hinge 26,
  0.0798 away (`bird.py`). The triangle is on the stationary side of hinge 26.
- **Back petal.** It goes below the packet: tip z = −0.5 at u = 90°
  (two-petals.md:39). "Behind" is right as seen from +z.

It is wrong in one place: the press step cannot bind (L2-8). Also, the file's
edges carry the finished bird's ±180, so `sheet` semantics matter (L2-9).

### Corrected example

```text
fseq 1
title "Bird base from a square base"
sheet "examples/bird-base.fold"          # creases at angle 0; the file's angles are the finished bird
anchor (0.58, 0.4)                        # inside triangle (v8, v9, v10), 0.08 from hinge 26

step collapse "Collapse into a square base."
  collapse at centre to 180
  sample 30 60 90 120 150 175
step front "Petal fold the front flap up."
  petal tip corner bottom-right to 175    # binds hinge 26; the only petal match whose hinge is at 0 with tip v1
step back "Petal fold the back flap behind."
  petal tip corner top-left to 175        # binds hinge 27; the front petal (hinge at 175) no longer matches
step "Press both petals flat."
  together
    continue front to 180                 # reuses the roles pinned at step front
    continue back to 180
```

---

## 4. `examples/crane.fold` with `CraneWing.hs`/`CraneWingSpec.hs`

Measured (`crane.py`, `crane2.py`; faces in file order):

- **Assignments.** M 58, V 41, F 20, B 10; no `U` and no angles (jq).
- **The spine's anchor (0.5, 0.5) is a vertex.** It is vertex 24, at
  `(0.499999999999988, 0.5000000000000178)`, 2.1e-14 away, on edges 1 (F),
  4 (M) and 28 (M). It is not strictly inside any face.
- **CraneWing's anchor is face 0.** Its ring `[46,49,54,55]` has material
  corners `(0.866,0.324),(1,0),(1,0.5),(0.9005,0.5)`. The point **(19/20, 1/3)**
  is strictly inside face 0, 0.050 from the nearest edge.
- **Seed.** (0.02, 0.97) is strictly inside **face 7**, 0.0070 from edge 24.
  It folds to (1.0071, 0.0354), on the tip side of y = ¼.
- **Wing faces.** Material crease segments at y = ¼:
  - face 2: (0.25,0.896)–(0.25,1);
  - face 3: (0,0.75)–(0.1036,0.75);
  - face 6: (0.1768,0.8232)–(0.25,0.8964);
  - face 7: (0.1036,0.75)–(0.1768,0.8232).

  Faces 2 and 3 have folded normal **−z**; faces 6 and 7 have **+z**. This
  matches gap-layer-selective-folds F11's "face up: 2 no, 3 no, 6 yes, 7 yes".
- **Folded extent.** x∈[0.646,1.354], y∈[0,0.538], z = 0. Tip v2 is material
  (0,1) and folded (1,0,0).
- **Sense.** CraneWingSpec.hs:99 pins the tip at
  `(1, 0.25 − 0.25 cos a, −0.25 sin a)`. At +90 it ends at **z = −¼**, away
  from a +z reader.
  - Wing A (faces 2, 3, 6, 7) lies **under** wing B as seen from +z. The note's
    taco rule puts 6 over 2 and 7 over 3, and "top 2 from +z picks wing B, not
    wing A" (gap-layer-selective-folds F14, script).
  - The −90 refusal is departure "through the other wing"
    (CraneWingSpec.hs:47-53; a-wing-resting-on-paper.md:11).

  Seen from +z this is a **mountain**. It reads as a valley only from below,
  which is where checked-crane.svg looks from: `basisFrom (V3 (-1) 1 (sqrt 2))`
  has forward +z (CraneGallery.hs:36).
- **The travel sign.** "+90" is the change in the **first** hinge segment's
  FOLD angle, and the other segments take whatever sign their stationary face's
  orientation needs (Flap.hs:10-16, :216). With segments on faces of both
  orientations, the sign follows which new `U` edge happens to get the lowest
  id. It is not a physical direction. (I did not compute the edge ids after
  cutting.)
- **Tail and body.**
  - Tail faces 8–15 all contain v0 = (0,0) and fold onto one folded centroid,
    (1.1485, 0.3948).
  - The tail must be above body faces 27 and 65 and below 29 and 66, in world z
    (CraneWingSpec.hs:61-81).
  - Every tail face overlaps those body faces: `required ⊆ worldOrder`, and
    `worldOrder` comes only from `faceOrders`.
  - Points strictly inside:
    - tail face 10: (1/4, 1/5), margin 0.027;
    - body face 27: (3/8, 5/9), margin 0.049;
    - body face 29: (4/9, 3/8), margin 0.049;
    - body face 65: (0.3, 0.39), margin 0.012;
    - body face 66: (0.49, 0.065), margin 0.010.
- **Stacking.** Index 2 is picked by `solveStackingAs defaultBudget [2]`
  (CraneWing.hs:78). "Indices 0 and 1 expose the root on one side; 3 and 4
  expose it on the other" (several-stackings.md:11-12).

### Corrected example

```text
fseq 1
title "Lower one crane wing"
sheet "examples/crane.fold"
anchor (19/20, 1/3)                        # strictly inside face 0 (ring 46,49,54,55); (1/2,1/2) is vertex 24
start folded
  layers (1/4, 1/5) above (3/8, 5/9)       # a tail layer (face 10) above body face 27
  layers (4/9, 3/8) above (1/4, 1/5)       # body face 29 above that tail layer
  # UNVERIFIED: that these two leave exactly one of the five stackings. Add
  # (0.3, 0.39) and (0.49, 0.065) (faces 65, 66) if solveStacking says otherwise.

step "Fold the lower wing down, behind."
  fold mountain 90 model (0, 1/4)-(2, 1/4) flap containing (0.02, 0.97)
  # seen from +z: wing A is under wing B; its tip, material (0,1), ends at (1, 1/4, -1/4)
```

---

## 5. D5: no arrow-bearing golden has a whole-model rigid-motion pair

Arrows reach an SVG only through `stepPage … True` or `withArrows`. The tracked
goldens that do so are exactly 12:

| golden | generator | why no pair is one whole-model motion |
| --- | --- | --- |
| quarter-fold-step-1, quarter-fold-steps | SvgSpec.hs:133 (`True`), `renderStep 0` + `withArrows topDown` | F0's vertices are unchanged in all three frames (jq) |
| checked-flap, checked-flat-flap, checked-stack-flap, checked-aligned-stack | FlapSpec.hs:292, 312, 322 (`True`); `flapAt` at 0, ⅓, ⅔, 1 | poses are "aligned to keep the stationary side still" (Flap.hs:22) |
| checked-blintz, checked-helmet, checked-crane | BlintzGallery.hs:39, HelmetGallery.hs:38, CraneGallery.hs:38 (`True`); `flapAt` states | same stationary side; consecutive states are distinct (11, 7 and 4 listed poses) |
| checked-petal, checked-bird-above, checked-bird-below | PetalGallery.hs:45 (`True`), CheckedBirdSpec.hs:173 | StudyCase fixed panel (0.58, 0.4) (CheckedPetal.hs:53); 8 and 23 distinct poses |

Every consecutive pair keeps at least one face's vertices exactly in place,
within 1e-12, and moves at least one vertex. None can be one whole-model motion.
The other goldens with a presented turn are drawn with arrows off: frog-sequence
(BasicBaseSpec.hs:216 `False`; turnover at BasicBaseGallery.hs:121-127) and the
bird-sequence goldens (BirdSequenceSpec.hs:79 `False`).
`examples/bird-base-sequence.fold`, which the CLI can draw with `--arrows`
(Cli.hs:568, off by default), has no such pair either. Each of its 15 pairs moves
3 or 6 of 13 vertices without keeping all pairwise distances (python). The claim
holds, **structurally**. One gap is objection L2-13.

---

## Objections

Each has an id, severity, claim, evidence and proposal. The structured index
repeats them.

### L2-1 (critical) — §5 quarter-fold step 2 has the wrong sense

- **Claim.** "fold mountain edge top to edge bottom", captioned "behind",
  produces edge 9 −180 and edge 11 +180. The fixture's frame 2 has edge 9 +180
  and edge 11 −180: both layers of the top half come **towards** a +z reader.
  Under D5 that is a valley. The same mistake would mis-set #60's acceptance.
- **Evidence.**
  - `quarter2.py`, step 1 held at ±180, step 2 at 170°, root F0: F1 and F2 at
    z = +0.0434.
  - jq frame 2: `edges_foldAngle[8:12] = [-180,180,-180,-180]`.
  - Key-frame assignments: edge 9 V, edge 11 M.
  - gap-step-annotation-channel F10: "one valley fold as seen".
- **Proposal.** `fold valley edge top to edge bottom`, captioned "Fold the top
  half down in front, onto the bottom." Add a fixture fact to §5:
  - step 1 moves `[8,6,3,7]` and `[8,7,0,4]` behind (z < 0);
  - step 2 moves `[8,5,2,6]` and `[8,6,3,7]` in front (z > 0), mapping
    one-for-one to V on edge 9 and M on edge 11 through their way up;
  - `[8,4,1,5]` never moves.

### L2-2 (critical) — §5 quarter-fold anchor lies in the paper step 1 moves

- **Claim.** `anchor (1/4, 1/4)` is inside F3 `[8,7,0,4]`, and step 1 moves F3
  (the left half). D3 invariant 5 refuses a move whose moving set contains the
  anchor face, so the example is refused at its first step. The fixture holds F0
  still.
- **Evidence.**
  - jq: F0's vertices 8, 4, 1, 5 keep their coordinates in frames 0–2.
  - F3's vertices 0, 7 move from (0,0) and (0,0.5) to (1,0) and (1,0.5).
  - Spine D3 invariant 5, spine.md:194-197.
- **Proposal.** `anchor (3/4, 1/4)` (inside F0, which is also Folding's
  default first face, so no re-anchoring is needed).

### L2-3 (major) — `sheet square` cannot match quarter-fold-steps.fold by index

- **Claim.** Under D6, a run from `sheet square` writes these frames:
  - frame 0: the bare square, 4 vertices, 4 edges, 1 face;
  - frame 1: 6 vertices, 7 edges, 2 faces;
  - frame 2: 9 vertices, 12 edges, 4 faces.

  Ids are allocated in a different order: the fixture's vertex 4 is (0.5,0) and
  5 is (1,0.5). The fixture's frames 0 and 1 already carry all 12 edges. So
  "#60's done-when is amended to tolerance on coordinates and angles" (D4
  consequences) compares arrays that do not line up.
- **Evidence.**
  - jq: the fixture's key frame has 12 edges including 9 and 11 at 0 (backfill).
  - #60 done-when (gh issue view 60): "creases and coordinates match".
  - Spine D6, spine.md:278-296.
- **Proposal.** Two separate tests.
  1. **Equivalence.** `sheet "examples/quarter-fold-steps.fold"`: folds along
     existing creases 8+10, then 9+11; ids are identical, compare coordinates
     and angles with a tolerance, assignments by the state rule.
  2. **Authoring.** `sheet square`: compare by material identity. For every
     fixture edge, the written frame's edges covering that material segment
     carry the fixture's angle, and a crease not yet made counts as angle 0.
     Vertex positions are compared by material coordinate.

  Write the comparison rule into the #60 amendment.

### L2-4 (critical) — D2 treats `centre` as a vertex, which blintz-base.fold does not have

- **Claim.** D2 resolves `corner`, `centre` and landmarks "as a vertex …
  within tolerance of exactly one vertex; a near miss is refused".
  - blintz-base.fold has no vertex at (½,½); its nearest vertex is 0.5 away.
    So `fold mountain corner bottom-right to centre`, the EDSL blintz and D16's
    first migration are all refused as `NearMiss`.
  - Conversely, `anchor (0.5,0.5)` on crane.fold (vertex 24) and `centre` on
    quarter-fold-steps.fold (vertex 8) are not strictly inside any face, so as
    regions they are refused.
- **Evidence.**
  - `blintz.py`: `centre (0.5,0.5) is a vertex: False  nearest vertex distance 0.5`.
  - `crane2.py`: (0.5,0.5) nearest vertex 2.14e-14, min edge distance 0.
  - E2 note, lines 432-437: "Needed for 'corner', 'centre' … a valid vertex
    name but an invalid region name".
  - spine.md:139-143.
- **Proposal.** Replace the two bullets with a rule by **use**, not by word:
  - **Position** — an input to O1–O7, `midpoint`, `fraction`, `model`, or a
    `P to Q` argument. Any point on the paper. It is placed through any face
    whose closed polygon contains it within `Faces.tolerance`, all such
    placements must agree (join check), and no vertex is required.
  - **Region** — `anchor`, `flap containing`, `hold`, `layers … above …`.
    Strictly inside exactly one face; or a vertex whose incident faces all lie
    on one side of the hinge in question (see L2-11).
  - **Vertex** — `collapse at`, `rabbit-ear at`, `petal tip`, the ends of
    `crease P-Q`. Within tolerance of exactly one vertex; a near miss is
    refused, naming the nearest vertex and its distance.

### L2-5 (major) — §5 crane anchor (0.5, 0.5) is a vertex, and the wrong face

- **Claim.** CraneWing anchors face 0 (ring `[46,49,54,55]`). The spine's
  comment says "pick a point in face 0", but (0.5,0.5) is vertex 24, on three
  edges, far from face 0, which spans x∈[0.866,1].
- **Evidence.**
  - CraneWing.hs:57-59 (face 0 ring check).
  - `crane.py`: face 0 material corners `(0.866,0.324),(1,0),(1,0.5),(0.9005,0.5)`.
  - `crane2.py`: `(0.95, 1/3) faces [0] min edge distance 0.05000`.
- **Proposal.** `anchor (19/20, 1/3)   # strictly inside face 0, 0.05 from its nearest edge`.

### L2-6 (major) — §5 crane `fold valley 90` is a mountain as seen from +z

- **Claim.** At +90 the moving wing's tip ends at (1, ¼, −¼), away from a +z
  reader. The moving wing, A, is also the lower of the two wings from +z. Under
  D5's own words ("as seen by the reader", camera looking down −z) the step is a
  mountain. It reads "valley" only from below: CraneGallery's camera
  (−1, 1, √2) looks towards +z.
- **Evidence.**
  - CraneWingSpec.hs:99: expectedTip z = −0.25 sin a.
  - gap-layer-selective-folds F14: "Top 2 from +z picks wing B, not wing A".
  - CraneWingSpec.hs:47-53: −90 refused through the other wing.
  - Camera.hs:107 (topDown); CraneGallery.hs:36.
- **Proposal.** `fold mountain 90 model (0, 1/4)-(2, 1/4) flap containing (0.02, 0.97)`,
  captioned "Fold the lower wing down, behind." Replace the "writer to verify"
  comment with the measured fact: tip material (0,1) → (1, ¼, −¼).

### L2-7 (major) — D5 residue makes a step's sense depend on the render camera

- **Claim.** The residue fixes "as seen" as "from the side the page's camera
  looks at, after presentation". The three galleries whose goldens D16 migrates
  or reuses look from **below**:
  - `basisFrom (V3 (-1) 0 1)` (BlintzGallery.hs:38);
  - `(-1, 1, √2)` (CraneGallery.hs:36);
  - `(-1, 0, 1)` when underside (PetalGallery.hs:44; checked-bird-below).

  So the blintz corners would be "valley" if rendered like checked-blintz.svg
  and "mountain" under topDown. One `.fseq` would give two sets of FOLD signs
  depending on `run -o .svg --view`. This contradicts D14: the camera is a
  display parameter, "never sequence data".
- **Evidence.**
  - `blintz.py` probe: corners to z < 0.
  - BlintzGallery.hs:3-4: "view its underside to see the flaps".
  - D13's `--view` flag, spine.md:453-454; D14, spine.md:494-498.
- **Proposal.** Replace the residue with: "`valley`/`mountain` are as seen from
  the +z side of the anchor face after the sequence's own `turn over`/`rotate`
  steps. Render options (`--view`, a study camera) never change a step's
  meaning. A figure drawn from below shows the same step, and the arrow glyph
  flips with the view, not with the source."

### L2-8 (major) — §5 bird press step cannot bind under D9's petal signature

- **Claim.** The petal signature requires the hinge "currently 0" and the
  opening creases "currently folded at ±180". At the press, both hinges are at
  175 and the openings at t − 180 = −5, so `petal tip corner bottom-right to 180`
  finds zero matches and is refused. The same holds for any macro resumed after
  a partial step.
- **Evidence.**
  - gap-exact-landmarks F12 signature bullets.
  - `birdAngles` (CheckedPetal.hs:103-110): openings at `t-180`, hinges at t.
  - `birdHinges PressPetals` (CheckedBird.hs:87): from (175,175).
- **Proposal.** Add a continuation step. Each part carries a concrete example:
  - **AST.** `Continue Name ParamTarget`.
  - **Text.** `continue front to 180`.
  - **Rule.** Reuse the roles, branch and disambiguation pinned in the named
    step's record (E2's "resolve once and pin").
  - **Refusal.** If any role crease's angle was changed by a later step other
    than a `continue` of the same macro, refuse and name the crease.
  - **Example.** Name the back step `back`, then write
    `together { continue front to 180; continue back to 180 }`.

### L2-9 (major) — `sheet FILE` does not say whether the file's angles are the start

- **Claim.** Two of the four example sheets carry finished-state angles:
  blintz-base.fold has −180 on edges 8–11, and bird-base.fold ±180 on 20 edges.
  The recipes zero them (BlintzSequence.hs `edgesFoldAngle = replicate … 0`;
  CheckedPetal/CheckedBird build every pose from their own angle lists). If
  `sheet` kept the file's angles, the blintz example would start as a finished
  blintz and the bird as a finished bird. Only the crane example says
  `start folded`. D12 and §4 (`SheetSource`) say nothing about angles or
  `faceOrders`.
- **Evidence.**
  - jq `.edges_foldAngle` on both files.
  - BlintzSequence.hs:42.
  - CheckedPetal.hs:51 (`foldFrameWith source {edgesFoldAngle = petalAngles 0}`).
  - spine.md:414-418, 424-427, 675.
- **Proposal.** In D12 and §4, add: "`sheet FILE` reads the key frame's crease
  pattern and assignments (intent, D3). It drops `edges_foldAngle`,
  `faceOrders`, `faces_vertices` and `frameExtras`, and starts at angle 0. The
  state in the file is used only by `start folded`, which takes
  `edges_foldAngle` when present and otherwise the assignments' ±180."

### L2-10 (major) — §5 crane stacking needs at least two relations, and exactly-one is untested

- **Claim.** `layers (tail point) above (body point)` is one relation. Tail
  exposure happens on both sides: indices 0–1 on one, 3–4 on the other. One
  "above" relation can exclude at most one side and leaves ≥ 2 survivors, which
  D11 refuses. CraneWingSpec's predicate needs the tail above faces 27 and 65
  **and** below 29 and 66. No test shows that any set of relations leaves
  exactly index 2: the spec checks only that index 2 satisfies them and the
  first order does not (CraneWingSpec.hs:74-81).
- **Evidence.**
  - several-stackings.md:11-12.
  - CraneWingSpec.hs:61-81.
  - `crane2.py` points strictly inside faces 10, 27, 29, 65, 66 (margins above).
  - Not run: `solveStacking` on the creased crane.
- **Proposal.**

  ```text
  start folded
    layers (1/4, 1/5) above (3/8, 5/9)   # tail face 10 above body face 27
    layers (4/9, 3/8) above (1/4, 1/5)   # body face 29 above tail face 10
  ```

  Add to D11's acceptance: "on crane.fold these relations leave exactly one of
  five orders (index 2); removing either leaves ≥ 2", with faces 65 and 66
  ((0.3, 0.39), (0.49, 0.065)) added if the solver shows two are not enough.

### L2-11 (minor) — A sheet corner as a flap seed or unfold target has no resolution rule

- **Claim.** Corners are boundary vertices, never strictly inside a face. After
  the blintz, material corner (1,0) sits at (½,½) with the other three corners
  (BlintzSequenceSpec.hs:106-107). On crane.fold, corner (0,1) is on faces 2, 3,
  6 and 7. So `unfold c1`, or any "flap containing corner …", is refused under
  D2's region rule, or is ambiguous if resolved by current position.
- **Evidence.**
  - blintz-base.fold v1 touches only border edges 1 and 2 (jq), so it lies in
    one face.
  - crane.fold: faces 2, 3, 6 and 7 all contain v2 (`crane.py`).
- **Proposal.**
  - `unfold S` reuses S's recorded material hinge segment and moving seed; it
    never re-resolves by position.
  - A vertex is a valid seed when every face incident to it is on the same side
    of the hinge. Otherwise refuse and list the faces.

### L2-12 (minor) — The §5 EDSL blintz does not print as the §5 text blintz

- **Claim.** "Text and EDSL must be written for the same models", but they
  differ:
  - captions: the EDSL's loop gives three identical captions, "Fold the next
    corner to the centre.", while the text has three different ones;
  - names: the text names step `c1` explicitly, while the builder's `c1 <-`
    returns a generated `Ref`;
  - signature: D1 says `sequenceOf :: Build () -> Sequence` (spine.md:95),
    while §4 and the example use `SequenceHeader -> Build () -> Sequence`
    (spine.md:680, 823).

  A PRD test `prettySequence blintz == parse text` would fail.
- **Evidence.** spine.md:95, 680, 768-777, 823-827.
- **Proposal.**
  - Use one signature, `sequenceOf :: SequenceHeader -> Build () -> Sequence`.
  - Have `step` take an optional name: `c1 <- stepNamed "c1" "…"`.
  - Make the EDSL loop use `zip` over the four text captions.
  - State the acceptance test: pretty-print the EDSL value, then compare it
    with the parsed text, spans stripped.

### L2-13 (minor) — D5's whole-model classification must exclude identical frames

- **Claim.** An identity pair is technically "related by one whole-model rigid
  motion". If the classifier does not exclude it, repeated frames would become
  presentation changes, where today they yield no motion (`movedVertices` is
  empty, Step.hs:137-142). No arrow-bearing golden has a repeated frame (§5 of
  this review), so the acceptance check would not catch this.
- **Evidence.**
  - Step.hs:137-142.
  - The generators and state lists in the table above.
  - bird-base-sequence.fold pairs moving 3 or 6 of 13 vertices (python).
- **Proposal.**
  - **Definition.** A pair is a presentation change when every vertex moved by
    more than `1e-9 × max 1 span`, and one rigid motion with determinant +1 maps
    all of them within that tolerance.
  - **Acceptance.** Name the 12 goldens: quarter-fold-step-1,
    quarter-fold-steps, the 4 FlapSpec goldens, checked-blintz, checked-helmet,
    checked-crane, checked-petal, checked-bird-above, checked-bird-below. Add a
    unit test that a repeated frame yields `[]`, not a presentation change.

### L2-14 (minor) — The §5 crane fact "travel +90 accepted, −90 refused" invites a sign-to-sense reading

- **Claim.**
  - "+90" is the change in the first hinge segment's FOLD angle. The four
    segments sit on faces of opposite orientation (2 and 3 face down, 6 and 7
    face up), so the sign depends on which new edge gets the lowest id, not on
    the physical direction.
  - Writers told "+90" and "valley = positive" wrote `fold valley 90` (L2-6).
- **Evidence.**
  - Flap.hs:10-16, :216.
  - `crane.py` face normals.
  - gap-layer-selective-folds F11.
- **Proposal.** Restate the fact physically: "the accepted turn swings wing A's
  tip, material (0,1), from (1,0,0) to (1,¼,−¼), away from +z. The opposite
  turn is refused at departure through wing B. The recipe spells this as +90 on
  its first `U` edge."

### L2-15 (minor) — `edge S` as a line in a folded state needs a collinearity rule

- **Claim.** The quarter fold's second step works because edge top's current
  segments are collinear, (1,1)–(0.5,1) twice. After blintz move 1, edge bottom
  is bent: material (0.5,0)–(1,0) lies along (0.5,0)–(0.5,0.5). So "O3 of edge
  bottom and …" has no line there. D2 lists `edge S` as a line without saying
  what happens.
- **Evidence.**
  - `quarter.py` frame-1 edge segments.
  - The reflection of (1,0) in x − y = ½ is (½,½) (`blintz.py`, O2 line).
- **Proposal.** Add to D2's lines: "`edge S` is the line through its current
  segments when they are collinear within `Faces.tolerance`. Otherwise refuse,
  naming the segments and their current ends, and suggest `P-Q` with corners."

---

## Confirmations (checked, correct)

- **quarter-fold-steps.fold facts are right.**
  - 9 vertices, 12 edges, 4 faces.
  - Edges 8–11 go 0 → `[-180,0,-180,0]` → `[-180,180,-180,-180]`.
  - Frame 1 extent x∈[0.5,1], y∈[0,1]; frame 2 x∈[0.5,1], y∈[0,0.5].
  - Titles name states.

  Evidence: jq/python dump of all three frames.
- **Quarter-fold lines and moving sides.** O3 at current positions gives
  x = ½ (moving F2, F3), then y = ½ (moving F1, F2, both layers), and step 1 is
  a mountain from +z. Evidence: `quarter.py` (F2, F3 at z = −0.0044, normals
  −z); frame-1 edge segments.
- **Blintz facts are right.** Edges 8–11 are the four chords, all M. The recipe
  uses travel −180 on faces 2, 3, 4, 1, then +180 on edge 8 / face 2. Evidence:
  jq; BlintzSequence.hs recipe; BlintzSequenceSpec.hs corner map
  `[FaceId 2, FaceId 3, FaceId 4, FaceId 1]`.
- **Blintz lines.** "corner X to centre" is O2, which lies exactly on edges
  8/9/10/11 (both ends on the line), so no new crease is made. It moves the face
  containing that corner, and later lines only touch earlier folded triangles
  at vertices. Evidence: `blintz.py`.
- **Blintz sense.** Mountain as seen from +z matches travel −180 with the
  central diamond anchored: corners go to z < 0. Evidence: `blintz.py` probe;
  BlintzGallery.hs:3-4; the spec's orders `FaceOrder i 0 Below`.
- **Bird route.**
  - Stages: collapse, front 0→175, back 0→175 with front held, press both
    175→180 (CheckedBird.hs:84-87).
  - Hinges 26 (v9–v10) and 27 (v11–v12).
  - Tips v1 = (1,0), bottom-right, and v3 = (0,1), top-left.

  Evidence: jq; `bird.py`; two-petals.md:9-10.
- **Bird anchor.** (0.58, 0.4) is strictly inside triangle (v8, v9, v10), on
  the stationary side of hinge 26, 0.0798 from its nearest edge. Evidence:
  `bird.py` barycentric (0.385, 0.341, 0.273); CheckedPetal.hs:53.
- **Bird centre.** It is vertex v8, and there is exactly one collapse match on
  the flat bird. Evidence: jq; gap-exact-landmarks F9, F13.
- **Crane wing facts.** Folded line y = ¼ (CraneWing.hs:98), faces
  `[2,3,6,7]` (:93), +90 accepted and −90 refused with `FlapEndpointOrder 0`
  (:80-84, refusal at :82), stacking index 2 (:78).
- **Crane seed.** (0.02, 0.97) is strictly inside face 7, 0.0070 from edge 24,
  and folds onto the tip side at (1.0071, 0.0354). Evidence: `crane2.py`,
  `crane.py`; gap-layer-selective-folds F12.
- **D5's golden claim holds structurally.** Each of the 12 arrow-bearing
  goldens holds a face fixed between consecutive frames. The turn-over frog
  sequence and the bird-sequence goldens are drawn with arrows off. Evidence:
  the table in §5; SvgSpec.hs:133; FlapSpec.hs:292/312/322; Flap.hs:22;
  CheckedPetal.hs:53; BasicBaseSpec.hs:216; BirdSequenceSpec.hs:79.

## Not checked

- `solveStacking` survivors for the proposed crane relations (needs a build).
- Which of the four new crane `U` edges gets the lowest id after cutting, and so
  the orientation of its stationary face. The physical direction comes from the
  spec, not from that id.
- BlintzSequenceSpec and CraneWingSpec passing on `568dcb6`. I relied on CI
  being green on `main`, as gap-step-annotation-channel reports; I did not run
  `gh run list` myself.
