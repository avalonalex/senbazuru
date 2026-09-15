# Gap — folding only some layers of already-folded paper

Researched 2026-09-14 against the repository at `568dcb6`
(branch `docs/prds-sequence-language`, clean). Nothing in the repository was
modified, built or tested.

Evidence used:

- `sed`/`rg` on the cited lines;
- `jq` on fixtures;
- `gh issue view 60`, `70` and `97` (bodies and comments);
- two fetches of https://origami.me/crane/ (© Origami.me, all rights
  reserved, so everything below is paraphrase);
- a scratch Python script I wrote, kept as
  [`scripts/layer-selection-analyse.py`](scripts/layer-selection-analyse.py).

The script is an independent re-implementation of four ideas the module
headers describe: tracing faces, folding a flat fold by reflections over a
walk of the face graph, clipping a folded-space line to each face, and
splitting the face graph along that line. It is not senbazuru, and GHC was not
run. Two checks tie it to the real code:

- It puts material vertex 2 of `examples/crane.fold` at folded `(1, 0)`, which
  is the tip position `CraneWingSpec.hs:99` expects at progress 0.
- The worst disagreement between faces about a shared vertex is `3.0e-13`.

Every number marked **(script)** comes from it. Reproduce with
`python3 scripts/layer-selection-analyse.py line <fold> x0,y0 x1,y1 u,v`. Add `CUT=f,g` to cut only
some faces, or use `layer-selection-analyse.py tacos <fold>`.

Terms used below: see `docs/glossary.md`. It defines flap (`:29`), layer order
(`:40`), taco (`:41`), layer number (`:47`), face ordering (`:63`) and material
coordinates (`:81`). A **share** is the piece of the drawn line that lies on
one face, mapped back to the flat sheet.

## Summary

A book step such as "valley fold the top flap along L" needs a set of faces
before any library call can run. Today `creaseThroughLayers` creases every face
under L. `CraneWing` hand-picks four faces and copies ThroughLayers' private
clipping and mapping without its guards.

A rule works without hand-picking. Cut every crossed face along L. The faces
connected to a material **seed** point are the flap. The accepted `faceOrders`
then say whether that flap is uncovered on the side it turns towards. A
**top n layers** selector is counted at each point of the line, not by layer
number.

On the crane this rule reproduces `CraneWing`'s faces `[2,3,6,7]` exactly
(script). The same line crosses 16 faces. Choosing one layer instead of two is
a coupled move that `Flap` refuses.

Unselected layers should get **no** crease. A crease at angle 0 changes
nothing about connectivity. It does break the "every U edge is the hinge"
recovery, it adds lines the reader never made, and `F` cannot hinge later.

The smallest library addition is `creaseThroughLayers` restricted to a face set
that returns its new edge ids. The interpreter also needs `nearness` exported
and a way to carry accepted orders across the crease.

## Findings

### What exists

1. **ThroughLayers creases every face under the line, by design, and says the
   selective move belongs elsewhere.** The header says a book distinguishes
   all layers from the near ones. It calls the second a different move that
   would need a depth question this module never asks (`ThroughLayers.hs:56-61`).
   The code matches:
   - shares are computed for every panel (`:254`);
   - the ends are refused if strictly inside *any* face (`:241-247`);
   - one batch is handed to `creaseAllAlong` (`:261-264`).
   The function takes a `Frame` and folds it itself (`:227-229`). A caller that
   chose faces from its own `foldFrameWith` result is therefore relying on the
   second fold numbering faces the same way. Only `creaseThroughLayers`,
   `ThroughError` and `renderThroughError` are exported (`:82-86`). The share
   function (`shareFor`, `:285-297`) and the per-layer flip (`facesUp`,
   `theOtherWay`, `:327-340`) are private.

2. **Issue #70 set this as an open decision. The code decided "refuse by
   omission", and the issue's own mechanism is not what shipped.** The #70
   body lists "decide which layers the crease cuts" as a property of the
   instruction. Its done-when asks that a crease missing some layers be
   "refused or expressible", decided rather than discovered. #70 is CLOSED,
   and the code creases all layers (finding 1).
   The issue proposed reading up-ness from `Origami.Flat`'s `panelFaceUp`. The
   module instead reads it from the placement's motion, and says why
   (`ThroughLayers.hs:47-52`). This is one more case of issue text that is not
   evidence. #60's owner comment calls #70 "probably a hard prerequisite" for
   every move after the first.

