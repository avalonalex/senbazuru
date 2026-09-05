# senbazuru

Render [FOLD](https://github.com/edemaine/FOLD) origami files as SVG, in the
visual style of step-by-step origami instruction books.

*Senbazuru* (千羽鶴) is the practice of folding a thousand paper cranes.

> **Status: early.** Crease patterns render correctly and are filled with paper.
> A pattern can be *folded* along its own fold angles and the result drawn from a
> choice of viewing angles, layer-correctly where the file says which face is in
> front. There is also a flat-foldability checker. Folding arrows — the thing
> that makes a diagram a *diagram* — are not built yet. See
> [Roadmap](#roadmap).

## What it does today

Given a `.fold` file, it draws every edge using the standard
Yoshizawa–Randlett line vocabulary: solid for the edge of the paper, dashed for
valley folds, dash-dot-dot for mountain folds, and a light line for creases that
exist but are not folded. Those dashes are instructions, so they belong to crease
patterns. A folded form is drawn the way a book draws the model itself, with
every edge solid.

```bash
stack run -- render examples/unit-square.fold -o unit-square.svg
```

produces a unit square with a valley fold down the middle, a mountain fold
across it, and a faint diagonal reference crease. That file records no faces, so
what comes out is exactly those lines on a blank page.

A file that *does* record `faces_vertices` gets its faces filled with a paper
tint, so the sheet reads as an object rather than as lines floating on the page:

```bash
stack run -- render examples/quarter-fold.fold -o quarter-fold.svg
```

`--no-fill` turns that off.

A folded form is filled too, but only when the file says which face is in front.
FOLD records that in `faceOrders`, and `examples/simple.fold` carries one:

```bash
stack run -- render examples/simple.fold --view iso -o simple.svg
```

The stacking is a fact about the paper rather than about the picture — it says a
face lies on the side another face's *normal* points to — so the drawing order
depends on where you are looking from, and the same model seen from behind
stacks the other way up. A folded form with no `faceOrders` stays a wireframe:
painting its faces in the order they happen to appear in the file would be a
confident picture of the wrong thing, and working the order out instead is
NP-hard in general.

Folded forms take a viewing angle:

```bash
stack run -- render examples/squaretwist.fold --view iso -o squaretwist.svg
```

The bare `--` matters: without it Stack tries to interpret `--view` as one of its
own options.

## What it folds

`--fold` computes the folded form rather than reading one. Given a crease
pattern and a fold angle for every crease, paper does not stretch, so each face
moves rigidly and the whole state is one rigid motion per face — walk the faces,
compose one turn per crease, and every vertex is a lookup.

```bash
stack run -- render examples/quarter-fold.fold --fold -o quarter-folded.svg
stack run -- render examples/diagonal-cp.fold --fold -o diagonal-folded.svg
```

The first folds a square into quarters and produces a quadrant with four layers;
the second folds a square along its diagonal and produces a triangle. Neither
needs `--view`: both fold *flat*, and the view is chosen from the coordinates, so
they are drawn from above. Forcing `--view iso` on a flat-folded model shears a
correct picture into a wrong one; leave the camera alone unless the fold really
does leave the plane. Fold angles
come from `edges_foldAngle`, or from the assignments if the file records none —
an assignment names a direction and not an amount, and a flat fold is the only
amount consistent with naming no number.

Not every set of angles describes something a sheet of paper can do. Walk round
an interior vertex and the turns must compose back to nothing, and the obvious
algorithm never checks: it reaches each face by one path and silently *tears* the
model when they disagree. `--fold` compares the places each face puts a shared
vertex and refuses rather than drawing the tear:

```console
$ senbazuru render bent.fold --fold
senbazuru: cannot fold bent.fold: vertex 6 is placed 0.707107 apart by the faces
meeting at it, so these fold angles tear the paper rather than folding it
```

The threshold for "disagree" admits arithmetic noise and nothing more, so angles
that are a fraction of a degree short of closing are refused too — the message
quotes the distance, which is how you tell a tear from a typo in the fourth
decimal place.

Layers are not ordered yet, so a folded form is drawn as a wireframe: senbazuru
knows where every face went, not which one is in front.

## What it checks

`senbazuru check` applies two classical theorems to every *interior* vertex of a
crease pattern — a vertex with paper all the way round it, as opposed to one on
the edge of the sheet, where neither theorem applies.

*Maekawa's theorem* says the number of mountain creases at such a vertex minus
the number of valley creases is always ±2. It follows that the total is even, so
three creases meeting at a point can never fold flat, whatever their angles:

```console
$ senbazuru check examples/three-crease.fold
examples/three-crease.fold, frame 0
  vertex 5: 3 creases meet here, an odd number, which never folds flat (Maekawa)
  checked 1 interior vertex; skipped 5 on the border
  1 violation
```

*Kawasaki's theorem* says that walking round the vertex and adding the angles
between consecutive creases with alternating signs gives zero. A square folded
into quarters satisfies both:

```console
$ senbazuru check examples/quarter-fold.fold
examples/quarter-fold.fold, frame 0
  checked 1 interior vertex; skipped 8 on the border
  no violations found
```

It says *no violations found* rather than *flat-foldable*, and that wording is
load-bearing. Both theorems are necessary, not sufficient: they are local, so a
sheet whose every vertex passes can still be impossible, and even at one vertex
they miss a third condition on which crease is a mountain and which a valley.
`examples/big-little-big.fold` passes this check and cannot be folded — see
[big-little-big.md](docs/notes/big-little-big.md). A violation means the pattern
is definitely wrong; a clean run means nothing was caught.

The command exits non-zero when it finds a violation, so it drops into a build
or a hook without anyone grepping the output.

There is also a summary command for poking at unfamiliar files:

```console
$ stack run -- info examples/unit-square.fold
examples/unit-square.fold
  title:   Unit square with a cross of creases
  creator: senbazuru (hand-written)
  classes: singleModel
  frames:  1
  frame 0: Preliminary creases
    classes:  creasePattern
    vertices: 8
    edges:    11
    faces:    0
    creases:  B=8 M=1 V=1 F=1
```

## Building

Requires [Stack](https://docs.haskellstack.org/). The project pins Stackage
`lts-22.44` (GHC 9.6.7).

```bash
stack build
stack test
make check      # formatting, lint and tests: everything CI should run
```

`stack.yaml` sets `system-ghc: true`, so Stack reuses a GHC 9.6.7 already on
your `PATH` rather than downloading its own. If you would rather Stack managed
the compiler, delete that line.

## Usage

```
senbazuru render FILE.fold [-o OUT.svg] [OPTIONS]
senbazuru check FILE.fold [--frame N] [--tolerance DEG]
senbazuru info FILE.fold
```

Working from source, reach the executable in any of three ways:

```bash
stack run -- render FILE.fold          # everything after -- goes to senbazuru
stack exec -- senbazuru render FILE.fold   # after a stack build
make install                           # puts senbazuru on your PATH, then use it directly
```

| Option | Meaning |
| --- | --- |
| `-o, --output FILE` | Write to a file instead of stdout |
| `--frame N` | Which frame to render (default `0`, the key frame) |
| `--width`, `--height` | Page size in points (default `400`) |
| `--margin` | Blank border in points (default `16`) |
| `--view NAME` | Viewing angle: `top`, `iso`, `front`, `side`. Defaults to `top` for crease patterns and `iso` for folded forms |
| `--transparent` | Omit the white background rectangle |
| `--hide-flat` | Do not draw flat (`F`) or unassigned (`U`) creases |
| `--no-fill` | Draw the sheet as a wireframe, with faces left unfilled |
| `--fold` | Fold the crease pattern along its fold angles and draw the result |

`check` takes `--frame` too, and one option of its own:

| Option | Meaning |
| --- | --- |
| `--tolerance DEG` | How far Kawasaki's alternating sum may sit from zero and still pass (default `0.000573`, which is 1e-5 radians). Raise it for files whose coordinates are heavily rounded |

## Project layout

```
src/Senbazuru/
  Geometry.hs              points, boxes, the model→page transform
  Geometry/VectorSpace.hs  the arithmetic 2D and 3D points share
  Geometry/V3.hs           points in space, for 3D input
  Geometry/Rigid.hs        motions that turn and slide without deforming
  Fold/Types.hs            the FOLD document model + JSON decoding
  Fold/Load.hs             reading files (the only I/O in the library)
  Fold/Query.hs            validating a frame into geometry you can trust
  Diagram.hs               backend-independent drawing IR
  Diagram/Style.hs         the origami line conventions
  Origami/FlatFold.hs      Maekawa's and Kawasaki's theorems, vertex by vertex
  Origami/Folding.hs       crease pattern + fold angles -> folded form
  Render/Camera.hs         orthographic projection, 3D → the page
  Render/CreasePattern.hs  FOLD frame → Diagram
  Render/Svg.hs            Diagram → SVG text
app/                       the command-line interface
test/                      property, example and golden tests
examples/                  sample .fold files, including three from upstream
docs/fold-primer.md        background on FOLD and on origami diagram notation
docs/fold-reference.md     every FOLD key, and what we do with it
docs/glossary.md           every term the docs and code assume
docs/notes/                one idea per file, with references
```

[`docs/fold-primer.md`](docs/fold-primer.md) is the place to start if origami or
the FOLD format are new to you, and
[`docs/fold-reference.md`](docs/fold-reference.md) is the key-by-key reference
with our coverage status. [`docs/notes/`](docs/notes/) collects short
single-idea notes on the theorems, algorithms and techniques this project leans
on or is heading towards. [`CLAUDE.md`](CLAUDE.md) holds the working
conventions.

## Roadmap

Roughly in order. Each item is an issue, tagged
[`roadmap`](https://github.com/avalonalex/senbazuru/labels/roadmap), where the
approach and the acceptance criteria are written out; this list is the map, the
issues are the detail.

0. **[Fold arrows.](https://github.com/avalonalex/senbazuru/issues/6)** A crease
   pattern is not yet instructions; the arrow showing *which way* the paper
   moves is what makes a diagram teachable. FOLD stores no arrows, so they are
   inferred by diffing consecutive frames. Needs a convex hull, and therefore
   needs to care about floating point.
   → [convex-hull](docs/notes/convex-hull.md),
   [robust-predicates](docs/notes/robust-predicates.md)
1. **[Multi-frame sequences.](https://github.com/avalonalex/senbazuru/issues/16)**
   Lay out a `file_frames` sequence as a numbered grid of steps at a single
   shared scale. Note that every published FOLD example is single-frame, so this
   needs fixtures we author ourselves.
   → [envelopes](docs/notes/envelopes.md)
2. **Solving for layer order.** A folded form senbazuru folded itself carries no
   `faceOrders`, so it is still drawn as a wireframe. Working one out is a
   constraint problem and NP-hard in general — the deep end.
   → [layer-ordering](docs/notes/layer-ordering.md)
3. **Authoring tools.** FOLD output
   ([#19](https://github.com/avalonalex/senbazuru/issues/19)) first, since
   nothing else can be built without it, and then operations on crease patterns.
   → [huzita-hatori](docs/notes/huzita-hatori.md)

## Credits and licence

The FOLD format is by Erik Demaine, Jason Ku and Robert Lang. The example files
in `examples/` marked as such come from the
[reference FOLD repository](https://github.com/edemaine/FOLD) (MIT).

senbazuru is MIT licensed, the same as the FOLD reference
implementation. See [LICENSE](LICENSE).
