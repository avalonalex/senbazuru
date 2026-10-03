# Spreading an existing connected wing

Start with the crane from `examples/crane.fold`, including the tail tucked
between the body layers. The [rigid-wing study](../usage.md#checked-crane-wing-movement) selects
four material panels which fold into two touching layers. They are already
connected to the body. Bending them must preserve their material identities
and the creases joining them; adding a separately shaped wing would not test
that connection.

Run this static experiment from the repository root:

```bash
stack run senbazuru-material-study -- --crane-spreading build/fold-material
```

Hold every body vertex at its original position. The wing turns from its
root, the line from the base of the neck to the base of the tail, folded
y = 0.37585, which the study finds by rule ([flap-roots.md](flap-roots.md);
owner decisions 34 and 35). Hold the wing's base, between its widest point and
the root, at 30 degrees from its resting plane, and the final eighth of its
length at 50 degrees. Place those grips by integrating a circular arc through
the paper between; this supplies an initial guess and exact grip positions.
The paper between is then free to relax under material-length, crease-angle,
panel-bending and contact terms. The circular arc is not imposed on its free
vertices.

Only the wing's panels receive dense subdivision. Adjacent triangles split
where they share a newly divided edge, so both sides use the same midpoint id.
At the root the crease cuts all eight of the wing's faces and the base gets
panels of its own, so the wing has more panels than at the studies' earlier
hinge, y = 1/4: 1,188 triangles with eight spans per wing panel, and 4,324 with
sixteen. The body is held, so dividing it would add cost without adding
freedom. Original creases keep their source edge ids; subdivision edges are
joins, not additional material creases. See the [glossary](../glossary.md)
for material coordinates, panels and layer order.

A run on 2026-10-02 at the root produced these measurements. Length errors are
relative to the original material; CPU times measure the solve, excluding
export.

| Control | Triangles | Maximum edge error | Maximum crease-angle error | Panel bending energy | Solve CPU seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Rigid 30-degree grip | 1,188 | 1.39e-11 | 4.34e-13 rad | 2.27e-25 | 1.07 |
| Curved 50-degree grip | 1,188 | 1.81e-7 | 8.31e-7 rad | 0.0131812 | 9.75 |
| Curved, finer mesh | 4,324 | 2.22e-7 | 4.54e-6 rad | 0.0133058 | 1,004, **not converged** |

The rigid and curved endpoints are accepted. They keep one material component,
84 source panels, 153 source edges and 978 source orders, and their body and
grip position errors are exactly zero. The curved wing's most compressed and
stretched directions have strains of -4.42e-7 and 2.84e-7.

The finer mesh does not converge: its solve ran 43 iterations without passing
its stopping test. With 40 and 100 iterations allowed per penalty stage, it
ran 63 and 123, and its energy and errors stopped changing, so the shape is
settled and the stopping test is what fails
([#469](https://github.com/avalonalex/senbazuru/issues/469)). It passes every
contact check, but an unconverged solve is not accepted, so the page has no
two-resolution comparison at the root.

At y = 1/4, measured on 2026-09-13, the wing had four panels: 392 triangles
with eight spans and 1,192 with sixteen.

| Control | Triangles | Maximum edge error | Maximum crease-angle error | Panel bending energy | Solve CPU seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Rigid 30-degree grip | 392 | 1.39e-11 | 5.98e-14 rad | 1.44e-27 | 0.47 |
| Curved 50-degree grip | 392 | 2.92e-7 | 2.37e-7 rad | 0.0121775 | 5.76 |
| Curved, finer mesh | 1,192 | 3.48e-7 | 3.95e-6 rad | 0.0126582 | 64.30 |

All three endpoints there retained one material component, 76 source panels,
138 source edges and 902 source orders. The finer result's most compressed and
stretched directions had strains of -8.82e-7 and 6.38e-7. Matching material
points moved at most 0.000167 between the two curved meshes, and bending
energy changed by 3.95%. Two resolutions give a useful comparison, not
evidence that the answer has stopped depending on the mesh. Stiffness is
illustrative rather than calibrated to a paper sample.

The independent contact check initially flagged narrow overlaps at the wing's
central seam. Their widths were about 2.5e-9 model units: an area-only test had
called them overlapping interiors even though its normal-distance tolerance
was 1e-7. Insetting each coplanar outline by half that tolerance makes the
in-plane and normal tests use the same distance margin. Regression tests keep
wider unordered overlaps and reversed layers as failures. No solved position
is snapped, and no arbitrary order is added between side-by-side panels.

The [visible glTF scene](visible-paper-mesh.md) resolves nearly coplanar
layers at its coordinate packing precision. Its clipping preserves original
material references; the complete scene still contains the entire sheet.
This export margin is separate from the solver and endpoint contact tolerance.

The incompatible control pushes only independent upper-grip vertices 0.005
units below their lower partners. After its small solve budget, the body and
grips remain exact, but 18 source orders are still reversed and the maximum
edge error is 9.59% at the root (at y = 1/4, the order was still reversed by
0.005, with 12.4%). This endpoint stays a diagnostic FOLD file and
never appears as an accepted model. A numerical solve cannot rescue an
incompatible exact grip by silently moving it.

A fixed body therefore suffices for this modest held bend. The follow-up
[wing-root study](wing-root-holds.md) separates the exact root-strip hold from
the crease preference and tests a small free body region. Paired grips on
both wings remain a later comparison.
These are static endpoints: optimizer iterates can stretch or cross paper,
and neither this experiment nor its rigid baseline certifies the flexible
route between them. Freer spreading, body expansion, friction and measured
material properties remain later studies under [#195](https://github.com/avalonalex/senbazuru/issues/195).
