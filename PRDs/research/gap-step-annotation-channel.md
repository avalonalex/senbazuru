# Gap — the step annotation channel: how captions, arrow kinds, turn-over and growing crease graphs reach the step page

Researched 2026-09-14 against the repository at `568dcb6`
(branch `docs/prds-sequence-language`, clean). Nothing in the repository was
modified, built or tested. Evidence: `sed`/`grep` on the cited lines, `jq` on
fixtures, `gh issue view` for #36, #48, #49, #94 and #95 (no comments on any),
`gh run list` for CI status, and three `python3` calculations on fixture
coordinates. This file extends C (findings 25-27), D (C4-C6), A1 (c) and the
critic's gap 3.3. It does not repeat them.

## Summary

The step page cannot learn intent from frames. It gets `[Frame]`, subtracts
neighbouring frames, and draws one bowed arrow per moving piece of paper. Five
measured facts shape the fix.

- The existing golden already shows backfill's cost. The flat sheet draws the
  second fold's line half valley, half mountain. Figure 2 draws the same
  unfolded line as a solid edge.
- One motion in the fixture changes a valley and a mountain crease together. So
  "arrow kind from the changed assignment" (#36) is ambiguous.
- A turn-over about #95's x = 0 axis doubles the shared extent's width and
  halves every figure's scale.
- A turn about the extent's centre keeps the extent, but the corner centroid is
  not the box centre. Inference would draw a spurious arrow of up to 0.0975
  model units on the bird sequence.
- Vertex ids survive creasing, which makes matching frames by material
  coordinates cheap.

The design recommended here:

- a typed `StepNote` per figure, passed beside the frames;
- arrow heads and a page-unit `Symbol` shape added to `Diagram`;
- captions placed by `Layout`;
- turns applied inside the page, about page axes through each figure's extent
  centre;
- material matching (design B) for graphs that grow.

With no notes, all 33 tracked goldens stay byte-identical.

## Findings

### A. What the page does today

1. **The pipeline.** `stepPage` resolves every frame that has vertices. It
   chooses **one** basis from all of their vertices together (`Render/Steps.hs:106-107`).
   It draws each frame with `creasePatternFrom` in that frame's own notation
   (`:118-122`). On every figure but the last it adds
   `withArrows theme basis (motionsBetween fr next)` (`:123-129`). Then it calls
   `gridOf` (`:110`). Its only intent input is one `Bool` for arrows
   (`:98`).

2. **`motionsBetween`'s contract.**
   - It refuses any pair whose `vertices_coords` length, `edges_vertices` or
     `faces_vertices` differ (`Origami/Step.hs:94-96`, `118-126`). This is pinned
     at `test/Senbazuru/Origami/StepSpec.hs:115`, `123`.
   - A face moved if any of its vertices moved more than `1e-9·modelSpan`
     (`Step.hs:137-142`).
   - Motions are connected groups of moved faces (`:175-192`).
   - `motionFrom`/`motionTo` are the mean of the group's **face corners**
     (`:112-113`, `144-145`), with repeats, not the centre of a box.
   - A frame against itself gives `[]` (`StepSpec.hs:90-92`).

3. **`withArrows` draws one kind of mark.** It appends one `Arrow (arrowFor …)`
   per motion, and nothing when the projected ends are closer than
   `1e-6·max 1 (max w h)` (`Render/CreasePattern.hs:592-605`). Its comment says
   books mark a turn-over with a loop, and that senbazuru has neither a loop nor
   a pair of arrows (`:584-591`). `CreasePatternSpec.hs:400-411` pins that no
   arrow is drawn from above and one is drawn from the side. `arrowFor` is the
   only place an `ArrowPath` is built (`Diagram/Style.hs:364-372`; grep).

4. **Layout works in model units, and the shared extent is absolute.**
   - `gridOf` takes the union of every figure's **absolute** extent
     (`Diagram/Layout.hs:108-112`).
   - The stride is `(1 + gutter) × size of that union` (`:121`).
   - Each figure is centred in its cell (`:132-137`).
   - The number is a `Label` inside the figure's own top-left corner, lowered
     by `0.12·h` (`:146-155`). The header records why: a band above each figure
     was a units bug (`:33-45`).
   - The page box has no trailing gutter (`:157-166`), pinned by
     `LayoutSpec.hs:85`.
   - `fitBox` maps extent to page with **one uniform scale**, the smaller of the
     two ratios (`Geometry.hs:153-194`).

   So any growth of the union shrinks every figure on the page.

5. **Mixed-unit shapes are finished in the backend.**
   - `Label` and `Arrow` are projected first. The type size and head length are
     then applied in page units (`Render/Svg.hs:181-192`, `197-230`).
   - The head is clamped to half the arrow's page length (`Svg.hs:215`).
   - `Offset` changes the transform, not the points (`Svg.hs:176`). It does not
     enter `shapePoints`, so it cannot rescale the page (`Diagram.hs:234-238`).
   - A newcomer reads `Label`'s `V2` as a page position. It is a model point,
     and only its size is in page units (`Diagram.hs:194-201`).

6. **Nothing at the file boundary carries intent.**
   - `creaseAllAlong` clears `facesVertices`, `faceOrders` and `frameExtras`
     (`Fold/Creasing.hs:264-267`).
   - Cutting does too (`Fold/Crossings.hs:73-80`).
   - `withFaceOrders` and `transformSurface` set `frameExtras = mempty`
     (`Origami/Surface.hs:263`, `292`).
   - The GLB keeps three `senbazuru:` keys (`Render/Gltf.hs:237-242`).
   - FOLD itself has no arrow or operation key (Step's header,
     `Step.hs:5-8`).

7. **Who calls the page.**
   - The CLI calls `stepPage` (`app/Senbazuru/Cli.hs:854`). It uses
     `withArrows` and `motionsBetween` for single frames (`:886`, `:922-929`),
     and refuses `--steps` with `--frame`, `--fold` or `--stacking`
     (`:843-851`).
   - Arrows on: CraneGallery `:38`, PetalGallery `:45` (used by both
     `petalSvg` and `birdSvg`, `:39-45`), BlintzGallery `:39`, HelmetGallery
     `:38`, FlapSpec `:292`, `:312`, `:322`, SvgSpec `:133`.
   - Arrows off: BirdSequenceSpec `:79`, BasicBaseSpec `:216`, WingBendingGallery
     `:42`, CraneSpreadGallery `:128`, BasicBaseGallery `:145`, `Main.hs:170`,
     StepsSpec.

   Changing `stepPage`'s arity therefore touches about fifteen call sites.

### B. What the fixture and goldens show

8. **The quarter-fold fixture's frames.** `test/fixtures/quarter-fold-steps.fold`
   is identical to the `examples/` copy (`cmp`).
   - Frame classes: key frame `creasePattern`, then `foldedForm`, `foldedForm`
     (`jq`).
   - Signed face areas, with faces `[8,4,1,5] [8,5,2,6] [8,6,3,7] [8,7,0,4]`
     (python on `jq` output):
     - frame 0: all +0.25;
     - frame 1: `+,+,−,−`, so faces 2 and 3 are face down;
     - frame 2: `+,−,+,−`.
   - Extents: frame 0 is x∈[0,1], y∈[0,1]; frame 1 is x∈[0.5,1], y∈[0,1];
     frame 2 is x∈[0.5,1], y∈[0,0.5].

9. **Backfill is already visible in `test/golden/quarter-fold-steps.svg`.**
   - Figure 1 (the flat sheet, crease-pattern notation) draws the y = 0.5 line
     in two styles:
     - `M 69.375 100 L 128.75 100` with the valley dash `6 3.5` (edge 9, V);
     - `M 69.375 100 L 10 100` with the mountain dash (edge 11, M).

     That is the **second** fold, drawn on step 1 half as a valley and half as
     a mountain.
   - Figure 2 (the rectangle, folded-form notation) draws the same line,
     `M 170.312 100 L 229.688 100`, **solid** at width 1. Edges 9 and 11 are
     still at angle 0 in frame 1 (`jq`).

   So a crease not yet folded looks exactly like a fold already made. A book
   draws that line on figure 2 dashed, as the instruction; Lang's summary
   agrees (finding 20). The `Style` header predicted the problem: a diagram
   marking the next fold on a folded form "will have to face it"
   (`Diagram/Style.hs:54-62`).

10. **One motion can change creases of both signs, so the kind is not in the
    assignment.**
    - Step 2 is one motion over faces 1 and 2 (`StepSpec.hs:76-79`).
    - Between frames 1 and 2, edge 9 (V) goes 0 → +180 and edge 11 (M) goes
      0 → −180 (`jq`). Both are ring edges of that group (`Step.hs:161-165`).
    - Face 1 lies face up and face 2 face down in frame 1 (finding 8). So both
      layers fold toward the reader: one **valley** fold as seen.

    #36 says to take valley or mountain "from the assignment that changed". On
    this pair that yields both. The resolution needs the camera, which `Step`
    does not have (it imports no camera, `Step.hs:49-63`), and which way up each face lies. AGENTS.md
    warns that winding is trusted as written, and that a backwards-wound file
    draws colours swapped (`AGENTS.md:315-323`). Step 1's creases are both M
    (8 and 10, 0 → −180), and the golden draws them with today's single arrow
    style.

11. **`frame_title` names a state, not an instruction.**
    - The fixture's titles are "Step 1: the flat sheet", "Step 2: folded in
      half" and "Step 3: folded in half again" (`jq`, and C finding 26).
    - The bird titles are states too, such as "First petal · lift · hinge 15°"
      (`jq`).
    - An arrow belongs to the figure **before** the fold (`Step.hs:17-21`), and
      a book's caption goes with the arrow.

    #94 would draw each frame's title under that frame's figure. For the
    fixture that repeats the step number already drawn by `Layout`
    (`Layout.hs:146-149`), and it states a result under a picture of the start.
    D (C6) already notes that #94's other premises are stale.

### C. Turning over and the single camera

12. **#95's axis moves the whole page.**
    - #95 defines turning over as `(x, y, z) ↦ (−x, y, −z)`: a half turn about
      the page axis at x = 0.
    - On frame 2 (x∈[0.5,1]) that gives x∈[−1,−0.5] (python).
    - The union extent then grows from [0,1]² to x∈[−1,1] (`Layout.hs:108-112`),
      twice as wide, so `fitBox`'s single scale shrinks every figure.
    - `motionsBetween` would also report a translation from (0.75, 0.25) to
      (−0.75, 0.25). `withArrows` would draw that on figure *i*, from its centre
      to a point outside its cell.

    The study never does this. It translates a material landmark to the origin
    before its half turn: `turnover after upright after` a translation by
    `−origin` (`study/fold-material/BasicBaseGallery.hs:121-127`).

13. **A turn about the extent centre keeps the extent, but inference still draws
    an arrow.**
    - A half turn about the vertical line through the box centre maps frame 2's
      x∈[0.5,1] onto itself (python).
    - `motionFrom` is the corner mean, not the box centre (finding 2). On the 16
      bird frames that mean is 0.0015-0.049 model units off-centre in x (python
      on `examples/bird-base-sequence.fold`).
    - A turn about the box centre therefore moves the mean by 0.0030-0.0975 in
      the top-down projection. That is 3,000-97,500 times `withArrows`' cut-off
      of `1e-6`.
    - The quarter fold is symmetric (mean = centre = (0.75, 0.25)), so its
      golden would never show this.

    An inferred arrow on a turn-over is therefore wrong by construction. It is
    the "confident and untrue" mark `withArrows`' comment warns about
    (`CreasePattern.hs:584-591`).

14. **Why the axis must be stated in page terms.**
    - `Rigid.rotationAbout p axis θ` turns about the line through `p`
      (`Geometry/Rigid.hs:114-117`).
    - `project` takes dot products with `basisRight` and `basisUp`
      (`Render/Camera.hs:238-239`).
    - `turnedBy` keeps those axes perpendicular and unit length
      (`Camera.hs:220-235`).

    **[analysis]** Let `r`, `u`, `f` be a point's dot products with
    `basisRight`, `basisUp` and `basisForward`. A half turn about an axis along
    `basisUp`, through a point with right-coordinate `c_r` and
    forward-coordinate `c_f`, maps `r ↦ 2c_r − r` and `f ↦ 2c_f − f`, and leaves
    `u` alone. Choose `c_r` as the projected extent's centre and `c_f` as the
    middle of the depth range. The figure's projected box and depth range are
    then unchanged. This holds under any basis, isometric included.

15. **The basis must be fixed before any turn.**
    - The page basis comes from all frames' vertices (`Steps.hs:107`;
      `basisFor`, `CreasePattern.hs:509-510`).
    - With no view named, that is `isometric` if `hasRelief`, else `topDown`
      (`CreasePattern.hs:521-524`).
    - `hasRelief` compares the z span with the larger of the x and y spans
      (`Geometry/V3.hs:88-95`).

    A turn defined in page axes needs the basis first, and the basis depends
    on the vertices. For flat models the order does not matter: under `topDown`
    the page-vertical axis is model y, in the sheet's plane, so flatness
    survives. For a 3D model under the default isometric view, the turn axis
    leaves the xy-plane and could in principle change `hasRelief`. The
    unambiguous rule is to pick the basis from the **unturned** frames (or the
    named view), then turn.

