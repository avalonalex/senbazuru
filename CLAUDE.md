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
stack run -- export examples/crane.fold --fold -o crane.glb
stack run -- info examples/squaretwist.fold
stack run -- crease examples/quarter-fold.fold --from 0,0 --to 1,1 --valley -o creased.fold
stack run -- crease examples/diagonal-cp.fold --folded --from 0,0.5 --to 0.5,0 --valley
stack ghci senbazuru:lib    # REPL with the library loaded

make fmt                    # ormolu, in place
make lint                   # hlint
make check                  # fmt-check + lint + test, i.e. what CI should run
```

The toolchain is Stack with snapshot `lts-22.44` (GHC 9.6.7), and `stack.yaml`
sets `system-ghc: true` so it reuses the ghcup-installed compiler. If you get a
GHC version mismatch, either `ghcup install ghc 9.6.7` or delete that line.

## Architecture

The pipeline, what each module holds, and the layering rules about which module
may know about which: [docs/architecture.md](docs/architecture.md). **Read it
before adding a module or moving code between them.**

Kept there rather than here for the reason the glossary is — one copy to keep
true, and findable by readers who are not contributors. What must not drift is
the direction: one flow, no cycles, geometry at the bottom knowing nothing about
paper, and paper knowing nothing about drawing.

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
| Oriedita | MIT | `birdbase.cp` vendored as `examples/bird-base.cp`, attributed there; its source is readable for the `.cp` format, but reimplement |
| Origami Simulator box-pleat `.fold` | MIT | usable with attribution |
| Flat-Folder examples | MIT | traditional models, the author's own designs and exhaustive enumerations vendored, attributed in `examples/README.md`; other designers' patterns there are not ours to take |
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

Three shapes need both: `Arrow`'s curve is in model units and its head's size is
in page units, `Label` is a model-space point with a page-unit type size, and
`Offset` is a page-unit displacement wrapped round a shape whose own coordinates
are in model units. All three are finished by the backend *after* projection,
which is the only place both units are in scope. The rule is what makes
`Diagram.Layout` possible at all — figures are combined by shifting their
coordinates, and nothing about how they are inked has to be recomputed.

**New backends consume `Diagram`, with one exception.** `Diagram` is 2D, so
`Senbazuru.Render.Gltf` reads `Fold.Query`'s faces directly rather than going
through it — a stated exception, not a precedent, and the day a second 3D format
arrives is the day a 3D intermediate representation earns its place. It must
not import `Render.CreasePattern`; the policy both share, which layer order to
use, is `Origami.Stacking.layerOrderFor`.

**Creases are drawn in batches, because the handing back is the cost.** Almost
all of drawing a crease is `withPlanarFaces` afterwards — every pair of edges
compared, every face walked — so doing it once per crease over a growing pattern
is cubic. `Fold.Creasing.creaseAllAlong` takes them all and cuts once;
`creaseAlong` is that with one. Creasing a 320-fold accordion through its layers
went from 63 seconds to 0.6, with byte-identical output. Two things the batch
must do that a single crease need not: intern ends against the batch as well as
the sheet, so two creases meeting at a new point meet at one vertex; and decide
every refusal against the frame as it was, so the answer does not depend on the
order the batch is in.

**A move that changes a pattern hands the result back to what validates a read
one.** `Senbazuru.Fold.Creasing` adds a crease and then calls
`Fold.Crossings.withPlanarFaces` — so a pattern that has been creased is cut,
traced and refused by exactly the code that cuts, traces and refuses a pattern
that came out of a file. The alternative, a move that checks its own work, is
two definitions of a valid pattern that drift.

Note what a move has to destroy. Drawing a crease cuts at least one face in
two, so `faces_vertices`, `faceOrders` — which name those faces and are read
against their winding — and `frameExtras` all go. Dropping the faces is also
what lets `splitCrossings` run at all, since it leaves a frame that records
faces alone.

`frameExtras` is dropped too widely, and knowingly: on the key frame it holds
the *file's* unknown keys as well as the frame's, so creasing a pattern
destroys a `cpedit:page` that a new crease does not invalidate. Nothing can
tell those apart from the ones it does invalidate. That is #73.

**A new input format becomes a `Frame` and stops there.** `Senbazuru.Import.*`
reads Orihime and Oriedita's `.cp` and ORIPA's `.opx` — both a flat list of
segments with no vertices, no faces and no angles — and hands back a `Frame`
that says only what the file said. Nothing downstream may know a frame came
from anywhere but a `.fold` file, and where a format cannot say something FOLD
can, the frame does not say it either. `Senbazuru.Fold.Load` picks the reader
from the extension; everything unrecognised is still tried as FOLD.

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

**`stack build --ghc-options=-fforce-recomp` does not show you the warnings**,
and believing it does is how eight of them accumulated in the test suite. Stack
decides whether to invoke GHC at all, from a hash of the source and the flags —
so `touch` changes nothing, and a *second* run with the same `--ghc-options`
rebuilds nothing and prints nothing. It looks exactly like a clean build.
`stack clean && stack build --test` is the check that is actually a check. CI
does it from cold every time, which is why it sees what a local run does not.

One trap in that: **do not name a binding `pattern`.** `hlint`'s parser reads it
as the `PatternSynonyms` keyword whether or not the extension is on, so
`draw pattern share = ...` compiles under GHC and fails `make lint` with a parse
error. It is a tempting name in a project about crease patterns; `paper` or
`sheet` says the same thing.

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
test/golden/X.svg`. Never accept a golden diff you have not read. A `.glb`
golden is opaque to a text diff, so its failure names the first byte that
differs — inside the JSON chunk is a change of document, inside the binary
chunk a change of geometry — and `cmp -l` shows the rest.

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
  angles no sheet can adopt. `foldFrame` closes the loops by hand, and it takes
  *two* checks. Comparing where each face puts a shared vertex (`TornAt`)
  catches most of it — but two faces across a crease share only that crease's
  endpoints, which lie on its rotation axis and are fixed by any turn about it,
  so a loop the walk closed by turning *nothing* leaves every shared vertex
  agreeing. `loopsClose` asks the other question: is each crease's own angle
  achieved? Anything else walking the face graph needs both or it will silently
  tear a model — or, worse, silently not fold one.
