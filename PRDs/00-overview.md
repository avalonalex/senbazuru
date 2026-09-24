# 00 — Overview: connecting the fold solver and the material study

Written 2026-09-14 against `568dcb6`, and reconciled on 2026-09-15 with
[decisions.md](decisions.md), the decision record every file in this series
follows; where the two disagree, the record wins. This file tells at length what
that record's [§1](decisions.md#1-the-two-halves-today-and-what-connecting-them-means)
(the two halves today), [§2](decisions.md#2-shape) (the shape),
[D18](decisions.md#d18-non-goals) (non-goals) and
[D19](decisions.md#d19-realistic-rendering) (what "realistic" means) decide. This
is research and requirements only; nothing is implemented. [README](README.md) has
the reading order.

The series answers three requests:

1. an embedded Haskell language for fold sequences and their steps;
2. a `senbazuru` verb reading the same language from a file;
3. the *material study* taking what (1) and (2) define and producing realistic
   renderings, as glTF (the 3D file format `export` writes,
   [glossary](../docs/glossary.md#this-project)) and as an SVG line drawing. The
   material study is `study/fold-material/`, an executable beside the library
   that bends folded paper as a thin elastic sheet.

Terms are defined in one clause and linked to [the glossary](../docs/glossary.md)
or [glossary-additions.md](glossary-additions.md), the only copy of every term
these PRDs introduce.

## The problem in one example

A *blintz* folds the four corners of a square to its centre
([glossary-additions](glossary-additions.md#origami)). Its fixture,
`examples/blintz-base.fold`, records a unit square as 8 vertices and 12
numbered *edges*, FOLD's straight segments between two vertices. Ids count from
zero. Edges 0–7 are the paper's border, each side split at its midpoint; edges
8–11 are the four corner creases (lines the paper bends along). The file records
no faces.
`jq -c '[(.vertices_coords|length), (.edges_vertices|length), .edges_assignment, .faces_vertices]' examples/blintz-base.fold`
prints `[8,12,["B","B","B","B","B","B","B","B","M","M","M","M"],null]`.

The study folds it with this table
([`BlintzSequence.hs:50-56`](../study/fold-material/BlintzSequence.hs#L50-L56)).
Two things in it look wrong and are not: move 4 names `FaceId 1` after `FaceId`
2, 3 and 4, and move 5 repeats move 1's ids. Both are explained just below it.

```haskell
recipe =
  [ ("Fold the first corner to the centre", EdgeId 8, FaceId 2, -180),
    ("Fold the second corner to the centre", EdgeId 9, FaceId 3, -180),
    ("Fold the third corner to the centre", EdgeId 10, FaceId 4, -180),
    ("Fold the last corner: blintz base", EdgeId 11, FaceId 1, -180),
    ("Reopen the first corner", EdgeId 8, FaceId 2, 180)
  ]
```

Each tuple has four parts:

1. a caption;
2. the *hinge*, the crease the paper turns about, as an edge id;
3. a *face*, a flat region between creases, on the side that moves
   ([glossary](../docs/glossary.md#geometry));
4. the *travel*, the signed change in that crease's *fold angle*, in degrees.

A fold angle of 0 is flat, negative is a mountain, positive is a valley, and ±180
is folded flat ([glossary](../docs/glossary.md#origami);
[travel](glossary-additions.md#running-a-sequence)).

- **Why move 4 names `FaceId 1`.** Because the file records no faces, they are
  *traced*: worked out from the creases by following edges round each region.
  `foldFrameWith` does this through `Fold.Crossings.withPlanarFaces`
  ([`Folding.hs:286-289`](../src/Senbazuru/Origami/Folding.hs#L286-L289)).
  Tracing finds the four corner triangles, then the central square. The recipe
  moves the square to the front, as `[centre, a, b, c, d]`
  ([`BlintzSequence.hs:44-47`](../study/fold-material/BlintzSequence.hs#L44-L47)).
  So the centre is `FaceId 0`, and the corners take ids 1–4 in the order they
  were traced, which is not the order they are folded in.
- **Why move 5 reuses move 1's ids.** Reopening turns the same hinge back, and
  no move in between added a crease, so no id changed.

Here are the same moves as a *sequence source*, the text an author writes. The
extension `.foldseq` is a placeholder
([glossary-additions](glossary-additions.md#the-sequence-language)).

```text
foldseq 1
title "Blintz base, then reopen one corner"
sheet "examples/blintz-base.fold"
anchor centre              # a region: strictly inside the traced central square

step c1 "Fold the south-east corner behind, to the centre." { fold behind corner south-east to centre }
step "Fold the north-east corner behind, to the centre." { fold behind corner north-east to centre }
step "Fold the north-west corner behind, to the centre." { fold behind corner north-west to centre }
step "Fold the south-west corner behind, to the centre." { fold behind corner south-west to centre }
step "Reopen the first corner." { unfold c1 }
```

| Move | Recipe tuple | Source | The crease both name |
| --- | --- | --- | --- |
| 1 | `EdgeId 8, FaceId 2, -180` | `fold behind corner south-east to centre` | (1/2, 0)–(1, 1/2), across the corner at (1, 0) |
| 2 | `EdgeId 9, FaceId 3, -180` | `… corner north-east to centre` | (1, 1/2)–(1/2, 1), across the corner at (1, 1) |
| 3 | `EdgeId 10, FaceId 4, -180` | `… corner north-west to centre` | (1/2, 1)–(0, 1/2), across the corner at (0, 1) |
| 4 | `EdgeId 11, FaceId 1, -180` | `… corner south-west to centre` | (0, 1/2)–(1/2, 0), across the corner at (0, 0) |
| 5 | `EdgeId 8, FaceId 2, 180` | `unfold c1` | move 1's, turned back |

Every crease in the last column is already in the fixture, as edges 8–11 in that
order, so no move adds a crease. The script below checks it.

Reading the source ([references](glossary-additions.md#references)):

- **`foldseq 1`** is the language version; `title` gives the whole run a title.
- **`step c1 "…"`** names the step `c1`, so that `unfold c1` can refer to it. The
  quoted text is its caption, the book's instruction under the figure. The other
  steps are unnamed.
- **`corner south-east`** uses the *sheet compass*, names fixed on the unfolded
  sheet with north as +y here. It always means the paper that started at (1, 0).
- **`P to Q`** is the fold line that lays P onto Q. Folding is a mirror across the
  fold line, so that line is exactly the points equally far from P and from Q.
  What moves is the [flap](glossary-additions.md#words-the-prds-narrow) containing
  P: the paper still joined to P if you imagine slicing along the line. Nothing
  is actually cut.
- **`behind`** is the alias of `mountain`. It is read from the *reader's side*,
  the side of the model facing the reader
  ([glossary-additions](glossary-additions.md#running-a-sequence),
  [D5](decisions.md#d5-presentation-and-the-readers-side)).
- **`anchor centre`** names the paper that stays still. Its comment calls `centre`,
  the point (1/2, 1/2), a region, and that is not a slip: an anchor fills a
  *region slot*, so it names the one face strictly containing the point
  ([slots](glossary-additions.md#references)). Here that face is the traced
  central square, with corners (1/2, 0), (1, 1/2), (1/2, 1) and (0, 1/2). The
  recipe gets the same effect by putting the central square first
  ([`BlintzSequence.hs:44-47`](../study/fold-material/BlintzSequence.hs#L44-L47)),
  because folding holds the first face still
  ([`Folding.hs:583-585`](../src/Senbazuru/Origami/Folding.hs#L583-L585)).
- **`sheet "…"`** is relative to the source file, here at the repository root.

**Checked against the fixture.** The script below uses exact fractions. For each
corner it lists the edges whose two ends are equally far from that corner and
from the centre, which by the mirror argument puts them on its fold line. It
prints each such edge's id, assignment, fold angle and ends:

```bash
python3 -c '
import json; from fractions import Fraction as F
d = json.load(open("examples/blintz-base.fold"))
V = [tuple(map(F, v)) for v in d["vertices_coords"]]; E = d["edges_vertices"]
c = (F(1,2), F(1,2))
same = lambda X, P: (X[0]-P[0])**2 + (X[1]-P[1])**2 == (X[0]-c[0])**2 + (X[1]-c[1])**2
show = lambda X: "(%s, %s)" % X
for name, P in [("south-east", (1,0)), ("north-east", (1,1)), ("north-west", (0,1)), ("south-west", (0,0))]:
    for i, (a, b) in enumerate(E):
        if same(V[a], P) and same(V[b], P): print(name, i, d["edges_assignment"][i] + str(d["edges_foldAngle"][i]), show(V[a]), show(V[b]))
on = lambda X, A, B: (B[0]-A[0])*(X[1]-A[1]) == (B[1]-A[1])*(X[0]-A[0]) and min(A[0],B[0]) <= X[0] <= max(A[0],B[0]) and min(A[1],B[1]) <= X[1] <= max(A[1],B[1])
print("centre on a vertex:", c in V, "| centre on an edge:", any(on(c, V[a], V[b]) for a, b in E))
'
```

One number in the output looks wrong and is not: the fixture stores every
corner crease at −180 (`M-180`), already folded. A plain `sheet` sets every
angle to 0 first, as the recipe does
([`BlintzSequence.hs:42`](../study/fold-material/BlintzSequence.hs#L42);
[D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)). The
file supplies the creases, not the starting state. It prints:

```text
south-east 8 M-180 (1/2, 0) (1, 1/2)
north-east 9 M-180 (1, 1/2) (1/2, 1)
north-west 10 M-180 (1/2, 1) (0, 1/2)
south-west 11 M-180 (0, 1/2) (1/2, 0)
centre on a vertex: False | centre on an edge: False
```

Each corner matches one edge, and that edge runs from one side of the square to
the next, so each fold line is exactly one existing crease and no move adds one.
`centre` lies strictly inside one face, which an anchor requires
([slots](glossary-additions.md#references),
[D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)).

**Which way the corners go.** The recipe folds them below the sheet
([`BlintzGallery.hs:3-4`](../study/fold-material/BlintzGallery.hs#L3-L4);
every corner `Below` the centre,
[`BlintzSequenceSpec.hs:108`](../test/BlintzSequenceSpec.hs#L108)). Seen from +z
that is a mountain, hence `behind`. The study has a second copy of this fold: the
`blintz` case in `cases.json`, a list of per-state angles the study executable
reads. It turns the same edges to +90° and then +175°, which is up
(`jq -c '.[3].id, [.[3].steps[] | .angles[8:12]]' study/fold-material/cases.json`).
Carried on to ±180°, both directions would give the same positions, because at
±180° a mountain and a valley are the same rigid motion
([A2-study-recipes-as-proto-dsl](research/A2-study-recipes-as-proto-dsl.md)
"(a) What each recipe does, and how each move is specified", F3). Which direction
this series treats as canonical is owner decision 8
([decisions §9](decisions.md#9-owner-decisions),
[10 §6](10-roadmap-risks-questions.md#6-owner-decisions)); its recommended default
is the recipe's `fold behind`, the spelling used above.

**Why ids cannot be the language.** Adding a crease discards every recorded face
([`Creasing.hs:265`](../src/Senbazuru/Fold/Creasing.hs#L265)) and re-traces them
in an order unrelated to the old numbering. Splitting an edge where a new crease
crosses it replaces that edge by its pieces and shifts every later edge id
([`Crossings.hs:310`](../src/Senbazuru/Fold/Crossings.hs#L310)). Only vertex ids
and *material coordinates*, where a point lay on the unfolded sheet, survive
([A1-library-fold-solver](research/A1-library-fold-solver.md) "(c) Identifiers
that do not survive, and the ones that do"). The blintz table works only because
none of its moves adds a crease.

## The two halves today

### The fold solver, in the library

It folds, checks and draws states, and checks one hinge turn at a time. It cannot
run a sequence source or a `Sequence`: nothing in it performs a list of moves.

| Piece | What it does | Where |
| --- | --- | --- |
| `Fold.Creasing.creaseAllAlong` | adds creases to a *crease pattern*, the flat sheet with its creases marked | [`Creasing.hs:138`](../src/Senbazuru/Fold/Creasing.hs#L138) |
| `Origami.ThroughLayers.creaseThroughLayers` | creases every layer under a line on a [flat-folded](glossary-additions.md#words-the-prds-narrow) model, returning "a crease pattern, never a folded form" (where the paper ends up) | [`ThroughLayers.hs:220-227`](../src/Senbazuru/Origami/ThroughLayers.hs#L220-L227) |
| `Origami.Folding.foldFrameWith` | turns fold angles into a `Folded`: the folded form, the *cut* pattern its ids refer to (creases split into pieces where they cross; no slit, which is what FOLD's `C` means), and one [rigid transform](../docs/glossary.md#geometry) per face | [`Folding.hs:283-322`](../src/Senbazuru/Origami/Folding.hs#L283-L322), [`:331`](../src/Senbazuru/Origami/Folding.hs#L331) |
| `Origami.Flap` | one hinge turn: `prepareFlap` picks it by ids, `checkFlap` checks the whole path for paper crossing paper, `flapAt` poses it | [`Flap.hs:154`](../src/Senbazuru/Origami/Flap.hs#L154), [`:249`](../src/Senbazuru/Origami/Flap.hs#L249), [`:290`](../src/Senbazuru/Origami/Flap.hs#L290) |
| `Origami.Surface` | what renderers and the study receive: topology, positions, material coordinates | [`Surface.hs:115`](../src/Senbazuru/Origami/Surface.hs#L115) |
| `Render.Steps.stepPage`, `Render.Gltf.renderSurfaceGlb` | a page of figures from `[Frame]`; a GLB (glTF's binary 3D file) from a surface | [`Steps.hs:90`](../src/Senbazuru/Render/Steps.hs#L90), [`Gltf.hs:219`](../src/Senbazuru/Render/Gltf.hs#L219) |

None of the CLI's six verbs (`render`, `info`, `check`, `export`, `crease`,
`fold`) reads a sequence source
([`Cli.hs:78-84`](../app/Senbazuru/Cli.hs#L78-L84),
[`:218-247`](../app/Senbazuru/Cli.hs#L218-L247)). `render --steps` draws an
existing *sequence*, a multi-frame FOLD file
([glossary](../docs/glossary.md#the-fold-format)), but performs no moves
([`:576-580`](../app/Senbazuru/Cli.hs#L576-L580)).

The only code that performs moves one after another is the study's recipes, and
they write a sequence down in four forms, of which the blintz table is one
([A2-study-recipes-as-proto-dsl](research/A2-study-recipes-as-proto-dsl.md)
"Summary"; [decisions §1](decisions.md#1-the-two-halves-today-and-what-connecting-them-means)):

- *angle tables*: each state a complete list of fold angles, one per edge by its
  position in the file (`cases.json`, read by `StudyCase`);
- *flap recipes*: moves naming ids of a cut pattern, like the blintz table
  (`BlintzSequence`, `HelmetSequence`, `CraneWing`, `FlapGallery`);
- *certified coupled recipes*: a stage and a progress fraction go through a
  formula to every angle, and each pose is checked against an exact proof
  (`CheckedPetal`, `CheckedBird`);
- *flat checkpoints*: material crease segments per milestone, with no motion
  implied (the frog guide in `BasicBases`).

Beside the recipes, `examples/` holds two multi-frame FOLD files. Run over
`examples/*.fold`, `jq '(.file_frames // []) | length'` prints 16 for
`bird-base-sequence.fold`, 2 for `quarter-fold-steps.fold` and 0 for every other
file. A file's *key frame* is its top-level object, which is both the file's
metadata and its first frame
([glossary-additions](glossary-additions.md#the-fold-format)).

- `bird-base-sequence.fold` is generated by the study "from those sixteen checked
  states" ([`examples/README.md:224-227`](../examples/README.md)). Its key frame
  holds only metadata (`jq '(.vertices_coords // []) | length'` prints 0), so its 16
  `file_frames` entries are its 16 states.
- `quarter-fold-steps.fold` is written by hand, as its `file_creator` says. **Its
  count looks one short and is not:** 2 `file_frames` entries hold 3 states,
  because its key frame is the flat sheet (9 vertices by the same `jq`) and
  counts as state 0 ([D16](decisions.md#d16-testing-and-acceptance)). A sequence
  file that `run` writes keeps its key frame for metadata only, so there state k
  is `file_frames[k]` ([D24](decisions.md#d24-states-figures-and-their-numbers)).

### The material study

`study/fold-material/` builds `senbazuru-material-study`
([`senbazuru.cabal:175`](../senbazuru.cabal#L175)), and the test suite also
compiles it ([`:193`](../senbazuru.cabal#L193)). Its solver has three defining
properties
([B-material-study-mechanics](research/B-material-study-mechanics.md)
"Summary"):

- **static**: it finds where the paper comes to rest (an *equilibrium*), with no
  notion of time;
- **zero-thickness**: the paper has no thickness;
- **held-boundary**: some points, the *holds*, are fixed exactly while the rest
  move.

A folded state is flat panels meeting at creases. The study splits each panel
into small triangles (a *mesh*) and moves some of their corners to where the
paper should go, which stretches the triangles around them. It then repeatedly
moves the free corners until every triangle edge is back to its length on the
unfolded sheet ([`FoldRelaxation.hs:3-8`](../study/fold-material/FoldRelaxation.hs#L3-L8)).
Springs resist each crease turning away from a preferred angle and each panel
bending. A penalty pushes apart layers that overlap, measured along one fixed
direction (`relaxPinnedContact`,
[`:256`](../study/fold-material/FoldRelaxation.hs#L256)). The rows for
[Gauss–Newton, line search and penalty contact](glossary-additions.md#material)
name the numerical methods. Separately, `CheckedBird` carries exact
[certificates](glossary-additions.md#assurance) for routes where several creases
turn together
([A2-study-recipes-as-proto-dsl](research/A2-study-recipes-as-proto-dsl.md)
"Summary").

These figures are recorded in repository notes, not re-measured
([B-material-study-mechanics](research/B-material-study-mechanics.md)
"Summary", "Capability table (question a)"):

- a crane wing bends and passes length, crease-angle and contact checks at 392
  and 1,192 triangles;
- releasing four body panels (faces) fails, unconverged after about 9 CPU
  minutes with 49 crossing triangle pairs;
- stiffnesses are illustrative, not measured from any paper, and results move
  2–4% under refinement;
- thickness is stored and not interpreted.

The only path from a rigid fold to bent paper is `craneSpreadWith`
([`CraneSpread.hs:80-115`](../study/fold-material/CraneSpread.hs#L80-L115)). It
takes one hand-built move, not a surface: `CraneWing`'s 90° turn of one crane wing
([`CraneWing.hs:80`](../study/fold-material/CraneWing.hs#L80)). From that move it
takes:

- the start state (`:85`);
- a rigid pose 30° into the 90° turn, written `30 / 90` because `flapAt` takes a
  fraction of the move (`:86`);
- the moving faces (`:88`);
- the hinge edge ids (`:91`, `:97`);
- the start state's accepted face orders, turned into lower/upper contact pairs
  along +z (`:108-114`).

It also derives *rest angles*, the angles its springs prefer (`:89-93`). The
hinge creases prefer that 30° pose's angles. Every other crease prefers −180° if
its assignment (its mountain or valley label) is mountain, and +180° otherwise.
See [gap-study-consumption-contract](research/gap-study-consumption-contract.md)
"(a) What the study takes from a move today". The two halves already share
`Origami.Surface`, `Origami.Contact` and `Origami.HingeSweep`.

### What connecting them means

Connecting them takes three new pieces, and two of them are contracts
([decisions §1](decisions.md#1-the-two-halves-today-and-what-connecting-them-means)).
[01 §2](01-architecture.md#2-what-crosses-the-boundaries) owns all three.

1. **The `Sequence` value.** One *first-order* Haskell value (plain data, no
   functions inside) that both front ends, the Haskell builder and the text
   parser, produce. It is a shared value, not a boundary between separately
   owned code, so it is not numbered as a contract
   ([01 §2.1](01-architecture.md#21-the-sequence-value)).
2. **Contract 1, the move record.** The library's *run* performs a `Sequence` and
   returns one *move record* per move, carrying that move's evidence
   ([glossary-additions](glossary-additions.md#running-a-sequence);
   [01 §2.2](01-architecture.md#22-contract-1-moverecord);
   [D14](decisions.md#d14-material-consumption)).
3. **Contract 2, the settle input.** The *material consumer* takes move records,
   never files. It resolves the holds, grips and rest angles an author named
   against one record into mesh vertex sets, target positions and a map from edge
   id to angle, and hands the solver that `SettleInput` with a `Surface V2`
   ([01 §2.3](01-architecture.md#23-contract-2-the-settle-input)). The solver
   returns a *settled* surface, bent by a static material solve. The consumer
   lives in the study until *graduation* moves it into the library
   ([glossary-additions](glossary-additions.md#material);
   [D15](decisions.md#d15-graduation-from-study-to-library)).

**The ids in contract 2 look forbidden and are not.** A sequence source never
names an edge or vertex id, yet `SettleInput` is full of them: they belong to one
refined surface for one call and never outlive it
([D14](decisions.md#d14-material-consumption)).

## Goals

| # | Goal | Owner |
| --- | --- | --- |
| 1 | The Haskell builder and the parser produce one first-order `Sequence`; the Haskell blintz equals the parsed one once source positions (*spans*) are stripped | [03](03-prd-embedded-dsl.md), [04](04-prd-sequence-source-and-cli.md) |
| 2 | Paper and lines are named by material references, resolved against the current state and recorded, never by id | [02](02-language-semantics.md) |
| 3 | Every move is checked by existing library code, and its move record keeps what was checked as an evidence value (a whole hinge turn, sample poses, the end state only, a presentation change, or nothing moved; [D10](decisions.md#d10-assurance-as-evidence-values)); a refusal message names the step and quotes the author's reference as the printer spells it ([D20](decisions.md#d20-errors)) | [02](02-language-semantics.md#12-refusal-catalogue), [05](05-prd-library-additions.md) |
| 4 | Existing verbs read a written [*sequence file*](glossary-additions.md#the-fold-format), what `run` writes, as ordinary FOLD; the 33 tracked goldens (`git ls-files test/golden \| wc -l`, run for this file) stay byte-identical, by [D16](decisions.md#d16-testing-and-acceptance)'s two `git diff --diff-filter` checks | [01](01-architecture.md), [09](09-testing-and-acceptance.md) |
| 5 | On a step page drawn from a sequence source, each figure carries its step's caption, arrows whose kind (valley, mountain, unfold) comes from move records rather than from comparing frames, a turn-over mark wherever the model is turned over, and fold-here lines for the creases the next move makes | [06](06-prd-step-diagrams.md) |
| 6 | The study [settles](glossary-additions.md#material) a step on request, starting from its move record; the settled result never replaces a rigid state | [07](07-prd-material-consumption.md) |
| 7 | Every output of a new mode (08's GLB modes and SVG line drawings, 07's settled files) names one level on each of the four [fidelity axes](glossary-additions.md#realistic-rendering), in glTF `extras.senbazuru.fidelity` or SVG `<desc>`; default outputs carry none | [08](08-prd-realistic-rendering.md) |
| 8 | The blintz and helmet flap recipes, `study/fold-material/BlintzSequence.hs` and `HelmetSequence.hs`, are each replaced by a sequence source whose run matches them, then deleted | [09](09-testing-and-acceptance.md#9-migrating-the-study-recipes) |

## Non-goals

[D18](decisions.md#d18-non-goals) decides these; the reasons are here.

| Out of scope | Why |
| --- | --- |
| A sequence solver, which finds the moves that fold a given crease pattern, or search over the vocabulary | Naming moves formally removes one obstacle in [no-sequence-solver.md](../docs/notes/no-sequence-solver.md): nobody had defined a set of moves to search. Another remains: many patterns are *collapsed*, brought together all at once rather than folded in order, so there is often no order to find |
| A general coupled-angle solver ([#55](https://github.com/avalonalex/senbazuru/issues/55)) as a prerequisite | Each *macro-move*, several creases turning at tied rates, derives and tests its own angle relation ([02](02-language-semantics.md)) |
| Sliding contact, touching layers sliding along each other | Study contact only keeps a supplied layer order (which paper lies over which) along one fixed direction ([B-material-study-mechanics](research/B-material-study-mechanics.md) "Capability table (question a)") |
| Automatic hold selection | Not yet general ([B-material-study-mechanics](research/B-material-study-mechanics.md) "Summary"); authors name holds against the record ([07](07-prd-material-consumption.md)) |
| Calibrated paper; wet folding (dampening thick paper so it can be shaped into curves that stay when it dries) | The study's stiffnesses are illustrative, not measured from any paper, so it models neither a particular paper nor what water does to one; its model is also static and zero-thickness |
| Pressure or inflation | Opening a closed pocket is its own problem, tracked as [#106](https://github.com/avalonalex/senbazuru/issues/106): a pushed-out bump does not keep the paper's lengths ([D-docs-issues-constraints](research/D-docs-issues-constraints.md) "A24") |
| Thickness as geometry | Research only. Rounding a second layer over a first crease stretches that layer's bent strip to three times its length, a 200% extension ([two-bends-need-more-than-radii.md](../docs/notes/two-bends-need-more-than-radii.md)); a display spacing called `--thickness` was shipped and removed ([paper-thickness.md](../docs/notes/paper-thickness.md)) |
| Step notes kept in FOLD; carrying the sheet's *vendor keys* (keys another tool added, which a frame keeps in `frameExtras`) through a run | Both wait on [#73](https://github.com/avalonalex/senbazuru/issues/73): today a change to a frame drops its `frameExtras`, the file's keys with the frame's |
| Resolving `frame_inherit`, a frame taking the keys it leaves unset from its parent frame | Decoded but not resolved ([fold-reference.md](../docs/fold-reference.md)); tracked as [#102](https://github.com/avalonalex/senbazuru/issues/102). A run writes every frame in full, so it never needs it ([D-docs-issues-constraints](research/D-docs-issues-constraints.md) "A27") |
| Reading OrigamiBench, FoldingAgent or Learn2Fold programs in v1 | These programs, from 2026 papers, name paper by index; an OrigamiBench action adds a crease between two vertex indices and moves no paper ([E1-prior-art-sequence-languages](research/E1-prior-art-sequence-languages.md) "D. The 2026 papers") |
| Recording an `expect refused` outcome in the written sequence file | [`expect refused`](glossary-additions.md#the-sequence-language) asserts that a move is refused, and a refusal claims nothing about a route taken, so it writes no move record and no state; `run --report` prints the outcome ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)) |

## The shape

**SKETCH.** Planned module names; arrows are data flow, not types. M-numbers are
the [milestones below](#what-you-can-see-at-each-milestone). The picture is
[decisions §2](decisions.md#2-shape)'s; [01 §1](01-architecture.md#1-the-module-graph)
has the module layers and which module may import which.

```
 Haskell author                          text author (.foldseq source)
  Sequence.Build (State, names only)     Fold.Load.readSequenceText -> Text
          \                               Sequence.Parse (megaparsec, pure)
           v                                   v
          Sequence.Syntax : Sequence  (first-order, spans)   <-> Sequence.Pretty
                         |
          Sequence.Check (names, kinds, arity, units; no geometry)
          Sequence.Elaborate (let; keeps provenance)
                         |
          Sequence.Run  (Budget, RunSettings, sheets) over Fold.* / Origami.*
                         |
          Run = records + states   (Sequence.Record)          <- contract 1
             |              |               |                     |
   Sequence.Write     Render.Sequence   Render.Gltf        Sequence.Material (study until M8)
   (FoldFile around   (StepNote per     (surfaces;           settleStep :: SettleSpec -> MoveRecord
    writtenStates)     state, then       new modes, M7)          -> Either SettleStepError Settled
                       stepPageWith)                                 |  SettleInput      <- contract 2
                                                                     v
                                                              Material.Settle.settle (library from M8)
```

The two material functions have these types
([D14](decisions.md#d14-material-consumption),
[01 §2.3](01-architecture.md#23-contract-2-the-settle-input)):

```haskell
settleStep :: SettleSpec -> MoveRecord -> Either SettleStepError Settled
settle :: SettleInput -> Surface V2 -> Either SettleError Settled
```

**Two error types, on purpose.** `Material.*` knows no moves, so a refusal that
names one, such as a `settle` block on a step where nothing moved, is a
`SettleStepError`, and `SettleStepError` wraps `SettleError` for a solve that
fails ([D14](decisions.md#d14-material-consumption)).

The picture has four stages:

1. **Build.** Both front ends produce the same `Sequence`, a *deep embedding*:
   first-order data, so it can be compared, printed and saved
   ([glossary-additions](glossary-additions.md#code-and-tests)).
2. **Check.** `Sequence.Check` refuses the mistakes it can find without any
   geometry: unknown names, wrong kinds and argument counts, unit mistakes. A
   zero denominator such as `1/0` never reaches it: numbers in a source are
   exact fractions, none can hold one, and the parser refuses it
   ([D12](decisions.md#d12-the-text-syntax)).
   `Sequence.Elaborate` expands shorthand such as `let`.
3. **Run.** The *runner* folds move by move with the existing `Fold.*` and
   `Origami.*` code, threading a *fold state*
   ([glossary-additions](glossary-additions.md#running-a-sequence)). It returns a
   `Run`: the start state, one move record per move, each step's outcome, and
   where the run stopped, if it did. The fold state stays inside `Sequence.Run`,
   so no renderer can come to depend on it
   ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).
4. **Consume.** The writer produces the sequence file and `Render.Sequence` the
   step page, both through `Sequence.Record.writtenStates`, so the page draws
   exactly the frames the file holds
   ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).
   `Render.Gltf` writes the GLB, and the material consumer settled surfaces.

## How the three features connect

| Feature | PRD | Reads | Produces |
| --- | --- | --- | --- |
| 1. Embedded DSL | [03](03-prd-embedded-dsl.md) | Haskell code | a `Sequence` |
| 2. Sequence source and `run` | [04](04-prd-sequence-source-and-cli.md) | a `.foldseq` file and the sheet files it names | a `Sequence`, then `.fold`, `.svg`, `.glb` through the runner |
| 3a. Material consumption | [07](07-prd-material-consumption.md) | move records and their `settle` blocks | settled surfaces, as illustrations |
| 3b. Realistic rendering | [08](08-prd-realistic-rendering.md) | surfaces from records or settles | new GLB modes, an exact SVG line drawing, animation |

All four rest on [02](02-language-semantics.md) (semantics),
[05](05-prd-library-additions.md) (solver changes) and
[06](06-prd-step-diagrams.md) (pages). Features 1 and 2 are one language with two
spellings: pretty-printing a checked `Sequence` and parsing the text gives back
its *canonical* form, the one spelling the parser produces for each shape, once
spans are stripped ([D12](decisions.md#d12-the-text-syntax)). Feature 3 reads a
move record and a settle spec (the parsed `settle` block), never a file, and a
`settle` block binds to its step's last moving record, not to a source position
([D14](decisions.md#d14-material-consumption)). So a `Sequence` built in Haskell
settles exactly as one read from a file does.

## What "realistic" means, honestly

Realism here is four independent
[fidelity axes](glossary-additions.md#realistic-rendering)
([D19](decisions.md#d19-realistic-rendering)): geometry, motion,
appearance and lines. Today every output sits on the lowest level of each: rigid
panels, no motion, two flat colours, book notation.
[08](08-prd-realistic-rendering.md#what-this-makes-realistic-and-what-it-does-not)
has the levels above that and what each changes.

On rigid moves, little of that is visible. Every panel is flat, so smooth
shading gives the flat normals viewers already compute
([`Gltf.hs:49-50`](../src/Senbazuru/Render/Gltf.hs#L49-L50)). Every outline lies
on a crease or boundary today's drawings already show
([G-realistic-rendering-and-simulation](research/G-realistic-rendering-and-simulation.md)
"D. SVG wireframe of a 3D paper surface", finding 21). **So for rigid moves the
new outputs add motion, texture coordinates and lines, not bent paper.**

Settling alone does not bend paper either: a checked rigid state is already an
equilibrium, so a [settle](glossary-additions.md#material) must name what differs
or is refused. **No bent paper is reachable from the `senbazuru` CLI before M8.**
Until then it comes only from the study: at M6 from `senbazuru-material-study
--sequence SOURCE DIR`, and at M7a as a new GLB mode on meshes the study already
produces.

## What you can see at each milestone

| M | New to run | What you see |
| --- | --- | --- |
| M0 | nothing | decisions recorded in `docs/`, issues amended, glossary rows moved in |
| M1 | `senbazuru run --check SOURCE` | refusals that need no geometry, at `path:line:col`; a Haskell `Sequence` printed as source; a source handed to `render` refused as a sequence source, not FOLD |
| M2 | `run -o x.fold`, `-o x.glb`, `--report` | sequence files of checked rigid states (blintz, helmet); the final state as today's two-colour GLB; each move's evidence |
| M3 | `run -o x.svg` | a book-style step page: captions, arrows from move records, turn-over symbols, fold-here lines |
| M4 | folds through some layers; `start folded`, `checkpoint`, `repeat` | the first part of the crane-wing recipe as a sequence source; the quarter fold authored from `sheet square`, which closes [#60](https://github.com/avalonalex/senbazuru/issues/60) |
| M5 | `collapse`, `rabbit-ear`, `petal` | the bird base, and the crane's opening from a square |
| M6 | `senbazuru-material-study --sequence SOURCE DIR` | the first bent paper from a sequence source: settled illustrations beside the rigid outputs |
| M7a | a new GLB mode | smooth shading and texture coordinates on the study's existing bent meshes (crane spreading, wing bending), the first visible realism |
| M7b | animated GLB; `--lines`; a glTF crease-line spike (a throwaway experiment testing whether viewers draw glTF line primitives) | checked rigid routes in motion; an exact SVG line drawing. On rigid moves: motion and lines, not realistic paper |
| M8 | `run --settle`, `--allow-unsettled` | bent paper from the `senbazuru` CLI |
| R | nothing | thickness, springback and unheld equilibrium remain research |

Order: M1 → M2; M2 → M3 and M2 → M4; M5 needs both M3 and M4; M4 → M6 → M8;
M2 → M7b. M7a depends on nothing. Inside that order, two of M0's recorded-text
changes have deadlines ([decisions §3](decisions.md#3-recorded-text-this-design-changes)):
the one saying a sequence source is a program, not an input format, lands no
later than M1's parser PR, and
[#111](https://github.com/avalonalex/senbazuru/issues/111)'s amendment, with
`Fold.Query.atRest` (the one threshold below which a fold angle counts as
unfolded, [D4](decisions.md#d4-written-frames-follow-the-state-rule)), before
M2's writer.
[#60](https://github.com/avalonalex/senbazuru/issues/60), the roadmap issue for a
vocabulary of moves, closes in M4's last PR, after M3 has merged: its amended
done-when includes authoring the quarter fold from `sheet square`, whose page
needs M3's `motionsAcross` (matching states whose crease graphs differ) and
whose second step needs M4's `creaseLayersThrough` (creasing some layers)
([D16](decisions.md#d16-testing-and-acceptance)).
[Decisions §8](decisions.md#8-milestones) lists every ordering constraint, and
[10](10-roadmap-risks-questions.md#1-milestones) owns each milestone's contents,
issues, gates and risks. Read [01](01-architecture.md) and
[02](02-language-semantics.md) next.