16. **Floating point.**
    - `sin π` in IEEE doubles is `1.2246467991473532e-16`, and `cos π` is
      exactly `−1.0` (python).
    - Mirrored bounds do not always round-trip: `(0.1+0.7)−0.7` gives
      `0.09999999999999998` (python).
    - A negated zero coordinate becomes `−0.0`. `formatNumber` normalises that
      (SvgSpec `:166-170`), but a `.glb` goes through its own rounding
      (AGENTS.md gotchas).

    So "extent unchanged" is exact only up to rounding, and a test must use a
    tolerance.

### D. When the crease graph grows

17. **Which ids survive a new crease.**
    - Vertex ids are kept, and crossings are appended
      (`Crossings.hs:73-75`).
    - `creaseAllAlong` appends vertices and edges and clears faces
      (`Creasing.hs:251-267`).
    - Face transforms are keyed by the **cut** pattern's faces
      (`Origami/Folding.hs:286-322`).
    - The spanning walk holds the first face still (`Folding.hs:577-585`).
    - A1 (c) adds that edge ids shift when an edge is cut, and that faces are
      re-traced in half-edge order.

    `Step` already compares edges by vertex-pair keys, not by `EdgeId`
    (`Step.hs:150-173`). So the vertex id, the one id that survives, is the one
    `Step` needs.

