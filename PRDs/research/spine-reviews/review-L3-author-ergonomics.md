# Review L3: author ergonomics of the sequence language (D2, D5, D9, D12, §5)

> **Historical record.** Part of the design review of the PRD series, kept so its citations resolve. Line numbers cite the draft named in the file; the current decisions are [../../decisions.md](../../decisions.md).

Lens: an origami-literate author, and a Haskell programmer who has never folded.
The question is whether the spine's vocabulary can write real book steps and
whether the result reads like a book. Reviewed 2026-09-14 against `568dcb6`.
Nothing in the repository was modified or built.

Evidence used:

- `jq` and `python3` on `examples/quarter-fold-steps.fold`, `blintz-base.fold`,
  `bird-base.fold` and `square-base.fold`;
- the gap note's own script (`../scripts/layer-selection-analyse.py line examples/crane.fold
  0,0.25 2,0.25 0.02,0.97`), rerun here;
- `sed` on `Origami/Folding.hs:34-56`, `Render/Camera.hs:176-194`,
  `Diagram/Style.hs:112-142`, `docs/glossary.md:28-48`,
  `study/fold-material/README.md:415-430` and
  `docs/notes/precreases-and-target-states.md`;
- `gh issue view 97`;
- one WebFetch of https://origami.me/crane/ (paraphrased; copyrighted);
- one web search for the `.fseq` extension;
- the research notes E1, E2, Z-critic, gap-layer-selective-folds,
  gap-exact-landmarks-and-macro-binding and gap-step-annotation-channel.

## 1. The first twelve crane steps, written in the spine's syntax as it stands

Steps are from origami.me's traditional crane, paraphrased, which has 28 steps.
The spelling follows D2, D12 and §5 exactly, and bracketed letters mark the
failures explained below the block. Material names are the spine's
(`corner bottom-left` = material (0,0)).

```text
fseq 1
title "Traditional crane"
sheet square
anchor (5/8, 1/8)      # [A] typed by hand to avoid every crease the file will make
                       # [B] book step 1 says coloured side up, diamond position: no header for it

step "Fold and unfold both diagonals."                                  # crane 1
  precrease valley corner bottom-left-corner top-right flap containing (3/4, 1/4)   # [C]
  precrease valley corner bottom-right-corner top-left flap containing (1/4, 1/4)   # [C][D]
step "Turn over."                                                       # crane 2
  turn over                                                             # ok; default axis unstated
step "Fold and unfold in half both ways."                               # crane 3
  precrease valley edge left to edge right                              # [E]
  precrease valley edge bottom to edge top                              # [D][E]
step "Collapse into a square base."                                     # crane 4
  collapse at centre                                                    # [F] NOT EXPRESSIBLE
step kite "Fold the lower edges of the top flap to the centre line."    # crane 5
  fold valley corner bottom-left-midpoint of edge bottom to centre-corner bottom-left top 2 layers   # [G][H]
  fold valley corner bottom-left-midpoint of edge left to centre-corner bottom-left top 2 layers     # [D][G][H]
step top "Fold the top corner down."                                    # crane 6
  fold valley ??-?? flap containing centre                              # [I][J] NOT EXPRESSIBLE
step "Unfold."                                                          # crane 7
  unfold top
  unfold kite                                                           # [D][K]
step front "Petal fold the top layer."                                  # crane 8
  petal tip corner ?? to 180                                            # [G][L]
step "Turn over."                                                       # crane 9
  turn over
step "Fold and unfold the edges to the centre line."                    # crane 10
  precrease valley ... to ... top 2 layers                              # [C][D][G][H]
step "Repeat the petal fold."                                           # crane 11
  repeat front ??                                                       # [M] no text syntax
step "Fold the edges to the centre line, leaving a small gap."          # crane 12
  fold valley model (..)-(..) top ?? layers                             # [N] NOT EXPRESSIBLE exactly
