# A fold keeps its turning on a finer mesh; a curve loses it

A mesh bends paper only at its joins, the edges its triangles were cut along
([glossary](../glossary.md#this-project)). Paper bent where the crease pattern
has none shows up as joins bent sharply, and the paper screen calls a join bent
past 45° a *false crease*. But a join can be sharp for two different reasons,
and only one of them is a fault in the pose:

- a **fold**: the pose really bends the paper sharply there, as a crease would;
- a **curve** the mesh is too coarse to follow: each join takes the bend of a
  whole triangle's width of the curve.

Splitting every triangle into four tells them apart. A fold stays sharp, so its
joins stay past the threshold. A curve is sampled twice as finely, so each join
bends about half as far, and soon none reaches the threshold.

**On More tucked, the false creases are folds.** Its construction, made again on
finer meshes:

| Triangles | Joins past 45° | Σ length × angle (sheet sides × degrees) |
| ---: | ---: | ---: |
| 448 | 15 | 144.8 |
| 1,792 | 26 | 142.2 |
| 7,168 | 56 | 140.5 |

The turning holds within 3%, while the number of joins nearly quadruples, since
a finer mesh cuts one fold into more, shorter joins. Counting joins would call
the same fold nearly four times worse, which is why the screen sums length ×
angle instead. These are research note Y3's figures (145, 142 and 141),
reproduced by the study's own construction.

**On a strip bent into a cylinder, the turning vanishes.** Y3's strip, one
sheet side by a quarter, laid exactly on a cylinder turning 270° about lines at
45° across it, is a curve and nothing else. With each cell's diagonal across
the bend:

| Cells along | Largest join | Σ length × angle past 20° | Σ length × angle, every join |
| ---: | ---: | ---: | ---: |
| 8 | 37.3° | 176.4 | 176.4 |
| 16 | 19.0° | 0 | 203.8 |
| 32 | 9.5° | 0 | 216.8 |

**The threshold is what makes the difference.** Summed over every join, a curve
keeps its turning: with the diagonals along the bend instead, the strip's joins
sum to 76.37 at 8, 16 and 32 cells, the same to within 10⁻¹³. That is the
strip's area divided by the cylinder's radius, again to within 10⁻¹³: a
property of the bent paper, not of the mesh. Drop the threshold and a smooth
curve scores like a fold.

**The screen measures both.** Every whole-crane pose that can be made again is
screened on its own mesh and one level finer. Only More tucked keeps its
turning (−1.8%). The other sketches lose 12% to 41% of theirs, curvature their
coarse mesh could not follow, and all still have joins past 45° at the finer
level.

The strip is placed, not relaxed. Y3 relaxed it with a solver, and the ridges
its triangles then formed across the bend made the coarse joins sharper still;
the study's solver did not settle that strip in 400 iterations a stage. The
placed strip tests the measure alone.

`PaperScreen.falseCreaseTurning` is the measure, `WholeCraneScreen.turningOn`
screens a pose one level finer, and `CylinderStrip` is the control. The
argument is PRD 11's (A-11-2) and research note
[Y3](../../PRDs/research/Y3-locking.md).
