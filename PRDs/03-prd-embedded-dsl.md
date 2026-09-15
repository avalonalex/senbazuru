# 03 — PRD: fold sequences written in Haskell

Written 2026-09-15 against `568dcb6`. This is feature 1 of three
([00](00-overview.md)): milestone M1, with the running half at M2. It follows
[decisions.md](decisions.md), the decision record every PRD is written against;
where the two disagree, the record wins. The decisions this file carries are
[D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders), the
syntax tree and its builders, and the builder's side of
[D12](decisions.md#d12-the-text-syntax), canonical values and the round trip. What
each construct *means* belongs to [02](02-language-semantics.md). Its text spelling
and the printer belong to [04](04-prd-sequence-source-and-cli.md). This file covers
how a Haskell author builds the same value. Nothing here is implemented. Blocks
marked **SKETCH** show shape, not final signatures.

## Summary

A Haskell author writes a fold sequence in an *embedded DSL*, a language written as
Haskell values ([glossary-additions][ga-code]): a `do` block in a builder monad,
`Build`. The result is a `Sequence`, a plain data type with no functions inside. The
parser produces the same value from a *sequence source*, the text an author writes
([glossary-additions][ga-lang]). The builder hands out **names, never geometry**, so
a `Sequence` can be:

- compared with `==`;
- printed as text;
- checked without folding anything;
- run by the *runner*, the library function that folds it move by move
  ([glossary-additions][ga-run]).

Haskell loops run while the value is built, so the printed text lists every step
they made. The acceptance test is one equation: the blintz below, built in Haskell,
equals the blintz parsed from text once source positions are stripped.

## Problem and evidence

- **A sequence in Haskell today is a table of ids that fits one file.** The blintz
  recipe is five tuples, each a caption, an edge id, a face id and an angle change
  ([`BlintzSequence.hs:50-56`](../study/fold-material/BlintzSequence.hs#L50-L56)).
  Its edge ids "refer to that fixture after cutting and tracing"
  ([`:4-5`](../study/fold-material/BlintzSequence.hs#L4-L5)). Adding a crease
  re-traces the faces and shifts edge ids ([A1] "(c) Identifiers that do not survive,
  and the ones that do").
- **Each recipe threads its own state by hand.** The blintz loop does it at
  [`BlintzSequence.hs:57-73`](../study/fold-material/BlintzSequence.hs#L57-L73). The
  helmet recipe repeats it
  ([`HelmetSequence.hs`](../study/fold-material/HelmetSequence.hs), the study's second
  hand-written sequence: three turns that make the traditional helmet base) ([F] "A.
  What the repository already commits to", finding 2).
- **[#60](https://github.com/avalonalex/senbazuru/issues/60) predates the other
  consumers.** It sketches `apply :: Move -> Frame -> Either MoveError Frame`. It
  rejects a *free monad* (a program as a chain of instructions, each ending in a
  function that computes the rest from the previous result) because "there is one
  interpreter". This design has at least four consumers of one sequence: frame
  generation in the library, the CLI parser and printer, diagram annotation, and the
  material study ([D] "A. Constraints and decisions, each with a verdict — question
  (a)", A2). So "one interpreter" no longer holds.
  [D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders)
  supersedes `apply` and that reason, keeping #60's plain data type; row 3 of
  [the recorded-text table](decisions.md#3-recorded-text-this-design-changes) amends
  the issue, and [01 §4.3](01-architecture.md#43-60) writes the amendment out.
- **A file holds only data**, so a sequence that is also a file cannot let later
  steps depend on computed results ([F] "B. Embedding styles", finding 14).
- **The library has no `State` dependency.** Its `build-depends` has no
  `transformers` or `mtl`
  ([`senbazuru.cabal:152-159`](../senbazuru.cabal#L152-L159)).

## Goals

1. Either front end gives one `Sequence`, so the Haskell blintz equals the text
   blintz.
2. Everything the text can say can be built from Haskell at M1, a step with no
   caption included.
3. Passing a point reference where a line belongs *to a builder* is a compile error,
   with no language extension added.
4. Building is pure and cannot fail. The refusals are the ones text gets, and each
   names where it happened: the step, the header or the written state.
5. A built sequence runs and writes its file from GHCi in a few lines.

## Non-goals

| Out of scope | Why |
| --- | --- |
| Binds that return lengths, faces or positions | The program could not be printed ([below](#what-a-bind-returns-names-never-geometry)) |
| Printing the Haskell back, loops included | A round trip holds on the tree, not on source ([F] "E. Round-trips", finding 21) |
| Macros defined by authors | v1's macro table is closed ([F] "Open questions" 4) |
| A type-indexed syntax tree | The parser would have to typecheck into it ([F] "Rejected alternatives") |
| An error type for the builder | `Build` cannot fail |
| Settle requests before M6 | [07](07-prd-material-consumption.md) owns `SettleRequest` |

## Users and scenarios

| Who | Scenario |
| --- | --- |
| Test author (M2) | Rewrites the blintz and helmet recipes as sequences, then deletes the recipes ([09](09-testing-and-acceptance.md)) |
| Author of generated patterns | Writes pleats or families of bases with loops ([AGENTS.md](../AGENTS.md#third-party-material) prefers generated patterns), then prints the result for CLI users |
| Explorer at GHCi | Builds, runs and reads refusals or *move records* ([glossary-additions][ga-run]); writes a *sequence file* ([glossary-additions][ga-fold]) |
| Study code (M6) | Builds the sequence it settles as a value, not as ids ([07](07-prd-material-consumption.md)) |

## Design

### The value first: the blintz

A *blintz* folds each corner of a square to its centre
([glossary-additions][ga-origami]); [00](00-overview.md#the-problem-in-one-example)
gives it as text. The sketch below is the one
[decisions.md §7](decisions.md#7-examples) carries. It writes the sense with the
lowercase builder `mountain`, not a constructor, for the reason given under
[the builder vocabulary](#the-builder-vocabulary).

Three lines in it look like typos, and are not:

- **`sequenceOf`, not `sequence`.** `sequence` and `repeat` are Prelude functions,
  hence `sequenceOf` and `repeatSteps`.
- **`mountain` under a caption saying "behind".** The text's `behind` is an alias of
  `mountain`, read from the *reader's side* ([glossary-additions][ga-run]). The tree
  stores only the sense, mountain or valley.
- **`unfold [c1]` takes a list**, because `unfold NAME…` may name several steps.

**SKETCH:**

```haskell
blintz :: Sequence
blintz = sequenceOf (header "Blintz base, then reopen one corner" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
  c1 <- step "c1" "Fold the south-east corner behind, to the centre." $ fold mountain (cornerOf SouthEast `onto` centre)
  forM_ [(NorthEast, "north-east"), (NorthWest, "north-west"), (SouthWest, "south-west")] $ \(c, word) ->
    step_ ("Fold the " <> word <> " corner behind, to the centre.") $ fold mountain (cornerOf c `onto` centre)
  step_ "Reopen the first corner." $ unfold [c1]
```

- `header` takes a title, the *sheet* (the starting paper) and the *anchor*. The
  anchor is the material point whose face stays still
  ([glossary-additions][ga-run]). Other fields take the parser's defaults
  ([Header construction](#header-construction)).
- `step` makes one *step* ([glossary-additions][ga-narrow]), which is one figure
  holding one or more *moves* ([glossary-additions][ga-lang]). It returns a
  reference to the step, here `c1`. `step_` makes an unnamed step and returns `()`,
  like `forM_`.
- `` cornerOf SouthEast `onto` centre `` is the fold line that lays the south-east
  corner onto the centre. In the text it is `corner south-east to centre`. Corners
  use the *sheet compass* ([glossary-additions][ga-ref]): names fixed on the
  unfolded sheet, in sheet coordinates (u, v), with the south-west corner at (0, 0)
  and north as increasing v ([02 §3](02-language-semantics.md#3-numbers)). On this
  unit sheet (u, v) is just the file's (x, y), so south-east is (1, 0).

**Checked on 2026-09-15.**

- **The captions the loop builds match the text's.** This script, run from the
  repository root, prints `5 True`:

  ```bash
  python3 -c '
  import re
  fence = "`" * 3                                   # a Markdown code fence
  text = open("PRDs/00-overview.md").read()
  block = text.split(fence + "text", 1)[1].split(fence, 1)[0]   # the first text block in 00: the blintz
  found = re.findall(r"^step(?: \S+)? \"([^\"]*)\"", block, re.M)
  built = ["Fold the south-east corner behind, to the centre."]
  built += ["Fold the " + w + " corner behind, to the centre." for w in ["north-east", "north-west", "south-west"]]
  built += ["Reopen the first corner."]
  print(len(found), found == built)'
  ```

- **The lines and the anchor fit the fixture.** Rerunning
  [00](00-overview.md#the-problem-in-one-example)'s fixture command prints
  `south-east 8 M-180 (1/2, 0) (1, 1/2)`, then edges 9, 10 and 11 for the
  north-east, north-west and south-west corners, then
  `centre on a vertex: False | centre on an edge: False`. So each corner-to-centre
  line is exactly one existing crease. The `M-180` is the file's already-folded
  angle, which a plain `sheet` sets to 0
  ([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)).
  `centre` lies on no vertex and no edge, so it is strictly inside one face, as an
  anchor must be ([slots][ga-ref]).

Printed (**SKETCH**, in the layout of [04](04-prd-sequence-source-and-cli.md#canonical-form-and-the-printer),
which owns it):

```text
foldseq 1
title "Blintz base, then reopen one corner"
sheet "examples/blintz-base.fold"
anchor centre

step c1 "Fold the south-east corner behind, to the centre." {
  fold mountain corner south-east to centre
}

step "Fold the north-east corner behind, to the centre." {
  fold mountain corner north-east to centre
}

step "Fold the north-west corner behind, to the centre." {
  fold mountain corner north-west to centre
}

step "Fold the south-west corner behind, to the centre." {
  fold mountain corner south-west to centre
}

step "Reopen the first corner." {
  unfold c1
}
```

The loop is gone. `forM_` ran while `blintz` was built, and the tree holds its three
steps ([F] "C. Builder ergonomics and prior art", finding 17). The moves say
`mountain` while the captions say "behind", because the printer writes canonical
words and never rewrites prose. Parsing this text gives `blintz` back. Nothing gives
the `forM_` back, and nothing needs to.

### What a bind returns: names, never geometry

**SKETCH:**

```haskell
-- Senbazuru.Sequence.Build
newtype Build a = Build (State BuildState a)   -- Control.Monad.Trans.State.Strict
  deriving newtype (Functor, Applicative, Monad)
newtype Moves a = Moves (State MoveState a)    -- a step's body; see below
  deriving newtype (Functor, Applicative, Monad)

type Ref :: Type -> Type                       -- not redundant: under PolyKinds a bare Ref would accept Ref Maybe
newtype Ref k = Ref Name                       -- constructor not exported
data PointK
data LineK
data StepK

sequenceOf        :: Header -> Build () -> Sequence
step              :: Name -> Text -> Moves () -> Build (Ref StepK)
step_             :: Text -> Moves () -> Build ()
stepReturning     :: Name -> Text -> Moves a -> Build (Ref StepK, a)
stepUncaptioned   :: Name -> Moves () -> Build (Ref StepK)
stepUncaptioned_  :: Moves () -> Build ()
mark              :: Name -> Point -> Maybe Point -> Moves (Ref PointK)
letPoint          :: Name -> Point -> Moves (Ref PointK)
letLine           :: Name -> Line -> Moves (Ref LineK)
repeatSteps       :: Ref StepK -> Maybe (Ref StepK) -> Maybe Isometry -> Moves ()
point             :: Ref PointK -> Point           -- PointNamed
namedLine         :: Ref LineK -> Line             -- LineNamed
hingeOf, creaseOf :: Ref StepK -> Line
```

- `BuildState` holds the steps so far, newest first, and `sequenceOf` reverses them
  once.
- Neither state holds a `Frame`, so building cannot fold, fail or do I/O.
- `Name` derives `IsString`, which lets `step "c1"` typecheck under the package's
  `OverloadedStrings` ([`senbazuru.cabal:95-99`](../senbazuru.cabal#L95-L99)).
- **Captions.** A step's caption is `Maybe Text`, because the text may leave it out
  ([D12](decisions.md#d12-the-text-syntax),
  [04](04-prd-sequence-source-and-cli.md#how-the-ambiguities-are-resolved)).
  `step`, `step_` and `stepReturning` take a plain `Text`, so a captioned step needs
  no `Just`, and store `Just` it. `stepUncaptioned` and `stepUncaptioned_` store
  `Nothing`. `step_ ""` stores `Just ""`, which is a different value.

**What breaks if a bind returns geometry.** Suppose `step` also returned the length
of its *hinge*, the line the paper turns about ([glossary-additions][ga-origami]):

```haskell
-- NOT this design: D1 rejects it
(c1, len) <- stepMeasured "c1" "…" $ fold mountain (cornerOf SouthEast `onto` centre)
if len > 0.7 then step_ "Fold the flap in half." (…) else step_ "Leave the flap." (…)
```

On the blintz sheet that hinge runs from (1/2, 0) to (1, 1/2), and is 0.7071 *sheet
lengths* long. A sheet length is the unit that makes the sheet's larger side 1
([glossary-additions][ga-ref]). On a 1 × 1/2 sheet, the same move's hinge runs from
(11/16, 0) to (15/16, 1/2), and is 0.5590. Both come from this command:

```bash
python3 -c '
from fractions import Fraction as F; import math
def hinge(w, h):
    (px, py), (cx, cy) = (w, 0), (w / 2, h / 2)
    a, b, k = 2*(cx-px), 2*(cy-py), cx*cx + cy*cy - px*px - py*py   # the fold line: a*x + b*y = k
    ends = {(x, (k - a*x) / b) for x in (0, w)} | {((k - b*y) / a, y) for y in (0, h)}
    ends = sorted(e for e in ends if 0 <= e[0] <= w and 0 <= e[1] <= h)
    return [tuple(map(str, e)) for e in ends], math.dist(*ends) / max(w, h)
print(hinge(F(1), F(1))); print(hinge(F(1), F(1, 2)))'
```

It prints `([('1/2', '0'), ('1', '1/2')], 0.7071067811865476)` and
`([('11/16', '0'), ('15/16', '1/2')], 0.5590169943749475)`. Then:

1. `sequenceOf` must fold paper to learn `len`. So it needs the sheet's `Frame` and
   returns `Either`, and building can fail for geometric reasons.
2. `run --check`, which refuses without folding
   ([04](04-prd-sequence-source-and-cli.md)), cannot check this program without
   folding it.
3. The text has no `if`. So `prettySequence` writes only the branch taken while
   building against the square: `then`, since 0.7071 > 0.7. Point that file's
   `sheet` line at a 1 × 1/2 sheet and it still takes `then`. The Haskell program
   built against that sheet takes `else`, since 0.5590 < 0.7.
4. A free monad has the same problem: its printer would have to invent `len` to see
   past the bind ([F] finding 14).

A name has none of these problems: `c1` is known before anything folds.

**Why empty types, not `DataKinds`.** A `Ref PointK` passed where `unfold` wants
`[Ref StepK]` is a compile error. The alternative, `Ref (k :: RefKind)`, needs
`DataKinds`, which GHC2021 lacks ([F] finding 10). The GHC user's guide page
[Controlling editions and extensions](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/control.html)
confirms this (fetched 2026-09-15). Adding it would change the stanza every module
inherits.

The kind signature `type Ref :: Type -> Type` looks redundant, but is not. GHC2021
does include `PolyKinds` (same page), under which a bare `newtype Ref k` accepts
`Ref Maybe`.

The tree stores `Name`, never `Ref`, so no interpreter gains a type parameter. That
is the cost [phantom-units.md](../docs/notes/phantom-units.md) weighs (lines
24-28), and here only builder signatures pay it. The `k` in `Ref k` makes the
compiler catch, in builder calls, the mistake `Sequence.Check` refuses as `WrongKind`
(a point name used as a line;
[02 §12](02-language-semantics.md#12-refusal-catalogue)). It never replaces that
check ([F] "F. Static versus dynamic checking", finding 22).

**What the hidden constructor buys.**

- A sequence built only with the `Ref`-taking builders cannot name something
  undefined, because a `Ref` comes only from the builder that defines its name, and
  `sequenceOf` returns none. `move` and the exported constructors bypass this:
  `move (Unfold ["c9"])` compiles, since `Name` derives `IsString`, and
  `checkSequence` refuses it as `UnknownName`, as it does in text.
- `Build` derives no `MonadFix`, although `StateT` has an instance
  ([transformers 0.6.1.0](https://hackage.haskell.org/package/transformers-0.6.1.0/docs/Control-Monad-Trans-State-Strict.html)).
  So `mdo` cannot use a `Ref` before its step.
- A duplicate `step "c1"` is still possible. `checkSequence` refuses it, as it does
  in text.

**Why a step body has its own type, `Moves`**
([D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders),
[C22](decisions.md#changes-since-draft-v2)). The alternative is one builder type,
`step :: Name -> Text -> Build () -> Build (Ref StepK)`. With it, `fold` typechecks
outside any step, and `step` typechecks inside another. Neither fits a `Sequence`,
whose steps hold `[Located Move]`, each move paired with its *span*. The builder
would have to drop or reorder something silently. A separate body type makes both
compile errors. `stepReturning` then lets a mark made in one step reach later ones.
Every call in this file's examples reads the same either way.

### Loops, helpers and what prints

- Haskell control flow (`forM_`, `zipWithM_`, `when`, helper functions) runs during
  building, and the tree records its output.
- A helper prints as its expansion ([F] finding 12). So anything a *file* must name
  is a syntax node, which is why *macro-moves* are constructors
  ([glossary-additions][ga-macro]).
- The round trip is about trees. [D12](decisions.md#d12-the-text-syntax) states it,
  and [R-04-9](04-prd-sequence-source-and-cli.md#requirements) owns it:
  `isRight (checkSequence s) ==> fmap stripSpans (parseSequence "gen" (prettySequence s)) == Right (canonical s)`.
  It says nothing about Haskell source, comments or aliases ([F] finding 21).

### The builder vocabulary

There is one lowercase builder per text keyword. `Sequence.Syntax` exports its
constructors too, and `move :: Move -> Moves ()` appends any `Move` built from them.
Moves are defined in [02](02-language-semantics.md). A *flap* is the paper that
turns ([glossary-additions][ga-narrow]). `FlapOfFirstArgument` turns the flap
containing the fold's first argument. For `` cornerOf SouthEast `onto` centre ``,
that is the paper still joined to the south-east corner once the sheet is cut along
the fold line ([02 §6.3](02-language-semantics.md#63-which-layers)). **SKETCH:**

| Text | Builder |
| --- | --- |
| `fold valley LINE` | `fold valley l` |
| `fold behind 90° LINE top flap moving P` | `move (Fold mountain (Degrees 90) l TopFlap (Just p))` |
| `fold and unfold valley LINE` | `foldAndUnfold valley l` |
| `unfold c1 c2` | `unfold [c1, c2]` |
| `turn over left-right` | `turnOver LeftRight` |
| `rotate 1/8 turn anticlockwise` | `rotate 1 Anticlockwise` |
| `mark A = P` | `mark "A" p Nothing` |
| `let L = LINE` | `letLine "L" l` |
| `repeat a..b` | `repeatSteps a (Just b) Nothing` |
| `expect refused K { MOVE }` | `expectRefused k m`, with `k :: RefusalKind` and `m :: Move` |
| `layers A above B`, in `start folded` or `checkpoint` | `above a b` |
| `corner south-east`, `centre`, `(3/4, 1/4)` | `cornerOf SouthEast`, `centre`, `at (3/4) (1/4)` |
| `P to Q`, `edge west` | `` p `onto` q ``, `edge West` |

The value each builder produces is the constructor that
[04's mapping table](04-prd-sequence-source-and-cli.md#from-spelling-to-syntax-tree)
gives for its text, under the names D1 fixes for the senses and the layer relation:
`valley` is `ValleyFold`, `mountain` is `MountainFold`, and `above a b` is
`LayerAbove a b`. A-7 checks that they agree.

Rules:

- **Defaults are the parser's.** No angle gives `ToFlat`; no layers clause gives
  `FlapOfFirstArgument`. `ToFlat` is kept apart from `Degrees 180` because a bare
  `fold` parses to it and prints with no angle. A builder writing `Degrees 180`
  would print `180°` and no longer equal the text. `foldAndUnfold` takes no angle,
  because `FoldAndUnfold` has no field for one
  ([D12](decisions.md#d12-the-text-syntax)).
- **A trailing `Maybe` is an optional clause of the text**, and `Nothing` leaves it
  out. `mark`'s is `in face containing S`, which picks one layer where P lies on
  several. `repeatSteps`'s is `mirrored across [P, Q]` or `turned k/4 about P`
  ([02 §9](02-language-semantics.md#9-repeat-checkpoint-not-modelled-expect-refused)).
- **`Rotate k` counts eighths of a turn**, so `rotate 1` is 45° and `rotate 2` a
  quarter turn.
- **Builders emit canonical values** ([D12](decisions.md#d12-the-text-syntax)). In
  text, a bare name next to `to`, or on the right of `let`, cannot say whether it
  names a point or a line. The parser always reads it as a point, and
  `Sequence.Check` settles the kind later
  ([04](04-prd-sequence-source-and-cli.md#canonical-form-and-the-printer)). A
  builder produces what the parser would. So `letLine n (namedLine r)` emits
  `Let n (BindPoint (PointNamed m))`, where `m` is `r`'s name, not
  `BindLine (LineNamed m)`. That looks like a typo, and is the parser's tree. No
  builder emits the other non-canonical shapes in 04's table. A value put together
  with `move` may, which is what `canonical` is for.
- **A slot for exactly one move takes a `Move` value**, not a builder body. So
  `expectRefused` cannot receive zero moves or two.
- **Numbers are `Rational`**, so they are exact, like the parser's.
  - A line that looks harmless: `at (1/0) 0` throws when forced, inside the author's
    own code. The cause is `reduce _ 0 = ratioZeroDenominatorError`
    ([`GHC.Real`, base 4.18](https://hackage.haskell.org/package/base-4.18.2.1/docs/src/GHC.Real.html)).
  - No library function can turn that into a `Left`.
  - The same fact makes text `1/0` a parse error with the hint `ZeroDenominator`,
    not a refusal from `Sequence.Check`: no `Rational` can hold it, so no tree ever
    carries one ([D12](decisions.md#d12-the-text-syntax),
    [D20](decisions.md#d20-errors)).
- **Names avoid clashes.**
  - `letPoint` and `letLine` avoid the keyword `let`.
  - `allLayers` avoids Prelude's `all`.
  - Macros take their *driving parameter* ([glossary-additions][ga-macro]) as an
    argument, since `until` is Prelude.
  - No builder is named `pattern`, which hlint parses as a keyword
    ([AGENTS.md](../AGENTS.md#conventions), "Do not name a binding `pattern`").

**The syntax constructors are `ValleyFold`, `MountainFold` and `LayerAbove`**
([D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders),
[C23](decisions.md#changes-since-draft-v2)). The obvious names are taken.
`Fold.Types.Assignment` has `Mountain` and `Valley`
([`Types.hs:302`](../src/Senbazuru/Fold/Types.hs#L302),
[`:304`](../src/Senbazuru/Fold/Types.hs#L304)), and `Fold.Types.Stacking` has
`Above` ([`:334`](../src/Senbazuru/Fold/Types.hs#L334), exported at
[`:81`](../src/Senbazuru/Fold/Types.hs#L81)). GHC 9.6 does not pick a constructor by
its type, so a module importing both `Fold.Types` and a tree that reused those names
would get an ambiguity error at the first unqualified use. Two such modules are
certain:

- `Sequence.Run`, which reads the tree and writes assignments, so the library
  itself would need qualified names at every use;
- the prompt of `stack ghci senbazuru:lib`, which "loads and imports all of the
  modules"
  ([Stack `ghci` docs](https://docs.haskellstack.org/en/stable/commands/ghci_command/),
  fetched 2026-09-15).

So the tree has `Sense = ValleyFold | MountainFold` and
`Relation = LayerAbove Point Point`, and `Sequence.Build` exports the builders
authors write: `valley`, `mountain`, `inFront` and `behind :: Sense`, and
`above :: Point -> Point -> Relation` for the relations of `start folded` and
`checkpoint`. Keeping the old constructor names and exporting only the lowercase
builders was rejected, because `Sequence.Run` would still need qualification
([Proposals not adopted](decisions.md#proposals-not-adopted)). The settle
vocabulary's region type is `SettleRegion` for the same reason, beside
`Origami.Visible`'s `Region`; [07](07-prd-material-consumption.md) owns it.

`grep -rnE '^(mountain|valley|behind|inFront|above)\b' src app study test` finds one
top-level definition, the test helper `above` at
[`LayersSpec.hs:31`](../test/Senbazuru/Origami/LayersSpec.hs#L31), in a module with
no reason to import `Sequence.Build`. `grep -rnE '\b(ValleyFold|MountainFold|LayerAbove)\b'`
over the same directories finds nothing.

### Header construction

**SKETCH:**

```haskell
header :: Text -> SheetSource -> Maybe Point -> Header
header title sheet anchor = Header
  { hTitle = Just title, hSheet = noSpan sheet, hAnchor = noSpan <$> anchor, hSide = ColouredUp
  , hStart = noSpan StartFlat, hMaterial = Nothing, hClosing = Nothing }
  where noSpan = Located NoSpan

sheetFile :: FilePath -> SheetSource    -- SheetFile
sheetSquare :: SheetSource              -- UnitSquare

-- any other field by record update:
whiteUpSquare :: Header
whiteUpSquare = (header "A square, white side up" sheetSquare Nothing) { hSide = WhiteUp }
```

- **`Located` fields.** `sheet`, `anchor`, `start` and `material` are the header
  lines a run can refuse, so each carries a span for the caret to point at
  ([D12](decisions.md#d12-the-text-syntax)'s tree refinements). `header` fills each
  with `NoSpan`, as every built value does.
- **The other fields.** Origami paper is usually coloured on one side and white on
  the other. `hSide` says which side faces the reader at the start
  ([reader's side][ga-run]). `StartFlat` starts every crease at angle 0, where
  `start folded` keeps the file's angles and chooses a stacking by a
  `StackingSpec`: `StartFolded (Relations [above a b, …])` or
  `StartFolded StackingFirst`
  ([02 §2.2](02-language-semantics.md#22-starting),
  [D11](decisions.md#d11-stacking-choices-are-relations)). `hMaterial` is
  [07](07-prd-material-consumption.md)'s `material { … }` block. `hClosing` is the
  optional closing caption, `closing "…"` in text, written after the last step, the
  order the page draws it ([D12](decisions.md#d12-the-text-syntax),
  [04](04-prd-sequence-source-and-cli.md#from-spelling-to-syntax-tree)).
- **Defaults.** They are what the parser gives when those header lines are absent.
- **Sheet paths.** A path is stored as written. The CLI resolves it against the
  source's directory ([D13](decisions.md#d13-the-run-verb-and-io)). A built sequence
  has no directory, so whoever calls the runner loads the sheet, keyed by that same
  text.

### Refusals from a built sequence

`checkSequence` and `runSequence` refuse exactly as for text
([02 §12](02-language-semantics.md#12-refusal-catalogue), as
[D20](decisions.md#d20-errors) corrects it). A built sequence carries `NoSpan` at
every *span*, the field that would hold a file position
([glossary-additions][ga-code]). So:

- **No location.** `sourceLocation err` and `excerpt sourceText err` are `Nothing`,
  and a caller prints the message alone.
- **The message names the place.** Its first words are the only place a Haskell
  author can look, so every `SequenceError` constructor carries one
  ([D20](decisions.md#d20-errors), [C11](decisions.md#changes-since-draft-v2);
  **SKETCH**):

  | Constructor | Place it names |
  | --- | --- |
  | `ParseFailed ParseProblem` | none needed: a built sequence is never parsed |
  | `StaticRefused Place Span StaticProblem`, with `data Place = InHeader \| InStep Int (Maybe Name)` | `step N (name)`, counting steps from 1, or `header` for a problem such as an `anchor` naming nothing |
  | `SheetRefused Span Text SheetProblem` | the header's sheet, by its path as written (`SheetHasNoVertices`, `SheetAlreadyFolded`) |
  | `ResolveRefused Int (Maybe Name) …`, `StepRefused Int (Maybe Name) …` | the step, by index and name |
  | `WriteRefused Int WriteProblem` | the written state, by its `file_frames` index ([D24](decisions.md#d24-states-figures-and-their-numbers)) |

  `Place` exists because of built sequences: text could have located a static
  problem by its span alone, and a built one has none.
- **Mistakes only Haskell can make.** No parser produces the values below.
  `checkSequence` refuses each, naming the step, so a checked sequence always prints
  as text that parses. `ParameterOutOfRange` is already in 02's catalogue;
  [D20](decisions.md#d20-errors) adds the other four as `StaticProblem`s
  (**SKETCH** names):

  | Value | Why | Refused as |
  | --- | --- | --- |
  | `Name "two words"` | not a name token | `NotANameToken` |
  | `Name "north-west"` | a [reserved word](04-prd-sequence-source-and-cli.md#reserved-words); reserved words are never names, compared ignoring case ([D12](decisions.md#d12-the-text-syntax)) | `ReservedWordAsName` |
  | `TopLayers 0` | selects no layer | `LayerCountNotPositive` |
  | `Degrees (-90)` in a `Fold` | a fold's angle is unsigned; the text allows a `-` only in `(u, v)`, `model` pairs, pose angles and settle `except` angles ([D12](decisions.md#d12-the-text-syntax), [R-04-2](04-prd-sequence-source-and-cli.md#requirements)) | `SignNotAllowed` |
  | a negative driving parameter | outside the macro's range | `ParameterOutOfRange` ([02 §12](02-language-semantics.md#12-refusal-catalogue)) |

### Running from GHCi

From M2. **SKETCH:** `defaultRunSettings` and `noFileHeader` are placeholder names.

```text
$ stack ghci senbazuru:lib
ghci> :set -XOverloadedStrings
ghci> import qualified Data.Map.Strict as Map
ghci> import qualified Data.Text.IO as T
ghci> Right file <- loadFoldFile "examples/blintz-base.fold"
ghci> let sheets = Map.fromList [("examples/blintz-base.fold", keyFrame file)]
ghci> let run = checkSequence blintz >>= runSequence defaultBudget defaultRunSettings sheets . elaborate
ghci> either (T.putStrLn . explain) (print . length . runRecords) run
ghci> let written = run >>= writeSequence noFileHeader
ghci> either (T.putStrLn . explain) (\f -> saveFoldFile "blintz.foldseq.fold" f >>= either (T.putStrLn . explain) pure) written
```

- **Types.** `run :: Either SequenceError Run`; `written :: Either SequenceError
  FoldFile`. `elaborate` expands shorthand ([glossary-additions][ga-code]). `Run` is
  defined in `Sequence.Record` and holds what a reader of a run needs, the start
  state, the records and each step's outcome, but not the runner's working state
  ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).
- **Five records expected.** The blintz should print 5, one move record per move.
  **UNVERIFIED** until the M2 runner exists; A-6 checks it.
- **Getting `blintz`.** Add its file with `:add`, or type it between `:{` and `:}`
  after `import Control.Monad (forM_)`, which Prelude does not export. Either works
  at this prompt, because the sketch names no constructor that `Fold.Types` also
  exports. Typing `Mountain` here means `Fold.Types`' assignment, a type error where
  a `Sense` belongs.
- **Why `:set` is explicit.** Stack's docs do not say whether the cabal file's
  default extensions reach the prompt (**UNVERIFIED**).
- **Existing functions:**
  - `loadFoldFile`, [`Load.hs:142`](../src/Senbazuru/Fold/Load.hs#L142);
  - `keyFrame`, [`Types.hs:128`](../src/Senbazuru/Fold/Types.hs#L128);
  - `defaultBudget`, [`Stacking.hs:184`](../src/Senbazuru/Origami/Stacking.hs#L184);
  - `saveFoldFile`, [`Load.hs:190`](../src/Senbazuru/Fold/Load.hs#L190), whose error
    has an `Explain` instance ([`:168`](../src/Senbazuru/Fold/Load.hs#L168)).

### Rejected alternatives

[D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders)
records the same rejections.

| Alternative | Why not |
| --- | --- |
| Shallow embedding: a sequence *is* a function over fold states | Cannot be printed, saved, statically checked or dry-run, and each new interpretation must be tupled in ([F] finding 11) |
| Free or operational monad, [defined above](#problem-and-evidence) | A file cannot hold the function to the rest, and a printer must invent a result to see past a bind. Its one extra power, steps that depend on results, is what a file cannot express ([F] finding 14) |
| Tagless final: programs as class-polymorphic functions | Reading a file needs a typechecker into an existential. Its extensibility is on the wrong axis: moves are added one reviewed constructor at a time ([F] finding 13) |
| GADT-indexed syntax tree | The parser would have to typecheck into it ([F] "Rejected alternatives") |
| `Ref` indexed with `DataKinds` | Adds an extension to every module for three kinds |
| One builder type for sequences and step bodies | A move outside a step and a step inside a step would compile, and the builder would have to drop or reorder one silently |
| Syntax constructors `Mountain`, `Valley` and `Above`, with only lowercase builders exported | `Sequence.Run` imports `Fold.Types` too, so the library itself would need qualified names at every use |
| `mtl` in the library stanza | `MonadState` does no design work here. megaparsec depends on mtl anyway ([F] "D. Parsing the text syntax", finding 18), so this is about signatures, not the dependency closure |
| Names the builder invents | Equality with a parsed source needs the author's names ([F] finding 17 sketches fresh ones) |

## Requirements

| # | Requirement | Checked by |
| --- | --- | --- |
| R-03-1 | `Sequence.Build` defines `newtype Build a` over `Control.Monad.Trans.State.Strict.State`, deriving only `Functor`, `Applicative` and `Monad`, and `sequenceOf :: Header -> Build () -> Sequence` | A-4; review |
| R-03-2 | Nothing in `Sequence.Build` takes or returns a `Frame`, `Folded`, `Surface` or measured `Double`; it imports only `Sequence.Syntax`, `base`, `text` and `transformers` | review of `grep '^import' src/Senbazuru/Sequence/Build.hs` |
| R-03-3 | `Ref :: Type -> Type` has an unexported constructor and index types `PointK`, `LineK`, `StepK`; the `common warnings` stanza gains no extension; the tree stores `Name`, never `Ref` | review; A-5 |
| R-03-4 | `step`, `step_`, `stepReturning`, `stepUncaptioned` and `stepUncaptioned_` each append one `Step` in call order, with the body's moves in call order; the first three store `Just` their caption, the last two `Nothing`; `step`'s `Ref StepK` holds its name | A-2, A-4, A-7 |
| R-03-5 | A step body has its own type, `Moves`, so a move outside a step or a step inside one is a compile error | review |
| R-03-6 | Every `Sequence.Syntax` constructor is buildable at M1, by a builder or `move`; each builder's defaults equal the parser's for an absent clause; `header t s a` equals, spans stripped, the header parsed from `foldseq 1`, `title`, `sheet` and optional `anchor` lines alone | A-2, A-7 |
| R-03-7 | No exported builder shares a Prelude name or is called `pattern`; `mountain`, `valley`, `behind`, `inFront :: Sense` and `above :: Point -> Point -> Relation` are exported; the `Sense` and `Relation` constructors are `ValleyFold`, `MountainFold` and `LayerAbove`, so no constructor `Sequence.Syntax` exports shares a name with one `Fold.Types` exports | A-5 |
| R-03-8 | Built values carry `NoSpan` everywhere; every error from one has `sourceLocation` and `excerpt` `Nothing` and names its place first: the step by index, and by name if any; the header; or the written state; `StaticRefused` carries a `Place` | A-3 |
| R-03-9 | `checkSequence` refuses each Haskell-only value in [Refusals from a built sequence](#refusals-from-a-built-sequence) with the problem named there (`NotANameToken`, `ReservedWordAsName`, `LayerCountNotPositive`, `SignNotAllowed`, `ParameterOutOfRange`), so a checked value prints as parseable text | A-1 |
| R-03-10 | Round trip on trees at M1, as [D12](decisions.md#d12-the-text-syntax) and [R-04-9](04-prd-sequence-source-and-cli.md#requirements) state it: `isRight (checkSequence s) ==> fmap stripSpans (parseSequence "gen" (prettySequence s)) == Right (canonical s)`; the Haskell blintz equals the parsed text blintz, and its printed form is a reviewed golden | A-1, A-2 |
| R-03-11 | At M2, `checkSequence`, `elaborate`, `runSequence` and `writeSequence` compose into `Either SequenceError FoldFile` with no I/O, given sheets keyed by the header's path text | A-6 |
| R-03-12 | The library stanza lists `transformers`, not `mtl`. GHC 9.6.7 ships transformers 0.6.1.0 and mtl 2.3.1: `ghc-pkg-9.6.7 --global field transformers version` and the same for `mtl`, run 2026-09-15 on Stack's GHC 9.6.7 | review of `senbazuru.cabal` |
| R-03-13 | `Sequence.Build`'s header says binds hand out names and why, loops print unrolled, the compiler checks only reference kinds (foldability is decided by running, [F] finding 23), and why the syntax constructors are `ValleyFold`, `MountainFold` and `LayerAbove` | review against AGENTS.md "Audience and tone" |
| R-03-14 | Every builder emits a canonical value: `canonical v == v` for its output; `letLine n (namedLine r)` emits `BindPoint (PointNamed …)` | A-7 |

## Acceptance criteria

All run in default CI; only A-6 folds paper. `stripSpans` sets every span to
`NoSpan`.

| # | Test | Turns red when |
| --- | --- | --- |
| A-1 | QuickCheck: [R-04-9](04-prd-sequence-source-and-cli.md#requirements)'s property over its generator extended with the Haskell-only values above, `isRight (checkSequence s) ==> fmap stripSpans (parseSequence "gen" (prettySequence s)) == Right (canonical s)`, with `checkCoverage` requiring those values to be generated; plus one example per Haskell-only value asserting its named refusal | the printer drops a caption or a `moving` seed; `checkSequence` accepts `Name "north-west"` or `TopLayers 0` |
| A-2 | `fmap stripSpans (parseSequence "blintz.foldseq" blintzText) == Right blintz`, plus a golden of `prettySequence blintz` via `goldenText` ([`Golden.hs:38`](../test/Test/Golden.hs#L38)) | `fold` defaults to `Degrees 180`; `header` defaults `hSide` unlike the parser; a loop caption changes; `sequenceOf` forgets to reverse |
| A-3 | a built sequence with `step "c1"` twice: `explain err` starts `step 2 (c1)`; `sourceLocation` and `excerpt` are `Nothing` | the builder invents a span; `StaticRefused` loses its `Place` |
| A-4 | property: `sequenceOf h (mapM_ (\c -> step_ c (turnOver LeftRight)) cs)` has captions `map Just cs` (a caption is `Maybe Text` because text may leave it out), one move each | a builder prepends, drops the last step, or merges bodies |
| A-5 | a test module importing `Prelude`, `Senbazuru.Fold.Types`, `Senbazuru.Sequence.Build` and `Senbazuru.Sequence.Syntax (Sense (..), Relation (..))` unqualified uses every builder, `ValleyFold`, `MountainFold` and `LayerAbove`, and also `Fold.Types`' own constructors in `[Mountain, Valley] :: [Assignment]` and `[Above] :: [Stacking]`, warning-free | a builder named `repeat`, `until` or `all` appears; a syntax constructor is named `Mountain`, `Valley` or `Above`, which makes those lines ambiguous |
| A-6 | M2: the GHCi composition on the blintz gives five move records and six `file_frames` entries: the starting state, then one end state per step, with no `sample` poses ([D24](decisions.md#d24-states-figures-and-their-numbers), [02 §11](02-language-semantics.md#11-written-frames)) | the runner needs I/O; a single-move step yields two records; the writer drops the starting state |
| A-7 | each row of [the vocabulary](#the-builder-vocabulary) equals the parse of its text column, spans stripped. LINE is `corner south-east to centre`; P is `corner south-east` after `moving` and `centre` after `mark`; K is `ExistingHingeFlat`; MOVE is `fold valley edge west to edge east`; `a` and `b` are steps defined earlier in the same source; A and B are `(1/4, 1/5)` and `(3/8, 5/9)`. A point row is wrapped as `anchor P`, a line row as `fold valley L`, and a move row as that move, each in a one-step source; the relation row is read from a header's `start folded { layers A above B }`. Also: every builder output `v` has `canonical v == v`; `stepUncaptioned_ (turnOver LeftRight)` equals the parse of `step { turn over left-right }` and has `stepCaption = Nothing`; `step_ ""` gives `Just ""` | a builder default drifts from the parser; `letLine` emits `BindLine (LineNamed …)`; `above` emits a constructor other than `LayerAbove`; an uncaptioned step gets `Just ""` |

## Dependencies

- **M0.** Glossary rows moved; #60 amended
  ([row 3](decisions.md#3-recorded-text-this-design-changes), written out in
  [01 §4.3](01-architecture.md#43-60)).
- **M1.** `Sequence.Syntax`, `Error`, `Build`, `Parse`, `Pretty`, `Check` and
  `Elaborate` land together ([§8](decisions.md#8-milestones)), since A-1 and A-2
  need the parser and printer. `transformers` joins the library stanza with
  megaparsec and parser-combinators ([04](04-prd-sequence-source-and-cli.md)).
  QuickCheck is already a test dependency
  ([`senbazuru.cabal:321`](../senbazuru.cabal#L321)).
- **M2.** `Sequence.Record` with `Run` and `writtenStates`, the runner and the
  writer ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)), for
  A-6 and GHCi.
- **M5.** Macro builders build syntax from M1, and run from M5.
- **M6.** A settle builder, typed so a step holds at most one settle
  ([07](07-prd-material-consumption.md)).
- **Issues.** Advances [#60](https://github.com/avalonalex/senbazuru/issues/60).
  [#97](https://github.com/avalonalex/senbazuru/issues/97) is the text half.
  [#63](https://github.com/avalonalex/senbazuru/issues/63) is related, not
  required: phantom types, but for units.

## Risks

| Risk | Mitigation |
| --- | --- |
| The front ends drift | A-1, A-2, A-7 in default CI, no geometry |
| "Typed" read as "checked": authors expect an impossible fold to be a compile error | R-03-13; foldability is decided by running ([F] finding 23) |
| Name clashes at the GHCi prompt | Syntax constructors `ValleyFold`, `MountainFold`, `LayerAbove`, and lowercase builders; A-5 |
| `stepReturning` goes unused | Drop it at M5 if no example from M2 to M5 needs it |

## Open questions for the owner

From the owner decisions in [decisions.md §9](decisions.md#9-owner-decisions), each
with a recommended default there;
[10](10-roadmap-risks-questions.md#6-owner-decisions) tracks them:

1. **File extension and "sequence source"** (decision 1; default `.foldseq`, first
   line `foldseq 1`). These fix the file names in A-2 and the module header.
2. **Blintz direction** (decision 8; default the recipe's `fold behind`). Both
   blintzes fold `mountain`, as the recipe does. The study's angle manifest
   (`study/fold-material/cases.json`) folds the corners up instead (+90°, then
   +175°). If the manifest is chosen, both switch to `fold in front` in one PR, and
   A-2 keeps them equal.
3. **Eighth turns** (decision 10; default trigonometry, with the platform bits in
   written coordinates stated). Should eighth turns stay a move
   (`rotate 1 Anticlockwise`), whose frames need trigonometry and so write
   platform-dependent bits into coordinates? Or should a header option start the
   square turned 45° as a diamond, leaving `rotate` with even k only, so frames stay
   exact?

The two questions this file raised earlier, a step body's own type and the
constructor names that clash with `Fold.Types`, are decided by
[C22](decisions.md#changes-since-draft-v2) and
[C23](decisions.md#changes-since-draft-v2).

## Research links

- [F]: "A. What the repository already commits to"; "B. Embedding styles"; "C.
  Builder ergonomics and prior art"; "D. Parsing the text syntax"; "E. Round-trips";
  "F. Static versus dynamic checking"; "Rejected alternatives".
- [D] "A. Constraints and decisions, each with a verdict — question (a)": A2, A7,
  A29, A30.
- [A1] "(c) Identifiers that do not survive, and the ones that do".

[F]: research/F-haskell-edsl-techniques.md
[D]: research/D-docs-issues-constraints.md
[A1]: research/A1-library-fold-solver.md
[ga-lang]: glossary-additions.md#the-sequence-language
[ga-run]: glossary-additions.md#running-a-sequence
[ga-ref]: glossary-additions.md#references
[ga-narrow]: glossary-additions.md#words-the-prds-narrow
[ga-origami]: glossary-additions.md#origami
[ga-macro]: glossary-additions.md#macro-moves
[ga-code]: glossary-additions.md#code-and-tests
[ga-fold]: glossary-additions.md#the-fold-format
