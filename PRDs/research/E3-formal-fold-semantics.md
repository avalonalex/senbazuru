# E3 — Fold sequences with formal semantics, and where senbazuru stands

Written 2026-09-23 against `19de099`, after #344 merged, so unlike the notes
beside it this one postdates the PRDs. It extends
[E1](E1-prior-art-sequence-languages.md), which surveyed languages that *write
down* folding sequences, with the work that *defines* what a fold is: what a
folded state is, which paper a fold moves, what "valley" means, and what is
checked. Five research passes read the primary sources; the evidence tags
follow the other notes: **[read]** in the source, **[ghci]** run against
senbazuru, **[reasoned]** derived here, **[unverified]** with where it came
from.

Revised the same day, after #353's post-merge review: section G's
square-base run had named the bottom page the top one, and is now a script
under [`scripts/`](scripts), rerun at `6c5048b`; the Summary's claims about
reopening are narrowed to a sense read from the viewer; and the corrections
to E2 are added.

## Summary

Five families were read:

- **Abstract origami and Eos** (Ida and colleagues, 2004–2025): a folded state
  is faces, adjacency and a superposition relation; a fold is graph rewriting;
  constructions are proved by Gröbner bases, a computer-algebra method that
  solves polynomial equations exactly.
- **Folded states, motions and simple folds** (Demaine and colleagues): a
  folded state is an isometry plus a layer order; a simple fold turns some
  layers by ±180° from flat to flat.
- **Construction axioms and their formalisations**: Justin, Huzita–Hatori,
  Alperin–Lang, Lucero; analyses in computer algebra systems; two Lean
  developments from 2026; and Beloch, an MIT-licensed OCaml fold language that
  E2 already listed, read again here at its latest commit.
- **Executable models**: Miyazaki's 1996 simulator, Balkcom and Mason's robot
  folds, An and Rus's fold schedules, Tachi and Xi–Lien's rigid motions.
- **The notation's own semantics**: diagram recognition (Kato, Shimanuki,
  Watanabe), Uchida and Itoh's knowledge representation, Tsuruta and Mitani's
  diagramming CAD, and Lang's diagramming conventions.

None of them combines what senbazuru does: a first-order sequence language,
paper named by material landmarks, every hinge turn checked over its whole
path with "unresolved" as an honest answer, and a record per move.

On the question #344's review left open, what `fold in front` means for paper
that is already folded:

- **No source gives reopening a folded hinge a sense word read from the
  viewer.** Every simple-fold model starts from an open hinge, and
  Akitaya–Demaine–Ku exclude reopening outright. Where reopening is written
  down it is its own operation: Eos's `Unfold`, Uchida and Itoh's "open",
  FoldingAgent's `unfold(e)`, Cardinal et al.'s directionless unfold, and the
  unfold arrow of the notation itself. Rigid-origami definitions do sign any
  hinge, a closed one included, but relative to the paper, not the viewer
  (finding 5).
- **Where a sense word read from the viewer is attached, it names where the
  moving paper goes**: Lang's valley arrow is paper moving towards the reader,
  Eos's valley puts the moved faces above those they overlap, FoldingAgent's
  moving side goes towards the viewer and lands on top, and Balkcom's
  reflection folds, which turn a page, are directed by where the flap lands.