- **A fold's transforms are against the *cut* pattern, not the file's frame.**
  `foldFrameWith` hands back all three — the folded form, that pattern, and one
  `Rigid` per face — because folding calls `withPlanarFaces` before anything
  else, and cutting the crossings adds vertices and re-traces the faces. So a
  face's motion is keyed by its index into the frame that came *out* of the
  cutting. Inverting one to write something back onto the sheet means writing
  onto `foldedPattern`; using the frame that went in numbers the faces of a
  different drawing, and `examples/unit-square.fold` is a file where the two
  differ.
- **A crease's end has to meet something, and that is a question about the
  drawing rather than about the sheet.** "That end is off the paper" is the
  tempting message and is false for a crease drawn from the middle of a face to
  the middle of a face, which is refused too. The argument is written out once,
  in `Fold.Creasing`'s module header; do not restate it.
- **Creasing through the layers asks whether an end is inside a *face*, never
  whether it is inside the *model*.** What has to hold is that every layer the
  line reaches is creased right across, which is a fact about each face on its
  own. An end on the boundary of every face it touches is fine wherever it sits,
  the model's interior included; an end in some face's *middle* creases that one
  layer part of the way and is refused. Generalising the test to the model's
  outline is the tempting move and answers a different question.
  `Origami.ThroughLayers` can ask this at all, where `Fold.Creasing` cannot say
  where a sheet *is*, because a folded model is a list of convex panels.
- **How often an end lands on a crease that every layer shares is not "usually",
  and guessing it wrong is easy.** It happens where a fold has brought several
  layers' edges into line, and not where one layer's crease runs across the
  middle of another's paper. Of the folded crane's 248 face-edge midpoints, 120
  are the first kind and 128 the second; the bird base splits 24 to 20; the
  quarter fold, whose four layers land exactly on top of one another, is 16 to
  nothing. Both halves are common and a doc that says either is the normal case
  is wrong.
- **Creasing a folded model asks for one kind of crease and writes both.** Every
  layer of a packet creases the same physical way, but alternate layers are
  upside down, so a fold that opens towards the reader is a valley on the faces
  lying top-up and a mountain on the ones lying top-down. Ask
  `Origami.ThroughLayers` for a valley across the quarter fold and the four
  creases come back M, V, M, V through the stack. Which way up a face lies flips
  across every crease the paper folds along and stays the same across every one
  it does not, so it is a parity count of the folds back to the root face. Passing the caller's assignment through unchanged gives
  every position right and every kind wrong, which is a file that looks fine
  and folds into a different model.
