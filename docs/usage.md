# Using senbazuru

Building it, running it, and every option the four commands take. For what the
commands are *for*, start at the [README](../README.md); for the format they
read, [fold-primer.md](fold-primer.md).

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

## Running it

```
senbazuru render FILE [-o OUT.svg] [OPTIONS]
senbazuru export FILE [-o OUT.glb] [OPTIONS]
senbazuru check  FILE [--frame N] [--tolerance DEG]
senbazuru info   FILE [--fold] [--layer-budget N]
```

Working from source, reach the executable in any of three ways:

```bash
stack run -- render FILE.fold              # everything after -- goes to senbazuru
stack exec -- senbazuru render FILE.fold   # after a stack build
make install                               # puts senbazuru on your PATH
```

The bare `--` matters. Without it, Stack reads `--view` and the rest as options
of its own and complains about them.

## The files it reads

Every command takes any of three formats, chosen by the file's extension:

| Extension | What it is |
| --- | --- |
| `.fold` | [FOLD](https://github.com/edemaine/FOLD), and anything with an extension senbazuru does not recognise |
| `.cp` | The crease patterns Orihime and [Oriedita](https://github.com/oriedita/oriedita) write: one crease to a line of text |
| `.opx` | The crease patterns [ORIPA](https://github.com/oripa/oripa) writes: the same, in XML |

```bash
stack run -- render examples/bird-base.cp -o bird-base.svg
stack run -- check  examples/bird-base.cp
```

The last two are crease patterns and nothing else. Neither format can store a
face, a fold angle or a second frame, so a file in either of them draws and
checks but does not fold. `render --fold` and `export` say so and stop, because
folding needs to know which pieces of paper move together and only the faces
say that; `--arrows` and `--steps` succeed and find nothing to draw, because
both compare one frame with the next and there is only ever one. Faces can be
worked out from the creases, which is
[#34](https://github.com/avalonalex/senbazuru/issues/34); until then, fold in
Oriedita or ORIPA and export FOLD.

Both formats measure `y` downwards, as the Java editors that write them draw
it, and senbazuru turns that the right way up on the way in. That is a
correction rather than a preference — see
[notes/cp-and-opx.md](notes/cp-and-opx.md) — and it means a pattern read from a
`.cp` is upside down compared with the same `.cp` put through Oriedita's own
FOLD export.

Output is always FOLD, SVG or glTF. senbazuru does not write `.cp` or `.opx`,
because writing one would silently drop whatever the document held that the
format cannot say.

## `render`

| Option | Meaning |
| --- | --- |
| `-o, --output FILE` | Write to a file instead of stdout |
| `--frame N` | Which frame to render (default `0`, the key frame) |
| `--width`, `--height` | Page size in points (default `400`) |
| `--margin` | Blank border in points (default `16`) |
| `--view NAME` | Viewing angle: `top`, `bottom`, `iso`, `front`, `side`. Defaults to `top` for crease patterns and flat-folded models, `iso` for anything with relief |
| `--rotate DEG` | Turn the drawing anticlockwise on the page (default `0`). A folded model lands whichever way up its crease pattern was drawn, and nothing in the file says which way up it should be read — the traditional crane comes out upside down, so its picture in the README is drawn with `--rotate 180` |
| `--transparent` | Omit the white background rectangle |
| `--hide-flat` | Do not draw flat (`F`) or unassigned (`U`) creases |
| `--no-fill` | Draw every crease and fill nothing: a wireframe. Also the way to render a file whose layers cannot be stacked, since nothing then needs to know which is on top |
| `--fold` | Fold the crease pattern along its fold angles and draw the result |
| `--arrows` | Draw the fold that takes this frame to the next one |
| `--steps` | Lay every frame out as one numbered page of figures, at one scale |
| `--columns N` | Figures across the page, with `--steps` (default `3`) |
| `--stacking N[,N...]` | Which layer order to draw, when a model has several: one index per component that has a choice, in the order `info --fold` lists them (default: the first of each) |
| `--layer-budget N` | How many guesses the layer solver may make in one component before giving up (default `1000`) |
| `--offset PT` | Draw a folded model's layers this far apart on the page, so a stack that lands on one spot reads as a stack (default `0`, off). Buried sheets are drawn finer than the model, so a small step still reads |

Some combinations are refused rather than quietly resolved, because they
describe different pictures: `--steps` with `--frame`, with `--fold`, or with
`--stacking`; `--fold` with `--arrows`; and `--arrows` with `--offset`, since an
arrow is drawn at the coordinates the paper actually has and `--offset` draws
every sheet a step away from those.

`--offset` is the one flag that needs the layers rather than merely using them,
so four things are worth knowing about it.

**How big to make it.** The buried sheets are drawn at 0.35pt against the
model's 1 to 1.6, so even a step of a point or two separates them; the limit is
the page rather than the ink. A model a handful of layers deep takes 4 to 6
comfortably. A deep one — the crane is 32 layers — wants a small step and a wide
margin, and is dense whatever you choose, because it really does have 32 layers.
[tour.md](tour.md#how-many-layers-is-too-many) says what printed books do
instead.

**It never changes the size of the drawing.** The page is fitted to the paper,
and opening a stack does not shrink the model to make room, so a large step on a
model that already fills the page runs off it. The answers are a wider
`--margin`, a bigger `--width`, or a smaller step.

**It does nothing under `--no-fill`**, which is the escape hatch that asks no
questions about layers at all.

**It refuses a model whose layers run in a circle** — a twist — because stepping
them apart needs one order for the whole model and there is none. The ordinary
picture of one still draws fine.

## `export`

Writes one frame as a 3D model, in glTF's binary form (`.glb`), which opens in
Blender, three.js, and the built-in viewers on macOS and Windows. The frame is
chosen the way `render` chooses it, and none of the page options apply — a
model has no page.

| Option | Meaning |
| --- | --- |
| `-o, --output FILE` | Write to a file instead of stdout |
| `--frame N` | Which frame to export (default `0`) |
| `--fold` | Fold the crease pattern along its fold angles and export the result |
| `--stacking N[,N...]` | Which layer order to use, as for `render` |
| `--layer-budget N` | As for `render` |
| `--thickness UNITS` | How far apart to place the layers of a flat-folded model, in the model's own units (default: a thousandth of its size) |

A flat-folded model has every face in one plane, and a 3D viewer cannot tell
coincident faces apart — it shows a shimmer of both, called z-fighting. So each
face is lifted by its layer number times the thickness, which is what makes
such a model viewable at all, and is also roughly what real paper does. The
paper's two sides come out in the two colours the SVG uses. A model with paper
still in the air is written exactly as folded, with no separation.

`--thickness 0` writes the paper exactly as folded and asks for no layer order,
which is the only way to export a twist — its layers run in a circle and have
no numbers. [tour.md](tour.md#what-it-exports) has the reasoning and
[notes/paper-thickness.md](notes/paper-thickness.md) the detail.

## `check`

Takes `--frame` as well, and one option of its own.

| Option | Meaning |
| --- | --- |
| `--tolerance DEG` | How far Kawasaki's alternating sum may sit from zero and still pass (default `0.000573`, which is 1e-5 radians). Raise it for files whose coordinates are heavily rounded |

It exits non-zero when it finds a violation, so it drops into a build or a hook
without anyone grepping the output.

## `info`

| Option | Meaning |
| --- | --- |
| `--fold` | Report the layers of each frame folded along its own angles, as `render --fold` draws it. A crease pattern has no layers until it is folded, so this is the only way to see what `--stacking` can choose between |
| `--layer-budget N` | As for `render` |

The `layers` line is where to look when a folded form comes out as a wireframe:
it reports the `faceOrders` the file carries, or, for a folded form without any,
whether one could be worked out and if not why. Where a model has more than one
valid layer order, a `stacking` line follows it with the indices `--stacking`
will accept.

```console
$ senbazuru info examples/crane.fold --fold
...
    layers:   (none in the file; 892 overlapping pairs in 2 components, 5 valid orders)
    stacking: 1 component with a choice; --stacking takes 0-4
```

The two counts differ by one on purpose. The first counts components the way
[Flat-Folder](https://github.com/origamimagiro/flat-folder) does, with the pairs
that were settled outright among them, so that its published figures can be
compared with these. The second counts what you can actually choose. See
[notes/several-stackings.md](notes/several-stackings.md).
