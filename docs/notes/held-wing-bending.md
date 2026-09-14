# Hold the ends; solve the paper between them

A triangle with corners `(0,-0.3)`, `(1,0)` and `(0,0.3)` makes a useful
wing-shaped test piece. Hold its wide root, where the original x coordinate
is at most `0.125`, flat. Hold the small tip region, x at least `0.875`, at a
new position and orientation. The rest of the sheet has to find a shape
between those two regions. These are controls on material points, not new
creases. [Material coordinates](../glossary.md) identify the points on the
original sheet even after they move in space.

`WingBending` places the grip using a circular bend of the middle `0.75` sheet
lengths. That bend also supplies an initial guess for the free points, but
does not constrain their final positions. Sampling an arc makes straight
triangle edges shorter than their material lengths. The solver must correct
that initial compression while reducing the [panel bending energy](crease-and-panel-energy.md).
The grip angle is the held tip's orientation; it is not a crease-angle target.

`FoldRelaxation.relaxPinnedHinges` removes held vertices from the unknowns in
each linear solve. Their displacement is exactly zero, so no spring stiffness
has to approximate a fixed grip. Forces at a held point need not vanish: the
grip supplies the opposing force. Convergence checks movement of the free
points and material lengths. Fully holding a triangle at incompatible lengths
therefore cannot claim convergence just because nothing can move.

Run `stack run senbazuru-material-study -- --wing-bending build/fold-material`.
The 40-degree control produced these measurements on 2026-09-13. Length error
is the largest relative change of any triangle edge against the original sheet.
Energy uses illustrative panel stiffness `0.2`, not a measured paper stock.

| Divisions | Triangles | Largest relative length error | Bending energy | Held-point error |
| --- | --- | --- | --- | --- |
| 8 | 64 | 2.11e-8 | 0.017646 | 0 |
| 16 | 256 | 5.89e-8 | 0.018340 | 0 |
| 24 | 576 | 9.28e-8 | 0.018648 | 0 |

All three converged and passed the independent static contact check over every
triangle pair, including neighbors. They retain one connected sheet, with the
same material coordinates and topology as their starting meshes. At the 45
material points common to both grids, the largest position change is
`0.001345` sheet lengths from 8 to 16 divisions, and `0.000418` from 16 to 24.
The latter energy change is about 1.7%. Refinement reduces the observed shape
change; these three meshes do not establish a fully converged continuum model.

The companion strip supplies an independently known discrete reference. Its
equal-length spans turn about parallel axes across its width. Equal angles
give equal-stiffness hinges the smallest sum of squared turns for the held
end orientations within that family of shapes. The first and
last span stay fixed. After perturbing the free points, the solver returns
within `1.3e-7` sheet lengths of that reference at 8, 16 and 24 spans, with
relative edge errors below `4.7e-9`. Each discrete reference defines its own
end position. Recovery from this nearby perturbation does not prove a unique
global minimum. The wing comparison instead holds the same physical regions
and grip placement across resolutions.

`UncreasedSurface` sends these solved triangles to both SVG and glTF. Each
triangle is a planar FOLD face, and internal edges are `J` (joins): subdivisions
inside one material panel, with no crease drawn there. The extra
`senbazuru:source_panels` array records original panel zero for every triangle;
original material coordinates also survive export. This adapter is restricted
to one uncreased panel. It cannot recover a crane's original crease identities
or layer orders from a bare triangle mesh.

These are separate static equilibria. There is no contact force in this solve;
contact is independently checked at each result. Neither the circular initial
guesses nor the optimizer iterations are certified physical folding routes.
The follow-up [two-layer experiment](two-held-paper-layers.md) adds an explicit
initial order, separate material identities and compatible grips. Coarse
controls pass, and [coupled preconditioning](coupled-touching-layer-solve.md)
now resolves the initial fine-mesh stall. That isolates contact before
attaching a wing to the crane body and deciding which body regions must move. Both continue
[#195](https://github.com/avalonalex/senbazuru/issues/195); realistic spreading,
body expansion and a verified flexible motion remain open.
