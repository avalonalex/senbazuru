# E1 — Prior art: folding sequences written as text or programs

Researcher slice: each system's move vocabulary and reference vocabulary.
Everything under "Findings" was read on 2026-09-14 at the URL or file:line
given. Anything not read directly is under "Unverified".

## Summary

Systems that write origami sequences down handle three separate concerns:

- **where** a fold line goes (references),
- **which paper** moves (move semantics),
- **how the step is drawn** (arrows and captions).

None of them handles all three well.

- **Doodle** (2001, GPLv2) names points symbolically and has a full set of arrows, but computes no folding.
- **Eos** (Mathematica) has rigorous axiom-based references and proofs, but nothing at the scale of a whole model.
- **Foldinator** (a 2001 paper) joined snap-to references to three real moves; only the paper survives.
- **origami-diagrams** stores arrows and captions as data under `re:` keys.
- **Akitaya, Mitani, Kanamori & Fukui** recognised reverse, squash, petal and rabbit-ear folds as rewrites of a crease pattern, working backwards from the folded model.

All four 2026 papers exist and broadly match the repo's descriptions, but their action spaces are narrower than the repo suggests:

- OrigamiBench's action adds a crease to a crease pattern; nothing moves.
- FoldingAgent has five primitives, and its only folds are simple ones.
- COrigami produces crease patterns, not sequences.
- Learn2Fold never lists its operations in the text I read.

Every one of them refers to paper by vertex or edge index, or by coordinates. None has a robust name for a flap.

Senbazuru's `Flap`/`HingeSweep` checks the whole path of a motion, which is stronger than anything the papers check. The PRDs should use:

- named, constructed landmarks that resolve to positions on the original sheet;
- a rule for which side of the line moves, with layer selection written out;
- macro-moves compiled to coupled rigid motions;
- arrows derived from the frames, with optional overrides.

## Findings

### A. Languages and programs for diagrams

