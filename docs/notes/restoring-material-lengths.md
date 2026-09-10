# Fit lengths and keep layers in order

The [sharp double fold](sharp-creases-and-opening-panels.md) looks like a square
folded in half twice, but its longest mesh edge has gained 0.538% in length.
Each vertex still remembers its original coordinates `(u,v)` on the sheet.
Those coordinates tell us what every edge's length should be, independently
of where we drew the folded paper. The next experiment in
[the material study](../../study/fold-material/README.md) corrects those lengths
while keeping the layers from passing through one another.

For an edge joining material points `(0,0)` and `(0.03125,0)`, the target is
`0.03125`. If its folded endpoints are `p` and `q`, its error is
`length(q-p) - 0.03125`. Correcting one edge at a time can undo a neighbouring
edge's correction because they share a vertex. `FoldRelaxation` instead
approximates how **all** edge errors respond to small vertex movements, then
chooses those movements together. This is the Gauss–Newton method: repeatedly
solve the locally linear version of a nonlinear problem.

Lengths alone are insufficient. In an initial run, `relaxLengths` reduced the
maximum edge error to 0.000994% but produced an ochre patch near the crease
intersection. A lower layer had risen through an upper one by as much as
`0.0002908163` model units. That was a geometric crossing, not the coincident
triangle or lighting problem fixed in the earlier study. `relaxPacket` adds a
penalty for such reversals, using `FoldContact` to measure them.

The contact check uses the prescribed bottom-to-top order of the packet's
panels. It projects each triangle onto the horizontal plane, finds each pair's
overlapping footprint with the existing convex polygon clipper, and compares
heights at every corner of that overlap. Height differences are linear inside
the overlap, so their largest reversal occurs at a corner. This also catches
crossings between triangle edges when neither triangle contains an original
vertex of the other. A pair counts only if its overlap exceeds `1e-14` square
model units; an edge-on triangle is reported as unchecked. These numerical
thresholds apply to the study's unit square, not arbitrary scales.

The combined error vector `r` contains the edge errors and **ten times each
negative layer gap**, where a positive gap means the upper layer is above the
lower one. Squaring this vector weights contact errors by 100. This is a
numerical penalty, not a measured material stiffness. A separated pair has no
penalty: attracting it towards zero gap would glue the layers together.
Write `J` for the derivatives of these errors with respect to vertex positions.
The proposed correction `d` solves:

```
(transpose(J) * J + 1e-8 * I) * d = -transpose(J) * r
```

Here `I` leaves a vector unchanged. The small extra term penalises movement
within this numerical step. Lengths and contact cannot distinguish a packet
from a translated copy, and many bending movements are also free. The penalty
makes the linear solve well-defined without fixing arbitrary vertices in place.
It does not represent bending stiffness or a preference for the original shape.

An edge contributes just two nonzero vectors to its row of `J`: minus its unit
direction at one endpoint and plus that direction at the other. Contact needs
more care: an overlap corner moves with the triangles. At a vertex/face contact,
use the face's normal; at an edge/edge contact, use a direction perpendicular to
both edges. The header of `FoldContact` records the construction. A test compares
these derivatives against small measured perturbations, including horizontal
movement; treating the intersection point as stationary gives the wrong result.

The solver applies the matrix by walking these sparse rows, without allocating
a dense matrix. Conjugate gradients finds an approximate solution using only
matrix-vector products. The coupled solve first rescales each coordinate by the
matrix's diagonal, called **diagonal preconditioning**: the strong, mostly
vertical contact corrections otherwise drown out the in-plane length changes.
Each outer iteration allows up to 600 inner iterations (300 for lengths alone).
A line search tries the correction at full size, then halves it up to 30 times,
accepting only a reduction in the combined sum of squared errors. Even errors
smaller than the stopping tolerance contribute to both that sum and its
derivatives; dropping them from only the derivatives can stall the solve.

The combined sum can decrease while an individual constraint gets worse, so
convergence measures both targets afresh: maximum absolute relative edge error
at most **0.001%**, and maximum packet-order reversal at most **`1e-7` model
units** (0.00001% of the sheet's side). These are numerical tolerances, not a
claim of exact isometry or a paper thickness. Hitting the 100-iteration limit is
recorded separately from meeting both targets.

Running this command produces the measurements, recorded checkpoints and an
offline viewer with the same camera and scale on both sides of the comparison:

```bash
stack run senbazuru-material-study -- build/fold-material
```

On the double fold's 1,089 vertices and 2,048 triangles, this run measured:

| Solver iteration | Maximum absolute edge error | Maximum layer reversal, model units |
| --- | ---: | ---: |
| 0 | 0.537860% | 0 |
| 5 | 0.249461% | 0.000011869 |
| 10 | 0.064426% | 0.000003979 |
| 20 | 0.014503% | 0.00000000425 |
| 50 | 0.001923% | 0.00000000337 |
| 69 | 0.000852% | 0.00000000324 |

Both targets are met at the final checkpoint, with no triangle pairs violating
the packet order beyond the contact tolerance. The orange patch is gone in the
depth-buffered viewer. The single fold already preserves lengths and layer order,
so it stops at iteration zero. All shared vertex indices and material coordinates
remain intact; the final double fold's area ratio is `1.0000000806`.

A triangle's three exact edge lengths fix its shape within the surface, but a
finite edge tolerance is not that same tolerance in every direction. The viewer
also measures **principal strains**: the greatest compression and extension
over all directions in each triangle. It derives the two spatial vectors for
unit material steps in `u` and `v`, then finds the smallest and largest length
multipliers of that linear mapping. The final double fold ranges from
**−0.000919% to +0.001458%**. Both heat maps use a fixed −1% to +1% range and
show the principal strain with larger magnitude, so rescaling colours cannot
disguise the change. The numerical cards report actual mesh edges.

The comparison displays computed checkpoints, not positions interpolated between
them. Iterations correct a posed mesh; they are neither physical time nor a
folding instruction sequence. Intermediate checkpoints can still cross. They
have OBJ and FOLD exports but no SVG preview, because the study's SVG painter
assumes the packet order and would conceal those unfinished crossings.

This remains a restricted surface experiment. Contact checks different layers
of the nearly flat packet, not arbitrary orientations, folds within a panel,
motion between checkpoints or finite-thickness clearance. Edge lengths leave
neighbouring triangles free to turn about their shared edge, including edges
introduced only to subdivide a panel. Bending resistance and preferred crease
angles must supply additional information. The
[Position Based Dynamics paper](https://matthias-research.github.io/pages/publications/posBasedDyn.pdf)
also treats cloth stretching, bending and collision constraints separately;
this study derives its own least-squares solver and does not implement that
paper's dynamics. Correct lengths and layer order are now reproducible checks,
while a physical paper model remains future work.