```

- **[A]** The anchor must stay off every crease for 28 steps and on the
  stationary side of every fold (D3 invariant 5). No book states one, and the
  author has to find it with a calculator.
- **[B]** There is no header saying which side of the paper faces the reader,
  and "as seen" senses depend on it. The diamond position is a 1/8 turn, which
  D5's exact ±1 matrices cannot build.
- **[C]** `P-Q` needs a `flap containing` seed (D2, line 151-152), but the
  `Precrease` constructor has no seed field (§4, line 662). Also,
  `bottom-left-corner` does not lex unambiguously when `-` is both part of a
  keyword and the O1 operator.
- **[D]** Two moves in one figure. `seqSteps :: [Located (StepHeader, Step)]`
  (§4, line 674) holds one move per figure.
- **[E]** Correct as geometry. But material `edge left` is now on the reader's
  right, and "the first argument moves" then moves the half the reader calls
  right.
- **[F]** After steps 1–3 all eight rays at the centre carry intent, and the
  six-ray collapse signature matches four ways, or none, at that one vertex.
  `at P` cannot choose. See L3-1.
- **[G]** Which material half-edge is the reader's lower-left edge, or which
  material corner is the front petal's tip, depends on which diagonal stayed
  flat in step 4 and on the turn in step 2. The author has to unfold the model
  mentally, and nothing in the spine shows them the names.
- **[H]** A book says top flap. On a square base that flap is two sheets, and
  `top 1 layers` is refused as coupled (gap-layer finding 16).
- **[I]** The line runs through the points where step 5's creases meet the
  outer edges. The language has no `crease of kite`, and a `let` of the O3
  construction is either re-evaluated after the edges have moved or pinned by
  an undefined rule.
- **[J]** `centre` is a vertex, but a seed must lie strictly inside one face
  (D2, lines 137-138).
- **[K]** `Unfold Name` takes one step, and `kite` holds two moves.
- **[L]** `to 180` is a macro parameter, while `to` is also O2/O3.
- **[M]** `Repeat Symmetry [Name]` exists in §4, with no spelling and no
  definition of `Symmetry`.
- **[N]** A small gap is not a landmark; only `model (x, y)` decimals can say
  it.

**Steps 13–28, classified under the same vocabulary:**

| Crane step (paraphrase) | Spine v1 |
| --- | --- |
| 13, 16, 19, 22 turn over | yes |
| 14 repeat 12 | no: [M] and [N] |
| 15, 17, 21, 23 swing the top right flap to the left | syntax only with a hand-found material seed [G]. Semantics open (gap-layer open question 3) |
| 18 fold the top flap's lower corner up along the existing crease | only as a construction lying on existing creases (D8). `crease P-Q` names one material segment, not a multi-layer hinge |
| 20 repeat 18 | no: [M] |
| 24, 25 swivel folds | no syntax at all (D9 "later") |
| 26 mountain fold the head and unfold | the line is judged by eye: [N] |
| 27 inside reverse fold | no syntax at all |
| 28 open the wings, shape the body | bend; only the M6 `settle` request, with no move |

**Tally over 28 steps:**

| Outcome | Steps | Count |
| --- | --- | --- |
| Writable as a book writes them | the six turn-overs | 6 |
| Writable only with hand-computed material names or seeds and split figures | 1, 3, 5, 7, 8, 10, 15, 17, 18, 21, 23 | 11 |
| Not writable | 4, 6, 11, 12, 14, 20, 24–28 | 11 |

The objections below are the changes that move steps out of the last two rows.

## 2. Objections

### L3-1 (major, D9) `collapse at P` cannot express crane step 4 from precreases

The claim: the traditional crane precreases both diagonals, turns over, and
precreases both midlines. D3 keeps intent M/V on every precrease (spine
lines 181-182), so seen from the white side all eight centre rays carry
intent: diagonals M, midlines V.

- gap-exact finding 10 (lines 240-244) says an eight-ray star at 45° matches the
  six-ray signature four ways, one per opposite pair left out, and that only
  `F` guides disambiguate.
- Signs do not reduce the four. Leaving out a diagonal gives a square base
  (pair = diagonal M, four = midlines V). Leaving out a midline gives a
  waterbomb base (pair = midline V, four = diagonals M, with sectors
  45,90,45,45,90,45). Both have the pair and the four of opposite sign, which is
  what the signature asks for.
- If an intent-bearing ray at 0 counts as moving, the clause that every other
  crease stays 0 in both states fails, and the match count is 0.
- Either way the count is not 1, and all candidates sit at one vertex, so D9's
  material-point disambiguator cannot choose.
- The §5 bird example works only because `sheet "examples/bird-base.fold"`
  supplies the `F` guides (`jq`: edges 11, 15, 19, 23 are `F`).

**Proposal.** The collapse names what stays flat:

```text
collapse square-base at centre keeping [corner south-east, corner north-west] flat
```

- The signature takes intent-bearing rays at 0 as candidates. The author's
  `keeping … flat` removes one opposite pair.
- The base name (`square-base` or `waterbomb-base`) must agree with the
  remaining sectors, or the step is refused, naming both.
- §5 gains a collapse example that starts from a blank sheet, not from a fixture
  that already carries `F` guides.

### L3-2 (major, D12 and §4) One move per figure cannot hold a book step

A book figure routinely carries several instructions:

- fold and unfold both diagonals (crane 1);
- both midlines (crane 3);
- both edges to the centre (crane 5, 10, 12, 14);
- unfold two earlier steps (crane 7);
- all four blintz corners.

The glossary already defines a **Step** as one picture plus its instruction
(`docs/glossary.md:48`). origami-diagrams stores an array per frame because one
printed figure can hold several instructions (E1 finding 4).

The spine contradicts itself. D12 says a step "runs to the next `step`" (line
427), but `seqSteps :: [Located (StepHeader, Step)]` (line 674) holds one
`Step`, and `Unfold Name` reverses one step. The blintz example is forced into
four figures, where a book draws one.

**Proposal.**

- Rename the AST's `Step` to `Move` and set
  `seqSteps :: [Located (StepHeader, [Located Move])]`.
- A figure's moves run in order, each checked, and each gets its arrow on the
  figure before.
- `together` stays for lockstep coupling only.
- `unfold NAME [NAME …]` reverses every move of the named figures, in reverse
  order.
- Pretty-printing keeps the grouping.

### L3-3 (major, D3.5, D2 and §5) The quarter-fold example is refused by the spine's own anchor rule, and its second sense is backwards

This is the example #97's done-when uses as its acceptance test.

*The anchor.* `python3` on `examples/quarter-fold-steps.fold`:

- `anchor (1/4, 1/4)` lies in face 3 `[8,7,0,4]`, the bottom-left quadrant.
- Frame 1's signed areas are `[0.25, 0.25, -0.25, -0.25]`, so faces 2 and 3 were
  turned over. The left half moved, as `fold mountain edge left to edge right`
  says.
- The anchor face moves, and D3 invariant 5 refuses a move whose moving set
  contains it.
- The fixture's own first face is face 0, the bottom-right quadrant.

*The sense.* Frame 2 has edge 9 (8→5) at +180. Edge 9 joins face 0, the
face-up front layer, to face 1.

- `Folding.hs:39-48`: M/V are named from +z, and a valley lifts the child
  towards +z.
- So the top half comes down **in front**: a valley as seen from +z.
- §5 writes `fold mountain edge top to edge bottom`, captioned as folding the
  top half behind.
- This is derived from the header's convention and the computed windings. It was
  not run through `foldFrameWith`.

*The root cause is ergonomic.* An author is asked to pick an anchor that the
moving-side rule must then avoid on every fold. The runner can re-anchor
without a jump (D3.5 already says so).

**Proposal.**

- Replace invariant 5's refusal with: *the moving side is decided by the move
  (first argument, seed or selector); if it contains the anchor, the runner
  re-anchors on the largest stationary face beside the hinge, jump-free, and
  records the new anchor.*
- `anchor` in the header and `hold` become optional overrides.
- For `[P, Q]`, O4 and existing-crease lines through all layers with no seed,
  the side **not** containing the anchor moves. Precreases then need no seed.
- Fix the example:

```text
fseq 1
title "A square folded into quarters"
sheet square