3. **`Flap` finds the moving paper by connectivity. It refuses selections that
   do not cut it free, and refuses `F` hinges.** `prepareFlapAlong`:
   - removes the selected creases' links from the face graph;
   - walks from the moving face;
   - refuses `FlapCoupled` if the stationary face is reached
     (`Flap.hs:196-199`).
   Every selected segment must:
   - be M, V or U (`:187`, else `FlapNotHinge`);
   - separate moving from stationary paper (`:209`, `FlapNotBoundary`);
   - lie on the hinge line in the *folded* shape, within `1e-12` of the
     sheet's span (`:207`, `:215`, `FlapUnalignedCrease`).
   Ids must come from `foldedPattern`, because cutting renumbers (`:9-10`). The
   module does not discover coupled motions (`:1-6`). Each overlapping pair
   needs a supplied order, and none is inferred from coincident positions
   (`:33-34`).

4. **`creaseAllAlong` writes ±180 for M/V whenever an angle array exists.** It
   drops faces, orders and extras, and appends the new edges at the end.
   - Angles: `flatAngleFor` gives M → −180, V → 180, anything else → 0
     (`Creasing.hs:316-320`). They are written when `edgesFoldAngle` is
     non-empty (`:290-292`). The header says a valley at 0 "is not a valley"
     (`:281-286`).
   - So through this API an unselected layer's crease "at angle 0" can only be
     `U` or `F`.
   - New edges are appended (`:255`) before `withPlanarFaces` (`:159`).
   - `facesVertices`, `faceOrders` and `frameExtras` are cleared (`:265-267`).

5. **New creases end up as a suffix of the edge list; old edge ids shift.**
   - The sheet numbers edges in id order (`Faces.hs:188-193`).
   - Cutting walks them in that order (`Crossings.hs:267-271`).
   - Each edge is replaced *in place* by its consecutive pieces
     (`Crossings.hs:342-346`), and each piece keeps its parent's assignment and
     angle (`:348-356`).
   - Faces are always re-traced after `creaseAllAlong`, because it empties
     them (`Faces.hs:136-150`).
   Two consequences. First, every piece of every new crease comes after every
   piece of every old edge, so a library could return the new ids at no cost.
   Second, an old `EdgeId` moves by one for each extra piece an earlier edge
   was cut into, and `FaceId`s are renumbered by tracing.

6. **CraneWing is the only precedent, and four of its steps are hand-written.**
   - It clips a fixed long line `(0,0.25)–(2,0.25)` to hand-named faces
     `[2,3,6,7]`. It maps each piece back with `inverse` placements and creases
     with `Unassigned` (`CraneWing.hs:90-101`).
   - Its clip has **neither** of ThroughLayers' guards: the length test and the
     midpoint-strictly-inside test (`ThroughLayers.hs:289-290`). A face touched
     only along an edge would produce a degenerate share there. This is the
     drift AGENTS.md warns about for policies copied into a second place.
   - It restores the anchor face's ring to position 0 after re-tracing, so the
     crane does not move (`CraneWing.hs:14-15`, `56-63`).
   - It recovers the hinge as "every `Unassigned` edge" and checks there are 4
     (`:65-66`). That only works because `crane.fold` has no U edges (`jq`: 0).
     `CranePocket.hs:131,138` depends on the same trick ("AuthoredRoot", count
     4).
   - It picks the moving face as the one containing both hinge ends and
     material vertex 2 (`:72-74`).
   - It re-solves the stacking and takes index `[2]` (`:75-79`). A test checks
     the tail relations that justify that index (`CraneWingSpec.hs:62-81`).

7. **The accepted order is not preserved across a crease; the precedent
   re-solves it.** `layerOrderFor` re-solves only when a frame has no orders
   (`Stacking.hs:386-400`), and creasing always empties them (finding 4). The
   crane admits five orders, and index 2 is the one that tucks the tail
   (`docs/notes/several-stackings.md`, paragraphs 1–2).
   `docs/notes/chaining-checked-folds.md` (paragraph 2) warns about exactly
   this: re-solving "could silently choose a different stack". Nothing in
   `src` or `study` maps orders from parent faces to child faces (`rg` for
   inherit/refine/parent found only unrelated hits).

