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

### Writing an explanation

Every rule below was earned by getting it wrong in this repo.

- **Start from what the reader has and build.** Do not join the argument
  halfway. A paragraph that only parses once you already know the answer is
  notes to yourself, not an explanation.
- **Define every term on first use, or link
  [the glossary](docs/glossary.md).** Prefer the glossary: a word defined in
  four notes will be defined four different ways within a year. A note that
  assumes vocabulary should say so in its first lines and link.
- **Prefer the plain word.** "A curved surface in a space with one dimension per
  crease" beats "a variety" — six words longer, no glossary entry needed, and
  the reader keeps moving.
- **Concrete before abstract.** Three lines of real coordinates do more work
  than a paragraph about projection. Worked examples are not padding, and
  numbers in them should come from a command that was actually run.
- **Name the line that looks like a typo** before the reader reaches it. The
  asymmetric sign in `fitBox`'s offset and `M[parent] · R_flat` in the folding
  algorithm both read as mistakes and are both correct; saying so is most of the
  value of the surrounding text.
- **If an example can be misread, fix the example.** A clarifying sentence
  nearby does not work. `fold-primer.md` stated "ids are indices" directly above
  an example that looked like coordinates, and readers believed the example.

**Before merging any doc**, reread it as someone who knows Haskell and has never
folded anything. Every word you would have to look up must be in the glossary or
defined on the spot; every step you would have to take on faith needs its reason
given.

## Commands