step half "Fold the left half behind, onto the right half."
  fold mountain edge west to edge east
step quarter "Fold the top half down in front, onto the bottom half."
  fold valley edge north to edge south
```

### L3-4 (major, D2 and §5) Decimals remain where landmarks exist

The spine still asks the author for these:

- `anchor (0.58, 0.4)`;
- `flap containing (0.02, 0.97)`;
- `model (0, 1/4)-(2, 1/4)`;
- the placeholders `(tail point)` and `(body point)`.

`model` as written also misparses. `InModel` is a single `Point` (§4, line 644),
so `model (0, 1/4)-(2, 1/4)` is `Through (InModel 0 1/4) (AtMaterial 2 1/4)`,
and material (2, 1/4) is off the sheet.

The rerun of the gap script on `crane.fold` shows landmark forms exist:

- Material vertex 2, corner (0,1), is in the rings of faces 2, 3, 6 and 7, which
  is exactly the seed component `[2, 3, 6, 7]`.
- Material (0.25, 1) (face 2, t = 0.5) and material (0, 0.75) (face 3, t = 0.5)
  are both at folded (1.0, 0.25). A line through those two would be degenerate.
- The tip (0, 1) is at folded (1, 0) (gap-layer summary; `CraneWingSpec.hs:99`).

**Proposal.**

1. *A vertex seed.* `flap containing P` accepts a vertex landmark when every
   face incident to it lies in one component after cutting; otherwise it is
   refused, naming the components. The crane becomes
   `flap containing corner north-west`.
2. *Replace the `model` escape in §5* with the construction below, which is the
   folded line y = 1/4 from the script's positions. Confirm in Haskell before a
   PRD relies on it.

   ```text
   perpendicular to [corner north-west, 1/4 along edge north] through 1/4 along edge north
   ```

   Keep `model` only as an escape that must take both points:
   `model [(0, 1/4), (2, 1/4)]`.
3. *Anchor.* The header anchor is optional (L3-3). When stated, allow
   `anchor inside [P, Q, R]`, the centroid of three landmarks, which is exact.
4. *Authoring aid.* `run FILE --landmarks -o steps.svg` labels every visible
   vertex on every figure with its material name (corner, midpoint, `mark`
   letter). `--report` lists each flap under a line with a seed that works.
   Without it, [G] is unwritable for anyone who cannot unfold a base in their
   head.

### L3-5 (major, D2) Material names are spelled with the reader's direction words

`corner top-left` and `edge left` name the unfolded sheet. The words, though,
are the reader's words, and after `turn over` or `rotate` they point the wrong
way.

- The crane is drawn as a diamond from step 1 and turned over six times.
- `Camera.hs:178-183` notes the crane's pattern is drawn upside down anyway.
- "First argument moves" then moves the half the reader calls the other one.
- gap-exact implication 5 already bans front/back for macro disambiguators.
- The study already uses compass names for material regions:
  `README.md:425-427` defines a name like `south-west` by the original south
  edge.

**Proposal.**

- Material features use compass names: `corner south-west`, `edge north`,
  `midpoint of edge east`. Lang-style letters (`mark A = …`) are an option too.
- `left`, `right`, `top`, `bottom`, `front` and `behind` are reserved for
  viewer-relative selectors. They are resolved once in page axes after
  presentation and pinned to a material seed (E2 rule 5), for example
  `top flap on the right of [P, Q]`.
- Glossary entry: *material names never change meaning when the model is
  turned; view words always do.*

### L3-6 (major, D2 and D3) No way to say "the crease just made" or "where two creases meet", and `let` is undefined

D3 keeps a landmark table and crease provenance (lines 186-187). D2's vocabulary
(lines 122-135) and §4's `Point`/`Line`, however, have only a `let`-bound
`PointNamed`/`LineNamed`.

- The spine never says whether `let` is re-evaluated at each use (then an O3
  construction means something else once its edges have moved) or pinned (then
  pinned to what).
- A constructed point on a folded state names several layers (E2 finding 4: the
  quarter fold's four corners share one folded point).
- E2 rule 3 (lines 444-452) recommended step landmarks as material geometry.
- Crane step 6 needs exactly this: the ends of step 5's creases.

**Proposal.**

- `crease of NAME` is the material segment set the named figure created. It is
  usable as a hinge, and as a `Line` only when its pieces are collinear at the
  current state; otherwise it is refused, naming the pieces.
- `ends of crease of NAME` plus `nearest P`, and `meet L1 L2`, give points.
- `mark A = POINT [on flap containing S]` pins a material point at that step. It
  is refused when more than one layer covers it and no flap is given, and the
  letter is drawn on figures while visible (Lang, E1 finding 15).
- `let` is a syntactic alias, re-evaluated at each use, and documented as such.
- Crane 6 then reads:
  `fold valley [ends of crease of kite] flap containing centre`.

### L3-7 (major, §4, D7 and D12) `repeat` has a constructor but no spelling and no meaning

- `Repeat Symmetry [Name]` (§4, line 670) and D7's repeat range exist.
- D12 and §5 give no text for them.
- `Symmetry` is undefined.
- E2 open question 4 (lines 548-552) leaves open what "repeat behind" maps to.

The crane repeats in steps 11, 14, 20 and 25, and 17 and 23 restate 15. That is
at least six of 28 steps. Writing them longhand needs [G] mental unfolding
every time.

**Proposal.** v1 syntax:

```text
repeat NAME[..NAME] (mirrored across [P, Q] | turned N/D turn about P | behind)
```

- It elaborates (D1) to explicit moves, with every material reference mapped by
  the named isometry of the sheet.
- Senses stay as written, because they are as seen (D5).
- Check refuses when a mapped reference fails to resolve.
- `behind` parses in v1. Its semantics are refused as `NotYetDefined` until
  E2 open question 4 is checked on the waterbomb and bird fixtures.

### L3-8 (major, D9, D10 and D12) Deferred moves have no syntax, so a crane file cannot even be parsed

- D9 defers squash, reverse, sink, swivel and crimp (lines 364-366) without
  reserving their words.
- D10 lists "checkpoints" as `StateOnly` evidence (line 398), but §4 has no
  checkpoint move.
- E1 implication 11 (lines 361-363) asked for a way to mark drawn-only or
  material-only steps.
- The crane's steps 24, 25, 27 and 28 fall here.

**Proposal.**

- Reserve and parse `squash`, `inside-reverse`, `outside-reverse`, `swivel`,
  `sink open|closed`, `crimp`, `pleat`, `open` and `shape` as `Macro name args`.
- `run --check` accepts them. `run` refuses at the first one with
  `NotYetSupported`, naming the step.
- Add `run --until NAME`, which renders the prefix.
- Add a move `reach "file.fold"`: a `StateOnly` checkpoint, accepted when the
  file's material coordinates match. Crane 24–28 can then jump to
  `examples/crane.fold`.

### L3-9 (major, D2 and D8) `top N layers` makes the author count sheets, and the text cannot combine it with a seed

- On the square base the book's "top flap" is two sheets. `top 1` is coupled
  (gap-layer finding 16, lines 246-254; finding 13 on the crane wing).
- §4 gives `Fold … Layers Amount (Maybe Point)`, but D12 and §5 never spell the
  extra seed.
- `Precrease Sense Line Layers` has no seed at all (§4, lines 660-662).

**Proposal.**

- `top flap` = the smallest n ≥ 1 whose selection is not coupled, resolved once
  and pinned (E2 rule 5). `top layer` = n = 1. `top N layers` stays.
- Grammar:

  ```text
  fold SENSE [ANGLE] LINE [LAYERS] [moving SEED | on the (left|right|upper|lower) side]
  ```

- `Precrease` gains the same optional seed.
- When `top N` covers every face, report the move as through all layers
  (gap-layer open question 1).

### L3-10 (major, D12 and §5) The grammar is not line-by-line parseable as written

- **Hyphen.** `-` is the O1 operator (`P-Q`), part of keywords (`bottom-left`,
  `rabbit-ear`, `left-right`, `arc-grip`, `rigid-pose`, `material-band`), a
  candidate character in names, and a minus sign. Examples:
  `corner bottom-left-corner top-right`; `fraction 1/3 along A-B-centre`.
- **`to`.** It means O2, O3, O5, O6 and O7, the macro parameter
  (`petal … to 175`) and the pose angle (`crease P-Q to A`).
- **Kinds.** After `to`, whether a `let` name is a point (O2) or a line (O3)
  cannot be decided by the parser.
- **Blocks.** Indentation is "not significant" (line 427). Yet `together`,
  `settle`, `start folded` + `layers`, and `sample` after its move rely on
  indentation in §5, while D9 writes `together { … }` and `pose { …; … }` with
  braces.
- **Order.** Text order (`fold valley 90 LINE`) differs from AST order
  (`Fold Sense Line Layers Amount`).
- **Units.** They are implicit and mixed: `90` is degrees, `rotate 1/4` a turn,
  `0..1/32` sheet units.

**Proposal** (EBNF fragment):

```text
file      = header { step } ;
step      = "step" [ name ] [ string ] NL { move NL } ;
move      = fold | "fold" "and" "unfold" sense line [layers] [seed]
          | "unfold" name { name } | "turn" "over" [ "top-to-bottom" ]
          | "rotate" rational "turn" ("clockwise" | "anticlockwise")
          | macro [ "until" angle ] | "together" NL { move NL } "end"
          | "pose" NL { "crease" segment "at" angle NL } "end" | repeat | mark ;
