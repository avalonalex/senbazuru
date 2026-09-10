# AGENTS.md

Working notes for senbazuru. Read this before changing code.

This is the shared source of project instructions for Codex and Claude Code.
`CLAUDE.md` imports this file; edit shared rules here. For setup and handoffs,
see [docs/agent-workflow.md](docs/agent-workflow.md).

## What this project is

Senbazuru renders [FOLD files](https://github.com/edemaine/FOLD) as SVG, in the
visual style of step-by-step origami instruction books, and is growing the
tools to author and manipulate FOLD files for origami design.

It is also a deliberate learning project. Optimise for **clarity over
cleverness** — if a fold-heavy point-free one-liner and an explicit recursive
function are equally correct, write the explicit one.

## Audience and tone

Write for a programmer who is comfortable with intermediate Haskell —
typeclasses, monads, `Maybe`/`Either`, records, `newtype` — but who has **never
worked on computational geometry or origami**. That means:

- Assume no geometry background. Say why the y axis gets flipped; do not assume
  "obviously we flip y".
- Assume no origami background. Define domain words (mountain, valley, crease
  pattern, folded form) the first time a module uses them, or link
  [the glossary](docs/glossary.md).
- Explain a Haskell technique when it is doing real design work (`parse, don't
  validate`, phantom-free `newtype` ids, property vs. golden tests). Do not
  explain what a `Functor` is.
- Prefer explaining **why** a decision was made over **what** the code does.
  The code already says what it does.

Haddock module headers are the main place this lives, and **the header is the
record**. A module header should answer: what is this for, why does it exist
as a separate module, and what is the non-obvious thing a newcomer would get
wrong here. This file points at headers; it does not copy them.

### Writing an explanation

Every rule below was earned by getting it wrong in this repo.

- **Start from what the reader has and build.** A paragraph that only parses
  once you already know the answer is notes to yourself, not an explanation.
- **Define every term on first use, or link the glossary.** Prefer the
  glossary: a word defined in four notes will be defined four different ways
  within a year.
- **Prefer the plain word.** "A curved surface in a space with one dimension per
  crease" beats "a variety".
- **Concrete before abstract.** Three lines of real coordinates do more work
  than a paragraph about projection, and the numbers in them come from a
  command that was actually run.
- **Name the line that looks like a typo** before the reader reaches it. The
  asymmetric sign in `fitBox`'s offset and `M[parent] · R_flat` in the folding
  algorithm both read as mistakes and are both correct; saying so is most of the
  value of the surrounding text.
- **If an example can be misread, fix the example.** A clarifying sentence
  nearby does not work.

Before merging any doc, reread it as someone who knows Haskell and has never
folded anything. Every word you would have to look up must be in the glossary
or defined on the spot; every step you would have to take on faith needs its
reason given.

## Commands

```bash
stack build                 # build library + executable
stack test                  # build everything and run the test suite
stack run -- render examples/unit-square.fold -o out.svg
stack run -- render examples/crane.fold --fold --rotate 180 -o crane.svg
stack run -- render examples/squaretwist.fold --view iso -o out.svg
stack run -- export examples/crane.fold --fold -o crane.glb
stack run -- info examples/squaretwist.fold
stack run -- check examples/crane.fold
stack run -- crease examples/quarter-fold.fold --from 0,0 --to 1,1 --valley -o creased.fold
stack run -- crease examples/diagonal-cp.fold --folded --from 0,0.5 --to 0.5,0 --valley
stack ghci senbazuru:lib    # REPL with the library loaded

make fmt                    # ormolu, in place
make lint                   # hlint
make check                  # fmt-check + lint + test, i.e. what CI runs
```

The toolchain is Stack with snapshot `lts-22.44` (GHC 9.6.7), and `stack.yaml`
sets `system-ghc: true` so it reuses the ghcup-installed compiler. On a GHC
version mismatch, `ghcup install ghc 9.6.7` or delete that line.

## Architecture

The pipeline, what each module holds, and which module may know about which:
[docs/architecture.md](docs/architecture.md). **Read it before adding a module
or moving code between them.** What must not drift is the direction: one flow,
no cycles, geometry at the bottom knowing nothing about paper, and paper
knowing nothing about drawing.

## Docs

| Where | What |
| --- | --- |
| Haddock module headers | Why a module exists and what a newcomer would get wrong in it. The primary place explanation lives. |
| `README.md` | What the tool is, in one page, for someone who has just found it. |
| `docs/tour.md` | Every feature at length, with the command and the reasoning. |
| `docs/usage.md` | Building it, running it, and every flag. |
| `docs/architecture.md` | The module map and the layering rules. |
| `docs/fold-primer.md` | The domain, for someone new to origami and geometry. |
| `docs/glossary.md` | Every term the docs and code assume. The one place a definition lives. |
| `docs/fold-reference.md` | Every FOLD key, its type, and our support status. |
| `docs/related-projects.md` | The other tools in this space, their licences, and what each one means for us. |
| `docs/roadmap.md` | Where the project stands, dated: what is done, what is open, how hard each open issue is, and an order. |
| `docs/notes/` | Background and direction. **One idea per file**, a few minutes to read, with references. |

When you learn something worth keeping — a theorem, an algorithm, a technique,
a measurement — add a note to `docs/notes/` and link it from that directory's
`README.md`. Keep it to one idea; a note that needs two headings is two notes.
This is the same material as a PR's "Interesting bits" section, promoted to
somewhere findable.

**Deliberate omissions are recorded next to the feature**, in `docs/usage.md`
and `docs/tour.md`, with unsupported keys in `docs/fold-reference.md` and the
things that are not on the roadmap in the README. Before fixing a limitation as
a bug, check there and `gh issue list`; most of them are decisions with a
reason written down.

## Third-party material

senbazuru is MIT. Anything vendored into this repo must be compatible with that,
and its provenance goes in `examples/README.md`.

**Reference implementations in this space are often GPL-licensed.** Read them to
understand the domain and never copy from them. That applies to test data as
much as to source: fixture files are part of the licensed work. The line is
expression versus idea. "They propagate fold transforms over a spanning tree of
the face graph" is an idea, and reimplementing it from understanding is fine —
so are published theorems and standard terminology. Their functions are
expression, and those stay where they are.

| Source | Licence | Use |
| --- | --- | --- |
| `edemaine/FOLD` examples | MIT | vendored, attributed in `examples/README.md` |
| Oriedita | MIT | `birdbase.cp` vendored as `examples/bird-base.cp`; its source is readable for the `.cp` format, but reimplement |
| Origami Simulator box-pleat `.fold` | MIT | usable with attribution |
| Flat-Folder examples | MIT | traditional models, the author's own designs and exhaustive enumerations vendored; other designers' patterns there are not ours to take |
| GPL reference implementations | GPL-3.0 | research only, never vendored |
| Patterns we generate ourselves | ours | preferred |

**A repository licence is not a design licence.** A crease pattern for an
original model is its designer's creative work, and an MIT repo that happens to
contain one does not clearly grant rights to the design. Prefer procedurally
generated patterns (Miura-ori, pleats, box-pleat tessellations) and traditional
bases, which have no single author.

## Conventions

Each of these has its argument written out somewhere else; the pointer says
where. Do not restate the argument here.

**Errors are values.** Return `Either SomeError a`. Do not throw, do not
`error`, do not use partial functions (`head`, `fromJust`, `!!`) in library
code. Error types carry enough context to point at the offending element —
"invalid FOLD file" is useless to someone holding a 4000-line crease pattern.

**Every error type has an `Explain` instance, and that is where its words
live.** One class, one method, in `Senbazuru.Explain`. **The compiler does not
enforce this** — a class demands an instance only where `explain` is called —
so a type nothing prints today gets an instance anyway, because it is one
`Left` away from being printed and the alternative is `show`. `num` is for a
quantity we measured; `tshow` is for an id, a count, or a number the *reader*
gave us. The header of `Senbazuru.Explain` has the rest.

**Two unit systems, never mixed.** Shape *coordinates* are in model units;
stroke *widths, dash lengths and displacements* are in page units and are never
scaled. `Arrow`, `Label` and `Offset` need both and are finished by the backend
after projection. Header of `Senbazuru.Diagram`; #63 tracks making it a type
error.

**Types mirror the format; validation is separate.** `Senbazuru.Fold.Types` is
permissive because FOLD is permissive; a decode failure must always mean "this
is not FOLD", never "this is FOLD we do not support yet". Refinement happens in
`Senbazuru.Fold.Query`.

**Preserve at the boundary, discard at the transform.** Unknown keys are
collected into `frameExtras` and written back, so a file survives a trip with
another tool's data intact; anything that *changes* a frame drops them, because
it cannot judge them. **Absent is not empty**: the writer leaves out every
`Nothing`, every empty list and a `frame_inherit` of `False`, because writing
`[]` is a claim the file did not make. `docs/notes/round-trips.md`. That
`frameExtras` is dropped too widely, taking the *file's* keys with the
frame's, is #73.

**A new input format becomes a `Frame` and stops there.** `Senbazuru.Import.*`
hands back a frame that says only what the file said; nothing downstream may
know a frame came from anywhere but a `.fold`. `Senbazuru.Fold.Load` picks the
reader from the extension.

**Faces are the creases read another way, and one function rebuilds them.**
Most files record none. Anything needing paper rather than lines calls
`Fold.Crossings.withPlanarFaces` — cut every crossing, then trace — rather than
refusing, and calls that one function rather than the two halves, because a
policy spelled out per backend is a policy the next backend forgets.
`Render.CreasePattern` deliberately does neither: a drawing must not stop
working because its faces cannot be worked out.

**A move that changes a pattern hands the result back to what validates a read
one.** `Fold.Creasing` adds creases and then calls `withPlanarFaces`, so a
creased pattern is cut, traced and refused by exactly the code that handles one
from a file. A move must drop what it invalidates (`faces_vertices`,
`faceOrders`, `frameExtras`), and creases are drawn in **batches**
(`creaseAllAlong`), because the handing back is the cost and doing it per crease
is cubic. Header of `Senbazuru.Fold.Creasing`.

**New backends consume `Diagram`, with one exception.** `Diagram` is 2D, so
`Render.Gltf` reads `Fold.Query`'s faces directly — a stated exception, not a
precedent. It must not import `Render.CreasePattern`; the policy both share,
which layer order to use, is `Origami.Stacking.layerOrderFor`. **`--layer-budget`
is a parameter of every entry point** — `creasePatternFrom`,
`creasePatternAuto`, `stepPage` and `renderGlb` — because it was a CLI flag that
did nothing on `render` for exactly as long as it was not.

**Do the geometry in Haskell, not in SVG attributes.** We never emit
`<g transform="scale(...)">`: it scales stroke widths too, and arithmetic hidden
in an attribute string cannot be property-tested.

**Style.** Formatting is whatever `ormolu` produces — run `make fmt`. `hlint`
must be clean. Warnings in `senbazuru.cabal`'s `common warnings` stanza apply
everywhere; keep the build warning-free. Extensions are set once in the cabal
file on top of `GHC2021`; prefer adding there over per-module pragmas.

Two things no tool enforces, which is why they are here:

- **`stack build --ghc-options=-fforce-recomp` does not show you the warnings.**
  Stack decides whether to invoke GHC at all from a hash of the source and the
  flags, so `touch` changes nothing and a second run with the same flags
  rebuilds nothing and prints nothing, which looks exactly like a clean build.
  `stack clean && stack build --test` is the check that is actually a check,
  and it is what CI does from cold.
- **Do not name a binding `pattern`.** `hlint`'s parser reads it as the
  `PatternSynonyms` keyword whether or not the extension is on, so it compiles
  under GHC and fails `make lint` with a parse error. `paper` or `sheet` says
  the same thing.

The ormolu version is **pinned in `.github/workflows/ci.yml`** (`ORMOLU_VERSION`,
currently `0.7.2.0`) and must match the one on your `PATH`, because ormolu
changes its output between releases. To upgrade: bump `ORMOLU_VERSION` *and*
`ORMOLU_ASSET`, install the same version locally, and run `make fmt` — all in a
commit that does nothing else.

## Testing

Three kinds, used for different things:

- **Property tests** (`Senbazuru.GeometrySpec` and the other geometry specs)
  for the geometry layer, where the rules are easy to state and the interesting
  failures are at awkward inputs a human would not think to write down.
- **Example tests** (`Senbazuru.Fold.TypesSpec`) for decoding, with cases drawn
  from *real* `.fold` files rather than from the spec — the things that break
  decoders are the things the spec permits without drawing attention to.
- **Golden tests** (`Senbazuru.Render.SvgSpec`, `GltfSpec`) for whole-document
  output.

To update a golden file after an intentional change: run `stack test`, read the
diff it prints, and if the new output is right, `mv test/golden/X.actual.svg
test/golden/X.svg`. **Never accept a golden diff you have not read.** A `.glb`
golden is opaque to a text diff, so its failure names the first byte that
differs — inside the JSON chunk is a change of document, inside the binary
chunk a change of geometry — and `cmp -l` shows the rest.

Anything that generates SVG goes through `formatNumber`, which keeps output
byte-for-byte reproducible: no scientific notation, no trailing zeros, no
negative zero.

**Measure, do not reason about, performance.** `stack build --profile` and
`+RTS -p`. A GHCi timing has misled twice, because the interpreter does not do
the optimisations a compiled build does; the header of
`Senbazuru.Origami.Stacking` has the numbers.

## Domain glossary

[`docs/glossary.md`](docs/glossary.md) — origami, FOLD, geometry, graph and
project terms in one place, so there is one copy to keep true.

## Gotchas

The rules that cross module boundaries, which is why they are here rather than
in one header. Everything local to one module is in that module's header, and
the header carries the argument: `Fold.Crossings` for cutting,
`Origami.FlatFold` for dissolving `F` and `J` before any theorem,
`Render.CreasePattern` for the offset view's painting rules, `Import.*` and
`docs/notes/cp-and-opx.md` for the segment formats and what editors actually
write.

- **The file's shape.** FOLD's top-level object is both the file metadata and
  the first frame; the decoder splits them. Ids are array indices, zero-based.
  Parallel arrays are not guaranteed to line up. Coordinates may be 2D or 3D:
  `frameVertices` returns `V3`, and projection is the camera's job.
  `docs/fold-primer.md`, `docs/fold-reference.md`.
- **A folded model's state is its fold angles, not its vertex positions.**
  Positions are derived by `Origami.Folding`; never interpolate positions to
  show a half-folded state, that stretches the paper. A spanning tree cuts every
  loop, and closing them takes **two** checks — comparing shared vertices
  (`TornAt`) and asking whether each crease's own angle is achieved
  (`loopsClose`), because a loop closed by turning nothing leaves every shared
  vertex agreeing. Anything else walking the face graph needs both.
  `docs/notes/folding-by-transforms.md`.
- **A fold's transforms are against the *cut* pattern.** `foldFrameWith` hands
  back the folded form, that pattern and one `Rigid` per face, keyed by the
  frame that came *out* of cutting; the frame that went in numbers the faces of
  a different drawing. Write back onto `foldedPattern`.
- **At ±180° a mountain and a valley are the same rigid motion.** Folding cannot
  tell them apart; the assignment survives only as layer ordering.
  `Origami.Folding.creaseIndex`.
- **Face winding is trusted exactly as written wherever the layer order is
  read** — `Origami.Layers`, `Origami.Flat`, `Origami.Stacking`, `Render.Gltf` —
  because `faceOrders` signs were written against the same winding and the two
  cancel. Only `foldFrame` re-winds, and it must then re-sign every order whose
  *second* face it turned round (`Folding.reorient`; missing that was #78).
  A traced winding (`Fold.Faces`) can be trusted. Which *side* of the paper a
  region shows (`Origami.Visible`) reads the winding a third time with nothing
  to cancel against, so a backwards-wound file draws its colours swapped, on
  the page and in the `.glb` alike, and nothing in the file can say so.
- **Three y-flips, each in one place.** Model y is up and SVG y is down
  (`Geometry`). `.cp` and `.opx` store screen coordinates, so
  `Import.Segments.fromScreenPoint` negates y — a correction, not a convention;
  Oriedita's own FOLD export does not, so its export and our reading are mirror
  images. glTF is y-up and `Render.Gltf` maps `(x, y, z)` to `(x, z, -y)`, a
  quarter turn; `(x, z, y)` would be a reflection. A wrong flip folds perfectly
  well and is the mirror model.
- **The `Fill` contract.** Abutting fills of one colour are one `Fill`, because
  two shapes sharing an edge antialias into a pale seam. Rings add up by the
  nonzero rule, so `Render.Svg` turns every ring anticlockwise on the way out.
  Header of `Senbazuru.Diagram`.
- **A layer order is not a painting order, and a stacking is not a drawing
  order.** SVG paints in document order. A twist's flaps stack in a circle with
  no order to paint them in, so a flat model is drawn by visible regions
  (`Origami.Visible`) and `paintOrder` remains for paper in the air. Whether a
  face is *nearer* depends on which way its normal points relative to the
  viewer; miss it and a model seen from behind comes out inside out.
  `Origami.Layers`.
- **Two facts about rings that bite elsewhere.** A ring can carry an edge of no
  length, wherever folding brought two corners together; anything asking which
  side of an edge a point is on has to skip it. And a stretch lying along a
  face's edge is judged by `Geometry.Polygon.distanceOutside` at its midpoint,
  never by clipping, which has no tolerance to call a hair inside and a hair
  outside the same answer.
- **`-0.0 == 0.0` is `True`** but they format differently, and a y-flip makes
  them. `formatNumber` normalises; `Render.Gltf` rounds through an `Integer`,
  which has no sign to keep.
- **Creasing is about faces, not the sheet.** A crease's end has to meet
  something, and that is a question about the drawing — the argument is in
  `Fold.Creasing`'s header; do not restate it. Through the layers, the test is
  whether an end is inside a *face*, never inside the model. Alternate layers
  lie upside down, so one kind asked for writes both (M, V, M, V), and which
  way up a face lies is `M · ẑ`, not the winding.
  `docs/notes/creasing-through-layers.md`.
- **A page of steps has one camera and one scale**, chosen from every frame
  together, and each figure keeps its own size, so folding visibly shrinks the
  paper. A step is a subtraction of *positions*, not of angles, and its arrow
  goes on the frame before the fold. `Render.Steps`, `Diagram.Layout`,
  `Origami.Step`.
- **A model usually has several valid layer orders**, a product over
  components; `componentCount` is ours plus one to match Flat-Folder's
  published figures. A different order is usually the same picture, so test
  `--stacking` by comparing `faceOrders`, or on the crane, whose states 0 and 3
  differ. `docs/notes/several-stackings.md`.

## Workflow

When switching agents, stop the previous session before the next edits the same
checkout. For concurrent work, use a separate branch and Git worktree (a separate
working directory) per task. Check `git status` and the current branch before
editing; preserve changes you did not make. At handoff, report the branch,
issue or PR, changes made, checks run and their results, and remaining work.
Record lasting decisions in the repository so the next tool can find them.

`main` is protected. Changes reach it through pull requests, and all three CI
checks must be green before merge. Do not push to `main` directly.

```bash
git switch -c feat/fold-arrows     # feat/ fix/ docs/ chore/ test/
# work; commit as you go
git push -u origin HEAD
gh pr create --fill                # then fill in the three sections
```

Issues track work before it starts, using the templates in
`.github/ISSUE_TEMPLATE/`: **Task** for a piece of work, **Bug** for something
that renders wrong, crashes, or rejects a valid file, **Study note** for
something to understand and write up in `docs/notes/`. The README roadmap items
each have an issue carrying the `roadmap` label; the README list is the map,
the issue holds the approach and the acceptance criteria, and adding a roadmap
item means editing both. Reference the issue from the PR body (`Closes #12`).

Merges are squash-only and history is linear, so the squashed commit message is
what survives — write it as carefully as the PR description. Commit messages:
imperative subject under ~72 characters, body explaining why.

## Pull requests

Keep PRs small and single-purpose — one idea per PR, the same rule as
`docs/notes/`. Every PR description must contain these three sections, and all
of them must be **succinct** — a few sentences or a short list each:

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
