# senbazuru

Render [FOLD](https://github.com/edemaine/FOLD) origami files as SVG, in the
visual style of step-by-step origami instruction books.

*Senbazuru* (千羽鶴) is the practice of folding a thousand paper cranes.

> **Status: early.** Crease patterns render correctly, and folded forms render
> as wireframes from a choice of viewing angles. Folding arrows, face filling and
> layer-correct shading — the things that make a diagram a *diagram* — are not
> built yet. See [Roadmap](#roadmap).

## What it does today

Given a `.fold` file, it draws every edge using the standard
Yoshizawa–Randlett line vocabulary: solid for the edge of the paper, dashed for
valley folds, dash-dot-dot for mountain folds, and a light line for creases that
exist but are not folded.

```bash
stack run -- render examples/unit-square.fold -o unit-square.svg
```

produces a unit square with a valley fold down the middle, a mountain fold
across it, and a faint diagonal reference crease. Folded forms take a viewing
angle:

```bash
stack run -- render examples/squaretwist.fold --view iso -o squaretwist.svg
```

The bare `--` matters: without it Stack tries to interpret `--view` as one of its
own options.

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

## Project layout

```
src/Senbazuru/
  Geometry.hs              points, boxes, the model→page transform
  Geometry/VectorSpace.hs  the arithmetic 2D and 3D points share
  Geometry/V3.hs           points in space, for 3D input
  Fold/Types.hs            the FOLD document model + JSON decoding
  Fold/Load.hs             reading files (the only I/O in the library)
  Fold/Query.hs            validating a frame into geometry you can trust
  Diagram.hs               backend-independent drawing IR
  Diagram/Style.hs         the origami line conventions
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

Roughly in order:

0. **A flat-foldability checker.** Maekawa's and Kawasaki's theorems decide
   whether each vertex can fold flat. Small, needs no new geometry, and it makes
   senbazuru understand origami rather than only draw it.
   → [maekawa](docs/notes/maekawa.md), [kawasaki](docs/notes/kawasaki.md)
1. **Fold arrows.** A crease pattern is not yet instructions; the arrow showing
   *which way* the paper moves is what makes a diagram teachable. FOLD stores no
   arrows, so they are inferred by diffing consecutive frames. Needs a convex
   hull, and therefore needs to care about floating point.
   → [convex-hull](docs/notes/convex-hull.md),
   [robust-predicates](docs/notes/robust-predicates.md)
2. **Faces.** Decode `faces_vertices` into filled polygons, so a sheet reads as
   paper rather than as a wireframe.
   → [half-edge](docs/notes/half-edge.md)
3. **Multi-frame sequences.** Lay out a `file_frames` sequence as a numbered
   grid of steps at a single shared scale. Note that every published FOLD
   example is single-frame, so this needs fixtures we author ourselves.
   → [envelopes](docs/notes/envelopes.md)
4. **Folded forms.** Fold a crease pattern into 3D, then render it
   layer-correctly. The folding itself is cheap; the layer ordering is where the
   real computational geometry starts.
   → [folding-by-transforms](docs/notes/folding-by-transforms.md),
   [fold-angles-are-the-state](docs/notes/fold-angles-are-the-state.md),
   [layer-ordering](docs/notes/layer-ordering.md)
5. **Authoring tools.** FOLD output, and operations on crease patterns.
   → [huzita-hatori](docs/notes/huzita-hatori.md)

## Credits and licence

The FOLD format is by Erik Demaine, Jason Ku and Robert Lang. The example files
in `examples/` marked as such come from the
[reference FOLD repository](https://github.com/edemaine/FOLD) (MIT).

senbazuru is MIT licensed, the same as the FOLD reference
implementation. See [LICENSE](LICENSE).
