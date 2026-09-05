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
