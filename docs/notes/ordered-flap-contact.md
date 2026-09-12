# A declared order can stop two flaps from crossing

Take a unit square with parallel creases at 0.3 and 0.7 of its width. The
outside strips are flaps; the middle strip joins them. Ask both creases to
prefer 150°. Each flap can reach that angle without stretching, but the two
then cross. Declaring the left flap below the right makes those preferences
compete with contact: the left closes farther while the right stays more open.

`SurfaceContact` turns declared source-panel orders into separation constraints
on the shared triangle mesh. “Below” means along a supplied direction in the
model, independent of the camera. Where two triangles overlap in projection,
the upper triangle must have at least the lower triangle's height. The gap is
linear across their overlap, so checking its corners bounds the whole overlap.
At least one triangle must be representable as height over that projection.
The other may stand upright: clipping its full 3D corners retains two heights
that project to the same point. Two upright triangles return an explicit
uncheckable error, even if another geometric test could resolve their contact.

The corners of the overlap move too. For example, a corner formed by crossing
two projected edges slides along both edges when either triangle tilts.
Differentiating only the heights at a fixed point gives the solver the wrong
force. A small forward derivative carries each scalar's value and its
sensitivity to vertex movement through clipping and height evaluation. The
ordinary product and quotient rules do the work; shared vertex contributions
add by material id. Finite differences check every coordinate of both a
vertex/face case and a case whose six overlap corners are moving intersections.

`FoldRelaxation.relaxSurfaceContact` uses these derivatives alongside the same
edge-length penalties and angular springs as the earlier bending study. Only
negative separation residuals produce contact forces; separated flaps do not
attract. The control uses a numerical clearance of `10⁻⁶` sheet units between
source panels sharing no material vertex. Joined panels retain zero clearance
so their common crease stays connected. This margin is not paper thickness:
it prevents a tolerated negative residual from leaving a strict intersection
at an otherwise touching edge. There are no displaced graphics copies in this
comparison; the independent checker inspects the saved positions.

Run `stack run senbazuru-material-study -- --bending build/fold-material` and
choose **Opposing flaps · contact correction**. Both solves start from crease
angles 145° and 105°, placing the left flap underneath as they approach. On its
24 triangles the recorded results are:

| Measurement | Without contact | With contact |
| --- | --- | --- |
| Achieved left/right crease angles | 150° / 150° | 160.06–160.12° / 139.47–139.48° |
| Maximum relative edge-length error | `1.34 × 10⁻⁸` | `8.80 × 10⁻⁸` |
| Strict crossing pairs | 6 | 0 |
| Reversed / unresolved / uncheckable pairs | 18 / 0 / 0 | 0 / 0 / 0 |

The corrected solve takes 139 numerical iterations. All saved iterates retain
one connected sheet, original material coordinates and triangle ids. The
independent `PanelContact.checkTriangleContact` checks all 276 triangle pairs,
including pairs inside one source panel. It judges the endpoint separately
from the solver's clearance residual and convergence test.

This is a local correction for supplied orders, not an inference of which
surfaces should meet. Contact can appear discontinuously if a flap enters an
overlapping projection from the wrong side: an initial 65° / 100° control
stalled with about 12% edge error and correctly reported nonconvergence.
Neither line search nor the declared order finds a route around such a
configuration. Clipping derivatives apply to the currently selected features;
changing features can make the objective nonsmooth. The numerical iterations
are not a certified folding path. General contact discovery, collisions within
a source panel, continuous collision detection and physical thickness remain
open. This step is tracked in [#154](https://github.com/avalonalex/senbazuru/issues/154).
