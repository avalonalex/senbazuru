# A fold keeps its turning on a finer mesh; a curve loses it

The study draws paper as a mesh of flat triangles, and between two triangles
the paper can bend only along the edge they share. Some of those edges are
creases, where the crease pattern says the paper folds. The rest are *joins*,
the edges each flat region of the pattern was cut along to make triangles,
which a written frame assigns `J` ([glossary](../glossary.md#the-fold-format)).
A join is not meant to fold, so the paper screen calls a join bent past 45° a
*false crease*. It measures a pose's false creases by their *turning*: over
those joins, the sum of each one's length on the flat sheet times its bend in
degrees, in sheet sides × degrees (the flat square's side is 1).

A join can be sharp for two reasons, and only one of them is a fault in the
pose:

- a **fold**: the pose bends the paper sharply along a line, as a crease would;
- a **curve** the mesh is too coarse to follow: each join takes the bend of a
  whole triangle's width of the curve.

Splitting every triangle into four is meant to tell them apart. A fold stays
sharp, so its joins stay past the threshold and its turning stays the same. A
curve is sampled twice as finely, so each join bends about half as far, and
soon none reaches the threshold.

**On a strip bent into a cylinder, the turning vanishes.** The control is
research note Y3's strip: one sheet side long and a quarter wide, cut into
square cells with one diagonal each, and laid exactly on a cylinder that turns
it through 270°, whose straight lines run at 45° across it. It is a curve and
nothing else. With each cell's diagonal across the bend:

| Cells along | Largest join | Turning past 20° | Turning, every join |
| ---: | ---: | ---: | ---: |
| 8 | 37.3° | 176.4 | 176.4 |
| 16 | 19.0° | 0 | 203.8 |
| 32 | 9.5° | 0 | 216.8 |

The threshold is 20°, not the screen's 45°, because placed exactly on its
cylinder the strip bends no join as far as 45° at any of these resolutions.
PRD 11 sets 20° for this strip (A-11-2), and it falls between the coarse
strip's largest join and the finer one's.

**Summed over every join, a curve does not fade, which is why the measure has
a threshold.** Without one, the finer strip scores 203.8, more than More
tucked's false creases below. But that sum is not a property of the curve; it
depends on how the cells are cut. Cut along the bend, every diagonal lies on
one of the cylinder's straight lines, and the triangles either side of every
other edge lie flat together, so the diagonals carry the whole bend. They sum
to 76.37 at 8, 16, 32 and 64 cells, to within 10⁻¹²: the strip's area divided
by the cylinder's radius. The strip spans 1.25/√2 across the straight lines
and turns 3π/2 across that span, so its radius is 1.25/(1.5π√2), and its
area, a quarter, over that is 0.3π√2 radians, or 54√2 degrees. Cut across the
bend, the diagonals bend against the curve and the cell sides with it; at 64
cells they sum to −76.3 and +146.7, and a sum of sizes counts both. So it
grows as the cells shrink, by about half as much each time, toward about 229,
three times 76.37 (223.0 at 64 cells).

**On More tucked, the false creases hold for three levels, then go.** More
tucked is one of the whole-crane gallery's *shape sketches*, poses built by
placing vertices where the crane should be rather than by folding paper
([glossary](../glossary.md#this-project)): the one with its wings held
highest. Its construction, made again on finer meshes:

| Triangles | Joins past 45° | Turning past 45° | Turning past 20° |
| ---: | ---: | ---: | ---: |
| 448 | 15 | 144.8 | 272.4 |
| 1,792 | 26 | 142.2 | 268.5 |
| 7,168 | 56 | 140.5 | 213.8 |
| 28,672 | 87 | 95.5 | 173.7 |
| 114,688 | 45 | 20.0 | 130.1 |

For three levels the turning holds within 3% while the number of joins nearly
quadruples, since a finer mesh cuts one bend into more, shorter joins.
Counting joins would call the same bend nearly four times worse, which is why
the screen sums length × angle. These are research note Y3's figures (145, 142
and 141), reproduced by the study's own construction, and on them Y3 and
PRD 11 call these false creases folds. The two finer levels, too slow for the
test suite and measured once, say otherwise: the turning drains away. So they
are not folds but bends narrower than the triangles of the first three
meshes, which could not tell them from folds. Agreement over two or three
levels does not show a fold.

**The screen measures two levels.** Every whole-crane pose is screened on its
own mesh and again with every triangle split into four, and passes the
false-crease part only with no join past 45° at either. The first candidate,
placed around a saved body, is not made again, so it cannot pass that part.
The other sketches lose 13% to 41% of their turning one level finer, and all
still have joins past 45° there; two levels cannot say how much of that loss
is curvature.

**The strip is placed, not relaxed.** Y3 held both end columns of cells on the
cylinder and relaxed the rest with a solver, whose ridges across the bend
("locking") made the coarse joins sharper still, up to 43.5° at 16 cells. The
study's solver cannot repeat that. It stops only when every edge is within
10⁻⁵ of its flat length, and an edge between two held vertices is a chord of
the cylinder, 0.1% to 0.9% shorter than the paper it spans on the strips
tried, which nothing moves. The placed strip's chords are short too, up to
3.7% at 8 cells cut across, but the measure takes its lengths from the flat
sheet, and a control only needs its vertices on the curve.

`PaperScreen.falseCreaseTurning` is the measure, `WholeCraneScreen.turningOn`
makes a pose again and measures it there, and `CylinderStrip` is the control.
The argument is PRD 11's (A-11-2) and research note
[Y3](../../PRDs/research/Y3-locking.md)'s.
