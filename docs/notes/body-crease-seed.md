# Compatible crease angles can still put paper through paper

[#383](https://github.com/avalonalex/senbazuru/issues/383) changes how the body
study gets its starting shape. The two previous constructions moved vertices
of a [saved flexible pose](body-feasible-initialization.md), without obtaining
positive clearance. The owner instead approved constructing a slightly open
pose from crease angles and deriving new positions for the same three grip
vertices. This changes the starting conditions, so it is not a matched
comparison with those earlier solves. Their archives remain unchanged.

```bash
stack run senbazuru-material-study -- --body-crease-seed build/fold-material
```

The construction uses the same 16-panel material patch, with 14 physical
creases and four flat connections. A panel is the piece between recorded
edges; [material coordinates](../glossary.md) identify where its corners came
from on the original sheet. Every panel stays rigid during construction: it
turns without stretching or bending. At the three internal crease
intersections, neighboring turns must agree. Closing a loop requires both
shared positions and the intended relative panel orientation; matching crease
endpoints alone can miss an incorrect turn.

One declared family starts all mountain/valley angles at signed 175°. Patch
edge 4 (original crane edge 5) stays at −175°; the other magnitudes can range
from 150° to 179.99°, without reversing their signs. Flat connections remain
at zero. Fixing one angle prevents the search from simply returning to the
closed 180° packet. These restrictions do not cover all possible rigid poses.

`CreaseSeed` provisionally walks the panel graph and measures disagreement
between each neighbor's transform and the transform its crease requests.
Its objective sums squared differences in orientation and translation in the
unit-sheet coordinates. Central differences at `1e-6` radians estimate how
angles change those residuals. The existing `SparseSolve` factors the normal
equations with damping `1e-8`; the original equations must pass a residual
check of `1e-10 × max(1, largest right-hand-side entry)`. Each correction is
scaled to at most 5° per angle, then tries fractions `1, 1/2, …, 1/4096` within
the angle bounds, accepting only lower disagreement. There are at most forty
corrections, with a maximum closure residual of `1e-10` required to finish.
No alternative seed or parameter retry was run on the body.

The production `foldFrameWith` then independently checks shared vertices and
achieved crease angles before a shared mesh can be exported. Face zero is
rigidly aligned with the original closed patch. Its centre and Wing A grip
therefore stay in place to rounding; Wing B moves with the construction.
The new three holds are exact at their derived positions. One midpoint
subdivision preserves the same piecewise planar shape and material identities.
Original crease preferences, panel stiffness and inherited layer orders stay
unchanged. No material or contact correction runs.

The **2026-09-24 result closes the angles but fails contact**. Two full angle
corrections reduce the largest transform disagreement from `0.0509811` to
`1.44949e-11`; the independent folding checks pass. The first construction
costs approximately `0.0012` CPU seconds, excluding fixture preparation,
measurement and export. Unlike the earlier initialization, the angle search
has only thirteen unknowns and no thousands-row contact system.

| Measurement | Coarse pose | Same pose subdivided |
| --- | ---: | ---: |
| Material vertices / triangles | 29 / 30 | 87 / 120 |
| Largest relative edge error, limit `1e-5` | `2.18405e-11` | `2.18412e-11` |
| Body depth, sheet units | 0.0254940 | 0.0254940 |
| Wing B grip movement from closed, drawing pixels | 15.3255 | 15.3255 |
| Crossing triangle pairs | 4 | 18 |
| Reversed inherited orders | 6 | 38 |
| Crease energy | 0.00859333 | 0.00859333 |
| Uncreased-panel energy | `2.15e-25` | `4.31e-25` |

Subdivision changes triangle-pair counts, not the physical shape or its
validity. The largest reversed-order height is about `0.00785563` sheet units,
roughly **4.71 drawing pixels** at 600 pixels per sheet unit. This is a distance
along the contact direction, not a projected area or a guarantee of visibility
from every camera. These are substantial intersections, not the tiny
crossings of the previous saved pose. The free neck and tail attachment
landmarks move approximately 0.01278 and 0.01279 sheet units from the closed
reference; the rest of the crane is still absent.

The coarse disjoint-triangle clearance diagnostic alone passes: the failing
coarse pairs share material vertices and are excluded from that positive-gap
subset. The independent all-pair checker still catches their crossings.
After subdivision, some children of those same panels share no vertices;
the smallest disjoint gap is now `−0.00785563`. This is why clearance for
unconnected triangles cannot replace checking *all* triangle pairs. Local
reference discovery and strict static checking fail at both resolutions, so
dependent barrier rows are not evaluated. There is no barrier-ready seed,
accepted opened body, material equilibrium or certified folding route.

The gallery compares the closed reference with both resolutions, at drawing
size and 4× magnification, with side, top, underside and material views.
`angles.fold` records a crease pattern with the attempted angles, never an
assertion of contact acceptance. The angle trace and all measurements are
exported separately. Independent calculations reproduce closure using a
different spanning tree, achieved angles, lengths, separate energies, grips,
landmarks, inherited-order gaps, every triangle-pair contact result and the
unchanged shape under subdivision. All 1,909 tests pass after a warning-free
cold build; formatting, HLint 3.10 and the JavaScript checks pass. The sixteen
gallery state/view/size combinations load without browser warnings or errors.

Stop at this bounded result. Opening every crease slightly and keeping its
mountain/valley sign does not determine a valid arrangement of layers. A next
proposal should select the arrangement using contact and inherited order
*during* angle construction, or derive it from a known valid folding route.
It should address the overlapping regions together, not resume repairs of
individual triangle pairs. Thickness, pressure, full-crane response and the
matched barrier/penalty comparison remain later work under
[#195](https://github.com/avalonalex/senbazuru/issues/195).
