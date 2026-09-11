# Pictures in the docs

senbazuru's own output, committed so the README can show what the tool does
rather than describe it. SVG rather than PNG because that is what the tool
produces: they are the actual files, small, and a diff on one is readable.

Regenerate them all after a change that alters the drawing, and read the diff
the way a golden file's diff is read — these are goldens in every sense except
that no test fails when they drift.

```bash
stack run -- render examples/crane.fold --rotate 180                      -o docs/img/crane-pattern.svg
stack run -- render examples/crane.fold --fold --rotate 180               -o docs/img/crane-folded.svg
stack run -- render examples/thirds-pinwheel.fold --fold --view bottom    -o docs/img/pinwheel-underside.svg
stack run -- render examples/quarter-fold-steps.fold --steps --arrows \
  --width 720 --height 260                                                -o docs/img/steps.svg
stack run -- render examples/quarter-fold.fold --fold --offset 6 \
  --width 260 --height 260 --margin 28                                    -o docs/img/quarter-fold-offset.svg
stack run -- render examples/bird-base.cp                                 -o docs/img/bird-base.svg
stack run -- render examples/puffed-square.fold --view iso                -o docs/img/puffed-square.svg
```

| File | What it shows |
| --- | --- |
| `crane-pattern.svg` | The traditional crane as its file stores it: a crease pattern, in the Yoshizawa–Randlett line notation. Turned to match the folded one beside it, so the two can be read together |
| `crane-folded.svg` | The same file folded and drawn — 72 faces stacked, hidden edges gone. Turned half a turn, because the crane lands upside down: a folded model sits whichever way up its crease pattern was drawn |
| `bird-sequence-preview.svg` | Four checked bird-base states at one scale, seen from 45° above: square base, each petal lifted to 90°, then the completed base. The main README preview, generated through the production step renderer |
| `pinwheel-underside.svg` | A twist from below, where the back of the paper shows in the other colour |
| `steps.svg` | A square folded into quarters as three numbered figures, with the arrows worked out by subtracting each frame from the next |
| `quarter-fold-offset.svg` | The same quarter fold, its four coincident layers stepped apart. Drawn with a wider margin than the default, because the offset pushes the stack outside the extent the page is fitted to and would otherwise touch the edge |
| `bird-base.svg` | The traditional bird base, read from a `.cp` file rather than a `.fold` one. The valley along the diagonal runs from lower left to upper right; it runs the other way in the file, which measures `y` downwards |
| `puffed-square.svg` | A square bulged into a dome, as a mesh of 200 flat faces with 3D coordinates, drawn face by face with its mesh lines showing. Hide them and the dome vanishes, which is what [notes/the-puff-is-a-drawing.md](../notes/the-puff-is-a-drawing.md) is about |

The crane and the pinwheel come from [Flat-Folder](https://github.com/origamimagiro/flat-folder)
and the bird base from [Oriedita](https://github.com/oriedita/oriedita); all
three are traditional designs, and their provenance is in
[examples/README.md](../../examples/README.md).

The four `material-{sharp,rounded}-{single,double}.svg` previews are generated
here, without third-party fixtures:

```bash
stack run senbazuru-material-study -- build/fold-material
cp build/fold-material/sharp-single.svg docs/img/material-sharp-single.svg
cp build/fold-material/sharp-double.svg docs/img/material-sharp-double.svg
cp build/fold-material/rounded-single.svg docs/img/material-rounded-single.svg
cp build/fold-material/rounded-double.svg docs/img/material-rounded-double.svg
```

Inspect them before copying. They illustrate the
[rounded-bend counterexample](../notes/two-bends-need-more-than-radii.md) and
[sharp-crease comparison](../notes/sharp-creases-and-opening-panels.md),
not production `render` output.

The main README's bird sequence preview is production `Render.Steps` output
from the study's checked bird states, with the same 45° camera as the full
sequence page. It selects zero-based state indices 0, 4, 11 and 15, without
interpolating positions. Regenerate it with:

```bash
stack run senbazuru-material-study -- --bird-svg build/fold-material
cp build/fold-material/bird-sequence-preview.svg docs/img/bird-sequence-preview.svg
```

Read the SVG diff and inspect the picture before committing it. The ordinary
FOLD source is `examples/bird-base-sequence.fold`; the preview is a selection
of its states, not a complete set of folding instructions.
