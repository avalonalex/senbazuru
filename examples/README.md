# Example crease patterns

`diagonal-cp.fold`, `squaretwist.fold` and `simple.fold` are taken from the
reference FOLD repository at <https://github.com/edemaine/FOLD/tree/main/examples>
(MIT licensed) and are kept here so the renderer is always exercised against
files it did not produce itself.

They were chosen because between them they cover the awkward parts of the
format:

| File                | What it exercises                                              |
| ------------------- | -------------------------------------------------------------- |
| `diagonal-cp.fold`  | A 2D crease pattern; `file_spec` of `1.1`; the vendor key `cpedit:page` |
| `simple.fold`       | 3D `foldedForm` coordinates, mountain and valley edges, and the only `faceOrders` in the repo — so it is the fixture for layer-correct drawing |
| `squaretwist.fold`  | A larger rigidly-folded 3D model                                |

Five more come from [Flat-Folder](https://github.com/origamimagiro/flat-folder)
(MIT), Jason Ku's flat layer-order solver, whose `examples/` folder ships 755
crease patterns, 741 of them with a row in a table of how its solver fared. They are copied
byte for byte from its `main` branch at commit `d50004815fb7` (2026-06-24), so
a diff against upstream is meaningful, and their `file_author` is as upstream
wrote it. They are here as the first real models in the suite and as a
cross-check: `Senbazuru.Origami.StackingSpec` compares the constraints our
solver generates for the four that have a row, kind by kind, against the counts
in that table; the fifth comes from the `unsatisfiable/` folder, which has no
table, and is tested for refusal.

A repository licence is not a design licence, so only three groups were taken.
The traditional models have no author to ask. Jason Ku's own designs are his to
license, and he licensed the repository. Daniel Brown's grids are an exhaustive
enumeration of the flat foldings of a small grid rather than a design. Every
other file in that folder is another designer's work and stays there.

| File                   | Upstream file, and what it is for                              |
| ---------------------- | -------------------------------------------------------------- |
| `crane.fold`           | `instagram/004_traditional_Crane.fold`. 72 faces, 20 flat creases, 5 valid stackings in 2 components. The first model in the suite that looks like anything; a golden |
| `kabuto.fold`          | `instagram/002_traditional_Kabuto.fold`. The samurai helmet: 18 faces, 9 valid stackings |
| `thirds-pinwheel.fold` | `instagram/006_ku_Thirds_Pinwheel.fold`. A twist with one valid stacking: its four flaps stack in a circle, which is a valid layer order and one that painting faces whole cannot draw. It is the fixture for drawing by visible regions instead |
| `bad-twist.fold`       | `unsatisfiable/001_ku_Bad_Twist.fold`. Folds without tearing and has no valid stacking at all; the solver must refuse it |
| `grid-2x2-d1.fold`     | `grids/002_brown_2x2_D1.fold`. 25 faces, 16 valid stackings in 5 components, and another twist |

One is not a FOLD file at all. `bird-base.cp` is Oriedita's own
`oriedita-data/src/test/resources/birdbase.cp`, copied byte for byte from
[oriedita/oriedita](https://github.com/oriedita/oriedita) (MIT) at commit
`c02a5442` (2026-06-12) and renamed to match the hyphenated names here. The
file itself has not changed since 2022.

It is the traditional bird base, so there is no designer to ask, and it is the
first real base in the suite. It is also the fixture for reading the `.cp`
format, which is why a hand-written one would not do: 26 lines of text, `y`
measured downwards, no vertices, no faces, and six creases meeting at a centre
the file spells three different ways. Its 52 endpoints are 22 distinct
spellings of 13 vertices, so a reader that does not merge them gets a bird base
in 22 disconnected pieces. See
[docs/notes/cp-and-opx.md](../docs/notes/cp-and-opx.md).

The rest are hand-written here, so they carry no third-party design and no
licence but this repository's. Between them they are what `senbazuru check` is
demonstrated on:

| File                   | What it is                                                     |
| ---------------------- | -------------------------------------------------------------- |
| `unit-square.fold`     | The smallest file with a border, a mountain fold and a valley fold. Its three interior creases cross at the centre without a vertex there, which earns it three jobs: `check` finds no interior vertex to look at, `Senbazuru.Fold.Crossings` cuts it into six creases through one new vertex, and the result folds and then cannot be *stacked* — its 2 mountains and 2 valleys at right angles are what Maekawa's theorem forbids, showing up as layers that would have to pass through each other |
| `quarter-fold.fold`    | A square folded into quarters: one interior vertex, four creases, and the lopsided three-mountains-to-one-valley that Maekawa's theorem forces. Its four faces meet at that vertex, which is what makes it the fixture for face filling |
| `three-crease.fold`    | Three creases meeting at a point, which cannot fold flat whatever the angles. `check` reports it |
| `big-little-big.fold`  | A vertex that satisfies both theorems `check` knows and still cannot fold flat, for the reason in [big-little-big.md](../docs/notes/big-little-big.md). `check` passes it, which is the point; `render --fold` refuses it, because its layers cannot be stacked |
| `puffed-square.fold` | Not a fold at all: a unit square on a 10×10 grid, each cell cut into two triangles, lifted by `z = 0.25 sin(πx) sin(πy)`, every interior edge `F`. Generated, so it carries no design. It is the method a puffed crane body would use, at the smallest size that shows it, and the fixture for drawing a curved surface as a mesh of flat faces — see [docs/notes/the-puff-is-a-drawing.md](../docs/notes/the-puff-is-a-drawing.md) |
| `letter-fold.fold`     | A square folded in three like a letter, with panels of different widths so that the layer order shows. Alternate the creases and it folds into an accordion; make them both valleys and it cannot be folded at all, because the long panel would have to pass through a closed fold |
| `quarter-fold-steps.fold` | The same quarter fold as three frames of a sequence, and the only multi-frame file here. Its folded coordinates were computed by senbazuru's own folding rather than typed out. `--arrows` and `--steps` are demonstrated on it |
| `book-base.fold`       | The simplest fold there is: one crease, two faces, two layers. Nothing smaller exercises folding at all, which is what makes it the first case for [#114](https://github.com/avalonalex/senbazuru/issues/114) |
| `accordion.fold`       | Four equal panels folded back and forth. The four layers land exactly on top of one another, as the quarter fold's do, but there is no interior vertex anywhere — so it is the quarter fold's stacking problem with the hard part removed |
| `blintz-base.fold`     | Four corners folded to the centre. Its creases are oblique, and its four flaps tile the diamond they fold onto exactly, so the folded form is one shape with eight edges hidden inside it. Draw it with `--view bottom`: the flaps are on the far side from the default camera, and from above it is a plain diamond |
| `crease-stops.fold` | Two creases that divide no paper: one running to a point in the middle of the sheet, and one ending part-way along a flat line, where the paper is continuous and three drawn lines leave one crease. What `check` reports as neither of its two theorems. |

## The base folds, and what they are for

`book-base.fold`, `accordion.fold` and `blintz-base.fold` are the first rung of
a ladder of traditional bases, and they are here for
[#114](https://github.com/avalonalex/senbazuru/issues/114): senbazuru draws a
folded stack as though the layers were loose sheets, because it never draws the
paper that wraps around a fold. `docs/img/quarter-fold-offset.svg` is the
symptom — four squares with nothing joining them.

**What these three have in common is that none of them has an interior
vertex.** Every crease runs between two points on the border, so `check` skips
every vertex and reports so. That is the point rather than a shortcoming. Where
several creases meet, the rounded folds interact and the surface is no longer
developable, which is the one part of #114 that has no clean answer; these
three let the fold radius and the layer separation be got right before anything
has to be decided about vertices.

They are traditional forms with no single author, and they are generated rather
than copied, so they carry no design and no licence but this one.