- **senbazuru's rule, the sign read from the held face
  ([PRD 05 L14](../05-prd-library-additions.md#l14-eq-on-flap-values-and-prepareflaptoward)), agrees
  on open hinges and disagrees on hinges already folded.** On a page turn it
  depends on which hinge crease is listed first, as a GHCi run on the square
  base shows (section G; the script is
  [`scripts/E3-square-base-listing.ghci`](scripts/E3-square-base-listing.ghci)).

Recommendation: define the sense by the moving paper's motion, which is what
[PRD 02 §5.3](../02-language-semantics.md#53-one-conversion-for-the-whole-model)'s
own sentence says, and add a reopening move with no sense beside `fold`.
Only #282's negative control changes its wording. **The owner adopted this on
2026-09-23**; [decisions.md](../decisions.md) records it in D5 and as owner
decision 13.

## Findings

### A. Abstract origami: Eos and graph rewriting

**1. The model.** Ida, Takahashi, Marin, Ghourabi, "Modeling Origami for
Computational Construction and Beyond", ICCSA 2007, LNCS 4706:653–665; Ida &
Takahashi, "Origami fold as algebraic graph rewriting", J. Symbolic
Computation 45(4):393–413, 2010 [read].

- *State.* Faces, each a convex polygon; a symmetric adjacency relation; and a
  superposition relation, "directly over", defined only between overlapping
  faces. Its transitive closure is proved a strict partial order. No fold
  angles.
- *A fold.* A crease step cuts the faces reachable from a given face set F
  along a directed line, then a basic fold rotates the moving set M by π
  (valley) or −π (mountain). M is everything reachable from the pieces right
  of the line, across edges not on the line, **plus every face lying on top of
  them**. The fold is refused if the line passes through a face's interior.
- *Layer update.* Both stationary: order kept. Both moved: inverted. Moved
  against stationary: valley puts the moved face above, mountain below, in the
  fixed top view.
- *Naming.* A face divides into children 2n and 2n+1; a directed edge
  between two named points identifies a face (Lemma 8).
- *Checked.* Only the combinatorics of the relations and the line test. No
  collision or motion check.

**2. The system.** Eos, 2002–2025, version 3.9.1 for Mathematica 14.3 [read:
tutorial notebook at github.com/Fadouagh/Eos, SYNASC 2021 tutorial, RISC 2024
notebook, 2025 supplement].

- `HO[...]` picks the Huzita operation from its argument types; `By->"R"`
  (earlier `Move`, `Handle`) names the moving side by a point; `FoldLine->k`
  picks one of several solutions; a postfix `!` folds and unfolds.
- The tutorial defines valley as directed towards the folder, mountain away.
- Since 2021, `ValleyFold` and `MountainFold` take a list of faces, and
  `InsertFace` says where in the stack the moved faces go. Classical folds are
  programs: an inside reverse fold is cut, mountain on the upper face, valley
  on the lower with `InsertFace`, glue (Ida & Takahashi, "A New Modeling of
  Classical Folds in Computational Origami", EPTCS 352:41–53, 2021).
- `Prove` turns the construction into polynomials and returns True or Fail
  with a proof document. The chosen solution is not a premise, so a proof
  covers every branch.
- **Eos has folded a crane**: a 2007 figure, §7.4.3 of Ida's 2020 book, a
  2024 big-wing crane program.
- Closed source: the packages come by email to project members; the tutorial
  is CC BY-NC-ND 4.0. Orikoto is a subset of Wolfram Language with no
  separate grammar.

### B. Folded states, motions and simple folds

**3. Folded state and motion.** E. Demaine, Devadoss, Mitchell, O'Rourke,
"Continuous Foldability of Polygonal Paper", CCCG 2004 [read], the basis of
Chapter 11 of *Geometric Folding Algorithms* (2007) [unverified: book not
read].

- A folded state is (f, λ): f preserves distance measured along the paper; λ
  orders pairs of points in contact, **relative to the paper's normal** at the
  reference point, as FOLD `faceOrders` does. Conditions: symmetry,
  transitivity, consistency, and local noncrossing.
- A motion is a continuous family of folded states, continuous in order as
  well as position: separating layers leave on the side λ says.
- Every piecewise-C² folded state (one that is smooth except along finitely
  many curves) is reachable, but not rigidly: the paper
  rolls. A "step" is left undefined.

**4. Simple folds.** Arkin, Bender, E. Demaine, M. Demaine, Mitchell, Sethia,
Skiena, "When Can You Fold a Map?", CGTA 29(1):23–46, 2004 [read]; Akitaya,
E. Demaine, Ku, "Simple Folding is Really Hard", J. Information Processing
25:580–589, 2017 [read].

- Arkin: a some-layers simple fold names a top side, a crease point, ℓ layers
  counted from the top, mountain or valley relative to the top, and which side
  moves. The moving part turns rigidly 180°; any self-intersection **during**
  the turn makes it invalid. In 2D, ℓ is given per portion of the line.
- Akitaya–Demaine–Ku: a simple fold is a directed axis and a moving region U,
  under seven conditions. Condition 3 keeps every existing crease folded, so
  **a simple fold never reopens a crease**. Conditions 6 and 7: before and
  after, U lies wholly above or below the paper it overlaps, on the side the
  axis's direction says. The direction of the axis is the sign.
- Cardinal et al., "Algorithmic Folding Complexity", Graphs and Combinatorics
  27(3), 2011 [read]: a valley puts the moved part on top; **unfolding is a
  separate operation with no direction** (rewind, or to any earlier state).
- Every state in these sequences is flat, and every fold starts with its
  hinge flat.

**5. Rigid origami.** Abel et al., "Rigid Origami Vertices", JoCG 7(1), 2016
[read]; Akitaya et al., "Rigid Foldability is NP-Hard", JoCG 11(1), 2020
[read]; Tachi, "Simulation of Rigid Origami", Origami⁴, 2009 [read]. The fold
angle is the signed deviation from flat, valley > 0, relative to the paper; a
motion is a continuous path through non-crossing rigid states; loop closure is
the product of rotations. These are the only definitions that give a sign at a
hinge that is not flat, and they give it relative to the paper, not the
viewer.

**6. Flat-folded states.** Akitaya, E. Demaine, Ku, "Computing Flat-Folded
States", Origami⁸, 2024 [read]: a face-by-face order is valid under
antisymmetry, transitivity, tortilla–tortilla, taco–tortilla and taco–taco,
and for convex faces is equivalent to the point-by-point definition — which
is what makes `faceOrders` formally checkable.

### C. Construction axioms and their formalisations

**7. The operation lists.** Justin 1986 (*L'Ouvert* 42) [read]: an elementary
step is a fold then an unfold, its result a crease; solution counts per
operation, including degenerate cases. Alperin, NYJM 6, 2000 [read]; Alperin &
Lang, Origami⁴, 2009 [read: draft]: a fold is a reflection, exactly seven
one-fold axioms, 489 two-fold ones. Lang, *Origami and Geometric
Constructions* [read]: which side moves is arbitrary. Lucero, Forum
Geometricorum 17, 2017 [read]: eight operations, his O3 being "fold along a
given line"; existence conditions for O5, O6 and O7.

**8. Algebraic views.** Ghourabi, Kasem, Kaliszyk, ADG 2012 [read]: each
operation denotes a *set* of lines, with exact degeneracy conditions and
counts (O5 ≤ 2, O7 ≤ 1, O6 ≤ 2 if parallel, else 1–3); a proof covers every
branch. Ghourabi & Takahashi, AISC 2018 [read]: exact counts by configuration.

**9. Machine-checked work.** Kaliszyk & Ida, CICM 2011 [read]: only Eos's
final algebraic goal, in HOL Light and Isabelle. Boulay, Chai, Chang, Moulin,
"A Lean Paper About Paper", arXiv 2609.14912, 2026 [read]: existence
(sometimes uniqueness) for each Huzita operation, one witness, nothing
enumerated. LeanOrigami (2026) [read]: its Axiom 7 appears to make every real
number constructible. Ramseyer, "Verifiable Origami Folding", 7OSME 2018
[read]: an SMT solver (a satisfiability checker for arithmetic constraints),
every fold immediately unfolded, solutions chosen by an
orientation-based index. **Nothing proves a solver returns all solutions.**

**10. Beloch** (github.com/tophcodes/beloch, MIT, OCaml, commit `61930e4`,
2026-09-23) [read: specification, decision records 0016 and 0022]. The
closest prior art to our constructions: candidates computed on the current
flat state, dropped unless they cut a face's interior in a segment of positive
length, a program-side selection, and defined only if exactly one remains.
O3 chooses by a `toward X` *direction* reading, after its notes found both a
"nearest bisector" and a "sector" reading pick the wrong crease on the kite
base; O5 and O6 pick the landing nearest X; a straddling operand is an error
unless `moving` picks a half. Exact real-algebraic arithmetic. E2 already
listed Beloch, whose history starts in April 2026; this reading corrects E2 on
one point, that `toward` is not `nearest` for O3 (recorded in decisions §10).

**11. ReferenceFinder** (Lang; GPL, research only) [read]: keeps every root,
filters landings off the paper, chooses who moves by a visibility rule, and
disambiguates in words by the landing point.

### D. Executable models

**12. Miyazaki, Yasuda, Yokoi, Toriwaki**, "An Origami Playing Simulator in
the Virtual Space", J. Visualization and Computer Animation 7(1), 1996 [read].
Faces in a split tree, a total order per plane, positions stored and rotated.
A fold is made by dragging a corner; faces the moving part overlaps *on the
side it turns towards* are carried along, so no collision can arise; no
collision detection at all. A total order per plane cannot hold a twist's
cyclic overlaps (Mitani, EG 2008 [read]).

**13. Balkcom & Mason**, "Robotic origami folding", IJRR 27(5), 2008, and
Balkcom's thesis, CMU-RI-TR-04-43 [read]. Facets with a rooted spanning tree
and signed crease angles; for flat states, the stacking plus the folded
creases. A *simple fold* moves everything on one side of a line up (valley) or
down (mountain); a *reflection fold*, which the thesis calls a book fold
(not the glossary's book fold, which halves a sheet edge to edge), lets flap
and base lie on the same side, like turning a page, and **its direction is which side of the base
the flap ends up on** — both are tried and the colliding one dropped.
Rewriting rules: mountain = flip · valley · flip; flip · flip = identity.
Candidate crease sets are contiguous runs from the top or bottom of the
stack, and must cut the facet graph. Collisions are checked only at start and
end, which is exact for a 180° turn from flat to flat.

**14. An, Benbernou, E. Demaine, Rus**, Robotica 29(1), 2011; Hawkes et al.,
PNAS 107(28), 2010 [read]: a plan is phases of target angles per hinge,
obtained by unfolding the target in a simulator and reversing; no collision
or layer check; the authors test in hardware.

**15. Tachi; Xi & Lien** [read: Tachi; abstracts only for Xi & Lien]: the
configuration is fold angles under vertex closure; global self-intersection
and stacking are explicitly unsolved in Tachi's simulator; Xi & Lien plan
collision-free paths by sampling, method unverified.

**16. FoldingAgent** (arXiv 2609.00377, 2026; in E1) [read]: a fold names an
existing edge and a direction `d`; the moving set is closed under shared edges
and sandwiched layers; moving planes land **on top**; `unfold(e)` is separate.

### E. The notation's own semantics

**17. Kato, Watanabe, Hase, Nakayama**, "Understanding Illustrations of
Origami Drill Books", IPSJ Journal 41(6), 2000 [read]; **Shimanuki, Kato,
Watanabe**, MVA 2002 [read], GREC 2003 [read in part], MVA 2005 [read]. One
basic operation, "folding back": split a face, turn one part 180°, direction
read from the symbol pair. Tucking in and covering are compound. Faces in the
way are carried along. **The next figure decides between candidates**,
including which layers moved. Shimanuki 2005 states the layer rule for
neighbouring faces that PRD 02 §5.3's table states.

**18. Uchida & Itoh**, "Knowledge Representation of Origami and Its
Implementation", IPSJ Journal 32(12), 1991 [read, in Japanese]. A "tower" of
face splits, one floor per operation; each crease carries (mountain or
valley, open or folded); operations fold, tuck and **open**; open has no
direction of its own. Built backwards from the crane's crease pattern.

**19. Tsuruta, Mitani, Kanamori, Fukui**, "A CAD System for Diagramming
Origami with Prediction of Folding Processes", Origami⁵, 2011 [read]. Only the
topmost *n* layers fold; a candidate is discarded when a lower layer is joined
to a selected one across the line — our coupled refusal. Valleys and
fold-and-unfold only; mountains by turning over.

**20. Lang, "Origami Diagramming Conventions"**, langorigami.com, 2011 [read].
Lines say where, arrows say motion; a valley arrow is paper moving towards the
reader, a mountain arrow away; a reverse fold moves sideways and by convention
takes a valley arrow. Reverse-fold lines give the crease as seen, per layer.
Montroll's double hollow arrowhead is used for every kind of unfolding. The
arrow's tail hooks round the flaps that move. Lang's **ply** is one thickness
and his **layer** a separable thickness.

## F. Side by side

| System | A state is | A move | Which paper moves | The sense means | Reopening a folded hinge | Checked |
| --- | --- | --- | --- | --- | --- | --- |
| Eos / abstract origami | faces, adjacency, superposition | cut + ±π rotation, rewriting | faces from F, plus all faces on top | end state: valley moved faces above | `Unfold` | construction proofs; no motion |
| Arkin simple fold | positions + partial order | 180° turn, flat to flat | top ℓ layers, per portion | rotation relative to chosen top | never (starts flat) | whole turn, no crossing |
| Akitaya–Demaine–Ku | flat fold + global order | reflect U across directed axis | U | direction of the axis | excluded (cond. 3) | endpoints (exact) |
| Rigid origami | fold angles | continuous path | — | angle sign, relative to paper | defined, relative to paper | loop closure; crossing |
| Balkcom & Mason | stacking + folded creases | simple fold, reflection fold | one side / top or bottom run | up = valley; reflection fold by landing side | reflection fold, both tried | start and end |
| Miyazaki | positions + order per plane | drag a corner | picked face + connected + in the way | where the corner goes | by dragging | none |
| Kato, Shimanuki | split tree + order stacks | folding back, compound | face named + carried | rotation from symbols | not covered | next figure matches |
| Uchida & Itoh | tower of splits | fold, tuck, open | any face, alternating | crease attribute | `open`, no sense | backwards consistency |
| Tsuruta et al. | layered model | valley, fold-and-unfold | top *n* | valley only | fold-and-unfold | coupling, penetration |
| FoldingAgent | graph + plane DAG | fold(edge, d), unfold | closure over planes | moving side towards viewer, lands on top | `unfold(e)` | none in simulator; results scored with Flat-Folder |
| Beloch | flat state | constructions | `moving` half | — | — | exactly one candidate |
| Lang's notation | — | arrows + lines | hooked flaps | motion towards / away from reader | unfold arrow | — |
| **senbazuru** | crease pattern + angles + `faceOrders` + anchor | hinge turn by A°, macros | flap containing a seed, `top N`, `top flap` | **rotation read from the held face (L14)** | `unfold NAME` (exact reversal) | whole path, "unresolved"; macros at samples |

## G. The open question: a sense for paper already folded

**Three kinds of hinge turn** [reasoned]:

1. *Closing an open hinge* — the moving paper lies flat beyond its crease.
   Every source agrees: valley brings it up towards the reader onto the held
   paper. So does senbazuru. The blintz, the quarter fold and the crane wing
   are all this kind.
2. *Reopening a closed hinge* — a flap lying folded over its held face is
   lifted back. No source gives this a sense read from the viewer (findings
   2, 4, 16, 18 and 20); rigid origami signs it relative to the paper
   (finding 5). Under L14, lifting a top flap towards the reader is `behind`.
3. *Turning a page* — the flap is hinged to paper on both sides of the line,
   so the turn opens one crease and closes another. Balkcom directs it by the
   landing side, Eos's valley puts it on top, FoldingAgent lands it on top.
   Under L14 the answer depends on which crease is listed first.

**Why L14 depends on the listing** [reasoned; ghci]. A rigid turn about a
line moves paper on one side of the line up and paper on the other side down.
L14 reads the *held* face beside the first crease; the reader-side sense of a
segment then depends only on which side of the line its held face lies, since
the face's way up cancels. On a page turn the held faces lie on both sides.
On `examples/square-base.fold`, with spine edge 14 relabelled unassigned
(Flap refuses its `F`), take the bottom page on one side: faces 6 and 7,
joined by edge 15 at +180. Face 0, the root, lies directly over it: from +z
that side stacks faces 1, 0, 7 and 6, in the only layer order the solver
finds [ghci]. That follows from the assignments: edge 8 is a mountain fold of
face 0, which lies top up, so it turns face 7 behind face 0, and edge 15 then
turns face 6 behind face 7 [reasoned]. The page is held by
face 5 across the spine (edge 14) and by face 0 above it (edge 8), and both
lie top up [ghci]. Lying under face 0, the page can only set off away from the
reader. Under L14, turning it towards −z gives travels of −180 on edge 14 and
+180 on edge 8 when listed `[14, 8]`, which is the page turn, and the opposite
when listed `[8, 14]`, which drives the page into face 0. Towards +z the two
listings swap: `[8, 14]` gives the page turn and `[14, 8]` the collision
[ghci]. The script is
[`scripts/E3-square-base-listing.ghci`](scripts/E3-square-base-listing.ghci),
run at `6c5048b`.

**Two readings, each consistent:**

- **(A) Motion.** `in front` means the paper that moves sets off towards the
  reader. Computed from the *moving* paper: a positive change in a crease's
  angle moves the face beside it towards that face's own top side, so the
  sign follows from the moving face's way up [reasoned]. The sense this
  gives a segment depends only on which side of the line that segment's
  moving face lies, so every segment agrees unless the moving paper itself
  straddles the line. A page turn gets one answer: on the square base,
  `behind` gives the page turn under either listing, reading face 6 for
  `[14, 8]` and face 7 for `[8, 14]` [reasoned from the ghci run: face 6 lies
  the same way up as face 5, which L14 reads for `[14, 8]`, and face 7 the
  other way up from face 0, which L14 reads for `[8, 14]`]. Refuse when the
  moving paper beside the hinge straddles the line or stands on edge. Agrees
  with L14 on open hinges.
- **(B) Crease, as built.** `in front` means the hinge closes on the reader's
  side of the held face. Consistent with the rigid-origami sign convention.
  To be honest about kinds 2 and 3 it needs a refusal for any fold that opens
  a folded hinge, pointing to `unfold`, and a separate move for page turns,
  since requiring every segment to agree would refuse every page turn.

| | (A) Motion | (B) Crease, as built |
| --- | --- | --- |
| Open hinges | same | same |
| Lifting a flap off the face it lies on | `in front` | `behind`, or refused → `unfold` |
| Page turn | where the page goes, one answer | listing order, or refused |
| Completing a valley already past 90° | reads as `behind`; refused while the moving face must lie flat (decisions D5) | `in front` |
| Blintz, quarter fold, crane wing | unchanged | unchanged |
| #282's negative control E10 | `fold in front …` | `fold behind …` (as written) |
| Crane source's four page turns | as written | depend on listing |
| Sources behind it | PRD 02 §5.3's sentence, Lang, Eos, FoldingAgent, Balkcom's reflection folds, Miyazaki | PRD 02 §5.3's table, PRD 05 L14, rigid-origami angle signs |

**Recommendation: (A)**, with `prepareFlapToward` reading the moving paper
instead of the held face — a small follow-up to #344. Under (A) a `fold` can
turn a folded-over flap back, with the sense of where it goes; a sense-free
reopening move is proposed beside it, since books draw reopening with an
unfold arrow and only one direction is ever possible. The case (A) handles
worse, a partial fold past vertical, is rare in instruction books and
ambiguous there too. Adopted by the owner on 2026-09-23.

#282's negative control under (A) is `fold in front 180° hinge of c1 moving
corner south-east`: the corner lies under the square after c1, so turning it
towards the reader drives it into the square. `Flap` refuses that as
`FlapEndpointOrder`. Once 02 §6.3's covering check (step 4) exists, the
square is found nearer on the side the corner turns towards, and the move is
refused before `Flap` runs, as `FlapCovered`, whichever sense word it is
written with: the same change the crane wing's example went through
(decisions C9) [reasoned].

## Implications for the design

1. **The sense.** As G recommends. PRD 02 §5.3's table becomes the special
   case of an open hinge, and its sentence the definition.
2. **Reopening.** An `open` move, or `unfold` taking a flap as well as a step
   name, with no sense (Uchida–Itoh, Lang/Montroll, FoldingAgent, Eos).
3. **Layers.**
   - senbazuru's "layer" is Lang's *ply*; a book's "fold the top layer" is our
     `top flap`. The glossary should say so.
   - "Top *n*, counted at each point" is universal (Arkin, Akitaya–Demaine–Ku,
     Tsuruta, Balkcom); our `DepthChangesAlong` refuses Arkin's own example of
     1, 3 and 2 layers along one fold, which `flap containing` covers.
   - Where Miyazaki, Kato and Eos carry covering paper along, we refuse. Keep
     refusing, but name the covering faces and the `top N` that would carry
     them.
   - The mirror case, `behind` with `top N`, passes only when nothing lies
     under the moving layers; either add `bottom N layers` or document the
     turn-over idiom (Balkcom's rewriting rules make them equal).
4. **Constructions** (Beloch, ReferenceFinder, the algebraic analyses):
   - `nearest P` should measure the *landing point* for O5 and O6, and record
     the chosen landing so a branch switch after an edit is visible.
   - "Crosses no paper" should mean "meets no face's interior in a segment of
     positive length" (a bisector touching only a corner is off the paper).
   - Treat a discriminant within tolerance as zero and merge equal lines
     before counting (tangent O5 must give one fold).
   - `DegenerateConstruction` should refuse the infinite families by their
     exact conditions; O6 with parallel lines is a quadratic with 0–2 answers,
     not an error.
5. **Property tests.**
   - Constructions: plant a solution (pick a fold, build the inputs from it,
     check it is returned); soundness; counts against closed forms; Justin's
     identity (O6 with parallel lines equals an O5); invariance under rigid
     motion and scale.
   - The sense: Balkcom's identities, `turn over; valley X; turn over` =
     `mountain X`.
   - `HingeSweep`: a 180° turn from flat to flat can only collide at its ends
     (Balkcom; Akitaya–Demaine–Ku 6–7), so an endpoint stacking check is an
     independent oracle on those cases, where "unresolved" should never occur.
6. **Refusals and records.** Name the reasons the literature separates: a
   tear or coupled selection, blocked at the start or the end, a collision on
   the path, a locked closed vertex (Tachi), unresolved. Optionally accept a
   target crease pattern and report the first step whose crease disagrees in
   sign (Balkcom). A per-step table of target angles (An et al.) is an export
   hardware and Origami Simulator already read.
7. **Naming.** Eos distinguishes a point of the paper, which folds carry, from
   a fixed point in space; that is the distinction E1's open question 1 needs
   for a point lying in several layers.

## Corrections to this repository's records

E1 and E2 are snapshots and are not edited; their corrections are recorded
in [decisions.md §10](../decisions.md#10-corrections), rows 33, 34, 37 and 38,
as row 32 did before them. The others are fixed where they stand.

- **E1** finding 2 ("What it lacks"), its §F table, implication 4 and open
  question 2 say Eos only picks a half-plane and that no prior art folds "only
  the top flap" or "only the near layers": Eos takes a face set (2007) and
  face lists with `InsertFace` (2021).
- **E1 Unverified**: the functions are `NewOrigami` and `Prove`, not
  `BeginOrigami` and `ProveByGroebner`; `NewPoint`, `ShowOrigami`, the `!`
  operator and right-side-moves-by-default are confirmed. Its table's licence
  cell should read closed source.
- **`docs/related-projects.md`** said Eos answers "never *how do I fold a
  crane*" and that its licence was not checked: Eos has folded a crane, and it
  is closed source, distributed on request to members. Fixed there, in #353
  and, for the "Two halves that never met" paragraph it missed, #361.
- **E2** calls `along <line>`, its fold along a line already on the paper,
  "Lucero's eighth" (its construction rule 4), and writes `nearest @p` as
  "Beloch's `toward`", which holds for O5 and O6 but not for O3 (finding 10).
- **PRD 02 §4.3, decisions D2 and the glossary additions** called
  `crease [P, Q]` "Lucero's eighth"; Lucero numbers it O3, the operation he
  adds, and his O8 is Huzita–Hatori O7. `P to L` is Justin's ④,
  Huzita–Hatori O7 with the second line perpendicular to L. Fixed there.

## Open questions

1. How books draw a page turn — a valley arrow, or an unfold arrow when the
   turn opens a crease — was not checked against a real diagram.
2. *Answered after review.* The square base's spine crease 14 is `F`, and
   `Flap` refuses to turn an `F` crease (PRD 02 §6.2's `ExistingHingeFlat`,
   D8), which is why the run above relabels it. The crane source does not meet
   this: its page turns hinge on the diagonal it creases with `fold and
   unfold`, and the working pattern keeps a precrease's intent at angle 0
   (D3), so that crease is a valley `Flap` can turn.
3. What `repeat` should mean for a step repeated "behind": by Balkcom's rules
   it is the step wrapped in a turn-over, which may or may not be what
   `mirrored across` already says for symmetric flaps.
4. Eos's 2024 slides list `Inside` and `Outside` directions beside mountain
   and valley without explaining them.
5. Whether a partial fold past vertical needs its own spelling under (A), for
   example a target angle.

## Unverified

- *Geometric Folding Algorithms* itself; its definitions are taken from the
  CCCG 2004 paper and from their restatement in Akitaya–Demaine–Ku 2024.
- Xi & Lien's planners (abstracts only); Balkcom's journal volume and pages.
- The SAC 2007, WFLP 2007, AISC 2004, Origami⁴ Eos chapter and JSC 2015 knot
  papers were not obtained; `InsertFace`'s definition is from a search excerpt
  and agrees with the 2021 paper.
- Book practice for page turns (open question 1).
- A summarising fetch invented content twice during this research (a
  turn-over section in Ramseyer, a viewer-relative definition in Balkcom);
  every [read] claim above was checked against the text itself.
- Beloch was read at one commit on the day it was updated; its decisions may
  change.
