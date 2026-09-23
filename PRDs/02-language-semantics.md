# 02 — Language semantics

Written 2026-09-14 against `568dcb6`. The cited source lines were re-read, and the
file reconciled with [decisions.md](decisions.md), on 2026-09-15.
[00](00-overview.md) introduces the series. Nothing here is implemented.

This file is the specification both front ends share. A `Sequence` built in
Haskell ([03](03-prd-embedded-dsl.md)) and one parsed from a *sequence source*
([04](04-prd-sequence-source-and-cli.md)) mean the same thing because they mean
what this file says. It covers:

- the state a run threads, and how it starts;
- units, and how references resolve;
- the reader's side, moves, and which layers a move takes;
- stacking relations, macro-moves, and figures holding several moves;
- `repeat`, `checkpoint`, `not modelled` and `expect refused`;
- assurance, the rules for written frames, and the refusal catalogue.

Other files own the rest:

| Topic | Owner |
| --- | --- |
| Library signatures | [05](05-prd-library-additions.md) |
| Grammar | [04](04-prd-sequence-source-and-cli.md) |
| Module layering and the record contract | [01](01-architecture.md) |
| Pages | [06](06-prd-step-diagrams.md) |
| Settles | [07](07-prd-material-consumption.md) |

Examples use the source spelling. [decisions.md](decisions.md) is the decision
record, and where this file and it disagree, the record wins. This file specifies
the record's decisions [D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)
to [D11](decisions.md#d11-stacking-choices-are-relations),
[D20](decisions.md#d20-errors) to
[D22](decisions.md#d22-figures-holding-several-moves) and
[D24](decisions.md#d24-states-figures-and-their-numbers), and links each rule to
the decision that settles it. Owner decisions are numbered as in
[decisions §9](decisions.md#9-owner-decisions) and
[10 §6](10-roadmap-risks-questions.md#6-owner-decisions). Type names come from
[decisions §5](decisions.md#5-type-sketch) and are **SKETCH**.

Terms are defined in one clause and linked to
[glossary-additions.md](glossary-additions.md) or
[the glossary](../docs/glossary.md). Evidence is tagged:

| Tag | Meaning |
| --- | --- |
| **[code]** | lines read at the cited place |
| **[jq]**, **[py]** | a fixture measurement; the command is in the [appendix](#appendix-checks-behind-the-examples) |
| **[py re-impl]** | the research's Python re-implementation of folding, not senbazuru |
| **[prd]** | a measurement made by another PRD file, whose linked section holds the command |
| **[reasoned]** | worked out from cited code, not run |

## 1. One run, walked through

Here is the quarter fold, as [decisions §7](decisions.md#7-examples) writes it:

```text
foldseq 1
title "A square folded into quarters"
sheet "examples/quarter-fold-steps.fold"
anchor (3/4, 1/4)          # south-east quarter, which neither step moves

step half "Fold the left half behind, onto the right." {
  fold behind edge west to edge east
}
step quarter "Fold the top half down in front, onto the bottom." {
  fold in front edge north to edge south
}
closing "Folded into quarters."
```

The fixture is a unit square. Four interior creases meet at vertex 8, (1/2, 1/2).
A *face* is one flat region between creases, and its *ring* is its vertex ids in
order round it [jq, [check Q](#check-q)].

| Face | Ring | Quarter of the sheet |
| --- | --- | --- |
| 0 | `[8,4,1,5]` | south-east |
| 1 | `[8,5,2,6]` | north-east |
| 2 | `[8,6,3,7]` | north-west |
| 3 | `[8,7,0,4]` | south-west |

A *state* is one entry of the written file's `file_frames`, numbered from 0 by its
index ([D24](decisions.md#d24-states-figures-and-their-numbers)). State 0 is the
flat start, state 1 follows step `half`, and state 2 follows step `quarter`. The
fixture lines up with that numbering: its key frame is state 0 and its
`file_frames[k − 1]` is state k, so [check Q](#check-q)'s "frame n" is state n.

| Edge | Runs from (1/2, 1/2) to | File assignment | Joins faces | Angle in states 0, 1, 2 |
| --- | --- | --- | --- | --- |
| 8 | (1/2, 0) | M | 0, 3 | 0, −180, −180 |
| 9 | (1, 1/2) | V | 0, 1 | 0, 0, 180 |
| 10 | (1/2, 1) | M | 1, 2 | 0, −180, −180 |
| 11 | (0, 1/2) | M | 2, 3 | 0, 0, −180 |

A *fold angle* is 0 when flat, negative for a mountain, and ±180 folded flat
([glossary](../docs/glossary.md#origami)). The *runner*, `Sequence.Run`, does this:

1. **Start** (§2.2). Plain `sheet` reads the file's key frame and sets every angle
   to 0. It keeps M, V, M, M on edges 8–11 as *intent assignments*: what each
   crease will fold as ([glossary-additions](glossary-additions.md#the-fold-format)).
   `anchor (3/4, 1/4)` fills a *region* slot, so it must be strictly inside one face.
   It is inside face 0. That face goes first in the working pattern and is held still.
2. **Step `half`.**
   - *Line.* `edge west to edge east` is O3, the fold putting one line onto another
     (§4.3). The two lines, x = 0 and x = 1, are parallel, so there is one solution:
     x = 1/2.
   - *Hinge.* That line lies along existing edges 8 and 10, so no crease is added.
     Those edges are the *hinge*, the line the paper turns about.
   - *What moves.* The side containing edge west's interior: faces 2 and 3, joined
     across edge 11. The anchor face is not among them.
   - *Direction.* A fold's *sense* is valley or mountain as the author wrote it,
     seen from the reader's side: `in front` is valley and `behind` is mountain.
     The syntax tree spells them `ValleyFold` and `MountainFold`, so that they do not
     clash with `Fold.Types`' `Valley` and `Mountain`
     ([D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders)).
     Here it is mountain, and the reader sees the sheet's top: coloured side up is
     the default, and nothing has turned the model over.
     The stationary faces 0 and 1 both show their tops, so both hinge segments
     change by −180. (Since owner decision 13 the moving faces decide it, and
     faces 2 and 3 show their tops too:
     [D5](decisions.md#d5-presentation-and-the-readers-side).)
   - *Against the fixture.* State 1 has −180 on edges 8 and 10, vertices
     0, 3 and 7 moved, and faces 2 and 3 have *signed area* −0.25 (the shoelace
     area, positive when a ring runs anticlockwise). Their rings now run clockwise,
     so they are turned over [jq].
3. **Step `quarter`.**
   - *Line.* In state 1, edge north's two material segments both lie at
     (1, 1)–(1/2, 1): vertex 3, corner (0, 1), is now at (1, 1) [jq]. They are
     collinear, so `edge north` is the line y = 1 (§4.6). O3 with y = 0 gives y = 1/2,
     along existing edges 9 and 11.
   - *What moves.* Edge north's interior lies in faces 1 and 2, which are joined
     across edge 10. That is one *flap*, two layers thick: the paper still joined to
     it once the hinge is cut
     ([glossary-additions](glossary-additions.md#words-the-prds-narrow)).
   - *Direction.* `in front` means valley as seen.

**The line that looks like a typo.** State 2 has edge 9 at +180 and edge 11 at
−180, although the step says valley.

- Edge 9's stationary face, face 0, shows its top to the reader.
- Edge 11's stationary face, face 3, was turned over by step `half`.
- A valley seen on the underside of paper is a mountain on its top, so one physical
  fold writes opposite signs on the two layers
  ([`ThroughLayers.hs:36-45`](../src/Senbazuru/Origami/ThroughLayers.hs#L36-L45),
  [`Flap.hs:14-16`](../src/Senbazuru/Origami/Flap.hs#L14-L16)).
- Face 0's vertices 1, 4, 5 and 8 never move [jq].

[01 §5.6](01-architecture.md#56-travel-per-segment) works the signs out segment by
segment.

The fixture is 2D, and at ±180 a mountain and a valley put the paper in the same
place, so its coordinates cannot show which way the paper turned. The senses above
are therefore [reasoned] from folding's rule that a positive angle lifts the child
face towards +z
([`Folding.hs:39-49`](../src/Senbazuru/Origami/Folding.hs#L39-L49)), not measured.

4. **Written file.** A metadata-only key frame, then the three states as
   `file_frames[0]` to `file_frames[2]`, written by §11's rules. Without the `anchor` line, step `half` would re-anchor (§2.3).

## 2. The state a run threads

### 2.1 What a fold state holds

`FoldState` is abstract and lives in `Sequence.Run`. A finished `Run`, defined in
`Sequence.Record`, does not hold it: a reader of a run gets records and displayed
states, never the working pattern
([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs),
[D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).

| Part | What it is | Why |
| --- | --- | --- |
| *Working pattern* | The crease pattern cut at crossings, in material coordinates: rings counter-clockwise, the anchor's face first, intent assignments, explicit `edges_foldAngle`, and the accepted orders as `faceOrders` | Folding holds the first face still ([`Folding.hs:577-585`](../src/Senbazuru/Origami/Folding.hs#L577-L585)) and reads explicit angles first ([`:507-512`](../src/Senbazuru/Origami/Folding.hs#L507-L512)) |
| *Directional layer requirements* | Face pairs a material solve keeps in order along a direction ([glossary-additions](glossary-additions.md#running-a-sequence)), where a move supplied them | The material consumer reads them ([07](07-prd-material-consumption.md)) |
| *Anchor* | A material point | Face ids do not survive creasing ([A1](research/A1-library-fold-solver.md) "(c) Identifiers that do not survive, and the ones that do") |
| *Anchor placement* | A `Rigid`: a proper rotation, identity at start, possibly built with trigonometry | Keeps the picture still across a re-anchor (§2.3) |
| *Presentation* | A `Rigid` | §5 |
| Landmark table | Marks and step names | §4.5 |
| Crease provenance | Which step made each material segment | So that `crease of NAME` resolves |
| Macro bindings | §8 | So that `continue` resumes |

*Raw* positions are what `foldFrameWith` gives for the working pattern, with the
first face at its flat position. Displayed positions are presentation `after` anchor
placement `after` raw positions, where ``a `after` b`` does `b` first
([`Rigid.hs:90`](../src/Senbazuru/Geometry/Rigid.hs#L90)).

**Intent at angle 0 is kept on purpose**
([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)). A
precrease that lies flat stays M or V on the working pattern. That departs from `Fold.Creasing`'s "A valley with an angle of
nought is not a valley" ([`Creasing.hs:281-286`](../src/Senbazuru/Fold/Creasing.hs#L281-L286)).

- *Why it is needed.* `Flap` turns only M, V or U
  ([`Flap.hs:187`](../src/Senbazuru/Origami/Flap.hs#L187)), and a collapse binds on
  direction (§8.2).
- *Why it is safe.* Folding reads explicit angles before assignments. Stacking takes
  a crease's direction from a nonzero angle first, and from its assignment only at 0
  ([`Stacking.hs:705-727`](../src/Senbazuru/Origami/Stacking.hs#L705-L727)). A crease
  at 0 is a *tortilla*, paper continuing flat across it, and a tortilla orders
  nothing ([`:632-639`](../src/Senbazuru/Origami/Stacking.hs#L632-L639)).

Written frames restore the FOLD rule (§11).

### 2.2 Starting

`Sequence.Run.sheetState :: SheetStart -> Frame -> Either SheetProblem FoldState`
(**SKETCH**) is pure, and the CLI only loads bytes. The runner wraps a
`SheetProblem` as `SheetRefused`, with the sheet path as written (§12). The rules
are [D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)'s.

1. **Which frame.** The sheet is the file's key frame, never a `file_frames` entry.
   Two key frames are refused:
   - one with no vertices, as `SheetHasNoVertices`, naming how many `file_frames`
     the file has;
   - one whose `Query.frameKind` is `FoldedForm`, as `SheetAlreadyFolded`. That is
     the test folding uses for `AlreadyFolded`
     ([`Folding.hs:338-339`](../src/Senbazuru/Origami/Folding.hs#L338-L339)).
2. **Clean-up.** Drop `faceOrders` and `frameExtras`, apply `withPlanarFaces`, and
   normalise the rings.
3. **Intent.** M and V are kept. An F crease whose file angle is outside ±τ becomes
   M below −τ and V above τ, where τ is `Fold.Query.atRest` (§11). This is
   `StudyCase`'s rewrite of F, which uses 1e-10
   ([`StudyCase.hs:207-210`](../study/fold-material/StudyCase.hs#L207-L210)). B, C,
   J and U are kept as written, so **a U crease stays U whatever its angle**. The
   two letters are treated differently on purpose
   ([C17](decisions.md#changes-since-draft-v2)):
   - F at a nonzero angle contradicts itself, since F means unfolded, so the angle
     is trusted over the letter;
   - U at a nonzero angle is consistent, since U says only that the direction is
     undecided. Intent is a claim about how a crease was made, and the runner must
     not invent it.
4. **Angles.** They depend on how the sheet is named:
   - *plain `sheet`* sets every angle to 0, as the *recipes* do. The recipes are
     the hand-written study programs in `study/fold-material/` that fold fixtures
     by hard-coded edge and face ids
     ([`BlintzSequence.hs:42`](../study/fold-material/BlintzSequence.hs#L42),
     [`HelmetSequence.hs:39`](../study/fold-material/HelmetSequence.hs#L39));
   - *`start folded { … }`*, a header field, keeps angles as `foldAnglesOf` reads
     them: explicit angles first, otherwise M −180, V +180 and everything else 0
     ([`Folding.hs:507-533`](../src/Senbazuru/Origami/Folding.hs#L507-L533)). It then
     chooses a *stacking*, one complete layer order, by §7;
   - *`sheet square`* is the unit square: 4 vertices, 4 border edges, 1 face.

| Sheet [jq] | What the file records | Plain `sheet` starts as | `start folded` starts as |
| --- | --- | --- | --- |
| `blintz-base.fold` | −180 on edges 8–11, all M; no faces | a flat square with four intent-M creases | the finished blintz |
| `bird-base.fold` | 16 nonzero angles (12 M, 4 V); 4 F at 0 | flat | the finished bird base |
| `crane.fold` | no angle array; 58 M, 41 V, 20 F, 10 B; 72 faces | flat | ±180 from the assignments, F at 0 |
| `quarter-fold-steps.fold` | key frame all 0 | flat | flat |

Without the zeroing, a blintz sequence would start already folded.

### 2.3 The anchor

**Default.** The *anchor* is the material point whose face stays still
([glossary-additions](glossary-additions.md#running-a-sequence)). By default it is
the *vertex mean*, the average of the corner coordinates, of the initial pattern's
largest face. Ties go to the lowest vertex mean, then the leftmost. This is the rule
`StudyCase` uses to pick its held panel: it ranks faces by area, then by negated
mean y, then by negated mean x
([`StudyCase.hs:242-247`](../study/fold-material/StudyCase.hs#L242-L247)). It is a
vertex mean, not an area centroid
([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs),
[C20](decisions.md#changes-since-draft-v2)). The two agree on triangles and squares,
which are all this file's examples use, but not on a general quadrilateral. A header
line `anchor P`, a region slot, overrides the default. A default vertex mean that is
not strictly inside its own face is refused, asking for `anchor P`; the vertex mean
of a convex face always lies inside it, so only a non-convex face can meet this
[reasoned]. Two fixtures [py]:

- **Blintz.** The central square has area 1/2 and each corner 1/8. The default is
  (1/2, 1/2), the same as `anchor centre`.
- **Quarter fold.** All four faces have area 1/4. Faces 0 and 3 have the lowest
  vertex means, at y = 1/4, and face 3's (1/4, 1/4) is further left. So the default
  is face 3.

**Re-anchoring**
([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)). When
a move's moving side contains the anchor's face, the runner re-anchors instead of
refusing:

1. The new anchor face is the stationary face beside the hinge with the largest
   material area. Ties go to the lowest, then leftmost, material vertex mean, never
   to face id. Its vertex mean becomes the anchor. The runner records it, and
   `--report` prints it.
2. Read h, that face's placement in the current raw fold, before any reordering.
3. Set anchor placement := anchor placement `after` h.
4. Put that face first, re-map orders and requirement pairs to the new face ids,
   and refold.
5. Join-check the displayed positions (§2.4, invariant 6).

It is refused as `ReanchorNotFlat` if the new face's displayed normal is not ±ẑ.
That keeps the reader's side defined (§5). The move `anchor P` does the same on
demand.

**Why nothing jumps** [reasoned from
[`Folding.hs:577-585`](../src/Senbazuru/Origami/Folding.hs#L577-L585)]. Rooting the
raw fold at the new face composes every face placement with h⁻¹. Composing the
anchor placement with h cancels it.

**Worked example.** Drop the `anchor` line from §1.

- Step `half` moves face 3, the default anchor.
- The stationary faces beside edges 8 and 10 are faces 0 and 1, of equal area. Face
  0's vertex mean (3/4, 1/4) is lower, so that becomes the new anchor.
- The sheet is flat before the move, so h is the identity and nothing on the page
  moves.

Re-anchoring is the recommended default of
[owner decision 3](10-roadmap-risks-questions.md#6-owner-decisions); refusing is its
alternative.

**An anchor that a new crease passes through**
([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs),
[C19](decisions.md#changes-since-draft-v2)). Creasing can put the anchor point on a
crease, where it no longer fills a region slot. So after creasing, if the anchor
point is not strictly inside one face, the anchor moves to the vertex mean of the
largest face that contains the old point in its closed polygon and that this move
does not turn. Ties go to the lowest, then leftmost, vertex mean. Creasing moves no
paper, so anchor placement is unchanged, and the record notes the move.

*Example* [reasoned, with the areas and vertex means checked by python3 using
`fractions`; **UNVERIFIED** as runner output]. `sheet square` with no `anchor` line
has its default anchor at (1/2, 1/2), the centre of its one face. The crane opening
of [decisions §7](decisions.md#7-examples) has a step `diagonals` whose first move
creases `[corner south-west, corner north-east]`, through that point, and turns the
half containing corner south-east. That step creases both of its diagonals in one
batch (§6.5), so after creasing the sheet is four triangles of area 1/4 meeting at
(1/2, 1/2). The first move leaves two of them unturned: the west triangle (0, 0),
(1/2, 1/2), (0, 1), with vertex mean (1/6, 1/2), and the north triangle (0, 1),
(1/2, 1/2), (1, 1), with vertex mean (1/2, 5/6). The lower one wins, so the anchor
moves to (1/6, 1/2). **That is not a slip for (1/3, 2/3).** (1/3, 2/3) is the vertex
mean of the half-square triangle (0, 0), (1, 1), (0, 1), which would be the unturned
face only if the first diagonal were creased on its own. The second move turns the
half containing corner south-west, which includes the west triangle, so it re-anchors
by the rule above. The stationary north and east triangles tie on area, and the
east one's vertex mean (5/6, 1/2) is lower. Neither §1's source nor
[09 §2.3](09-testing-and-acceptance.md#23-test-2-authoring-from-sheet-square-m3-and-m4)'s
authoring test meets this rule: both write `anchor (3/4, 1/4)`, which no crease of
theirs passes through.

### 2.4 The seven invariants

These are [D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)'s.
They come from the recipes' shared *handoff* policy, the rules for passing one
move's result to the next
([A2](research/A2-study-recipes-as-proto-dsl.md) "(b) The shared handoff policy:
invariants an interpreter must enforce").

| # | Invariant | What goes wrong without it |
| --- | --- | --- |
| 1 | Carry accepted angles and orders onto the working pattern. Never feed folded coordinates back as material ([`BlintzSequence.hs:63`](../study/fold-material/BlintzSequence.hs#L63)) | The folded sheet is folded a second time |
| 2 | Drop `frameExtras` and stale faces on every transform ([`Creasing.hs:265-267`](../src/Senbazuru/Fold/Creasing.hs#L265-L267)) | Stale faces name the wrong paper |
| 3 | Refold after every handoff, and never patch a `Folded`, folding's result (the cut pattern and where it folds to). Orders reach `Flap` by sitting on the working pattern before the fold. `foldFrameWith` copies them, and it may reverse a face's ring. A `faceOrders` sign is read against its second face's normal, so it then flips every order whose second face it reversed (missing that was [#78](https://github.com/avalonalex/senbazuru/issues/78); [`Folding.hs:385`](../src/Senbazuru/Origami/Folding.hs#L385), [`:482-486`](../src/Senbazuru/Origami/Folding.hs#L482-L486)). The blintz does this ([`BlintzSequence.hs:63-64`](../study/fold-material/BlintzSequence.hs#L63-L64)). A state's first stacking: fold, solve on `foldedFrame`, record the orders on the working pattern, refold. Never attach orders to a `Folded` as [`CraneWing.hs:79`](../study/fold-material/CraneWing.hs#L79) does | `Flap`'s start check ignores orders ([`Flap.hs:169-181`](../src/Senbazuru/Origami/Flap.hs#L169-L181)), so a patch changing only orders passes unseen |
| 4 | Re-resolve every id after a topology change | Creasing empties faces, and cutting shifts edge ids |
| 5 | Anchor by material point, and re-anchor as in §2.3 | Re-tracing can put a different face first |
| 6 | Join-check every step. Positions must agree within 1e-12 × `modelSpan` ([`BlintzSequence.hs:69`](../study/fold-material/BlintzSequence.hs#L69)). Angles, edge lists, face rings, orders and material coordinates must be exactly equal, as at [`CheckedBird.hs:145-146`](../study/fold-material/CheckedBird.hs#L145-L146). `CheckedBird` compares rings as written; the runner compares them as `map sort facesVertices`, so a re-trace that starts a ring at another vertex is not a break | A changed fixture silently inserts a rigid jump ([`BlintzSequence.hs:13-15`](../study/fold-material/BlintzSequence.hs#L13-L15)) |
| 7 | Never re-solve a stacking silently (§7) | The crane has five stackings ([several-stackings.md](../docs/notes/several-stackings.md)), and a re-solve may pick another |

Every comparison names its tolerance, and all but two already exist in code. The new
ones are `RunSettings.nearMissBand` (§4.4) and the 1e-12 of
[05](05-prd-library-additions.md)'s `isProperRotation` (§5.2).
Each checked step costs about seven `foldFrameWith` calls, counted from code, not
timed ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
"From reading the code (counts, not timings)").

## 3. Numbers

Every number in a sequence is one of four kinds
([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)):

| Kind | Where written | Meaning |
| --- | --- | --- |
| *Sheet length* | `(u, v)`, lengths | (u, v) = ((x − xmin)/s, (y − ymin)/s). Here s is the larger side of the unfolded sheet's bounding box and (xmin, ymin) its south-west corner, one scale on both axes. The resolver converts once and records s ([glossary-additions](glossary-additions.md#references)) |
| Model units | only inside `model [...]` | the current model's coordinates, as seen |
| Degrees | always with `°` (ASCII `deg`) | fold amounts, `until`, pose `at`, `sample` |
| Pure ratio | `fraction r along`; route progress | a number in [0, 1] |

Numbers are exact `Rational`s in the syntax tree and become `Double` once, at
resolution. Physical lengths appear only in the `material { … }` block, each with a
unit suffix ([07](07-prd-material-consumption.md)).

**Example** [py, [check X](#check-x)].

- `blintz-base.fold` spans [0, 1]², so s = 1 and `(u, v)` is simply `(x, y)`.
- `examples/bird-base.cp` has 26 segments with x and y in [−200, 200], so s = 400.
  There `(1/2, 1/2)` is model (0, 0), and `(29/50, 2/5)` is model (32, −40). The box
  is symmetric about 0, so the `.cp` import's y-flip does not change it (AGENTS.md,
  "Three y-flips").

One source names points by the same fractions on either sheet. Written output stays
in model units.

## 4. References

A *reference* names paper or a line. It is never a raw id, and it is resolved
against the current state and recorded
([glossary-additions](glossary-additions.md#references)).

### 4.1 Material names

| Name | Material point or line | On a unit square |
| --- | --- | --- |
| `corner south-west`, `south-east`, `north-east`, `north-west` | corners of the sheet's box | (0, 0), (1, 0), (1, 1), (0, 1) |
| `edge south`, `east`, `north`, `west` | the boundary between two corners | y = 0, x = 1, y = 1, x = 0 |
| `centre` | centre of the box | (1/2, 1/2) |

North is +v on the unfolded sheet as the file draws it. These *sheet compass* names
never change when the model turns or a flap folds over.

**Compass names need a square outline**
([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)). `corner X`
is refused unless a boundary vertex lies at that corner of the sheet's bounding box
within `Fold.Faces.tolerance` (§4.4), and `edge S` unless boundary edges cover that
side of the box. `centre` and `(u, v)` are always defined. On `crane.fold` the
corners are 5.8e-15 off, inside the 1.41e-9 tolerance
([07](07-prd-material-consumption.md#one-move-fed-by-hand)'s box check) [prd].

The words `left`, `right`, `top`, `bottom`, `front` and `behind` are reserved for
what the reader sees. The parser refuses them where a material feature is expected,
and its message gives the compass spelling
([04](04-prd-sequence-source-and-cli.md)). Messages and records also say where a
feature currently appears, as seen: "corner north-west, now at the reader's
top-right".

**Why** [jq]. After step `quarter`, all four corners, vertices 0–3, are at (1, 0),
the reader's bottom-right. A reader-relative name would have to be relearnt every
step. The sheet never gains or loses paper, so a name in material coordinates stays
valid however the paper moves. CAD's names for faces and edges have no such fixed
sheet to live on ([E2](research/E2-references-and-persistent-naming.md) "D. The
topological naming problem in CAD").

### 4.2 Points

| Form | Means |
| --- | --- |
| `corner …`, `centre` | §4.1 |
| `(u, v)` | a material point in sheet lengths; a typed literal, guarded (§4.4) |
| `midpoint of [P, Q]`, `fraction r along [P, Q]` | P + r(Q − P), with r = 1/2 for `midpoint` |
| `midpoint of edge S` | the midpoint of side S of the sheet's box: `midpoint of edge north` is (1/2, 1) on a unit square. `fraction r along edge S` is refused, because nothing says which end r counts from ([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)) |
| `meet L1 L2` | where two lines cross, in **current positions** |
| `end of crease of NAME nearest P` | the material vertex ending a segment NAME created, nearest P; a tie is refused (`EndTie`) |
| a `mark` name | its pinned material point (§4.5) |
| a `let` name | whatever it expands to, at each use |

Everything except `meet` is computed in material coordinates, on the unfolded
sheet. So `midpoint of [corner south-west, corner north-east]` is (1/2, 1/2) even
after those corners are folded onto one spot.

### 4.3 Lines

The *Huzita-Hatori operations* O1–O7 are the seven single-fold alignments
([glossary-additions](glossary-additions.md#references)). Solution counts are from
[E2](research/E2-references-and-persistent-naming.md) "B. Huzita–Justin–Hatori: the
vocabulary of fold lines" (web sources). The moving side is decided by the move's
text, never by the anchor
([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)).

| Form | Op | The fold that… | Answers | Moving side |
| --- | --- | --- | --- | --- |
| `[P, Q]` | O1 | passes through P and Q | 1; P = Q refused | needs a `moving` seed |
| `P to Q` | O2 | puts P on Q | 1; P = Q refused | the side containing P |
| `L1 to L2` | O3 | puts L1 on L2 | 1 if parallel, 2 if crossing. The one mapping segment onto segment is preferred, and `nearest` is needed only if two remain | the side containing L1's interior; refused if L1 straddles the fold line |
| `perpendicular to L through P` | O4 | is perpendicular to L through P | 1 | needs a `moving` seed |
| `P to L through Q` | O5 | puts P on L, through Q | 0–2 | the side containing P |
| `P to L1 and Q to L2` | O6 | puts P on L1 and Q on L2 | 0–3 | the side containing P; refused if Q lies on the other side |
| `P to L1 perpendicular to L2` | O7 | puts P on L1, perpendicular to L2 | 0 or 1 | the side containing P |
| `P to L` | O7, with L2 ⊥ L | puts P on L with the fold line parallel to L: "fold the corner to the crease" | 1; P on L refused | the side containing P |
| `edge S` | — | the line through its current segments, only if they are collinear within `Fold.Faces.tolerance` (§4.6) | 1 | needs a `moving` seed |
| `crease [P, Q]` | Lucero's O3, the one he adds | runs along existing creases from vertex P to vertex Q | 1 | needs a `moving` seed |
| `hinge of NAME` | — | runs along the segments NAME's single move turned about | 1 | needs a `moving` seed |
| `crease of NAME` | — | runs along the segments NAME created, which may be none. Usable as a line only when they are collinear now | 1 | needs a `moving` seed |
| `model [(x1, y1), (x2, y2)]` | escape | runs between two points in the current model's coordinates as seen. Flat states only, recorded as "not a landmark", and it depends on the anchor | 1 | needs a `moving` seed |

**Constructions need a flat state**, one where every face lies in one plane
([glossary-additions](glossary-additions.md#words-the-prds-narrow)). Creasing
through layers has the same restriction
([`ThroughLayers.hs:63-67`](../src/Senbazuru/Origami/ThroughLayers.hs#L63-L67)).

- *Where they compute.* On raw positions. A construction commutes with rigid
  motions, so this gives the same material answer as displayed positions would.
  Only `model [...]` is mapped through the inverse of the displayed motion.
- *With paper in the air*, a state that is not flat. Only `crease [P, Q]`, `hinge of`, material seeds and
  macros are allowed. A construction is refused as `ConstructionInTheAir`.

**Axioms return lists.**

1. Compute every real solution.
2. Set aside any whose line crosses no paper. It is listed in the message and the
   record but never chosen, so an author who expected that answer sees why it was
   not taken ([E2](research/E2-references-and-persistent-naming.md) finding 10).
3. If more than one solution on the paper remains, require `nearest P`.
4. Accept exactly one.

### 4.4 Resolution by slot

A point resolves by the *slot* it fills, never by its spelling
([glossary-additions](glossary-additions.md#references)). The tolerance throughout
is `Fold.Faces.tolerance`, 1e-9 × the sheet's bounding-box diagonal
([`Faces.hs:248-251`](../src/Senbazuru/Fold/Faces.hs#L248-L251)). That is 1.41e-9
on the unit square ([gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md)
"A. How exact a landmark is today", finding 2).

| Slot | Filled by | Accepted when | Refused as |
| --- | --- | --- | --- |
| **Position** | inputs of O1–O7 and `P to L`; both arguments of `P to Q`; `meet`; `model` | the point is on paper. It is placed through every face whose closed polygon contains it within tolerance, and all those placements agree | `OffThePaper`; `PlacementsDisagree`. Typed literals only, meaning `(u, v)` or `model`: `NearMiss` when not within tolerance of a vertex but within `RunSettings.nearMissBand` of one (default 1e-3 sheet lengths, [owner decision 2](10-roadmap-risks-questions.md#6-owner-decisions)). `corner`, `centre` and `midpoint` are exact and skip this guard |
| **Region with a hinge** | a move's *seed*: `moving P`, or an alignment fold's first argument | strictly inside exactly one face. Or a vertex: cut the crossed faces along the line, take the pieces containing P, and require them all in one component. Vertex seeds are preferred to decimals | `SeedOnTheLine`; `SeedSplit`, naming the components; `NotInOneFace` |
| **Region without a hinge** | `anchor`, `layers A above B`, `mark … in face containing S` | strictly inside exactly one face, with no vertex exception | `NotInOneFace` |
| **Vertex** | `collapse at`, `rabbit-ear at`, `petal tip`; the ends of `crease [P, Q]` and of pose creases; `end of crease of` | within tolerance of exactly one vertex | `VertexMiss`, naming the nearest vertex and distance; `TwoVerticesWithin`. Never `Creasing.existingAt`'s first match ([`Creasing.hs:322-327`](../src/Senbazuru/Fold/Creasing.hs#L322-L327)) |

Worked cases [py, checks [B](#check-b), [S](#check-s), [C](#check-c)]:

| Reference | Fixture | Slot | Result |
| --- | --- | --- | --- |
| `anchor centre` | blintz-base | region | Accepted. There is no vertex at (1/2, 1/2), and the point lies on the inner side of all four edges of ring 4–5–6–7 |
| `anchor (1/2, 1/2)` | crane | region | `NotInOneFace`. Vertex 24 is 2.1e-14 away, and a vertex lies inside no face |
| `(1/2, 1/2)` in a construction | crane | position | Accepted, as vertex 24 |
| `anchor (19/20, 1/3)` | crane | region | Accepted: inside face 0 only, 0.05 from the nearest edge |
| `(1/2, 0.207)` in a construction | bird-base | position | `NearMiss`: 1.07e-4 from vertex 9 at (1/2, 0.2071067811865475), which is outside tolerance and inside the band. The author meant 0.5(√2 − 1) |
| `anchor (29/50, 2/5)` | bird-base | region | Accepted: 0.0798 from the nearest crease, so inside exactly one face |
| `collapse at centre` | bird-base | vertex | Accepted: vertex 8 is exactly (1/2, 1/2) |
| `collapse at centre` | blintz-base | vertex | `VertexMiss`: the nearest vertices are the edge midpoints, 1/2 away |

### 4.5 Landmarks: `mark`, `let`, step names

- **`mark A = POINT [in face containing S]`.** POINT is evaluated to a folded
  position, and the distinct material points of every face there are collected. If
  more than one is found, the mark is refused (`MarkOnSeveralLayers`) unless S picks
  exactly one. The chosen material point is pinned and labelled on figures while
  visible ([06](06-prd-step-diagrams.md)).

  *Example* [jq]. After step `quarter`, `meet edge east edge south` is folded
  (1, 0), where material vertices 0, 1, 2 and 3 all lie. So
  `mark A = meet edge east edge south` is refused, listing those four corners. With
  `in face containing (3/4, 1/4)` it picks face 0, whose only material point there
  is vertex 1, corner south-east.
- **A slot needing a material point, filled by a folded position**
  ([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)).
  `anchor meet L1 L2` fills a region slot with a point found in current positions.
  It resolves as `mark` does: the distinct material points there, refused when there
  is more than one.
- **`let NAME = POINT | LINE`** is expanded by `Sequence.Elaborate` and re-evaluated
  at each use, so it pins nothing. `let mid = edge north to edge south` is y = 1/2
  on the sheet, and something else once a fold moves edge north.
- **Names.** Only marks and step names enter the landmark table. Names are unique,
  with no shadowing (`DuplicateName`). A reference that a later step made ambiguous
  is refused (`LandmarkAmbiguous`): for example, a mark used as a region after a new
  crease passes through it.

### 4.6 `edge S` on a folded state

`edge S` is the line through its current segments, but only when they are collinear
within tolerance. Otherwise it is refused as `EdgeNotStraight`, naming the segments'
current ends and suggesting `[P, Q]` with corners.

- **Quarter fold, state 1** [jq]. Edge north's segments v3–v6 and v6–v2 both lie on
  y = 1. Accepted.
- **Blintz, after step `c1`** [py]. The step is
  `step c1 "Fold the south-east corner behind, to the centre." { fold behind corner south-east to centre }`
  (§6.2). Corner (1, 0) reflected in x − y = 1/2 lands at
  (1/2, 1/2), while (1/2, 0) stays put. Edge south's east half now runs
  (1/2, 0)–(1/2, 1/2), perpendicular to its west half. Refused.

## 5. The reader's side and presentation

### 5.1 The reader's side

The *reader's side* is model +z of the displayed model: the side of the paper facing
the reader ([glossary-additions](glossary-additions.md#running-a-sequence)).

- **How it starts.** The header's `coloured side up` (the default, the file's +z)
  or `white side up`, which starts with a `left-right` turn-over
  ([D5](decisions.md#d5-presentation-and-the-readers-side)).
- **What changes it.** Each `turn over` flips it. `rotate` and re-anchoring do not.
- **What is read from it.** `valley`/`mountain` (aliases `in front`/`behind`),
  `top N layers`, `top flap`, `layers A above B`, `model [...]` and pose angles.
- **What is never consulted.** A camera.

It is a property of the fold state, never of a render.

### 5.2 Presentation moves no paper

`turn over left-right | top-bottom` and `rotate k/8 turn clockwise | anticlockwise`
update `FoldState.presentation`. They are page words, never compass words. The axis
belongs to the model and is computed in `Sequence.Run` from `Geometry` alone:

- `turn over left-right`: (x, y, z) ↦ (2cx − x, y, 2cz − z);
- `turn over top-bottom`: (x, y, z) ↦ (x, 2cy − y, 2cz − z);
- `rotate`: about the line parallel to +z through (cx, cy);
- (cx, cy) is the centre of the xy bounding box of the current displayed state, and
  cz is the middle of its z range.

**Example** [jq].

- Quarter-fold state 2 spans x ∈ [1/2, 1], y ∈ [0, 1/2], and is flat. So cx = 3/4
  and cz = 0.
- `turn over left-right` maps x ↦ 3/2 − x, which takes [1/2, 1] onto itself.
- [#95](https://github.com/avalonalex/senbazuru/issues/95)'s half turn about x = 0
  would move the model to x ∈ [−1, −1/2] and double the page's width
  ([gap-step-annotation-channel](research/gap-step-annotation-channel.md) "C.
  Turning over and the single camera", finding 12).

**How the motions are built.**

- Turn-overs, half turns and quarter turns use exact 0/±1 entries.
- Eighth turns, a book's diamond view, use trigonometric `rotationAbout`
  ([`Rigid.hs:114-129`](../src/Senbazuru/Geometry/Rigid.hs#L114-L129)). That is
  acceptable because presentation moves no paper and joins compare unpresented
  positions. Written coordinates then carry *platform bits*: trigonometry can round
  differently on different machines, so the written bytes may differ between them
  ([owner decision 10](10-roadmap-risks-questions.md#6-owner-decisions)).
- Every presentation `Rigid` is checked to be a *proper rotation* by
  [05](05-prd-library-additions.md)'s `isProperRotation`: rows orthonormal and
  det = +1, each within 1e-12. The check is needed because `Rigid` "will hold any
  3×3 matrix … and nothing here checks"
  ([`Rigid.hs:24-26`](../src/Senbazuru/Geometry/Rigid.hs#L24-L26)).

### 5.3 One conversion for the whole model

The **raw sense** is the fold's sense (§1), negated exactly when presentation
`after` anchor placement sends ẑ, the unit vector along +z, to −ẑ. It is used in three
places:

1. **New creases on a flat sheet.** The raw sense names their assignment.
2. **Creasing through layers.** It is the assignment handed to the library, which
   flips it on face-down layers itself
   ([`ThroughLayers.hs:321-340`](../src/Senbazuru/Origami/ThroughLayers.hs#L321-L340)).
3. **The hinge turn.**
   - *Physically,* a valley turns the moving paper towards the reader's side.
   - *In FOLD terms,* each hinge segment's angle changes by A or −A. The sign
     depends on the raw sense and on which way that segment's stationary face lies,
     as in the table below.
   - *In the library,* `Flap`'s *travel* is the change in the *first* listed
     segment's angle, and `Flap` derives every other segment's sign from that
     segment's own stationary face
     ([`Flap.hs:10-16`](../src/Senbazuru/Origami/Flap.hs#L10-L16),
     [`:201-216`](../src/Senbazuru/Origami/Flap.hs#L201-L216)).

| Raw sense | Stationary face shows its top towards raw +z | Stationary face shows its back |
| --- | --- | --- |
| valley | +A: edge 9 in §1's step `quarter` | −A: edge 11 in step `quarter` |
| mountain | −A: edges 8 and 10 in step `half` | +A: the crane wing's accepted `behind` (§9) [reasoned] |

*Superseded in part* by [D5](decisions.md#d5-presentation-and-the-readers-side)'s
amendment (owner decision 13, 2026-09-23): the sign is read from the *moving* face
beside each hinge segment, not the stationary one. On an open hinge, which is every
example here, the two faces beside a crease lie the same way up, so the table keeps
its numbers. The table and the paragraph below are rewritten with that change to
`prepareFlapToward`.

**The runner hands `Flap` a side, not a signed travel**
([D5](decisions.md#d5-presentation-and-the-readers-side),
[C5](decisions.md#changes-since-draft-v2)). The table shows that the sign of travel
depends on the raw sense *and* on which way up the first segment's stationary face
lies, and one model can hold both: crane wing A has faces 2 and 3 face down and
faces 6 and 7 face up
([gap-layer-selective-folds](research/gap-layer-selective-folds.md) finding 11). So
the way-up decision stays in the library, where `Flap` already holds the face's ring.
[05](05-prd-library-additions.md) adds (**SKETCH**):

```haskell
data Toward = TowardRawPlusZ | TowardRawMinusZ
prepareFlapToward :: [EdgeId] -> FaceId -> Double -> Toward -> Folded -> Either FlapError FlapMotion
```

- It reads the first segment's stationary face normal from that face's placement.
- It sets the travel to +A when "towards raw +z" agrees with the sign of that
  normal's z, and to −A otherwise.
- A normal that is not ±ẑ within `isProperRotation`'s 1e-12 is refused as
  `FlapStationaryNotFlat`.
- The runner passes `TowardRawPlusZ` for a raw valley and `TowardRawMinusZ` for a
  raw mountain.

Checked against the table [reasoned]: a raw valley over a face showing its top
agrees, so +A (edge 9); a raw valley over a face showing its back disagrees, so −A
(edge 11); a raw mountain over a face showing its back agrees, so +A (the crane
wing). [01 §5.5](01-architecture.md#55-raw-sense-and-travel) and
[§5.6](01-architecture.md#56-travel-per-segment) work step `quarter` through
segment by segment.

Constructions use raw positions (§4.3).

### 5.4 Render options never change meaning

For every V, the move records and states behind `run -o x.svg --view V` equal those
written by `run -o x.fold`. On a page:

- the arrow drawn is the stated kind, inverted when the camera looks from the side
  opposite the reader's;
- edge-on views draw the stated kind and mark the figure edge-on;
- captions are prose and are not rewritten, and `run` warns once when a page is
  drawn from the opposite side.

Page extent across a turn is [06](06-prd-step-diagrams.md)'s.

### 5.5 Written frames are presented

Frames are written with the displayed motion applied. `Origami.Step` treats a pair
of frames as a presentation change, and infers no arrow, when some vertex moves and
one whole-model proper rotation maps every vertex
([D5](decisions.md#d5-presentation-and-the-readers-side)). *Some* vertex, not every:
a turn-over leaves the vertices on its own axis still, 3 of 9 on
`quarter-fold-steps.fold` [prd]. `Step.hs`'s header says the opposite today
([`Step.hs:30-34`](../src/Senbazuru/Origami/Step.hs#L30-L34)).
[05](05-prd-library-additions.md) has `fitRigid`, and [06](06-prd-step-diagrams.md)
the page.

## 6. Moves

### 6.1 Every move

| Move | What it does | Evidence (§10) |
| --- | --- | --- |
| `fold SENSE [A°] LINE [LAYERS] [moving P]` | one checked hinge turn by A, 180 by default (§6.2) | `SweptHinge` |
| `unfold NAME…` | reverses the named steps' net angle changes, last move first (§6.4) | `SweptHinge` |
| `fold and unfold …` (alias `precrease`) | a fold, then an unfold of it: two moves, and no angle (§6.4) | `SweptHinge` each |
| `turn over …`, `rotate …` | presentation (§5.2) | `Presented` |
| `anchor P` | re-anchors on demand (§2.3) | `NoMotion` |
| `mark A = …` | pins a landmark (§4.5) | `NoMotion` |
| `let NAME = …` | expanded away, leaving no record | — |
| `collapse`, `rabbit-ear`, `petal`, `continue`, `together` | macro-moves (§8); a `together` is one move | `Sampled` |
| `pose { … }` | sets angles, claiming no route (§8.6) | `StateOnly` |
| `repeat …` | reruns named steps mapped by an isometry (§9) | each expanded move's own |
| `checkpoint "path" { … }` | replaces the paper (§9) | `StateOnly` |
| `not modelled "…"` | ends the run, keeping every state before it (§9) | — (no record) |
| `expect refused KIND { move }` | requires a refusal and changes nothing (§9) | — (no record; the outcome is kept in the `Run`) |
| `settle { … }` | a block, not a move: illustrates the step's last moving record ([07](07-prd-material-consumption.md)) | — |

There is one *move record* per move that runs
([glossary-additions](glossary-additions.md#running-a-sequence)); `let` leaves none,
and neither do `not modelled` and `expect refused` (§9). Its `recordBefore` is the
creased, unturned state, and every id in it uses that numbering. It also keeps
presentation and anchor placement, before and after, as separate fields, so a
`turn over` record and a re-anchoring fold can each say which display changed
([D14](decisions.md#d14-material-consumption);
[01 §2.2](01-architecture.md#22-contract-1-moverecord) owns the fields). A step
whose only moves are `let`, or which has none, is refused before any geometry as
`EmptyStep` ([D12](decisions.md#d12-the-text-syntax)).

### 6.2 `fold`

- **Amount.** `ToFlat`, 180°, or `A°`, an unsigned magnitude. The direction comes
  from the sense (§5.3).
- **Hinge.** Where the line lies along existing creases covering the selected faces,
  the fold hinges on them without creasing. On a traditional crane that is 6 of the
  12 steps folding through some layers but not all: steps 15, 17, 18, 20, 21 and 23
  in the table of [gap-layer-selective-folds](research/gap-layer-selective-folds.md)
  "(e) The traditional crane, step by step", counted by reading a book rather than
  computed. That section's summary line says 7, but its table marks 6, and 6 is the
  count ([D8](decisions.md#d8-folding-some-layers),
  [C72](decisions.md#changes-since-draft-v2)).
- **New creases.** Otherwise new creases go on the selected faces only, at angle 0
  with intent, and then the paper turns. The library's `AtRest` angle policy is
  [05](05-prd-library-additions.md)'s.
- **Flat creases cannot hinge.** An existing F crease is refused as
  `ExistingHingeFlat`, because `Flap` turns only M, V or U
  ([`Flap.hs:187`](../src/Senbazuru/Origami/Flap.hs#L187)). Giving an F hinge an
  intent from the fold's sense, by the per-layer rule creasing uses, is a later
  library function, not v1 ([D8](decisions.md#d8-folding-some-layers)).

**Blintz example.** Step `c1` (§4.6), `fold behind corner south-east to centre`:

- *Line.* O2 of (1, 0) and (1/2, 1/2) is x − y = 1/2, which contains both ends of
  edge 8 [py]. No crease is added.
- *What moves.* The moving side contains corner south-east, whose only face is its
  corner triangle. The anchor square is stationary and top up.
- *Against the recipe.* Edge 8 changes by −180, the recipe's first travel
  ([`BlintzSequence.hs:50-56`](../study/fold-material/BlintzSequence.hs#L50-L56)).

### 6.3 Which layers

| Words | Selects |
| --- | --- |
| none, on an alignment fold (`P to Q`, `L1 to L2`, `P to L`) | the *flap containing* the first argument: that component after cutting |
| `moving P` | the flap containing P |
| `all layers` | everything under the line |
| `top layer` | the top 1 layer |
| `top N layers` | N layers, counted at each point along the line from the reader's side |
| `top flap` | the smallest N whose selection is not *coupled* (a selection is coupled when its moving paper is still joined to paper that must stay) |

The **selection rule** is stated here as semantics. The library functions that
implement it are [05](05-prd-library-additions.md)'s.

1. **Cut every crossed face along the line.** A face counts as crossed only if its
   clip is longer than a [hair](../docs/glossary.md#origami) and its midpoint is
   strictly inside
   ([`ThroughLayers.hs:285-290`](../src/Senbazuru/Origami/ThroughLayers.hs#L285-L290)).
2. **Pick the selection.**
   - `flap containing` / `moving`: the seed's component.
   - `top N`: depth at each point along the line, from the reader's side, using the
     accepted orders. A face's depth must not change along the line
     (`DepthChangesAlong`).
   - *Why not layer numbers.* A layer number is the longest chain of faces below,
     and on the crane that is 31 while the thickest point holds 24 sheets
     ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) finding 9).
3. **Cut only the selected faces, and walk from the moving side.** Reaching the
   other half of a selected face means the selection is coupled. It is refused,
   naming the joining face.
4. **Check what covers the flap.** Refuse as `FlapCovered` if a stationary face is
   nearer than a selected face on the side the flap turns towards. This runs before
   `Flap`'s sweep, so a fold asked for in the wrong direction stops here and never
   reaches `Flap`'s own refusals, such as `FlapEndpointOrder`.
5. **Leave unselected layers alone.** They get no crease
   ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) "(b)
   Unselected layers: no crease").
6. **Pin.** `top …` selections resolve once against the accepted layer order, and
   the record keeps them as material seeds.

**The seed a record keeps for `L1 to L2`**
([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot),
[C68](decisions.md#changes-since-draft-v2)). An alignment fold's seed is its first
argument, but L1 is a line, not a point, and `unfold` (§6.4) re-resolves a recorded
seed in a region slot. So the record keeps the vertex mean of the face beside L1's
longest current material segment, ties to the lowest, then leftmost, segment.

- *Example* [py, [check Q](#check-q)]. On §1's step `quarter`, edge north's segments
  are edges 4 and 5, each 1/2 long. The leftmost is edge 5, beside face 2, ring
  `[8,6,3,7]`, so the seed is (1/4, 3/4), inside the moving flap.
- *Why not a point on L1.* A point on the edge itself, such as (3/4, 1), lies in no
  face's interior, so it fills no region slot and `unfold` could not re-resolve it.

**Crane example** [py re-impl, [check P](#check-p)]. Take the crane-wing step of
[decisions §7](decisions.md#7-examples),
`fold behind 90° corner north-west to midpoint of edge north`.

- *Points.* Folded with face 0 as root, vertex 2 (corner north-west) is at
  (1, 4.6e-14), and vertex 28 (the edge's midpoint, within 1.2e-14) is at (1, 0.5).
- *Line.* Their O2 is y = 1/4, the line `CraneWing` clips
  ([`CraneWing.hs:98`](../study/fold-material/CraneWing.hs#L98)). It crosses 16
  faces, and no end is strictly inside any.
- *Seed.* The step names no `moving` point, so its seed is its first argument,
  corner north-west. That is a vertex, so §4.4's vertex rule applies, and it lies
  in exactly faces 2, 3, 6 and 7 [py, [check C](#check-c)]. The script needs an
  interior point, so the component was computed from (0.02, 0.97), in face 7 on the
  corner's side of the line. It is faces 2, 3, 6 and 7: `CraneWing`'s hand-picked
  set ([`:93`](../study/fold-material/CraneWing.hs#L93)).
- *Sense.* The recipe's accepted turn lowers the tip to z = −1/4, away from the
  reader, hence `behind`
  ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) finding 14).

The same research found that one layer of that wing is coupled, that "top flap" on
a square base is two sheets, and that a quarter-fold seed near (1, 0) is covered.
**All of this is Python evidence (§13).**

### 6.4 `unfold`, and `fold and unfold`

**`unfold NAME…`** takes the named steps' moves, last first
([D22](decisions.md#d22-figures-holding-several-moves)).

1. For each move, reuse its *recorded* material hinge and moving seed. They are
   never re-resolved by position.
2. Map them onto current ids.
3. Turn back by the negation of that move's net angle change, checked like any
   hinge turn.

A move whose hinge creases are all at 0 now is skipped, and that covers every
`fold and unfold`. If a later move changed one of those creases, the unfold is
refused as `UnfoldChangedSince`, naming the crease. *Blintz example:* `unfold c1`
takes edge 8 from −180 to 0, the recipe's last tuple.

**`fold and unfold`** elaborates to a fold and an unfold of that fold, keeping
provenance. It takes no angle, because the tree's `FoldAndUnfold` has no field for
one ([D12](decisions.md#d12-the-text-syntax)). The crease remains, flat, with its intent. Written frames show it as F
at 0 (§11).

### 6.5 Figures holding several moves

A *step* may hold several moves, all drawn on one figure: the state the step
starts from ([D24](decisions.md#d24-states-figures-and-their-numbers),
[glossary-additions](glossary-additions.md#words-the-prds-narrow)).

- **Honesty** ([D22](decisions.md#d22-figures-holding-several-moves)). Moves run in
  order, and each is checked. The step's figure draws the state
  before its first move, so move *k* is accepted only if the paper it moves is still
  where that drawing shows it, compared by material identity. In practice none of
  that paper may have been moved by moves 1 to *k* − 1. Otherwise the move is
  refused as `MoveLeavesFigure`, with a hint to start a new `step`.
  - A `fold and unfold` pair counts as one move here.
  - All four blintz corners in one step pass.
  - "Fold the corner to the centre, then fold that flap in half" fails.
- **Batching stays inside one step**
  ([D22](decisions.md#d22-figures-holding-several-moves),
  [C16](decisions.md#changes-since-draft-v2)). Consecutive moves of one step whose
  lines resolve on the step's start state share one `creaseAllAlongWith` call,
  because re-cutting is the cost (AGENTS.md, "A move that changes a pattern").
  - In the crane opening of [decisions §7](decisions.md#7-examples), step
    `diagonals` creases its two diagonals in one batch. Step `midlines` is another
    batch, because the step "Turn over." lies between the two steps.
  - A batch across steps would show a later step's creases on an earlier
    figure, the backfill [D6](decisions.md#d6-crease-graphs-grow-between-frames)
    rejects.
  - Batched results must equal creasing move by move, compared by material
    identity, since edge ids may differ. One difference is visible: a batched
    move's `recordBefore` can already show a later move's creases of the same step
    at 0. Each record's `recordNewCreases` still lists only its own.
- **Names and evidence.** `unfold` and `repeat` name steps. `sample` belongs to a
  macro move, and `settle` to the step's last moving record. A step's state
  carries the weakest evidence of its moves (§10).

## 7. Stacking relations

`layers A above B`, the tree's `LayerAbove A B`, says that paper at material point A
lies over paper at B, as seen from the reader's side
([D11](decisions.md#d11-stacking-choices-are-relations)). A and B fill region slots
and resolve to faces fA and fB.

- **How it reaches the solver.** The pair means "first face on the +z side of the
  second", in the solver's sense and in raw terms: (fA, fB) when the reader's side
  is raw +z, otherwise (fB, fA). It is not FOLD's `faceOrders` sign, which is read
  against the second face's normal
  ([glossary](../docs/glossary.md#the-fold-format)).
- **How it is used.** `Origami.Stacking.stackingWhere` seeds its search with the
  pairs as decided, per component (**SKETCH**, [05](05-prd-library-additions.md)).

| Outcome | Result | Detected by |
| --- | --- | --- |
| exactly one stacking remains | its orders go on the working pattern (§2.4, invariant 3); `StackingChoice` records the orders and the relations | the runner |
| a relation's two points resolve to one face | `RelationOnOneFace` | the solver, from face ids: the library's `StackingError` |
| a pair does not overlap | `RelationNotOverlapping` | the solver: `StackingError` |
| none remain | `RelationsContradict` | the solver: `StackingError` |
| two or more remain | `StillAmbiguous`, with the count and the *open pairs*: overlapping faces whose order differs among the survivors | the runner's counting policy: `StackingChoiceError` |
| the budget runs out | `GaveUpStacking`, never "ambiguous": a `FoldError` ([`Query.hs:139`](../src/Senbazuru/Fold/Query.hs#L139)) that the solver wraps as `StackingRefused` ([`Stacking.hs:448`](../src/Senbazuru/Origami/Stacking.hs#L448)) | the solver |

**Errors split by who can detect them**
([D11](decisions.md#d11-stacking-choices-are-relations),
[C32](decisions.md#changes-since-draft-v2)). Whether relations can hold together is
visible from face ids alone, so the library reports it. How many surviving stackings
are acceptable is the runner's policy, so `Sequence.Error`'s `StackingChoiceError`
holds `StillAmbiguous` and `SeveralStackings` and wraps the library's
`StackingError`.

- **No relations and several stackings.** Refused as `SeveralStackings`, with the
  count and the open pairs, unless the author writes `stacking first`, which records
  index 0 as a stated default. `StillAmbiguous` is kept for relations that leave two
  or more. `layerOrderFor`'s silent first choice
  ([`Stacking.hs:386-400`](../src/Senbazuru/Origami/Stacking.hs#L386-L400)) is never
  used.
- **Where relations are written.** In `start folded { … }` and in
  `checkpoint "path" { … }`, each holding one
  `StackingSpec = Relations [Relation] | StackingFirst` (**SKETCH**).
- **The budget.** `runSequence` takes a `Budget`, so `--layer-budget` reaches it.

**Crane example** [py]. The crane-wing relations of
[decisions §7](decisions.md#7-examples) are
`layers (1/4, 1/5) above (3/8, 5/9)` and `layers (4/9, 3/8) above (1/4, 1/5)`. The
three points lie only in tail face 10 and body faces 27 and 29, at 0.0274, 0.0491
and 0.0491 from the nearest edge.

**UNVERIFIED:** that these two relations leave exactly the tail-tucked stacking,
today's index 2 of 5 ([`CraneWing.hs:78`](../study/fold-material/CraneWing.hs#L78)),
and that removing either leaves two or more. That is an M4 acceptance test
([09](09-testing-and-acceptance.md)).

## 8. Macro-moves

### 8.1 Parts

A *macro-move* turns several creases at rates the geometry fixes
([glossary-additions](glossary-additions.md#macro-moves)). It cannot be built from
flap turns: a petal's seven creases turn at three rates, and `Flap` "does not
discover coupled motions" ([`Flap.hs:1-6`](../src/Senbazuru/Origami/Flap.hs#L1-L6);
[gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md)
finding 15).

| Part | What it is |
| --- | --- |
| Driving parameter | `until 175°`: an unsigned, exact `Rational` in degrees |
| Role formulas | one Haskell function each, shared by the runner and its tests. For example, in the bird base's collapse the *four* (the midline mountains, §8.2) turn by v = 360/π · atan2 (√2 · sin h) (cos h), where h = m·π/360 is half the driving parameter m, in radians ([`CheckedBird.hs:108-113`](../study/fold-material/CheckedBird.hs#L108-L113)) |
| Signature | what the macro requires of a *moving star*: the creases it would turn at a vertex, with their current angles and intent signs |
| Roles, branch and sign | each matched crease's *role*, its part in the match, which fixes its formula; the *branch*, the sign choice the match made (σ for a collapse, §8.2); signs come from intent |

v1 has `collapse at P [keeping [Q1, Q2] flat] until A°`, `rabbit-ear at P until A°`,
and `petal tip P until A°` / `petal top flap until A°`. Squash, the reverse folds,
sink, swivel and crimp stay `not modelled` until each has a derived and tested
relation ([D9](decisions.md#d9-macro-moves-as-named-angle-relations)).

A macro landing flat with several stackings is refused as `SeveralStackings`,
listing the open pairs, because v1 has no syntax giving a macro relations (§7).

### 8.2 Collapse

1. **Candidates.** Rays from P whose first segment is at angle 0 with intent M or V.
   Each is continued straight through collinear segments to the paper's edge.
2. **`keeping [Q1, Q2] flat`** removes the pair of rays towards Q1 and Q2 (vertex
   slots). It is refused unless Q1 and Q2 are the far ends of one opposite, collinear
   pair.
3. **Matching.** The six-ray signature must match exactly once: sectors 45°, 45°,
   90°, 45°, 45°, 90° up to rotation and reflection. Otherwise the step is refused,
   listing every candidate as the `keeping` clause that would pick it.
4. **Roles.** The *pair* is the two rays each flanked by two 45° sectors, and the
   *four* are the rest.
5. **Signs.** The pair takes σ·m and the four −σ·v. Here m is the driving
   parameter, v is the four's formula angle (§8.1), and σ = +1 when the pair's
   intent is V.

Sectors are compared with `FlatFold`'s tolerance, 1e-5 rad
([`FlatFold.hs:162-163`](../src/Senbazuru/Origami/FlatFold.hs#L162-L163)), so that
`check` and the macro agree.

| Plain sheet [py, [check S](#check-s)] | Rays at the centre: bearing, edge (eN is edge N), intent | Matches |
| --- | --- | --- |
| `square-base.fold` | 0° e11 V · 45° e12 M · 90° e13 V · **135° e14 F** · 180° e15 V · 225° e8 M · 270° e9 V · **315° e10 F** | 1. F is not a candidate, so six rays remain. The pair is e12 + e8 (M), so σ = −1 |
| `bird-base.fold` | 0° e14 M · 45° e9 V · 90° e18 M · 180° e22 M · 225° e8 V · 270° e10 M | 1. The pair is e9 + e8 (V), so σ = +1. Each of the four continues through an F segment (11, 15, 19, 23) to the edge, and those segments turn too ([`CheckedBird.hs:114`](../study/fold-material/CheckedBird.hs#L114)) |
| `sheet square` after both diagonals and both midlines are precreased | the same eight bearings, all with intent | 4, so refused. **UNVERIFIED**: reasoned from gap-exact-landmarks finding 10 and the bearings above |

Square-base's two F rays end at (0, 1) and (1, 0). So
`keeping [corner south-east, corner north-west] flat` names exactly the pair that
fixture marks F. Keeping a midline pair instead gives the waterbomb base's sectors
([gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md)
finding 10).

**Refusal sketch (SKETCH).** For the precreased square in the last row of the table:

```text
step 4 (base): collapse at centre until 180°: 4 collapses match at centre; add one of
keeping [corner south-east, corner north-west] flat, keeping [corner south-west,
corner north-east] flat, keeping [(1/2, 0), (1/2, 1)] flat, keeping [(0, 1/2),
(1, 1/2)] flat
```

### 8.3 Rabbit ear and petal

- **`rabbit-ear at P`** needs four moving rays at 0. Roles and signs come from the
  *lone* crease, the one whose intent differs from the other three, and the rate
  comes from Foschi, Hull and Ku's relation. Equal adjacent sectors are refused:
  the relation then holds the lone crease flat until the others close, which is
  derived but not tested
  ([gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md)
  finding 11; not checked here on a fixture).
- **`petal tip P`** needs a *hinge* at 0 with intent V; two *opening creases*, each
  the outer part of a straight line currently folded at ±180, which open to 0; four
  *sides* at 0 with intent M, running from the hinge's ends to paper-edge vertices,
  two of which meet at the tip; and 22.5° corner geometry.
  - On the bird at the square-base pose there are two matches (same note, finding
    12).
  - The only sheet corner joined to both ends of hinge 26 is vertex 1, corner
    south-east. For hinge 27 it is vertex 3, corner north-west [py].
  - So `petal tip corner south-east` picks hinge 26.
- **`petal top flap`** is allowed on flat states only. It is resolved once, as the
  match nearest the reader by the accepted order, and pinned as its tip's material
  point.

### 8.4 `continue`

`continue NAME until A°`:

1. takes the latest *macro binding*, the record of what a macro matched (roles,
   branch, disambiguator and the parameter reached,
   [glossary-additions](glossary-additions.md#macro-moves)), in NAME's line of
   continuations, including a binding inside a `together` record (§8.5). It is
   refused if NAME is not a step holding exactly one macro move;
2. maps each role's material segment onto the current working pattern, and is
   refused, naming the crease, if a segment is split or missing;
3. checks that each role crease is at its formula's angle at `reached`, the driving
   parameter's value so far, within `FlatFold`'s tolerance. It also checks that no
   crease inside the macro's *rigid sectors*, the panels between its role creases
   that it turns without bending, is folded or moving;
4. requires reached < A ≤ max, where *max* is the largest driving value the macro's
   formula allows, then runs from `reached` to A.

Signatures are not loosened, because recovering the parameter from `Double` angles
loses its exact value.

*Why it exists* [reasoned from
[gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md)
finding 12's signature, which needs the hinge currently at 0]. Once the bird's
petals, made by steps `first-petal` and `second-petal`, reach 175°, both hinges are
at 175, not 0. A second `petal tip` then matches nothing. So the *press*, the last
motion flattening both petals together, has to be
`together { continue first-petal until 180°; continue second-petal until 180° }`,
as in the bird-base source of [decisions §7](decisions.md#7-examples).

### 8.5 `together` and `sample`

- **`together { … }`** is one move and one record
  ([D9](decisions.md#d9-macro-moves-as-named-angle-relations),
  [C12](decisions.md#changes-since-draft-v2)).
  - *Lockstep.* Members advance by the same fraction of each member's own range, and
    the whole is checked as one motion. Members that share a crease are refused.
  - *Bindings.* The record carries `recordMacros :: [MacroBinding]`, one binding per
    member. Each names the line it continues (`bindLine`, the step that started it),
    so a later `continue first-petal` finds its binding inside a `together` record.
- **`sample 30° 60° …`** is an attribute of a macro move. It chooses illustration
  poses in the macro's own parameter, and every sample must lie strictly between
  `reached` and A. Each is written as its own state, before the step's end state,
  and drawn as its own figure with no caption and no arrows (§11,
  [D24](decisions.md#d24-states-figures-and-their-numbers)).
- **Checking does not depend on illustration**
  ([C38](decisions.md#changes-since-draft-v2)). The runner checks the authored
  samples plus `RunSettings.macroChecks` evenly spaced interior parameters, a count
  to be fixed with evidence in M5's PR. So a macro written with no `sample` still
  earns `Sampled` evidence, and writes no extra states.

### 8.6 `pose`

`pose { crease [P, Q] at -90°; … }` sets each named crease's angle, and every other
crease keeps its own. The result is refolded, so a pose that does not close is
refused with folding's own `TornAt` or `AngleNotAchieved`
([`Folding.hs:154`](../src/Senbazuru/Origami/Folding.hs#L154),
[`:170`](../src/Senbazuru/Origami/Folding.hs#L170)).

- **Sign.** A pose angle is a FOLD angle, converted once for the whole model by
  §5.3's rule: negated exactly when presentation `after` anchor placement sends ẑ to
  −ẑ. There is no per-layer flip. So +90 is a valley as seen from the reader's side
  on paper lying the same way up as the anchor's face, and a mountain as seen on
  paper lying the other way up.
  - *Example.* Halfway through §1's step `quarter`, a single valley as seen, is
    `pose { crease [centre, (1, 1/2)] at 90°; crease [centre, (0, 1/2)] at -90° }`.
    Edge 11's faces, 2 and 3, lie face down after step `half`, so its angle is
    negative. [01 §5.5](01-architecture.md#55-raw-sense-and-travel) folds exactly
    these angles [py].
  - *Why no per-layer flip* [reasoned]. A pose may run with paper in the air, where
    a layer does not lie flat and has no way up to flip by. So "positive means a
    valley as seen" holds only on paper lying the same way up as the anchor's face
    ([D9](decisions.md#d9-macro-moves-as-named-angle-relations),
    [C61](decisions.md#changes-since-draft-v2)).
- **Evidence.** `StateOnly`.
- **Where it may run.** It is serialisable and allowed with paper in the air.

## 9. Repeat, checkpoint, not modelled, expect refused

### `repeat NAME[..NAME] [mirrored across [P, Q] | turned k/4 about P]`

- **The isometry** ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)).
  P and Q are exact material points: corners, `centre`, `(u, v)`, or `midpoint of`
  an edge. Constructions are refused.
  - Only quarter turns are allowed, so mapped points stay `Rational`.
  - `turned k/4` turns anticlockwise on the sheet as the file draws it.
  - The isometry must map the sheet to itself.
  - The bare form is the identity: a restatement at a later state.
- **What maps.** Only material references. Presentation moves are kept as written.
  A step containing `model` or `top N` is refused.
- **The check is in material terms.** After the move, its new creases must equal
  the isometry's image of the original's, with the same assignments, **and** each
  hinge segment's material image must turn by the same net angle change. Otherwise
  it is refused as `RepeatNotSymmetric`.
- **The page.** It is one figure carrying a repeat range. Expanded moves get derived
  names and are each checked. There is no `repeat … behind`, because turning and
  mirroring together would flip every layer twice.

**Example** [py]. On the blintz, `repeat c1 turned 1/4 about centre` uses
(x, y) ↦ (1 − y, x). That takes corner south-east to corner north-east, and edge 8's
segment (1/2, 0)–(1, 1/2) onto edge 9's (1, 1/2)–(1/2, 1), the recipe's second
tuple. `c1` adds no crease, so comparing new creases alone would compare nothing.
That is why the hinge turns are compared too: the recipe turns edges 8 and 9 both by
−180 ([`BlintzSequence.hs:51-52`](../study/fold-material/BlintzSequence.hs#L51-L52)).

### `checkpoint "path" { layers … }`

- **What it does.** Replaces the working pattern with a named, loaded key frame
  ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused),
  [C18](decisions.md#changes-since-draft-v2)). Its angles are read as `start folded`
  reads them (§2.2), by `foldAnglesOf`: explicit angles first, otherwise from
  assignments. One rule serves both, so a checkpoint file's recorded angles are kept
  as a sheet's are. Intent follows §2.2's starting rule, and the stacking is chosen
  by a `StackingSpec` (§7). Evidence: `StateOnly`.
- **What it must match.** The sheet's outline in material coordinates, within
  `Fold.Faces.tolerance`. It may add or remove creases, as frog milestones do.
- **The page.** A new figure with no inferred motion, because removing creases
  breaks the prefix rule that motion across a growing crease graph needs
  ([D6](decisions.md#d6-crease-graphs-grow-between-frames)). The record carries the
  added and removed creases. `start folded` is the header's equivalent for the first
  state.

### `not modelled "inside reverse fold"`

- `run --check` accepts it.
- `runSequence` stops there and returns `Right` a `Run` whose `runStop` names the
  step and the text, with every record and state before it
  ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused),
  [C10](decisions.md#changes-since-draft-v2)). It is a `Right` because a `Left`
  could carry none of them.
- `runRefusal :: Run -> Maybe SequenceError` gives `StepRefused … NotModelled`. `run`
  writes the states before the stop, then prints that message and exits nonzero
  ([D13](decisions.md#d13-the-run-verb-and-io)).
- Every other refusal returns no partial run in v1.
- The page draws the step's caption on its start state, with no arrows.
- Real macro forms are added only when §8's signature exists.

### `expect refused KIND { move }`

- **Where it goes.** It is a move inside a step, written before the move it
  contrasts with, so both run against one state
  ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused),
  [C8](decisions.md#changes-since-draft-v2)).
- **What it does.** Runs the inner move against the current state, and requires a
  refusal whose kind is KIND (§12), at any nesting depth.
- **What it leaves behind.** An unchanged state, **no move record and no state**. A
  refusal claims nothing about a route taken, and every consumer of records (page,
  animation, settle) would otherwise have to skip it. Its outcome is kept in the
  `Run`, on its step, and printed by `--report`; it is not written to the sequence
  file ([D18](decisions.md#d18-non-goals)).
- **A step of nothing else.** A step whose moves are all `expect refused` writes no
  state and is not a figure
  ([D24](decisions.md#d24-states-figures-and-their-numbers)).
- **What it is for.** Documenting which direction is physical. For example, the
  crane-wing step of [decisions §7](decisions.md#7-examples), shown here without its
  `settle` block:

  ```text
  step wing "Fold the underneath wing away from you until it stands straight out." {
    expect refused FlapCovered { fold in front 90° corner north-west to midpoint of edge north }   # UNVERIFIED kind
    fold behind 90° corner north-west to midpoint of edge north
  }
  ```

  - *What it records.* The physical fact behind `CraneWing`'s refused −90
    ([`CraneWing.hs:81-84`](../study/fold-material/CraneWing.hs#L81-L84)): wing B,
    which stays still, lies on wing A's reader side, so wing A cannot turn towards
    the reader. That wing B lies there is inferred (§13).
  - *Why `FlapCovered`* (**UNVERIFIED** until M4's runner raises it,
    [C9](decisions.md#changes-since-draft-v2)). §6.3's step 4 refuses the move
    before `Flap` runs. `CraneWing` calls `prepareFlapAlong` directly, with no
    selection step, so it gets `Flap`'s `FlapEndpointOrder 0` instead.
  - *A valley at −90 is not a typo.* By §5.3's table, the accepted `behind` is +90
    only because the first hinge segment's stationary face shows its back, and on
    that face `in front` is −90 [reasoned]. The moving face beside it is the other
    half of a face the crease cuts, so it shows its back too, and
    [D5](decisions.md#d5-presentation-and-the-readers-side)'s amendment gives the
    same sign.
- **Its refusals.** If the inner move is accepted: `RefusalNotRaised`. If it is
  refused by another name: `RefusedDifferently`, naming both.

## 10. Assurance

A *route* is the continuous path between two states. A valid end state does not
show that paper can reach it ([endpoints-and-routes.md](../docs/notes/endpoints-and-routes.md)).
Each record's `RouteEvidence` says what was checked. §6.1 says which move produces
which value.

| Value | Claims |
| --- | --- |
| `SweptHinge CheckedFlap` | one hinge turn checked over its whole path; `CheckedFlap` is opaque ([`Flap.hs:95-96`](../src/Senbazuru/Origami/Flap.hs#L95-L96)) |
| `Sampled CheckedMacro SampleReport` | a coupled route checked at sample poses; `CheckedMacro` is opaque |
| `StateOnly` | end state checked, route not |
| `Presented` | only presentation changed |
| `NoMotion` | no paper moved: a move that creases without turning, `anchor P`, or `mark` |

- **Weakest** ([D10](decisions.md#d10-assurance-as-evidence-values)). A step's state
  carries the weakest evidence of its moves, in the order
  `StateOnly` < `Sampled` < `SweptHinge` < `Presented` < `NoMotion`, ordered by how
  much of the route a reader takes on trust. The records keep each move's own.
- **Poses** (**SKETCH**, [05](05-prd-library-additions.md)). With
  `data PoseRef = PoseBefore | PoseAfter | PoseOnRoute Rational`,
  `recordPoseAt :: MoveRecord -> PoseRef -> Either PoseError RoutePose` refuses
  `PoseOnRoute` as `NoRoute` for `StateOnly`, `NoMotion` and `Presented`.
  `RoutePose` lives in `Origami.Route`, and `Sequence.Record` re-exports it.
- **Records derive `Eq`.** No record field holds a function. `Flap`'s `FlapMotion`
  and `CheckedFlap` derive only `Show` today
  ([`Flap.hs:93`](../src/Senbazuru/Origami/Flap.hs#L93),
  [`:96`](../src/Senbazuru/Origami/Flap.hs#L96)), so 05 adds `Eq` to both.
- **`expect refused` has no evidence**, because it produces no record (§9).
- **Certificates**, exact proofs of one fixture's route, attach after the run in the
  study. They are keyed by macro name and fixture fingerprint, and never downgraded
  ([07](07-prd-material-consumption.md)).
- **Where it appears.** `run --report` prints each move's evidence, and §11 writes
  each state's.

## 11. Written frames

**The at-rest rule, defined once.** `Fold.Query.atRest :: Double` is τ, and
`assignmentAtRest :: Assignment -> Double -> Assignment` applies it:

- B, C and J pass through;
- otherwise M below −τ, V above τ, and F in between;
- when the writer writes F, it writes the angle as exactly 0.

So no written frame has F with a nonzero angle, and every reader agrees. τ is
1e-10 degrees ([D4](decisions.md#d4-written-frames-follow-the-state-rule)), equal to
the two existing thresholds it should replace
([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278),
[`StudyCase.hs:208`](../study/fold-material/StudyCase.hs#L208)), so migrating either
later is a rename. [05](05-prd-library-additions.md) adds it.
`creaseDirections` keeps its exact test
([#111](https://github.com/avalonalex/senbazuru/issues/111)).

**Why the state rule** ([gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md)
"Recommendation"). The *state rule*, the at-rest rule above, was chosen over three
alternatives: writing each crease's intent, M or V, at 0; writing U at 0; and
writing what each crease will be at the end of the sequence.

- It alone agrees with all three written authorities: FOLD's sign rule, the
  `Assignment` haddock
  ([`Types.hs:298-313`](../src/Senbazuru/Fold/Types.hs#L298-L313)) and
  `flatAngleFor` ([`Creasing.hs:316-320`](../src/Senbazuru/Fold/Creasing.hs#L316-L320)).
- It needs no look-ahead: each frame depends only on the steps before it. The
  end-of-sequence rule must run the whole sequence before writing the first frame,
  which a CLI reporting the first failing step cannot do.
- Writing square-base's flat guides as M made `check` report a false Maekawa
  violation, measured with a prebuilt binary from 2026-09-07.

**Every emitted frame** has explicit `edges_foldAngle` (otherwise the writer
refuses, as `WriteMissingAngles`, §12), no non-finite number (`WriteNonFiniteAngle`),
never uses U, and never writes M or V at 0. The material consumer reads intent from
records, never from written F/M/V ([07](07-prd-material-consumption.md)).
`Sequence.Record.writtenStates` applies these rules and the displays once, and both
the writer and the page call it, so the page draws exactly the states the file holds
([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).

**Layout.**

- *Key frame.* Metadata only, with no vertex-indexed data until
  [#73](https://github.com/avalonalex/senbazuru/issues/73) separates file keys from
  frame keys. A record that is not vertex-indexed, such as
  [07](07-prd-material-consumption.md)'s `senbazuru:unsettled`, may sit there.
- *`file_frames`.* State 0, the start; then, for each step that writes a state, its
  authored `sample` poses in parameter order and its end state
  ([D24](decisions.md#d24-states-figures-and-their-numbers)). State k is
  `file_frames[k]`.
- *`--frame`.* Every verb counts the key frame as frame 0: `allFrames` puts it first
  ([`Types.hs:209-210`](../src/Senbazuru/Fold/Types.hs#L209-L210)), and `--frame`'s
  help says "default: 0, the key frame"
  ([`Cli.hs:484-493`](../app/Senbazuru/Cli.hs#L484-L493)). So state k is
  `--frame k+1`. **That looks off by one and is not:** the written key frame holds
  no state. `bird-base-sequence.fold` is laid out the same way, with a key frame of
  no vertices and 16 states [jq], which `docs/usage.md` calls frames 1–16
  ([`usage.md:1017-1018`](../docs/usage.md)).
- *Vendor keys.* `senbazuru:material_coords` and `senbazuru:assurance` go only on
  `file_frames` entries, written after the last transform.

**`frame_classes`.** A frame is `creasePattern` only when every angle is 0 *and*
every face shows its top towards +z in the written coordinates: its material-winding
ring has positive signed area in written x, y. Every other frame is `foldedForm`.
`faces_vertices` keep the material winding, so a turned face draws its back, and a
`white side up` sheet's first state is `foldedForm` although it is flat.

**File header.** `writeSequence :: FileHeader -> Run -> Either SequenceError FoldFile`
(**SKETCH**) writes `file_spec` 1.2, a `file_creator` naming senbazuru, `file_title`
from the sequence title, `file_classes ["diagrams"]`, and optional `file_author` and
`file_description`. The sheet's `file_classes`
and top-level unknown keys are not copied, a stated omission until #73.

**Captions and assurance point opposite ways, on purpose.**

- A state's `frame_title` is the caption of the next step that writes a state: the
  step *leaving* it. The last state's is `closing`, which the source writes after
  the last step and the tree stores as `hClosing`
  ([D12](decisions.md#d12-the-text-syntax)). A sample state has no caption.
- Its `senbazuru:assurance` is the evidence of the step that *produced* it, and is
  absent on state 0. Absent is not empty.

For §1, where the fixture's own values come from [jq]:

| State | Angles 8–11 | Fixture assignments | Written assignments | `frame_classes` | `frame_title` | `senbazuru:assurance` |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 0, 0, 0, 0 | M, V, M, M | F, F, F, F | `creasePattern` | "Fold the left half behind, onto the right." | absent |
| 1 | −180, 0, −180, 0 | M, V, M, M | M, F, M, F | `foldedForm` | "Fold the top half down in front, onto the bottom." | step `half`'s |
| 2 | −180, 180, −180, −180 | M, V, M, M | M, V, M, M | `foldedForm` | "Folded into quarters." (`closing`) | step `quarter`'s |

The fixture's titles name states instead ("Step 1: the flat sheet") [jq]. The
fixture's key frame is its state 0, so its states and the written file's share
numbers, and [09 §2.2](09-testing-and-acceptance.md#22-test-1-folding-equivalence-m2)
compares them state by state.

## 12. Refusal catalogue

**Message shape.**

- A `SequenceError` message is "step N (name)", then the author's reference text,
  then the nested error's `explain`, never reworded
  ([`Explain.hs:41-43`](../src/Senbazuru/Explain.hs#L41-L43)).
- It carries no location, because a Haskell-built sequence has none. The CLI
  prefixes `path:line:col` ([04](04-prd-sequence-source-and-cli.md)).
- It names the step instead, the only place a Haskell author can look
  ([D20](decisions.md#d20-errors), [C11](decisions.md#changes-since-draft-v2)).
  `StaticRefused Place Span StaticProblem` carries
  `data Place = InHeader | InStep Int (Maybe Name)`, and a problem in the header
  reads `header` instead of `step N`
  ([03](03-prd-embedded-dsl.md#refusals-from-a-built-sequence)).
- Ids appear as "(internal edge 37)", so an author knows they did not write them.

`SequenceError` (**SKETCH**, [decisions §5](decisions.md#5-type-sketch)) has six
constructors, and the table's *Carried by* column names what each holds:
`ParseFailed` a `ParseProblem`; `StaticRefused` a `StaticProblem`; `SheetRefused`,
with the sheet path as written, a `SheetProblem`; `ResolveRefused` a
`ResolveProblem`; `StepRefused` a `MoveFailure`; and `WriteRefused`, with the state
number, a `WriteProblem`.

The example below (**SKETCH**) is a hypothetical step on `bird-base.fold`:

```text
step 2 (kite): (1/2, 0.207): a typed point 1.07e-4 sheet lengths from (internal vertex 9) at (1/2, 0.2071067811865475), outside the tolerance but inside the near-miss band 0.001; name the vertex by a construction
```

**Table** (**SKETCH**). Names that exist in code are cited. The rest are proposals
for [05](05-prd-library-additions.md) and [04](04-prd-sequence-source-and-cli.md) to
finalise, and they are what `expect refused` matches. `MoveFailure` wraps the
selection, macro, stacking and library errors. Every sequence-level problem type
lives in `Sequence.Error` with its `Explain` instance, which is also where
`expect refused` finds its kind names ([D20](decisions.md#d20-errors),
[D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).

| Refusal | Carried by | Trigger | Message names |
| --- | --- | --- | --- |
| `ViewWordForMaterial` | `ParseProblem` (04) | `left`/`right`/`top`/`bottom`/`front`/`behind` where a material feature is expected | the word; the compass spelling |
| `UnknownName`, `DuplicateName` | `StaticProblem` | a reference nothing binds; a second binding | the name |
| `WrongKind` | `StaticProblem` | a point name used as a line, a step name as a point, and so on | the name; expected and actual kind |
| `ZeroDenominator` | a `Hint` in `ParseProblem` (04) | `n/0`. It is a parse error, not a static one: no `Rational` can hold it, so no tree reaches `Sequence.Check` with one ([D12](decisions.md#d12-the-text-syntax)) | the number |
| `RatioOutOfRange`, `NotEighths`, `NotQuarters`, `ParameterOutOfRange` | `StaticProblem` | `fraction r along` with r outside [0, 1]; `rotate k/8` with k outside 1–7; `turned k/4` with k outside 1–3; a fresh macro's `until` outside (0, max], including a negative one built in Haskell, or a `sample` outside (reached, A), with reached = 0 for a fresh macro. A `continue`'s reached is known only when it runs, so that bound is checked then | the number; its allowed range |
| `NotANameToken`, `ReservedWordAsName`, `LayerCountNotPositive`, `SignNotAllowed` | `StaticProblem` | values only a Haskell builder can make ([03](03-prd-embedded-dsl.md#refusals-from-a-built-sequence)): a `Name` that is not a name token, such as `Name "two words"`; a reserved word as a name, compared ignoring case, such as `Name "north-west"`; `TopLayers 0`; a signed angle such as `Degrees (-90)` in a `Fold`, where the text allows a sign only in coordinates, pose angles and settle `except` angles | the step; the name or value |
| `EmptyStep` | `StaticProblem` | a step with no move other than `let` ([D12](decisions.md#d12-the-text-syntax)) | the step |
| `NotASingleMacro`, `NotAFigure`, `HingeOfSeveralMoves` | `StaticProblem` | `continue`, `unfold`/`repeat`, or `hinge of` naming the wrong kind of step | the name |
| `RepeatUnmappable` | `StaticProblem` | `repeat` over a step containing `model` or `top N`, or an isometry point that is a construction | the move |
| `UnknownRefusalKind` | `StaticProblem` | an `expect refused` KIND not in this table | KIND |
| `SheetHasNoVertices`, `SheetAlreadyFolded` | `SheetProblem`, in `SheetRefused` | key frame empty; `frameKind` `FoldedForm`, meaning z relief or the `foldedForm` class ([`Query.hs:459-463`](../src/Senbazuru/Fold/Query.hs#L459-L463)) | path; `file_frames` count, or the z span or class |
| `WriteMissingAngles`, `WriteNonFiniteAngle` | `WriteProblem`, in `WriteRefused` | a state to write without explicit `edges_foldAngle` (§11); a non-finite angle ([05](05-prd-library-additions.md)) | the state; the edge, internal |
| `NearMiss` | `ResolveProblem` | a typed literal in a position slot, near a vertex but not on it | literal; internal vertex; distance |
| `VertexMiss`, `TwoVerticesWithin` | `ResolveProblem` | vertex slot: no vertex, or two, within tolerance | nearest vertices; distances |
| `NotInOneFace` | `ResolveProblem` | region slot on a crease or vertex | the point; face count; where it appears as seen |
| `OffThePaper`, `PlacementsDisagree` | `ResolveProblem` | a position on no face; faces placing it apart | the point; the distance |
| `EdgeNotStraight`, `CreaseNotStraight`, `EmptyCrease` | `ResolveProblem` | `edge S` or `crease of NAME` not collinear now; `crease of` a step that made none | the segments' current ends |
| `ConstructionInTheAir` | `ResolveProblem` | a construction or `model` on a state that is not flat | the construction |
| `NoSolution`, `NeedsNearest`, `NearestAmbiguous`, `DegenerateConstruction` | `ResolveProblem` | 0 solutions; ≥2 without `nearest`; `nearest` leaving 0 or ≥2; coincident inputs | every candidate line, off-paper ones included |
| `NoCreaseThere` | `ResolveProblem` | `crease [P, Q]` with no existing edges along it, or a gap | the uncovered stretch |
| `MarkOnSeveralLayers`, `EndTie`, `LandmarkAmbiguous` | `ResolveProblem` | §4.5; `EndTie` §4.2 | the candidate material points |
| `SeedMissing` | `SelectionError` | a non-alignment line with no `moving P` | both sides, each with a working seed |
| `SeedOnTheLine`, `SegmentStraddles`, `SeedSplit` | `SelectionError` | §4.4; §4.3 | the seed or segment; the components |
| `UnorderedOverlap`, `DepthChangesAlong` | `SelectionError` | overlap on the line with no accepted order; a depth that changes along the line | internal faces; a point |
| `SelectionCoupled`, `NoUncoupledFlap` | `SelectionError` | the restricted cut stays joined; `top flap` coupled at every N | the joining face, as a material point |
| `FlapCovered` | `SelectionError` | a stationary face nearer on the turning side | moving and covering faces; a point |
| `LineStopsInSelectedFace`, `NothingSelected`, `ExistingHingeFlat`, `LayersInTheAir` | `SelectionError` | an end strictly inside a selected face; nothing selected; an F hinge; layer words with paper in the air | the end as given; the crease's material segment |
| `NoMatch`, `SeveralMatches` | `MacroBindError` | 0 or ≥2 signature matches | the vertex, measured sectors and failed clause; every candidate as its disambiguator |
| `KeepingNotAPair`, `PetalGeometryUnsupported`, `DegenerateRabbitEar` | `MacroBindError` | §8.2, §8.3 | Q1, Q2; measured angles |
| `RoleCreaseChanged`, `MacroStateChanged`, `NotBeyondReached` | `MacroBindError` | §8.4 | the crease; expected and actual angle; `reached` |
| `RelationOnOneFace`, `RelationNotOverlapping`, `RelationsContradict` | the library's `StackingError` ([05](05-prd-library-additions.md)), wrapped by `StackingChoiceError` | §7: a relation's two points in one face; a relation's faces do not overlap; relations leave none | the relations |
| `StillAmbiguous`, `SeveralStackings` | `StackingChoiceError` | §7: relations leave two or more; no relations and several stackings, including a macro landing flat (§8.1) | count; open pairs as `layers … above …` |
| `GaveUpStacking` | `FoldError` ([`Query.hs:139`](../src/Senbazuru/Fold/Query.hs#L139)), wrapped as `StackingRefused` in `StackingError` ([`Stacking.hs:448`](../src/Senbazuru/Origami/Stacking.hs#L448)) | budget exhausted | the budget |
| `FlapCoupled`, `FlapNotHinge`, `FlapNotBoundary`, `FlapUnalignedCrease`, `FlapEndpointOrder`, `FlapStackOrder`, `FlapStartMismatch` | `FlapError` ([`Flap.hs:104-121`](../src/Senbazuru/Origami/Flap.hs#L104-L121)) in `MoveFailure` | the hinge turn is refused | the library's words; ids as internal |
| `FlapStationaryNotFlat` | `FlapError`, new with `prepareFlapToward` ([05](05-prd-library-additions.md)), in `MoveFailure` | the first hinge segment's stationary face normal is not ±ẑ within 1e-12 (§5.3); to be replaced by `FlapMovingNotFlat`, with `FlapMovesBothWays` beside it ([D5](decisions.md#d5-presentation-and-the-readers-side)'s amendment) | the face, internal |
| `TornAt`, `AngleNotAchieved` | `FoldingError` ([`Folding.hs:154`](../src/Senbazuru/Origami/Folding.hs#L154), [`:170`](../src/Senbazuru/Origami/Folding.hs#L170)) in `MoveFailure` | a pose, checkpoint or macro pose fails to close | the vertex or crease, internal |
| `LineStopsOnTheModel` | `ThroughError` ([`ThroughLayers.hs:154`](../src/Senbazuru/Origami/ThroughLayers.hs#L154)) in `MoveFailure` | a line end inside a face while creasing through layers | the point given, after the flag-leak fix ([05](05-prd-library-additions.md)) |
| `ReanchorNotFlat` | `MoveFailure` | §2.3 | the face, as a material point |
| `JoinBroken` | `MoveFailure` | invariant 6 | which quantity differed, and by how much |
| `MoveLeavesFigure` | `MoveFailure` | §6.5 | the move; a material point; "start a new step" |
| `RepeatNotSymmetric`, `CheckpointOutlineDiffers` | `MoveFailure` | §9 | the first differing crease, hinge turn or outline point |
| `UnfoldChangedSince` | `MoveFailure` | §6.4: a later move changed a crease the unfold would turn back | the crease's material segment |
| `NotModelled` | `MoveFailure`, reaching the CLI through `runRefusal` from a run that returned `Right` | §9 | the quoted text |
| `RefusalNotRaised`, `RefusedDifferently` | `MoveFailure` | §9 | the kinds |
| `NoRoute` | `PoseError` | `recordPoseAt` on a route-less record | the evidence value |
| `NotAProperRotation` | `MoveFailure` | a presentation `Rigid` that `isProperRotation` rejects. The language cannot build one, so the check is tested directly on a mirror and on `diag(2, 1/2, 1)` ([05](05-prd-library-additions.md)) | det |
| `SettleOnNoMove`, `SettleStartNotFlat`, `SettleNoPose`, `SettleNoRest`, `NoDifference` | `SettleStepError`, in `Sequence.Material`, which wraps the solver's own `SettleError` as `SettleFailed` ([D14](decisions.md#d14-material-consumption), [C6](decisions.md#changes-since-draft-v2)) | [07](07-prd-material-consumption.md#settlespec-and-settleinput-two-contracts) | — |

## 13. What rests on the Python re-implementation

These claims come from
[`research/scripts/layer-selection-analyse.py`](research/scripts/layer-selection-analyse.py).
That script is not senbazuru. It closes loops to 3.0e-13, and it puts vertex 2 at
folded (1, 0), the tip position
[`CraneWingSpec.hs:99`](../test/CraneWingSpec.hs#L99) expects at progress 0 (both
rerun here, [check P](#check-p)). Each must be reproduced
in Haskell before a PRD relies on it
([gap-layer-selective-folds](research/gap-layer-selective-folds.md) "Unverified").

From §6.3's crane example:

- the folded positions of vertices 2 and 28;
- the 16 crossed faces;
- the seed component of faces 2, 3, 6 and 7, which M4's acceptance depends on.

From the three results listed after it:

- one layer of the wing is coupled;
- `top flap` on a square base is two sheets;
- a quarter-fold seed near (1, 0) is covered.

One more is inferred from test assertions rather than solved: that wing B lies on
wing A's +z side, so "top 2 from +z" on the crane is wing B
([gap-layer-selective-folds](research/gap-layer-selective-folds.md) finding 14 and
"Unverified"). §9's `expect refused FlapCovered` example rests on it.

## 14. Gaps this file raised, and where they were decided

An earlier draft of this file proposed rules for fourteen questions that the
previous decision record left open. [decisions.md](decisions.md) has decided every
one ([C11](decisions.md#changes-since-draft-v2) for G14,
[C19](decisions.md#changes-since-draft-v2) for G1,
[C21](decisions.md#changes-since-draft-v2) for G2–G13), and each rule is now stated
in the section named below. The numbers G1–G14 stay because the decision record
cites them.

| # | Question | Decided rule | Decision | Stated in |
| --- | --- | --- | --- | --- |
| G1 | An anchor that a new crease passes through | the anchor moves to the vertex mean of the largest face containing it that the move does not turn. The draft also said 09's authoring test meets this; it does not, because that test writes `anchor (3/4, 1/4)` | [D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs) | §2.3 |
| G2 | The moving side for O5, O6 and O7 | the side containing P; O6 is refused if Q lies on the other side | [D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot) | §4.3 |
| G3 | The direction of `turned k/4`, and the axis of `white side up` | anticlockwise on the sheet as the file draws it; `left-right` | [D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused), [D5](decisions.md#d5-presentation-and-the-readers-side) | §9, §5.1 |
| G4 | `repeat` of a move that adds no crease, where comparing creases compares nothing | each hinge segment's material image must also turn by the same net angle change | [D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused) | §9 |
| G5 | `unfold` after a later move changed one of its creases | refused as `UnfoldChangedSince`, naming the crease | [D22](decisions.md#d22-figures-holding-several-moves) | §6.4 |
| G6 | What lockstep means for `together` | the same fraction of each member's own range; members sharing a crease are refused | [D9](decisions.md#d9-macro-moves-as-named-angle-relations) | §8.5 |
| G7 | An order for "weakest", and a value for `anchor` and `mark` | `StateOnly` < `Sampled` < `SweptHinge` < `Presented` < `NoMotion`, by how much of the route a reader takes on trust; `anchor` and `mark` carry `NoMotion`, meaning no paper moved | [D10](decisions.md#d10-assurance-as-evidence-values) | §10, §6.1 |
| G8 | A slot needing a material point, filled by a folded position | resolved as `mark` is | [D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot) | §4.5 |
| G9 | A macro landing flat with several stackings | refused, listing the open pairs | [D9](decisions.md#d9-macro-moves-as-named-angle-relations) | §8.1 |
| G10 | `sample` values at or beyond A, or at or below `reached` | refused | [D9](decisions.md#d9-macro-moves-as-named-angle-relations) | §8.5, §12 |
| G11 | Compass names on a sheet whose outline is not its bounding box | `corner X` needs a boundary vertex at that corner of the box, and `edge S` boundary edges covering that side; `centre` and `(u, v)` are always defined | [D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot) | §4.1 |
| G12 | A step holding only `expect refused` | it writes no state and is not a figure | [D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused), [D24](decisions.md#d24-states-figures-and-their-numbers) | §9 |
| G13 | A default anchor, a vertex mean, not strictly inside its non-convex face | refused, asking for `anchor P` | [D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs) | §2.3 |
| G14 | Refusals from `sheetState` and from the writer | `SequenceError` gains `SheetRefused` and `WriteRefused` | [D20](decisions.md#d20-errors) | §2.2, §12 |

## 15. Open questions for the owner

The owner decisions this file depends on, numbered as in
[decisions §9](decisions.md#9-owner-decisions) and
[10 §6](10-roadmap-risks-questions.md#6-owner-decisions). Each has a recommended
default, which this file follows:

- **2.** The `nearMissBand` default. Recommended: 1e-3 sheet lengths.
- **3.** Re-anchor automatically, or refuse, when a move carries the anchor.
  Recommended: re-anchor, printed by `--report`.
- **8.** The blintz direction. The *manifest*, the study's table of cases and their
  angles (`study/fold-material/cases.json`), folds corners up; the recipe folds them
  down
  ([A2](research/A2-study-recipes-as-proto-dsl.md) F3). Recommended: the recipe's
  `fold behind`, which §6.2 follows.
- **9.** Whether `quarter-fold-steps.fold` migrates to the state rule (§11's
  "Fixture" and "Written" columns differ in states 0 and 1), or stays as the
  regression. Recommended: it stays.
- **10.** Eighth turns with trigonometry, or a `sheet square as diamond` start.
  Recommended: trigonometry, with platform bits in written coordinates stated.

G1–G14 are no longer open (§14).

## Appendix: checks behind the examples

All were run from the repository root on 2026-09-14/15. Outputs are abbreviated to
the lines cited.

### Check Q

`quarter-fold-steps.fold`, python3:

```bash
python3 - <<'EOF'
import json
d=json.load(open("examples/quarter-fold-steps.fold"))
fr=[d]+d["file_frames"]; V=d["vertices_coords"]; E=d["edges_vertices"]; F=d["faces_vertices"]
def area(r,P): return sum(P[r[i]][0]*P[r[(i+1)%len(r)]][1]-P[r[(i+1)%len(r)]][0]*P[r[i]][1] for i in range(len(r)))/2
for i,r in enumerate(F): print("face",i,r,"area",area(r,V),"mean",tuple(sum(V[k][j] for k in r)/len(r) for j in (0,1)))
for e in range(8,12):
  joins=[i for i,r in enumerate(F) if any({r[k],r[(k+1)%len(r)]}==set(E[e]) for k in range(len(r)))]
  print("edge",e,E[e],[V[k] for k in E[e]],d["edges_assignment"][e],"faces",joins,"angles",[f.get("edges_foldAngle",[None]*12)[e] for f in fr])
for n,f in enumerate(fr):
  P=f["vertices_coords"]; print("frame",n,"moved",[k for k in range(9) if P[k]!=V[k]],"bbox x",min(p[0] for p in P),max(p[0] for p in P),"y",min(p[1] for p in P),max(p[1] for p in P),"signed areas",[area(r,P) for r in f.get("faces_vertices",F)])
P1=fr[1]["vertices_coords"]; print("north-edge vertices (material y=1) in frame 1:",[(k,V[k],P1[k]) for k in range(9) if V[k][1]==1])
P2=fr[2]["vertices_coords"]; print("vertices at (1,0) in frame 2:",[(k,V[k]) for k in range(9) if P2[k][:2]==[1,0]])
EOF
```

Output (here "frame n" counts the fixture's key frame as 0, so frame n is state n):
every face has area 0.25, with means (0.75, 0.25), (0.75, 0.75),
(0.25, 0.75) and (0.25, 0.25); the edge rows of §1's table; frame 1 moved
`[0, 3, 7]`, with signed areas `[0.25, 0.25, -0.25, -0.25]`; frame 2 moved
`[0, 2, 3, 6, 7]`, box x 0.5–1 and y 0–0.5, signed areas `[0.25, -0.25, 0.25, -0.25]`;
vertex 3 at `[1, 1]` in frame 1; vertices 0–3 at (1, 0) in frame 2.

Assignments and titles, jq:

```bash
jq -c '[.edges_assignment[8:12], .edges_foldAngle[8:12]], (.file_frames[] | [.edges_assignment[8:12], .edges_foldAngle[8:12]])' examples/quarter-fold-steps.fold
jq -c '[.frame_title, .frame_classes], (.file_frames[]|[.frame_title,.frame_classes])' examples/quarter-fold-steps.fold
jq -c '{nv:(.vertices_coords|length), frames:(.file_frames|length)}' examples/bird-base-sequence.fold
```

The three commands print:

1. `["M","V","M","M"]` in all three frames;
2. "Step 1: the flat sheet" `creasePattern`, then two `foldedForm` frames;
3. `{"nv":0,"frames":16}` for the bird sequence file.

The seed step `quarter`'s record keeps (§6.3), run on 2026-09-15. It lists the edges
at material y = 1, each with its length, its lower x, and its one face as id, ring
and vertex mean:

```bash
python3 - <<'EOF'
import json
d=json.load(open("examples/quarter-fold-steps.fold"))
V=d["vertices_coords"]; E=d["edges_vertices"]; F=d["faces_vertices"]
north=[i for i,(a,b) in enumerate(E) if V[a][1]==1 and V[b][1]==1]
for i in north:
  a,b=E[i]
  faces=[j for j,r in enumerate(F) if any({r[k],r[(k+1)%len(r)]}=={a,b} for k in range(len(r)))]
  print("edge",i,"length",abs(V[a][0]-V[b][0]),"min x",min(V[a][0],V[b][0]),[(j,F[j],tuple(sum(V[k][c] for k in F[j])/len(F[j]) for c in (0,1))) for j in faces])
EOF
```

```text
edge 4 length 0.5 min x 0.5 [(1, [8, 5, 2, 6], (0.75, 0.75))]
edge 5 length 0.5 min x 0 [(2, [8, 6, 3, 7], (0.25, 0.75))]
```

### Check B

`blintz-base.fold`, exact fractions:

```bash
python3 - <<'EOF'
import json; from fractions import Fraction as Fr
d=json.load(open("examples/blintz-base.fold")); V=[tuple(map(Fr,v)) for v in d["vertices_coords"]]; E=d["edges_vertices"]
c=(Fr(1,2),Fr(1,2)); print("centre is a vertex:", c in V)
ring=[4,5,6,7]
print("centre left of every edge of ring 4-5-6-7:",[str((V[b][0]-V[a][0])*(c[1]-V[a][1])-(V[b][1]-V[a][1])*(c[0]-V[a][0])) for a,b in zip(ring,ring[1:]+ring[:1])])
refl=lambda p:(p[1]+Fr(1,2),p[0]-Fr(1,2))
print("corner (1,0) reflected in x-y=1/2:",tuple(map(str,refl((Fr(1),Fr(0))))), " (1/2,0) ->",tuple(map(str,refl((Fr(1,2),Fr(0))))))
rot=lambda p:(1-p[1],p[0])
print("edge 8 turned a quarter anticlockwise about the centre:",sorted(tuple(map(str,rot(V[k]))) for k in E[8]),"edge 9:",sorted(tuple(map(str,V[k])) for k in E[9]))
def area(r): return sum(V[r[i]][0]*V[r[(i+1)%len(r)]][1]-V[r[(i+1)%len(r)]][0]*V[r[i]][1] for i in range(len(r)))/2
for r in ([4,5,6,7],[0,4,7],[4,1,5],[5,2,6],[6,3,7]): print(r,"area",area(r))
EOF
```

Output: `centre is a vertex: False`; `'1/4'` for all four edges of ring 4–5–6–7;
(1, 0) reflects to (1/2, 1/2) while (1/2, 0) stays; edge 8's quarter-turn image
equals edge 9, `[('1', '1/2'), ('1/2', '1')]`; area 1/2 for the central square and
1/8 for each corner.

Vertices and edges 8–11:

```bash
jq -c '.vertices_coords, [.edges_assignment[8:12], .edges_foldAngle[8:12]]' examples/blintz-base.fold
```

This prints
`[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,1.0],[0.5,0.0],[1.0,0.5],[0.5,1.0],[0.0,0.5]]`
and `[["M","M","M","M"],[-180,-180,-180,-180]]`. The vertices are corners and edge
midpoints only, so the vertices nearest the centre are 1/2 away. That O2 of each
corner with the centre contains its chord is shown by the exact-fraction script in
[00](00-overview.md#the-problem-in-one-example), rerun unchanged on 2026-09-15. It
prints:

```text
south-east 8 M-180 (1/2, 0) (1, 1/2)
north-east 9 M-180 (1, 1/2) (1/2, 1)
north-west 10 M-180 (1/2, 1) (0, 1/2)
south-west 11 M-180 (0, 1/2) (1/2, 0)
centre on a vertex: False | centre on an edge: False
```

### Check S

`bird-base.fold` and `square-base.fold`:

```bash
python3 - <<'EOF'
import json, math
def segd(p,a,b):
  dx,dy=b[0]-a[0],b[1]-a[1]; t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy))); return math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
for f in ["bird-base","square-base"]:
  d=json.load(open(f"examples/{f}.fold")); V=d["vertices_coords"]; E=d["edges_vertices"]; A=d["edges_assignment"]; G=d["edges_foldAngle"]
  c=[i for i,v in enumerate(V) if v==[0.5,0.5]][0]
  print(f,"centre vertex",c,"rays:",sorted((round(math.degrees(math.atan2(V[b if a==c else a][1]-.5,V[b if a==c else a][0]-.5))%360,1),i,A[i],V[b if a==c else a]) for i,(a,b) in enumerate(E) if c in (a,b)))
  print(f,"F edges:",[(i,[V[k] for k in E[i]]) for i,a in enumerate(A) if a=="F"],"nonzero angles:",sum(1 for g in G if g!=0))
d=json.load(open("examples/bird-base.fold")); V=d["vertices_coords"]; E=d["edges_vertices"]
print("v9",V[9]); p=(0.5,0.207); print("(1/2, 0.207) nearest vertices:",sorted((math.dist(p,v),i) for i,v in enumerate(V))[:2])
q=(29/50,2/5); print("(29/50, 2/5) min distance to any edge:",min(segd(q,V[a],V[b]) for a,b in E))
print("corners joined to both ends of hinge 26:",[k for k in range(4) if any(set(e)=={k,E[26][0]} for e in E) and any(set(e)=={k,E[26][1]} for e in E)],"hinge 27:",[k for k in range(4) if any(set(e)=={k,E[27][0]} for e in E) and any(set(e)=={k,E[27][1]} for e in E)])
EOF
```

Output: the two star rows of §8.2's table, with far ends; bird F edges 11, 15,
19 and 23, each an outer midline segment; 16 nonzero angles on the bird and 6 on
the square base; `v9 [0.5, 0.2071067811865475]`; `(0.0001067811865474999, 9)` as
the vertex nearest (1/2, 0.207); `0.07982756057296904` from (29/50, 2/5) to the
nearest edge; corners `[1]` and `[3]` for hinges 26 and 27.

### Check C

`crane.fold`:

```bash
python3 - <<'EOF'
import json, math
d=json.load(open("examples/crane.fold")); V=d["vertices_coords"]; E=d["edges_vertices"]; F=d["faces_vertices"]
def segd(p,a,b):
  dx,dy=b[0]-a[0],b[1]-a[1]; t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy))); return math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
def inside(p,r):
  c=False
  for i in range(len(r)):
    a,b=V[r[i]],V[r[(i+1)%len(r)]]
    if (a[1]>p[1])!=(b[1]>p[1]) and p[0]<a[0]+(p[1]-a[1])*(b[0]-a[0])/(b[1]-a[1]): c=not c
  return c
for name,p in [("anchor (19/20,1/3)",(19/20,1/3)),("tail (1/4,1/5)",(1/4,1/5)),("body (3/8,5/9)",(3/8,5/9)),("body (4/9,3/8)",(4/9,3/8)),("seed (0.02,0.97)",(0.02,0.97))]:
  print(name,"faces",[i for i,r in enumerate(F) if inside(p,r)],"min edge distance",round(min(segd(p,V[a],V[b]) for a,b in E),4))
i24=min(range(len(V)),key=lambda i:math.dist(V[i],(0.5,0.5))); print("nearest vertex to (1/2,1/2):",i24,V[i24],math.dist(V[i24],(0.5,0.5)))
print("faces containing vertex 2:",[i for i,r in enumerate(F) if 2 in r])
EOF
```

Output: faces `[0]`, `[10]`, `[27]`, `[29]` and `[7]`, at minimum edge distances
0.05, 0.0274, 0.0491, 0.0491 and 0.007; vertex 24 at `2.1431618279190542e-14` from
(1/2, 1/2); vertex 2 in faces `[2, 3, 6, 7]`.

§2.2's table:

```bash
for f in blintz-base bird-base crane quarter-fold-steps; do jq -c --arg f $f '{f:$f, nv:(.vertices_coords|length), nf:(.faces_vertices|length), nonzero:([.edges_foldAngle[]?|select(.!=0)]|length), asg:(.edges_assignment|group_by(.)|map({(.[0]):length})|add)}' examples/$f.fold; done
jq 'has("edges_foldAngle")' examples/crane.fold
```

```text
{"f":"blintz-base","nv":8,"nf":0,"nonzero":4,"asg":{"B":8,"M":4}}
{"f":"bird-base","nv":13,"nf":0,"nonzero":16,"asg":{"B":8,"F":4,"M":12,"V":4}}
{"f":"crane","nv":58,"nf":72,"nonzero":0,"asg":{"B":10,"F":20,"M":58,"V":41}}
{"f":"quarter-fold-steps","nv":9,"nf":4,"nonzero":0,"asg":{"B":8,"M":3,"V":1}}
false
```

### Check P

The Python re-implementation of folding (not senbazuru):

```bash
python3 PRDs/research/scripts/layer-selection-analyse.py fold examples/crane.fold | grep -E "^faces|^v 2 |^v 28 "
python3 PRDs/research/scripts/layer-selection-analyse.py line examples/crane.fold 0,0.25 2,0.25 0.02,0.97 | grep -E "crossed faces|component_faces|ends strictly"
python3 -c 'import json;d=json.load(open("examples/crane.fold"));print(d["vertices_coords"][2],d["vertices_coords"][28])'
```

```text
faces 72 closure 3.038435658516928e-13
v 2 (5.88685e-15, 1) -> (1, 4.60769e-14)
v 28 (0.5, 1) -> (1, 0.5)
ends strictly inside a face: []
crossed faces: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
component_faces [2, 3, 6, 7]
[5.886846565772426e-15, 0.9999999999999996] [0.49999999999998834, 1]
```

### Check X

`bird-base.cp` extent:

```bash
python3 -c 'L=[l.split() for l in open("examples/bird-base.cp") if l.strip()];xs=[float(t[i]) for t in L for i in (1,3)];ys=[float(t[i]) for t in L for i in (2,4)];print(len(L),"lines; x",min(xs),max(xs),"y",min(ys),max(ys))'
```

```text
26 lines; x -200.0 200.00000000000003 y -200.0 200.0
```
