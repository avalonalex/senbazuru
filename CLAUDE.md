# CLAUDE.md

Working notes for senbazuru. Read this before changing code.

## What this project is

Senbazuru renders [FOLD files](https://github.com/edemaine/FOLD) as SVG, in the
visual style of step-by-step origami instruction books. Longer term it may grow
tools for authoring and manipulating FOLD files for origami design.

It is also a deliberate learning project. Optimise for **clarity over
cleverness** — if a fold-heavy point-free one-liner and an explicit recursive
function are equally correct, write the explicit one.

## Audience and tone

Write for a programmer who is comfortable with intermediate Haskell — typeclasses,
monads, `Maybe`/`Either`, records, `newtype` — but who has **never worked on
computational geometry or origami**. That means:

- Assume no geometry background. Say why the y axis gets flipped; do not assume
  "obviously we flip y".
- Assume no origami background. Define domain words (mountain, valley, crease
  pattern, folded form) the first time a module uses them.
- Do explain a Haskell technique when it is doing real design work
  (`parse, don't validate`, phantom-free `newtype` ids, property vs. golden
  tests). Do not explain what a `Functor` is.
- Prefer explaining **why** a decision was made over **what** the code does. The
  code already says what it does.

Haddock module headers are the main place this lives. A module header should
answer: what is this for, why does it exist as a separate module, and what is
the non-obvious thing a newcomer would get wrong here.

## Commands

```bash
stack build                 # build library + executable
stack test                  # build everything and run the test suite
stack run -- render examples/unit-square.fold -o out.svg
stack run -- info examples/squaretwist.fold
stack ghci senbazuru:lib    # REPL with the library loaded

make fmt                    # ormolu, in place
make lint                   # hlint
make check                  # fmt-check + lint + test, i.e. what CI should run
```

The toolchain is Stack with snapshot `lts-22.44` (GHC 9.6.7), and `stack.yaml`
sets `system-ghc: true` so it reuses the ghcup-installed compiler. If you get a
GHC version mismatch, either `ghcup install ghc 9.6.7` or delete that line.

## Architecture

One direction of flow, no cycles:

```
 .fold bytes
     |  Senbazuru.Fold.Load          I/O boundary: read + decode, errors as values
     v
 FoldFile / Frame                    Senbazuru.Fold.Types
     |                               a faithful, permissive mirror of the format
     |  Senbazuru.Fold.Query         validate + refine: indices become real points
     v
 [Crease]                            geometry that cannot be structurally wrong
     |  Senbazuru.Render.CreasePattern
     |  + Senbazuru.Diagram.Style    origami line conventions
     v
 Diagram                             Senbazuru.Diagram
     |                               backend-independent: shapes + strokes
     |  Senbazuru.Render.Svg         + Senbazuru.Geometry for the page transform
     v
 SVG text
```

| Module | Holds |
| --- | --- |
| `Senbazuru.Geometry` | `V2`, `Box`, `Transform`. No FOLD, no SVG. |
| `Senbazuru.Fold.Types` | The FOLD document model and its JSON instances. |
| `Senbazuru.Fold.Load` | The only I/O in the library. |
| `Senbazuru.Fold.Query` | Validation and refinement of a `Frame`. |
| `Senbazuru.Diagram` | The drawing IR: `Shape`, `Stroke`, `Diagram`. |
| `Senbazuru.Diagram.Style` | Every decision about how diagrams *look*. |
| `Senbazuru.Render.CreasePattern` | FOLD frame → `Diagram`. |
| `Senbazuru.Render.Svg` | `Diagram` → SVG text. |
| `Senbazuru.Cli` (in `app/`) | Flag parsing. Not part of the library. |

### Layering rules

- `Senbazuru.Geometry` depends on nothing in the project. Keep it that way.
- `Senbazuru.Diagram` must not know what FOLD is.
- `Senbazuru.Render.Svg` must not know what a mountain fold is.
- Only `Senbazuru.Fold.Load` does I/O. Everything else takes and returns values,
  which is what makes the rest testable without a filesystem.
- New output backends (PDF, PNG) become new consumers of `Diagram`, never a
  second traversal of `Frame`.

## Conventions

**Errors are values.** Return `Either SomeError a`. Do not throw, do not `error`,
do not use partial functions (`head`, `fromJust`, `!!`) in library code. Error
types carry enough context to point at the offending element — "invalid FOLD
file" is useless to someone holding a 4000-line crease pattern.

**Two unit systems, never mixed.** Shape *coordinates* are in model units (from
the FOLD file). Stroke *widths and dash lengths* are in page units and are never
scaled. A crease line is ~1pt wide whether the paper is 1 unit or 400 units
across. See the header of `Senbazuru.Diagram`.

**Do the geometry in Haskell, not in SVG attributes.** We never emit
`<g transform="scale(...)">`, because that scales stroke widths too, and because
arithmetic hidden in an attribute string cannot be property-tested.

**Types mirror the format; validation is separate.** `Senbazuru.Fold.Types` is
permissive because FOLD is permissive. A decode failure must always mean "this
is not FOLD", never "this is FOLD we do not support yet". Refinement happens in
`Senbazuru.Fold.Query`.

**Style.** Formatting is whatever `ormolu` produces — do not argue with it, run
`make fmt`. `hlint` must be clean. Warnings in `senbazuru.cabal`'s `common
warnings` stanza apply everywhere; keep the build warning-free.

**Extensions** are set once in the cabal file (`DerivingStrategies`,
`LambdaCase`, `OverloadedStrings`, `RecordWildCards`) on top of `GHC2021`.
Prefer adding to that list over per-module `LANGUAGE` pragmas.

## Testing

Three kinds, used for different things:

- **Property tests** (`Senbazuru.GeometrySpec`) for the geometry layer, where
  the rules are easy to state and the interesting failures are at awkward inputs
  a human would not think to write down.
- **Example tests** (`Senbazuru.Fold.TypesSpec`) for decoding, with cases drawn
  from *real* `.fold` files rather than from the spec — the things that actually
  break decoders are the things the spec permits without drawing attention to.
- **Golden tests** (`Senbazuru.Render.SvgSpec`) for whole-document output.

To update a golden file after an intentional change: run `stack test`, read the
diff it prints, and if the new output is right, `mv test/golden/X.actual.svg
test/golden/X.svg`. Never accept a golden diff you have not read.

Anything that generates SVG must go through `formatNumber`, which is what keeps
output byte-for-byte reproducible (no scientific notation, no trailing zeros, no
negative zero).

## Domain glossary

| Term | Meaning |
| --- | --- |
| **Crease pattern** | The flat, unfolded sheet with all creases marked. Coordinates are already page coordinates — nothing to simulate. |
| **Folded form** | The same graph with vertices moved to where they end up after folding, usually in 3D. |
| **Mountain fold** (`M`) | Crease that rises towards the viewer. Drawn dash-dot-dot. |
| **Valley fold** (`V`) | Crease that sinks away from the viewer. Drawn dashed. |
| **Border** (`B`) | Edge of the paper, not a fold. Drawn solid. |
| **Flat** (`F`) | A crease line that is not folded (angle 0). |
| **Unassigned** (`U`) | A crease whose direction is not yet decided. |
| **Cut** (`C`) / **Join** (`J`) | A slit in the paper / two faces that are really one piece. |
| **Fold angle** | Dihedral angle in degrees, `[-180, 180]`. Negative is mountain, positive is valley. |
| **Frame** | One state of the paper. A multi-frame FOLD file is how a diagram sequence is stored. |
| **Yoshizawa–Randlett** | The standard origami diagram notation. The line vocabulary is documented in `Senbazuru.Diagram.Style`. |
| **Assignment colour convention** | The *other* convention, used by on-screen crease-pattern editors: red mountains, blue valleys, uniform weight. We target the printed-book line vocabulary instead; see `Senbazuru.Diagram.Style`. |
| **Face ordering** | Which sheet of paper is on top where. Needed for folded forms; not implemented yet. |

## Gotchas

- **FOLD's top-level object is both the file metadata and the first frame.** The
  decoder splits them; nothing downstream should have to remember this.
- **Ids are array indices, zero-based.** There is no `"id"` field anywhere. An
  edge is `edges_vertices[i]`, its assignment is `edges_assignment[i]`.
- **Parallel arrays are not guaranteed to line up.** Check lengths.
- **Coordinates may be 2D or 3D.** `frameVertices` drops z, which is correct for
  a crease pattern and an orthographic top view for a folded form. A top view of
  a folded model is *not* a correct picture of it.
- **Real files carry vendor keys** like `"cpedit:page"`. Ignore unknown keys.
- **`file_spec` is a number, not an integer.** Real files say `1.1`.
- **Model y is up, SVG y is down.** Every model→page transform flips y.
- **SVG paints in document order**, so later shapes cover earlier ones. See
  `paintOrder` in `Senbazuru.Render.CreasePattern`.
- **`-0.0 == 0.0` is `True`** but they format differently. A y-flip produces
  negative zeros. `formatNumber` normalises them.

## Not implemented yet

Deliberate omissions, so nobody thinks they are bugs:

- Frame inheritance (`frame_inherit` / `frame_parent`) is decoded but not resolved.
- `faceOrders` / `edgeOrders` are not decoded at all.
- No face filling, so folded forms render as wireframes.
- No fold arrows, which is the main thing standing between this and a real
  step-by-step diagram.
- No FOLD *output* (`ToJSON`), which the authoring-tools goal will need.

## Pull requests

Keep PRs small and single-purpose. Every PR description must contain these three
sections, and all of them must be **succinct** — a few sentences or a short list
each, not an essay:

```markdown
## Why this way

The design choice and the alternative it was chosen over. Not a restatement of
what the code does.

## How this is verified

The specific evidence. Name the tests, and say what was checked by hand and how.
"Added tests" is not an answer; "property test that every point in the source box
lands on the page, plus a golden test on two fixtures" is.

## Interesting bits

A short list of things the PR ran into that were worth knowing — a Haskell
technique that did real work, or a fact about origami or geometry that would
surprise someone meeting it for the first time. This is a learning project; this
section is where that gets banked.

Keep it to things this PR actually touched. Signed zero mattering to golden
files is a good entry. "Haskell has typeclasses" is not.
```

Commit messages: imperative subject under ~72 characters, body explaining why.