fold      = "fold" sense [ angle ] line [ layers ] [ seed ] ;
line      = segment | point "to" target [ "through" point ] [ "nearest" point ]
          | "perpendicular" "to" line "through" point | name ;
segment   = "[" point "," point "]" | "edge" compass | "crease" "of" name ;
point     = "corner" compass | "centre" | "(" rational "," rational ")"
          | rational "along" segment | "midpoint" "of" segment
          | "meet" "(" line ")" "(" line ")" | name ;
angle     = rational ( "°" | "deg" ) ;
```

- Brackets give segments, as Doodle's `[a, b]` does (E1 finding 1). This frees
  `-` for hyphenated keywords only.
- `to` is reserved for alignments. Parameters use `until`, poses `at`.
- Name references parse to an untyped `Ref`, and Check assigns O2 or O3 by kind.
- Every block ends with `end`.
- Reserved words are listed in the PRD.
- Test that `0..1/32` lexes as a range. Whether megaparsec's `scientific`
  backtracks on `..` was not checked.

### L3-11 (major, D5) `rotate` cannot express the diamond position

- D5 builds presentation from exact ±1 matrices (line 248), and gap-annotation
  types rotation as an exact fraction of a turn (line 567). Crane step 1's
  diamond is a 1/8 turn, which has no ±1 matrix.
- D5's "extent and page scale do not change" (lines 252-253) is stated for both
  turn-over and rotate. gap-step-annotation says a quarter turn of a non-square
  figure legitimately changes the union (line 465).
- `rotate N/D` has no direction.
- The renderer already turns by any angle without mirroring
  (`Camera.hs:188-193`, `viewTurn` in radians, anticlockwise).

**Proposal.**

- `rotate k/8 turn clockwise|anticlockwise`. Quarter and half turns are exact;
  eighth turns take `Double` cos/sin, which is safe because presentation moves
  no paper.
- Alternatively, a header `sheet square as diamond`, which sets the initial page
  turn.
- Restrict "extent unchanged" to turn-over and half turns.

### L3-12 (minor, D5 and D12) No header says which side of the paper the reader sees first

- Books begin with coloured side up or white side up (crane step 1).
- The reader's valley/mountain in step 1 depends on it.
- The library leaves the question open: `Style.hs:118-127` says which side is
  which is not decided there, and `paperFront` is the off-white `#faf8f3`.

