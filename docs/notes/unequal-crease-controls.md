# When the two panels want different shapes

The [symmetric experiment](coupled-crease-contact.md) lets both interiors bend,
but equal conditions leave their surfaces almost coincident. Change only the
upper panel's grip or add an explicit bend preference. Does it separate from
its partner, or change that partner's shape through contact? The small sheet
and its [material identities](../glossary.md) remain the same.

```bash
stack run senbazuru-material-study -- --unequal-crease build/fold-material
```

The boundary conditions need care. An initial probe rotated the upper outer
strip by `0.05` radians with only the shared crease line held. It converged
without crossing, but opened the crease by about `0.0068` radians on the
coarse mesh, failing the original `1e-5` angle cap. Holding a line fixes its
position, not the orientation of the paper beside it.

For the comparison, hold the narrow strips within `0.125` sheet lengths of
the crease on both sides. These fix its orientation and keep it closed. Hold
only the outer edge at the opposite end, leaving the interiors free. All
compatible controls use these same holding regions. Their matched-holds
reference differs from the earlier outer-strip experiment, so comparisons
use a newly solved reference at each resolution.

There are five controls:

- **Matched holds:** the original bent shape and passive panel springs.
- **Open the upper grip:** rotate upper material beyond the held root strip
  by `0.05` radians around its end. The outer edge stays at that new position.
  This supplies a length-preserving static starting guess, not a folding path.
- **Upper bend preference:** leave all holds unchanged. At upper material
  coordinates `u = -0.125, -0.25, -0.375`, add springs preferring twice each
  line's original profile turn. These six hinge segments are explicit controls,
  not new authored creases. Stiffness is eight times material line length,
  giving four per segment at both resolutions. Refinement across a line does
  not strengthen its control. Passive springs remain present on both panels.
- **Same preference, contact off:** keep exactly those springs, holds and seed,
  but omit contact inequalities and feasibility repairs. This is a diagnostic.
- **Incompatible held rows:** additionally hold one interior row on each side
  through its partner, demanding a negative gap of `0.002` sheet lengths.

The normal solve still measures both current triangle surfaces, rechecks
stored-coordinate gaps exactly, and repairs penetrating proposals before
accepting a decrease in material energy. Contact-off retains the same material
objective, damping, length-weight stages and convergence checks. It still
reports gaps afterward; disabling enforcement does not make crossing valid.
The held strips fix all triangles incident on the shared crease, so its
angular spring cannot transmit movement between free interiors in this test.
Switching contact therefore isolates its influence on the lower panel.

The compiled gallery on 2026-09-14 gives the following results. Distances are
fractions of the unit sheet's side; panel changes compare identical material
points against the matched-holds endpoint at the same resolution.

| Measurement | 32 triangles | 64 triangles |
| --- | ---: | ---: |
| Open-grip maximum gap | 0.02174 | 0.02183 |
| Open-grip lower change | < 2e-15 | < 1e-11 |
| Upper-preference lower change | 0.002149 | 0.002560 |
| Upper-preference maximum gap | 7.271e-7 | 0.007009 |
| Contact-off lower change | < 4e-15 | < 6e-15 |
| Contact-off minimum gap | -0.002857 | -0.004238 |
| Largest accepted endpoint relative edge error | 8.560e-7 | 3.747e-6 |

The open grip separates the paper without appreciably changing the lower
shape. The upper preference does change the lower shape when contact is on.
Removing contact restores the lower reference response but leaves a crossing;
it still converges and passes lengths and the held crease angle. Thus a
material equilibrium alone cannot decide whether the layers are valid.

All six contact-enabled endpoints pass exact order, lengths, held positions,
material identities and the separate whole-sheet contact check at its
unchanged `1e-7` distance tolerance. Their authored crease errors are below
`1e-12` radians. Every recorded constrained iterate has nonnegative exact gaps.
Both contradictory holds are refused. The largest accepted outward repair
is `2.011e-4` per side for the coarse upper preference and `4.214e-7` for the
fine one; rounding adds less than `1.4e-17`. Those repairs are numerical
policies, not observed physical movement. Initial repairs are zero here.

The page keeps a side projection of three material rows separate from its
magnified gap plot. The latter draws all overlap-corner gaps across the
width, including contacts at edges and vertices; marks are not contact-area
estimates. Complete FOLDs retain the measured coordinates. GLBs round for
viewing, and `checks.json` retains controls, repairs and solver reports.

Refinement changes more than a last decimal: the coarse preferred-bend case
is nearly touching, while the fine case separates by up to `0.007009`. Its
matching coarse material positions change by at most `0.001315`, but extra
fine vertices also describe the shape between those points. Matching-point
agreement alone would miss that difference. These controls have identical
strength across meshes; the result is still not mesh-independent or calibrated
paper mechanics.

The next bounded check is refinement of this unequal-preference case, including
resolution across the panel's width. Compare contact regions and maximum gaps
as well as matching material points before returning to the crane body patch.
Known order along z, retained triangle facing directions and the held crease
remain assumptions. Continuous flexible motion is still unchecked.

The follow-up [independent refinement study](unequal-crease-refinement.md)
keeps these controls fixed while varying both mesh directions.
