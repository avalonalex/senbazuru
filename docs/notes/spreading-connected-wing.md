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

Hold every body vertex at its original position. Hold the first eighth of the
wing at 30 degrees from its resting plane, and the final eighth at 50 degrees.
Place those grips by integrating a circular arc through the middle three
quarters; this supplies an initial guess and exact grip positions. The middle
is then free to relax under material-length, crease-angle, panel-bending and
contact terms. The circular arc is not imposed on its free vertices.

Only the four wing panels receive dense subdivision. Adjacent triangles split
where they share a newly divided edge, so both sides use the same midpoint id.
This gives 392 triangles with eight spans per wing panel, and 1,192 with sixteen.
Uniformly dividing the whole crane would require 7,168 and 28,672 triangles.
The body is held, so most of that uniform subdivision would add cost without
adding any freedom. Original creases keep their source edge ids; subdivision
edges are joins, not additional material creases. See the
[glossary](../glossary.md) for material coordinates, panels and layer order.

A run on 2026-09-13 produced these measurements. Length errors are relative to
the original material; CPU times measure the solve, excluding export.

| Control | Triangles | Maximum edge error | Maximum crease-angle error | Panel bending energy | Solve CPU seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Rigid 30-degree grip | 392 | 1.39e-11 | 5.98e-14 rad | 1.44e-27 | 0.47 |
| Curved 50-degree grip | 392 | 2.92e-7 | 2.37e-7 rad | 0.0121775 | 5.76 |
| Curved, finer mesh | 1,192 | 3.48e-7 | 3.95e-6 rad | 0.0126582 | 64.30 |

All three endpoints retain one material component, 76 source panels, 138
source edges and 902 source orders. Body and grip position errors are exactly
zero. Independent checks examine all triangle pairs, including within each
bending panel, and all retained orders. The finer result's most compressed and
stretched directions have strains of -8.82e-7 and 6.38e-7. Matching material
points move at most 0.000167 between the two curved meshes; bending energy
changes by 3.95%. Two resolutions give a useful comparison, not evidence that
the answer has stopped depending on the mesh. Stiffness is illustrative rather
than calibrated to a paper sample.

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
grips remain exact, but the layer order is still reversed by 0.005 and the
maximum edge error is 12.4%. This endpoint stays a diagnostic FOLD file and
never appears as an accepted model. A numerical solve cannot rescue an
incompatible exact grip by silently moving it.

A fixed body therefore suffices for this modest held bend. The next bounded
experiment can apply paired grips to both wings, initially keeping the body
fixed, and release a small body region only if the checks expose a conflict.
These are static endpoints: optimizer iterates can stretch or cross paper,
and neither this experiment nor its rigid baseline certifies the flexible
route between them. Freer spreading, body expansion, friction and measured
material properties remain later studies under [#195](https://github.com/avalonalex/senbazuru/issues/195).
