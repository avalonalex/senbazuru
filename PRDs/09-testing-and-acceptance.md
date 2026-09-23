# 09 — Testing and acceptance

Written 2026-09-15 against `568dcb6`. Research and requirements only. This file
owns the design's testing decision,
[D16](decisions.md#d16-testing-and-acceptance): what each milestone must pass, the
two quarter-fold tests, the end-to-end table, budgets, CI placement, how angles and
bytes are compared, and how the study recipes migrate. Feature files own their
criteria; this file gathers them by id and writes out only those no file owns yet.

[decisions.md](decisions.md) is the design record every file in `PRDs/` is written
from; where this file and it disagree, it wins. Its decisions are numbered D1–D24,
and each one cited here links there with a clause saying what it decides. *Draft
v2* is the earlier version of that record; each rule here that replaces one of
its sentences links the change, numbered C1–C74 in
[Changes since draft v2](decisions.md#changes-since-draft-v2).
**SKETCH** marks a proposed name or type no code has yet; **UNVERIFIED** marks a
claim no command here has checked. *M0*–*M8* are milestones, each a group of pull
requests ([decisions §8](decisions.md#8-milestones),
[10 §1](10-roadmap-risks-questions.md#1-milestones)); "owner decision N" is row N
of [10 §6](10-roadmap-risks-questions.md#6-owner-decisions), whose recommended
defaults are [decisions §9](decisions.md#9-owner-decisions).

A *golden* test compares output byte for byte with a checked-in file
([AGENTS.md "Testing"](../AGENTS.md#testing)). A *fold angle* is 0 when flat,
+180 for a *valley* folded flat and −180 for a *mountain*, read from the top side
of the face that stays still ([glossary](../docs/glossary.md#origami)); §2.1
shows why that is not always the reader's side. A *face* is a flat region between
creases ([glossary](../docs/glossary.md#geometry)). A study *recipe* is a
hand-written list of folds in `study/fold-material/`, each an edge id, a face id
and a travel, such as `BlintzSequence` (§9). Every other new term links to
[glossary-additions](glossary-additions.md).

[1. Every PR](#1-rules-for-every-pull-request) ·
[2. Quarter fold](#2-the-quarter-fold-two-tests) ·
[3. E1–E10](#3-end-to-end-e1e10-on-the-blintz) ·
[4. By milestone](#4-acceptance-by-milestone) ·
[5. Whole crane](#5-the-whole-crane-parses-and-checks) ·
[6. Budgets and CI](#6-budgets-measurements-and-where-tests-run) ·
[7. Angles](#7-angle-equality) · [8. Platform bytes](#8-bytes-that-differ-by-platform) ·
[9. Migration](#9-migrating-the-study-recipes) ·
[10. Owner questions](#10-open-questions-for-the-owner) ·
[11. Commands](#11-commands-behind-the-numbers)

## 1. Rules for every pull request

### 1.1 Every assertion names the change that turns it red

Every criterion in this series has a "red when" column: a plausible wrong change
that makes it fail. A test nobody can name such a change for protects nothing and
is rewritten before review.

### 1.2 Tracked goldens stay byte-identical

There are 33 (`git ls-files test/golden | wc -l`), grouped by what could move
them in
[06](06-prd-step-diagrams.md#goldens-that-must-stay-byte-identical-all-33-git-ls-files-testgolden).
On the committed branch:

```bash
git diff --name-only --diff-filter=MD origin/main...HEAD -- test/golden/   # must print nothing
git diff --name-only --diff-filter=A  origin/main...HEAD -- test/golden/   # the goldens this PR adds
```

Both print nothing on this branch today. They are
[D16](decisions.md#d16-testing-and-acceptance)'s check
([C53](decisions.md#changes-since-draft-v2)). They replace draft v2's
`git diff --name-only origin/main -- test/golden/`, which mixes added with
changed files, compares with the working tree (where a new golden not yet
`git add`ed is invisible), and shows commits `main` gained since the branch.

| A golden change that is… | Caught by |
| --- | --- |
| not accepted | `stack test`: `goldenText`/`goldenBytes` ([`Golden.hs:38`](../test/Test/Golden.hs#L38), [`:81`](../test/Test/Golden.hs#L81)) write `X.actual.svg`/`.glb`, which git ignores ([`.gitignore:10-11`](../.gitignore#L10-L11)), and name the first difference |
| accepted by `mv X.actual.svg X.svg` | only the first command above |

**Red when** a tracked golden changes a byte or is deleted. The one foreseen
exception is owner decision 9: migrating the quarter-fold fixture to the
[state rule](glossary-additions.md#the-fold-format) would move
`quarter-fold-steps.svg` and `quarter-fold-step-1.svg` in that PR alone. Both
goldens read `test/fixtures/quarter-fold-steps.fold`
([`SvgSpec.hs:371`](../test/Senbazuru/Render/SvgSpec.hs#L371),
[`:380`](../test/Senbazuru/Render/SvgSpec.hs#L380)), a byte-identical copy of
`examples/quarter-fold-steps.fold`, so they move only if that copy migrates too.

### 1.3 Multi-frame examples draw the same step pages

[D5](decisions.md#d5-presentation-and-the-readers-side) (presentation and the
reader's side) makes `Origami.Step` treat a whole-model rigid motion as a
*presentation change*, which gets no arrow
([05 L3](05-prd-library-additions.md#l3-fitrigid-proper-rotations-and-the-whole-model-classification)).
Its acceptance: `render --steps --arrows` is byte-identical on every multi-frame
file in `examples/`. There are two (§11 command 1):

| File | `file_frames` | States | Drawn with arrows by a golden today? |
| --- | ---: | ---: | --- |
| `bird-base-sequence.fold` | 16 | 16: its key frame has no vertices | no: its goldens pass `False` ([`BirdSequenceSpec.hs:79`](../test/BirdSequenceSpec.hs#L79)) |
| `quarter-fold-steps.fold` | 2 | 3: its key frame is the first state | yes: `quarter-fold-steps.svg` ([`SvgSpec.hs:380`](../test/Senbazuru/Render/SvgSpec.hs#L380)), from `test/fixtures/quarter-fold-steps.fold`, identical to the `examples/` copy by `cmp` |

So the check has three parts:

1. **Pin first.** A PR before 05 L3 adds the reviewed golden
   `bird-base-sequence-arrows.svg` (**SKETCH** name): `stepPage` with arrows over
   that file, drawn by today's code, because no existing golden draws it with
   arrows ([C70](decisions.md#changes-since-draft-v2)). 05 L3's PR keeps it and
   `quarter-fold-steps.svg` byte-identical. **Red when** a pair is classified as
   presentation and loses its arrow.
2. **By hand**, in the PR's "How this is verified", since the CLI is untested by
   design ([D13](decisions.md#d13-the-run-verb-and-io), the `run` verb and I/O):
   `senbazuru render FILE --steps --arrows -o OUT`
   from a worktree at the merge base and from the branch, then `cmp`, for every
   multi-frame file tracked at the merge base. (Not run for this PRD: it needs
   05 L3's code, which is not written yet.)
3. A multi-frame file added later has no "before"; its own golden pins it (E7).

05 L3's Python pre-check found no consecutive pair of states in either file (0 of
15, 0 of 2) that keeps every distance while something moves, so none *can*
classify.

### 1.4 The build is warning-free from cold

`stack clean && stack build --test` ([AGENTS.md](../AGENTS.md#conventions)).
**Red when** an exhaustive match misses a new constructor. Wildcard matchers
escape it; [06 R-06-7](06-prd-step-diagrams.md#requirements) lists them.

## 2. The quarter fold, two tests

[#60](https://github.com/avalonalex/senbazuru/issues/60) asks a sequence to
reproduce `examples/quarter-fold-steps.fold`. Frames match index by index only
when the run starts from the fixture's own creases, so
[D16](decisions.md#d16-testing-and-acceptance) splits the test
([01 §4.3](01-architecture.md#43-60)).

### 2.1 The fixture, measured

[02 §1](02-language-semantics.md#1-one-run-walked-through) walks this fixture
through a run: its faces, edges 8–11, and which vertices each step moves;
[01 §5.0](01-architecture.md#50-the-fixture-and-the-source) draws it. States are
numbered from 0, as [D24](decisions.md#d24-states-figures-and-their-numbers)
(states, figures and their numbers) fixes: state *k* is `file_frames[k]` of the
written sequence file. The fixture keeps its state 0 in its key frame, so fixture
state *k* ≥ 1 is its `file_frames[k-1]`; §2.2 names that off-by-one. What the
tests read (§11 command 2):

| State | Where in the fixture | `frame_title` | `frame_classes` | Angles of edges 8–11 |
| --- | --- | --- | --- | --- |
| 0 | key frame | "Step 1: the flat sheet" | `creasePattern` | 0, 0, 0, 0 |
| 1 | `file_frames[0]` | "Step 2: folded in half" | `foldedForm` | −180, 0, −180, 0 |
| 2 | `file_frames[1]` | "Step 3: folded in half again" | `foldedForm` | −180, 180, −180, −180 |

Every state has 9 vertices, 12 edges and faces F0 `[8,4,1,5]` (south-east
quarter), F1 `[8,5,2,6]`, F2 `[8,6,3,7]`, F3 `[8,7,0,4]` (south-west). Edges 0–7
are boundary (`B`); creases 8–11 carry `M V M M` in every state, even at angle 0.
Coordinates are 2D; no frame has `faceOrders`.

**The line that looks like a typo: state 2 has edge 11 at −180, although step 2 is
a valley.** The sign is read from the top of the face that stays still, and edge
11's, F3, was turned over by step 1;
[02 §1](02-language-semantics.md#1-one-run-walked-through) gives the argument. A
face's ring, its corners in order, with positive signed area runs anticlockwise
seen from +z, so the face shows its top to the reader; negative means it is turned
over ([winding](../docs/glossary.md#geometry)). State 1's rings have signed areas
+¼, +¼, −¼, −¼ (§11 command 3).

### 2.2 Test 1: folding equivalence (M2)

The source is
[04's first source](04-prd-sequence-source-and-cli.md#a-first-source-read-line-by-line):
`sheet "examples/quarter-fold-steps.fold"`, `anchor (3/4, 1/4)`, then step `half`,
`fold behind edge west to edge east`, and step `quarter`,
`fold in front edge north to edge south`. Step 1 turns about existing edges 8 and
10 (x = ½), step 2 about 9 and 11 (y = ½) (§11 command 2); neither makes a crease.

**Why the anchor is written.** The
[anchor](glossary-additions.md#running-a-sequence) is the material point whose
face stays still. Without the line the default anchor is F3, which step 1 moves,
so the run would [re-anchor](glossary-additions.md#running-a-sequence) onto F0;
[02 §2.3](02-language-semantics.md#23-the-anchor) works this case, and nothing on
the page moves. Writing the anchor keeps test 1 about folding alone, because
re-anchoring is owner decision 3 and may become a refusal. (3/4, 1/4) is inside
F0, which neither step moves (§11 command 3).

**The line that looks like an off-by-one.** The written
[sequence file](glossary-additions.md#the-fold-format) puts the sheet in
`file_frames[0]`, the state after `half` in `[1]` and after `quarter` in `[2]`;
its key frame holds metadata only
([01 §5.9](01-architecture.md#59-the-written-frame-and-the-page-note),
[02 §11](02-language-semantics.md#11-written-frames)). The fixture keeps its sheet
in the key frame. So written `file_frames[k]` is fixture state *k*, which is
fixture `file_frames[k-1]` for *k* ≥ 1. The command line counts frames with the
key frame at 0 ("default: 0, the key frame",
[`Cli.hs:491`](../app/Senbazuru/Cli.hs#L491)), so state *k* is `--frame k` on the
fixture and `--frame k+1` on the written file
([D13](decisions.md#d13-the-run-verb-and-io),
[C59](decisions.md#changes-since-draft-v2)).

| Compared | Rule | Red when |
| --- | --- | --- |
| States | 3 written `file_frames`; key frame without vertices | the sheet goes in the key frame |
| `edges_vertices`, `faces_vertices` | exact: same ids, same ring order | `sheetState` re-cuts a frame that records faces (today [`Crossings.hs:128`](../src/Senbazuru/Fold/Crossings.hs#L128) keeps it); rings re-wound (already anticlockwise, signed area +¼ each); anchor face moved off index 0 |
| `vertices_coords` | fixture `[x, y]` padded to `[x, y, 0]`, each within 1e-12 × `modelSpan` ([`V3.hs:72`](../src/Senbazuru/Geometry/V3.hs#L72)) of the material coordinates, as [`BlintzSequence.hs:67-69`](../study/fold-material/BlintzSequence.hs#L67-L69) takes it; here 1 | a different face held still; a rotation's sign flipped (the mirror model) |
| `edges_foldAngle` | exact (§7): flap endpoints are `angle + progress * travel` on the author's ±180 ([`Flap.hs:343`](../src/Senbazuru/Origami/Flap.hs#L343)) | "in front" read from a camera (edge 9 −180); a layer's way up applied twice (edge 11 +180) |
| `edges_assignment` | `assignmentAtRest` of the fixture's assignment and angle ([state rule](glossary-additions.md#the-fold-format)): `F F F F`, `M F M F`, `M V M M` after `B`×8 | an [intent assignment](glossary-additions.md#the-fold-format) `M`/`V` written at angle 0; `U` written |
| `frame_classes` | `creasePattern`, `foldedForm`, `foldedForm` ([D4](decisions.md#d4-written-frames-follow-the-state-rule): written frames follow the state rule) | a state with nonzero angles written `creasePattern` |
| Not compared | `frame_title` (a caption describes the move *leaving* its figure); `faceOrders` (the fixture has none; E3 checks orders); `frame_attributes` (whether `hasRelief` uses a tolerance is unverified: [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md) "Unverified" 5) | — |

**Why angles are exact.** Draft v2 compared test 1's angles "within tolerance";
[D16](decisions.md#d16-testing-and-acceptance) compares them exactly
([C52](decisions.md#changes-since-draft-v2)). At progress 1 a flap endpoint is
`angle + 1 * travel`, sums and products of whole-number `Double`s, which IEEE
arithmetic gives exactly on every platform
([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
finding 16), so exact equality is the stronger test and still passes.

**Its page**, `stepPage` with arrows
([`Steps.hs:90`](../src/Senbazuru/Render/Steps.hs#L90)) over the written frames,
then `renderSvg`, as `render --steps` draws them, is a new reviewed golden
(**SKETCH** name `quarter-fold-sequence-steps.svg`). It cannot equal
`quarter-fold-steps.svg`: the state rule writes flat creases `F`, which turns
step 1's four dashed crease paths grey and solid and changes step 2's horizontal
crease (prebuilt binary,
[gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md)
finding 18, variant B). The existing golden stays as the regression for the
unchanged fixture.

### 2.3 Test 2: authoring from `sheet square` (M3 and M4)

Same anchor and steps, from `sheet square`. The written anchor matters here too.
Without it, the default anchor is the vertex mean of the square's one face,
(½, ½), which lies on step 1's new crease x = ½, and the run would move it by
[D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)'s rule
for an anchor a new crease passes through. With `anchor (3/4, 1/4)` this test does
not exercise that rule ([C19](decisions.md#changes-since-draft-v2)); the crane
opening in [decisions §7](decisions.md#7-examples), which has no `anchor` line,
does (M5, **UNVERIFIED**).

Under [D6](decisions.md#d6-crease-graphs-grow-between-frames) a crease graph grows
between frames, so a crease first appears in the frame of the move that makes it, and the
run writes coarser crease graphs than the fixture's: 4 vertices, 4 edges, 1 face;
then 6, 7, 2; then 9, 12, 4. Those counts come from hand-built frames (§11 command
4), **UNVERIFIED** as runner output; the ids differ too (the fixture's vertex 4 is
(½, 0), 5 is (1, ½)).

Frames are compared by *material identity*, which piece of paper each vertex and
edge is ([material point](glossary-additions.md#references)). The fixture's
material coordinates are its key frame's, a flat unit square. Per state, rules
T1–T5 ("T" for test 2), which [D16](decisions.md#d16-testing-and-acceptance)
adopts ([C48](decisions.md#changes-since-draft-v2)):

| # | Rule | Red when |
| --- | --- | --- |
| T1 | Each fixture edge's material segment lies inside exactly one written edge with the same angle, or inside none and has angle 0 (a crease not yet made) | a crease drawn before its step; a wrong angle; step 2 creasing only the top layer |
| T2 | The fixture edges inside each written edge cover it: their lengths sum to its length | a written crease where the fixture has none, such as a precrease along the diagonal (0, 0)–(½, ½) |
| T3 | Each written vertex sits at a fixture vertex's material coordinate, positions within 1e-12 × `modelSpan` | a vertex off the fixture's grid; a layer misplaced |
| T4 | Each other fixture vertex is placed at its fixture position, same tolerance, by the written face or edge containing its material point ([05 L5](05-prd-library-additions.md#l5-motionsacross-creasestocome-and-a-non-convex-point-test)'s material-to-position map) | an uncreased region placed as if creased |
| T5 | Assignments by the state rule, as in test 1 | as in test 1 |

§11 command 4 runs both red-when cases of T1 and T2 on hand-built frames: creasing
only the top layer in state 2 fails T1 alone, and adding the diagonal precrease to
state 1 fails T2 alone.

**Why not draft v2's clauses.** Draft v2 said "every written edge inside exactly
one fixture edge's material segment" and "every unmatched fixture vertex lies on
a written edge's segment". Both are false on correct frames. On state 0 the
written boundary (0, 0)–(1, 0) spans fixture edges 0 and 1; on state 1,
(1, 0)–(1, 1) spans edges 2 and 3 and the crease (½, 0)–(½, 1) spans edges 8 and
10; on state 0 the centre (½, ½) lies inside the only face. §11 command 4 finds
v2's edge clause false on states 0 and 1, its vertex clause false on state 0, and
T1–T2 true on all three.

**When it lands.** Test 2 and its new reviewed golden land in M4, after M3 has
merged: the later of the two ([D16](decisions.md#d16-testing-and-acceptance),
[decisions §8](decisions.md#8-milestones),
[C49](decisions.md#changes-since-draft-v2)). From a bare square, step 2 creases
both layers of a flat-folded state, which needs `creaseLayersThrough`
([05 L8](05-prd-library-additions.md#l8-creaselayersthrough), milestone M4); the
page needs `motionsAcross`
([05 L5](05-prd-library-additions.md#l5-motionsacross-creasestocome-and-a-non-convex-point-test),
milestone M3). [#60](https://github.com/avalonalex/senbazuru/issues/60) closes in
that PR, M4's last.

## 3. End to end: E1–E10 on the blintz

The default-CI end-to-end test runs [00](00-overview.md#the-problem-in-one-example)'s
blintz: four corners folded behind to the centre, then the first reopened. Every
move turns about existing creases 8–11, the four lines cutting off the corners,
(½, 0)–(1, ½) round to (0, ½)–(½, 0) (§11 command 5). Nothing creases through
layers. Creasing through layers maps a crease's folded position back to material
coordinates through each face's rotation (`applyRigid (inverse placement)`), which
puts `cos` and `sin` bits into the material coordinates the GLB's JSON stores raw
([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
finding 15); the blintz's stay the source's exact numbers (§8). Files (**SKETCH**
names): the source `blintz.foldseq` at the repository root, where 00 saves it; its
written `examples/blintz-sequence.fold`, with provenance "generated by senbazuru"
in `examples/README.md`;
`test/golden/blintz-sequence-steps.svg` and `blintz-sequence-final.glb`. The run
is built once in `beforeAll` (§6.3). Corner direction is owner decision 8.

**Why the source is not in `examples/`.** A `sheet` path is relative to the
source's own directory ([D13](decisions.md#d13-the-run-verb-and-io),
[04 R-04-6](04-prd-sequence-source-and-cli.md#requirements)). 00's source says
`sheet "examples/blintz-base.fold"`, and E1 compares the parse with
[03](03-prd-embedded-dsl.md#acceptance-criteria)'s `blintz`, whose `sheetFile` is
the same text. Saved inside `examples/`, the line would have to read
`sheet "blintz-base.fold"` and the two values would no longer be equal.

| # | Assertion | Red when |
| --- | --- | --- |
| E1 | `fmap stripSpans (parseSequence p text) == Right blintz` ([03 A-2](03-prd-embedded-dsl.md#acceptance-criteria)), and printing then parsing returns it | `behind` parsed as valley; `valley` printed for `mountain`; a keyword renamed on one side |
| E2 | Five [move records](glossary-additions.md#running-a-sequence), each with `SweptHinge c` evidence (the turn checked over its whole path, [route evidence](glossary-additions.md#assurance)) and `sweepOutcome (flapCheck c) == SweepClear`; each `recordCost` equals a checked-in list of (sweep intervals, refolds) per move, set in the first runner PR from a reviewed run. A *refold* is one `foldFrameWith` call recomputing positions from angles | the moving side resolved to the other face; the sweep budget below the count; `HingeSweep` needing other intervals; a refold added |
| E3 | [Join check](glossary-additions.md#running-a-sequence) at every move: positions within 1e-12 × `modelSpan` ([`BlintzSequence.hs:69`](../study/fold-material/BlintzSequence.hs#L69)); angles, edges, rings as vertex sets, orders and material coordinates exact ([`CheckedBird.hs:145-146`](../study/fold-material/CheckedBird.hs#L145-L146)) | folded coordinates fed back as material; orders taken from `foldedPattern` instead of the accepted endpoint ([`BlintzSequence.hs:63`](../study/fold-material/BlintzSequence.hs#L63)) |
| E4 | `withoutCoordinates expected == withoutCoordinates actual` on the whole file ([`BirdSequenceSpec.hs:41`](../test/BirdSequenceSpec.hs#L41)): topology, angles, `faceOrders`, titles, classes, attributes, metadata, `senbazuru:` keys (material coordinates are the source's exact numbers here) | `Folding.reorient` removed (#78); an edge renumbered; a caption changed; `frame_inherit` written `false`; `M` written at 0 |
| E5 | Coordinates: equal counts, each within absolute 1e-12 ([`BirdSequenceSpec.hs:48-50`](../test/BirdSequenceSpec.hs#L48-L50)) | wrong face held still; rotation sign flipped |
| E6 | `eitherDecode (encode file) == Right file` | a field written but not read; doubles encoded through `toEncoding`, which writes `-0.0` ([`Types.hs:583-596`](../src/Senbazuru/Fold/Types.hs#L583-L596)) |
| E7 (M3) | `stepPageWith` over `stepNotes run`, then `renderSvg`, byte-exact | stroke width; camera basis; default arrow head; `formatNumber` decimals; a crease drawn before its step |
| E8 | `renderGlb` ([`Gltf.hs:200`](../src/Senbazuru/Render/Gltf.hs#L200)) on the run's final state, as `run -o x.glb` calls it ([04](04-prd-sequence-source-and-cli.md#the-run-verb)), byte-exact against `blintz-sequence-final.glb` | `toGltfAxes` becomes `(x, z, y)`; `quantumFor` changed; `faceOrders` leave the extras |
| E9 | The GLB's `extras.senbazuru.frame` equals the sequence file's last state: exact in topology, angles, orders; positions within one rounding step, 1e-6 × span ([`Gltf.hs:261-264`](../src/Senbazuru/Render/Gltf.hs#L261-L264)); extras only for the keys the GLB keeps ([`:241-242`](../src/Senbazuru/Render/Gltf.hs#L241-L242)) | GLB drops or reorders `faceOrders`; the writers disagree on the final state or its presentation |
| E10 | Negative control. Move 5, `unfold c1`, is replaced by `fold in front 180° hinge of c1 moving corner south-east`, carrying the corner on through the centre (`c1` is the name 00's source gives the first corner step). The corner lies under the square after c1, so that turn sets it off towards the reader: `in front` since owner decision 13 ([D5](decisions.md#d5-presentation-and-the-readers-side)'s amendment), where the held-face rule had `behind`. Once 05 L11's covering check lands (M4), the kind below becomes `FlapCovered`, here and in 04's A19. The run gives `Left (StepRefused 5 Nothing span failure)` with `FlapEndpointOrder` inside, `Nothing` because step 5 has no name; `explain` starts "step 5"; `sourceLocation` names its line; no frame is written, since a refusal other than `not modelled` returns no partial run. Written instead inside step 5's braces as `expect refused FlapEndpointOrder { … }` ([glossary-additions](glossary-additions.md#the-sequence-language)), a move inside a step and never at top level, the run succeeds because the inner move is refused as expected. That move produces no [move record](glossary-additions.md#running-a-sequence) and no state, and changes nothing; its outcome is kept on step 5's outcome in the `Run` and printed by `--report` ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused), [C8](decisions.md#changes-since-draft-v2)). Step 5's only move is that wrapper, so it writes nothing and is not a figure: the file holds five states, not six ([D24](decisions.md#d24-states-figures-and-their-numbers)) | the runner catches `Left` and continues; spans dropped; a wrapper rewords the nested error; `expect refused` writes a frame, adds a record or a figure, or is missing from `renderRunReport` |

E10's spelling follows [04's grammar](04-prd-sequence-source-and-cli.md#grammar):
`fold` takes a sense, an optional angle, a line and a seed, and `hinge of N` is a
line. No runner exists yet, so the runner's refusal is **UNVERIFIED** until M2.
What is evidence today is the recipe's equivalent:
`prepareFlap (EdgeId 8) (FaceId 2) (-180)` on the reopening's start is refused as
`FlapEndpointOrder`
([`BlintzSequenceSpec.hs:110-115`](../test/BlintzSequenceSpec.hs#L110-L115)).

## 4. Acceptance by milestone

"Owned" links another file's ids; §11 command 7 re-derives the ranges.
[02](02-language-semantics.md) numbers no requirements, so its rules appear under
"stated here", named as in its
[refusal catalogue](02-language-semantics.md#12-refusal-catalogue).
[10](10-roadmap-risks-questions.md#1-milestones) owns milestone contents and
order; "row N" is row N of
[decisions §3](decisions.md#3-recorded-text-this-design-changes), written out in
[01 §4](01-architecture.md#4-recorded-text-this-design-changes) and placed by
[decisions §8](decisions.md#8-milestones).

| M | Owned |
| --- | --- |
| M0 | Rows 1–10 and 16 |
| M1 | [03](03-prd-embedded-dsl.md#requirements) R-03-1…10, 12…14; A-1…A-5, A-7. [04](04-prd-sequence-source-and-cli.md#requirements) R-04-1…19, 23, 29, 30; [A1…A10, A12, A14, A15's `--check` rows, A17](04-prd-sequence-source-and-cli.md#acceptance-criteria) |
| M2 | 03 R-03-11, A-6. [05](05-prd-library-additions.md) L1 (R-05-4, 5), L2 (R-05-6…9), L3 (R-05-10…13), [L4](05-prd-library-additions.md#l4-flapstationaryface-flapposeat-and-routepose)'s `flapStationaryFace` (R-05-14); L14 (R-05-44…47: `prepareFlapToward`, and `Eq` on `FlapMotion` and `CheckedFlap`: [D5](decisions.md#d5-presentation-and-the-readers-side), [D10](decisions.md#d10-assurance-as-evidence-values)); R-05-1…3 per PR. 04 R-04-20…22, 24…28 (R-04-22's and R-04-27's `.svg` parts with M3); A11, A13, the rest of A15, A16, A18, A19. Rows 11, 12 (`runSequence`), 13 |
| M3 | [06](06-prd-step-diagrams.md#requirements) R-06-1…23, A1…A17, new goldens; 05 L5 (R-05-16…20). Row 12 (`stepPageWith`). R-06-23 (a step's `sample` poses are figures of their own) lands here, but only macro-moves carry `sample`, so nothing exercises it before M5 ([06 "Risks"](06-prd-step-diagrams.md#risks)) |
| M4 | 05 L6…L12 (R-05-21…40). Rows 15, 17, 18 |
| M5 | 05 L13 (R-05-41…43) |
| M6 | [07](07-prd-material-consumption.md#requirements) R-07-1…38, 40, 43…45, and R-07-41's default-CI part; AC-1…AC-12, AC-14, AC-16, AC-17. 04 A2's crane-wing golden. 05 L4's `flapPoseAt` (R-05-15) lands with its first consumer, here or M7b |
| M7a | [08](08-prd-realistic-rendering.md#requirements) R-08-1…11; [A-1…A-10](08-prd-realistic-rendering.md#acceptance-criteria) |
| M7b | 08 R-08-12…31; A-11…A-23. 05 L15 (R-05-48…49: `foldedWalk`, [D19](decisions.md#d19-realistic-rendering)) |
| M8 | 07 R-07-39, R-07-41's `run --settle` cap, R-07-42; AC-13, AC-15 |

| # | Stated here | Red when |
| --- | --- | --- |
| M0 (a) | Every link in rows moved into `docs/glossary.md` resolves from `docs/` | a moved row still links `research/…` or another path relative to `PRDs/` |
| M0 (b) | *Rest angle* is defined once; today the [Origami](../docs/glossary.md#origami) section (line 19) and the [Geometry](../docs/glossary.md#geometry) section (line 83) each define it | both rows kept |
| M0 (c) | §1.2's first command prints nothing | an M0 PR changes or deletes a tracked golden |
| M1 (a) | §5's assertions, on 04 A5's source | as in §5 |
| M1 (b) | A golden of `explain` text for each `StaticProblem` in 02's catalogue, as [D20](decisions.md#d20-errors) (errors) corrects it | a message built with `show` |
| M2 (a) | §2.2, test 1 | as in §2.2 |
| M2 (b) | E1–E6, E8–E10 | as in §3 |
| M2 (c) | §1.3 | as in §1.3 |
| M2 (d) | §9's blintz and helmet equivalence | as in §9 |
| M2 (e) | `sheetState` refuses a Haskell-built key frame with no vertices as `SheetHasNoVertices`, naming how many `file_frames` exist, and one whose `frameKind` is `FoldedForm` as `SheetAlreadyFolded` ([02 §2.2](02-language-semantics.md#22-starting)) | `sheetState` reads `file_frames[0]` instead of refusing |
| M2 (f) | Every frame the M2 tests write has explicit `edges_foldAngle`, no `U`, and no `M`/`V` at angle 0 ([02 §11](02-language-semantics.md#11-written-frames)) | intent assignments copied into the written frame |
| M2 (g) | On a sequence stopping at `not modelled "…"`, `runSequence` returns `Right` a `Run` whose `runStop` names the step and the text and which holds every record and state before it; `runRefusal` of that run is `Just (StepRefused n name span (NotModelled text))`, the error the CLI prints and exits nonzero on ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused), [C10](decisions.md#changes-since-draft-v2); [02 §9](02-language-semantics.md#9-repeat-checkpoint-not-modelled-expect-refused)) | the stop returned as `Left`, discarding the earlier records and states; `runRefusal` gives `Nothing` for a stopped run |
| M3 (a) | E7 | as in §3 |
| M4 (a) | On `crane.fold` the Haskell layer selection for the wing fold (the faces a move folds when it folds only some layers, the [top flap](glossary-additions.md#references)) gives faces `[2,3,6,7]`, as [`CraneWing.hs:93`](../study/fold-material/CraneWing.hs#L93) hand-picks; until then the evidence is Python ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) "Re-deriving CraneWing by rule (script)") | layers counted from the far side instead of the reader's |
| M4 (b) | Under [D11](decisions.md#d11-stacking-choices-are-relations) (stacking choices are relations, solved with a budget), the two crane [stacking relations](glossary-additions.md#running-a-sequence) leave exactly today's index 2 of five ([`CraneWing.hs:78`](../study/fold-material/CraneWing.hs#L78)), and dropping either leaves two or more, **UNVERIFIED** | the relations filter a budget-capped list of stackings |
| M4 (c) | A `repeat` whose creases are not the original's image under its mirror or quarter turns is refused as `RepeatNotSymmetric` ([02 §9](02-language-semantics.md#9-repeat-checkpoint-not-modelled-expect-refused)) | *senses*, whether each fold is mountain or valley, compared as seen instead of in material terms |
| M4 (d) | §2.3's test 2 and its page, in M4's last PR, after M3 has merged | as in §2.3 |
| M4 (e) | Crane-wing prefix equivalence (§9), slow job | as in §9 |
| M5 (a) | `collapse at centre` on a crane's [precreased](glossary-additions.md#origami) centre refuses, listing four `keeping` clauses (four is **UNVERIFIED**, [02 §8.2](02-language-semantics.md#82-collapse)) | the first match taken silently |
| M5 (b) | One match, needing no `keeping`, on `square-base.fold` and `bird-base.fold` ([02 §8.2](02-language-semantics.md#82-collapse)) | a single match still demands `keeping` |
| M5 (c) | Bird route records match `CheckedBird`'s stages within §7's formula tolerance, slow job | a role's formula or its sign changes |
| M6 (a) | Each default-CI [settle](glossary-additions.md#material) asserts its refined triangle count ≤ 392 (R-07-41's default-CI part) | a default spec refines further |
| M6 (b) | §6.3's placement | a crane-sized fixture outside `describe "slow"` |
| M7a (a) | A-10's validator run and screenshot go in the PR, since no CI job runs an external program (R-07-43) | a CI job runs the validator |
| M7b (a) | A-13 on the 4,312-triangle mesh and A-15's measurement run in the slow job (§6.3) | either runs in the default job |
| M7b (b) | The manual parts of A-12 and A-23 go in the PR, not CI | a CI job opens a viewer or Blender |
| M8 (a) | [#208](https://github.com/avalonalex/senbazuru/issues/208)'s value-only line search merged before M6's crane equivalence and before M8 (R-07-40), a gate checked on the issue | an M8 PR opens while #208 is open |

## 5. The whole crane parses and checks

A traditional crane has 28 steps, 12 folding only some layers
([gap-layer-selective-folds](research/gap-layer-selective-folds.md) "(e) The
traditional crane, step by step"). This M1 test,
[04 A5](04-prd-sequence-source-and-cli.md#acceptance-criteria), shows the language
can say all of them before most can run. Its source,
`examples/traditional-crane.foldseq`, starts from `sheet square`. It is parsed and
checked, never run, so its senses, [seeds](glossary-additions.md#references) (the
points naming what moves) and `keeping` pairs
([disambiguators](glossary-additions.md#references)) are **UNVERIFIED** (M5
derives them). Its steps are the book's 28. No move sits outside a step
([D12](decisions.md#d12-the-text-syntax), the text syntax;
[C14](decisions.md#changes-since-draft-v2)), so a diamond start written as
`rotate 1/8 turn` would be a step of its own and make 29. This section fixes what
the source holds and asserts.

| Crane steps | Written with | Runs from |
| --- | --- | --- |
| 1, 3 | two `fold and unfold` moves in one step | M2 |
| 2, 9, 13, 16, 19, 22 | `turn over left-right` | M2 |
| 7 | `unfold` | M2 |
| 5, 6, 10, 15, 18, 21 | folds by alignment with `top flap`, along `end of crease of …`, or along existing creases | M4 |
| 12, 14 | `model [...]` folds ("leaving a small gap" names no landmark, and `repeat` refuses a step using `model`) | M4 |
| 17, 20, 23 | `repeat` | M4 |
| 4 | `collapse at centre keeping [...] flat until 180°` | M5 |
| 8; 11 | `petal top flap until 180°`; `repeat` of 8 `turned 2/4 about centre` | M5 |
| 24, 25, 26, 27 | [`not modelled`](glossary-additions.md#the-sequence-language) "swivel fold" twice, "fold the head", "inside reverse fold" | — |
| 28 | [`checkpoint`](glossary-additions.md#the-sequence-language) `"crane.fold" { stacking first }`, then `not modelled "open the wings and shape the body"` | — |

Step 11's back petal lifts the corner diagonally opposite step 8's: in
`bird-base-sequence.fold` the first petal moves material corner (1, 0) and the
second (0, 1) (§11 command 8). So the `repeat` is a half turn about the centre,
`turned 2/4`, or a mirror across the diagonal joining the other two corners. A
quarter turn would lift an adjacent corner, which no petal moves, and `repeat`
would refuse it as `RepeatNotSymmetric` (reasoned from
[D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused), which checks
a repeat's creases and hinge turns against the isometry's image). Which of the two
spellings the runner accepts is **UNVERIFIED**, like the senses.

**The path that looks truncated.** Step 28 writes `"crane.fold"`, not
`"examples/crane.fold"`, because a `checkpoint` path is relative to the source's
own directory ([D13](decisions.md#d13-the-run-verb-and-io),
[04 R-04-6](04-prd-sequence-source-and-cli.md#requirements)), and this source
already sits in `examples/`; the longer spelling would name
`examples/examples/crane.fold`.

`examples/crane.fold` is the finished crane's crease pattern: 58 vertices, 129
edges, 72 faces, assignments and no `edges_foldAngle` (§11 command 5). A
checkpoint reads explicit angles first and assignments otherwise, as `start folded`
does ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)), so
this file is folded from its assignments.

| Assertion | Red when |
| --- | --- |
| `parseSequence` succeeds with 28 steps | a keyword the file uses leaves the grammar |
| `checkSequence` succeeds, pure, loading no file | checking needs `examples/crane.fold` |
| Exactly five `NotModelled` moves and one `Checkpoint` | either constructor removed (compile or parse fails); `not modelled "…"` parsed as a caption |
| `parseSequence (prettySequence s)` returns `s`, spans stripped | the printer drops a checkpoint's block |

## 6. Budgets, measurements and where tests run

### 6.1 Budgets count work

A budget is counted work, identical on every machine given identical bits, as
`Budget` argues for stacking guesses
([`Stacking.hs:151-165`](../src/Senbazuru/Origami/Stacking.hs#L151-L165)).
Seconds appear only as CI job timeouts. Each move record carries a `StepCost`
(**SKETCH**) that `--report` prints:

| Count | Limit | On reaching it |
| --- | --- | --- |
| [Sweep intervals](glossary-additions.md#geometry) ([`HingeSweep.hs:100`](../src/Senbazuru/Origami/HingeSweep.hs#L100)) | 4096 at depth 20 ([`:94-95`](../src/Senbazuru/Origami/HingeSweep.hs#L94-L95)), from `RunSettings` | `SweepUnresolved`, a refusal ([`:455`](../src/Senbazuru/Origami/HingeSweep.hs#L455)); the runner never raises the limit |
| Refolds (`foldFrameWith` calls) | none | recorded: about 7 per checked step today, counted from code ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md) finding 6), plus one per creasing move for 05 L7–L8; E2 pins the blintz's, so caching is a reviewed change |
| Triangles `checkFlap` inspects; triangle pairs at each endpoint (all pairs, finding 7) | none in v1 | recorded |
| Stacking guesses per component | `--layer-budget` | `GaveUpStacking`, its own error (R-05-39) |
| Settle triangles | 1,192 for `run --settle`; 392 in default CI (R-07-41) | `TriangleBudget` before solving (07 AC-13) |

A sequence's cost is the sum of its records', plus a creasing-and-stacking entry
for each move that adds a crease.

### 6.2 What has been measured

From [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
"Measured" and "Addendum": the compiled test binary under `/usr/bin/time -p`
with `--match`, by [`scripts/time-specs.sh`](research/scripts/time-specs.sh), in
a separate clone on a loaded Apple M1 Max (10 cores).

| What | Wall | hspec's own time | Runs | Load average |
| --- | --- | --- | ---: | --- |
| Matching nothing | 19.03, 19.59, 20.95 s (user 15.91, 15.76, 16.92 s) | ≤ 0.0003 s | 3 | 8.6–9.3 |
| `BlintzSequenceSpec` | 14.81–21.24 s | 0.0096–0.0141 s | 5 | 7.4–10.7 at start |
| `HelmetSequenceSpec` | 14.86–15.00 s | 0.0222–0.0243 s (runs 1–3) | 5 | 7.4–9.5 at start (runs 1–3) |
| `CraneWingSpec` | 16.00–16.14 s | **1.21–1.25 s** | 5 | 5.6–6.8 after |
| `CheckedBirdSpec` | 27.36–27.50 s | **12.50–12.52 s** (3 logs kept the line) | 4 | 5.5–6.2 after |
| CI test step ([#208](https://github.com/avalonalex/senbazuru/issues/208)) | 10m48s | 626 s over 1,387 examples; `CraneRoot` ≈164.87 s, `CraneSpread` 97.48 s | 1 | — (`ubuntu-latest`) |

Reading it: a run matching nothing still takes 19–21 s of wall time (about 16 s
user), and every filtered run pays that setup, because hspec's `runIO` runs while
the test tree is built, before `--match` selects anything
([glossary-additions](glossary-additions.md#code-and-tests)), so only hspec's own
time isolates a spec. `CheckedBird` certifies with exact arithmetic and uses
neither `Flap` nor `HingeSweep` (finding 11), so its cost says nothing about a
runner. The per-stage crane `checkFlap` profile, the `stack test --match` runs
and a 20-step crane estimate were never run ("Unverified" 1–3), so **no
wall-clock guard is adopted**. The first sequence spec's PR times the zero-match
run before and after, compiled rather than in GHCi
([AGENTS.md "Testing"](../AGENTS.md#testing)), over 3–5 runs, the count
[07 R-07-41](07-prd-material-consumption.md#requirements) asks for before raising
the settle cap.

### 6.3 `beforeAll`, not `runIO`, and a slow job

Fourteen spec files build fixtures in `runIO` (`grep -rl runIO test | wc -l`),
such as [`BlintzSequenceSpec.hs:31`](../test/BlintzSequenceSpec.hs#L31) and
[`CraneWingSpec.hs:32`](../test/CraneWingSpec.hs#L32). `beforeAll` runs only when
an item under it runs, as the crane-material specs rely on
([`WingBendingSpec.hs:54`](../test/WingBendingSpec.hs#L54)); that is inferred, not
documented ("Unverified" 7), so the first sequence spec's PR confirms it once
with an uncommitted `beforeAll` action writing to stderr under a zero-match run.

1. Every new sequence spec builds its run in `beforeAll`.
2. A crane-sized fixture (`crane.fold` has 72 faces) sits under `describe "slow"`.
3. The default job runs `stack test --test-arguments '--skip /slow/'`; a new slow
   job runs `--match /slow/`. hspec 2.11.12 is pinned with both flags (finding 9);
   today CI runs one `stack test` ([`ci.yml`](../.github/workflows/ci.yml)).
4. Existing `runIO` specs stay as they are; a recipe's spec changes only in that
   recipe's deletion PR (§9) ([D16](decisions.md#d16-testing-and-acceptance),
   [C71](decisions.md#changes-since-draft-v2)).

| Default job | Slow job |
| --- | --- |
| M1 syntax tests and §5; §2; §3; blintz and helmet equivalence; 05's unit tests on the quarter, blintz and bird fixtures; 06's goldens; settles ≤ 392 triangles | crane-wing sequence and equivalence; [D11](decisions.md#d11-stacking-choices-are-relations)'s crane relations; bird route equivalence; collapse on the crane; M6's crane solve; line drawing on 4,312 triangles |

**The slow job changes a recorded sentence.** It is a fourth CI job beside
today's `test`, `format` and `lint`
([`ci.yml:11`](../.github/workflows/ci.yml#L11), [`:36`](../.github/workflows/ci.yml#L36),
[`:71`](../.github/workflows/ci.yml#L71)), and
[`AGENTS.md:378-379`](../AGENTS.md#workflow) requires "all three CI checks" green
before merge. The M4 PR adding the slow job changes that sentence
([decisions §3](decisions.md#3-recorded-text-this-design-changes) row 15,
[C51](decisions.md#changes-since-draft-v2)). Owner decision 12's default makes the
slow job a required check, so the sentence counts four; an optional slow job would
let slow regressions merge.

## 7. Angle equality

After [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md)
"Implications" item 9:

| Angle | Compare | Why |
| --- | --- | --- |
| [Driving parameter](glossary-additions.md#macro-moves) (`until 175°`) | exactly | a stored `Rational` |
| Literal copied through (`pose` angles, manifest values) | exactly | untouched |
| Endpoint pinned by an explicit guard to 0 or ±180: the writer's `F` at exactly 0 | exactly | the guard writes the literal |
| Flap endpoint: `angle + progress * travel` on the author's ±180 ([`Flap.hs:343`](../src/Senbazuru/Origami/Flap.hs#L343)), no guard | exactly | IEEE sums and products of whole-number `Double`s are exact ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md) finding 16) |
| Two outputs of one binary on one platform (EDSL against text; a repeated run) | exactly | deterministic |
| Formula-derived (collapse, rabbit ear, petal) | within 1e-12°, as [`RabbitEarSpec.hs:49`](../test/RabbitEarSpec.hs#L49) and [`CheckedPetalSpec.hs:146`](../test/CheckedPetalSpec.hs#L146), until the tolerance-unification issue names one | the rabbit-ear literal is one [ulp](glossary-additions.md#geometry) from its formula |

Two traps. `-0.0 == 0.0` under Haskell's `Eq`, so a value comparison passes where
golden bytes differ. And a sample is written as a value of the macro's driving
parameter (`sample 90°`), never as a fraction of the route: turning the fraction
back into degrees, `175 * (90/175)`, gives `89.99999999999999`
([A2](research/A2-study-recipes-as-proto-dsl.md) F32, Python), which fails an
exact comparison with 90.

## 8. Bytes that differ by platform

From [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
findings 12–17, lines re-read here:

| Output | What can move | Policy |
| --- | --- | --- |
| Any folded position | last bits: `cos`/`sin` in the rotation ([`Rigid.hs:117-129`](../src/Senbazuru/Geometry/Rigid.hs#L117-L129)), recorded as differing on macOS and Linux ([`BirdSequenceSpec.hs:43-45`](../test/BirdSequenceSpec.hs#L43-L45)). `bird-base-sequence.fold` holds `-6.123233995736766e-17` where exact arithmetic gives 0 (its magnitude is `cos (pi/2)` in `Double`), and 175 nonzero numbers below 1e-15 in magnitude (§11 command 6) | tolerance, never exact |
| SVG | a coordinate crossing a 0.0005 rounding boundary ([`Svg.hs:332-345`](../src/Senbazuru/Render/Svg.hs#L332-L345)); a ring's first corner is chosen on formatted strings ([`:280-294`](../src/Senbazuru/Render/Svg.hs#L280-L294)) | goldens exact; a Linux-only diff is fixed in serialisation (`docs/notes/closed-path-starts.md`) |
| GLB positions | a coordinate within float noise of half a rounding step ([`Gltf.hs:259-264`](../src/Senbazuru/Render/Gltf.hs#L259-L264), [`:309-314`](../src/Senbazuru/Render/Gltf.hs#L309-L314)); equal packed corners keep input order ([`:386-399`](../src/Senbazuru/Render/Gltf.hs#L386-L399)) | goldens exact |
| GLB JSON | raw `edges_foldAngle`, `senbazuru:material_coords`, `layerRequirements` direction ([`Gltf.hs:236-242`](../src/Senbazuru/Render/Gltf.hs#L236-L242)); material coordinates carry trig bits once a crease is mapped back through a face's rotation (finding 15) | default-CI fixtures crease no layers; rounding these numbers moves goldens, so its own issue |
| FOLD | every coordinate; trig-derived angles and material coordinates ([`Load.hs:182-183`](../src/Senbazuru/Fold/Load.hs#L182-L183); `-0` dropped, [`Types.hs:583-596`](../src/Senbazuru/Fold/Types.hs#L583-L596)) | E4 exact without coordinates, E5 within 1e-12; material coordinates within 1e-12 for moves creasing through layers |
| Eighth turns | written coordinates (`rotationAbout`, [D5](decisions.md#d5-presentation-and-the-readers-side)) | owner decision 10 |

When a golden differs on Linux only, decode E9's frame first: it shows whether the
cause is a rounding step, a raw JSON number or a clipping choice.

## 9. Migrating the study recipes

After [gap-study-consumption-contract](research/gap-study-consumption-contract.md)
"(d) Migration table", which lists every test line guarding each recipe. Each
"becomes a sequence" row lands as two PRs:

1. **Equivalence.** The sequence goes beside the recipe, both built once in
   `beforeAll`. Records meet [A2](research/A2-study-recipes-as-proto-dsl.md) F28's
   exact bar (end angle lists, order counts, frame counts) and F29's tolerant one
   (1e-12 material error, per-face placement, contact); orders compared with
   `shouldMatchList`; goldens byte-identical.
2. **Deletion.** The recipe leaves the `other-modules` lists of the study
   executable ([`senbazuru.cabal:179`](../senbazuru.cabal#L179)) and the test
   suite ([`:195`](../senbazuru.cabal#L195)); gallery and spec point at the
   sequence.

**Reusing recipe goldens.** `checked-blintz.svg` is an eleven-figure page: the
open square, then each move's halfway pose and endpoint
([`BlintzSequence.hs:75-87`](../study/fold-material/BlintzSequence.hs#L75-L87),
[`BlintzSequenceSpec.hs:125-127`](../test/BlintzSequenceSpec.hs#L125-L127)).
`checked-helmet.svg` has seven, the first intermediate at 120° because "at this
camera's 45-degree elevation the first 90-degree pose has the open sheet's
silhouette" ([`HelmetSequence.hs:70-86`](../study/fold-material/HelmetSequence.hs#L70-L86)).
A step page draws one figure per written state
([D24](decisions.md#d24-states-figures-and-their-numbers), states, figures and
their numbers), and a flap move writes no halfway state: only a
[macro-move](glossary-additions.md#macro-moves) carries `sample` poses
([D22](decisions.md#d22-figures-holding-several-moves), figures holding several
moves; [02 §8.5](02-language-semantics.md#85-together-and-sample)). The blintz's
five steps write six states, so `stepNotes` gives six figures
([03 A-6](03-prd-embedded-dsl.md#acceptance-criteria)), and neither page comes
from it. The equivalence PR rebuilds each
page through the recipe's own page function, from each record's `SweptHinge c`:
`flapAt c 0`, `flapAt c 0.5` (or `120/180`) and `recordAfter` (`flapAt` is
exported, [`Flap.hs:49-59`](../src/Senbazuru/Origami/Flap.hs#L49-L59)). **Red
when** the record's [working pattern](glossary-additions.md#running-a-sequence)
differs from the recipe's start in face numbering, ring order or orders, which
moves the halfway poses and so the bytes.

This is [D16](decisions.md#d16-testing-and-acceptance)'s migration rule
([C50](decisions.md#changes-since-draft-v2)). Draft v2 said the migration keeps
the recipe's figure-per-corner layout to reuse `checked-blintz.svg`; one figure
per corner cannot reproduce an eleven-figure page. The migration table calls the
helmet's 120° pose "a 120° illustration rule as presentation"; it is an
illustration pose, which moves paper along the route, not a presentation change,
which moves none ([D5](decisions.md#d5-presentation-and-the-readers-side)).

| Recipe | Fate | Waits for |
| --- | --- | --- |
| `BlintzSequence` | becomes a sequence, first | M2 |
| `HelmetSequence` | becomes a sequence, second; a [hinge](glossary-additions.md#origami) named by one material line resolves to several edges | M2 |
| `CraneWing` | stays; its prefix becomes a sequence | M4 (folding some layers, stacking relations; `expect refused` lands at M2); slow job |
| `CraneSpread`, `CraneRoot`, `CraneBody`, `CraneInternal` | stay; [holds](glossary-additions.md#material) re-expressed by name, 07 AC-1 first | M6, with #208 or no re-solve (R-07-40) |
| `CheckedPetal`, `CheckedBird` | a study-authored sequence of macro-moves; modules shrink to entries in the [certificate](glossary-additions.md#assurance) registry | M5 and the registry (R-07-36); slow job |
| `BasicBases` endpoints; frog guide | stay (squash and a frog petal are `not modelled`) | — |
| `cases.json` `single`, `double`, `kite`, `blintz` | stay as state-only controls (`blintz` after owner decision 8) | — |
| `cases.json` `square`, `waterbomb`, `rabbit-ear` | generated from macros; a one-ulp literal change is a reviewed fixture change (§7) | M5 |
| `cases.json` `bird-petal` | stays: the source of `bird-base-sequence.fold`, compared exactly except coordinates ([`BirdSequenceSpec.hs:39-51`](../test/BirdSequenceSpec.hs#L39-L51)) | exact regeneration or a reviewed fixture change |

## 10. Open questions for the owner

From the owner decisions in [10](10-roadmap-risks-questions.md#6-owner-decisions),
each with the default [decisions §9](decisions.md#9-owner-decisions) recommends:

1. **(8) Blintz direction**, which fixes E1–E10's source and goldens. Default:
   the recipe's `fold behind`.
2. **(9) The quarter-fold fixture.** Default: it stays as the regression, and the
   state-rule page is a new golden. Migrating it makes test 1's assignments exact
   and moves two goldens (§1.2).
3. **(10) Eighth turns.** Default: trigonometry, which puts platform bits in
   written coordinates, stated (§8).
4. **(12) CI placement and triangle budget.** Default: crane-sized sequences in a
   slow job that is a required check, so row 15 changes AGENTS.md's "all three CI
   checks" to four; default CI settles at most 392 triangles (§6.3).

The questions this file raised earlier are decided: test 2 lands with the later
of M3 and M4 under rules T1–T5 (§2.3; [C48](decisions.md#changes-since-draft-v2),
[C49](decisions.md#changes-since-draft-v2)); existing `runIO` specs stay until
their recipe's deletion PR (§6.3; [C71](decisions.md#changes-since-draft-v2));
and the bird page with arrows is pinned as a golden before 05 L3 (§1.3;
[C70](decisions.md#changes-since-draft-v2)).

## 11. Commands behind the numbers

From the repository root at `568dcb6`.

1. `for f in examples/*.fold; do n=$(jq '(.file_frames // []) | length' "$f"); [ "$n" -gt 0 ] && echo "$f $n"; done`
2. `jq -c '.file_frames[] | {frame_title, frame_classes, a: .edges_assignment, ang: .edges_foldAngle}' examples/quarter-fold-steps.fold`
   (and the key frame), and
   `python3 -c 'import json;d=json.load(open("examples/quarter-fold-steps.fold"));V=d["vertices_coords"];[print(k,V[a],V[b]) for k,(a,b) in enumerate(d["edges_vertices"]) if k>7]'`
3. Signed areas, centroids, moved vertices. Prints `[0.25]*4` with centroids
   (0.75, 0.25), (0.75, 0.75), (0.25, 0.75), (0.25, 0.25); then
   `[0.25, 0.25, -0.25, -0.25] [0, 3, 7]`; then `[0.25, -0.25, 0.25, -0.25] [2, 3, 6]`.

   ```python
   import json
   d = json.load(open('examples/quarter-fold-steps.fold'))
   F = d['faces_vertices']; S = [d['vertices_coords']] + [f['vertices_coords'] for f in d['file_frames']]
   area = lambda r, P: sum(P[r[i]][0]*P[r[(i+1)%len(r)]][1] - P[r[(i+1)%len(r)]][0]*P[r[i]][1] for i in range(len(r)))/2
   for s, P in enumerate(S):
       print(s, [area(f, P) for f in F], [tuple(sum(P[i][k] for i in f)/4 for k in (0, 1)) for f in F] if s == 0 else
             [i for i in range(9) if P[i] != S[s-1][i]])
   ```

4. §2.3's rules on hand-built frames (`W`: each state's written material
   segments and angles as [D6](decisions.md#d6-crease-graphs-grow-between-frames)
   and [D8](decisions.md#d8-folding-some-layers) (folding some layers of folded
   paper) would make them; not runner output). Prints
   `0 4 4 False False True True`, `1 6 7 False True True True`,
   `2 9 12 True True True True`: state, written vertices, written edges, draft
   v2's edge clause, draft v2's vertex clause, T1, T2. For §2.3's red-when cases, `run` is
   called on a changed `W`. Creasing only the top layer in state 2 (dropping
   `((h,h),(0,h),-180)` and joining `((0,1),(0,h))` and `((0,h),(0,0))` into
   `((0,1),(0,0))`) prints `2 8 10 False True False True`; adding
   `((0,0),(h,h),0)` to state 1 prints `1 7 8 False True True False`.

   ```python
   import json, math
   from fractions import Fraction as Fr
   d = json.load(open('examples/quarter-fold-steps.fold')); M = [tuple(map(Fr, p)) for p in d['vertices_coords']]
   ang = [d['edges_foldAngle']] + [f['edges_foldAngle'] for f in d['file_frames']]; h = Fr(1, 2)
   B0 = [((0,0),(1,0)),((1,0),(1,1)),((1,1),(0,1)),((0,1),(0,0))]
   B1 = [((0,0),(h,0)),((h,0),(1,0)),((1,0),(1,1)),((1,1),(h,1)),((h,1),(0,1)),((0,1),(0,0))]
   B2 = [((0,0),(h,0)),((h,0),(1,0)),((1,0),(1,h)),((1,h),(1,1)),((1,1),(h,1)),((h,1),(0,1)),((0,1),(0,h)),((0,h),(0,0))]
   W = [[s+(0,) for s in B0], [s+(0,) for s in B1] + [((h,0),(h,1),-180)],
        [s+(0,) for s in B2] + [((h,h),(h,0),-180),((h,h),(1,h),180),((h,h),(h,1),-180),((h,h),(0,h),-180)]]
   on = lambda p, a, b: (b[0]-a[0])*(p[1]-a[1]) == (b[1]-a[1])*(p[0]-a[0]) and min(a[0],b[0]) <= p[0] <= max(a[0],b[0]) and min(a[1],b[1]) <= p[1] <= max(a[1],b[1])
   inside = lambda s, t: on(s[0], t[0], t[1]) and on(s[1], t[0], t[1])
   ln = lambda s: math.hypot(float(s[0][0]-s[1][0]), float(s[0][1]-s[1][1]))
   def run(W, k):
       X = [(M[a], M[b], ang[k][i]) for i, (a, b) in enumerate(d['edges_vertices'])]; wv = {p for w in W[k] for p in w[:2]}
       v2_edge = all(sum(inside(w, x) and w[2] == x[2] for x in X) == 1 for w in W[k])
       v2_vertex = all(any(on(p, w[0], w[1]) for w in W[k]) for p in M if p not in wv)
       t1 = all((lambda H: (len(H) == 1 and H[0][2] == x[2]) or (not H and x[2] == 0))([w for w in W[k] if inside(x, w)]) for x in X)
       t2 = all(abs(sum(ln(x) for x in X if inside(x, w)) - ln(w)) < 1e-15 for w in W[k])
       print(k, len(wv), len(W[k]), v2_edge, v2_vertex, t1, t2)
   for k in range(3):
       run(W, k)
   ```

5. `jq -c '[.edges_vertices[8:12][] as [$a,$b] | [.vertices_coords[$a], .vertices_coords[$b]]]' examples/blintz-base.fold`;
   `jq -c '{n_v:(.vertices_coords|length), n_e:(.edges_vertices|length), n_f:(.faces_vertices|length), has_angles: has("edges_foldAngle")}' examples/crane.fold`
6. `grep -o -i -- '-6.123233995736766e-17' examples/bird-base-sequence.fold`;
   `jq '[.. | numbers | select(. != 0 and fabs < 1e-15)] | length' examples/bird-base-sequence.fold` (175)
7. The id ranges §4 quotes. Prints each file's highest requirement id and last
   acceptance row; on 2026-09-15: R-03-14, A-7; R-04-30, A19; R-05-49; R-06-23,
   A17; R-07-45, AC-17; R-08-31, A-23. Milestone splits come from each file's own
   tags (03's A-6, 04's "Dependencies", 05's per-section "Milestone").
   `for f in PRDs/0[3-8]-*.md; do echo "$f: $(grep -oE 'R-0[3-8]-[0-9]+' "$f" | sort -t- -k3 -n -u | tail -1) $(grep -oE '^\| (A|AC)-?[0-9]+ ' "$f" | tail -1)"; done`
8. Which corner each bird petal lifts. Prints `True [1, 4, 5] [3, 6, 7] [[1, 0], [0, 1]]`:
   the sequence's edges equal `bird-base.fold`'s, so vertex ids agree; the first
   petal (`file_frames[0]` to `[7]`) moves vertices 1, 4, 5 and the second (`[7]`
   to `[14]`) moves 3, 6, 7; vertices 1 and 3 are material corners (1, 0) and
   (0, 1).
   `python3 -c 'import json; d=json.load(open("examples/bird-base-sequence.fold")); b=json.load(open("examples/bird-base.fold")); F=d["file_frames"]; mv=lambda i,j: [v for v in range(len(F[i]["vertices_coords"])) if any(abs(x-y)>1e-9 for x,y in zip(F[i]["vertices_coords"][v],F[j]["vertices_coords"][v]))]; print(F[0]["edges_vertices"]==b["edges_vertices"], mv(0,7), mv(7,14), [b["vertices_coords"][v] for v in (1,3)])'`

## Research links

- [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md):
  "Measured", "From reading the code (counts, not timings)", "Platform-sensitive
  bytes (for task d)" findings 12–17, "Implications for the design", "Unverified",
  "Addendum — runs that finished after this note was written".
- [gap-study-consumption-contract](research/gap-study-consumption-contract.md):
  "(d) What guards each recipe", "(d) Migration table".
- [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md):
  "Implications" item 9.
- [gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md):
  finding 18.
- [A2](research/A2-study-recipes-as-proto-dsl.md): F28–F32.
- [gap-layer-selective-folds](research/gap-layer-selective-folds.md): "(e) The
  traditional crane, step by step"; "Re-deriving CraneWing by rule (script)".