**Proposal.**

- Header `start (coloured | white) side up`, defaulting to coloured.
- It sets the initial presentation (a turn-over when the reader's side is the
  file's −z), and the theme's `paperFront` is documented as the coloured side.

### L3-13 (minor, D2 and §5) `centre` is resolved as a vertex, but the blintz example needs it as a region and a position

- D2 lists `centre` among vertex landmarks (lines 139-140).
- `examples/blintz-base.fold` has 8 vertices and none at (0.5, 0.5) (`jq`). So
  `anchor centre` and `corner bottom-right to centre` are near misses under D2
  as written.
- The blintz captions omit "behind" for a `mountain` fold. Its fixture is `M` at
  −180, so the corners go behind as seen from +z.
- The EDSL version's captions ("the next corner") differ from the text version's
  ("second", "third", "last"). The two therefore cannot compare equal, although
  §5 says both are written for the same model.

**Proposal.** The use site decides how a point resolves:

- construction arguments are positions: any material point on the paper,
  located in a face, on an edge or at a vertex;
- seeds and anchors are regions, or vertices under L3-4's one-component rule;
- `collapse at` and `petal tip` are vertices.

Also fix the blintz captions ("Fold the corner behind to the centre.") and make
the EDSL captions identical to the text.

### L3-14 (minor, D2) "The side containing the first argument" is undefined for crossing lines, and one book form is missing

- For O3 with crossing lines, a full line lies on both sides of the bisector.
- When the crossing is interior (a diagonal onto a midline), both bisectors
  cross the paper, and `nearest` is demanded where a book never needs it
  (E2 finding 9, table row O3).
- "Fold the corner down to the crease" has no single construction: O5 needs a
  through-point, and O7 a perpendicular line.

**Proposal.**

- The moving side is that of the named **segment's** interior; refuse if it
  straddles.
- For segment-to-segment, prefer the solution mapping the first segment onto
  the second, and ask for `nearest` only if two remain.
- Add `P to L` with no other argument: O7 with L2 ⟂ L, so the fold line is
  parallel to L and P moves straight onto it.

### L3-15 (minor, D12) Book words: `precrease` is not what books say, and common words are absent

- origami.me says fold and unfold in steps 1, 3, 10 and 26. None says
  precrease.
- The glossary defines book fold and cupboard fold (`docs/glossary.md:30-31`).
- The language has no `fold in half`, `fold behind` or `fold in front`,
  `swing`, or `open and squash`.

**Proposal.** A v1 word table, each entry elaborating to core moves:

| Word | Meaning |
| --- | --- |
| `fold and unfold` | canonical; `precrease` kept as an alias |
| `fold in half COMPASS to COMPASS` | O3 on opposite edges |
| `cupboard fold COMPASS and COMPASS` | two moves |
| `fold behind` / `fold in front` | aliases of `mountain` / `valley` |
| `swing top flap to the (left \| right)` | existing-crease hinge |
| `squash`, `inside-reverse` | reserved (L3-8) |

`Sequence.Pretty` prints the canonical form.

### L3-16 (minor, D8) The crane tally is off by one

D8 says 7 of the 12 some-layers steps hinge on existing creases, and cites
"crane steps 15–23".

Counting the gap-layer table rows marked existing gives 15, 17, 18, 20, 21 and
23: **6**. The range 15–23 also includes the turn-overs 16, 19 and 22.

**Proposal.** "12 fold some layers and 6 of those (15, 17, 18, 20, 21, 23) hinge
on existing creases."

### L3-17 (minor, D12 and naming) `.fseq` is taken, "scheme" is still the repo's word, and two names collide

- `.fseq` is the xLights/Falcon Player light-show sequence format (web search:
  manual.xlights.org, github.com/Cryptkeeper/fseq-file-format).
- `docs/roadmap.md:85-86,145,371`, #97's title and body, and F's sketch
  (`Scheme`, `SchemeError`) all say "scheme". The glossary says
  "diagram sequence" (`docs/glossary.md:48,58`).
- The AST's `Step` collides with the existing `Senbazuru.Origami.Step` module (a
  frame-pair motion).