8. **`nearness` is the right tool and is not exported. It also treats a missing
   order as "neither is nearer".** `Visible.nearness` combines three things:
   FOLD's rule that a sign is read against the second face's normal, the face's
   up-ness from its winding, and the viewer's side (`Visible.hs:240-270`). An
   unrecorded pair answers `False` both ways (`:226-229`), which is only right
   if the pair really does not overlap. The module exports only `VisibleForm`,
   `Region`, `VisibleEdge` and `visibleForm`. An interpreter that wants
   "nearer" would have to restate the sign convention, and
   `Folding.hs:303-308` warns that faces and orders must come from the same
   frame, `foldedFrame`.

9. **Layer numbers are the wrong count for "top n".** `layerDepths` gives the
   longest chain of "above" relations. On the crane that chain is 31 while the
   thickest point holds 24 sheets (`docs/notes/layer-numbers.md`, "What it
   costs"). A chain can pass through faces that never share a point under the
   line, so "top 2 layers" must be counted at each point along the line.

10. **Material points already name panels in the study.** `StudyCase` resolves
    a panel, or the fixed panel, by a finite material point strictly inside
    exactly one face, with tolerance `1e-10` (`StudyCase.hs:139-143`,
    `165-170`). That is the precedent for a seed.

### Re-deriving CraneWing by rule (script)

11. **The crane line crosses 16 faces in three groups, not 4.** ThroughLayers
    would crease all of them; no end is strictly inside a face (script).

    | faces | what they are | span along the line | face up |
    | --- | --- | --- | --- |
    | 2, 3, 6, 7 | wing A (all contain material corner (0,1), vertex 2) | x ∈ [0.896, 1.104] | 2 no, 3 no, 6 yes, 7 yes |
    | 0, 1, 4, 5 | wing B (all contain material corner (1,0), vertex 54) | same span | 0 yes, 1 yes, 4 no, 5 no |
    | 8–15 | tail (all contain material corner (0,0), vertex 0) | x ∈ [1.25, 1.28] | mixed |

    Wing A's four shares on the sheet run (0.25,1) → (0.25,0.896) →
    (0.177,0.823) → (0.104,0.75) → (0,0.75). That is the "bent chain" the
    header describes (`CraneWing.hs:8-10`).

12. **The seed rule gives `[2,3,6,7]` without naming a face.** Seed the
    material point (0.02, 0.97): it lies in face 7 and folds onto the tip side.
    Cut all 16 crossed faces along the line. The seed's component is exactly
    {2, 3, 6, 7}, and no face has both halves in it (script). The seed
    (0.97, 0.02) gives wing B, {0, 1, 4, 5}.

13. **One layer of the wing is a coupled move.** Cut only {6, 7} or only
    {2, 3}. The seed's component is then all 72 faces, with both halves of the
    cut faces in it (script). The reason is edge 2–11. It joins faces 2 and 6
    (a mountain taco) and runs from folded (1, 0) to (0.866, 0.324), crossing
    y = 0.25. So the two thicknesses stay joined on the tip side, and `Flap`
    would say `FlapCoupled`. Cutting wing B as well ({0…7}) leaves the
    component at {2, 3, 6, 7}, so an extra crease at angle 0 changes nothing
    about connectivity.

14. **"Top 2 from +z" picks wing B, not wing A.** The taco rule is the solver's
    own first rule (`Stacking.hs:49-52`). By it, from +z: 6 over 2 (edge 48),
    7 over 3 (edge 24), 0 over 4 (edge 35) and 1 over 5 (edge 12) (script).
    The order between the two wings comes from the checked turn:
    - the accepted +90° lowers the tip to z = −0.25 (`CraneWingSpec.hs:99`);
    - the −90° direction, which lifts the tip, is refused with
      `FlapEndpointOrder 0` (`CraneWing.hs:81-84`, `CraneWingSpec.hs:52-54`);
    - the note says that refusal is the stationary wing being in the way
      (`a-wing-resting-on-paper.md`, paragraph 5).
    So wing B lies on wing A's +z side. At every point of the line, top to
    bottom from +z, the stack is B (2 faces) then A (2 faces). "Top 2 from +z"
    is wing B, and wing A is "top 2 seen from −z". A book would say "turn
    over, fold the top flap down". This is inferred from assertions I read but
    did not run; see Unverified.

### A second and third fixture (script)

15. **Quarter fold, top-layer corner fold.** `examples/quarter-fold.fold`
    stacks four faces exactly.
    - Taco rule, bottom to top from +z: face 3, 0, 1, 2. The rules alone make
      this a total order of four overlapping faces, so any accepted order must
      be this one. It agrees with the M, V, M, V measured bottom to top in
      `docs/notes/creasing-through-layers.md` ("More layers").
    - Line (0.5,0)–(1,0.5), folding the corner towards the centre: all four
      faces are crossed. Each share runs between existing vertices: face 0
      4→5, face 1 6→5, face 2 6→7, face 3 4→7.
    - Top 1 from +z is {2}. The seed near material (0,1) also gives {2}.
    - The seed near (1,0) gives {0}. Faces 1 and 2 cover it from above and face
      3 from below, so it can turn neither way. The rule should refuse that
      with orders, before a sweep does.
    - Restricted to {2}, the pattern gains one U crease, 6–7. ThroughLayers
      would add the whole square 4–5–6–7, three creases the reader never made.

16. **Square base (crane step 5, kite fold) — "top flap" means two
    thicknesses.** `examples/square-base.fold`, folded:
    - Line from the sheet corners' point (0,0) to (0.5, 0.2071) crosses faces
      {0, 1, 6, 7}.
    - Taco rule, bottom to top: 6, 7, 0, 1.
    - The seed near material (0.5, 0) gives {0, 1}: the top two, joined along
      the side fold 4–8. The seed near (0, 0.5) gives {6, 7}.
    - Cutting only {1} is coupled.
    So origami.me's "top flaps" is two sheets per flap.

17. **Square base, top-corner line (crane step 6).** Line
    (0.5, 0.2071)–(0.2071, 0.5) crosses all 8 faces. Their halves on the
    centre-of-sheet side form one component. Cutting only the front two
    ({1, 2}) or front four ({0, 1, 2, 3}) is coupled (script).
    - Why: face 0 is joined to face 7 along the centreline beyond the line.
    - Consequence: on this fixture, "fold the top corner down" can only be a
      rigid hinge through all layers.
    - The kite flaps from step 5 reach exactly to this line and do not cross
      it; that was not modelled.

## Implications for the design

### (a) A rule from line + selector to a face set

Inputs:

- the current `Folded`, the result of folding the current pattern;
- the **accepted** orders for its `foldedFrame` (finding 8), never re-solved;
- a folded-space line (p, q);
- the viewer side (+z or −z; after a presentation turn-over this is −z);
- a selector.

Steps:

1. Read `flatSheet (foldedFrame …)`. Compute each face's share with
   ThroughLayers' three guards: clip, length above the hair, midpoint strictly
   inside (`ThroughLayers.hs:285-297`). Call the crossed faces C, each with its
   interval along the line.
2. Collect existing edges that lie along the line inside (p, q). These are
   hinge candidates that need no crease: crane steps 15–23 fold along existing
   creases.
3. Build the piece graph. Each crossed face becomes two pieces, one per side
   of the line; each other face is one piece. Pieces are linked across shared
   interior edges, by which side the edge's end vertices are on. An edge lying
   along the line is not a link.
4. Selector **`FlapAt m`** (a material point):
   - m must be strictly inside exactly one face (`StudyCase` precedent,
     `1e-10`);
   - fold m through that face's placement, and refuse it if it lands on the
     line;
   - K is the seed's component, and selected = C ∩ faces(K);
   - refuse if K holds both halves of any face.
5. Selector **`TopLayers n side`**, where `side` is a material point on the
   moving part:
   - split the line at every interval endpoint;
   - on each sub-interval, sort the covering faces with the viewer's nearness
     (every overlapping pair must have an order);
   - a face's depth must be the same on every sub-interval it covers;
   - selected = faces of depth < n.
6. **Both selectors:** cut only the selected faces and walk from the moving
   side.
   - If the walk reaches a piece on the other side of any selected face,
     refuse as coupled (finding 13), naming the unselected face that joins
     them.
   - Then use the orders to check that no face outside the flap is nearer, on
     the side it turns towards, than a selected face over the same
     sub-interval (finding 15, seed near (1, 0)).

### (b) Unselected layers: no crease

A crease at angle 0 on unselected layers leaves Flap's connectivity unchanged
(finding 13), so it never causes `FlapCoupled`. It still costs:

- **Collinearity catches nothing.** Those segments lie on the same folded line
  and pass the `onLine` check (`Flap.hs:207`). Put them in a hinge list, as
  `CraneWing`'s every-U-edge recovery would, and they fail only at
  `FlapNotBoundary` (`:209`).
- **Unneeded refusals.** They inherit ThroughLayers' ends test for layers the
  reader never touched. On the crane line that means 12 creases instead of 4.
- **A lasting choice between U and F.** `F` blocks any later hinge there
  (`:187`). `U` keeps it usable, but writes a crease no book step made.
- **No gain on step pages.** They change the topology that `motionsBetween`
  compares (`Step.hs:94-96`) exactly as much as the selected creases do.

Recommend no crease. The "fold and unfold" steps (crane 1, 3, 5–7, 10) are a
separate question, the precrease convention (critic §3.2), and it concerns
*selected* creases after unfolding.

### (c) Smallest library addition, and what the interpreter does itself

A sketch; nothing here is implemented.

```haskell
-- Senbazuru.Origami.ThroughLayers
data Creased = Creased
  { creasedPattern :: !Frame,    -- faces re-traced; orders and extras dropped
    creasedEdges :: ![EdgeId]    -- every piece of every new crease (the suffix, finding 5)
  }

creaseLayersThrough ::
  S.Set FaceId ->   -- faces of foldedPattern to crease; others stay uncreased
  V2 -> V2 ->       -- the line, in folded coordinates
  Assignment ->     -- named from +z; flipped per face-down layer as today
  Folded ->         -- the fold the ids belong to; not folded again
  Either ThroughError Creased

-- creaseThroughLayers from to a fr =
--   creasedPattern <$> (fold, then creaseLayersThrough allFaces from to a folded)
```

Why this is the smallest:

- It reuses `shareFor` and the flip, which callers otherwise re-implement
  without the guards (finding 6).
- It removes the refold and the id mismatch (finding 1).
- It replaces the fragile U-edge recovery (finding 6).
- Existing goldens stay unchanged, because `creaseThroughLayers` becomes the
  all-faces case.

New `ThroughError` constructors: `LayerNotUnderTheLine FaceId`,
`LayerNotInThisFold FaceId`, `NoLayersChosen`. The ends test becomes
`LineStopsOnTheModel` for **selected** faces only.

Two more small exports are needed:

- `nearness`, or a wrapper that also refuses an overlapping pair with no order
  (finding 8);
- `carryOrders :: Folded -> [FaceOrder] -> Folded -> Either _ [FaceOrder]`.
  Each new face inherits its parent's relation. The parent is the old face
  that strictly contains the child's material centroid. Two children inherit
  a relation only if they overlap by more than the speck. This is exact
  because a crease at angle 0 moves no paper, and a child has its parent's
  normal. Without it, every step repeats CraneWing's re-solve-and-pick-index
  (finding 7).

What the interpreter can do itself, with exports that exist today:

- the piece-graph walk (`facesAlongEdges`, `foldedPlacements`, `clipSegment`,
  `strictlyInside`);
- restoring the anchor by a material point (`CraneWing.hs:56-63` does it by
  ring);
- choosing `Flap`'s moving face as whichever face of the first hinge edge lies
  on the seed's side;
- after the turn reaches ±180, relabelling U as M or V from the angle's sign
  (FOLD: a valley's angle is in (0, 180], `Creasing.hs:281-286`). Flap already
  gives each segment the sign its stationary face needs (`Flap.hs:208-216`),
  so the M/V alternation falls out without `facesUp`.

The selection rule itself belongs in the library too. PRDs 1 and 2 both need
it, and a policy restated per caller is the one AGENTS.md says gets forgotten.
It is not strictly needed to unblock an interpreter, though.

Tests. Each is named with the change that would turn it red.

- Restricted to all faces equals `creaseThroughLayers` byte for byte (red if
  the flip or guards differ).
- CraneWing's hinge equals the seed rule's output on `crane.fold` (red if the
  hand list and the rule diverge).
- Top 1 of the wing is refused as coupled, naming face 2 or 6 (red if the
  separation check is dropped).
- Quarter-fold seed near (1, 0) is refused as covered (red if orders are
  ignored).
- Carried orders on the creased crane still satisfy `CraneWingSpec`'s tail
  relations without `solveStackingAs [2]` (red if the carry loses a pair).
- U + flap to ±180 + relabel equals V at 180 from the restricted crease, for
  positions and assignments (red if either sign convention flips).

### Refusal list (for PRD error types, each with an `Explain` instance)

| Refusal | Carries | Trigger |
| --- | --- | --- |
| inherited `PaperStillInTheAir`, `FaceNotConvex`, `ThroughRefused` | as today | `flatSheet` |
| `NoAcceptedOrder` | — | overlapping crossed faces and no orders supplied; never re-solve silently |
| `UnorderedOverlap` | f, g, point | overlap on the line with no order, or order 0 |
| `ContradictoryOrder` / `CyclicStackAt` | f, g / point | `nearness` refusal, or a cycle on a sub-interval |
| `DepthChangesAlong` | f, point | a face partly covered along the line: the tie a "top n" cannot resolve |
| `SeedNotInOneFace` | material point, count | 0 or ≥ 2 faces (`StudyCase` rule) |
| `SeedOnTheLine` / `SideOnTheLine` | point | moving side undefined |
| `LineDoesNotSeparate` | f | seed component holds both halves of f |
| `SelectionCoupled` | selected f, joining face g | restricted cut still joined (finding 13) |
| `FlapCovered` | moving f, covering g, point | a stationary face nearer on the turning side (finding 15) |
| `LineStopsInSelectedFace` | end, f | an end strictly inside a selected face |
| `NothingSelected` | — | empty selection and no existing hinge on the line |
| `ExistingHingeFlat` | edge | fold along an existing `F` edge, which `Flap` would refuse as `FlapNotHinge` |

### (e) The traditional crane, step by step

Steps are from https://origami.me/crane/, paraphrased.

Classes:

- **all** — a hinge through all layers;
- **top** — a hinge through some layers, by selector or seed;
- **existing** — a top hinge along a crease already there, so no new crease;
- **coupled** — several creases on different lines move together; not `Flap`;
- **whole** — the whole model moves (presentation).

Evidence: **S** = script on a fixture, **R** = classified by reading the text
and reasoning about geometry, not computed.

| # | Step (paraphrase) | Class | Ev. | Note |
| --- | --- | --- | --- | --- |
| 1 | fold and unfold both diagonals | all (one sheet) | R | fold then back to 0 is the precrease convention |
| 2 | turn over | whole | R | viewer side flips for later "top" selectors |
| 3 | fold and unfold both midlines | all | R | as 1 |
| 4 | collapse to square base | coupled | R | many creases at one vertex |
| 5 | top flaps' edges to centreline | top, n = 2 per flap, two seeds | S | finding 16; one layer is coupled |
| 6 | top corner down | all | S* | finding 17; *on the square base, kite flaps not modelled |
| 7 | unfold step 5 | top (reverse of 5) | R | angles back to 0 |
| 8 | petal fold (lift top layer) | coupled | R | text says top layer; still several creases |
| 9 | turn over | whole | R | |
| 10 | fold and unfold edges to centre | top | R | as 5, from −z |
| 11 | petal fold again | coupled | R | |
| 12 | edges to centreline, small gap | top | R | the "gap" is not an exact landmark (critic §3.4) |
| 13 | turn over | whole | R | |
| 14 | repeat 12 | top | R | |
| 15 | top right flap over to the left | existing (top) | R | see open question 3 |
| 16 | turn over | whole | R | |
| 17 | repeat 15 | existing (top) | R | |
| 18 | top flap's bottom corner up along existing horizontal crease | existing (top) | R | if that crease was unfolded as `F`, `Flap` refuses it |
| 19 | turn over | whole | R | |
| 20 | repeat 18 | existing (top) | R | |
| 21 | top right flap over to the left | existing (top) | R | |
| 22 | turn over | whole | R | |
| 23 | repeat 21 | existing (top) | R | |
| 24 | swivel fold for tail | coupled | R | |
| 25 | swivel fold, other side | coupled | R | |
| 26 | mountain fold head, crease, unfold | top (all layers of the neck flap, by seed) | R | |
| 27 | inside reverse fold head | coupled | R | reverses layers |
| 28 | open wings, shape body | coupled, paper not flat | R | the study's `CraneSpread` territory |

Counts: 6 whole-model, 7 coupled, 3 through all layers, 12 through some
layers. Of those 12, 7 hinge on an existing crease.

Two takeaways for the PRDs:

- The some-layers move plus turn-over covers most of a book.
- "Fold along an existing crease" must resolve to edge ids without drawing a
  crease. ThroughLayers refuses that case today as `NoPaperUnderTheLine`
  (`ThroughLayers.hs:129-132`).

## Open questions

1. When `TopLayers n` with n at least the stack depth covers every face, should
   the step be reported as "through all layers"? A diagram arrow may want to
   say so.
2. Should a selector's moving side be a material point, as E2 suggests for
   landmarks, or a folded point? A material point inside a layer that is not
   selected must be refused. A folded point is ambiguous in exactly the stacks
   this move is for.
3. Along the long axis y = 0 of `examples/bird-base.fold`:
   - the only edges lying on it are edges 8 and 9, both V at 180;
   - faces 12–15 straddle it (script);
   - a seed in face 0's leg pulls in faces 12 and 13 through edge 1–9.
   So on the plain bird base a book-turn about the axis is not an
   existing-crease hinge. Does crane step 15 apply to a state where it is?
   That needs the state after steps 12–14, which no fixture records.
4. Should `carryOrders` refuse or re-solve when a child pair overlaps but its
   parents had no order? I think refuse, because the input was already
   inconsistent.
5. Where should viewer side live after turn-over? It interacts with critic
   contradictions 1–2. A frame-level turn-over flips +z, but a presentation
   `Rigid` does not.

## Unverified

- Everything marked **(script)** comes from my Python re-implementation, not
  from senbazuru. It agrees with the repo at one tip position, and closes loops
  to 3e-13. Face ids match only because `crane.fold`, `quarter-fold.fold` and
  `square-base.fold` either record faces (crane, quarter) or were traced by my
  own tracer (square base, bird base). Senbazuru's tracer may number the traced
  fixtures' faces differently.
- The orders in findings 14–16 use only the solver's taco rule
  (`Stacking.hs:49-52`), not the solver. For the quarter fold and the square
  base's four faces the rule alone gives a total order. For the crane, wing B
  being on wing A's +z side is **inferred** from assertions at
  `CraneWingSpec.hs:52-54` and `:96-100`, which I read but did not run. A
  direct check would compare `solveStackingAs defaultBudget [2]` orders for
  pairs (0, 2), (4, 6), (1, 3), (5, 7) through `nearness`.
- That `Flap`'s endpoint check at progress 0 covers *every* touching
  stationary face, which finding 14 relies on, is my reading of
  `Flap.hs:303-312` and the note. It was not traced through `HingeSweep`.
- The crane table's R rows are not computed. The origami.me text was read
  through a fetch summariser, twice. The two summaries disagreed on step 6's
  layer wording: once "single layer", once nothing stated. Finding 17 computes
  "all layers" for the square base's top triangle.
- I did not check whether the crease-pattern renderer draws `U`/`F` lines, the
  cost of the extra faces in (b), or FOLD's rules for a `U` edge with a nonzero
  angle.
- `docs/notes/checked-square-collapse.md`, `petal-fold-motion.md` and
  `checked-petal.md` exist (`ls`). I did not read them, so the coupled rows cite
  no study evidence.
