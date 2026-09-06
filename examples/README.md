# Example FOLD files

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

The rest are hand-written here, so they carry no third-party design and no
licence but this repository's. Between them they are what `senbazuru check` is
demonstrated on:

| File                   | What it is                                                     |
| ---------------------- | -------------------------------------------------------------- |
| `unit-square.fold`     | The smallest file with a border, a mountain fold and a valley fold. Note its three interior creases cross at the centre without a vertex there, so it has no interior vertex to check |
| `quarter-fold.fold`    | A square folded into quarters: one interior vertex, four creases, and the lopsided three-mountains-to-one-valley that Maekawa's theorem forces. Its four faces meet at that vertex, which is what makes it the fixture for face filling |
| `three-crease.fold`    | Three creases meeting at a point, which cannot fold flat whatever the angles. `check` reports it |
| `big-little-big.fold`  | A vertex that satisfies both theorems `check` knows and still cannot fold flat, for the reason in [big-little-big.md](../docs/notes/big-little-big.md). `check` passes it, which is the point; `render --fold` refuses it, because its layers cannot be stacked |
| `letter-fold.fold`     | A square folded in three like a letter, with panels of different widths so that the layer order shows. Alternate the creases and it folds into an accordion; make them both valleys and it cannot be folded at all, because the long panel would have to pass through a closed fold |
| `quarter-fold-steps.fold` | The same quarter fold as three frames of a sequence, and the only multi-frame file here. Its folded coordinates were computed by senbazuru's own folding rather than typed out. `--arrows` and `--steps` are demonstrated on it |
