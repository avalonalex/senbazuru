# D. Decisions and constraints already on record for a sequence DSL, a scheme file and material rendering

Slice D of the PRD research. Repository at `568dcb6` on branch
`docs/prds-sequence-language`, clean tree. Issues were read on 2026-09-14 with
`gh issue view N --json body,comments`. Nothing was built or run. Every
measurement below is `jq`/`grep` against files, or is quoted from an issue and
marked as such. Remarks tagged **[analysis]** are my reasoning, not something
the repository says.

## Summary

Most recorded decisions reinforce the request: a move is
`Frame -> Either e Frame`, errors are values with `Explain`, arrows come from
diffing frames, the flat pattern with its angles stays authoritative, and
"realistic" means a checked material surface.

Five strain or overturn it:

1. #60's "one interpreter, so no free monad"; the request names four consumers.
2. "A new input format becomes a Frame and stops there"; a scheme yields many
   frames and would lose its move kinds.
3. Raw face and edge ids, which cutting renumbers; a scheme needs material
   landmarks.
4. `--steps` refusing `--stacking`; a sequence needs layer choices by relation.
5. The study calling its recipes "not an instruction language".

Premise checks: `quarter-fold-steps.fold` needs no crease-adding (verified), a
`Flap` test already folds it, and it uses M/V at angle 0, which PR #72 called
invalid. #94's "nothing reads `frame_title`" is stale; #36 and #95 disagree on
turn-over; #114 is superseded.

The glossary lacks reference, landmark, scheme, move, sink, reverse fold,
precrease, hinge and route, and defines rest angle twice.

## Findings

### A. Constraints and decisions, each with a verdict — question (a)

Each entry gives the rule, where it is recorded, and whether the request
**reinforces**, **strains** or **overturns** it, and why.

**A1. Not a sequence solver.**
- *Source:* `docs/notes/no-sequence-solver.md`:
  - lines 7-10: the binding reason is that a step is a named macro-move with no
    agreed formalisation;
  - lines 12-14: collapsed designs have no sequence at all;
  - lines 22-27: NP-hardness is the weakest of the three reasons;
  - lines 40-46: a multi-frame file *is* the sequence, and arrows are inferred
    by subtraction.
- *Also:* `README.md:155-157`; #60 body ("This is not a sequence solver").
- *Verdict: reinforces, with one strain.* A vocabulary a person writes is the
  "tractable half" #60 names. The strain is that once senbazuru defines a formal
  move vocabulary, the note's binding reason (nothing formal to search) is no
  longer true of senbazuru's own moves. #96 already calls the note dated.
- *For the PRDs:* state that search over the vocabulary stays out of scope,
  and why, rather than leave the note contradicting the DSL.

**A2. "A plain ADT and an interpreter. Not a free monad."**
- *Source:* #60 body, Approach. It says a second interpreter is what would earn
  a free monad. The sketch there is `data Move`,
  `apply :: Move -> Frame -> Either MoveError Frame`, a scheme is `[Move]`, and
  `scanl` over it gives `[Frame]`.
- *Verdict: overturns the premise, not necessarily the conclusion.* The request
  names at least four consumers of one scheme:
  1. rigid frame generation in the library;
  2. the CLI parser and printer;
  3. diagram annotation (captions, arrow kinds);
  4. the material study.
- **[analysis]** A first-order `[Move]` supports any number of interpreters as
  ordinary functions. What would force monadic structure is a move whose
  arguments depend on the *result* of an earlier move — a flap made in step 3,
  or a point located by a fold in step 2. That is A14's naming problem.
- **[analysis]** Request (2), a file language "similarly specified", pushes the
  other way. A file holds only first-order data, so an EDSL that lets users bind
  Haskell functions between moves cannot be written to a file or read back.

**A3. Arrows are inferred by diffing frames, never stored.**
- *Source:*
  - `src/Senbazuru/Origami/Step.hs:10-15` (subtraction, not search) and
    `:30-34` (it compares positions, not angles, because a turn-over moves paper
    without changing an angle);
  - `docs/fold-reference.md`, section "What FOLD does not contain" (no arrows,
    operations or captions);
  - `docs/related-projects.md:24` (origami-diagrams stores arrows; senbazuru
    infers them);
  - `docs/glossary.md:39`.
- *Verdict: strains.* A scheme knows what each step is, which is the information
  #36 plans to reconstruct by classifying motions. Today's inference cannot see
  some moves:
  - `test/Senbazuru/Render/CreasePatternSpec.hs:401-410` pins that a motion
    whose two ends project to one point draws no arrow;
  - `src/Senbazuru/Render/CreasePattern.hs:599-601` implements that;
  - `Motion` in `Step.hs` has faces, creases, `from` and `to`, and no kind.