- **Which way up a face ended is `M · ẑ`, not the winding.** A flat fold sends
  the up direction to exactly `+ẑ` or `-ẑ`, so the sign of the transformed
  vector is the whole answer, and it is a measurement.
  `Origami.Flat`'s `panelFaceUp` answers the same question from the *file's*
  winding, which is the guess with nothing to cancel against described below —
  fine for deciding which side of the paper a picture shows, and not what to
  build a crease's assignment on.
- **A line drawn on a folded model is one segment per *face*, not per layer.**
  Three counts get confused. On the folded crane the worst line crosses 56 of
  its 72 faces, the deepest stack of paper found over any single point is 24,
  and the largest layer number is 32. Only the first bounds the work, and its ceiling is the
  face count.
- **At ±180° a mountain and a valley are the same rigid motion.** Turning half a
  turn either way about a line lands in the same place. The assignment still
  matters — it decides which layer ends up on top — but that is layer ordering,
  not position, so folding cannot tell a flat mountain from a flat valley.
- **Not every line in a crease pattern folds.** `F` (flat) and `J` (join) are
  drawn but the paper is continuous across them, so anything reasoning about the
  angles around a vertex has to dissolve them first — otherwise the crease count
  is wrong, which flips the parity Maekawa's theorem depends on. Dissolving can
  also leave *one*, and one is not a Maekawa case at all: it is a crease that
  stops in the middle of the paper, which `check` now says as such — see
  `Origami.FlatFold`'s `CreaseStops`. `B` and `C` mean the paper stops, which
  makes the vertex a border vertex, where the flat-folding theorems do not apply
  at all.
- **A folded form is not necessarily 3D.** The traditional crane folds *flat*,
  so its folded frame lies in a plane. Choose a view from the coordinates
  (`defaultBasisFor`), never from `frame_classes`. The line notation is the one
  exception: a flat-folded form and a crease pattern have the same kind of
  coordinates, so `defaultNotationFor` asks the class, and only when the
  geometry is flat.
- **Real files carry vendor keys** like `"cpedit:page"`. Do not interpret an
  unknown key — and do not destroy it either. `parseFrame` collects everything
  it did not claim into `Frame`'s `frameExtras` and the encoder writes it back,
  so a file survives a trip through senbazuru with another tool's data intact.
  The two key lists, `fileKeys` and `frameKeys`, are what say which is which; a
  key that falls out of them gets read *and* collected, and then written twice.
- **Preserve at the boundary, discard at the transform.** Keeping keys we do not
  understand means the writer cannot judge them, so whatever *changes* the
  document has to. `foldFrame` drops `frameExtras` wholesale, because folding
  rewrites every coordinate and reverses the winding of any face that turns
  over, and a carried `faces_edges` would then be false. See
  `docs/notes/round-trips.md`.
- **Faces are not extra information, they are the creases read another way.**
  Most files record none — no `.cp` or `.opx` can — so `Senbazuru.Fold.Faces`
  traces them, and `Origami.Folding` and `Render.Gltf` both call
  `Fold.Crossings.withPlanarFaces` — cut, then trace — rather than refusing.
  **One function, not two calls at each backend**, for the reason
  `--layer-budget` is written down below: a policy spelled out per backend is a
  policy the next backend forgets.
  `Render.CreasePattern` deliberately does neither, and not for fear of
  churning goldens: tracing can fail on a drawing no cutting fixes — a crease
  that stops in the middle of the paper has no face round it — and a drawing
  must not stop working because its faces cannot be worked out. Filling only
  when the trace happens to succeed would make the picture depend on something
  nobody looking at the page can see.
- **The face walk turns clockwise to trace an anticlockwise face.** From the
  half-edge `u→v` it turns at `v` onto the next crease *clockwise* from `v→u`.
  Turning the way the face winds traces the same rings backwards; turning the
  sharpest way against the direction of travel is what keeps the walk hugging
  one region. The outer ring is the one with negative area and is dropped.
- **A traced winding can be trusted, unlike a file's.** The sign is what
  selected the ring, so every traced face is anticlockwise. This does not
  contradict the rule that a file's winding is taken as written: that rule is
  about not breaking `faceOrders` signs, and a frame that recorded no faces
  recorded no orders either.