18. **Where material coordinates already reach the page.**
    - `surfaceFromFrame` reads `senbazuru:material_coords`. Without it, it takes
      a flat `creasePattern` frame's own x/y as material coordinates
      (`Surface.hs:179-195`).
    - `materialFrame` writes the key (`Surface.hs:248-252`).
    - `FlapSpec` passes `map materialFrame states` to `stepPage` with arrows on,
      for four goldens (`FlapSpec.hs:292`, `312`, `322`).
    - `bird-base-sequence.fold` frames carry no such key, and all 16 share one
      `edges_vertices` and one `faces_vertices` (`jq`, `unique | length` = 1).

19. **Where a new crease's ends can lie.** Each end of a new crease must meet an
    existing edge or corner (`Creasing.hs:38-42`). A crossing between two
    creases in the **same** batch can lie inside an old face, not on an old
    edge.

### E. Prior art for the marks (ideas only)

20. **Lang's conventions**, fetched from a secondary summary at
    <https://zenorig.blogspot.com/2012/09/origami-diagramming-conventions-robert.html>
    (licence not stated; paraphrased):
    - Turn-over is a valley arrow with a loop in its stem. It lies
      horizontally for a side-to-side flip and vertically for a top-to-bottom
      one.
    - Mountain arrows have a hollow, one-sided head.
    - Unfolding uses a double-sided hollow head.
    - Push arrows have a hollow, cleft tail.
    - Rotation is a fraction inside a circle with arrows.
    - A repeat is a leader to a box holding a step range and a count.
    - The crease to be folded is drawn dashed before the fold.
    - Text should stay minimal.

    Wikipedia's Yoshizawa–Randlett article
    (<https://en.wikipedia.org/wiki/Yoshizawa%E2%80%93Randlett_system>,
    CC BY-SA 4.0) agrees on solid valley heads versus open mountain heads.

    This confirms E1 finding 15 independently. The loop's **orientation**
    encodes the axis, so the axis has to be known in page terms when the mark is
    drawn.

