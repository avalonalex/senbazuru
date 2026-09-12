# A crease keeps its identity when the mesh gets finer

Start with a square whose diagonal is edge 4. Dividing that edge into four
short segments does not create four different folds: all four still belong
to crease 4. Each segment needs the same preferred angle, and the sum of their
spring stiffnesses should equal the stiffness of the original crease.
A diagonal introduced only to triangulate a panel is different: it represents
uncreased paper, so its preferred bend is zero.

`Origami.Surface.refineSurfaceWithEdges` now carries source edge ids through
midpoint subdivision alongside panel ids. It matches endpoints by vertex id,
then splits each recorded segment at the same midpoint used by its neighboring
triangles. It never identifies creases from coordinates. Two cut edges may
have identical coordinates but distinct ids and therefore distinct midpoints.
`refineSurface` is a convenience view of that same refinement, returning only
the mesh and panel ids. Source edges absent from the triangulation are omitted
from the segment map; the mechanics adapter refuses a required crease that
is absent or fails to join two panels.

`FoldBending.buildSurfaceHinges` accepts a shared surface, a refinement level,
stiffnesses and an explicit `Map EdgeId Double` of preferred angles in radians.
Ids refer to the surface's **cut pattern**, because cutting crossings may
renumber edges. These controls are separate from `edges_foldAngle`, which
records the current pose. Reading 60° from a starting pose must not silently
tell the solver that 60° is already the desired equilibrium.
Positive controls are valleys and negative ones mountains; an unassigned
crease needs an explicit signed control too. Missing controls, boundary-edge
controls, inconsistent signs and duplicate crease ownership are errors.
Flat face divisions and ordinary mesh diagonals retain zero-bend springs.
The same angular-energy code still supports the original coordinate-defined
packet controls; only their fixture adapter knows those coordinates.

The expanded `bending.html` compares two additional equilibria on unit sheets.
These numbers come from running the compiled `--bending` gallery command:

| Example | Triangles | Starting angles | Preferred and achieved angles | Maximum relative edge error | Iterations |
| --- | --- | --- | --- | --- | --- |
| Diagonal fold | 32 | 60° | 120°, within 0.000002° | `4.43 × 10⁻⁹` | 4 |
| Kite flaps | 64 | 75° / 110° | 150° / 165°, within 0.000001° | `1.71 × 10⁻⁸` | 5 |

Both have compatible rigid solutions: panels can remain flat while creases
meet the targets. The solver finds their positions by reducing length and
angular errors. It does not use the known final positions. Original material
coordinates, triangle connectivity and crease ownership stay fixed.

These two solves have no contact force. Separately,
`PanelContact.checkTriangleContact` checks every pair of triangles in each
recorded state, including pairs within a source panel. Declared source-panel
orders expand to their triangles along the stored material direction. The
final diagonal and kite states pass 496 and 2,016 pair checks respectively:
no strict crossings, unresolved coplanar overlap, reversed orders or
uncheckable order comparisons at the `10⁻⁷` unit-sheet tolerance.
A failed diagnostic is reported; it cannot push paper apart. Strict crossing
checks permit touching edges and creases, so this is not a general certificate
against every form of self-contact. Numerical attempts are not a folding path,
and no check certifies the motion between them. General contact correction,
calibrated stiffness and controlled opening remain later work.

The [energy note](crease-and-panel-energy.md) explains the unchanged springs
and solver. This adapter is tracked in
[#152](https://github.com/avalonalex/senbazuru/issues/152), following #150.