- **Tracing refuses a drawing that is not planar as drawn, and it must.** Two
  creases crossing with no vertex, or a vertex sitting on an unsplit edge, both
  produce rings — plausible ones that fill and fold — describing regions that
  are not the regions on the page. Neither is a fact about the paper, though,
  so `Fold.Crossings` cuts them first and only what survives that is refused.
- **Cut every crossing before adding any of them as a vertex.** Three creases
  through one point are three crossings pairwise, and computing each on its own
  gives three vertices a rounding error apart joined by creases shorter than
  anything a person drew. `examples/unit-square.fold` is exactly that case.
  Find every crossing, merge them at the sheet's tolerance, *then* cut.
- **`splitCrossings` leaves two kinds of frame alone**, and both matter. A
  frame that *records its own faces* has already answered the question cutting
  asks — a crease stopping part-way along another is no defect there, the face
  just has a corner mid-side — so cutting would swap the file's answer for ours,
  re-wound, and `faceOrders` are read against the file's winding. And a frame
  with *nothing to cut* comes back untouched, keys and all, which is what lets
  this sit in front of every fold and export without stripping keys or adding
  refusals on paths that never asked. When it does cut, `faces_vertices` and
  `frameExtras` go, on the preserve-at-the-boundary rule.
- **Cutting does not renumber the vertices** — every one the file had keeps its
  id, and crossings are appended after them. What makes a stale
  `faces_vertices` untrue is the new corners in the middle of its sides, not
  dangling ids. The obvious reason is the wrong one, and it was in this file.
- **Editors are not as tidy as you would assume.** Of thirty crease patterns in
  the reference corpora, one hand-written file has creases genuinely crossing —
  and ORIPA's own `turkey2015.opx` has 71 creases that stop on another crease
  it never cut, which made it unfoldable here until `Fold.Crossings` existed.
- **Absent is not empty.** The decoder reports a missing `faces_vertices` as
  `[]` because it is permissive; the encoder must not write `[]` back, because
  that is a claim the file did not make. Every `Nothing`, every empty list and a
  `frame_inherit` of `False` are left out.
- **`file_spec` is a number, not an integer.** Real files say `1.1`.
- **`.cp` and `.opx` are y-down, and the flip is a correction, not a
  convention.** Both were written by Java desktop editors storing screen
  coordinates — Oriedita's `Camera.object2TV` never negates y. Reading one
  without negating y gives the *mirror* of the model, which folds perfectly
  well and is not the file's. `Senbazuru.Import.Segments.fromScreenPoint` is
  the one place it happens. Oriedita's own FOLD export does not do it, so our
  reading of a `.cp` and its export of the same file are mirror images.
- **The two type-code tables agree on 1, 2, 3 and disagree about auxiliary.**
  Paper edge, mountain, valley in both; auxiliary is 0 in an `.opx` and 4 in a
  `.cp`, where Oriedita's further colours run on to 11. Flat-Folder's two
  tables disagree with *each other* on code 1 and get away with it because it
  recomputes the boundary from the faces. See `docs/notes/cp-and-opx.md`.
