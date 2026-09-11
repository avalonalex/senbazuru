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
senbazuru crease FILE --from X,Y --to X,Y (--mountain|--valley|--flat|--unassigned)
                      [--folded] [--frame N] [-o OUT.fold]
senbazuru fold   FILE [--frame N] [--stacking N[,N...]] [--layer-budget N] [-o OUT.fold]
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
face, a fold angle or a second frame — but the first two of those are not
losses senbazuru has to live with. The faces are determined by the creases and
are traced from them, and a fold angle follows from a mountain or a valley, so
`--fold` and `export` work on a `.cp` as they do on a `.fold`:

```bash
stack run -- render examples/bird-base.cp --fold -o bird-base-folded.svg
```

What a single frame really cannot give you is a *sequence*: `--arrows` and
`--steps` succeed and draw the pattern, but neither adds anything to it, since
both work by comparing one frame with the next.

One thing this does not change is the flat picture. `render` on a pattern that
records no faces draws a wireframe, as it always has, and filling it is not a
matter of switching the tracing on: some drawings cannot be traced however much
is worked out — a crease that stops in the middle of the paper has no face
round it — and they still have to draw. So the fill follows the file, and
folding does not.

Both formats measure `y` downwards, as the Java editors that write them draw
it, and senbazuru turns that the right way up on the way in. That is a
correction rather than a preference — see
[notes/cp-and-opx.md](notes/cp-and-opx.md) — and it means a pattern read from a
`.cp` is upside down compared with the same `.cp` put through Oriedita's own
FOLD export.

Two things a segment list can describe that a crease pattern cannot, and that
the reader passes through as it finds them: two creases that cross with no
vertex where they meet, and the same crease listed twice.

The first is no longer a problem. `--fold` and `export` cut the creases at the
points where they meet before working out the faces, so a pattern drawn with
crossings folds like any other; `check` still reads it as drawn, so it has one
fewer vertex to look at than the picture suggests — the same under-reporting a
`.fold` file drawn that way gets. The second is refused, naming both creases:
along the stretch two creases share there are two answers to how the paper
folds, and neither is ours to pick.

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

## `crease`

Draws a crease on a pattern and writes the whole document back out as FOLD.
The one command that produces a crease pattern rather than a picture of one.

```bash
stack run -- crease examples/quarter-fold.fold --from 0,0 --to 1,1 --valley -o creased.fold
```

| Option | Meaning |
| --- | --- |
| `--from X,Y` | One end of the crease |
| `--to X,Y` | The other end |
| `--mountain` / `--valley` / `--flat` / `--unassigned` | What kind of crease it is. Exactly one, and required |
| `--folded` | Read `--from` and `--to` on the model the pattern folds into, and crease every layer under that line. What is written out is still the pattern |
| `--frame N` | Which frame to crease (default 0). The others are carried through untouched |
| `-o`, `--output` | Where to write. Default is stdout |

The ends join whatever is already at them: a corner they land on, or a crease
they land in the middle of, which is cut there. Anything the new crease crosses
on the way is cut too, and the faces are worked out again afterwards — so what
comes out is a pattern in the same good order as one that was read.

**A negative coordinate needs the `=` form**, because otherwise the argument
parser reads it as an option:

```bash
stack run -- crease examples/bird-base.cp --from=100,-200 --to=100,200 --flat
```

That is not a corner case. Every `.cp` and `.opx` in existence is drawn on the
square from `(-200, -200)` to `(200, 200)`. (The line above is a vertical one
through the right-hand half of the bird base, which crosses five of its creases
and takes it from 26 creases to 37. Its own diagonals are already creased, so
drawing one of those is refused — see below.)

Four creases it will not draw, each refused naming what is wrong: one with no
length, or with two ends the sheet counts as one point; one drawn along a crease
that is already there, where the paper would have two ways to fold along the
stretch they share; one on a folded form, which is `--folded`'s business below;
and one whose end does not land on any edge or corner the pattern already has,
so it would stop there and divide nothing. The last names the point:

```console
$ senbazuru crease square.fold --from 0,0 --to 3,3 --valley
senbazuru: cannot crease square.fold: the end at (3.0, 3.0) does not meet any crease
or edge the pattern already has, so the crease would stop there and divide nothing
```

It says that rather than "that end is off the paper" because the second is not
always true — [the tour](tour.md#what-it-creases) has the case that shows why.
An end part-way *along* an existing crease is not refused: it meets something.

### `--folded`, creasing through the layers

A book almost never gives its instructions on the flat sheet. Step 4 says "fold
the top corner down" about paper that was folded in half in step 2, and the
reader is creasing every layer under their fingers at once. `--folded` is that
move: the two ends are read on the model the pattern folds into, and what comes
back is the pattern with everything that line creases marked on it.

```bash
stack run -- crease examples/diagonal-cp.fold --folded --from 0,0.5 --to 0.5,0 --valley
```

`diagonal-cp.fold` is the unit square with a valley down the diagonal, so it
folds in half onto a triangle. That command draws the triangle's midline, which
reaches both layers, and the pattern comes back with two new creases —
mirror images about the existing fold, and **one of each kind**:

| | |
| --- | --- |
| `(0, 0.5)` to `(0.5, 0)` | valley, as asked |
| `(0.5, 1)` to `(1, 0.5)` | **mountain** |

That is not a bug and it is what paper does. Every layer of a packet creases the
same physical way, but a flap folded over is upside down, so the same fold is a
valley where the sheet is face up and a mountain where it is face down. Fold a
square in half, crease the packet, unfold, and you have one of each. Ask for a
valley across the quarter fold, which is four layers, and the kinds alternate
through the stack: mountain, valley, mountain, valley. Which way up a layer lies
flips across every crease the paper actually folds along, so it is a parity count
of the folds between that layer and whichever face was held still.

A line drawn on a folded model is **one crease per face it crosses**, which is
not the same as one per layer and is usually more: across the folded crane, the
worst line crosses 56 of its 72 faces, where the deepest stack of paper found
over any single point is 24 and the deepest layer number is 32.

**Neither end may be in the middle of a face**, because that layer would then be
creased only part of the way across, and a crease that stops in the middle of
the paper divides nothing:

```console
$ senbazuru crease examples/bird-base.cp --folded --from=-200,150 --to=-100,150 --valley
senbazuru: cannot crease examples/bird-base.cp: --from is inside face 12 of the folded
model rather than on that face's edge, so that layer would be creased only part of the
way across. Each layer the line reaches has to be creased right across, so move this
end onto an edge or clear of the paper
```

An end *on* a face's edge is fine, wherever it is — including well inside the
model's outline. What matters is only that every layer the line reaches gets
creased right across, and an end sitting on the edge of each face it touches
does exactly that. This is why a line can be drawn from one crease of the
quarter fold to another.

How often a crease of a folded model is such a place depends on whether the
layers' edges line up there, and that varies a lot. Of the folded crane's 248
face-edge midpoints, 120 sit on the edge of every face they touch; the other 128
are in the middle of some other layer's paper and are refused. The bird base
splits 24 to 20. The quarter fold, whose four layers land exactly on top of one
another, is 16 to nothing.

Moving that end off the paper creases the bird base through all fourteen of its
layers, and the result folds:

```bash
stack run -- crease examples/bird-base.cp --folded --from=-300,150 --to=-100,150 --valley -o bird.fold
```

Three things it will not do. It creases *every* layer under the line — "fold the
top layer only" is a different instruction, and is part of
[#60](https://github.com/avalonalex/senbazuru/issues/60). It wants a model that
folds *flat*, because a line drawn on the page of a model with paper still in
the air is a ray rather than a point and names no one place on the sheet. And it
takes the **pattern**, not a file that is already a folded form: the line is
mapped back by undoing the motion that placed each face, and those motions exist
only because we did the folding. A file that arrives already folded carries
neither them nor a sheet to map back to, and recovering one is unfolding.

Without `--folded` a folded form is refused outright, as it always was: the
regions between a folded form's creases are not its faces, so there is nothing
to draw a line on.

## `fold`

Folds a crease pattern and writes the folded shape out as FOLD, with the layer
order it worked out. `render --fold` computes all of this and then draws it;
this is the same computation with the answer kept.

```bash
stack run -- fold examples/crane.fold -o crane-folded.fold
stack run -- render crane-folded.fold -o crane.svg     # the same picture, from the file
```

| Option | Meaning |
| --- | --- |
| `--frame N` | Which frame to fold (default 0, the key frame) |
| `--stacking N[,N...]` | Which layer order to write, when the model has several. `info --fold` lists the choices |
| `--layer-budget N` | How many guesses the layer solver may make before giving up |
| `-o`, `--output` | Where to write. Default is stdout |

**One frame comes out, and it is the folded shape.** The other frames of the
input are not carried through, and neither is the pattern: the input file still
holds it, and a file whose first frame is a folded form followed by the flat
sheet is a picture of the model coming undone, since `--steps` draws frames in
file order.

What comes out carries `frame_classes: ["foldedForm"]`, 3D coordinates when the
model leaves the plane, the fold angles it folded by, and `faceOrders` when the
layer order can be worked out. A model the solver does not cover — one not
folded flat, or with a face that is not convex — gets no `faceOrders` rather
than an empty list, because "no two faces overlap" and "nobody knows" are not
the same claim.

Two deliberate omissions. The vendor keys of the input do not survive, which is
[#73](https://github.com/avalonalex/senbazuru/issues/73): folding rewrites every
coordinate, and nothing can judge which unknown keys still hold. And
`file_creator` is left alone, so a file that says another tool made it goes on
saying so; `crease` behaves the same way.

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

## Fold-material experiment

`stack run senbazuru-material-study -- build/fold-material` generates a single fold
and two perpendicular folds, with sharp and rounded variants plus a before/after
length and contact correction. It produces a rotatable viewer, baseline SVG previews,
indexed OBJ and FOLD surfaces for each recorded checkpoint, material-length
measurements and solver progress. Open
`build/fold-material/index.html`. The [study guide](../study/fold-material/README.md)
explains how to run and inspect it. The corrected double fold meets both its
edge-length and packet-order targets. The viewer also reports crossings in
unfinished iterations. Bending stiffness, crease-angle preferences, finite
thickness and general collision handling remain unsolved. Solver checkpoints
have no SVG preview because the study painter would hide intermediate crossings. This experiment does not change
`render` or `export`.

The [fish and bird fixtures](../examples/README.md#fish-and-bird-bases-opening-and-reshaping-flaps)
can be drawn with `render examples/fish-base.fold --fold` and
`render examples/bird-base.fold --fold`. Their crease patterns and closed
endpoints are checked. In the study viewer, select **Fish base** for fifteen
states gathering its two rabbit ears in sequence. The first stays at its 175°
inspection state while the second moves; the final view leaves both slightly
open. Select **Bird base** for sixteen states: the square base, the first petal,
the second petal on the underside, and a final press of both petals to the flat
bird base. During the second stage, the first petal stays at 175°. Drag to see
the underside. Continuous collision certification and paper thickness remain
unsupported; see [the study guide](../study/fold-material/README.md#two-petals-form-the-bird-base).

The checked bird sequence is also an ordinary FOLD example for the main CLI:

```bash
stack run -- render examples/bird-base-sequence.fold --steps --columns 4 --view iso --width 1000 --height 1000 -o bird-steps.svg
stack run -- render examples/bird-base-sequence.fold --steps --columns 4 --view bottom --width 1000 --height 1000 -o bird-underneath.svg
stack run -- render examples/bird-base-sequence.fold --frame 12 --view iso -o second-petal.svg
```

Frame zero holds file metadata; frames 1–16 are the folding states, so frame
12 shows the second petal at 90°. These frames already contain folded geometry;
omit `--fold`. The page keeps one camera and scale and adds no arrows unless
requested. Open convex planar panels use depth over projected overlaps to hide
covered paper and creases. Coplanar contact still needs `faceOrders`.
Intersecting depths, unsupported faces and free edge-on outlines retain the
older fallback. `--no-fill` remains available for a wireframe, including a file
whose faces are malformed. See [the visibility note](notes/projected-panel-visibility.md).