- *For the PRDs:* either inference stays authoritative and the move only labels
  or cross-checks it, or the move kind is carried forward. Whichever is chosen,
  a FOLD file exported from a scheme must still render without the scheme:
  `--steps` "draws the frames a file already has" (`app/Senbazuru/Cli.hs:844`).
  If kinds travel with the file, they go under a vendor key and meet A6.

**A4. Captions come from the standard `frame_title`.**
- *Source:* #94 body; `related-projects.md:24`.
- *Verdict: reinforces.* A step's text maps onto a standard key, with no vendor
  key needed. Its premises are checked in C6.

**A5. A move drops what it invalidates, and creases are drawn in batches.**
- *Source:*
  - `AGENTS.md:206-213`;
  - `src/Senbazuru/Fold/Creasing.hs:18-35`: a new crease is cut, the faces are
    re-traced, and extras are dropped;
  - `Creasing.hs:90-101`: re-validating after each crease is cubic (#77);
  - `Creasing.hs:116-121`: a batch's refusals are decided against the frame as
    it was, so the order of the batch does not matter.
- *Verdict: reinforces.* Every move hands its result back to `withPlanarFaces`.
- *Strain:* a macro-move, or a step with several creases, must be one
  `creaseAllAlong` call. A step that only changes angles (every step of
  quarter-fold-steps) must not re-cut anything.

**A6. Preserve at the boundary, discard at the transform; absent is not empty.**
- *Source:* `AGENTS.md:184-192`; `docs/notes/round-trips.md:62-87`;
  `fold-reference.md` ("Nothing is dropped", "A field that was absent stays
  absent"); #73 body; #91 comment, point 3.
- *Verdict: strains.* Running a scheme is a chain of transforms, so every frame
  after the starting sheet loses `frameExtras`.
  - For the key frame, those extras are the *file's* keys. #73 shows `crease`
    dropping `cpedit:page`.
  - Demoting a key frame into `file_frames` moves file keys inside a frame
    (#91, point 3).
  - Recording the scheme inside FOLD under a vendor key (#97's second shape)
    would be dropped by the first transform, unless #73's split between file and
    frame keys is made first.
  - A scheme file is itself a new boundary, with comments and layout of its own.
    `round-trips.md:55-60` is the argument for a lossless syntax tree if the CLI
    will ever rewrite a scheme.

**A7. Errors are values, and every error type has an `Explain` instance that
names the offending element.**
- *Source:*
  - `AGENTS.md:160-172`;
  - `src/Senbazuru/Explain.hs:63-75`: a message is a lower-case fragment with no
    full stop, and names the element;
  - `src/Senbazuru/Render/Steps.hs:58-77`: `StepError` leads with the frame
    index, because the reader is holding a file, not a frame;
  - there are 16 `instance Explain` declarations in `src/`.
- *Verdict: reinforces and extends.* Scheme errors need a source position (step
  or line) the way `StepError` needs a frame index. They also need to wrap the
  existing `FoldError`, `FlapError`, `SweepError` and `ThroughError`. #60's
  third done-when (refuse by name, never apply halfway) is reachable with these
  types.

**A8. Keep the default output unchanged.**
- *Source:* not a written repository rule. It is the owner's memory note
  (`keep-the-default-output-unchanged.md`) and a recurring acceptance pattern in
  issues:
  - #6: a single-frame file renders as before;
  - #16: `--frame N` is byte-for-byte unchanged;
  - #56: a single-frame export is byte-identical;
  - #49: the drawing outside the cut-away circle is byte-for-byte unchanged;
  - #94: an untitled frame is byte-identical;
  - #110 and #111: no golden moves.

  Related: `AGENTS.md:266`, never accept a golden diff you have not read.
- *Verdict: strains, mostly PRD 3.* Realistic output must be a second view — a
  new verb, flag or glTF scene — and not a change to the defaults of `render` or
  `export`. `docs/roadmap.md:222-227` already notes that #104's silhouettes
  change every folded-form golden.

**A9. A new input format becomes a `Frame` and stops there.**
- *Source:* `AGENTS.md:193-197`; `docs/architecture.md:155-158` (only
  `Fold.Load` does I/O, and `Import.*` takes `Text`) and `:170-175`.
- *Verdict: needs an explicit revisit.* A scheme is not a crease-pattern format.
  It is a program over a starting sheet that yields a `FoldFile` of many frames.
- Read strictly, nothing downstream may know that a frame came from a scheme.
  Move kinds, step text and layer intentions must then survive in FOLD keys
  (A3, A4, A6).
- Two consequences follow either way:
  - the parser should be a pure `Text -> Either e AST`;
  - a scheme that names its starting sheet (a `.cp` or a `.fold`) needs that
    path opened by `Fold.Load`, never inside the parser.
- The glTF backend (A21) shows the rule can gain a stated exception, but only by
  editing `AGENTS.md` and `architecture.md`.

**A10. Do the geometry in Haskell, not in SVG attributes; keep numbers
reproducible.**
- *Source:* `AGENTS.md:223-226`; `src/Senbazuru/Render/Svg.hs:16-24`;
  `AGENTS.md:271-273` (`formatNumber`).
- *Verdict: reinforces.* A wireframe of curved paper is many projected segments
  computed in Haskell, with no `transform` attribute anywhere.

**A11. Two unit systems, never mixed.**
- *Source:* `AGENTS.md:173-178`; `src/Senbazuru/Diagram.hs:21-47`; #63 body and
  comment. The comment records a tolerance that silently changed from an area to
  a distance, and got past 554 tests and a review.
- *Verdict: strains.*
  - PRD 3 adds physical quantities that do move geometry — thickness, bend
    radius, stiffness — in model units. These must stay apart from display
    adjustments. `docs/notes/paper-thickness.md:3-7` records the earlier mistake:
    a display spacing that was named `--thickness`.
  - The DSL adds a third question: is an amount in a scheme a fraction of the
    sheet, model units, or degrees? Model units differ by a factor of 400
    between a `.cp` square and a unit-square `.fold` (`glossary.md:46`).
  - **[analysis]** A typed EDSL is the cheapest place to apply #63's phantom
    units.

**A12. `--layer-budget` reaches every entry point.**
- *Source:* `AGENTS.md:217-222`; `app/Senbazuru/Cli.hs:385-400`; `stepPage`
  takes a `Budget` (`Steps.hs`).
- *Verdict: reinforces.* The interpreter and any `run` verb take a `Budget`.
- *Related strain:* `--steps` refuses `--stacking`, because one list of stacking
  indices means nothing across a page of frames (`Cli.hs:845-851`;
  `docs/usage.md:125-127`). A sequence does need per-step layer choices:
  - the crane-wing recipe needs the order with the tail tucked between the body
    layers (#193 result; `docs/notes/several-stackings.md:9-15`);
  - `several-stackings.md:12-15` says the index merely selects an order, while
    the face relations explain why it is the intended one.

  A scheme should therefore state the relation it wants, not an index.

**A13. The state is fold angles; vertex positions are never interpolated.**
- *Source:* `AGENTS.md:300-307`; `docs/notes/fold-angles-are-the-state.md:11-31`;
  #27 point 4; #56 body; `docs/notes/the-puff-is-a-drawing.md:144-147`
  (coordinates may come from outside; hand-edited angles may not).
- *Verdict: reinforces PRDs 1 and 2.* A move sets angles or adds creases, and
  positions are derived.
- *Strains PRD 3:* the study's corrections move vertices numerically, and
  `roadmap.md:132-135` says those straight paths can stretch the sheet and are
  not folding instructions. A realistic in-between state must be either a
  checked state or labelled as a solver artefact.

**A14. Ids belong to the *cut* pattern and are renumbered — the naming problem.**
- *Source:*
  - `AGENTS.md:308-311`;
  - `src/Senbazuru/Origami/Folding.hs:283-313`: `foldedPattern` is not the input
    frame, and `unit-square.fold` goes in with 8 vertices and comes out with 9;
  - `src/Senbazuru/Origami/Flap.hs:9-10`: select ids from `foldedPattern`;
  - `study/fold-material/BlintzSequence.hs:4-8`: the recipe's edge ids refer to
    the fixture after cutting, and faces are reordered;
  - `related-projects.md:85-106`: the topological naming problem.
- *Verdict: overturns any design that puts `EdgeId` or `FaceId` in a written
  scheme.* The study's recipes are exactly that — for example
  `("Fold the first corner…", EdgeId 8, FaceId 2, -180)` in
  `BlintzSequence.hs:50-56` — and they are valid for one fixture only.
- *Precedent for an alternative:* `StudyCase.buildCasePose` resolves panel names
  from points on the original sheet, so declarations survive renumbering
  (`architecture.md:417-419`). `Surface` carries material coordinates
  (`architecture.md:462-467`).

**A15. The folding walk holds one face still, and today the recipes choose it by
hand.**
- *Source:* `BlintzSequence.hs:5-8`; `study/fold-material/HelmetSequence.hs:8-10`;
  `architecture.md:204-205`; `Flap.hs:19-24` (poses are aligned so the
  stationary side stays still).
- *Verdict: strains.* A scheme has to say what stays still. Otherwise the anchor
  is whichever face happens to be listed first, the whole model can turn between
  frames, and both the diffed arrows (A3) and the one-camera page (A22) mislead
  the reader.

**A16. At ±180° a mountain and a valley are the same rigid motion, and creasing
through layers alternates M and V.**
- *Source:* `AGENTS.md:312-314` and `:351-357`;
  `src/Senbazuru/Origami/ThroughLayers.hs:36-54`;
  `docs/notes/creasing-through-layers.md:30-41`.
- *Verdict: reinforces, with a newcomer trap.*
  - "Valley fold" in a scheme is said from the reader's current side of the
    model. After a turn-over that is the other side.
  - Through a packet of layers it writes M, V, M, V onto the sheet.

  The PRD has to define whose side a scheme's mountain and valley are read from.

**A17. Creasing a folded model creases every layer, and works on flat models
only.**
- *Source:* `ThroughLayers.hs`:
  - `:56-62`: folding only the near layers is a different move, belonging to
    the vocabulary, and would need depth;
  - `:63-68`: flat-folded models only;
  - `:69-72`: neither end of the line may be inside a face.
- *Verdict: constrains.* "Through all layers" and "top layer only" must be
  different moves, and the second has no implementation. Any crease move on a
  model with paper in the air is refused today.

**A18. The library checks a turn about one hinge line; coupled moves are not
general.**
- *Source:*
  - `Flap.hs:1-6` (it does not discover coupled motions) and `:34` (it does not
    infer a stack from coincident positions);
  - #54, remaining checkbox: compatible changes where creases meet;
  - #55 is open;
  - `study/fold-material/CheckedBird.hs:8-14`: it composes four certified paths,
    "not arbitrary instructions".
- *Verdict: strains the named macro-moves.* Squash, petal, reverse and sink each
  move several creases on different axes. Today they exist only as
  fixture-specific certificates in the study. A PRD that lists `petalFold` as a
  general move is asking for #55.

**A19. The study's recipes and manifests are deliberately not an instruction
language.**
- *Source:* `BlintzSequence.hs:4` ("a recipe … not an instruction language");
  `architecture.md:206-207` (neither module adds a general instruction format);
  `architecture.md:412-413` (the study manifest is not a new library input
  format); `study/fold-material/StudyCase.hs:212-214`.
- *Verdict: overturned by the request, deliberately.* PRDs 1 and 2 build the
  general format these modules disclaim.
- The recipes supply the move shape to generalise from: title, crease selection,
  moving side, signed travel, and angles and orders carried forward. #60 said to
  wait for three examples. Four now exist: blintz, helmet, the quarter fold
  (`test/Senbazuru/Origami/FlapSpec.hs:36-47`) and the crane wing (#193).

**A20. The library imports no study code; the study is its own executable and is
compiled into the tests.**
- *Source:*
  - `architecture.md:201`, `:230-232` and `:405-406`;
  - `senbazuru.cabal:175-189`: the study executable depends on the library plus
    `directory`;
  - `senbazuru.cabal:193`: the test suite's source directories include
    `study/fold-material`;
  - `senbazuru.cabal:152-159`: the library does not depend on `directory`;
  - #208: the build/test job took 14m36s, 10m48s of it in `stack test`.
- *Verdict: strains PRD 3.* "The study consumes what (1)/(2) define" fits the
  current direction of dependency. "The CLI produces realistic renderings" needs
  either solver code promoted into the library, with its own review, or a CLI
  that links the study. Adding long solves to the default tests collides with
  #208.

**A21. Backends consume `Diagram`; the 3D exception consumes `Surface`.**
- *Source:*
  - `AGENTS.md:214-222`; `architecture.md:176-182` and `:470-473`;
  - `architecture.md:402-405`: the study's corrected meshes use a depth-buffered
    viewer, because the SVG painter assumes a layer order those meshes can
    violate;
  - `architecture.md:123`: `Render.Projected` handles convex open panels;
  - `roadmap.md:61-62`: rendering general bent panels remains a
    study-to-production gap.
- *Verdict: reinforces the route* — glTF from `Surface`, SVG via
  `surfaceDiagram`.
- It also means an SVG wireframe of bent paper does not exist yet. PRD 3 must
  plan it together with #104.

**A22. One camera and one scale per page.**
- *Source:* `AGENTS.md:358-362`; `Steps.hs:15-26`;
  `the-puff-is-a-drawing.md:44-50` (books break this exactly once, at the step
  where the model stops being flat, and senbazuru has no such exception).
- *Verdict: strained by PRD 3, and by any per-step `view` in a scheme.* The
  exception needs designing and announcing on the page, not permitting per
  figure.

**A23. Thickness is optional material metadata, not display spacing; a bend
radius does not follow from layer count.**
- *Source:*
  - `paper-thickness.md:3-17`; `docs/notes/connected-paper-surface.md:18-26`;
    `glossary.md:123`; #146 done-when 4;
  - `docs/notes/two-bends-need-more-than-radii.md`: in the double fold, the upper
    layer's second bend stretches by 200%, and the surface has 4.71% more area
    than the sheet;
  - `docs/notes/a-crease-is-a-hinge.md:5-9`: that note is now marked as an early
    hypothesis.
- *Verdict: constrains PRD 3.* "Realistic" must not bring back per-layer lifting,
  or #114's radius rule presented as physics.

**A24. Schematic versus material opening.**
- *Source:* `the-puff-is-a-drawing.md:3-7` (the schematic proposal is kept as
  history); #106 body (a bump is not a material-preserving state; opening needs a
  control, compatible crease motion, bending where needed, and contact checks);
  `README.md:158-165`.
- *Verdict: defines "realistic".* PRD 3 should mean checked material geometry,
  with any schematic output labelled as such.

**A25. A valid state, a checked route and reachability are three different
questions.**
- *Source:* `docs/notes/endpoints-and-routes.md:8-12` and `:33-36`; #61, "Limits"
  (a contact witness is not the earliest impact; an unresolved interval is a
  refusal).
- *Verdict: constrains all three PRDs.* Each move must say what it certifies: a
  valid endpoint, a checked route, or neither. A scheme that runs without error
  has certified only what its interpreter checked.

**A26. Licences.**
- *Source:* `AGENTS.md:132-153`; `related-projects.md:35-38` (TreeMaker is GPL;
  ReferenceFinder "GPL (not checked)"; Eos and Doodle "not checked").
- *Verdict: constrains.* Borrow ideas, such as Huzita–Hatori references or
  Doodle's text shape; never borrow expression. Example schemes should fold
  traditional or generated models, never another designer's pattern.

**A27. Frame inheritance is decoded, not resolved.**
- *Source:* #102; `fold-reference.md:59-64` and `:221-224`;
  `StudyCase.hs:212-214`.
- *Verdict: constrains the output.* A scheme must write every frame in full.
  Resolving #102 later would change what a round trip preserves.

**A28. The FOLD writer's loose ends.**
- *Source:* #58 items 3-4;
  `src/Senbazuru/Fold/Load.hs:182` (`encodeFoldFile :: FoldFile -> ByteString`,
  so it cannot refuse a non-finite number); `Load.hs:192` (`BS.writeFile`, not
  atomic); `round-trips.md:128-143` (the refusal is not done).
- *Verdict: newly reachable.* #58 waited on "an authoring toolset" to reach
  these. A `run scheme -o model.fold` edit loop, writing over the file it read,
  is that toolset.

**A29. Clarity over cleverness, and few dependencies.**
- *Source:* `AGENTS.md:15-17`; #55 body (a hand-written Gauss–Newton, no
  `hmatrix`); #62 body (write the dual number by hand rather than depend on
  `ad`).
- *Verdict: constrains PRD 1.* Type-level EDSL machinery and heavy dependencies
  must earn their place by doing design work.

**A30. Types mirror the format; validation is separate.**
- *Source:* `AGENTS.md:179-183`.
- *Verdict: a template for PRD 2.* **[analysis]** Parse permissively, so a
  failure means "not a scheme". Then resolve names to geometry in a separate
  step that refuses what senbazuru cannot do yet.

### B. How the relevant open issues depend on each other — question (b)

"A ← B" means A waits on B. Statuses are from `gh issue list` on 2026-09-14.

```
#60 vocabulary (roadmap) ← #97 scheme format ← #96 note on the 2026 papers   (roadmap.md:370-373)
  #97 gates #95 turn over (#97 body); then #94 captions and #36 arrow kinds
  #95 → #36 (the looped arrow);  #36 ~ #48 x-ray lines, #49 cut-away (both scoped by Step)
#60 ← #54 flap rotation [largely done as Origami.Flap] ← #52 degree-4 closed form
  #54 → #55 coupled angle solve ← #52, #53 simulator tolerances, #62 dual-number Jacobian
  #55 → #56 glTF animation ← #110 folded frame with its layer order
  #54, #55 ~ #61 checks along a motion
every move touches: #73 vendor keys, #111 what an angle means, #109 angle-list length,
  #102 frame_inherit, #58 items 3-4, #63 phantom units
closed prerequisites: #34 faces, #19/#57 writer, #72 crease, #70 through layers,
  #91 fold verb, #146 shared surface
#106 pocket opening ← #146 (done), #114, #61, #54/#55, #104 silhouettes
  #195 curved wing (study) → #106;  #206 visibility refusal;  #208 CI cost
#50 side view (thickness is now optional metadata, #146)
#64 rigid vs compliant note (not yet written) frames #55, #56, #61, #106
roadmap.md:368-374 orders #93 corpus sweep (with #87 behind it) before #96 and #97
```

What the PRDs would do to each:

- **Close:**
  - #97, if a PRD writes the decision into `docs/notes/schemes.md` as #97's
    done-when asks.
  - #95, since `TurnOver` becomes one constructor.
  - Plausibly #94, once step text writes `frame_title` and captions render.
- **Subsume in part:**
  - #60: the vocabulary and the verb. Its "rest of the moves" includes coupled
    macro-moves that hang on #55.
  - #36: arrow kinds could come from the scheme.
- **Rewrite before reusing:**
  - #60 done-when (C1-C3);
  - #97 done-when 2 (same fixture);
  - #36 done-when 1 (C5);
  - #94 premise (C6);
  - #114 (C8);
  - #64's framing. It says inflating a body is outside the model, which #106,
    `README.md:158-165` and `connected-paper-surface.md:38-46` have overtaken.
- **Depend on without closing:** #54, #55, #61, #104, #106, #195.
- **Resolve, or explicitly defer, inside the PRDs:** #73, #102, #58 items 3-4,
  #111, #109, #63.

### C. Acceptance criteria checked against the code and fixtures — question (c)

**C1. #60's comment "that fixture needs no crease-adding at all" is correct.**
Checked with `jq` on `examples/quarter-fold-steps.fold`:
- the key frame and both `file_frames` have identical `edges_vertices`
  (12 edges), `faces_vertices` (4 quads) and `edges_assignment` (eight `B`, then
  `M, V, M, M`);
- `vertices_coords` are nine two-component points;
- the angles on edges 8-11 go from all 0, to `[-180, 0, -180, 0]`, to
  `[-180, 180, -180, -180]`;
- no frame carries `faceOrders`.

The three frames differ only in fold angles and the coordinates derived from
them.

**C2. #60 done-when 1 is reachable with existing code, and is a weak test.**
- `examples/quarter-fold.fold` has the same vertices, edges, faces and
  assignment as the steps fixture's key frame, and exactly the final frame's
  angles (`jq`).
- `FlapSpec.hs:36-47` folds that file in two checked turns:
  `prepareFlapAlong [8,10] (FaceId 3) (-180)`, re-fold, then
  `prepareFlapAlong [9,11] (FaceId 1) 180`. It asserts the final angles equal
  the source's.
- So a checked, crease-free route to the last frame already exists in a test.
  Reproducing this fixture tests folding, not a vocabulary.
- "Coordinates match" still needs a tolerance and a 2D/3D decision.
  `foldedAttributes` writes `2D` or `3D` according to relief
  (`Folding.hs:408-413`).

**C3. A convention is hidden in the fixture.**
- Step 2 has `V` on edge 9 and `M` on edge 11, both at angle 0. The key frame
  has M/V at angle 0 on every crease.
- PR #72's "Interesting bits" say a `V` at angle 0 "is not a valley" and that
  writing one made an invalid file.
- `docs/notes/precreases-and-target-states.md:20-23` writes an unbent guide line
  as `F` at 0.
- `StudyCase`'s `active` (`StudyCase.hs:207-210`) turns an `F` with a nonzero
  angle into M or V. It leaves an M/V at angle 0 alone, so the study does not
  contradict the fixture.

So the fixture uses the assignment to mean the crease's eventual direction. A
scheme interpreter must choose a convention. Matching the fixture byte-for-byte
commits it to the one #72 called invalid.

**C4. #60 done-when 2: the golden exists.** It is
`test/golden/quarter-fold-steps.svg`, used by `SvgSpec`. It contains
`<title>fixture</title>`, the step numbers 1, 2 and 3, and no captions. It
collides with #94 (C6).

**C5. #36 done-when 1 cannot be met as written, and it contradicts #95.**
- On a flat model, reflecting through the sheet's plane (z → −z) leaves every
  coordinate unchanged, because z is 0. `Step` compares positions only
  (`Step.hs:30-34`), and `StepSpec.hs:90` pins that it "finds nothing between a
  frame and itself". There is nothing to classify.
- #95 argues a turn-over is a half turn, `(x, y, z) ↦ (−x, y, −z)`, and that a
  reflection gives the mirror model.
- `CreasePatternSpec.hs:401-410` pins that no arrow is drawn when a motion's two
  ends project to one point.
- **[analysis]** #95's half turn is about the page axis at x = 0. The quarter
  fold occupies x ∈ [0.5, 1], so the model would also jump across the page, and
  `Step` would report a translation. The PRD must fix the axis (for example
  through the model's own centre), and the move's kind must come from somewhere
  other than a positional diff.

**C6. #94's premises are stale.**
- It says `frame_title` is decoded and nothing reads it. In fact `Cli.hs:779`
  and `:879` read it for the GLB and SVG titles, and `fold-reference.md:54`
  marks it "used (SVG `<title>`)".
- Its done-when "quarter-fold-steps, given titles" is already true: all three
  frames have titles (`jq`).
- Rendering captions therefore moves the existing golden, against #60's
  done-when 2, unless captions are opt-in.

**C7. #52 and #60's crane counts are correct, with a qualification.**
`jq` on `examples/crane.fold`:
- 48 vertices touch no border (`B`) edge.
- Counting `M`, `V`, `F` and `U` edges, 41 of those vertices have degree 4, 6
  have degree 6 and 1 has degree 8.
- Counting only M and V, 10 have degree 2, 37 degree 4 and 1 degree 6.

So "41 of 48" counts flat guide lines as hinges. #55's "119 non-border creases"
matches 58 M + 41 V + 20 F.

**C8. #114's premises have been superseded.**
- There is no `--thickness` flag: no match in `Cli.hs`.
- No corner-ownership or face-lifting text remains in
  `src/Senbazuru/Render/Gltf.hs`, and #146 records per-face lifting as removed.
- Its argument "a rounded fold is isometric, so a radius from layers × thickness
  is faithful" extends to stacks. `two-bends-need-more-than-radii.md` shows the
  stacked case stretching the paper.
- Its invariant (the exported mesh has as many connected components as the
  pattern) was met by #146's done-when 2.
- Only the single-fold spine can be reused as written.

**C9. #55 done-when 1 is met for its two fixtures, but by prescribed routes, not
by the solver it describes.**
- `Flap` poses are re-folded from angles and checked (`Flap.hs:19-24`).
- The bird route is four certified paths composed together
  (`CheckedBird.hs:8-14`; #189 closed).
- "Every intermediate frame accepted" holds for the checked poses. The Newton
  solver does not exist.

**C10. #106 done-when 1 is not reachable with current fixtures.**
- `examples/` has `waterbomb-base.fold`, but no waterbomb balloon.
- `roadmap.md:313-315` says the crane pocket map "does not yet identify a closed
  cavity".

**C11. #97 done-when 2 reuses #60's test and inherits C2-C4.** The bird base,
named in #97's approach, is the more discriminating target. Its route exists
only as a study certificate (A18).

### D. Glossary coverage — question (d)

Checked with `grep` for `| **Term` rows in `docs/glossary.md`.

**Present, but thin or inaccurate:**
- **Flap** (`:29`) does not say how a flap is identified. The code's working
  definition is the faces reached after removing the selected creases from the
  face graph (`Flap.hs:2-6`).
- **Step** (`:48`) says steps are stored as consecutive frames of `file_frames`.
  But the key frame is also a step (quarter-fold-steps' "Step 1: the flat sheet"
  is the top-level object), and a key frame holding only metadata is not one
  (`Steps.hs:85-89`).
- **Squash fold**, **Rabbit-ear fold** and **Petal fold** (`:32-34`) describe the
  hand motion. None says which creases change, or that each is a coupled
  multi-axis move.
- **Rest angle** is defined twice, differently:
  - at `:19`, as set by the material's yield stress, independent of thickness,
    and not zero;
  - at `:83`, as a spring's preference that the solve need not reach.

  That breaks the glossary's own claim to be the one place a definition lives
  (the `AGENTS.md` docs table).
- **Collapse** (`:37`) and **Through all layers** (`:38`) are adequate.

**Missing, and needed by the PRDs:**
- *Language:* scheme, move, macro-move, reference (point or line), landmark,
  anchor (the stationary face), interpreter.
- *Moves:* precrease (defined only in `precreases-and-target-states.md:3-6`),
  fold-and-unfold, turn over, rotate, inside and outside reverse fold, sink (open
  and closed), crimp, pleat, swivel.
- *Motion:*
  - hinge, used throughout `Flap` and the notes;
  - route, and configuration space (`endpoints-and-routes.md:26-31`);
  - checkpoint, and certificate;
  - travel: a signed change in fold angle (`Flap.hs:10-13`).
- *Diagram:* x-ray line, cut-away, side view, silhouette, caption.
- *Material:*
  - hold or grip, and control (an opening control);
  - subdivision edge versus material crease, hinted at under **Panel** (`:82`);
  - pocket or cavity, and mid-surface;
  - numerical correction versus folding motion.

## Implications for the design

1. **Make one first-order AST that both the EDSL and the file produce.** Put the
   Haskell ergonomics in smart constructors, not in binds. Then the file and the
   EDSL really are the same language (A2).
2. **Decide how paper is named before designing moves.**
   - Refer to paper by material landmarks on the original sheet, resolved
     against `foldedPattern` at each step.
   - Refuse, by name, a landmark that no longer names any paper.
   - Never expose `EdgeId` or `FaceId` in the language (A14).
   - Give resolution its own error type, carrying the step and the landmark
     (A7).
3. **Tier the vocabulary by what can be checked.**
   1. Crease-only moves, through `Creasing` and `ThroughLayers`, batched.
   2. Single-hinge turns, through `Flap`, with a checked route.
   3. Coupled macro-moves: either endpoint-only frames marked unchecked, or
      fixture-specific certified routes, until #55 lands.

   Never present a tier 3 move as tier 2 (A18, A25).
4. **Every step states** its anchor, which side mountain and valley are read
   from, and optionally a layer-order relation — never a stacking index (A12,
   A15, A16).
5. **The output is an ordinary multi-frame `FoldFile`.**
   - Every frame is written in full (A27).
   - Step text goes in `frame_title` (A4).
   - Anything else goes under a named vendor key, with #73's split between file
     and frame keys decided first (A6).
   - If move kinds reach the arrows, record that as a stated exception to A9 in
     `AGENTS.md` and `architecture.md`.
6. **Replace the quarter-fold acceptance test in #60 and #97.** Use a sequence
   that adds creases on the flat sheet and through a folded state (the fixture
   #70 asked for). Keep quarter-fold-steps as a folding regression checked to a
   tolerance. Settle the M/V-at-0 convention (C3) before any byte comparison.
7. **Sequence captions (#94) and #60's golden explicitly,** or make captions
   opt-in (A8, C4, C6).
8. **For PRD 3, "realistic" means checked material surfaces through `Surface`,**
   as #106 defines it, with schematic output labelled.
   - Ship it as a new verb, flag or scene, never as a changed default.
   - Plan SVG for bent panels together with #104.
   - Keep physical parameters apart from display offsets.
   - Keep long solves out of the default CI run (#208).

   (A20-A24.)
9. **Take a `Budget` everywhere** (A12); **open a scheme's starting sheet through
   `Fold.Load`** (A9); **fix #58 items 3-4 when the edit loop ships** (A28).
10. **Revise `no-sequence-solver.md` alongside PRD 1.** The project's own
    vocabulary makes its first reason a statement about the field, not about
    senbazuru (A1).

## Open questions

- Is a scheme an input format, following A9 strictly so that information travels
  only through FOLD keys? Or is it a second front end with a stated exception?
- After a turn-over, do mountain and valley refer to the sheet's printed side, or
  to the side the reader is now looking at?
- Do landmarks live only on the original sheet? That is stable, but a flap made
  part-way through has no name beforehand. Or can a step bind a new name — the
  case that pushes toward monadic structure (A2)?
- Is the fixture's M/V-at-angle-0 convention valid FOLD (see Unverified), and
  which convention will the interpreter write?
- May captions deliberately change the quarter-fold-steps golden once, or must
  they be opt-in?
- Does PRD 3's CLI path promote study solvers into the library, and which checks
  decide a promotion?
- Where does the one-camera exception for a final 3D figure live: in the scheme,
  in the page layout, or in the renderer?
- Should a macro-move without a checked route be allowed in a scheme at all, or
  only through an explicit "unchecked endpoint" construct?

## Unverified

- **#60 comment:** that refolding reproduces the fixture to within `6e-17`, as
  three-component coordinates. Not run, because building was out of bounds.
- **FlapSpec's first quarter-fold turn:** whether its endpoint equals step 2's
  angles `[-180, 0, -180, 0]`. The test asserts only the final angles.
- **PR #72:** that a `V` at angle 0 is invalid FOLD. `fold-reference.md:85`
  gives only the range [−180, 180] with negative as mountain. I did not fetch
  the FOLD specification.
- **Rendering:** whether a folded frame draws M/V at angle 0 differently from `F`
  at angle 0. This decides whether C3's convention choice moves the steps golden.
- **#95:** that `apply TurnOver` followed by `render` equals
  `render --view bottom --rotate 180`. Not run.
- **External sources:** the contents of the 2026 papers (#96;
  `related-projects.md:115-124`), DIAMOND (#36), Doodle, Foldinator and Eos.
  None was fetched. `related-projects.md` marks several of their licences "not
  checked", ReferenceFinder's included (`:36`).
- **Measurements:** #208's CI timings and #87's profiles are taken as reported
  in the issues, not re-measured.