- **An `.opx` property is named, not positioned, and an absent one is zero.**
  `XMLEncoder` sorts a bean's properties by name, so ORIPA writes `x0 x1 y0
  y1`, and a positional reader draws a plausible wrong pattern. It also omits
  any value a fresh bean already has, so a crease on an axis has no `x`
  coordinates and an auxiliary line has no `type`. That is the opposite of
  FOLD, where absent means the file made no claim.
- **Endpoints that should be one vertex are not equal.** A segment list has no
  vertex ids, so they are matched by distance within
  `Senbazuru.Import.Segments.mergeTolerance` — a billionth of the pattern's
  diagonal. The search is a grid of tolerance-wide cells and it looks at nine
  of them, because two points a tolerance apart can straddle a cell boundary;
  comparing cells alone splits exactly the pair that most needs merging.
- **A degenerate segment is one whose endpoints merged, not a short one.**
  Measuring the segment and merging its ends are different questions: a
  segment nearly two tolerances long that straddles an existing vertex has both
  ends land on it, and the edge would run from a vertex to itself. So
  `frameFromSegments` interns first and rejects the segments whose two ids came
  out equal. That test subsumes "shorter than the tolerance" exactly.
- **An `.opx` walk has to count nesting.** `properties` reads a flat stream of
  tags, and the `</object>` closing an object nested inside a property looks
  exactly like the one closing the crease. Stopping at the first one does not
  fail — it returns early, silently dropping every property after the nested
  element. `Senbazuru.Import.Opx.insideElement` takes a whole subtree at a
  time, which is also what lets a property holding a `<string>` be skipped
  instead of refusing the file.
- **Model y is up, SVG y is down.** Every model→page transform flips y.
- **SVG paints in document order**, so later shapes cover earlier ones. Creases
  are sorted by `creaseOrder` in `Senbazuru.Render.CreasePattern`; the paper
  sits outside that ordering entirely — every fill is emitted before every line.
  Where the fills overlap each other, their order is
  `Senbazuru.Origami.Layers.paintOrder`; where they do not, they are one `Fill`.
- **The offset view is the one picture where a fill goes over a line.** Its
  layers are separate sheets, so a layer's paper has to cover the layer below
  it, lines and all, or the stack reads as a heap of wireframes. The order there
  is fill, lines, fill, lines, from the bottom up — and within one layer the
  usual rule still holds.
- **The offset view is drawn in two weights, and the weight is the whole fix.**
  A buried sheet goes down at `themeBuriedWidth` (0.35pt) and the model —
  `Senbazuru.Origami.Visible`'s unhidden stretches — over the top at full
  weight. At one weight a dozen sheet edges three points apart are a black band.
  Dropping lines instead does not work and was measured: keeping only each
  sheet's silhouette removes 6 of the crane's 242 edge copies, because nearly
  every crease separates two faces at different depths.
- **`formEdges` and `formSheetEdges` are the same stretches cut differently.**
  The first is joined up across changes of the sheet behind it, which is what an
  ordinary drawing wants and what `joinRuns` was written for; the second is cut
  at every such change and labelled with the sheet, which is what a drawing that
  moves the sheets apart needs. Making the first behave like the second is the
  tempting simplification and it silently resplits every ordinary picture's
  outline.
- **A layer number is the longest chain below a face, not a count of what is
  under it.** `Senbazuru.Origami.Layers.layerDepths` is what the offset view
  steps by, and the distinction is the whole of getting it right: counting gives
  two overlapping faces the same number as soon as the stack fans out, and then
  they are drawn on top of each other again. Longest-chain strictly increases
  along every `faceOrders` relation, which is also what makes sorting by it a
  valid painting order. See `docs/notes/layer-numbers.md`.
- **A page-unit displacement is a `Shape` wrapper, not a coordinate.** `Offset`
  is the third shape needing both units, after `Arrow`'s head and `Label`'s type
  size, and the first whose page-unit part is a position. It is deliberately
  outside `shapePoints`, so the extent never sees it and a stack opened out does
  not rescale the page; and `mapShapePoints` passes through it, so laying
  figures out on a grid leaves it alone the way it leaves a stroke width alone.
  `Senbazuru.Render.Svg` moves the transform rather than the points.
- **Abutting fills of one colour are one `Fill`, not several shapes.** Two
  shapes that share an edge are each antialiased against what is behind them, so
  the shared edge comes out as a pale seam — measured, on a square split by its
  diagonal, as `#d6cab3` where the whole square gives `#c8b89a`. One path with
  several subpaths rasterises as one region and is pixel-identical to the whole.
  Paper arrives in pieces constantly: a crease pattern is faces abutting along
  every crease, and a visible region is several convex pieces.
- **A `Fill`'s rings add up by the nonzero rule**, so two overlapping rings
  wound opposite ways cut a hole in each other. `Senbazuru.Render.CreasePattern`
  turns every ring anticlockwise on the way out, which is allowed precisely
  because filling has never relied on the file's winding — see below for what
  does.
- **Face winding is not to be trusted — except in a folded form's layers.** FOLD
  specifies counterclockwise and real files disagree. Filling does not care, and
  folding measures the winding from the coordinates. But `faceOrders`'s signs
  are read against a face's *normal*, which is *defined* by its winding, so the
  two were written against each other: a file with backwards windings has
  backwards signs, and they cancel. Recomputing the winding there would uncancel
  them and turn the model inside out. `Senbazuru.Origami.Layers` takes the
  file's winding exactly as written, and so does `Senbazuru.Origami.Flat`, which
  reads it to tell a face lying top-up from one lying top-down;
  `Senbazuru.Origami.Stacking` then checks it against itself across every
  crease. `foldFrame` therefore writes its faces counterclockwise as measured on
  the pattern, so the folded frames it produces are frames whose winding can be
  trusted.
