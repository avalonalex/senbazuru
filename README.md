# senbazuru

[![CI](https://github.com/avalonalex/senbazuru/actions/workflows/ci.yml/badge.svg)](https://github.com/avalonalex/senbazuru/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Haskell: GHC 9.6.7](https://img.shields.io/badge/Haskell-GHC%209.6.7-5e5086.svg)](https://www.haskell.org/)

**Origami diagrams from [FOLD](https://github.com/edemaine/FOLD) files.** Hand it
a crease pattern — FOLD, or the `.cp` and `.opx` the desktop editors write — and
get back the picture a book would print.

*Senbazuru* (千羽鶴) is the practice of folding a thousand paper cranes. This is
the version where you fold none of them and still get the pictures.

<table>
<tr>
<td align="center"><img src="docs/img/crane-pattern.svg" width="300" alt="The crease pattern of a traditional crane"></td>
<td align="center"><img src="docs/img/crane-folded.svg" width="300" alt="The same crane, folded flat and drawn as paper"></td>
</tr>
<tr>
<td align="center"><em>what the file says</em></td>
<td align="center"><em>what senbazuru made of it</em></td>
</tr>
</table>

```bash
stack run -- render examples/crane.fold          --rotate 180   -o pattern.svg
stack run -- render examples/crane.fold --fold   --rotate 180   -o crane.svg
```

Same file both times, and the same half turn, so a corner of the square on the
left can be followed to a wing tip on the right. For the second picture
senbazuru folded the sheet along its own angles, worked out which of the
seventy-two faces ends up on top of which, and drew only the parts you could
actually see.

> **Status: early**, and moving. Crease patterns, folding, layer order, hidden
> lines, two-sided paper, opened-out stacks, fold arrows, step-by-step pages, a
> flat-foldability checker, a 3D export, the `.cp` and `.opx` readers, and the
> first authoring verb — draw a crease on a pattern, or straight through the
> layers of a folded model, and write it back out. What it cannot yet do is
> show a model part-way through a fold, or write a folding *sequence*.
> [Roadmap](#roadmap) · [everything that works, at length](docs/tour.md)

## Try it

You need [Stack](https://docs.haskellstack.org/). The build is the slow part;
after that every command is a fraction of a second.

```bash
git clone https://github.com/avalonalex/senbazuru && cd senbazuru
stack build
stack run -- render examples/crane.fold --fold --rotate 180 -o crane.svg
```

Then keep going:

```bash
stack run -- render examples/crane.fold --fold --view bottom --rotate 180 -o underside.svg
stack run -- render examples/quarter-fold-steps.fold --steps --arrows -o steps.svg
stack run -- render examples/quarter-fold.fold --fold --offset 6 -o stack.svg
stack run -- render examples/bird-base.cp --fold -o bird-base.svg
stack run -- check examples/crane.fold
stack run -- export examples/crane.fold --fold -o crane.glb
```

`stack test` runs the suite, which takes about a second once everything is
built. Every flag is in [docs/usage.md](docs/usage.md).

## The interesting part is that paper is opaque

Drawing a crease pattern is easy: the coordinates in the file are already the
coordinates on the page. Drawing a *folded* model is not, and the reason is
layers.

Fold a crane and press it flat, and all seventy-two of its faces lie in the same
plane. Something has to be on top of something else, and nothing in the
coordinates says which — there is no depth left to compare. So senbazuru works
it out, from four local rules about how paper can and cannot interleave, and
finds that the crane has **five** valid answers. All of them are real paper.
Two of them are different pictures. Ku's pinwheel pockets has forty-seven, and
one model in the reference corpus has more than 10⁸³, which is more layer
orders than there are atoms in the observable universe.

Then there are the ones that stack in a *circle*. The four flaps of a twist lie
A over B over C over D over A, with no paper passing through any other and no
order at all to paint four faces in. That model cannot be drawn face by face
however carefully you sort them, so senbazuru draws what is *visible* instead:
over any one point of the page the layers are perfectly well ordered, even when
the whole model is not.

None of that shows in the output, which is rather the point.

## Three pictures a book would print

**A sequence, with the arrows worked out.** FOLD has no key for an arrow, so
senbazuru subtracts one frame from the next to find what moved and where it
went, and lays the whole thing out at one scale — the model genuinely shrinks
as it is folded, because that is what folding does.

<p align="center">
  <img src="docs/img/steps.svg" width="640" alt="A square folded into quarters, drawn as three numbered figures with fold arrows">
</p>

**The underside.** Origami paper is coloured on one side, and `--view bottom`
on a flat-folded model is a different picture rather than the same one upside
down: a different set of faces is on top, and they show the other side of the
sheet. This is the twist whose flaps stack in a circle.

<p align="center">
  <img src="docs/img/pinwheel-underside.svg" width="260" alt="A thirds pinwheel seen from below, its centre showing the back of the paper">
</p>

**The stack, opened out.** Fold a square into quarters and the four quadrants
land exactly on top of one another. The honest picture is one square, and the
reader learns nothing from it, so `--offset` steps the layers apart the way a
book does. The step is in page units: six points whether the sheet is one unit
across or four hundred.

<p align="center">
  <img src="docs/img/quarter-fold-offset.svg" width="260" alt="A square folded into quarters, its four layers drawn stepped apart up and to the right">
</p>

## What it does

- **Draws crease patterns** in the Yoshizawa–Randlett notation every book uses:
  solid for the edge of the paper, dashed for a valley, dash-dot-dot for a
  mountain.
- **Folds them.** Give it a pattern and its fold angles and it computes where
  every face ends up, then draws that from above, below, the front, the side,
  or an isometric angle.
- **Works out which layer is on top** when the file does not say, and tells
  you how many other answers there were so you can ask for a different one.
- **Draws only what you can see**, in two paper colours, with hidden edges
  removed.
- **Opens the stack out**, infers the arrows, and lays a sequence out as one
  numbered page at one scale.
- **Exports a 3D model.** glTF (`.glb`), both sides of the paper in their two
  colours, with a flat-folded model's layers lifted apart so a 3D viewer can
  tell them apart at all — paper has no thickness, and a depth buffer needs
  one.
- **Checks flat-foldability** at every interior vertex by Maekawa's theorem and
  Kawasaki's, and says which vertex fails and why — including the failure that
  is neither theorem, a crease that stops in the middle of the paper.
- **Draws a crease and writes the pattern back out.** `crease` is the one
  command that produces a crease pattern rather than a picture of one. With
  `--folded` it draws the line on the *folded model* and writes the creases it
  makes on the sheet, one per face it crosses — and because alternate layers lie upside
  down, asking for one valley across four layers comes back as mountain,
  valley, mountain, valley, which is what the paper would do.
- **Reads what people actually share.** Most patterns in the wild are not FOLD
  files but Orihime and Oriedita's `.cp` or ORIPA's `.opx`: a flat list of
  creases with the vertices left out. It rebuilds the vertices and carries on.
- **Works out what a file leaves unsaid.** Most patterns record no faces, but a
  crease pattern is a planar graph and its faces are the regions the creases
  cut the sheet into, so it traces them. Creases that cross with no vertex, or
  stop part-way along another, are cut where they meet first — one real ORIPA
  design has seventy-one of those and could not be folded here until it was.

Each of those has a section in [the tour](docs/tour.md), with the command and
the reasoning.

## Things it will not do, so you do not have to find out by trying

- **Turn a crease pattern into instructions.** Nobody can, and the obstacle is
  not compute: the vocabulary of moves a solver would search over has never
  been pinned down ([why](docs/notes/no-sequence-solver.md)). Senbazuru is
  building that vocabulary so a *person* can write a sequence, which is the
  tractable half of the same problem.
- **Inflate a waterbomb.** Every face here is a flat polygon, and an inflated
  balloon's are not. Wet-folding and shaping are outside the model for the same
  reason. Spreading a crane's wings *looks* like the same problem and is not:
  that is angles, and it is on the roadmap.
- **Guess.** A model with no valid layer order is refused with the reason, not
  drawn as something plausible. A file whose faces cannot be traced draws as a
  crease pattern and declines to fold. A mirrored model folds perfectly well
  and is not the model in the file, so the camera turns and the paper does not.

## Why the crane is upside down

Because nothing in a FOLD file says which way up a crease pattern is meant to
be read, and this one lands on its head. `--rotate` turns the *camera*, which
matters more than it sounds: a *mirrored* drawing would look just as right, and
would be a picture of the other crane — the one whose creases are these
reflected, whose mountains and valleys are swapped, and which folds perfectly
well from a square of its own. It is simply not the model in the file.

## Why Haskell, and why so many words

Senbazuru is a learning project as well as a tool, and it is written for a
programmer who is comfortable with Haskell and has never folded anything. So it
is optimised for clarity over cleverness, and it explains itself: every module
header says why the module exists and what a newcomer would get wrong in it,
and [docs/notes/](docs/notes/) holds the theorems, algorithms and traps it runs
on, one idea per file with references. If you know Haskell and not origami,
start with [the primer](docs/fold-primer.md). If you know origami and not
Haskell, start with [the tour](docs/tour.md); the pictures are the same either
way.

## Roadmap

Roughly in order. Each item is an issue tagged
[`roadmap`](https://github.com/avalonalex/senbazuru/labels/roadmap), where the
approach and the acceptance criteria are written out; this list is the map, the
issues are the detail, and the smaller pieces in between are the rest of the
[issue tracker](https://github.com/avalonalex/senbazuru/issues).
[docs/roadmap.md](docs/roadmap.md) is the state of play behind this list,
with every open issue tiered by how hard it is.

1. **[A vocabulary of folds, so a sequence can be authored.](https://github.com/avalonalex/senbazuru/issues/60)**
   FOLD output came first, since nothing else can be built without it, and the
   first move is built: `crease` draws a line on a pattern, or through the
   layers of a folded model, and writes the result out. What is missing is the
   rest of the vocabulary — turning the model over, rotating a flap, and the
   named moves a book uses — and a way to write a whole sequence down. Not a
   sequence *solver*; see above.
   → [huzita-hatori](docs/notes/huzita-hatori.md),
   [round-trips](docs/notes/round-trips.md)
2. **[Folding in three dimensions.](https://github.com/avalonalex/senbazuru/issues/55)**
   A model part-way through a fold, honestly: angles solved for rather than read
   off, so the paper never stretches and never tears. Measure what real angles
   look like first, then the degree-4 closed form, then rotating a flap — which
   covers 41 of the crane's 48 interior vertices without a solver at all — then
   the general solve, then animation over each face's rigid transform.
   Somewhere along it the layers have to stay out of each other, or a spread
   wing sweeps through the body.
   → [fold-angles-are-the-state](docs/notes/fold-angles-are-the-state.md),
   [folding-by-transforms](docs/notes/folding-by-transforms.md)
3. **[A schematic side view of the stack.](https://github.com/avalonalex/senbazuru/issues/50)**
   What a book draws when a model has too many layers to show them all at once,
   and the answer to where `--offset` runs out. The 3D export already gives
   paper a thickness; this should reuse it rather than invent a second one.
   → [paper-thickness](docs/notes/paper-thickness.md)

## Documentation

| Where | What |
| --- | --- |
| [docs/tour.md](docs/tour.md) | Every feature at length, with the command and the reasoning behind it |
| [docs/usage.md](docs/usage.md) | Building it, running it, and every flag of every command |
| [docs/architecture.md](docs/architecture.md) | The pipeline, what each module holds, and the rules about which may know about which |
| [docs/fold-primer.md](docs/fold-primer.md) | The place to start if origami or the FOLD format are new to you |
| [docs/fold-reference.md](docs/fold-reference.md) | Every FOLD key, its type, and whether senbazuru supports it |
| [docs/glossary.md](docs/glossary.md) | Every term the docs and the code assume, in one place |
| [docs/notes/](docs/notes/) | One idea per file, with references: the theorems, algorithms and techniques this leans on or is heading towards |
| [docs/related-projects.md](docs/related-projects.md) | The other tools in this space, their licences, and what each one means for us |
| [docs/roadmap.md](docs/roadmap.md) | Where the project stands, dated: what is done, what is open, how hard each open issue is, and an order |
| [CLAUDE.md](CLAUDE.md) | The working conventions |

## Credits and licence

The FOLD format is by Erik Demaine, Jason Ku and Robert Lang. The example files
in `examples/` marked as such come from the
[reference FOLD repository](https://github.com/edemaine/FOLD) (MIT),
[Flat-Folder](https://github.com/origamimagiro/flat-folder) (MIT) and
[Oriedita](https://github.com/oriedita/oriedita) (MIT); each one's provenance is
in [examples/README.md](examples/README.md). The `.cp` format is Orihime's and
`.opx` is [ORIPA](https://github.com/oripa/oripa)'s; senbazuru's readers for
them were written from the formats, not from either implementation.

senbazuru is MIT licensed, the same as the FOLD reference implementation. See
[LICENSE](LICENSE).