```bash
stack build                 # build library + executable
stack test                  # build everything and run the test suite
stack run -- render examples/unit-square.fold -o out.svg
stack run -- render examples/squaretwist.fold --view iso -o out.svg
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
 [Crease]                            3D geometry that cannot be structurally wrong
     |                               |
     |                               +--> Senbazuru.Origami.FlatFold
     |                               |    origami knowledge, no drawing: is this
     |                               |    pattern locally impossible to fold?
     |                               +--> Senbazuru.Origami.Folding
     |                               |    fold it: a Frame in, a folded Frame
     |                               |    out, straight back into this pipeline
     |                               +--> Senbazuru.Origami.Layers
     |                               |    which face is in front, given where
     |                               |    the viewer is standing
     |                               +--> Senbazuru.Origami.Step
     |                                    subtract two frames: which paper moved
     |                                    and where it went, i.e. the arrow
     |  Senbazuru.Render.CreasePattern
     |  + Senbazuru.Render.Camera    orthographic projection to the page
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
| `Senbazuru.Geometry.VectorSpace` | The arithmetic 2D and 3D points share. |
| `Senbazuru.Geometry.V3` | Points in space, the cross product, and whether a set of points is flat. |
| `Senbazuru.Geometry.Rigid` | 3×3 matrices and motions that turn and slide but never deform. |
| `Senbazuru.Fold.Types` | The FOLD document model and its JSON instances. |
| `Senbazuru.Fold.Load` | The only I/O in the library. |
| `Senbazuru.Fold.Query` | Validation and refinement of a `Frame`: `Crease`, `Face`. |
| `Senbazuru.Diagram` | The drawing IR: `Shape`, `Stroke`, `Diagram`. |
| `Senbazuru.Diagram.Style` | Every decision about how diagrams *look*. |
| `Senbazuru.Diagram.Layout` | Several figures on one page, at one shared scale. |
| `Senbazuru.Origami.FlatFold` | Maekawa's and Kawasaki's theorems, vertex by vertex. |
| `Senbazuru.Origami.Folding` | Crease pattern + fold angles → folded form. |
| `Senbazuru.Origami.Layers` | `faceOrders` + a viewing direction → an order to draw in. |
| `Senbazuru.Origami.Step` | Two frames → what moved between them. |
| `Senbazuru.Render.Camera` | Orthographic projection: 3D → the page. |
| `Senbazuru.Render.CreasePattern` | FOLD frame → `Diagram`, and which view to use. |
| `Senbazuru.Render.Svg` | `Diagram` → SVG text. |
| `Senbazuru.Cli` (in `app/`) | Flag parsing. Not part of the library. |

### Layering rules

- `Senbazuru.Geometry` depends on nothing in the project. Keep it that way.
- `Senbazuru.Diagram` must not know what FOLD is.
- `Senbazuru.Origami.*` is what senbazuru knows about paper, as opposed to what
  it knows about drawing. Nothing in it may mention a diagram, a page or a
  colour; it is a second consumer of `Fold.Query`, not a stage on the way to
  SVG.
- `Senbazuru.Render.Svg` must not know what a mountain fold is.
- Only `Senbazuru.Fold.Load` does I/O. Everything else takes and returns values,
  which is what makes the rest testable without a filesystem.
- New output backends (PDF, PNG) become new consumers of `Diagram`, never a
  second traversal of `Frame`.

## Docs

| Where | What |
| --- | --- |
| Haddock module headers | Why a module exists and what a newcomer would get wrong in it. The primary place explanation lives. |
| `README.md` | What the tool is and how to run it. |
| `docs/fold-primer.md` | The domain, for someone new to origami and geometry. |
| `docs/glossary.md` | Every term the docs and code assume. The one place a definition lives. |
| `docs/fold-reference.md` | Every FOLD key, its type, and our support status. |
| `docs/notes/` | Background and direction. **One idea per file**, a few minutes to read, with references. |

How to write these is in [Writing an explanation](#writing-an-explanation).

When you learn something worth keeping — a theorem, an algorithm, a technique —
add a note to `docs/notes/` and link it from that directory's `README.md`. Keep
it to one idea; a note that needs two headings is two notes. This is the same
material as a PR's "Interesting bits" section, promoted to somewhere findable.

## Third-party material

senbazuru is MIT. Anything vendored into this repo must be compatible with that,
and its provenance goes in `examples/README.md`.

**Reference implementations in this space are often GPL-licensed.** Read them to
understand the domain and never copy from them. That applies to test data as
much as to source: fixture files are part of the licensed work.

The line is expression versus idea. "They propagate fold transforms over a
spanning tree of the face graph" is an idea, and reimplementing it from
understanding is fine — so are published theorems and standard terminology,
which belong to the literature rather than to any implementation. Their
functions are expression, and those stay where they are.

| Source | Licence | Use |
| --- | --- | --- |
| `edemaine/FOLD` examples | MIT | vendored, attributed in `examples/README.md` |
| Origami Simulator box-pleat `.fold` | MIT | usable with attribution |
| GPL reference implementations | GPL-3.0 | research only, never vendored |
| Patterns we generate ourselves | ours | preferred |

One further trap: **a repository licence is not a design licence.** A crease
pattern for an original model is its designer's creative work, and an MIT repo
that happens to contain one does not clearly grant rights to the design. Prefer
procedurally generated patterns (Miura-ori, pleats, box-pleat tessellations) and
traditional bases, which have no single author.

## Conventions

**Errors are values.** Return `Either SomeError a`. Do not throw, do not `error`,
do not use partial functions (`head`, `fromJust`, `!!`) in library code. Error
types carry enough context to point at the offending element — "invalid FOLD
file" is useless to someone holding a 4000-line crease pattern.

**Two unit systems, never mixed.** Shape *coordinates* are in model units (from
the FOLD file). Stroke *widths and dash lengths* are in page units and are never
scaled. A crease line is ~1pt wide whether the paper is 1 unit or 400 units
across. See the header of `Senbazuru.Diagram`.

Two shapes need both: `Arrow`'s curve is in model units and its head's size is
in page units, and `Label` is a model-space point with a page-unit type size.
Both are finished by the backend *after* projection, which is the only place
both units are in scope. The rule is what makes `Diagram.Layout` possible at
all — figures are combined by shifting their coordinates, and nothing about how
they are inked has to be recomputed.

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

The ormolu version is **pinned in `.github/workflows/ci.yml`** (`ORMOLU_VERSION`,
currently `0.7.2.0`) and must match the one on your `PATH`. Ormolu changes its
output between releases, so an unpinned formatter fails CI on a day nobody
touched the code. Check with `ormolu --version`.

To upgrade: bump `ORMOLU_VERSION` *and* `ORMOLU_ASSET` (the release asset was
renamed from `ormolu-Linux.zip` to `ormolu-x86_64-linux.zip` at 0.8.0.0),
install the same version locally, and run `make fmt` — all in a commit that does
nothing else.

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

Moved to [`docs/glossary.md`](docs/glossary.md) — origami, FOLD, geometry, graph
and project terms in one place. Kept there rather than here so that readers who
are not contributors can find it, and so there is only one copy to keep true.

## Gotchas

- **FOLD's top-level object is both the file metadata and the first frame.** The
  decoder splits them; nothing downstream should have to remember this.
- **Ids are array indices, zero-based.** There is no `"id"` field anywhere. An
  edge is `edges_vertices[i]`, its assignment is `edges_assignment[i]`.
- **Parallel arrays are not guaranteed to line up.** Check lengths.
- **Coordinates may be 2D or 3D.** `frameVertices` returns `V3` and keeps z;
  2D vertices get `z = 0`. Projection is the camera's job, in
  `Senbazuru.Render.Camera`, not the query layer's.
- **A folded model's state is its fold angles, not its vertex positions.**
  Positions are derived from angles by `Senbazuru.Origami.Folding`. A folded
  frame therefore keeps `edges_foldAngle`, and nothing should interpolate
  vertex positions to show a half-folded state — that stretches the paper.
- **A spanning tree cuts every loop, and loops are the whole constraint.**
  Folding reaches each face by one path, so it will produce coordinates for
  angles no sheet can adopt. `foldFrame` closes the loops by hand, comparing
  where each face puts a shared vertex. Anything else walking the face graph
  needs the same check or it will silently tear a model.
- **At ±180° a mountain and a valley are the same rigid motion.** Turning half a
  turn either way about a line lands in the same place. The assignment still
  matters — it decides which layer ends up on top — but that is layer ordering,
  not position, so folding cannot tell a flat mountain from a flat valley.
- **Not every line in a crease pattern folds.** `F` (flat) and `J` (join) are
  drawn but the paper is continuous across them, so anything reasoning about the
  angles around a vertex has to dissolve them first — otherwise the crease count
  is wrong, which flips the parity Maekawa's theorem depends on. `B` and `C`
  mean the paper stops, which makes the vertex a border vertex, where the
  flat-folding theorems do not apply at all.
- **A folded form is not necessarily 3D.** The traditional crane folds *flat*,
  so its folded frame lies in a plane. Choose a view from the coordinates
  (`defaultBasisFor`), never from `frame_classes`. The line notation is the one
  exception: a flat-folded form and a crease pattern have the same kind of
  coordinates, so `defaultNotationFor` asks the class, and only when the
  geometry is flat.
- **Real files carry vendor keys** like `"cpedit:page"`. Ignore unknown keys.
- **`file_spec` is a number, not an integer.** Real files say `1.1`.
- **Model y is up, SVG y is down.** Every model→page transform flips y.
- **SVG paints in document order**, so later shapes cover earlier ones. Creases
  are sorted by `creaseOrder` in `Senbazuru.Render.CreasePattern`; faces sit
  outside that ordering entirely — every fill is emitted before every line, and
  the order of the fills among themselves is
  `Senbazuru.Origami.Layers.paintOrder`.
- **Face winding is not to be trusted — except in `faceOrders`.** FOLD specifies
  counterclockwise and real files disagree. Filling does not care, and folding
  measures the winding from the coordinates. But `faceOrders`'s signs are read
  against a face's *normal*, which is *defined* by its winding, so the two were
  written against each other: a file with backwards windings has backwards
  signs, and they cancel. Recomputing the winding there would uncancel them and
  turn the model inside out. `Senbazuru.Origami.Layers` takes the file's winding
  exactly as written, and is the only place that does.
- **A page of steps shares one scale, and each figure keeps its own size.**
  `Diagram.Layout` lays figures out against the union of their extents, so a
  folded model is drawn smaller than the sheet it came from. Scaling each figure
  to fill its own cell is the tempting error: it makes folding look like it does
  not shrink the paper.
- **A step is a subtraction, and it compares positions.** FOLD records no
  arrows, so `Senbazuru.Origami.Step` works out what moved between two frames.
  It compares where the paper *is*, not `edges_foldAngle`: a frame may record no
  angles, may record ones that disagree with its own coordinates, and turning a
  model over moves paper without changing an angle at all.
- **The arrow goes on the frame before the fold**, as a printed book draws it.
  Step 2 shows the paper as it is, with the instruction for reaching step 3.
- **A stacking is not a drawing order.** `faceOrders` says a face is on the side
  another face's normal points to, which is a fact about the paper. Whether that
  is nearer the viewer depends on which way that normal points relative to them,
  and a folded model has faces pointing both ways. Miss it and models seen from
  their back face come out inside out.
- **`-0.0 == 0.0` is `True`** but they format differently. A y-flip produces
  negative zeros. `formatNumber` normalises them.

## Not implemented yet

Deliberate omissions, so nobody thinks they are bugs:

- Frame inheritance (`frame_inherit` / `frame_parent`) is decoded but not
  resolved, so every frame of a multi-frame file must repeat the whole graph.
- `edgeOrders` is not decoded at all.
- No solver for layer order. `faceOrders` is read and used when a file supplies
  one; nothing computes one, so a folded form senbazuru folded itself is drawn
  as a wireframe.
- Folding solves for positions from given angles. It does not solve for *angles*
  — there is no way to ask for a model half folded, because scaling every angle
  by a fraction generally lands on angles no paper can adopt.
- No FOLD *output* (`ToJSON`), which the authoring-tools goal will need.

## Workflow

`main` is protected. Changes reach it through pull requests, and all three CI
checks must be green before merge. Do not push to `main` directly.

```bash
git switch -c feat/fold-arrows     # feat/ fix/ docs/ chore/ test/
# work; commit as you go
git push -u origin HEAD
gh pr create --fill                # then fill in the three sections
```

Issues track work before it starts, using the templates in
`.github/ISSUE_TEMPLATE/`:

| Template | For |
| --- | --- |
| **Task** | A piece of work — a feature, a refactor, a doc |
| **Bug** | Something renders wrong, crashes, or rejects a valid file |
| **Study note** | Something to understand, then write up in `docs/notes/` |

The README roadmap items each have an issue carrying the `roadmap` label, so
`gh issue list --label roadmap` is the roadmap with its reasoning attached. The
README list stays the map — one paragraph per item, in order; the issue holds the
approach and the acceptance criteria. Adding a roadmap item means editing both.

Reference the issue from the PR body (`Closes #12`) so merging closes it.

Merges are squash-only and history is linear, so the squashed commit message is
what survives — write it as carefully as the PR description. Branches are
deleted on merge.

## Pull requests

Keep PRs small and single-purpose — one idea per PR, the same rule as
`docs/notes/`. Every PR description must contain these three sections, and all
of them must be **succinct** — a few sentences or a short list each, not an
essay:

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