- **A winding is not private to its face, so re-winding one means re-signing the
  orders that name it.** `foldFrame` is the one place that rewrites a winding,
  and it therefore has to move the signs with it: `Folding.reorient` flips
  `Above` and `Below` on every `faceOrders` entry whose *second* face was turned
  round. Only the second — FOLD reads the sign against `g`'s normal, so
  reversing `f` changes which face is being placed and not the direction the
  relation is read in. Doing neither was #78, and it turned a clockwise-wound
  file's model inside out in silence.
- **The cancellation covers the layer order and nothing else.**
  `Senbazuru.Origami.Visible` reads the same winding a third time, to say which
  *side* of the paper a region shows, and there is nothing for that to cancel
  against: a file that wound every face backwards *and* negated every
  `faceOrders` sign picks the same face as visible and calls it the other side
  of the sheet. Both paper colours come out swapped, silently, because no
  signal in such a file distinguishes the two. Trusting the winding is what
  makes the layer order work and what makes the paper side a guess.
- **A stretch of edge is judged by how far outside a face its midpoint is, not
  by clipping it.** A stretch lying along a face's edge clips to itself when
  rounding puts it a hair inside and to nothing when rounding puts it a hair
  outside, and a clip has no tolerance to call those the same answer. Use
  `Senbazuru.Geometry.Polygon.distanceOutside`, which returns the hair and lets
  the caller decide it is one. Getting this wrong dropped a face from the
  reckoning entirely and stopped visible creases dead in the middle of the
  crane.
- **A ring can carry an edge of no length**, wherever folding brought two
  corners together or a clip passed exactly through one. Such an edge names no
  side, so clipping by it keeps everything both ways — `subtractConvex` returned
  overlapping pieces adding up to more paper than went in until it skipped them.
  Anything that walks a ring's edges and asks which side of one a point is on
  has to skip them too.
- **The layer solver's cost is the propagation, not the geometry, and only a
  profile says so.** On a 161-layer accordion the whole triple enumeration —
  every one of the C(f, 3) `Acyclic` rules — is 0.9% of the run, while looking
  pairs up in the decided-pairs map is over half. Two things measured in GHCi
  said the opposite and were both wrong: the interpreter does not float the
  loop-invariant clip out that a compiled build does, so an "optimisation" worth
  2× interpreted was worth nothing compiled. Use `stack build --profile` and
  `+RTS -p`; a proxy measurement here has misled twice.
- **A model usually has several valid layer orders, and the count is a
  product.** The constraint graph falls into components that share no rule, so
  the orders are every combination of theirs: the crane has 5, one of
  Flat-Folder's models has 10^83. Solve each component separately and the cost
  adds up over them instead of multiplying — the crane's 87 open pairs are one
  component that 8 guesses exhaust. `stateCount` returns `Integer` for a reason.
- **`--layer-budget` has to reach every backend, not just the CLI.** A folded
  form's layer order is asked for through `Origami.Stacking.layerOrderFor`,
  which takes the budget, so it is a parameter of `creasePatternFrom`,
  `creasePatternAuto`, `stepPage` *and* `renderGlb`. It was a CLI flag that did
  nothing on `render` for exactly as long as it was not, and a new backend that
  forgets it repeats that.
- **Flat-Folder counts the settled pairs as a component and we match it.**
  Its first component is always the pairs propagation forced, whether there are
  any or not — a model with no variables at all still reports one. So
  `componentCount` is our components plus one, deliberately, because matching
  its published figures model for model is the best evidence the split is right.
- **A different layer order is usually the same picture.** All 16 of the 2x2
  grid's orders draw identically from either side; the kabuto's 9 are one
  picture from above and four from below; the crane's 5 make two. Testing
  `--stacking` by comparing rendered output will mostly compare equal things —
  compare the `faceOrders`, or use the crane, whose states 0 and 3 differ.
- **A layer order need not be a painting order.** The solver forbids a circle
  only among three faces that share a patch of paper. Three faces can overlap
  pairwise with no point under all three — the flaps of a twist do — and then
  their pairwise orders may legitimately run in a circle, which `paintOrder`
  reports as `ImpossibleStacking` because it needs one global order. That is why
  a flat-folded model is drawn by `Senbazuru.Origami.Visible` instead, which
  never needs one: over any single point the covering faces *are* totally
  ordered, and that is all a region asks. `paintOrder` remains for folded forms
  with paper in the air, which have no plane to cut into regions.