- `repeat` and `sequence` are Prelude functions, so a builder spelling them
  would clash.

**Proposal.**

- Keep "sequence", since it matches the glossary. Record the rename from
  "scheme" in M0 (roadmap wording, #97's decision note).
- Pick an extension checked for collisions (candidate `.foldseq`; not
  searched).
- Rename the AST `Step` to `Move` (L3-2).
- Name the builder functions `repeatSteps` and `sequenceOf`.

### L3-18 (minor, D9 and §5) The bird example follows the certificate's route, not a book's, and petal tips need mental unfolding

- §5's bird petals the back flap while the front is held at 175, then presses
  both.
- A book petals the front flat, turns over and repeats (crane 8–11).
- `petal tip corner bottom-right` makes the author know which material corner is
  the front tip.
- gap-exact implication 5 forbids front/back because the back petal moves while
  the front is in the air. That reason does not apply to flat states.

**Proposal.**

- Allow `petal top flap` only on flat states, resolved once by nearness to a
  tip corner and pinned in the record. Keep the material form for paper in the
  air.
- Add the book route (petal, `turn over`, `repeat … behind`) as a §5 sketch
  marked unverified against contact at 180°.

### L3-19 (minor, D9) Signs and units of `pose` angles and macro parameters are not stated against D5

D5 makes `valley`/`mountain` as seen, but `pose { crease P-Q to A }` and
`petal … to 175` state no sign convention. A negative pose angle is either FOLD's
sign or the reader's.

**Proposal.**

- Pose angles are FOLD signs along the anchor's +z, spelled
  `crease [P, Q] at -90°`.
- Macro parameters are unsigned magnitudes in each macro's own convention,
  spelled `until 175°`.
- State both in the glossary.

## 3. Confirmed

- **D5, senses as seen.** Books name the sense as seen, and the library already
  names M/V from +z for the crease pattern (`Folding.hs:39-40`). Presentation
  then only has to map one to the other.
- **D5, turn not mirror.** A turn, never a mirror, is the existing camera rule
  (`Camera.hs:196-210`).
- **D2, the moving-side rule.** O2/O3 "first argument moves" reproduces
  `quarter-fold-steps.fold`: step 1 moves the left half (frame 1 x ∈ [0.5, 1],
  faces 2 and 3 turned over) and step 2 the top half (frame 2 y ∈ [0, 0.5]).
- **D8, the seed rule.** On `crane.fold` it gives `[2, 3, 6, 7]` with seed
  (0.02, 0.97). The line crosses 16 faces, none of whose ends lies strictly
  inside a face (rerun of `analyse.py`, closure 3.0e-13).
- **§5, blintz facts.** `blintz-base.fold` edges 8–11 are the corner creases,
  all `M` at −180 (`jq`).
- **§5, bird facts.** `bird-base.fold` has v8 at (0.5, 0.5), and hinges 26 and 27
  are `V` at 180 (`jq`).
- **§5, quarter-fold facts.** `quarter-fold-steps.fold` edges 8–11 go
  0 → [−180, 0, −180, 0] → [−180, 180, −180, −180] (`python3`).
- **D8, the crane table.** origami.me's crane has 28 steps. gap-layer's class
  counts (6 whole, 7 coupled, 3 all, 12 some) match its table, apart from the
  existing-crease count (L3-16).
- **D12, rejecting JSON.** Rejecting JSON as authoring syntax is consistent with
  #97's test of writing without a calculator (`gh issue view 97`).
