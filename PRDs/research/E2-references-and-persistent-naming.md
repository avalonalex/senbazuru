# E2 — References and persistent naming: how a written fold says WHAT and WHERE

Research slice for the fold-sequence PRDs (embedded DSL, CLI sequence file,
material-study realistic rendering). No code was changed and nothing was built.
Dates: researched 2026-09-14.

## Summary

A step must name **what** paper moves and **where** the fold goes. Today
senbazuru uses raw ids (`EdgeId 8, FaceId 2` in `BlintzSequence`), angle lists
in edge order (`cases.json`) and typed coordinates (`crease --from 0,0 --to
1,1`). One name already persists: `StudyCase` resolves a panel from a
**material point** `at: [u, v]` on the unfolded sheet, surviving face
renumbering. The Huzita–Justin–Hatori axioms are the complete single-fold line
vocabulary. O3, O5, O6 and O7 can give zero, two or three answers, so a language
must require a disambiguator and refuse unless exactly one remains. CAD's
topological naming problem is the "front flap" problem. What maps onto
senbazuru is naming by **geometry in a fixed parameter domain**: unlike a CAD
solid, the sheet never gains or loses material. Viewer-relative selectors ("top
layer") and landmarks ("the crease from step 3") should resolve to material
references once and be pinned. Knitting agrees: address the product, not the
machine; keep a virtual machine that checks every step; use conservation as
the cheap check.

## Findings

### A. How senbazuru names paper and lines today

1. **Raw positional ids are the current recipe language, and they break
   without warning.** `BlintzSequence`'s recipe is a list of
   `(title, EdgeId, FaceId, travel)` tuples
   (`study/fold-material/BlintzSequence.hs:50-56`). Its header says the ids
   refer to the fixture *after cutting and tracing*, and to a face order that
   the module itself rearranged, putting the central diamond first
   (`BlintzSequence.hs:4-8`, reorder at `:44-47`). `HelmetSequence` does the same
   with lists of edges (`study/fold-material/HelmetSequence.hs:48-50`), and its
   `:42` refuses anything but the expected face-size signature. These ids stay
   correct only while the fixture file, the cutting code and the reordering stay
   unchanged. The module has to guard that with a shape check because the ids
   cannot guard it themselves. A newcomer will read `FaceId 2` as "a face of the
   file", but it means "a face of `foldedPattern` after this module reordered
   faces".

2. **Angle lists in `cases.json` are a whole state named by edge position.**
   Each step is a complete `angles` list in the source file's `edges_vertices`
   order, boundary edges included (`study/fold-material/README.md:330-339`,
   checked by length at `StudyCase.hs:152-154`). The bird case has 28 numbers
   per state (`study/fold-material/cases.json:219`), and `CheckedBird` builds
   the same thing as a positional Haskell list (`CheckedBird.hs:110-114`). Any
   edit to the source file that reorders edges silently changes what every
   number means. The header says why it was done: it keeps the study out of
   inferring a sequence from a picture (`StudyCase.hs:5-7`).

3. **Material-point names already exist, and the reason for them is written
   down.** Contact declarations name panels as `{"name": "lower-right", "at":
   [0.8, 0.1]}` (`cases.json:29-37`). `fixedPanel: [0.58, 0.4]` picks the
   panel held still (`cases.json:174`; field at `StudyCase.hs:69-70`). The
   resolver requires a finite point strictly inside **exactly one** material
   face, with a `1e-10` tolerance, and refuses otherwise
   (`StudyCase.hs:139-143`; fixed panel at `:165-170`). The header gives the
   motive: face renumbering during crease cutting cannot change what an order
   means (`StudyCase.hs:117-120`). The README adds that neither face
   numbering nor the camera can change which panel a rule names
   (`README.md:371-374`). Two stricter rules come with it. Every panel must be
   named exactly once (`StudyCase.hs:133-134`), and equal-area ties for the
   default anchor are broken lowest, then leftmost (`StudyCase.hs:242-248`).
   `docs/notes/crane-pocket-map.md` uses the same idea for regions: material
   quadrants, which it says survive face renumbering. The README's compass
   names (`south-west` = western triangle along the south edge,
   `README.md:427-429`) are human labels. The point is what the code resolves.

4. **The shared surface keys everything by material, not by where paper sits
   now.** `Origami.Surface` stores each vertex's original `V2` beside its current
   `V3` (`src/Senbazuru/Origami/Surface.hs:76-80`). It says vertex ids, never
   coincidence of folded coordinates, decide what is shared (`Surface.hs:1-4`,
   `:322-324`). `docs/notes/sharing-material-vertices.md` shows why with a
   command that was actually run: the quarter fold's four corners, material
   `(0,0)`, `(1,0)`, `(1,1)`, `(0,1)`, all land at folded `(1,0,0)`. **So a
   folded-space point can name four pieces of paper, and a material point
   always names one.** The surface's own layer requirements, however, are
   still `(FaceId, FaceId)` pairs, and they are validated only as indices in
   range (`Surface.hs:115-122`, `:306-312`). `StudyCase` translates names to
   ids at the edge of the study (`StudyCase.hs:125-127`).

5. **A flap is currently named by a hinge (edge ids) plus one face on the
   moving side, and the library works out the rest.** `prepareFlap :: EdgeId ->
   FaceId -> Double -> Folded` and `prepareFlapAlong :: [EdgeId] -> FaceId -> …`
   (`src/Senbazuru/Origami/Flap.hs:152-162`). The flap is the connected set of
   faces left after removing the hinge creases from the face graph
   (`Flap.hs:2-6`, computed at `:196-199`). The call is refused if the
   stationary face is reachable (`FlapCoupled`), if a hinge segment does not
   separate moving from still paper (`FlapNotBoundary`, `:209`), or if the
   segments are not collinear in the *current* folded shape
   (`FlapUnalignedCrease`, `:207-216`). Ids must come from the cut pattern
   (`Flap.hs:9-10`). **The line a newcomer will think is wrong:** a stationary
   face on an upside-down layer turns the same physical way with the opposite
   sign of FOLD angle (`Flap.hs:14-17`). The helmet recipe relies on this
   with two material creases on one hinge (`HelmetSequence.hs:4-6`). This is
   a good design for names: the *caller* supplies a small seed (hinge plus one
   point on the moving side), and the *operation* grows it into the unit it
   needs.

6. **Lines are named by coordinates, in one of two frames.** `creaseAlong ::
   V2 -> V2 -> Assignment -> Frame` (`src/Senbazuru/Fold/Creasing.hs:90`),
   exposed as `--from X,Y --to X,Y` (`app/Senbazuru/Cli.hs:266-277`). Each end
   must *meet something the drawing already has* (`Creasing.hs:40-47`), or
   it is refused as `CreaseEndMeetsNothing` (`:186-188`). With `--folded` the
   same two points are read on the folded model and every layer under the line
   is creased (`Cli.hs:278-284`; `creaseThroughLayers`,
   `src/Senbazuru/Origami/ThroughLayers.hs:227`). There, each face's piece of the
   line is mapped back to the sheet through that face's inverse placement
   (`ThroughLayers.hs:285-297`). The flat pattern stays authoritative
   (`ThroughLayers.hs:26-34`). About half the pieces come back as the *other*
   assignment because alternate layers lie face down (`:36-45`). Two limits are
   stated: it always creases **all** layers, and "only the near ones" is left to
   the vocabulary issue (`:56-61`). It also works on flat-folded models only
   (`:63-67`). Issue #97, read with `gh issue view 97`, names the gap
   directly: the CLI takes coordinates while a book says fold *corner to
   corner*.

7. **Any move that changes the pattern invalidates every id.** `creaseAllAlong`
   appends edges, sets `facesVertices = []`, `faceOrders = []`,
   `frameExtras = mempty`, and hands off to `withPlanarFaces`
   (`Creasing.hs:252-268`). Faces are re-traced and new edges are cut from old
   ones, so after one crease *no* stored `FaceId` is safe, and an `EdgeId` is
   safe only for edges no new line crossed. `docs/notes/crease-identity-through-refinement.md`
   records the same renumbering risk for bending controls. It also records
   the fix used there: carry a *source* edge id through subdivision and never
   match by coordinates.

8. **Typed decimals cannot land on landmarks.** Creasing judges "meets
   something" within the sheet's hair, a billionth of the model's size (see
   *Hair* in `docs/glossary.md`). A crease end meant to sit on a line at 1/3
   and typed as `0.333` is about `3.3e-4` away, far outside a `1e-9` hair. It
   is refused as meeting nothing, or it is snapped to the wrong feature. The
   CLI help text shows the parser already had to handle negative
   coordinates (`Cli.hs:291-297`). Exact references are a correctness need,
   not sugar.