- **A page of steps is drawn through one camera**, chosen from every frame
  together. Asking each frame what view suits it moves the reader around the
  model between figures, and makes the shared extent a union of boxes measured
  in different projections. The *notation* is still per frame — that is a
  different question. See `Senbazuru.Render.Steps`.
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
  negative zeros. `formatNumber` normalises them. The 3D export has the same
  problem in float32, which keeps the two zeros as different bytes, and removes
  it by rounding every coordinate through an `Integer`, which has no sign to
  keep — not by a guard, which cannot see the sign either, and not by rounding
  in `Float`, where `realToFrac` of a negative zero keeps the sign under
  optimisation and drops it without.
- **The layer solver reads the creases, so hand it the frame.** `Render.Gltf`
  once rebuilt a frame from vertices and faces alone to ask for a layer order;
  the solver, finding no creases and no assignments, had nothing to constrain
  and stacked every model flat — including the quarter fold, silently. A twist
  exporting without complaint was what gave it away.
- **glTF is y-up; senbazuru treats FOLD's z as up.** FOLD itself does not
  say; z-up is the convention its folded forms follow and `Render.Camera`
  adopts. `Render.Gltf` maps `(x, y, z)` to
  `(x, z, -y)`. The `-y` reads as a typo and is a quarter turn about `x`;
  `(x, z, y)` would be a reflection and the model would come out mirrored,
  which folds perfectly well and is not the model in the file.
- **A hex colour is sRGB and glTF wants linear.** `#faf8f3` written through
  unconverted is visibly too light. `Render.Gltf.linearOf` inverts the transfer
  function; `Diagram.colourComponents` deliberately does not, because the
  transfer is glTF's convention and not the colour's.
- **In a 3D export every face owns its corners.** Faces at different layers are
  lifted to different heights, so a crease's two faces cannot share a vertex;
  the quarter fold is sixteen vertices, not nine. A watertight mesh would be the
  wrong answer — a folded sheet is not a solid.
- **Two paper colours are two primitives, not a two-sided material.** glTF has
  no material with a front colour and a back colour, so each face is written
  twice, wound both ways, each copy single-sided and culled from behind.
- **`--thickness 0` skips the layer solver entirely.** It is the export's
  `--no-fill`: the only way to write a twist, whose layers run in a circle and
  have no numbers to be lifted by.

## Not implemented yet

Deliberate omissions, so nobody thinks they are bugs:

- Frame inheritance (`frame_inherit` / `frame_parent`) is decoded but not
  resolved, so every frame of a multi-frame file must repeat the whole graph.
- `edgeOrders` is not decoded at all.
- Layer order is solved only for models folded flat, with convex faces. A
  folded form with paper still in the air and no `faceOrders` is drawn as a
  wireframe, and a face that is not convex declines the whole model. Both are
  reported by `info`.
- Hidden-line removal and the two-sided paper colour are for models folded
  flat. A folded form with paper in the air is painted face by face with every
  crease drawn, as it always was.
- Which side of the paper a region shows is read from the file's winding and
  cannot be checked. A folded form whose faces are all wound backwards — which
  some editors emit — is drawn with its two paper colours swapped. The layer
  order survives it, because its signs were written against the same windings;
  the paper side has nothing to cancel against. The 3D export inherits this
  identically: its two primitives are wound from the file, so such a file comes
  out with its two paper colours swapped there too.
- A file whose own `faceOrders` run in a circle through three faces that share
  a patch of paper is a contradiction `Senbazuru.Origami.Visible` does not
  detect: each of the three loses the shared patch to the other two, and the
  model comes out with a hole in it. Nothing senbazuru produces can be like
  that. A pair of entries that contradict each other directly *is* refused.
- `--offset` is refused with `--arrows`: an arrow is drawn where the paper is
  and the offset draws every sheet a step away from there, so the tail would
  start on bare page. Putting the arrow on the sheet it leaves is a real answer
  and not one that has been worked out.
- **Merging a layer's faces into one area is right for a flat model and wrong
  for one with paper in the air.** Two faces of one layer are unordered because
  they do not overlap /on the paper/; projected, they can still cover the same
  patch of page. Flat, that cannot happen and merging is what keeps the seams
  out; in the air it discards the depth order and paints the far face over the
  near one. `Senbazuru.Render.CreasePattern` has both and picks by which path it
  is on.