## Implications for the design

### (a) The fields of a per-step note

A note belongs to figure *i* and describes the move from *i* to *i+1*, like the
arrows (`Step.hs:17-21`). The last figure may carry a caption only.

| Field | Can `Step` infer it from two frames? | Source |
| --- | --- | --- |
| Caption | No. `frame_title` names the state, not the move (finding 11). | Sequence |
| Arrow kind: valley or mountain as seen | Only with the camera, which way up the face lies and trusted winding. Ambiguous per crease (finding 10). | Sequence; inference usable only as a check |
| Fold-and-unfold | No: identical frames give `[]` (finding 2) | Sequence, with the arrow's two ends |
| Push, sink, open | No rigid signature | Sequence |
| Turn-over and its page axis | No. With an axis through the centre, inference either sees nothing or draws a spurious arrow (findings 12-13). | Sequence gives the axis; the page gives where it passes |
| Rotation on the page | As for turn-over | Sequence |
| Repeat range | No | Sequence |
| Layer selection (top *n* versus all) | The moved faces, yes (`motionFaces`). "Top only" is checkable only when frames carry `faceOrders`, and the quarter fold's do not (`jq`). | Sequence; checked when orders exist; consumed by #48/#49 |
| Arrow anchor (the flap's edge, not its centre) | Centre only (`Step.hs:67-70`) | Sequence, optional |
| The next fold's crease line | Under backfill, from `motionCreases`; under design B, from the new edges | Inferred |

### (b) Marks extend `Diagram`; captions are placed by `Layout`

- **Arrow kinds extend `ArrowPath`, not `Shape`.**
  - Add a head shape and a body style, which is #36's split.
  - `arrowFor` is the only construction site (finding 3). It keeps today's
    solid head and plain body as the default, and `Svg` must emit exactly
    today's bytes for that pair.
  - `Diagram` stays ignorant of FOLD. It receives a head shape, never an
    `Assignment` (#36).
- **Turn-over, rotate and repeat symbols need one new `Shape`.** Call it
  `Symbol`: its whole geometry is in page units, anchored at one model point.
  - This makes a fourth mixed-unit shape. Its size cannot be in model units:
    a loop sized to the model would change printed size with the number of
    columns, as a band measured in model units did (`Layout.hs:38-45`).
  - `shapePoints` returns only the anchor, as for `Label`. That keeps it
    inside the figure's extent, so the page does not rescale.
  - `-Wincomplete-patterns` will flag `shapePoints`, `mapShapePoints` and
    `shapeToSvg`. It will **not** flag the `\case … _ ->` matchers in
    `LayoutSpec.hs:32-35`, `42-44` or `CreasePatternSpec.hs:394`, which will
    silently ignore the new constructor.
- **Marks are added per figure, by `Render.Steps`.** That module holds the
  basis and the figure's extent, as `withArrows` does. A `withNotes` must
  project with the same `basisFor`, for the reason `CreasePattern.hs:503-508`
  gives.
- **Captions go in `Layout`, as `Label`s; no new shape.**
  - Only `Layout` knows cells, and the number convention is already there.
  - **Do not** reserve a page-unit band below each figure, as #94 proposes.
    `Layout` has no page units, and `Layout.hs:38-45` records that exact bug.
  - Instead, put the baseline at the model-space bottom of the figure's cell
    plus one gutter, raised by a page-unit `Offset` equal to the descent.
    Glyphs grow upward into the gutter. When figures are small the caption
    may overlap its **own** figure, but never the next row. This is the same
    trade the numbers make (`Layout.hs:42-45`).
  - The last row needs a trailing gutter inside the page box. Add it **only
    when some figure has a caption**, so `LayoutSpec.hs:85` and every existing
    page are unchanged.
- **Horizontal overflow is unsolved** (see Open questions). A long caption
  spilling into the next column collides with a different figure, which the
  Layout header calls wrong, not untidy.

### (c) Two designs for a crease graph that grows

**Design A: backfill.** Every frame carries the final graph, and creases not
yet made sit at angle 0.

- Effect on `motionsBetween`: none.
- Effect on goldens: none. The quarter-fold fixture is already backfilled.
- Costs:
  - The defects in finding 9. A flat sheet shows every later fold, with mixed
    styles along one line. A folded figure shows a crease not yet folded as a
    finished edge. On a crane that would put all of its creases on step 1.
  - A precrease step has no signature (finding 2), so its arrow must come from
    the note.
  - The interpreter needs two passes. Pass 1 learns every crease with the
    graph growing. Pass 2 re-folds the final pattern, and must re-anchor each
    pose by a material point: re-tracing can change which face comes first
    (finding 17), which moves the whole model rigidly.
  - The critic's contradiction 3 applies too: angle-0 creases need an
    assignment convention.
- A mitigation, "A + birth": the note carries the step at which each `EdgeId`
  was born. `EdgeId`s are stable under A, because there is only one graph. The
  figure then suppresses unborn creases. Faces split by an unborn crease still
  fill without a seam, because a `Fill` is the union of its rings
  (`Diagram.hs:160-185`). Whether `Visible` would still draw a hidden unborn
  edge is unverified.

**Design B: match frames by material identity.** Add `motionsAcross` beside
`motionsBetween`.

- The vertex ids of `before` must be a prefix of `after`'s, with equal material
  coordinates (checked, or refused).
- Each vertex that `after` adds is placed on `before`:
  - on a `before` edge: interpolate between that edge's two ends, using the
    material parameter;
  - inside a `before` face (the batch crossing in finding 19): use the affine
    map from material to position given by three non-collinear corners. For a
    rigid face this map is exact.
- Groups are formed over `after`'s faces, the finer ones. `motionFrom` uses
  `before` positions and `motionTo` uses `after` positions.
- The companion `creasesToCome` returns `after`'s new creases at `before`
  positions. That is the dashed line a book draws on figure *i*, styled by the
  note's arrow kind, not by the sheet's assignment (finding 10).
- Effect on `motionsBetween`: none. Keep it verbatim, and call `motionsAcross`
  only when graphs differ.
  - For identical graphs, `motionsAcross` visits the same rings in the same
    order, so the sums, and with them the bytes, match. A test must pin that
    and not trust it: run both on every consecutive pair of the quarter
    fixture and of FlapSpec's four material-frame sequences.
  - Byte identity of the 12 arrow-bearing goldens is then structural. They all
    pass `motionsBetween` today (CI green on `main`, `gh run list`), so their
    graphs are equal.
- Preconditions and refusals:
  - Frames with differing graphs and no `senbazuru:material_coords` and no
    flat crease-pattern class are refused, as today. That covers every
    existing `.fold` in `examples/`.
  - The interpreter writes the key with `materialFrame`. The page reads it
    through `surfaceFromFrame`, the one existing reader (finding 18).
- `motionFaces` becomes `after`'s ids. #48 and #49 want regions on the
  **before** figure, so they need the `before`-positioned polygons, not face
  ids.
- New refusals need new `FoldError` constructors, each with an `Explain`
  instance (AGENTS.md conventions).
- On study-bent panels the three-corner affine map is approximate. That is
  acceptable for arrow ends and not for geometry.

**Recommendation: B.** It is the only design in which figure *i* shows the
paper as it is. It costs nothing for existing files. It uses the id that
survives creasing (finding 17) and a coordinate the study already names things
by (E2).

### (d) Where a turn-over axis passes, and how its loop is drawn

- **Where turns are applied.** Apply presentation **inside** the page, in the
  page basis:
  1. Choose the basis once from the unturned frames, or from the named view
     (finding 15).
  2. Keep one running `Rigid` `P`, starting at `identity`.
  3. For a note `TurnOver axis` on figure *i*, take frame *i+1* turned by the
     running `P`, and measure its projected box `[r0,r1]×[u0,u1]` and its depth
     range `[f0,f1]`.
  4. Set `p = c_r·basisRight + c_u·basisUp + c_f·basisForward`, where each `c`
     is the middle of its range.
  5. Update `P` to `halfTurn p axisVector after P`. The axis vector is
     `basisUp` for `PageVertical` and `basisRight` for `PageHorizontal`.
- **The camera does not jump.** Figure *i+1*'s extent is unchanged
  (finding 14), so the union and the scale are unchanged. A sequence whose only
  notes are turn-overs keeps the page geometry of the same sequence without
  them. That is a property to test with a tolerance (finding 16).
- **Build the half turn exactly.** Use the ±1 matrix entries, not
  `rotationAbout … pi` with `sin π ≠ 0`.
- **Rotation.** Rotating on the page uses `basisForward` through the same
  point. A quarter turn of a non-square figure legitimately changes the union.
- **Arrows across a turn.** Diff frame *i* and frame *i+1* under the **same**
  `P`, the one before the turn. A pure turn-over step then gives `[]`, so
  there is no spurious arrow (finding 13). A fold combined with a turn draws
  its fold arrow and the loop.
- **Share the writer.** Export one function, `presentFrames :: Basis -> …`, so
  the sequence writer stores turned frames through the same rule.
  `render file.fold --steps` on the written file then draws the turn, without
  the loop. A1's "presentation outside `Folded`, applied at export" is kept.
- **The loop symbol.** Draw `Symbol stroke size anchor (TurnOverLoop axis)`:
  - The anchor is the midpoint of the figure's own extent edge that the axis
    crosses: the bottom edge for `PageVertical`, the right edge for
    `PageHorizontal`.
  - The backend draws a valley-headed arrow with one loop in its stem, lying
    across the axis. It is horizontal for a vertical axis (Lang, finding 20).
  - It extends **into** the figure, so it can overlap its own drawing but never
    a neighbour's.
  - The size is a theme field in page units. It needs no clamping, unlike
    `Svg.hs:215`, because its length is not derived from model geometry.

### (e) Golden plan

**Must stay byte-identical (all 33 tracked files, `git ls-files test/golden`).**

- **Step pages with arrows (12).** These exercise `motionsBetween` and
  `withArrows`:
  - `quarter-fold-steps.svg`, `quarter-fold-step-1.svg`;
  - `checked-flap.svg`, `checked-flat-flap.svg`, `checked-stack-flap.svg`,
    `checked-aligned-stack.svg` (material frames);
  - `checked-blintz.svg`, `checked-helmet.svg`, `checked-crane.svg`,
    `checked-petal.svg`, `checked-bird-above.svg`, `checked-bird-below.svg`.
- **Step pages without arrows (4).** These exercise the one camera and scale:
  `bird-sequence-iso.svg`, `bird-sequence-bottom.svg`, `frog-sequence.svg`,
  `bent-strip.svg`.
- **Single figures (14).** Any `Shape` or `ArrowPath` change reaches these
  through `Svg`: `unit-square.svg`, `diagonal-cp.svg`, `bird-base.svg`,
  `bird-base-folded.svg`, `quarter-fold.svg`, `quarter-fold-folded.svg`,
  `letter-fold-folded.svg`, `crane-folded.svg`, `kabuto-underside.svg`,
  `quarter-fold-offset.svg`, `letter-fold-offset.svg`, `simple-iso-offset.svg`,
  `simple-iso.svg`, `squaretwist-iso.svg`.
- **GLB (3).** Presentation must not reach `renderGlb` unless asked:
  `crane-folded.glb`, `quarter-fold-folded.glb`, `simple.glb`.

**New goldens**, each with the change that would turn it red:

1. `quarter-fold-steps-noted.svg`. Same fixture, with notes: an instruction
   caption on figures 1-2, `MountainArrow` on figure 1 and `ValleyArrow` on
   figure 2.
   - Red if the mountain head reverts to solid.
   - Red if captions are placed in a model-unit band.
   - Red if the trailing gutter is missing and the last row's captions fall
     into the margin.
2. `quarter-fold-turn-over-steps.svg`. The fixture plus a final `TurnOver
   PageVertical`, repeating frame 2.
   - Red if the axis passes through x = 0: the page is rescaled, every
     coordinate changes and the figures narrow.
   - Red if an inferred arrow is drawn beside the loop.
   - Red if the loop's size follows the model.
3. `quarter-fold-growing-steps.svg`, design B. A new fixture,
   `test/fixtures/quarter-fold-growing.fold`: a plain square, then one fold,
   then two, each frame with `senbazuru:material_coords`.
   - Red if figure 1 draws the second crease.
   - Red if `motionsAcross` refuses.
   - Red if figure 2's next crease is drawn solid.
4. `diagonal-precrease-steps.svg`. A fold-and-unfold on the diagonal, whose
   frames are identical.
   - Red if no double-headed hollow arrow is drawn, which is today's behaviour.

**New non-golden tests:**

- `stepPageWith … (map (\f -> (f, noNote)) fs) == stepPage … fs` on the quarter
  fixture and StepsSpec's sheets. Red if any default in `noNote` leaks into the
  drawing.
- For identical graphs, `motionsAcross == motionsBetween` on every consecutive
  pair above.
- The page extent is equal with and without turn-over notes, within
  `1e-12·span`, on the quarter fold **and** on a bird frame (the asymmetric
  case, finding 13).
- Each head shape's page bytes are equal at model sizes 1 and 400, and so are
  the loop symbol's. This extends `SvgSpec.hs:251-256`.
- A caption's anchor is never below its own cell for 1-60 figures, in
  LayoutSpec.

### Type sketch (no implementation)

```haskell
-- Senbazuru.Diagram — still FOLD-ignorant
data ArrowHead = SolidHead | HollowHalfHead | HollowDoubleHead   -- valley (today), mountain, unfold
data ArrowBody = PlainBody | CleftTail                            -- today, push
-- ArrowPath gains: arrowHeadShape :: !ArrowHead, arrowBody :: !ArrowBody
data PageAxis = PageVertical | PageHorizontal                     -- as the reader sees the page
data Glyph = TurnOverLoop !PageAxis | RotateBy !Int !Int | RepeatRange !Int !Int !Int
data Shape = … | Symbol !Stroke !Double !V2 !Glyph                -- page-unit size, model-unit anchor

-- Senbazuru.Origami.Step — camera-free
motionsBetween :: Frame -> Frame -> Either FoldError [Motion]     -- unchanged
motionsAcross  :: Frame -> Frame -> Either FoldError [Motion]     -- design B
creasesToCome  :: Frame -> Frame -> Either FoldError [(EdgeId, V3, V3)]

-- Senbazuru.Render.Steps — knows FOLD and the camera
data ArrowKind = ValleyArrow | MountainArrow | UnfoldArrow | PushArrow  -- viewer-relative
data Arrows = InferArrows | InferArrowsAs !ArrowKind | GivenArrows ![(ArrowKind, V3, V3)] | NoArrows
data Presentation = TurnOver !PageAxis | RotateOnPage !Int !Int   -- exact fraction of a turn
data Layers = AllLayers | TopLayers !Int
data StepNote = StepNote
  { noteCaption :: !(Maybe Text),
    noteArrows  :: !Arrows,
    noteThen    :: !(Maybe Presentation),   -- applied to every later figure
    noteRepeat  :: !(Maybe (Int, Int, Int)),
    noteLayers  :: !Layers }
noNote :: StepNote                          -- Nothing, InferArrows, Nothing, Nothing, AllLayers
stepPageWith  :: Theme -> Budget -> Grid -> View -> Bool -> [(Frame, StepNote)] -> Either StepError (Maybe Diagram)
stepPage      :: Theme -> Budget -> Grid -> View -> Bool -> [Frame] -> Either StepError (Maybe Diagram)
                 -- = stepPageWith … . map (\f -> (f, noNote)); one implementation, as AGENTS.md:217-221 requires of --layer-budget
presentFrames :: Basis -> [(Frame, Maybe Presentation)] -> [Frame]

-- Senbazuru.Diagram.Layout
gridOfCaptioned :: Grid -> [(Diagram, Maybe Text)] -> Maybe Diagram   -- gridOf = gridOfCaptioned . map (\d -> (d, Nothing))
```

`StepError` wraps only `FoldError` today (`Steps.hs:58-62`), and the CLI takes
it apart (`Cli.hs:855-862`). A note refused for its own reasons, such as a
`noteThen` on the last figure or `TopLayers` contradicted by `faceOrders`,
needs a sum type there. That breaks the CLI's pattern match, so the PRD should
list it as a deliberate change.

## Open questions

1. **Overflowing captions.** The backend has no font metrics: it emits a
   generic `sans-serif` and records markup, not glyphs (`Svg.hs:177-180`).
   Should an overflow be squashed to the cell width with SVG `textLength`,
   truncated by an estimated width, or refused?
2. **Which way turns are passed.** Should presentation be applied inside
   `stepPageWith`, or should the interpreter hand over already-turned frames
   plus a note that only draws the loop? The first keeps one axis rule; the
   second keeps `stepPage` closer to today.
3. **Whose view "as seen" means.** Is `ArrowKind` as seen through the page
   basis, or as seen from +z after presentation? These differ for bottom and
   isometric views.
4. **Checking arrow kinds.** Should the page check a stated kind against the
   inferred one (finding 10) and refuse on disagreement, or trust the sequence?
5. **Layers consumers.** Does `Layers` belong in v1 at all, given that its
   only consumers (#48, #49) are open?
6. **Repeat marks.** Should a repeat be a `Symbol` on figure *i*, or a leader
   to other figures? A leader crosses cells, which `Layout` avoids.
7. **The quarter fold's own golden.** Should the quarter-fold fixture be
   rewritten as a growing sequence once design B lands, deliberately moving
   `quarter-fold-steps.svg`? Or should it stay as the backfill regression?
8. **#95 and the arrow design.** Should #95's done-when be amended to name the
   centre-of-extent axis, given finding 12?

## Unverified

- That `Visible` or the folded-form painter would suppress or keep an unborn
  backfilled edge between coplanar faces in design "A + birth". I read no
  visibility code for this.
- That `motionsAcross` over identical graphs reproduces `motionsBetween`'s sums
  in the same order. This is argued from `Step.hs:108-116` and not run.
- That Blintz, Helmet, Crane, Petal and Bird gallery frames carry
  `senbazuru:material_coords`. Their modules mention `materialFrame` (grep),
  but I did not trace their frames.
- That `bent-strip.svg`'s page goes through `WingBendingGallery:42`'s
  `stepPage … False`. This is inferred from the import and the call, not
  traced.
- GHC's value of `sin pi`. Only Python's was computed; both normally use the
  platform's libm.
- The zenorig page's authorship and licence. The summary tool described it as
  a republication of Lang's newsletter articles; I did not confirm that
  independently.
- Whether a 3D model's `hasRelief` can change under a turn about isometric
  "up" in any real fixture (finding 15). That was analysis only.