### B. Huzita–Justin–Hatori: the vocabulary of fold lines

9. **The seven operations, what they take, and how many answers they give**
   (Wikipedia, https://en.wikipedia.org/wiki/Huzita%E2%80%93Hatori_axioms;
   Alperin & Lang, "One-, Two-, and Multi-Fold Origami Axioms", *Origami⁴*,
   read via https://langorigami.com/wp-content/uploads/2015/09/o4_multifold_axioms.pdf):

   | Op | Given | Fold that… | Solutions | No / degenerate |
   | --- | --- | --- | --- | --- |
   | O1 | points p1, p2 | passes through both | 1 | p1 = p2: every line through the point |
   | O2 | points p1, p2 | puts p1 on p2 (perpendicular bisector) | 1 | p1 = p2: infinite |
   | O3 | lines l1, l2 | puts l1 on l2 | 2 if they cross (two bisectors); 1 if parallel (midline) | l1 = l2: infinite |
   | O4 | point p, line l | is perpendicular to l through p | 1 | — |
   | O5 | points p1, p2, line l | puts p1 on l, through p2 | 0, 1 or 2 (circle about p2, radius \|p1p2\|, against l) | 0 when the circle misses l |
   | O6 | points p1, p2, lines l1, l2 | puts p1 on l1 and p2 on l2 | 0, 1, 2 or 3 (common tangents of two parabolas; solves cubics) | — |
   | O7 | point p, lines l1, l2 | puts p on l1, perpendicular to l2 | 1 in general | Wikipedia: none when l1 ∥ l2 |

   The degenerate cells for coincident inputs are my own reasoning, not a
   quoted source. Alperin and Lang assume the points and lines in each
   alignment pair are **distinct**, which is what excludes those cases. One
   more case follows by the same reasoning and is not stated in the sources:
   O7 with l1 ∥ l2 and p already on l1 has infinitely many answers, because any
   fold perpendicular to l2 keeps p on l1.

10. **Why seven is complete, and the two restrictions that matter to us.**
    Alperin and Lang define a one-fold axiom as a *minimal* set of alignments
    that fixes one fold line, *on a finite region* of the plane, *with a
    finite number of solutions*. They then list every pair of one-equation
    alignments (their Table 1) to show nothing is missing. They leave out
    "parallel to a given line" precisely because it can only be checked with
    infinite paper. Wikipedia and Lang's own page credit completeness to Lang
    (https://langorigami.com/article/huzita-justin-axioms/, © Lang). The same
    paper enumerates two-fold alignments: 489 distinct combinations with one
    alignment type included, 203 without. Lucero (arXiv 1610.09923,
    https://arxiv.org/abs/1610.09923) argues there are **eight** elementary
    operations: the seven plus *folding along a line that already exists*.
    Earlier lists omitted it because it creates no new line. That eighth is
    the most common instruction in real diagrams ("fold along the existing
    crease", Finding 13).

11. **History.** Justin listed seven operations in 1989. Huzita presented six
    at the same 1989 meeting. Hatori rediscovered the seventh in 2001 (Alperin
    & Lang, introduction); Lang's page gives Hatori's date as 2002. The repo
    note `docs/notes/huzita-hatori.md` has "Huzita 1991" and "Hatori 2001",
    so its dates should be checked against Alperin & Lang before a PRD cites
    them.

12. **How existing systems handle several answers or none.**
    - *Eos / Orikoto* (Ida et al.; Mathematica). The SYNASC 2021 tutorial
      notebook
      (https://www.wolframcloud.com/obj/ida.tetsuo.ge/Published/SYNASC%202021%20Tutorial%20published.nb)
      names corners A–D and has the system name new intersection points
      automatically when asked to mark them. For an O6 step in angle
      trisection it **shows all three candidate fold lines and the user picks
      one**. Its exercises ask for configurations with 0, 1 or 2 lines. By
      default a fold is a valley and the faces on the right of the fold line
      move. So *which side moves* is a convention tied to the line's
      direction, not a named flap.
    - *ReferenceFinder* (Lang). It searches short sequences of the seven
      operations that land a target point or line, and reports the five best by
      error and fold count (https://langorigami.com/article/referencefinder/).
      Licence: **GNU GPL version 2**, per that page.
      `docs/related-projects.md:36` currently says "GPL (not checked)" and can
      now say GPL-2.0.
    - *Beloch* (https://github.com/tophcodes/beloch, MIT, repo created
      2026-07-05, 1 star per the GitHub API). A declarative language on the
      seven operations that compiles to FOLD. Corners have dotted names,
      lines and creases have `--` names, and `as` binds a result for later
      steps. Its `flatten` statement solves for a crease no axiom gives and
      takes a `toward <point>` hint, apparently to choose between solutions.
      Its README says mountain/valley come from layer order. I read only the
      README, not the code, and the project is two months old.
    - *Foldinator* (Szinger, 2001,
      https://zingman.com/origami/foldinator3OSMEpaper.php). Fold lines snap to
      bisectors of pairs of edges or creases and to crease/edge
      intersections, which are landmarks, not coordinates. It supports valley,
      mountain and reverse folds; petal, squash, rabbit ear and sink were
      planned. The paper does not address choosing layers.

### C. How books refer to paper

13. **Diagram vocabulary.** A current crane diagram (https://origami.me/crane/,
    © Origami.me) names paper by: corners ("top corner"); edges ("left and
    right edges"); landmark lines ("vertical centerline", "the existing
    horizontal crease"); flaps and layers ("top flaps", "top right flap", "top
    layer"); body parts once they exist ("wings", "tail"); and whole-model
    moves ("turn the model over", "repeat on the right side"). Nearly every
    *where* is an alignment ("meet the centerline", "align with") or the
    eighth operation ("along the existing creases"). Nearly every *what* is
    relative to the viewer ("top", "right").

14. **Lang's diagramming advice deliberately swaps descriptions for labels.**
    Lang recommends **lettering flaps and points**. Instead of describing a
    point by its place in the picture, the text says *fold flap A to point C*.
    Words for location ("outer flap") should be kept apart from words for
    direction ("fold outward"). Hidden edges and arrows passing behind layers
    get x-ray lines
    (https://zenorig.blogspot.com/2012/09/origami-diagramming-conventions-robert.html).
    The Yoshizawa–Randlett page lists symbols for folds, repeats, reverse folds
    and turning over, and says nothing about a one-layer versus all-layers
    notation (https://en.wikipedia.org/wiki/Yoshizawa%E2%80%93Randlett_system).
    In books that distinction lives in the text and in how the arrows are
    drawn.

15. **"Flap" is not a polygon.** The glossary defines a flap as a liftable part
    that may hold several faces and layers (`docs/glossary.md`, *Flap*).
    `docs/notes/no-sequence-solver.md` says diagram steps are named macro-moves
    with no agreed formal definition. A reference language therefore cannot
    have "flap" as a primitive stored type. A flap exists only relative to a
    hinge and a state, which is exactly how `Flap.hs` computes it (Finding 5).

### D. The topological naming problem in CAD

16. **The problem, in CAD's words.** FreeCAD's own documentation
    (https://github.com/FreeCAD/FreeCAD-documentation/blob/main/wiki/Topological_naming_problem.md)
    gives the standard example: a sketch attached to `Face6` ends up on
    different geometry after an upstream edit renumbers faces. It describes
    FreeCAD 1.0's mitigation as three aims: **flag** a broken reference at the
    operation that broke it, **suggest** likely fixes, and **resolve
    automatically** only when confidence is high, mostly for parameter changes
    rather than structural ones. It says this reached parity with realthunder's
    original work in 1.0. The practical advice is still to attach to origin
    planes, datum planes and coordinate systems, not to generated faces.
    `docs/related-projects.md:85-98` already says a written fold hits this
    problem the moment it says "petal fold the front flap".

17. **History-based naming: Kripac 1997; E-REP / Capoyleas, Chen & Hoffmann
    1996.** Wang & Nnaji's survey (Computer-Aided Design 37 (2005) 1081–1093,
    read via https://msse.gatech.edu/publication/JCAD_PID_wang.pdf) describes
    Kripac's Topological ID System this way. A face's name is the modelling
    step that created it, an index within that step, and its surface type.
    Edges and vertices are named by their adjacent faces. A kept face history
    maps new entities to old ones after re-evaluation, and the survey counts
    the global graph matching this needs as a cost. It describes E-REP naming,
    citing Capoyleas, Chen & Hoffmann among its references, like this. A new
    entity is named from the old entity it was generated from, for example an
    extruded edge from the vertex swept to make it. Re-evaluation matches
    names by comparing local topological neighbourhoods, using orientation to
    break ties. Its opening example is a hole dimensioned to edge e1 whose
    reference *jumps* to e2 after a boolean re-evaluation. The survey's own
    proposal is IDs based on **continuity of geometry**, not construction
    history.

18. **realthunder's element maps (FreeCAD 1.0's lineage).** The algorithm wiki
    (https://github.com/realthunder/FreeCAD_assembly3/wiki/Topological-Naming-Algorithm)
    describes these steps. Names are carried from input to output through the
    geometry kernel's record of which inputs produced which outputs. An
    element with no such record is named from a named parent or from its
    named bounding elements. **When one input yields several outputs, an index
    is appended in the order the kernel reports them.** A broken reference is
    looked up by shared source tags. Names encode operation codes and owner
    tags, and are not meant to be read by people. Note the weak point: split
    disambiguation depends on the kernel's reporting order, which is the CAD
    version of senbazuru's face order after `withPlanarFaces`.

19. **Query-based references: Onshape, build123d, CadQuery.** Onshape's
    FeatureScript docs (https://cad.onshape.com/FsDoc/modeling.html) describe a
    query as a set of criteria, not a list of entities. It is evaluated
    against the current model so a reference such as "the top of the cube" can
    be found again after resizing and drilling. `qCreatedBy` selects geometry
    made by a given operation, `qContainsPoint` selects geometry touching a
    point, and `evaluateQuery` returns one transient query per match, so zero
    or several. build123d
    (https://build123d.readthedocs.io/en/latest/topology_selection.html)
    selects by operation history: `Select.LAST` means what the last operation
    brought in or created, and `Select.NEW` means what existed in no input.
    Results are refined with `filter_by`, `sort_by` and `group_by`. The page
    does not discuss ties, tolerances, or selectors changing meaning after
    upstream edits. CadQuery's string selectors
    (https://cadquery.readthedocs.io/en/latest/selectors.html) pick by
    direction (`>Z`, `|Z`, `#Z`), type (`%Plane`) and nth-along-an-axis
    (`>Y[1]`), combined with and/or/not. The page warns that for a non-planar
    face the test is made at its centre of mass, with surprising results. It
    does not say how ties are broken.

### E. Machine knitting as the analogous craft-to-machine language

20. **Knitout addresses the machine, not the fabric.** The spec
    (https://textiles-lab.github.io/knitout/knitout.html, maintained by Jim
    McCann; the page describes itself as public domain) is a header plus a flat
    list of operations. Needles are addressed by bed (`f`, `b`, and slider beds
    `fs`, `bs`) and index. **Racking** is machine state that changes which
    back needle lines up with a front needle. Yarn carriers are named. The
    interpreter tracks each carrier's position so it can insert "kickbacks"
    the author never wrote. Its stated goals are machine independence,
    staying low level with no abstraction, and making front-ends easy to
    write. The loops themselves, the actual product, are never named. They
    are implied by the history of operations on each needle.

21. **The compiler over it: McCann, Albaugh, Narayanan, Grow, Matusik, Mankoff,
    Hodgins, "A Compiler for 3D Machine Knitting", ACM TOG 35(4), SIGGRAPH
    2016** (authors and venue confirmed at
    https://publications.ri.cmu.edu/a-compiler-for-3d-machine-knitting and
    https://la.disneyresearch.com/publication/machine-knitting-compiler/). Users
    assemble high-level shape primitives, tubes and sheets, and the compiler
    turns them into needle-level instructions. At its core is a heuristic
    transfer-planning algorithm for knit cycles that the authors **prove sound
    and complete**. The abstract's point is that a change needing thousands of
    low-level edits becomes one high-level edit.

22. **Addressing the product instead: Narayanan, Wu, Yuksel, McCann, "Visual
    Knitting Machine Programming", SIGGRAPH 2019**
    (https://history.siggraph.org/learning/visual-knitting-machine-programming-by-narayanan-wu-yuksel-and-mccann/).
    Low-level operations are stored *per face* of an "augmented stitch mesh",
    with directed edge labels for dependencies. Edits keep the mesh knittable
    by construction. This is the knitting counterpart of addressing paper by
    material coordinates instead of by FOLD ids.

23. **A virtual machine that catches errors: Hofmann, Albaugh, Wang, Mankoff,
    Hudson, "KnitScript", UIST 2023**
    (https://make4all.org/portfolio/knitscript-a-domain-specific-scripting-language-for-advanced-machine-knitting/).
    It keeps a comprehensive virtual model of the knitting machine, automates
    tedious details, and describes direct machine-level programming as
    error-prone. A Northeastern news piece
    (https://www.khoury.northeastern.edu/the-programming-behind-machine-powered-knitting-is-getting-a-much-needed-rewrite/,
    2024-01-17) quotes Hofmann saying the barrier fell from months of machine
    training to a few practice problems.

24. **Hand notation checked by conservation: KnitSpeak.** Stitch Maps' guide
    (https://stitch-maps.com/about/knitspeak/, © Stitch Maps) describes its
    knitspeak dialect. Rows are numbered with RS/WS marks. Horizontal repeats
    are `*…, repeat from *`. `knit`/`purl` mean "as many as possible". A
    stitch is addressed implicitly, as the next unconsumed stitch of the
    previous row. The checker enforces **exact stitch-count agreement between
    consecutive rows** (short rows excepted). It rejects unknown
    abbreviations, more than one variable-width section per row, and
    shorthand such as "all other WS rows": every row number must be spelled
    out. KnitPicking (Hofmann, Albaugh, Sethapakadi, Hodgins, Hudson, McCann,
    Mankoff, UIST 2019; abstract via
    https://api.semanticscholar.org/graph/v1/paper/DOI:10.1145/3332165.3347886)
    turns hand-knitting texture patterns into KnitGraphs that can be output
    as machine or hand instructions, with a corpus of 472 textures.

## Implications for the design

### What CAD teaches, mapped onto senbazuru

- **Senbazuru has what CAD lacks: a fixed parameter domain.** A CAD solid's
  faces are created and destroyed by booleans, so a name has to be a story
  about history (Kripac, E-REP, element maps). Rigid folding never adds or
  removes paper. Every point of every state has the same material coordinate
  it had on the flat sheet (`Surface.hs:76-80`; the quarter-fold table in
  `docs/notes/sharing-material-vertices.md`). The sheet is the datum plane
  FreeCAD tells users to attach to (Finding 16), and it is geometry-based
  naming in Wang & Nnaji's sense without their continuity machinery. **The
  PRDs should make material references the stored, canonical form of every
  "what" reference**, and treat every other form as sugar resolved to it.
  One exception to flag: `Cut` edges and paper that is really cut would break
  the one-sheet assumption, and today the surface refuses joined cuts
  (`Surface.hs:342`).
- **Never store `FaceId`/`EdgeId` across a step.** Finding 7 shows every
  pattern-changing move re-numbers. Ids are resolution *outputs* used inside
  one step, as `StudyCase` already does (`StudyCase.hs:125-137`). The
  surface's `layerRequirements :: (FaceId, FaceId)` (`Surface.hs:121`) is
  fine *inside* a state and must not appear in a sequence file.
- **Selectors (Onshape, build123d, CadQuery) are the right model for
  viewer-relative words, but only if pinned.** A query re-run after an
  upstream edit can quietly select something else (Findings 17 and 19; the
  build123d page does not even warn about it). Rule: a viewer-relative
  selector resolves **once**, at the step where it is written, to material
  references. The evaluator records that result (in a trace or in the
  step's FOLD `frame_*` metadata). On replay it re-resolves and **refuses if
  the result differs**, naming both. This is FreeCAD 1.0's aim 1: flag at the
  operation that broke. It fits the `Explain` convention: say which step,
  which words, what each resolution was.
- **Split disambiguation must not depend on computation order.** realthunder
  appends indices in kernel-report order (Finding 18). Senbazuru's equivalent
  would be `withPlanarFaces`'s trace order. Material points avoid the
  problem: a point picks one piece of a split panel by *where it is*.

### A small reference vocabulary, with resolution rules and refusals

All points below are in **material coordinates** unless marked *folded*. The
evaluator resolves against the state *before* the step. Every refusal carries
the step label, the reference text, and the candidates found.

1. **Material point `@(u, v)`: names paper, one location.**
   - *As a region (panel):* resolve to the unique face whose material ring
     contains the point strictly inside, within a tolerance relative to the
     sheet (a hair, not `StudyCase`'s absolute `1e-10`). **Refuse** if it is on
     a crease or corner (several faces), as `StudyCase.hs:141-143` already does,
     or if it is off the sheet.
   - *As a flap seed:* resolve the face, then grow the flap as `Flap.hs`
     does: the component on the moving side once the hinge is removed.
     **Refuse** with `FlapCoupled`/`FlapNotBoundary` (`Flap.hs:196-216`).
     **Flap names survive later splits; panel names do not.** If a later
     crease splits the kite's `lower-right` panel, `@(0.8, 0.1)` still grows to
     the same flap, but as a panel name it now means only one piece. Anything
     stored *per panel*, like `StudyCase`'s "every panel named exactly once"
     (`StudyCase.hs:133-134`), must be re-checked after every
     pattern-changing step. The PRD should say which operations take regions
     and which take flaps.
   - *As a vertex:* a point within a hair of a material vertex resolves to
     that vertex. Needed for "corner", "centre". The square base's centre
     `(0.5, 0.5)` is on eight faces (`docs/notes/precreases-and-target-states.md`)
     and is a valid *vertex* name but an invalid *region* name. A point near
     but not within a hair of a vertex is refused, listing the nearest
     vertex, so a typed `0.333` cannot pass as `1/3` (Finding 8).
2. **Material segment `@(u1,v1)–@(u2,v2)`: names a crease or a hinge.**
   Resolve to every current edge whose material segment lies on that line and
   overlaps it. The edge set, not one id, is the name, so it survives cutting
   (Finding 7) and matches how `crease-identity-through-refinement.md` carries
   source identity. **Refuse** if no edge lies along it, or if the covered
   edges leave a gap when a hinge was required.
3. **Landmark from a prior step: `step3.crease`, `step3.point "p"`.**
   `Select.LAST`/`NEW` and `qCreatedBy` (Finding 19), and Beloch's `as` and
   Lang's letters (Findings 12 and 14). Stored as the **material geometry**
   the step produced (a segment or point), never as ids. Resolution goes
   through rule 1 or 2. This keeps landmarks exact: an intersection of two
   creases is carried as a computed point, not retyped. **Refuse** a
   landmark that later steps have made ambiguous, such as a point whose
   material location a new crease now passes through when used as a region.
   Landmark names must be unique within a sequence, and shadowing is refused.
4. **Construction `O1…O7` and `along <line>` (Lucero's eighth).** Inputs are
   points and lines from rules 1–3, or sheet features (edges, corners). The
   result is a line in the *frame of the state*. On the flat sheet it is
   material. On a flat-folded state it is in folded coordinates and handed to
   `creaseThroughLayers` (`ThroughLayers.hs:227`), which already refuses
   non-flat states (`:63-67`). **Resolution rule:** compute all real
   solutions. Discard any whose line does not cross paper, and *report* them
   as "off the paper" rather than silently dropping them, because Alperin &
   Lang's finite-region condition is about exactly this. Then apply the
   disambiguator. **Accept only if exactly one remains.** O1, O2 and O4 need
   no disambiguator. O3 (crossing lines), O5, O6 and O7 *require* one when the
   count is above one. Disambiguators are themselves references: `nearest
   @p` (Beloch's `toward`), `through side of @q`, or `the one moving @p1
   across @line`. **Refuse** 0 solutions, coincident inputs (infinitely many
   answers), and a disambiguator that leaves 0 or ≥2, listing every candidate
   line. Eos's interactive "show all three and pick" is the CLI's error
   message, and the DSL's `Left`. The "which side moves" convention must be an
   explicit flap seed, not Eos's right-of-direction default, because
   reversing a line's endpoints must not reverse a fold.
5. **Viewer-relative selectors: `top layer`, `front flap`, `the flap on the
   left`, `all layers`, `one layer`.** Resolve against a view (`fromAbove` or
   a camera) and the state's **pinned** layer order, using the machinery
   `Origami.Visible.nearness` already has (`Visible.hs:240-270`). Rules:
   - `top layer at <folded point>`: the faces covering the point, ordered by
     `nearness`, and the first one chosen. **Refuse** if the state has no
     recorded order for an overlapping pair. A model usually has several
     valid stackings (AGENTS.md, *several valid layer orders*), so a
     re-solved order could flip the answer. The step must use the order
     already accepted for the state, as the chained recipes do
     (`docs/notes/chaining-checked-folds.md`).
   - `one layer` / `the top n layers` along a line: the faces under the line
     above a depth. **ThroughLayers does not offer this today**
     (`ThroughLayers.hs:56-61`), so it is new library work, and the PRD
     should say so rather than presume it.
   - `left`/`right`/`front`: order candidate flaps by a direction in *view*
     space. **Refuse ties** within a tolerance, which CadQuery and build123d
     leave undocumented (Finding 19).
   - Every viewer selector is **resolved once and pinned** (see above). The
     output records the material reference so a reader of the FOLD file needs
     no camera.
6. **Symmetry: `repeat on the other side`, `repeat behind`.** Express as a
   named isometry of the *material square* (reflection across a diagonal,
   rotation by 90°) applied to every reference in a step, then resolved
   normally. **Refuse** if a mapped reference fails to resolve. Do not assume
   the current state is symmetric: the bird's first petal breaks the square
   base's symmetry (`cases.json:173`, description). Whether a material
   reflection keeps mountain/valley as written is an open question below.

### What knitting says the evaluator should be

- **Address the product, not the machine** (Findings 20 and 22). FOLD ids are
  needle indices. Material coordinates are the stitch mesh. The file language
  should never expose ids.
- **Keep a virtual machine and check every step** (Finding 23).
  `Folded` + `Surface` + the accepted layer order is that state. The checked
  `Flap` path (`Flap.hs:19-24`) is already the pattern to copy, and the
  sequence evaluator is a `foldM` over steps that refuses at the first bad
  one.
- **Conservation is the cheapest validator** (Finding 24). KnitSpeak checks
  stitch counts row to row. The study already checks one unit of area and
  convex panels on every pose (`StudyCase.hs:158-160`), and the flap path
  checks lengths. A sequence file should get these checks for free from
  the evaluator, not per recipe.
- **Refuse shorthand the checker cannot expand** (Finding 24: "all other WS
  rows" is rejected). "Repeat on all four flaps" should expand to four
  resolved steps, each checked, or be refused.
- **Higher-level primitives with proofs, compiled to low-level state**
  (Finding 21). Macro-moves (petal, rabbit ear) should compile to crease-angle
  paths that go through the existing checked operations, not to new geometry.

### Things to avoid

- Positional angle lists as a public format (Finding 2). Fine as the study's
  internal output, wrong as input a person writes.
- Decimal coordinates where a landmark is meant (Finding 8).
- Storing any id, or any selector result that has not been pinned, in a
  sequence file.
- Silently choosing among axiom solutions, or silently dropping off-paper
  ones.

## Open questions

1. **Region or flap?** Should the language have one "paper" reference whose
   meaning each operation picks (a flap for `fold`, a panel for layer
   constraints), or two distinct types? Two types make the split failure in
   rule 1 a type error in the DSL. The CLI would need two spellings.
2. **Where does a pinned resolution live?** In a trace file next to the
   sequence, in each FOLD frame's `frame_*` metadata (which
   `buildCaseSequence` currently fills without extras,
   `StudyCase.hs:215-226`), or in a `senbazuru:` vendor key, which the
   *preserve at the boundary* rule would then drop on transform?
3. **Tolerance for material points.** `StudyCase` uses an absolute `1e-10`
   (`StudyCase.hs:141`). Creasing and ThroughLayers use the sheet-relative
   hair. A reference language should use one. Does a `.cp` on a 400-unit
   square change which authored points resolve?
4. **Does a material reflection keep mountain and valley?** A reflection
   *within* the sheet's plane keeps the front face in front, so it should.
   "Repeat behind" is a half-turn of the *folded* model and may map to a
   different material isometry, or to none. This needs checking on the
   waterbomb and bird fixtures before rule 6 is written.
5. **Which frame do axioms run in on a folded state?** For flat-folded states,
   folded 2D coordinates are unambiguous. For states with paper in the air
   (every `cases.json` intermediate), the axioms have no plane. Refuse, or
   allow constructions only on named panels' planes?
6. **Is Lucero's "fold along an existing line" separate from `Flap`?** It
   adds no crease; it is a hinge motion on an existing material segment.
   Probably the same operation as `prepareFlapAlong` with the segment
   resolved by rule 2.
7. **Symmetric ties in viewer selectors.** A square base seen from above has
   flaps exactly left and right of centre. Refuse, or require the author to
   write a material point? The KnitSpeak precedent says refuse.
8. **#97's own dates and licence cells.** `docs/notes/huzita-hatori.md` and
   `docs/related-projects.md:36` should be checked against Finding 11 and
   ReferenceFinder's stated GPL-2.0.

## Unverified

- **Kripac's and Capoyleas–Chen–Hoffmann's original papers were not read.**
  Their content above comes only from Wang & Nnaji's 2005 survey. Bibliographic
  details (Kripac, *Computer-Aided Design* 29(2), 1997, pp. 113–122;
  Capoyleas, Chen & Hoffmann, *CAD* 28(1), 1996, pp. 17–26) come from search
  results. ScienceDirect and Semantic Scholar pages returned 403, empty pages
  or 429.
- **Onshape "historical versus state-based" queries**: only a search-result
  summary. The fetched modeling page did not use those terms. Onshape's
  handling of zero or several matches beyond `evaluateQuery` returning a
  list is not confirmed.
- **FreeCAD 1.0 dates** (mitigation enabled in weekly builds in May 2024,
  Ondsel 2024.3): search results only. The Ondsel blog returned 403 and the
  FreeCAD wiki returned an anti-bot page.
- **Rabbit Ear's axiom functions** (said to fail either as out of bounds or as
  not constructible, and to return up to three lines): search snippet only.
  `rabbitear.org` did not resolve. GPL-3.0; ideas only in any case.
- **ReferenceFinder's instruction wording** (how it phrases "fold A to B") was
  not seen; only its purpose, ranking and licence were.
- **KnitSpeak compiler inside KnitPicking**: the fetched abstract does not
  mention KnitSpeak, and the full paper PDF was too large to fetch. That
  KnitPicking reads KnitSpeak comes from search summaries.
- **Beloch** claims come from its README as summarised by the fetch tool. The
  exact role of `toward` (choosing among solutions versus a direction for
  `flatten`) is my reading, not confirmed from code.
- **Knitout version number** (0.6) is the fetched page's self-description as
  summarised, not read directly.
- **Eos** behaviour comes from one 2021 tutorial notebook, not the system or its
  papers. How Eos names layers or selects faces beyond "right of the fold line
  moves by default" was not found.
- The **degenerate-case cells** in Finding 9 (coincident inputs, O7 with p on
  l1) are my derivations, consistent with Alperin & Lang's distinctness
  assumption but not quoted from any source.