**1. Doodle is a diagram language with names instead of coordinates, and no folding in it.**
- *Provenance.* The about page names the authors as J. Gout, X. Fouchet and V. Osele; the command is `doodle [-f format] [-o file] file.doo`, and the default output is PostScript (https://doodle.sourceforge.net/about.html). Reference manual v2.1 is by Jérôme Gout, October 2001 (https://doodle.sourceforge.net/manual/index.html).
- *Licence.* The SourceForge project page lists **GPLv2** (https://sourceforge.net/projects/doodle/). `docs/related-projects.md:38` says "not checked". It should say GPLv2, which means ideas only.
- *File shape.* A file is a header block followed by a sequence of step blocks (manual `node3.html`). Only two operators open blocks, `\diagram_header { }` and `\step { }`. Every other operator starts with a backslash and ends with a semicolon (`node5.html`, `node13.html`).
- *What a step is.* A step inherits every point and edge defined before it. Valley and mountain lines from the previous step are automatically demoted to the plain-crease style. At the end of each block a figure is emitted (`node15.html`, `node10.html`). An explicit line operator overrides the automatic demotion (`node10.html`).
- *References.*
  - The manual's stated design: the user works with names, not coordinates (`node2.html`).
  - The vertex store is a global dictionary from names to coordinates, and a vertex, once defined, is never removed (`node7.html`).
  - Generic constructions: corners named by `\square`/`\diamond`, plus `\middle`, `\fraction(a,b,num,den)`, `\intersection`, `\perpendicular`, `\parallel` and `\symmetry` (`node33`–`node45`).
  - Origami-specific constructions compute the ends of a fold line:
    - `\point_to_point` takes a moving vertex, a destination vertex, and the two edges the fold line must end on (`node42`).
    - `\point_to_line` takes an optional argument choosing which of the two geometric solutions to use (`node41`).
    - `\line_to_line` handles the bisector cases (`node36`).
    - `\rabbit_ear` takes three triangle vertices, the first being the one you grab, and returns the endpoints of the fourth, reversed crease (`node43`).
- *Moves.*
  - The line operators `\valley_fold`, `\mountain_fold`, `\fold` (an existing crease), `\xray_fold`, `\border` and `\cut` only **draw** (`node47`–`node53`).
  - Paper is moved by hand. `\move(p, [a,b])` reflects a single named point across a line; the author cuts the edges, restyles the fold line as a border and fills in the back faces (`node38`, `node34`).
  - Whole-model operators: `\rotate(deg)`, and `\turn_over_horizontal`/`\turn_over_vertical`, which mirror every stored coordinate (`node60`–`node63`).
  - `\shift` nudges a point's drawn position by millimetres, to fake the offset between layers (`node44`).
- *Arrows and captions.*
  - `\simple_arrow` draws an arc from a source vertex either to a destination vertex or to the source's mirror image across a fold line, with head types such as valley, mountain and unfold (`node58`).
  - The other arrows are `\return_arrow`, `\push_arrow` (vertex, absolute angle, distance), `\open_arrow` (edge and side), and `\repeat_arrow` taking step labels (`node54`–`node59`).
  - Captions are `\caption("…")`; steps are cross-referenced with `\label`/`\ref` (`node87`–`node89`).
  - `\define` creates new operators and `\include` pulls in files (`node100`).
- *Validity.* None, by design. The about page says the compiler checks neither feasibility nor coherence. The manual says Doodle never works out where layers go after a fold (`node10`).
- *Sample.* Written for this note from the operator signatures in the manual, not copied and not compiled:

  ```
  \step {
    \square(a, b, c, d);
    ab = \middle(a, b);  cd = \middle(d, c);
    \valley_fold(ab, cd);                            % draws a dashed line, nothing more
    \simple_arrow(b, [ab, cd], none, valley, right); % arc to b's mirror image
    \caption("Fold in half.");
  }
  \step {
    \cut([a, b], ab);  \cut([d, c], cd);
    \move(b, [ab, cd]);  \move(c, [ab, cd]);         % the author moves each point
    \border(ab, cd);
  }
  ```
- *Newcomer trap.* Doodle reads like a folding language, but the second step above is the author doing the fold's geometry point by point. Forget one `\move` and you get a picture of paper that does not exist, and the compiler says nothing.

**2. Eos gives each axiom named arguments and proves things about the result.**
- *Source.* Ida & Watt, *Origami Folds in Higher-dimension* (2017), https://cs.uwaterloo.ca/~smwatt/pub/reprints/2017-scss-ndorigami.pdf.
- *The operations.* Pages 4–5 state the Huzita–Justin set, which they call HO. It has seven operations, O1–O7. Each is written with named points `P, Q` and named lines `m, n` that must lie on the faces, and each produces a fold line.
- *Folding model.* The origami is abstract: a set of faces with two relations between them, "superposes" and "adjacent" (p. 4). A fold means choosing a line and turning one half-plane by ±π, and the paper leaves the choice of half-plane and direction to the designer (p. 8). For a reader new to geometry: "half-plane" means everything on one side of the line.
- *Axioms can have several answers, or none.* Table 1 (p. 6) gives how many fold lines each operation can have:

  | Operation | Fold lines |
  | --- | --- |
  | O3 | 1–2 |
  | O4 | 1 |
  | O5 | 0–2 |
  | O6 | 0–3 |
  | O7 | 0–1 |

- *What a step looks like.* In the angle-trisection example (p. 6), each step is an operation with named arguments, of the form "(O4) with m = AD and P = F". Step 4 explicitly picks the third of O6's three solutions.
- *Proof.* Eos proves the construction correct using Gröbner bases, a computer-algebra method for polynomial equations, here over rational functions (pp. 6–8).
- *Orikoto and the tutorial.* `docs/related-projects.md:37` describes the logic-based specification. The SYNASC 2021 tutorial notebook (https://www.wolframcloud.com/obj/ida.tetsuo.ge/Published/slide-for-SYNASC%202021%20Tutorial.nb) was fetched; its raw page contains the identifiers `EosSession`, `Unfold` and `Mark`.
- *Licence.* Needs Mathematica; the licence was not checked.
- *What it lacks.* Nothing selects a flap beyond choosing a half-plane, and there is no arrow or diagram output.

**3. Foldinator joined references to real moves, and stopped short of complex folds.**
- *Source.* https://zingman.com/origami/foldinator3OSMEpaper.php. Paper only.
- *Data model.* A `Paper` starts as a two-sided, zero-thickness square. Each fold splits a polygon into two joined by a hinged edge, and later folds spread through several layers automatically. A `Scene` is the paper plus its symbols and text; a `Sequence` is the scenes plus metadata. Sequences were saved as a text file referencing BMP or JPG renders.
- *Moves.* Valley, mountain and reverse folds are implemented. Petal, squash, rabbit ear and sink were planned, and the author argues most of them can be done as sequences of simpler folds.
- *References.* The user drags a fold line with snap-to on by default. It snaps to:
  - the bisector of two edges, of an edge and a crease, or of two creases;
  - the intersection of two creases, or of a crease and an edge;
  - where a point on a flap should land.
- *Which side moves.* Whichever side of the line the mouse is on. The arrow type can be Fold, Unfold, or Fold and Unfold, and clicking "Next" animates the step.
- *Views.* Rotate, Flip and Zoom tools. A section view shows the layers in cross-section, and aligned layers are deliberately drawn offset so the figure can be read.
- *Validity.* The author believes his constraints stop the paper passing through itself, but says this is not proven.
- *Deferred.* Curvature, thickness and large models.
- *Newcomer trap.* "Most complex folds are sequences of simple folds" holds at the level of *which creases exist*, but not at the level of *motion*. A petal cannot be performed as a series of single-hinge turns of rigid panels; see finding 17.

**4. origami-diagrams stores arrows, lines and captions as data in vendor keys.**
- *Repository and licence.* `gh api repos/mayakraft/origami-diagrams` resolves to `amkraft/origami-diagrams`, and GitHub detects no licence file. Its `package.json` declares `"license": "MIT"`. It was last pushed in 2019.
- *Layout.* According to the readme:
  - The top level holds only `file_` keys, and `file_frames` is the ordered list of steps.
  - Each step frame has `frame_classes: ["diagrams"]` and an array `re:diagrams`. It is an array because one printed figure can hold several instructions.
  - Each entry holds `re:diagram_lines` (endpoint coordinates plus classes such as valley) and `re:diagram_arrows` (start and end coordinates plus classes).
  - Each entry also holds `re:diagram_instructions`, keyed by ISO language code, and `re:diagram_step`, a string.
- *An open question the readme records itself.* Should a frame count as a step because of `frame_classes`, or because the key is present?
- *Validity.* None; the arrows are whatever was typed in.

**5. Rabbit Ear's axioms return lists of answers, and its fold works on the crease pattern.**
- *Repository and licence.* `robbykraft/Origami` redirects to `rabbit-ear/rabbit-ear`, which is **GPL-3.0** (GitHub API). Only doc-comment lines and export names were read, for ideas.
- *Axioms.* `src/axioms/axioms.js` exports `axiom1` to `axiom7`, a parallel family of variants that express a line as a normal vector and a distance, and a dispatching `axiom`. The doc comments say each returns an *array* of solution lines; axiom 3 returns up to two (https://github.com/rabbit-ear/rabbit-ear/blob/main/src/axioms/axioms.js, lines 47–129).
- *Folding.*
  - `src/graph/fold/flatFold.js` is documented as putting a crease through the entire model, given a 2D line and an M/V/F assignment (lines ~196–207).
  - `foldGraph.js` creases a line, ray or segment through a *folded* model. It takes an assignment (default V), an optional fold angle and folded coordinates, and edits the graph in crease-pattern form (lines 69–89).
- *Other modules.* `src/diagrams/axiomArrows.js` and `src/graph/flaps.js` exist. Only their file names were read.
- *Why it matters.* The shape agrees with `Senbazuru.Origami.ThroughLayers`: work out the line on the folded model, then crease the flat sheet (`ThroughLayers.hs:26-34`).

### B. From a crease pattern back to steps

**6. ORIPA and Oriedita estimate a folded endpoint and have no idea of steps.**
- *ORIPA.* GPL, first released 2005; it calculates the folded shape of a flat-foldable crease pattern (https://mitani.cs.tsukuba.ac.jp/oripa/). The GitHub API reports `oripa/oripa` as GPL-3.0.
- *Oriedita.* Its `LICENSE.md` is the MIT text. The GitHub API reports NOASSERTION only because it does not recognise the file. It simulates folding, checks vertices with the extended Fushimi theorem, and shows the folded version (https://github.com/oriedita/oriedita).
- *No steps.* Neither page mentions sequences. Senbazuru already computes endpoints in `Origami.Stacking` (`docs/related-projects.md:25-26`).

**7. Akitaya et al. defined each named move by what it leaves on the crease pattern, and ran it backwards.**
- *Source.* Tsukuba CS seminar paper, 2012-11-06, advisors Mitani, Kanamori and Fukui (https://www.cgg.cs.tsukuba.ac.jp/~akitaya/CSSeminarAkitaya.pdf, 4 pp.).
- *Prior attempt.* An earlier 5OSME method applied 10 hand-picked manoeuvres heuristically, and only to patterns made of rabbit-ear molecules.
- *The graph.* The crease pattern is a graph. Each vertex keeps its creases in angular order, and each crease is marked M or V.
- *Moves as rewrite rules.* Each named manoeuvre is a graph-rewriting rule `S → S′`: a small subgraph pattern and what it becomes. The method starts from the folded model's crease pattern and applies the rules in reverse, towards the blank square.
- *Why multi-layer folds are awkward.* A simple fold through several layers adds "reflection creases": pairs of creases sharing a vertex that mirror each other, with a crease bisecting them and opposite M/V. A complete chain of these can be removed without breaking local flat-foldability.
- *The step graph.* All the ways of matching rules form a directed step-sequence graph. Every path from the blank square to the finished pattern is a valid sequence.
- *Coverage.* Inside reverse, outside reverse, squash and petal, together with simple folds (and rabbit ears in the fish-base figure), were enough for most traditional models.
- *Cost.*

  | Example | Nodes | Arcs | Time |
  | --- | --- | --- | --- |
  | Crane | 41 | 75 | 451 ms |
  | Frog base | 22,665 | 73,204 | ~1,780 s |

- *Implementation.* Input is an ORIPA file. Pattern matching is brute-force subgraph isomorphism. The animation holds each face's angular velocity constant and, for moves that are not rigidly foldable, lets the faces distort. Global self-intersection is left unsolved.
- *Descendants.* Creasy (https://github.com/xkevio/Creasy, **GPL-3.0**, Java) implements the method. OrigamiBench built its one-step dataset with Creasy (arXiv 2603.13856 HTML, appendix).

**8. Tachi's simulators and Origami Simulator have fold controls and no step language.**
- *Tachi's software.* Rigid Origami Simulator reads `.opx`/`.dxf` crease patterns. Freeform Origami reads `.obj` and has drag tools, constraints and a fold/unfold key. Both are for non-commercial use only, and users must cite them (https://tsg.ne.jp/TT/software/).
- *Tachi's method.* The research index describes rigid kinematics of general crease patterns, computed by projecting motion onto what the constraints allow (https://origami.c.u-tokyo.ac.jp/~tachi/cg/).
- *Origami Simulator (MIT).*
  - It reads `edges_assignment` and `edges_foldAngle` through the FOLD API, folds every crease at once, and exports FOLD, STL and OBJ.
  - Its slider runs from −100% to 100%, and the negative half swaps mountains and valleys.
  - It is a compliant bar-and-hinge model computed on the GPU: creases are springs rather than exact hinges (https://github.com/amandaghassaei/OrigamiSimulator).
- *What this means.* A single global fold percentage is a collapse, not a sequence.

### C. The container: FOLD

**9. FOLD records states. Steps are array order, and inheritance is only reuse.**
- *What the spec says* (https://raw.githubusercontent.com/edemaine/FOLD/main/doc/spec.md):
  - `file_classes` includes `"diagrams"`, a sequence of frames representing folding steps (line 106), and `"animation"` (line 104).
  - `file_frames[i]` is frame `i+1` (lines 409–412).
  - `frame_parent` (line 418) and `frame_inherit` (line 422) make a child frame inherit any properties it leaves unset.
  - Custom keys use `namespace:key`.
  - `edges_foldAngle` is positive for valleys and negative for mountains.
- *What senbazuru does.*
  - It decodes `frameParent`/`frameInherit` but does not resolve inheritance (`src/Senbazuru/Fold/Types.hs:150-153`; `docs/fold-reference.md:59-63`).
  - It records that FOLD has no transitions (`docs/fold-reference.md:196-198`).
  - It works out a step by subtracting positions rather than angles (`src/Senbazuru/Origami/Step.hs:10-15, 30-34`).
  - `frameTitle` is decoded (`Types.hs:143`) and #94 plans to draw it as the caption.
  - The study already writes `file_classes: ["diagrams"]` with a title per frame (`study/fold-material/BlintzSequence.hs:97-99`, `HelmetSequence.hs:94-96`).

### D. The 2026 papers

**10. All four IDs resolve, and the descriptions mostly match.** Each was checked on its arXiv abstract page and HTML full text.

| ID | Title (abridged) | First author · v1 date | Matches `related-projects.md:115-124` / #96? |
| --- | --- | --- | --- |
| 2603.13856 | *OrigamiBench: An Interactive Environment to Synthesize Flat-Foldable Origamis* | Agarwal · 14 Mar 2026 | Mostly; see 11: the action is *adding a crease*, not a fold |
| 2603.29585 | *Learn2Fold: Structured Origami Generation with World Model Planning* | Huang · **2 Feb 2026** (v2 2 Apr) | Yes. The v1 date predates the `2603` prefix; reported as shown |
| 2606.26299 | *COrigami: An AI Pipeline for Co-Designing Flat-Foldable Visually Recognisable Origami* | Zahavy (Robert J. Lang among the authors) · 24 Jun 2026 | Yes: text to crease pattern, no sequences |
| 2609.00377 | *FoldingAgent: Inferring Parametric Origami Procedures from Demonstration Videos* | Moriya · 31 Aug 2026 | Yes |

Issue #96 says "three papers built one [a vocabulary] anyway" and then lists four, one of which (COrigami) does not.

**11. OrigamiBench.** Source: https://arxiv.org/html/2603.13856, HTML text.
- *The action.* The main text defines it as `add_crease` with two **vertex indices** and an assignment in {M, V}. The prompt in the appendix instead asks for `p1`/`p2` **coordinates** on a square from (0, 0) to (10, 10). It also allows `add_creases` batches, but only when a single crease would break flat-foldability or a symmetric structure needs several at once.
- *Checks.* The JSON schema first, then Flat-Folder: Maekawa and Kawasaki at each vertex, and at least one valid folded state must exist.
- *State and observation.* The state is a `CreasePattern` that can be written as `.fold`. The model sees three PNGs (target, current folded form, crease pattern) and a yes/no flag saying whether its last action was feasible.
- *Data.* 366 designs taken from Flat-Folder's online collection.
- *Metrics.* Query efficiency, silhouette IoU and CLIP similarity.
- *Finding.* On the causal one-step task the best model scored 43.37% against a 25% chance baseline.
- *Licence.* The paper is CC BY 4.0; no code licence was found.
- *What a step is.* An edit to the crease pattern, after which the solver recomputes the whole folded form. No paper moves, no flap is chosen and no layer is selected.

**12. Learn2Fold.** Source: https://arxiv.org/html/2603.29585.
- *Graph.* The crease pattern is a graph with vertices in [0,1]² and edges labelled M/V/U. It is made canonical by sorting vertices lexicographically and renumbering edges from that, and training data is augmented with rotations and reflections.
- *State.* `s_t` = signed dihedral angles, progress ratios, crease types, a **global frame angle**, an **M/V-flip flag**, and a step counter.
- *Actions.* The vocabulary is the union of operation tokens, graph-index tokens and quantised geometry bins, emitted under "a fixed JSON schema". The operation names are **not listed** in the HTML text.
- *Checking.* A deterministic "Level-0" kernel returns validity, a reason, and a mask of affected edges. A learned world model then scores the survivors in a lookahead loop that proposes 8 candidates per step.
- *Data.* OrigamiCode: 25 classes, 5,760 sequences, 75,000 trajectories drawn from instructional sources.
- *Code.* No licence or repository is given.

**13. COrigami.** Source: https://arxiv.org/html/2606.26299.
- *Pipeline.* A stick figure (labelled sticks with length, azimuth and elevation) becomes a box-pleated packing, then a flat-foldable crease pattern. A crease is two endpoints, M/V and a fold percentage in [0,1].
- *Shaping tools.*
  - A **simple fold** along a line through two points, cut through the flat-folded layers.
  - A **clip pattern** template that is carried across a flap's layers and swaps M/V automatically on layers that are upside down.
- *Agent.* A reinforcement-learning agent orchestrates the tools.
- *No sequence.* No folding sequence is produced; the folded form is simulated from the crease pattern.
- *Code.* No repository or licence was found.
- *Match with senbazuru.* The automatic M/V swap is the same fact as `ThroughLayers.hs:36-45`.

**14. FoldingAgent.** Source: https://arxiv.org/html/2609.00377.
- *State.* `S = (V, F, E, O, L)`: FOLD vertices, faces and edges with labels in {B, F, M, V}; a flag per face saying which side faces up; and a bottom-to-top list of layers made of "planes" (faces joined by flat edges).
- *Five primitives.*
  - `add_vertex(e, p)`: a point at fraction p along edge e.
  - `fold(e, d)` with `d ∈ {±1}`: fold along an existing edge.
  - `unfold(e)`.
  - `rotate(θ)`.
  - `flip(α)`, a **reflection** about x, y, y=x or y=−x.
- *Composition.* Folding along a line that does not pass through existing vertices is `add_vertex` followed by `fold`.
- *Scope.* Pureland origami: simple mountain and valley folds only.
- *Which paper moves (appendix B.3).* The "moving set" starts with the planes containing the ends of `e`. It grows by any plane sharing an edge on the moving side, and by any plane sandwiched between planes already moving. Moving vertices are mirrored across the line, and moving planes are turned over and placed above their static neighbours.
- *Checks.* "Compilation validity" through the Flat-Folder compiler: consistent topology, no self-intersection.
- *Data.* PurelandFold has 27 sequences, from the 40 Pureland models in OrigamiWay's Easy category, filmed by the authors.
- *Code.* Only a project page is given.
- *Newcomer trap.* A reflection is not the same as turning the model over. On a flat state that tracks which side faces up, reflecting plus toggling the side gives the same result. On 3D paper a reflection is the mirror model, which is exactly why #95 defines turning over as a half turn.

### E. The human vocabulary

**15. Lang's conventions: one step per figure, and letters on key points.** Source: a secondary summary, https://zenorig.blogspot.com/2012/09/origami-diagramming-conventions-robert.html.
- Valley lines are dashed; mountain lines are dash-dot.
- Valley arrows have symmetric filled heads; mountain arrows have hollow, one-sided heads. Push arrows have hollow stems.
- Turn-over is a looped arrow; rotation is a fraction inside a circle; repeats use leaders carrying step ranges.
- Each figure shows one step. Letters label key points. Cut-away and side views are used where layers hide the action.
- Base names should be limited to the standard ones.

**16. The Yoshizawa–Randlett system and fold definitions.**
- *History.* Yoshizawa introduced the symbols in 1954; Randlett and Harbin extended them; Randlett described the system in 1961 (https://en.wikipedia.org/wiki/Yoshizawa%E2%80%93Randlett_system).
- *Definitions.* Operational definitions of reverse folds, squash, rabbit ear, petal ("two side-by-side rabbit ears" joined along a reference crease), swivel and open/closed sinks are at https://en.wikibooks.org/wiki/Origami/Techniques/Practice.
- *Senbazuru's glossary.* It defines squash, rabbit ear, petal, puff and collapse (`docs/glossary.md:31-37`).

**17. The moves, each with a geometric meaning and a motion class.**

The motion classes:
- **Hinge**: one rigid rotation about one line. The line may span several collinear crease segments and several layers.
- **Coupled**: several creases turning together, with angles tied by the geometry.
- **Bend**: panels must curve, so no rigid-panel path exists or is known.
- **Whole**: a rigid motion of the entire model that changes no crease.

| Move | What happens, for someone who has never folded | Class | Evidence |
| --- | --- | --- | --- |
| Valley fold | Turn the paper on one side of a line up and over, onto the paper that stays | Hinge | `Flap.hs:1-6`; `prepareFlapAlong` handles several segments (`HelmetSequence.hs:47-51`) |
| Mountain fold | The same, turned away behind | Hinge | same |
| Precrease (fold and unfold) | Fold, then undo the same hinge. The crease stays as a mark that is flat in later states (`F`, 0°) | Hinge ×2 | `precreases-and-target-states.md:21`; the blintz "reopen" step (`BlintzSequence.hs:55`) |
| Turn over | Half-turn the whole model about an axis in the page | Whole | #95; Doodle `\turn_over_*` mirrors coordinates, FoldingAgent `flip` reflects |
| Rotate | Spin the model in the page's own plane | Whole (view) | Doodle `\rotate`; Lang's circle symbol |
| Inside reverse fold | On a doubled flap joined along a spine crease, fold two creases out from a point on the spine. The flap's end turns inside out between the layers, and the spine beyond that point changes from valley to mountain | Coupled | Wikibooks. The layers must separate: it is not one hinge through all layers |
| Outside reverse fold | The same, but the end wraps round the outside | Coupled | Wikibooks |
| Squash | Lift a doubled flap, open its pocket, press it flat, symmetric about its old spine | Coupled | `glossary.md:32`; endpoint study `six-more-base-endpoints.md:21-24` |
| Petal | Lift one layer's tip while its two sides fold inwards, making a long narrow flap | Coupled (checked) | `petal-fold-motion.md:48, 54`: the side angle obeys `tan(s/2)=sin22.5°·tan(t/2)`, two midline segments open from −180°; `CheckedBird.hs:1-14` |
| Rabbit ear | Gather a triangle along three creases meeting at a point, plus one reversed crease, into a pointed flap | Coupled (checked) | `rabbit-ear-motion.md:11, 55`; Doodle `\rabbit_ear` |
| Open sink | Push a point into the model while opening the layers, reversing the creases round the tip | Coupled, passes through a 3D state | Wikibooks |
| Closed sink | The same without opening the layers | Coupled; probably Bend (see Unverified) | Wikibooks |
| Crimp | Two reverse folds made together on a doubled strip | Coupled | Wikipedia Y–R |
| Pleat | A parallel valley and mountain, like an accordion | Hinge ×2 (can be done one after the other) | Wikipedia Y–R |
| Swivel | A flap rotates about a fixed point while a crease forms along one edge | Coupled | Wikibooks |
| Inflate / puff | Blow a pocket out into a 3D body | Bend | `glossary.md:35`; `the-puff-is-a-drawing.md:16` |
| Collapse (not Y–R) | Many precreased folds close at once | Coupled when rigid (`CheckedBird.hs:107-109`), Bend for a square twist (`endpoints-and-routes.md:21`) | `glossary.md:37` |

### F. Side by side, and against senbazuru

**18. Comparison.**

| System | A step is | Moves | Names moving paper by | References by | Checks | Output | Licence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Doodle | `\step{}` block | none computed; lines, arrows, `\move` per point | named points | named constructions, several axiom-like | none | PostScript | GPLv2 |
| Eos | one HO operation | O1–O7, unfold | half-plane of a fold line | named points/lines, solution index | Gröbner proofs | Mathematica graphics | needs Mathematica |
| Foldinator | a Scene | valley, mountain, reverse | mouse side | snap-to landmarks | "believed" | bitmaps + text | paper only |
| origami-diagrams | frame + `re:diagrams` | none | none | typed coordinates | none | SVG/HTML | MIT (package.json) |
| Rabbit Ear | a function call | axioms; flat fold through all layers | side of the line | 2D points/lines | layer solver | FOLD/SVG | GPL-3.0 |
| Akitaya et al. | a rewrite rule | simple, reverse×2, squash, petal, rabbit ear | the subgraph matched | the crease pattern itself | local flat-foldability | step graph + animation | paper; Creasy GPL-3.0 |
| OrigamiBench | add a crease | `add_crease(s)` M/V | nothing | vertex ids, or coordinates on a 0–10 square | Flat-Folder | `.fold` + PNG | paper CC BY 4.0 |
| Learn2Fold | one JSON action | not listed | canonical edge ids | quantised bins | Level-0 kernel + learned model | programs | not given |
| COrigami | a tool call (shaping) | simple fold, clip pattern | a flap (layers of it) | two points | flat-foldability, layer order | crease pattern | not given |
| FoldingAgent | one or more primitives | add_vertex, fold, unfold, rotate, flip | direction ±1 + moving-set closure | edge ids, edge fraction | Flat-Folder compile | programs + states | paper CC BY 4.0 |

**19. Where senbazuru's vocabulary stands today.**
- *The `crease` verb.* It takes raw coordinates, `--from X,Y --to X,Y`, with one of `--mountain`, `--valley`, `--flat` or `--unassigned`, and `--folded` to crease through the layers (`app/Senbazuru/Cli.hs:262-282, 316-320`). Each end must meet something already drawn (`src/Senbazuru/Fold/Creasing.hs:38-47`).
- *Through the layers.* `ThroughLayers` always creases every layer under the line; folding only the near layers is left to the vocabulary (`ThroughLayers.hs:56-61`).
- *A flap.* `Flap` selects a flap by crease id, a face on the moving side, and signed travel, with ids taken from the pattern *after* cutting (`Flap.hs:1-17`). A second path joining the two sides is refused, and creases on different axes need a coupled motion (`docs/notes/checked-flap-operation.md:11, 16`).
- *The study recipes.* Each step is a tuple of title, `EdgeId`, `FaceId` and travel (`BlintzSequence.hs:50-56`, `HelmetSequence.hs:47-51`), and a header says outright that this is not an instruction language (`BlintzSequence.hs:4-5`). The bird is four certified stages (`CheckedBird.hs:48, 83-87`).
- *Naming by position on the sheet.* The petal case names its fixed panel by a point on the original sheet, `fixedPanel: [0.58, 0.4]`, which survives face renumbering (`docs/notes/petal-fold-motion.md:62`; `study/fold-material/cases.json:174`).
- *Checking the route.* `HingeSweep` checks a whole rotation over an angle interval, and gives up with `Unresolved` rather than guess (`HingeSweep.hs:1-11, 49-51`). A valid state is not a route (`endpoints-and-routes.md:8`).
- *Flat folds.* At ±180° a mountain and a valley are the same rigid motion (`Origami/Folding.hs:542-545`).
- *Naming flaps.* The problem is recorded as CAD's topological naming problem (`docs/related-projects.md:89-96`).

## Implications for the design

1. **Keep references, moves and presentation as three layers of one syntax tree, and derive the third.**
   - Doodle shows what happens when drawing is the source of truth: it can describe paper that does not exist.
   - Senbazuru already derives arrows from positions (`Step.hs`).
   - Allow presentation overrides the way Doodle overrides line styles (`node10`), and store them as an optional vendor key in the style of origami-diagrams. Never let them drive the geometry.

2. **Name points in the written language by construction, not coordinates and not ids.**
   - Coordinates are what OrigamiBench's prompt and today's `--from/--to` use. They are "coordinates with extra steps" (#97), and a transposed pair is silent (`Cli.hs` comment on `point`).
   - Ids are what OrigamiBench's main text, Learn2Fold, FoldingAgent and the study recipes use. They are renumbered by cutting (`Flap.hs:9-10`, `crease-identity-through-refinement.md`), so a written file would silently point at different paper.
   - Adopt Doodle's and Eos's idea: named landmarks built from corners, midpoints, fractions, intersections and axiom solutions, as Lang's lettered points do. Resolve each landmark to a **position on the original sheet**, following the `fixedPanel` precedent. That position is stable across refolding; a face id is not.

3. **Axioms return a list, and choosing one must be written into the sequence.** Eos's Table 1 (0–3 answers), Doodle's optional choice argument and Rabbit Ear's arrays all say this. The PRD needs a deterministic, documented ordering (and a stable one if the model is rotated), an explicit index or disambiguating hint, and an `Either` error with an `Explain` instance for "no solution" and for "ambiguous, give an index".

4. **Which paper moves must be stated separately from the line, and the default should be what books assume.**
   - The prior-art rules: Eos picks a half-plane; Foldinator uses the mouse side; FoldingAgent uses a direction plus a closure that sweeps up sandwiched layers; Rabbit Ear and `ThroughLayers` fold through all layers.
   - None of them supports "fold only the top flap".
   - The PRD should make "through all layers" the default, name "near layers only" as a separate move (as `ThroughLayers.hs:56-61` already anticipates), and name the moving side with a material landmark, as `fixedPanel` names the stationary one.

5. **Make named macro-moves functions that compile to coupled rigid motions; do not invent a separate move kind.**
   - Akitaya's rewrite rules show that a macro-move is checkable by its signature on the crease pattern.
   - Senbazuru's certified petal, rabbit ear and square collapse show what such a move compiles to: a set of creases and a relation that drives their angles together.
   - The primitive in the syntax tree should be `Hinge` (one line) or `Coupled` (creases plus a driving angle); `petal`, `rabbitEar`, `reverseInside` and so on are library functions producing them.
   - Foldinator's "sequences of simpler folds" gives the right crease sets but the wrong motions, so it must not be the design.

6. **Precrease-then-collapse must be expressible.** No sequence exists for collapsed designs (`no-sequence-solver.md:13`), and books teach a petal as precrease followed by a lift. A precrease is two hinge moves with the crease left flat (`F`, 0°), and a collapse is one `Coupled` step.

7. **Turning over is a half turn, and rotating is state.**
   - Learn2Fold keeps a frame angle and an M/V-flip flag in its state. Doodle mirrors every coordinate; FoldingAgent reflects.
   - Follow #95: a whole-model rigid half turn. Any importer of FoldingAgent-style programs has to translate `flip` into it.

8. **One syntax tree, two front ends.**
   - Eos is embedded in Mathematica, the counterpart of the Haskell DSL (1). Doodle is a standalone text language, the counterpart of (2).
   - Both 2026 agents emit JSON against a schema.
   - Specify the syntax tree once. Make the text syntax a parser into it, and add a JSON encoding so LLM-produced programs can be read and checked against the same kernel.
   - Doodle's `\define`/`\include` show that macros and includes arrive quickly; decide early whether the text format has them.

9. **The output is a multi-frame FOLD with `file_classes: ["diagrams"]` and `frame_title`.**
   - The study already writes this (`BlintzSequence.hs:97-99`).
   - Do not rely on `frame_inherit`, which is not resolved (`Types.hs:150-153`).
   - Where the program is recorded (a vendor key or a separate file, #97 options 1 and 2) has to respect "preserve at the boundary, discard at the transform". A program key describing frames would be dropped by any transform, so whatever runs the sequence must regenerate it.

10. **Validity goes in levels, and the PRD should name them.**
    - Prior art stops at endpoint checks: flat-foldability and layer order in OrigamiBench, FoldingAgent and COrigami; a hard-coded kernel in Learn2Fold; nothing in Doodle; "believed" in Foldinator.
    - Senbazuru has a route check for single and certified coupled motions, which none of them has. The PRD should keep the three questions separate (state, route, reachability; `endpoints-and-routes.md:8`) and report which level each step passed.

11. **The material study (3) has to accept steps that rigid checking cannot certify.**
    - Puff, closed sink and twist need bending. Foldinator deferred curvature; Origami Simulator's compliant model folds everything at once and has no sequence.
    - Give the language a way to mark a step as material-only, or as drawn only, rather than rejecting it when parsed. The material solver or a prescribed shape (`the-puff-is-a-drawing.md`) then realises it, and the rigid engine refuses it by name.

12. **Test data and licences.**
    - Doodle, Rabbit Ear, Creasy and ORIPA are GPL: read for ideas only.
    - OrigamiBench's 366 designs come from Flat-Folder's collection, which includes other designers' patterns (`AGENTS.md` third-party rules), so none of them become fixtures without a check per design.
    - No dataset licence was found for PurelandFold or OrigamiCode.
    - `docs/related-projects.md` needs corrections: Doodle is GPLv2; origami-diagrams now lives at `amkraft/` and declares MIT only in `package.json`; Oriedita's `LICENSE.md` is MIT.

## Open questions

1. How does a written step name a flap that exists only because of earlier folds (for example "the front flap" after a squash) without an id that renumbers? A material point inside the flap is stable, but a point can lie in several layers. Does it need a depth ("the top layer at landmark X")?
2. Should "fold only the near layers" be a move in the first vocabulary milestone, given that no prior art supports it and `ThroughLayers` refuses it?
3. How are multiple axiom solutions ordered so the order does not change when the model is turned over or rotated before the step?
4. Is the program stored in the FOLD file under a vendor key, in a separate text file, or both? And what does `render` do with a program key it did not generate?
5. Should the first milestone be Pureland only (hinges plus turn-over and rotate), as FoldingAgent scoped itself, with macros added as certified coupled motions one at a time?
6. Can macros be added to the language without a general coupled-motion solver (#55), when today each one is a derived closure formula (petal, rabbit ear)?
7. Should the JSON encoding aim to read OrigamiBench, FoldingAgent or Learn2Fold programs directly, given their id-based references?
8. How should the material study (3) report a step it could render but could not certify, so that a realistic picture is not taken as a validity claim?

## Unverified

- **Eos function names.** `BeginOrigami`, `NewPoint`, `ShowOrigami`, `ProveByGroebner`, a `!` postfix meaning fold-and-unfold, and "right faces move by default" came from a summarising fetch of the SYNASC notebook. A grep of the raw page found only `EosSession`, `Unfold` and `Mark`. The author list (Ida, Takahashi, Marin, Kasem, Ghourabi) comes from search snippets.
- **Foldinator was never released** (`related-projects.md:39`). The paper only says it is under development, with 1.0 anticipated.
- **Mitani's folded-shape estimation algorithm.** No paper describing it was found or read; only the ORIPA page.
- **Tachi's method.** The details (crease angles as the configuration, projection onto the constraint space) come from a summarising fetch of the research index and a search snippet. The 2009 paper itself was not read.
- **Learn2Fold's operation names**, and the explanation for its v1 date preceding the `2603` prefix.
- **OrigamiBench's actual interface.** Whether the environment accepts vertex indices (main text), coordinates (appendix prompt), or both.
- **Akitaya's final publication.** The 6OSME 2014 venue and the SIGGRAPH 2013 poster are known from search results only. The method as described here is from the 2012 seminar paper, not the final version.
- **Motion classes for squash, swivel, crimp and both sinks.** These are my geometric reasoning, not measured. Reverse folds and crimps as "Coupled" rests on each being flat-foldable vertices of degree 4, whose rigid kinematics the repo cites for the rabbit ear (`rabbit-ear-motion.md:22-26`); global collisions were not considered. The closed sink as probably needing bending is folder lore, not checked.
- **Licences not checked.** Creasy's handling of its ORIPA dependency; the code for COrigami, FoldingAgent and Learn2Fold; the PurelandFold and OrigamiCode datasets.
- **Lang's conventions.** They were read through a secondary blog summary, not Lang's own document.
- **Wiki definitions.** Wikipedia's one-line definition of swivel and crimp, and the Wikibooks definitions, came through a summarising fetch. They were not reread in raw text.
