# 04 — The sequence source and the `run` verb

Written 2026-09-15 against `568dcb6`. This is feature 2 of the three requests
[00](00-overview.md) lists. It is requirements only: nothing is implemented, and
every grammar, type and message is **SKETCH** until the M1 parser compiles.

This file owns three things about a *sequence source*, the text an author writes
([glossary-additions](glossary-additions.md#the-sequence-language)):

- how it is spelled;
- how `senbazuru run` reads it and turns it into files;
- how a refusal is shown to the person holding the text.

What each spelling *means* is [02](02-language-semantics.md). The Haskell builder
that makes the same value is [03](03-prd-embedded-dsl.md). The decisions this file
rests on are in [the decision record](decisions.md), which wins wherever this file
and it disagree: the syntax is [D12](decisions.md#d12-the-text-syntax), the `run`
verb [D13](decisions.md#d13-the-run-verb-and-io), and errors
[D20](decisions.md#d20-errors). The clause beside each citation gives the reason.
Origami words link to [the glossary](../docs/glossary.md).

## Summary

- A sequence source is a UTF-8 file whose first line is `foldseq 1`. The extension
  `.foldseq` is a placeholder.
- Its *steps* are blocks in braces. A step is one figure on the page, holding one
  or more *moves* ([glossary-additions](glossary-additions.md#words-the-prds-narrow)).
  Every move sits inside a step.
- Paper is named on the unfolded sheet (`corner south-east`, `(3/4, 1/4)`), never
  by an id.
- `Sequence.Parse` uses megaparsec to turn the text into the same first-order
  `Sequence` that 03's builder makes (a data type with no functions inside, so it
  can be compared and printed: [deep embedding](glossary-additions.md#code-and-tests)).
  `Sequence.Pretty` prints any `Sequence` back in one canonical spelling, and
  parsing that output returns the value.
- `Fold.Load.readSequenceText` is the only reader of source bytes, so the
  [runner](glossary-additions.md#running-a-sequence) stays pure.
- `senbazuru run SOURCE` writes one of three outputs, chosen by the `-o`
  extension: a *sequence file* ([glossary-additions](glossary-additions.md#the-fold-format), `.fold`),
  a page of step figures like `render --steps` draws (`.svg`), or a
  [GLB](../docs/glossary.md#this-project) model (`.glb`).
- A refusal is one line from `explain`. The CLI adds `path:line:col` and an excerpt
  of the source with a caret under the mistake.

## Problem and evidence

| Today | Evidence |
| --- | --- |
| Nothing can write a sequence down. The one authoring verb takes one crease per call, as coordinates. | `crease --from X,Y --to X,Y` ([Cli.hs:258-283](../app/Senbazuru/Cli.hs#L258-L283)). [#97](https://github.com/avalonalex/senbazuru/issues/97) asks for a syntax "a person can write without a calculator". |
| Every verb reads its input as a crease pattern. A source given to `render` would be decoded as FOLD and fail as bad JSON (not run). | Every verb goes through `withFoldFile` ([Cli.hs:691-698](../app/Senbazuru/Cli.hs#L691-L698), [:800-804](../app/Senbazuru/Cli.hs#L800-L804)). Any unrecognised extension decodes as FOLD ([Load.hs:102-106](../src/Senbazuru/Fold/Load.hs#L102-L106)), pinned by [LoadSpec.hs:167-171](../test/Senbazuru/Fold/LoadSpec.hs#L167-L171). |
| The library has no parser. | [senbazuru.cabal:152-159](../senbazuru.cabal#L152-L159); the `.cp` reader splits words by hand ([C](research/C-renderers-cli-formats.md) "(e) Dependencies", finding 22). |
| The CLI is untested by design. The test suite's source directories are `test` and `study/fold-material`, not `app`, so nothing in `Cli.hs` can be tested, and the parser, path rules, flag rules and messages must live in the library. | [Cli.hs:5-8](../app/Senbazuru/Cli.hs#L5-L8); [senbazuru.cabal:193](../senbazuru.cabal#L193). |
| An error message is a lower-case fragment for after a colon. megaparsec's rendered errors span several lines. | [Explain.hs:62-69](../src/Senbazuru/Explain.hs#L62-L69); `errorBundlePretty` prints source context ([F](research/F-haskell-edsl-techniques.md) "D. Parsing the text syntax", finding 18). |
| One refusal already needs a path and a number around one message, and gets two wordings. `render --steps` takes `StepError` apart in `Cli.hs` to build "cannot render frame N of PATH: …", so the same failure reads one way there and another through `explain`. | [Steps.hs:64-78](../src/Senbazuru/Render/Steps.hs#L64-L78), [Cli.hs:855-863](../app/Senbazuru/Cli.hs#L855-L863). |
| Only `Fold.Load` does I/O, and a sequence names a second file: its sheet. | [architecture.md:155-158](../docs/architecture.md). |

## Goals

1. The quarter fold, blintz, bird base and a crane wing can be written with no ids
   and no decimals a book would not print ([Examples](#example-sources-checked-against-their-fixtures)).
2. Text and Haskell produce one `Sequence` type, and printing and parsing round-trip.
3. Every mistake is reported at a line and column, with the line itself and a caret.
4. One verb writes a sequence file, a page of step figures or a GLB. Existing verbs
   stay byte-identical.
5. Only `Fold.Load` touches the filesystem.

## Non-goals

- Semantics ([02](02-language-semantics.md)); the words inside `settle` and `material`
  blocks ([07](07-prd-material-consumption.md)).
- Keeping comments or layout. `pretty . parse` is not the identity on text
  ([F](research/F-haskell-edsl-techniques.md) "E. Round-trips", finding 21).
- A JSON encoding of the syntax tree, which may come later
  ([D12](decisions.md#d12-the-text-syntax)). Reading other tools' id-based
  programs, since adding a crease renumbers ids ([D18](decisions.md#d18-non-goals)).
- `--until`, `--landmarks`, watch mode: none is decided.
- Atomic writes ([#58](https://github.com/avalonalex/senbazuru/issues/58) item 4),
  which need `directory` in the library ([D13](decisions.md#d13-the-run-verb-and-io)).
- Copying the sheet file's top-level keys into the output (until
  [#73](https://github.com/avalonalex/senbazuru/issues/73)).
- Writing an `expect refused` outcome into the sequence file; `--report` prints it
  instead ([D18](decisions.md#d18-non-goals)).

## Users and scenarios

| Who | Scenario |
| --- | --- |
| A folder | Writes `blintz.foldseq`, runs `run blintz.foldseq --check`, fixes the line the caret points at, runs `-o blintz.svg`. |
| A Haskell test author | Builds a `Sequence` with 03's builder and pins `prettySequence` in a golden. |
| A contributor adding a move | Adds a constructor, a production, a [mapping row](#from-spelling-to-syntax-tree), a generator case and a reserved word. The round-trip property stays red until printer and parser agree. |
| The material study (M6) | Reads sources through the same `readSequenceText` and `parseSequence` ([07](07-prd-material-consumption.md)). |

## Requirements

Each requirement points at the design section that details it.

| # | Requirement |
| --- | --- |
| R-04-1 | The source's first line is `foldseq 1`; nothing comes before it, not a blank line or a comment. Any other version is refused, naming it. Input starting with `{` is refused with the hint `LooksLikeFold`, whose message says the text looks like a FOLD file and names no command (R-04-13); `refusalLines` adds the line naming the verbs that read FOLD ([The `run` verb](#the-run-verb)). |
| R-04-2 | Tokens follow [Lexical rules](#lexical-rules). Numbers are exact `Rational`s. An angle carries `°` or `deg`. `0..1/32` is three tokens. A `-` sign is allowed only in `(u, v)` coordinates, `model [...]` pairs, and the angles of `pose { … }` and settle's `except { … }`. |
| R-04-3 | The parser accepts exactly [the grammar](#grammar) and resolves ambiguities as [the table](#how-the-ambiguities-are-resolved) says. Braces delimit every block. A newline or `;` separates statements. Indentation means nothing. |
| R-04-4 | No name equals a [reserved word](#reserved-words), ignoring case. A *view word* (`left`, `right`, `top`, `bottom`, `front`, `behind`: words for what the reader sees, reserved so that paper is named by [sheet compass](glossary-additions.md#references)) where a material feature is expected gets the compass spelling as a hint. A reserved future move gets a `not modelled "…"` hint. A Haskell-built name the parser would read differently is refused by `checkSequence` ([R-03-9](03-prd-embedded-dsl.md#requirements)). |
| R-04-5 | Header lines come after `foldseq 1` and before the first step, in any order, at most once each; a duplicate is refused naming both lines. `sheet` is required. `closing` follows the last step and is stored as `hClosing`. A header holds no move ([D12](decisions.md#d12-the-text-syntax)). |
| R-04-6 | `sheet` and `checkpoint` paths are relative to the source's directory, and absolute paths are kept. The pure function `Sequence.Syntax.sourceFiles` implements this. |
| R-04-7 | Every spelling maps to the constructor in [the mapping table](#from-spelling-to-syntax-tree); aliases map to their canonical constructor. A bare name whose kind the text cannot fix parses to the [canonical](#canonical-form-and-the-printer) point spelling, and `Sequence.Check` assigns its kind. |
| R-04-8 | `prettySequence :: Sequence -> Text` is total and prints the canonical spelling. |
| R-04-9 | A QuickCheck property: `isRight (checkSequence s) ==> fmap stripSpans (parseSequence "gen" (prettySequence s)) == Right (canonical s)`. `stripSpans` removes *spans* (source positions, [glossary-additions](glossary-additions.md#code-and-tests)). `canonical` is idempotent, and parser and builder output are canonical. The generator covers every constructor, captions, names, signed `Rational`s where allowed and nested blocks, enforced by `checkCoverage`. This file owns the property, as [D12](decisions.md#d12-the-text-syntax) states it; 03's R-03-10 and A-1 run the same property over a generator extended with Haskell-only values. `canonical` and `stripSpans` live in `Sequence.Syntax` ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)). |
| R-04-10 | `Sequence.Parse` exports `reservedWords`. A property checks that every word the printer emits outside a string is either reserved or a name used in `s`. |
| R-04-11 | The grammar and reserved words are recorded in `Sequence.Parse`'s module header. `docs/usage.md` documents `run` and every flag. |
| R-04-12 | `ParseProblem`, defined in `Sequence.Error`, stores a span, what was found (a whole word, a character or end of input), the expected labels and an optional `Hint`, all as data ([Error display](#error-display)). |
| R-04-13 | `explain` for `ParseProblem` and `SequenceError` is one lower-case line, with no path, line, column, full stop or command-line word such as a verb or flag ([D20](decisions.md#d20-errors)). |
| R-04-14 | `Sequence.Error.sourceLocation :: SequenceError -> Maybe Text` gives `path:line:col`, 1-based, with columns in code points and a tab counting as one. It gives `Nothing` for `NoSpan`. |
| R-04-15 | `Sequence.Error.excerpt :: Text -> SequenceError -> Maybe Text` is the only multi-line text. Its caret line copies each tab of the source line so the caret stays aligned. |
| R-04-16 | The CLI prints `senbazuru: PATH:LINE:COL: MESSAGE` and then the excerpt. Without a location it prints `senbazuru: MESSAGE`, as [D20](decisions.md#d20-errors) has it. A sheet that fails to load is prefixed with its `sheet` line's location. No output line names one path twice. An unclosed block is located at its `{`. |
| R-04-17 | `Fold.Load.readSequenceText :: FilePath -> IO (Either LoadError Text)` decodes strict UTF-8, strips a byte-order mark and changes nothing else. It imports no `Sequence` module. |
| R-04-18 | `decodeFile` refuses a `.foldseq` extension, compared after lowercasing, with a new `LoadError` carrying the path. Its `explain` says the file is a sequence source, not FOLD, and names no command. `app/`'s `withFoldFile` appends "use `senbazuru run PATH`" when it sees that constructor ([D13](decisions.md#d13-the-run-verb-and-io)). Every other extension behaves as today. |
| R-04-19 | The CLI loads each distinct `sheet` and `checkpoint` path with `loadFile` before running. It passes the runner a `Map FilePath Frame` from each path *as written* to that file's *key frame*, its top-level frame ([glossary-additions](glossary-additions.md#the-fold-format)). |
| R-04-20 | Encoding a frame with a non-finite number is refused, naming the element ([#58](https://github.com/avalonalex/senbazuru/issues/58) item 3), by M2. |
| R-04-21 | `Command` gains `RunSource RunOptions`. `run` never uses `withFoldFile`. Other verbs' `--help` text and outputs are unchanged. |
| R-04-22 | Output follows the lowercased `-o` extension: `.fold`, `.svg` or `.glb`. With no `-o`, the sequence file goes to stdout. Any other extension is refused before reading any file. |
| R-04-23 | `--check` parses and checks, opens no sheet, prints one summary line and runs no geometry. It refuses `-o`, `--report`, `--layer-budget`, `--frame` and the page flags. |
| R-04-24 | `--report` writes `Sequence.Record.renderRunReport :: Run -> [Text]` to stderr under a heading naming the source, as `check` formats its report ([Cli.hs:962-966](../app/Senbazuru/Cli.hs#L962-L966)). It prints each `expect refused` outcome too, which has no record and is kept on its step in the `Run` ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)). |
| R-04-25 | `--layer-budget N` reaches `runSequence` and the renderer for every geometric output. |
| R-04-26 | `--frame N` goes only with `.glb`. It counts as every verb does, frame 0 being the key frame, so `--frame N` selects state N − 1, which is `file_frames[N − 1]` ([D13](decisions.md#d13-the-run-verb-and-io), [D24](decisions.md#d24-states-figures-and-their-numbers)); `bird-base-sequence.fold`'s states are read the same way ([usage.md:1017-1018](../docs/usage.md)). With no `--frame` it selects the last state. `0` and values past the state count are refused, naming the count. |
| R-04-27 | `--columns`, `--view`, `--width` and `--height` go only with `.svg`, with `render`'s defaults. `--all-layers` goes only with `.glb`. `--author` and `--description` go only with `.fold`, because they fill `file_author` and `file_description`, which only the sequence file has ([D4](decisions.md#d4-written-frames-follow-the-state-rule)). |
| R-04-28 | Any refusal exits nonzero. At a `not modelled` move, `runSequence` returns `Right` a `Run` whose `runStop` names the step and which holds every record and state before it. `run` writes those states, then prints `runRefusal`'s `StepRefused … NotModelled` and exits nonzero, so the work up to the gap is kept ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)). Every other refusal returns no partial run. |
| R-04-29 | The library adds megaparsec, parser-combinators and transformers, and the executable adds `containers` and `filepath` ([bounds](#dependencies-in-the-cabal-file)). |
| R-04-30 | The flag rules of R-04-22, R-04-23, R-04-26 and R-04-27, and the output lines of R-04-16, are pure functions in `Sequence.RunPlan` that the CLI only calls. `Sequence.RunPlan` holds its own option types and imports no `Render.*` module ([The `run` verb](#the-run-verb), [D13](decisions.md#d13-the-run-verb-and-io)). |

## Design

### A first source, read line by line

The quarter fold folds a square in half, then in half again. Its fixture,
`examples/quarter-fold-steps.fold`, is the acceptance test that #60 and #97 name.
This is the source the first quarter-fold test uses
([D16](decisions.md#d16-testing-and-acceptance),
[09 §2.2](09-testing-and-acceptance.md#22-test-1-folding-equivalence-m2)):

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

- **`sheet "examples/…"`** is relative to the source's own directory. The examples
  here are saved in the repository root. Saved inside `examples/`, the line would
  read `sheet "quarter-fold-steps.fold"`.
- **Frame numbers below are the fixture's, and a written file's differ by one.**
  `quarter-fold-steps.fold` keeps its flat start in its key frame, so its frame 1,
  `file_frames[0]`, is the state after `half`. A sequence file that `run` writes
  has a key frame holding only metadata, so there the state after `half` is state
  1, `file_frames[1]`, which `--frame 2` selects
  ([D24](decisions.md#d24-states-figures-and-their-numbers)). Test 1 compares a
  written `file_frames[k]` with the fixture's frame k.
- **`anchor (3/4, 1/4)`** names the paper that stays still while folds move the rest
  ([glossary-additions](glossary-additions.md#running-a-sequence)). The numbers are
  *sheet lengths*: the sheet's larger side is 1 and its south-west corner is (0, 0)
  ([glossary-additions](glossary-additions.md#references)). The point lies in face
  `[8,4,1,5]`. A *face* is one flat region between creases, listed by its corner
  vertices, and these four vertices never move.
- **`edge west to edge east`** is an *alignment fold*, a fold named by what it
  brings together. Here that line is x = 1/2, which is the fixture's existing edges
  8 (v8→v4) and 10 (v8→v6), so no crease is made. Frame 1 turns both edges to −180
  and moves vertices 0, 3 and 7, the west half.
- **`behind`** is an alias of `mountain`, a fold that sends paper away from the
  reader. `in front` is an alias of `valley`, towards the reader
  ([glossary](../docs/glossary.md#origami)).

**The next fact looks like a typo and is not.** Step 2 is a valley fold along
y = 1/2, the fixture's edges 9 and 11, yet frame 2 writes edge 9 as +180 and
**edge 11 as −180**. A FOLD [fold angle](../docs/glossary.md#origami) is negative
for a mountain, judged from the paper's own top side: the side that faces +z in
the crease pattern ([Folding.hs:39-48](../src/Senbazuru/Origami/Folding.hs#L39-L48)).
Both faces beside edge 11, `[8,6,3,7]` and `[8,7,0,4]`, are in the west half and
have lain upside down since step 1. So a fold the reader sees as a valley is, from
those faces' own top side, a mountain, and is written −180. Frame 2 moves vertices
2, 3 and 6.

Checked with the command below, which printed the faces, then edges 8–11 as
`[[8,4],[8,5],[8,6],[8,7]]` assigned `M V M M`, then `1 [-180, 0, -180, 0] [0, 3, 7]`
and `2 [-180, 180, -180, -180] [2, 3, 6]`:

```sh
python3 -c 'import json; f=json.load(open("examples/quarter-fold-steps.fold")); fr=[f]+f["file_frames"]
print(f["faces_vertices"], f["edges_vertices"][8:], f["edges_assignment"][8:])
for i in (1, 2): print(i, fr[i]["edges_foldAngle"][8:], [v for v in range(9) if fr[i]["vertices_coords"][v] != fr[i-1]["vertices_coords"][v]])'
```

Whether the runner reproduces those frames is
[D16](decisions.md#d16-testing-and-acceptance)'s test 1, at M2
([09 §2.2](09-testing-and-acceptance.md#22-test-1-folding-equivalence-m2)).

### Lexical rules

The Token column gives the name the [grammar](#grammar) uses.

| Token | Item | Rule |
| --- | --- | --- |
| — | Comment | `#` to end of line, outside strings. Not kept. |
| `SEP`, `SEPS` | Separator | Newline or `;`; `SEPS` is one or more. Blank lines are ignored. Inside `( )` and `[ ]` a newline is whitespace, so long constructions can wrap. |
| `NAME`, keywords | Word | A letter, then letters, digits, `-` and `_`, read as far as possible. A word on the reserved list is a keyword, quoted in the grammar, so `north-west` and `rabbit-ear` are one token each. Any other word is a `NAME`: `first-petal` is a name although `first` is reserved. |
| `KIND` | Refusal kind | The kind in `expect refused KIND` is a word starting upper-case. Check accepts the kinds in [02's catalogue](02-language-semantics.md#12-refusal-catalogue), whose names `Sequence.Error` holds ([D20](decisions.md#d20-errors)). |
| `STRING` | String | `"…"` on one line. Escapes are `\"`, `\\`, `\n`, `\t`, and `\u{…}` for any other character below U+0020, so the printer can write any caption a Haskell `Text` holds. |
| `INTEGER` | Whole number | Digits only, with no point and no slash: `foldseq 1`, `top 2 layers`, `refine side moving 3`. |
| `NUMBER` | Number | `175`, `0.58` (digits on both sides of the point) or `29/50`. All are exact, so `0.58` is `29/50`. `n/0` is a parse error (hint `ZeroDenominator`), because no `Rational` can hold it ([D12](decisions.md#d12-the-text-syntax)). |
| `EIGHTHS`, `QUARTERS` | Turn | After `rotate`, an `INTEGER` then `/8`; after `turned`, an `INTEGER` then `/4`. The denominator is read as typed and not reduced, so `2/8` is k = 2, and `rotate 1/4 turn` is a parse error asking for eighths. A k outside 1–7 (or 1–3) parses, and Check refuses it as `NotEighths` (`NotQuarters`). |
| `RANGE` | Range | `NUMBER` `..` optional `NUMBER`: `0..1/32`, `7/32..`. An upper bound follows `..` with no space, so `7/32.. 3` is an open range and then the number 3 ([why](#how-the-ambiguities-are-resolved)). |
| `SIGNED_NUMBER`, `SIGNED_ANGLE` | Sign | An optional `-` directly before a `NUMBER` or `ANGLE`. Only `(u, v)`, `model [...]` pairs, `pose { … }` and settle's `except { … }` use them. A `-` before a number anywhere else is refused (hint `StraySign`). |
| `ANGLE` | Angle | A `NUMBER` followed at once by `°` (U+00B0) or `deg`. A bare `90` is refused with "write 90°". |
| `LENGTH` | Length | A `NUMBER` followed at once by `mm`, `cm`, `m` or `in`. Only `material` blocks use lengths, because only the material study needs physical size ([D14](decisions.md#d14-material-consumption)). |

**This looks like a malformed decimal and is not: `0..1/32`.** It is the range from
0 to 1/32 sheet lengths. A decimal needs a digit after its point, so the number
stops at `0` and `..` comes next. A lexer test pins this.

Two characters look like `°` on a Mac keyboard: `º` (U+00BA, ordinal indicator)
and `˚` (U+02DA, ring above). Each is refused with a message naming both code
points.

### Grammar

In the grammar, a space between items means sequence and `|` means choice. `?`
marks something optional, `*` repeats zero or more times, `+` one or more. `#`
starts a comment. Quoted words are keywords or punctuation; upper-case names are
tokens from the lexical table's Token column; lower-case names are productions. The
comments `O1`–`O7` name the Huzita–Hatori operations, the standard ways of naming a
fold line ([glossary-additions](glossary-additions.md#references)).

```ebnf
# SKETCH: foldseq 1
source      = "foldseq" INTEGER (SEPS header)* (SEPS step)* (SEPS "closing" STRING)? SEP* ;
block(x)    = "{" SEP* (x (SEPS x)*)? SEP* "}" ;

header      = "title" STRING | "sheet" ("square" | STRING) | "anchor" point
            | ("coloured" | "white") "side" "up"
            | "start" "folded" stackingblock | "material" block(materialitem) ;
stackingblock = "{" SEP* "stacking" "first" SEP* "}"                        # alone in its block
            | block("layers" point "above" point) ;

step        = "step" NAME? STRING? "{" SEP* (move (SEPS move)* (SEPS settle)? | settle)? SEP* "}" ;
move        = fold | precrease | unfold | turnover | rotate | anchormove | mark | let
            | macro | continue | together | pose | repeat | checkpoint | notmodelled | expect ;
fold        = "fold" sense ANGLE? line layers? seed? ;
precrease   = ("pre-crease" | "precrease" | "fold" "and" "unfold") sense line layers? seed? ;
sense       = "valley" | "mountain" | "in" "front" | "behind" ;
layers      = "all" "layers" | "top" "layer" | "top" INTEGER "layers" | "top" "flap" ;
seed        = "moving" point | "flap" "containing" point ;
unfold      = "unfold" NAME+ ;
turnover    = "turn" "over" ("left-right" | "top-bottom") ;
rotate      = "rotate" EIGHTHS "turn" ("clockwise" | "anticlockwise") ;
anchormove  = "anchor" point ;
mark        = "mark" NAME "=" point ("in" "face" "containing" point)? ;
let         = "let" NAME "=" (alignment | simpleline | point) ;
macro       = ("collapse" "at" point ("keeping" segment "flat")? | "rabbit-ear" "at" point
              | "petal" ("tip" point | "top" "flap")) "until" ANGLE ("sample" ANGLE+)? ;
continue    = "continue" NAME "until" ANGLE ;
together    = "together" block(move) ;
pose        = "pose" block("crease" segment "at" SIGNED_ANGLE) ;
repeat      = "repeat" NAME (".." NAME)? ("mirrored" "across" segment | "turned" QUARTERS "about" point)? ;
checkpoint  = "checkpoint" STRING stackingblock ;
notmodelled = "not" "modelled" STRING ;
expect      = "expect" "refused" KIND "{" SEP* move SEP* "}" ;

point       = "corner" cornerword | "centre" | "(" SIGNED_NUMBER "," SIGNED_NUMBER ")"   # sheet lengths
            | "midpoint" "of" (segment | "edge" compassword) | "fraction" NUMBER "along" segment
            | "meet" simpleline simpleline | "end" "of" "crease" "of" NAME "nearest" point | NAME ;
segment     = "[" point "," point "]" ;
cornerword  = "south-west" | "south-east" | "north-east" | "north-west" ;
compassword = "north" | "east" | "south" | "west" ;
line        = alignment | simpleline ;
simpleline  = "edge" compassword | segment                                 # O1
            | "perpendicular" "to" simpleline "through" point              # O4
            | "crease" segment | "hinge" "of" NAME | "crease" "of" NAME
            | "model" "[" pair "," pair "]" | "(" line ")" | NAME ;
pair        = "(" SIGNED_NUMBER "," SIGNED_NUMBER ")" ;                     # model units
alignment   = point "to" point                                             # O2
            | point "to" simpleline                                        # P to L
            | point "to" simpleline "through" point nearest?               # O5
            | point "to" simpleline "and" point "to" simpleline nearest?   # O6
            | point "to" simpleline "perpendicular" "to" simpleline        # O7
            | simpleline "to" simpleline nearest? ;                        # O3
nearest     = "nearest" point ;

# 07 owns these words; these productions parse the crane example below.
# Until M6 the parser refuses a settle or material block as not yet supported.
settle       = "settle" block(settleitem) ;
settleitem   = "refine" region INTEGER | "hold" region ("at" target)? | "grip" region target
             | "rest" "at" ("before" | "after" | "rigid-pose" NUMBER)
               ("except" block(creaseline "at" SIGNED_ANGLE))? ;
creaseline   = "crease" segment | "hinge" "of" NAME | "crease" "of" NAME ;   # D14 CreaseLine
sideword     = "stationary" | "moving" ;
region       = regionatom (("union" | "minus") regionatom)* ;               # left to right
regionatom   = "side" sideword | "across-hinge" sideword | "closed" regionatom
             | "band" sideword RANGE | "material-band" RANGE | "crease-line" segment
             | "hinge" "of" NAME | "layer" ("upper" | "lower") "of" regionatom | "(" region ")" ;
target       = "rigid-pose" NUMBER | "arc-grip" ANGLE ANGLE ;
materialitem = "size" LENGTH | "thickness" LENGTH | "stiffness" NAME | "rest" NAME ;
```

The grammar says what parses. Which move is allowed in which state is
[02](02-language-semantics.md)'s. Three rules of
[D12](decisions.md#d12-the-text-syntax) are easy to miss in the EBNF:

- **No move outside a step.** `source` takes header lines and then steps, so a
  `rotate` or an `expect refused` at the top level does not parse. A sheet that
  starts as a diamond says so in a first step,
  `step { rotate 1/8 turn anticlockwise }` (owner decision 10 may add a header
  option instead).
- **An empty step parses, and Check refuses it.** A step whose only moves are
  `let`, or that has none, is refused as `EmptyStep`
  ([D24](decisions.md#d24-states-figures-and-their-numbers)): it would write a
  state identical to the one before it.
- **`refine` takes a region, not a side.** `refine side moving 3` refines the
  moving side at level 3. A bare side could not say `CraneSpread`'s second
  refinement, `side moving union across-hinge stationary`
  ([D14](decisions.md#d14-material-consumption),
  [07's control table](07-prd-material-consumption.md#every-existing-crane-control-re-expressed)).
  The count after a region is unambiguous except after an open range, which
  [the next table](#how-the-ambiguities-are-resolved) settles.

### How the ambiguities are resolved

Rows marked **Refinement** add to `Sequence.Syntax`.
[D12](decisions.md#d12-the-text-syntax) adopts all three and 03's builders emit
them; like every type here they stay **SKETCH** until M1 compiles. `Located a` is a
value paired with its `Span`.

| Where | Resolution |
| --- | --- |
| **`to`**, which O2, O3, O5, O6, O7 and "P to L" all use | `to` appears only in alignments (macros say `until`, poses say `at`), so a `to` always starts an alignment's second operand. The word after the second operand decides: `through` means O5, `and` O6, `perpendicular` O7. `nearest` may end O3, O5 or O6. Among the forms with no keyword after the second operand (O2, P to L, O3), `nearest` marks O3, and O2 or P to L followed by `nearest` is refused. With no such word, the two operands' kinds decide. |
| **`line to line`** would be left-recursive | An alignment starts with an operand, which is a point or a simple line, never with an alignment. Nesting an alignment therefore needs parentheses, as in `perpendicular to (corner south-west to centre) through centre`. The printer adds parentheses exactly there. |
| **A name next to `to`**, where the parser cannot know whether it is a point or a line | It parses to the canonical point spelling, and Check assigns the kind. A line followed by `to` and then a point is refused. |
| **`(`**, a coordinate or a parenthesised line | A number or `-` after `(` makes a coordinate, because no line starts with a number. |
| **`fold and unfold`** | `and` is not a sense, so one token decides. It takes no angle, because `FoldAndUnfold` has no field for one. |
| **A step named like a keyword**, such as `step front` or `step collapse` | Refused: reserved words are never names, even where only a name could appear. So the bird example's steps are `square-base`, `first-petal` and `second-petal`. |
| **`closing`** | Written after the last step, the order in which the page draws it, though it is stored in `Header` as `hClosing`. |
| **`expect refused`** | A `Move`, written inside a step before the fold it contrasts with, so both run against one state. It produces no move record and no state; its outcome is kept on its step in the `Run`, and `--report` prints it ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)). |
| **`midpoint of edge north`**: `MidpointOf Point Point` needs two points, and an edge is not one | **Refinement:** `MidpointOfEdge Compass`. `fraction r along edge S` is refused, because nothing says which end r counts from. |
| **`checkpoint … { stacking first }`**: a `Checkpoint` holding `[Relation]` cannot say it | **Refinement:** `data StackingSpec = Relations [Relation] \| StackingFirst`, used by both `StartFolded StackingSpec` and `Checkpoint FilePath StackingSpec`. `stacking first` stands alone in its block, so no value mixes the two. |
| **A step with no caption** | Allowed: `stepCaption :: Maybe Text`, and the printer leaves it out. |
| **A refusal in a header field or inside `together`**, which would otherwise be located at the whole step or nowhere | **Refinement:** the header fields that can be refused (`sheet`, `anchor`, `start`, `material`) and the members of `together` become `Located`, so the caret points at their own line. |
| **`refine band moving 7/32.. 3`**, where an open range could take the count as its upper bound | An upper bound follows `..` with no space. So `7/32.. 3` is the open range from 7/32 and then the count 3, and `7/32..3` is a closed range with no count after it, refused as a missing whole number. |

### Canonical form and the printer

Most spellings have exactly one tree. A bare name beside `to` is the exception:

```text
let a = corner south-west
let b = edge north
fold valley a to b
```

- **Parsing.** The parser reads `a to b` as `Onto (PointNamed "a") (PointNamed "b")`.
  `Sequence.Check` sees that `b` names a line and treats the move as "P to L".
- **Building.** A Haskell author who builds `PointToLine (PointNamed "a")
  (LineNamed "b")` prints the same text.
- **Comparing.** `canonical` rewrites the builder's value to the parser's, so the two
  compare equal.

| Non-canonical | `canonical` gives |
| --- | --- |
| `PointToLine p (LineNamed b)` | `Onto p (PointNamed b)` |
| `LineOnto (LineNamed a) (LineNamed b) Nothing` | `Onto (PointNamed a) (PointNamed b)` |
| `LineOnto (LineNamed a) l Nothing`, with `l` not a bare name | `PointToLine (PointNamed a) l` |
| `Let n (BindLine (LineNamed b))` | `Let n (BindPoint (PointNamed b))` |

A `nearest` clause fixes O3, so `LineOnto … (Just p)` is already canonical. 03's
builder emits canonical values ([D12](decisions.md#d12-the-text-syntax)).

The printer:

- **Order.** Header lines come in the order `title`, `sheet`, `anchor`,
  `white side up`, `start folded`, `material`. The printer leaves out exactly what the
  parser defaults: no anchor, the coloured side up, a flat start, default layers, no
  seed, no `nearest`, an empty `sample`, no angle for `ToFlat` (`Degrees 180` prints
  `180°`), no step name and no caption.
- **Layout.** A blank line before each step and before `closing`. One statement per
  line, two spaces of indent per block. `settle` comes last in its step.
- **Aliases** print canonically: `in front` as `valley`, `behind` as `mountain`,
  `precrease` and `fold and unfold` as `pre-crease`, `deg` as `°`,
  `flap containing P` as `moving P`, `top 1 layers` as `top layer`.
- **Numbers** print as an integer or as `n/d` in lowest terms, never as a decimal.
  A typed `0.58` prints as `29/50`.
- **`rotate 2/8 turn` looks unreduced and is intended.** `Rotate` stores k eighths
  and `TurnedQuarters` k quarters, and the printer writes k over its own
  denominator (`2/8`, `2/4`). These are the only numbers not printed in lowest
  terms, because the parser reads that denominator as typed.
- **Strings** escape `"`, `\`, newline, tab and the other control characters.
  Comments are gone.

The quarter fold, printed; this is the first pretty golden:

```text
foldseq 1
title "A square folded into quarters"
sheet "examples/quarter-fold-steps.fold"
anchor (3/4, 1/4)

step half "Fold the left half behind, onto the right." {
  fold mountain edge west to edge east
}

step quarter "Fold the top half down in front, onto the bottom." {
  fold valley edge north to edge south
}

closing "Folded into quarters."
```

### Reserved words

| Group | Words |
| --- | --- |
| Header | `foldseq` `title` `sheet` `square` `anchor` `coloured` `white` `side` `up` `start` `folded` `layers` `above` `stacking` `first` `material` `closing` |
| Structure | `step` `together` `pose` `settle` `checkpoint` `not` `modelled` `expect` `refused` `repeat` `mirrored` `across` `turned` `about` `mark` `let` |
| Folds | `fold` `and` `unfold` `pre-crease` `precrease` `valley` `mountain` `in` `front` `behind` `all` `top` `layer` `flap` `containing` `moving` `face` |
| Presentation | `turn` `over` `left-right` `top-bottom` `rotate` `clockwise` `anticlockwise` |
| References | `corner` `south-west` `south-east` `north-east` `north-west` `edge` `north` `east` `south` `west` `centre` `midpoint` `of` `fraction` `along` `meet` `end` `crease` `nearest` `to` `perpendicular` `through` `hinge` `model` |
| Macro-moves | `collapse` `at` `keeping` `flat` `until` `rabbit-ear` `petal` `tip` `sample` `continue` |
| Settle, material ([07](07-prd-material-consumption.md)) | `refine` `hold` `grip` `stationary` `closed` `band` `material-band` `across-hinge` `crease-line` `upper` `lower` `union` `minus` `rigid-pose` `arc-grip` `rest` `except` `before` `after` `stiffness` `size` `thickness` |
| View words ([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)), for what the reader sees | `left` `right` `bottom`, with `top` `front` `behind` above |
| Future moves ([D9](decisions.md#d9-macro-moves-as-named-angle-relations)) | `squash` `sink` `swivel` `crimp` `pleat` `reverse` `inside-reverse` `outside-reverse` |
| Hint only | `center` `colored` `counterclockwise` `counter-clockwise` `anti-clockwise` |

Future move words are reserved now, so later macros
([D9](decisions.md#d9-macro-moves-as-named-angle-relations)) cannot break a source
that used one as a name. A word built from view words, such as `top-left`, is
refused where a corner or edge is expected, with the compass spelling in the
message.

### From spelling to syntax tree

This table is the record of `Sequence.Syntax`'s constructor names, including the
refinements above. **`ValleyFold`, `MountainFold` and `LayerAbove` are not
stuttering.** `Fold.Types` already has constructors `Mountain` and `Valley`
([Types.hs:302-304](../src/Senbazuru/Fold/Types.hs#L302-L304)) and `Above`
([:334](../src/Senbazuru/Fold/Types.hs#L334)). `Sequence.Run` imports both modules,
and GHC does not choose a constructor by its type, so the shorter names would force
qualified names inside the library itself
([D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders)).

| Spelling | Constructor |
| --- | --- |
| `title "T"` · `closing "T"` | `hTitle = Just "T"` · `hClosing = Just "T"` |
| `sheet square` · `sheet "p"` | `hSheet = UnitSquare` · `SheetFile "p"` |
| `anchor P` in the header · in a step | `hAnchor = Just P` · `Anchor P` |
| `coloured side up` · `white side up` | `hSide = ColouredUp` · `WhiteUp` |
| `start folded { layers A above B … }` · `{ stacking first }` | `StartFolded (Relations [LayerAbove A B, …])` · `StartFolded StackingFirst` |
| `step N "C" { … }` | `Step (Just N) (Just "C") moves settle` |
| `fold valley`/`in front` · `fold mountain`/`behind` | `Fold ValleyFold …` · `Fold MountainFold …` |
| `fold S LINE` · `fold S 90° LINE` | `Fold S ToFlat LINE …` · `Fold S (Degrees 90) LINE …` |
| no layers · `all layers` · `top layer` · `top N layers` · `top flap` | `FlapOfFirstArgument` · `AllLayers` · `TopLayers 1` · `TopLayers N` · `TopFlap` |
| `moving P` · `flap containing P` | `Just P`, the fold's last field |
| `pre-crease S LINE …` · `precrease S LINE …` · `fold and unfold S LINE …` | `FoldAndUnfold S LINE layers seed` |
| `unfold A B` | `Unfold [A, B]` |
| `turn over left-right` · `top-bottom` | `TurnOver LeftRight` · `TopBottom` |
| `rotate 1/8 turn clockwise` · `rotate 2/8 turn anticlockwise` | `Rotate 1 Clockwise` · `Rotate 2 Anticlockwise` |
| `mark A = P` · `… in face containing S` | `Mark A P Nothing` · `Mark A P (Just S)` |
| `let N = P` · `let N = L` | `Let N (BindPoint P)` · `Let N (BindLine L)` |
| `collapse at P keeping [Q1, Q2] flat until A° sample B° …` | `Macro (Collapse P (Just (Q1, Q2)) A) [B, …]` |
| `rabbit-ear at P until A°` | `Macro (RabbitEar P A) []` |
| `petal tip P until A°` · `petal top flap until A°` | `Macro (Petal (TipAt P) A) []` · `Macro (Petal TopFlapTip A) []` |
| `continue N until A°` · `together { … }` | `Continue N A` · `Together [Located Move]` |
| `pose { crease [P, Q] at -90°; … }` | `Pose [(P, Q, -90), …]` |
| `repeat N` · `repeat N..M mirrored across [P, Q]` · `repeat N turned 2/4 about P` | `Repeat N Nothing Nothing` · `Repeat N (Just M) (Just (MirroredAcross P Q))` · `Repeat N Nothing (Just (TurnedQuarters 2 P))` |
| `checkpoint "p" { … }` · `not modelled "T"` | `Checkpoint "p" stacking` · `NotModelled "T"` |
| `expect refused K { m }` | `ExpectRefused (RefusalKind "K") m` |
| `material { … }` · `settle { … }` | `hMaterial = Just …` · `stepSettle = Just …` (07) |
| `corner south-west` … · `centre` · `(u, v)` | `CornerOf SouthWest` … · `Centre` · `AtSheet u v` |
| `midpoint of [P, Q]` · `midpoint of edge S` | `MidpointOf P Q` · `MidpointOfEdge S` |
| `fraction r along [P, Q]` · `meet L1 L2` | `FractionAlong r P Q` · `Meet L1 L2` |
| `end of crease of N nearest P` | `EndOfCreaseOf N P` |
| a name as a point · as a line | `PointNamed N` · `LineNamed N` |
| `edge S` · `[P, Q]` | `EdgeOf S` · `Segment P Q` |
| `P to Q` · `P to L` · `L1 to L2 [nearest R]` | `Onto P Q` · `PointToLine P L` · `LineOnto L1 L2 r` |
| `perpendicular to L through P` | `PerpendicularThrough L P` |
| `P to L through Q [nearest R]` · `P to L1 and Q to L2 [nearest R]` · `P to L1 perpendicular to L2` | `PointToLineThrough P L Q r` · `TwoToTwo P L1 Q L2 r` · `PointToLinePerpendicular P L1 L2` |
| `crease [P, Q]` · `hinge of N` · `crease of N` | `ExistingCrease P Q` · `HingeOf N` · `CreaseOf N` |
| `model [(x1, y1), (x2, y2)]` | `ModelSegment (x1, y1) (x2, y2)` |

`foldseq 1` and parentheses around a line set no field. `hSheet`, `hAnchor`,
`hStart` and `hMaterial` hold their values inside `Located`, which the table leaves
out.

### Error display

A `SequenceError` reaches a person as three separate pieces: `explain`,
`sourceLocation` and `excerpt`. They are kept apart for three reasons:

- a sequence built in Haskell has no location;
- no line of output may name the same path twice;
- `StepError` shows the cost of making one method carry both reason and location
  ([Steps.hs:64-78](../src/Senbazuru/Render/Steps.hs#L64-L78)).

`ParseProblem` is defined in `Sequence.Error`, beside `SequenceError`, which wraps
it as `ParseFailed` and which `parseSequence`, `checkSequence` and `runSequence` all
return ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).
`Sequence.Parse` only builds one.

```haskell
-- SKETCH (Senbazuru.Sequence.Error)
data ParseProblem = ParseProblem
  { problemSpan :: Span, problemFound :: Found        -- FoundWord Text | FoundChar Char | FoundEnd
  , problemExpected :: [Text], problemHint :: Maybe Hint }
data Hint = ViewWordForMaterial Text | FutureMove Text | ReservedName Text | NeedsUnit Rational
          | NotDegreeSign Char | StraySign | ZeroDenominator | UnclosedBlock Text
          | UnsupportedVersion Integer | LooksLikeFold | FractionAlongEdge
          | DuplicateHeader Text Int | HeaderAfterStep Text | NotYetSupported Text
```

megaparsec's error bundle is converted once, using its first error:

- **Position.** The error's offset becomes a line and column by counting code points
  in the same `Text`. megaparsec's own tab-width positions are not used.
- **What was found.** A failed keyword reads the whole next word, so the message
  says `found "left"`, not `found 'l'`.
- **Unverified names.** The megaparsec names used here (`errorOffset`,
  `customFailure`, `ErrorItem`) were read in the local 9.4.1 source
  (`Text/Megaparsec/Error.hs:75, 194`, `Text/Megaparsec.hs:369`), not in the pinned
  9.5.0.

Outputs (**SKETCH**; each line and column computed with `python3`). The first and
third are the quarter fold above with a mistake typed in, the second is the
[crane wing](#example-sources-checked-against-their-fixtures) with its `°` left off:

```text
senbazuru: quarter.foldseq:7:20: "left" names a direction on the page; a material edge is named by compass: edge north, east, south or west
  |
7 |   fold behind edge left to edge east
  |                    ^^^^
senbazuru: wing.foldseq:13:15: an angle needs its unit: write 90°
   |
13 |   fold behind 90 corner north-west to midpoint of edge north
   |               ^^
senbazuru: quarter.foldseq:6:56: the "{" opening step half is never closed
  |
6 | step half "Fold the left half behind, onto the right." {
  |                                                        ^
```

**Header refusals.** They start with the header line as the printer spells it. A
sheet that `sheetState` refuses arrives as `SheetRefused`, carrying the `sheet`
line's span and the path as written ([D20](decisions.md#d20-errors)).
`examples/bird-base-sequence.fold` makes a good case: its key frame has 0 vertices
and there are 16 `file_frames`
(`python3 -c 'import json; f=json.load(open("examples/bird-base-sequence.fold")); print(len(f.get("vertices_coords", [])), len(f["file_frames"]))'`):

```text
senbazuru: bird.foldseq:3:1: sheet "examples/bird-base-sequence.fold": the key frame has no vertices, and a sheet is always the key frame; this file keeps its 16 states in file_frames
```

**Step refusals.** They start `step N (name)`, then give the reference as the
printer spells it, then the nested error's `explain` unchanged
([D20](decisions.md#d20-errors)). The nested wording is [02's catalogue](02-language-semantics.md#12-refusal-catalogue)'s. Here an
author types a decimal that nearly hits the bird base's vertex 9 at
(1/2, 0.2071067811865475), 1.07e-4 sheet lengths away (0.2071067811865475 − 0.207,
by arithmetic), inside the near-miss band of owner decision 2:

```text
foldseq 1
sheet "examples/bird-base.fold"

step pinch {
  fold valley corner south-west to (1/2, 0.207)
}
```

```text
senbazuru: pinch.foldseq:5:3: step 1 (pinch): (1/2, 207/1000): a typed point 1.07e-4 sheet lengths from (internal vertex 9) at (1/2, 0.2071067811865475), outside the tolerance but inside the near-miss band 0.001; name the vertex by a construction
  |
5 |   fold valley corner south-west to (1/2, 0.207)
  |   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

**This looks wrong and is intended: the message never contains the *source's*
path, yet every CLI line starts with one.** The path comes from `sourceLocation`,
so a Haskell-built sequence gets the same sentence with no prefix. A path inside
the message, like the sheet's above, is a different file.

**References are quoted as the printer spells them.** Above, the author typed
`0.207` and the message says `207/1000`; the excerpt under it shows what was typed.
Quoting the typed text would need a span on every point, which adds a field to every
point constructor 03's builder fills. Only moves, steps and the `Located` header
fields carry spans, so the caret underlines the whole move.

### Reading a source and its sheets

1. The CLI calls `readSequenceText path`, then `parseSequence path`, then
   `checkSequence` ([02](02-language-semantics.md)).
2. With `--check`, it stops here and prints `checkSummary`, for example
   `blintz.foldseq: 5 steps, 5 moves, checked without geometry`.
3. `sourceFiles path sequence` lists `(written, toOpen, span)` for each `sheet` and
   `checkpoint`. For the crane wing saved inside `examples/`, as
   `examples/wing.foldseq` with `sheet "crane.fold"`, `toOpen` is
   `examples/crane.fold`.
4. The CLI calls `loadFile toOpen` for each distinct path and takes `keyFrame`
   ([Types.hs:128](../src/Senbazuru/Fold/Types.hs#L128)). So `.cp` and `.opx` sheets
   work too.
5. It calls `runSequence budget settings (Map.fromList [(written, frame)]) (elaborate checked)`,
   then writes the output. `checked` is `checkSequence`'s result, `budget` comes from
   `--layer-budget`, and `settings` is `RunSettings`, the runner's tolerances, at its
   defaults: no `run` flag changes them.
6. If `runRefusal` of the run gives `Just e`, the run stopped at a `not modelled`
   move. The output written in step 5 holds the states before it; the CLI then
   prints `e` through `refusalLines` and exits nonzero (R-04-28).

The map is keyed by the path *as written*. Messages and the report therefore use
the author's spelling, and tests pass frames without a filesystem. Paths resolve
against the source, not the working directory, so `run` answers alike from a
Makefile, a test and a shell.

**A source handed to another verb is refused, and the library's words name no
command.** Today `decodeFile` decodes every unrecognised extension as FOLD
([Load.hs:102-106](../src/Senbazuru/Fold/Load.hs#L102-L106)), so
`render blintz.foldseq` fails as bad JSON. R-04-18's new `LoadError` says instead
that the file is a sequence source. The advice "use `senbazuru run PATH`" is
appended by `app/`'s `withFoldFile`, not written by `explain`, because a library
message is also read from GHCi and by the study, where a command is no help
([D13](decisions.md#d13-the-run-verb-and-io)). The repository has that leak once
today, and [D20](decisions.md#d20-errors) removes it: `Fold.Query.creaseEndFlag`
returns `--from` or `--to` ([Query.hs:68-71](../src/Senbazuru/Fold/Query.hs#L68-L71)),
and `ThroughLayers`' message starts with it
([ThroughLayers.hs:194-195](../src/Senbazuru/Origami/ThroughLayers.hs#L194-L195)).
Input starting with `{` is split the same way: `LooksLikeFold`'s message says the
text looks like FOLD, and `refusalLines` adds which verbs read it.

### The `run` verb

```text
senbazuru run SOURCE [-o OUT.fold|OUT.svg|OUT.glb] [--layer-budget N] [--report]
                     [--frame N] [--all-layers] [--columns N] [--view NAME]
                     [--width PT] [--height PT] [--author TEXT] [--description TEXT]
senbazuru run SOURCE --check
```

| Output | Library path |
| --- | --- |
| none, or `.fold` | `writeSequence header run`, then `encodeFoldFile` through `writeDocument` ([Cli.hs:788-794](../app/Senbazuru/Cli.hs#L788-L794)). The frames are laid out as [D4](decisions.md#d4-written-frames-follow-the-state-rule) decides and [02 §11](02-language-semantics.md#11-written-frames) walks through: a key frame holding only metadata, then state k as `file_frames[k]` ([D24](decisions.md#d24-states-figures-and-their-numbers)). For the quarter fold, `file_frames` holds state 0, the flat start; state 1, after `half`; and state 2, after `quarter`. So `--frame 2` selects state 1, the state after `half`. |
| `.svg` | `stepNotes run`, which returns `Either WriteProblem [(Frame, StepNote)]`, then `stepPageWith theme budget grid view` ([06](06-prd-step-diagrams.md)), then `renderSvg`; `app/` turns the plan's view name into a `View`. `stepNotes` and `writeSequence` both read `Sequence.Record.writtenStates`, so the page draws exactly the states the `.fold` holds ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)). The page is titled with the file title, as `render --steps` does ([Cli.hs:866](../app/Senbazuru/Cli.hs#L866)). |
| `.glb` | The chosen state, through `renderGlb budget mode title frame` ([Gltf.hs:200](../src/Senbazuru/Render/Gltf.hs#L200)) with `export`'s title rule ([Cli.hs:779](../app/Senbazuru/Cli.hs#L779)). `app/` maps the plan's `GlbScenes` to `VisiblePaper`, or to `CompletePaper` with `--all-layers`, as `export` chooses its mode ([Cli.hs:776](../app/Senbazuru/Cli.hs#L776)). 08's modes add flags later. |

**Flag rules are library functions with their own types.** The CLI is untested, so
what `run` accepts and how it prints a refusal live in `Sequence.RunPlan`, at level
6 of the `Sequence` family
([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)) and in row 6 of
[the module layers](decisions.md#2-shape):

```haskell
-- SKETCH (Senbazuru.Sequence.RunPlan)
data RunOptions = RunOptions { ... }   -- every flag as given; each is a Maybe or a Bool
data Plan = PlanCheck | PlanFold (Maybe FilePath) Budget FileMeta
          | PlanSvg FilePath Budget PageFlags | PlanGlb FilePath Budget (Maybe Int) GlbScenes
data PageFlags = PageFlags { flagColumns :: Int, flagViewName :: Maybe Text
                           , flagWidth :: Double, flagHeight :: Double }
data GlbScenes = GlbVisibleAndComplete | GlbCompleteOnly   -- app/ maps it to ExportMode
planRun :: RunOptions -> Either RunOptionError Plan       -- R-04-22, 23, 27; --frame 0
chooseState :: Maybe Int -> Int -> Either RunOptionError Int   -- state N - 1 for --frame N, checked against the count
refusalLines :: Text -> SequenceError -> [Text]           -- R-04-16, without "senbazuru: "
```

- **The plan holds a view *name* and a scene enumeration**, not `Render.Camera.View`
  ([Camera.hs:188](../src/Senbazuru/Render/Camera.hs#L188)) or
  `Render.Gltf.ExportMode` ([Gltf.hs:147](../src/Senbazuru/Render/Gltf.hs#L147)).
  Those live in row 7, which a row-6 module cannot import, so `app/` maps them.
  `Budget` is `Origami.Stacking`'s
  ([Stacking.hs:165](../src/Senbazuru/Origami/Stacking.hs#L165)), which row 6 may
  import. The field names are not `pageWidth` and `pageHeight`, which `app/`
  already uses for the page it draws ([Cli.hs:911-912](../app/Senbazuru/Cli.hs#L911-L912)).
- **`RunOptionError` names flags, and that is not the leak
  [D20](decisions.md#d20-errors) forbids.** That rule keeps command-line words out
  of messages that GHCi and the study read. `Sequence.RunPlan` exists only for the
  `run` verb, which is also why `refusalLines`, not `explain`, adds the verbs that
  read FOLD after input starting with `{`.

The CLI calls `planRun` before it reads any file, and passes the plan's `Budget` to
both `runSequence` and the renderer. `die` adds `senbazuru: `
([Cli.hs:1085-1086](../app/Senbazuru/Cli.hs#L1085-L1086)).

Choices that could look arbitrary:

- **Flags are parsed with `optional`.** So `run` can tell a typed `--columns 3` from
  the default 3, and refuse it when `-o` is `.glb`. The defaults are `render`'s:
  400 × 400, 3 columns, and the view chosen from the geometry
  ([Cli.hs:546-607](../app/Senbazuru/Cli.hs#L546-L607)). The budget's default and
  its refusal of anything below 1 are
  [Cli.hs:385-406](../app/Senbazuru/Cli.hs#L385-L406)'s.
- **`--frame` is refused with `.fold` and `.svg`.** Both hold every state, which is
  why `render --steps` refuses `--frame` ([Cli.hs:843](../app/Senbazuru/Cli.hs#L843)).
  `run` also gets its own `--frame` parser, because the shared one says "default: 0,
  the key frame" ([Cli.hs:484-493](../app/Senbazuru/Cli.hs#L484-L493)).
- **`--frame 2` is a different state on the fixture and on `run`'s file, and both
  are right.** On `quarter-fold-steps.fold` it is the state after `quarter`,
  because that file keeps its flat start in its key frame. On the sequence file
  `run` writes, it is the state after `half`, because that key frame holds only
  metadata. Every verb reads `--frame` through `allFrames f = keyFrame f : otherFrames f`
  ([Types.hs:209-210](../src/Senbazuru/Fold/Types.hs#L209-L210)), so the flag means
  one thing everywhere and the two files differ.
- **The constructor is `RunSource`.** The runner's result type is named `Run`, and
  [D23](decisions.md#d23-the-sequence-modules-and-where-run-lives) defines it in
  `Sequence.Record`. A `Command` constructor also named `Run` would clash wherever
  both are imported unqualified.
- **No `--rotate`.** A turn the reader should see is written in the source
  (`rotate 1/8 turn`), so it reaches every output alike
  ([D5](decisions.md#d5-presentation-and-the-readers-side),
  [D13](decisions.md#d13-the-run-verb-and-io)).
- **`--view` is extracted into a shared parser**, so `run` and `render` accept the
  same view names under one help string. `render --help` must stay byte-identical,
  checked with `diff`.
- **`run -o x.glb --frame N` gives the same bytes as `export` of `run`'s `.fold`
  at `--frame N`.** Both call `renderGlb` on the same frame with the same title rule.
- **`--report` goes to stderr**, so it composes with FOLD on stdout. Under a
  heading per move it lists one fact per line. An `expect refused` move has no
  record, so its line comes from its step's outcome in the `Run`:

  | Report line | Where it comes from |
  | --- | --- |
  | Assurance: what the move claims about its route ([glossary-additions](glossary-additions.md#assurance)) | `recordEvidence` ([D10](decisions.md#d10-assurance-as-evidence-values)) |
  | Each reference as resolved, and where it now appears as seen | `recordResolved` ([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)) |
  | New creases, as material segments with "(internal edge N)" | `recordNewCreases` ([D20](decisions.md#d20-errors)) |
  | Re-anchors: where the paper held still changes | `recordAnchor` ([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)) |
  | Stacking choice | `recordStacking` ([D11](decisions.md#d11-stacking-choices-are-relations)) |
  | Work counts | `recordCost` |
  | An expected refusal: the kind asked for and the kind raised | the step's outcome in `runSteps` ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)) |

  If a `material` block gives a thickness, the report says it is stored but not
  used, because thickness is not modelled as geometry
  ([D14](decisions.md#d14-material-consumption), [D18](decisions.md#d18-non-goals)).

### Dependencies in the cabal file

```cabal
-- SKETCH: library build-depends additions
    , megaparsec          >=9.5  && <9.6
    , parser-combinators  >=1.3  && <1.4
    , transformers        >=0.6  && <0.7
```

- **Pinned by the snapshot.** The lock file pins `lts/22/44.yaml`
  ([stack.yaml.lock](../stack.yaml.lock)). That snapshot lists megaparsec 9.5.0
  (BSD-2-Clause) and parser-combinators 1.3.0 (BSD-3-Clause)
  ([C](research/C-renderers-cli-formats.md) "(e) Dependencies", finding 23).
  Stackage's `cabal.config` for lts-22.44 agrees
  ([F](research/F-haskell-edsl-techniques.md) finding 18), and so does the snapshot
  file in Stack's pantry cache
  ([decisions, appendix command 6](decisions.md#appendix-commands-behind-the-numbers)).
- **Trap.** A stackage.org *package* page served LTS 24.59 (finding 23), so it is
  not evidence for the pinned versions.
- **transformers** 0.6.1.0 ships with GHC 9.6.7 (finding 23). It gives the
  builder `Control.Monad.Trans.State.Strict`
  ([D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders)).
  megaparsec 9.4.1's own cabal file, read locally at lines 64-68, bounds it `<0.7`.
- **parser-combinators** is already a dependency of megaparsec. It is still listed,
  because GHC hides packages a stanza does not name, and the parser imports
  `Control.Monad.Combinators.Expr` for `union` and `minus`.
- **Library, not executable.** The builder and parser must work without the CLI
  ([Cli.hs:5-8](../app/Senbazuru/Cli.hs#L5-L8)), and the study reads sources too.
- **Executable and tests.** The executable adds `containers` and `filepath`
  ([senbazuru.cabal:167-172](../senbazuru.cabal#L167-L172)). The tests need nothing
  new, since QuickCheck is there ([senbazuru.cabal:321](../senbazuru.cabal#L321)).

### Rejected alternatives

| Alternative | Why not |
| --- | --- |
| JSON or YAML authoring | Errors point to JSON paths, not lines, for exactly the errors that matter ([F](research/F-haskell-edsl-techniques.md) finding 19). |
| Significant indentation, or `end` | Errors about invisible whitespace. The design chose braces ([D12](decisions.md#d12-the-text-syntax)). |
| S-expressions | Unfamiliar to folders ([F](research/F-haskell-edsl-techniques.md) finding 20). |
| A hand-written reader, as for `.cp` | The grammar nests blocks, so it is megaparsec-sized, not `T.words`-sized ([C](research/C-renderers-cli-formats.md) "Implications for the design"). |
| Context-dependent keywords, so `step front` parses | Every new keyword would break old sources, and a stray word would give an ambiguous error. |
| A parser that tracks each name's kind | Parsing would depend on declaration order. References parse untyped and Check assigns kinds ([D12](decisions.md#d12-the-text-syntax)); the four-row `canonical` costs less. |
| `--check` opening sheets | `--check` would stop being `checkSequence . parseSequence`, the function the tests call. `run` reports a missing sheet before any geometry. |
| Reading `.foldseq` through `loadFile` | `Fold.Load` would depend on `Origami.*` ([C](research/C-renderers-cli-formats.md) finding 21). |
| Location in `explain`, or `errorBundlePretty` as the message | A Haskell-built sequence has no location, and that text runs to several lines. |
| Lenient UTF-8, as `.cp` uses ([Load.hs:108-121](../src/Senbazuru/Fold/Load.hs#L108-L121)) | A Latin-1 `°` would become U+FFFD, the replacement character, reported as an unexpected character nobody can see. |
| `--format` instead of the extension | Two ways to say one thing. |
| Flag rules in `Cli.hs` | Untestable, which is how `--layer-budget` did nothing on `render` for as long as it was not a parameter ([AGENTS.md](../AGENTS.md) "Conventions"). |
| `decodeFile`'s `explain` naming `run` | A library message is read from GHCi and by the study too, where a command is no help; `app/` appends the hint ([D13](decisions.md#d13-the-run-verb-and-io), [D20](decisions.md#d20-errors)). |
| A `Plan` holding `Render.Camera.View` and `Render.Gltf.ExportMode` | Both are row-7 types, and `Sequence.RunPlan` is in row 6 ([D13](decisions.md#d13-the-run-verb-and-io)). |

### Example sources, checked against their fixtures

Each example is typed as an author would, aliases included. Its pretty golden is
its canonical print. The quarter fold is [above](#a-first-source-read-line-by-line).

**Blintz** (M2). A blintz folds all four corners to the centre
([glossary-additions](glossary-additions.md#origami)).

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

```sh
python3 -c 'import json, math; f=json.load(open("examples/blintz-base.fold")); V=f["vertices_coords"]; E=f["edges_vertices"]
print(len(V), min(math.dist(v, (.5, .5)) for v in V), "faces_vertices" in f, [(E[e], f["edges_assignment"][e], f["edges_foldAngle"][e]) for e in range(8, 12)])
on = lambda c, k: abs((V[k][0]-(c[0]+.5)/2)*(c[0]-.5) + (V[k][1]-(c[1]+.5)/2)*(c[1]-.5)) < 1e-12
print([[e for e, (a, b) in enumerate(E) if on(c, a) and on(c, b)] for c in [(1, 0), (1, 1), (0, 1), (0, 0)]])'
```

- **The centre is not a vertex.** There are 8 vertices, the nearest 0.5 from
  (1/2, 1/2), and the file has no faces. An anchor fills a *region* slot, which
  asks only that the point lie strictly inside one face, not on a vertex
  ([slots](glossary-additions.md#references),
  [D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)). With no
  faces in the file, they are *traced*: recovered from the creases by `Fold.Faces`. The traced central
  square's corners are the four edge midpoints, so its sides lie
  (1/2)/√2 ≈ 0.354 from the centre, by arithmetic.
- **Every fold line is an existing crease.** The lines taking the south-east,
  north-east, north-west and south-west corners to the centre contain edges 8, 9,
  10 and 11 respectively, so nothing is creased. That is the recipe's order
  ([BlintzSequence.hs:50-56](../study/fold-material/BlintzSequence.hs#L50-L56)).
- **The file's angles are not the start.** Edges 8–11 are `M` at −180 in the file;
  plain `sheet` zeroes them, as the recipe does
  ([BlintzSequence.hs:42](../study/fold-material/BlintzSequence.hs#L42)).
- **UNVERIFIED:** that the runner reproduces the recipe
  ([D16](decisions.md#d16-testing-and-acceptance) migration, M2); and the direction,
  owner decision 8.

**Bird base** (M5). A *collapse* folds several precreases at once into a square
base. A *petal fold* lifts one flap while its sides fold in. Both are *macro-moves*
([glossary-additions](glossary-additions.md#macro-moves)). The step names avoid
reserved words.

```text
foldseq 1
title "Bird base"
sheet "examples/bird-base.fold"
anchor (29/50, 2/5)

step square-base "Collapse into a square base." {
  collapse at centre until 180° sample 30° 60° 90° 120° 150° 175°
}
step first-petal "Petal fold the front flap up." { petal tip corner south-east until 175° }
step second-petal "Petal fold the back flap behind." { petal tip corner north-west until 175° }
step "Press both petals flat." {
  together { continue first-petal until 180°; continue second-petal until 180° }
}
```

```sh
python3 -c 'import json, math; f=json.load(open("examples/bird-base.fold")); V=f["vertices_coords"]; E=f["edges_vertices"]; A=f["edges_assignment"]; G=f["edges_foldAngle"]
nb = lambda v: sorted({b for a, b in E if a == v} | {a for a, b in E if b == v})
print(V[1], V[3], V[8], [i for i, a in enumerate(A) if a == "F"], [(E[i], A[i], G[i]) for i in (26, 27)], nb(1), nb(3), sum(g != 0 for g in G), len(G))
(ax, ay), (bx, by), (cx, cy), (px, py) = V[8], V[9], V[10], (29/50, 2/5); d = (by-cy)*(ax-cx) + (cx-bx)*(ay-cy)
l1 = ((by-cy)*(px-cx) + (cx-bx)*(py-cy))/d; l2 = ((cy-ay)*(px-cx) + (ax-cx)*(py-cy))/d; print([round(x, 3) for x in (l1, l2, 1-l1-l2)])
seg = lambda p, a, b: math.dist(p, [a[i] + max(0, min(1, ((p[0]-a[0])*(b[0]-a[0]) + (p[1]-a[1])*(b[1]-a[1]))/math.dist(a, b)**2))*(b[i]-a[i]) for i in (0, 1)])
print([(i, e) for i, e in enumerate(E) if set(e) <= {8, 9, 10}], "faces_vertices" in f, min((round(seg((px, py), V[a], V[b]), 4), i) for i, (a, b) in enumerate(E)))'
```

- **`centre` is a vertex here**, v8 at (0.5, 0.5), as `collapse at` requires. Edges
  11, 15, 19 and 23 are `F` guides (*flat*: crease lines that exist but are not
  folded, [glossary](../docs/glossary.md#the-fold-format)), and the flat bird has
  exactly one collapse match
  ([gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md)
  "B. Signatures, checked by hand", finding 13).
- **Each tip names one petal.** v1 = (1, 0), the south-east corner. Its interior
  neighbours are v9 and v10, both ends of hinge 26; its other neighbours, v4 and
  v5, lie on the sheet's edges. v3 = (0, 1), the north-west corner. Its interior
  neighbours are v11 and v12, both ends of hinge 27; its other neighbours, v6 and
  v7, lie on the sheet's edges. Both hinges are `V` at 180 in the file. Finding 13
  counts these two petal matches.
- **The anchor is inside one face.** The file has no `faces_vertices`. Edges 10, 14
  and 26 bound triangle (v8, v9, v10), and the anchor's *barycentric coordinates*
  in it (the weights that write the point as a mix of the three corners; all
  positive means strictly inside) are (0.385, 0.341, 0.273). The nearest crease,
  edge 26, is 0.0798 away, so the anchor lies on no crease, as
  [02 §4.4](02-language-semantics.md#44-resolution-by-slot) also finds.
- **The file's angles are not the start.** 16 of 28 edges carry a nonzero angle,
  which plain `sheet` zeroes.
- **UNVERIFIED:** the `continue` bindings
  ([D9](decisions.md#d9-macro-moves-as-named-angle-relations)) and the sample poses,
  at M5.

**Crane wing** (M4, M6). `start folded` keeps the file's folded state and names its
*stacking*, which layer lies over which
([glossary-additions](glossary-additions.md#running-a-sequence)). `settle` asks the
material study to bend the result
([glossary-additions](glossary-additions.md#material)); 07 owns those words. This
is the version [decisions §7](decisions.md#7-examples) records.

```text
foldseq 1
title "Lower one crane wing"
sheet "examples/crane.fold"
anchor (19/20, 1/3)        # strictly inside face 0
start folded {
  layers (1/4, 1/5) above (3/8, 5/9)     # UNVERIFIED: must leave exactly the tail-tucked stacking
  layers (4/9, 3/8) above (1/4, 1/5)
}
material { stiffness illustrative }

step wing "Fold the underneath wing away from you until it stands straight out." {
  expect refused FlapCovered { fold in front 90° corner north-west to midpoint of edge north }   # UNVERIFIED kind
  fold behind 90° corner north-west to midpoint of edge north
  settle {
    refine side moving 3
    rest at rigid-pose 1/3
    hold closed side stationary
    hold band moving 0..1/32 at rigid-pose 1/3    # UNVERIFIED: equals CraneSpread's root-strip pins
    grip band moving 7/32.. arc-grip 30° 20°      # UNVERIFIED: equals CraneSpread's grip pins
  }
}
```

```sh
python3 -c 'import json, math; f=json.load(open("examples/crane.fold")); V=f["vertices_coords"]; F=f["faces_vertices"]
def seg(p, a, b): t = max(0, min(1, ((p[0]-a[0])*(b[0]-a[0]) + (p[1]-a[1])*(b[1]-a[1]))/math.dist(a, b)**2)); return math.dist(p, (a[0]+t*(b[0]-a[0]), a[1]+t*(b[1]-a[1])))
def rings(r): return list(zip([V[k] for k in r], [V[k] for k in r[1:]+r[:1]]))
inside = lambda p, r: sum((a[1] > p[1]) != (b[1] > p[1]) and p[0] < a[0]+(p[1]-a[1])*(b[0]-a[0])/(b[1]-a[1]) for a, b in rings(r)) % 2
for p in [(19/20, 1/3), (1/4, 1/5), (3/8, 5/9), (4/9, 3/8)]: print(p, [(i, round(min(seg(p, a, b) for a, b in rings(r)), 3)) for i, r in enumerate(F) if inside(p, r)])
print([i for i, r in enumerate(F) if 2 in r], V[2], V[28], "edges_foldAngle" in f)'
python3 PRDs/research/scripts/layer-selection-analyse.py fold examples/crane.fold | grep -E '^faces|^v (2|28) '
python3 PRDs/research/scripts/layer-selection-analyse.py line examples/crane.fold 0,0.25 2,0.25 0.02,0.97 | grep -E 'seed_faces|component_faces'
```

The anchor's comment is checked by the command above; the comments marked
**UNVERIFIED** are not. The *tail-tucked stacking* is the one of the fixture's five
layer orders that puts all eight tail faces between the two sides of the body,
index 2
([CraneWing.hs:75-78](../study/fold-material/CraneWing.hs#L75-L78);
[several stackings](../docs/notes/several-stackings.md)). *CraneSpread's root strip*
is the short strip of wing beside the hinge that the study holds at a fixed angle
([CraneSpread.hs:7](../study/fold-material/CraneSpread.hs#L7)).

- **Every typed point is inside exactly one face.** The anchor is in face 0, 0.05
  from its boundary. The relation points are in tail face 10 (0.027), body face 27
  (0.049) and body face 29 (0.049).
- **The named points are vertices.** `corner north-west` is vertex 2 at
  (5.886846565772426e-15, 0.9999999999999996). `midpoint of edge north` lands on vertex 28 at
  (0.49999999999998834, 1). Resolution to a vertex allows a tolerance, and sheet
  lengths are measured from the file's own box
  ([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)).
- **The fold line is folded y = 1/4.** The file has no `edges_foldAngle`, so
  `start folded` folds it from its assignments, having no angles to keep
  ([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)). The
  research script puts vertex 2 at (1, 4.6e-14) and vertex 28 at (1, 0.5). Its
  *closure error*, the worst disagreement between two faces about where a shared
  vertex lies, is 3.0e-13. The line bringing vertex 2 onto vertex 28 is y = 1/4.
- **The flap, the paper that turns, is the wing.** Faces 2, 3, 6 and 7 hold vertex
  2. The script's [seed](glossary-additions.md#references) (0.02, 0.97), a point
  inside the wing rather than on a crease, selects the faces still joined to it once
  the paper is cut along the line: `[2, 3, 6, 7]`
  ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) "Re-deriving
  CraneWing by rule (script)"). That is Python evidence, not Haskell
  ([D8](decisions.md#d8-folding-some-layers)).
- **The `material` and `settle` lines.** `stiffness illustrative` is
  `Bending 1 0.2`, the stiffness `CraneSpread` builds its hinges with
  ([CraneSpread.hs:98](../study/fold-material/CraneSpread.hs#L98)).
  `refine side moving 3` refines the wing at level 3, one of the two levels
  `craneSpreadWith` accepts ([:82-83](../study/fold-material/CraneSpread.hs#L82-L83)).
  `rest at rigid-pose 1/3` rests every active crease at its angle a third of the way
  through this 90° fold, the wing at 30°; with no rest line here or in the
  `material` block, the settle is refused as `SettleNoRest`
  ([D14](decisions.md#d14-material-consumption)).
- **The expected kind is `FlapCovered`, not `FlapEndpointOrder`.** The selection
  rule refuses a fold when a stationary face is nearer than the flap on the side it
  turns towards, and it runs before `Flap`'s sweep
  ([D8](decisions.md#d8-folding-some-layers),
  [02 §6.3](02-language-semantics.md#63-which-layers) step 4). `CraneWing` gets
  `FlapEndpointOrder` ([Flap.hs:120](../src/Senbazuru/Origami/Flap.hs#L120)) only
  because it calls `Flap` with no selection step
  ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)).
- **UNVERIFIED:** that the two relations leave exactly one stacking
  ([D11](decisions.md#d11-stacking-choices-are-relations), M4); that the valley is
  refused at all, and as `FlapCovered`, which rests on the inference that the other
  wing lies on this wing's reader side
  ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) finding 14);
  the sense as seen ([02](02-language-semantics.md)); and every `settle` equivalence,
  07's first M6 test.

## Acceptance criteria

| # | Criterion | Turns red when |
| --- | --- | --- |
| A1 | R-04-9's round-trip property passes, with a `cover` for each constructor. | The printer drops captions, a production is deleted, `canonical` is not idempotent, or a `Rational` prints as a decimal. |
| A2 | Pretty goldens of the quarter fold, blintz and bird base at M1, and of the crane wing at M6 when the parser reads `settle`, via `goldenText` ([Golden.hs:38](../test/Test/Golden.hs#L38)). | Any spelling, indent, order or number rule changes. |
| A3 | Error-text goldens (`explain` plus `excerpt`) for: view word, missing unit, `º`, unclosed block, reserved name, `foldseq 2`, input starting with `{`, a stray sign, `fraction … along edge`, `nearest` on O2, `1/0`, `rotate 1/4 turn`, `stacking first` beside a relation, a duplicate header, a header after a step, a tab before the caret. | A message's words or a caret column change. |
| A4 | `0..1/32` lexes as a range, `7/32..` as an open range, and `refine band moving 7/32.. 3` parses as that open range and the count 3. | The decimal reader accepts `0.` with no digit after the point, or a space is allowed before an upper bound. |
| A5 | `examples/traditional-crane.foldseq`, 28 steps from `sheet square` using `repeat`, five `not modelled` moves and one `checkpoint` ([09 §5](09-testing-and-acceptance.md#5-the-whole-crane-parses-and-checks)), parses and checks without loading any file. | `NotModelled`, `Checkpoint` or `Repeat` leaves the parser, or checking needs the checkpoint's file ([D16](decisions.md#d16-testing-and-acceptance)). |
| A6 | Covered by [03's A-2](03-prd-embedded-dsl.md#acceptance-criteria) (the builder's blintz equals the parsed blintz); not repeated here. | — |
| A7 | `decodeFile` refuses `x.foldseq` and `X.FOLDSEQ` with the new `LoadError`, whose `explain` names no command (neither `run` nor `senbazuru`), and still decodes a path with no extension (`square`) as FOLD. | The case is deleted or placed after the fallback, or a command enters the library message. |
| A8 | `readSequenceText` strips a byte-order mark, and gives `DecodeFailed` on invalid UTF-8 and `ReadFailed` on a missing file. | Decoding becomes lenient; the byte-order mark reaches the parser; a missing file gives `DecodeFailed`. |
| A9 | `sourceFiles "examples/w.foldseq"` maps `"crane.fold"` to `examples/crane.fold`, keeps `"crane.fold"` as the written key, and keeps absolute paths. | Paths resolve against the working directory, or the key becomes the resolved path. |
| A10 | `explain` is identical for an error with a span and the same error with `NoSpan`, and `sourceLocation` is `Nothing` for the second. | A path or line number enters the message. |
| A11 | Encoding `NaN` or an infinity is refused, naming the element. | The encoder writes aeson's `"+inf"` or `null`. |
| A12 | R-04-10's reserved-word property passes. | The printer gains a keyword the list lacks. |
| A13 | By hand at M2: `run -o q.glb --frame 2` matches `export` of `run`'s `.fold` at `--frame 2` (`cmp`), and `render --help` matches its output saved from a build of `568dcb6` (`diff`). | `run` chooses the frame or the title differently, or reads the source through `withFoldFile` (A7's refusal stops it). |
| A14 | The 33 tracked goldens are byte-identical ([D16](decisions.md#d16-testing-and-acceptance)). | Any existing output changes. |
| A15 | `planRun` refuses each flag outside its output: `--frame` with `.fold` or `.svg`, a page flag without `.svg`, `--all-layers` without `.glb`, `--author` or `--description` without `.fold`, and any of these or `-o` with `--check`. It refuses `-o x.png` and accepts `-o X.SVG`. Every geometric plan holds the `--layer-budget` given. | A refusal is dropped, the extension is compared before lowercasing, or a plan holds `defaultBudget` in place of the flag. |
| A16 | `chooseState` on a 3-state file refuses `--frame 0` and `--frame 4`, both naming 3; gives state 0 for `--frame 1` and state 2 for `--frame 3`; and gives state 2 with no `--frame`. | `--frame N` selects state N rather than N − 1, so `run` and `export` disagree by one; or the default becomes the first state. |
| A17 | `refusalLines` gives `wing.foldseq:13:15: an angle needs its unit: write 90°` followed by the three excerpt lines for the missing-unit error; exactly `[explain e]` for a `NoSpan` error; and, for input starting with `{`, one more line after the excerpt naming the verbs that read FOLD, which `explain` does not name. | A `NoSpan` error gets a location prefix, the excerpt is printed without one, or the verb line moves into `explain`. |
| A18 | The quarter fold with step `quarter`'s fold replaced by `not modelled "fold in quarters"`: `runSequence` gives `Right` a `Run` whose `runStop` names step 2, `quarter`; `runRefusal` gives `StepRefused 2 (Just "quarter") … (NotModelled "fold in quarters")`; and the writer writes a sequence file of 2 states, the flat start and the state after `half`. | The records before the move are discarded, the stop becomes a `Left`, `runRefusal` gives `Nothing`, or the writer refuses a run that stopped early. |
| A19 | Goldens of `renderRunReport` on the quarter fold, with every record row of the report table present, and on 09's E10 blintz with move 5 wrapped in `expect refused FlapEndpointOrder` ([09 §3](09-testing-and-acceptance.md#3-end-to-end-e1e10-on-the-blintz)), whose report has the expected-refusal line. | A report line is dropped or reads a different field, or an expected refusal is left out of the report. |

## Dependencies

| Milestone | From this file |
| --- | --- |
| M0 | Row 2 of [01](01-architecture.md)'s recorded-text table: a source is a program, not an input format. |
| M1 | `Sequence.Syntax`, `Parse` and `Pretty`; `Sequence.Error` and `Check` with 02; `readSequenceText`; the `decodeFile` refusal and `withFoldFile`'s `run` hint; `Sequence.RunPlan` for `--check`; `run --check`; A1–A10, A12, A14, A15's `--check` rows, A17. The parser refuses `settle` and `material` blocks as not yet supported. |
| M2 | `run -o .fold` and `.glb`, `--report` with its `expect refused` lines, the `not modelled` stop through `runRefusal`, `--layer-budget`, `--frame`, `--all-layers`, `--author`, `--description`; #58 item 3 (A11); A13, the rest of A15, A16, A18, A19. Closes [#97](https://github.com/avalonalex/senbazuru/issues/97) and advances [#60](https://github.com/avalonalex/senbazuru/issues/60). |
| M3 | `run -o .svg` and its page flags, through 06's `stepPageWith`. |
| M4, M5 | `start folded`, `checkpoint`, `repeat` and the macros run; all parse from M1. |
| M6 | The words of `settle` and `material`, from 07; A2's crane-wing golden. |

Other files: 02 (meanings, `StaticProblem` wording, refusal kinds), 03 (the tree
and canonical construction), 05 and 06 (functions the outputs call), 07, 08 (GLB
modes), [#73](https://github.com/avalonalex/senbazuru/issues/73).

What other files carry from this one, as the decision record settles it:

- **03** builds the tree refinements in
  [How the ambiguities are resolved](#how-the-ambiguities-are-resolved)
  ([D12](decisions.md#d12-the-text-syntax)), and its R-03-10 and A-1 run R-04-9's
  property over a generator with Haskell-only values.
- **02**'s catalogue has `ZeroDenominator` as a parse `Hint`, not a `StaticProblem`,
  because no `Rational` holds `n/0`, so no tree reaches Check with one
  ([D20](decisions.md#d20-errors)). `ViewWordForMaterial` is the `Hint` named here.
- **09**'s crane round trip takes R-04-9's form, and its M1 and M2 rows list
  A15–A19.
- **07**'s settle words and crane block match [the grammar](#grammar) and
  [the crane example](#example-sources-checked-against-their-fixtures).

## Risks

| Risk | Mitigation |
| --- | --- |
| megaparsec names were read in 9.4.1, not 9.5.0 | M1 compiles against 9.5.0 before any message golden is accepted. |
| megaparsec reports the furthest failure, so expected lists get long | Labels (`<?>`), hints for known traps, A3. |
| The EBNF in `Sequence.Parse`'s header drifts from the parser | Kept in step by review only. A1 and A12 catch printer–parser drift, not a stale header (R-04-11). |
| `run` passes the plan's budget to `runSequence` but not to the renderer | By review only; A15 covers `planRun`, not the call sites. `Cli.hs` already imports `defaultBudget` for `budgetOption` ([Cli.hs:395](../app/Senbazuru/Cli.hs#L395)), so the type system does not stop a call site using it. |
| A later keyword breaks old sources | Future move words are reserved now; `foldseq` carries a version. |
| `°` is awkward to type | `deg`, and hints for `º` and `˚`. |
| Carets misalign under wide characters in captions | Stated. Columns count code points; only tabs are copied. |
| The traditional crane source copies a book's captions | Its captions are our own words, with provenance in `examples/README.md`, checked in review of A5's PR. |

## Open questions for the owner

From the owner decisions in [decisions §9](decisions.md#9-owner-decisions), which
[10 §6](10-roadmap-risks-questions.md#6-owner-decisions) tracks:

1. **The extension and the words "sequence source"** (decision 1). Every example here
   uses `.foldseq`.
2. **The near-miss band** (decision 2). It is the number quoted when a typed coordinate
   is refused for lying close to a vertex without being on it.
3. **`rotate k/8 turn` or `sheet square as diamond`** (decision 10). The second adds
   `as diamond` to the `sheet` line. Until it is decided, a diamond start is a first
   step, because a header holds no move.
4. **The blintz direction** (decision 8). It decides whether the blintz example says
   `behind`.
5. **Whether `quarter-fold-steps.fold` moves to the state rule** (decision 9), the
   rule for which assignment a written frame gives a crease
   ([glossary-additions](glossary-additions.md#the-fold-format)). It decides which
   fixture the first example is checked against.

## Research links

- [C — renderers, CLI and formats](research/C-renderers-cli-formats.md): "(c) CLI verb
  structure", "(d) A new input format becomes a Frame and stops there", "(e) Dependencies".
- [F — Haskell embedding techniques](research/F-haskell-edsl-techniques.md): "D. Parsing
  the text syntax", "E. Round-trips".
- [E1 — prior art](research/E1-prior-art-sequence-languages.md): "A. Languages and
  programs for diagrams". Doodle's `[a, b]` segments are borrowed as an idea only,
  since Doodle is GPLv2.
- [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md):
  "B. Signatures, checked by hand".
- [gap-layer-selective-folds](research/gap-layer-selective-folds.md): "Re-deriving
  CraneWing by rule (script)".