- The offset view steps a whole sheet, where a printed book offsets edges only
  across the boundary of a cut-away circle, and falls back to a schematic side
  view when a model has too many layers to draw at all. Neither the local
  cut-away nor the side view exists here, so a deep model — the crane is 32
  layers — comes out honest and crowded.
- The offset view needs one order for the whole model, so a twist has none: it
  is refused, with the message `paintOrder` gives, rather than drawn without the
  offset. The ordinary picture of a twist is unaffected. `--offset` also does
  nothing under `--no-fill`, which is the escape hatch that asks no questions
  about layers at all.
- The offset never enters the extent, on purpose, so a large step on a model
  that already fills the page runs off it. There is no auto-fitting: the reader
  picks a smaller step or a bigger page.
- The layer solver enumerates a component's orders only up to its budget, so a
  model with more of them than that reports "at least" rather than a count. It
  gives up on a component it cannot settle within the budget rather than
  searching on, which is a refusal and not a decline: `render` says so instead
  of drawing something.
- Folding solves for positions from given angles. It does not solve for *angles*
  — there is no way to ask for a model half folded, because scaling every angle
  by a fraction generally lands on angles no paper can adopt.
- The 3D export separates layers only for a model folded flat. A form with
  paper in the air is written as it stands, and its coplanar faces, where it
  has any, z-fight; the general case groups faces by plane and lifts each group
  along its own normal.
- The 3D export fans each face from its first corner, which is right for convex
  faces and refuses the rest. Ear clipping would take any simple polygon.
- The 3D export writes faces and no crease lines, no normals (viewers compute
  flat ones, which is right for paper), and no animation. The per-face rigid
  transforms it would need are there — `Folding.foldFrameWith` hands them back
  — but the intermediate angles that close their loops are not, per
  `docs/notes/fold-angles-are-the-state.md`.
- A `.cp` or an `.opx` is read and never written. Neither format can hold a
  face, a fold angle or a second frame, so writing one would silently drop
  them; senbazuru writes FOLD, SVG and glTF.
- The `.cp`/`.opx` reader rebuilds the vertices and nothing else, so a segment
  list can still describe something that is not a planar graph. `check` reads
  such a file as drawn, so a crossing with no vertex there leaves it one vertex
  short of what the picture suggests — the same under-reporting
  `examples/unit-square.fold` already gets, and `check` does not cut. Anything
  needing faces cuts first (`Fold.Crossings`) and refuses what is left.
- Two creases lying along one line with a stretch in common are refused rather
  than cut: along the stretch they share there are two answers to how the paper
  folds, and picking one is not senbazuru's to do.
- The `.cp` reader accepts type codes 1 to 11 and refuses everything else,
  including 0. Oriedita's auxiliary colours are the ones above 4, and it drops
  the colour, because FOLD has nowhere to put it.
- Creasing through the layers creases *every* layer under the line. A book also
  says "fold the top layer only", and that is a different instruction belonging
  with #60's vocabulary — it would need to know which face is over which at a
  point, which this deliberately never asks.
- Creasing through the layers is for a model folded *flat*. With paper still in
  the air a line drawn on the page is a ray and not a point, so it names no one
  place on the sheet. The same restriction `Origami.Visible` and the layer
  solver carry, and it arrives via `Origami.Flat.flatSheet`.
- A folded-form *file* is still refused by both creasing verbs. `--folded`
  takes the *pattern* and folds it here, which is the only way the per-face
  transforms exist; a file that is already folded carries neither them nor a
  sheet to map back to, and recovering one is unfolding.
- A new crease takes the fold angle its assignment implies — ±180 for a
  mountain or a valley — not zero. A valley with an angle of zero is not a
  valley, and `foldFrame` reads the same value off the assignment when the
  array is absent, so writing zero made one command mean two things depending
  on whether the file happened to record angles.
- `crease` does not say that an end is *off the paper*, only that it meets
  nothing, and it never learns which. `Fold.Creasing` still has no "is this
  point on the sheet" question, and does not need one.
- The FOLD writer does not refuse a non-finite number. `aeson` writes an
  infinity as the string `"+inf"` and a `NaN` as `null`, neither of which is a
  FOLD coordinate, and the decoder reads a `null` coordinate back as `NaN` so
  the two agree with each other and with nothing else. Nothing produces one
  today. Fixing it means `encodeFoldFile` returning `Either`, which is what the
  rest of the codebase would do.

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
