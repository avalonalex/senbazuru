# A small contact penalty still permits a small overlap

The [single-crease reference](near-closed-crease.md) gives two bending panels
with known touching geometry. Now hold the lower panel still and let part of
the upper panel settle. Can the existing solver repair a penetrating guess?
The [glossary](../glossary.md) defines panels, material coordinates and creases.

```bash
stack run senbazuru-material-study -- --crease-correction build/fold-material
```

The original sheet is the unit square, folded at material `u = 0`. The whole
lower half (`u >= 0`) is held at its bent reference. The outer quarter of the
upper half (`u <= -0.375`) is also held there. Three shared crease vertices
belong to the lower panel and therefore stay fixed. The crease's angle is a
spring preference of 180°, not a second positional hold: the adjacent upper
vertices remain free to move in all three coordinates. Bending inside the
panels prefers flat paper. These incompatible preferences make touching an
interesting solve rather than a shape with no forces to balance.

The solver assigns costs to stretching, bending away from a preferred angle,
and penetration. A **contact penalty** makes negative gaps expensive by
multiplying their squared size by a large weight. Its finite weight still
allows a trade against the other costs.

Five controls use the same 32- and 64-triangle references:

- **Touching start:** the known bent panels coincide exactly.
- **Penetrating start:** lower each free upper vertex by
  `0.002 * sin(pi * abs(u) / 0.5)` sheet lengths. Holds do not move.
- **No contact forces:** the identical penetrating guess, holds and springs,
  with only contact forces disabled. The endpoint is still checked.
- **Tiny penetration:** replace `0.002` by `2e-8`, already smaller than the
  existing contact-check tolerance.
- **Conflicting hold:** hold the upper row at `u = -0.25` at its penetrating
  positions too. No correction can satisfy both that hold and the order.

The penetrating inputs are imperfect solver guesses and initially strain the
material: some lengths differ from those on the original sheet. They are not length-preserving folding states. Refinement splits
the same four profile segments; it does not prescribe a smoother curve.

The existing solver uses forty iterations per penalty stage and its existing
four weights, ending at `1e8`. No solver, spring stiffness or tolerance is
changed. The numerical endpoint check requires convergence, relative edge
error at most `1e-5`, exactly held positions, crease error at most `1e-5`
radians, and the whole-mesh contact check at its existing `1e-7` distance
tolerance. Exact lower/upper order is reported separately.

Unlike the prescribed reference, the solved upper panel may vary across its
width. Checking only an outside edge could miss an interior penetration.
`CreaseCorrection.auditLowerGap` clips **every upper triangle** over each
linear segment of the fixed lower profile, including its finite width. The
upper-minus-lower height is linear on each clipped piece; its extrema occur
at the corners. `Rational` arithmetic computes those gaps exactly from the
stored `Double` coordinates, independently of force derivatives and contact
snapping. The test includes a warped middle row with unchanged outside edges.
This is an exact directional-order reference against the held lower panel,
not a general self-contact certificate for an arbitrary upper surface.

Measured with the compiled gallery on 2026-09-14:

| Control | Minimum gap, 32 triangles | Minimum gap, 64 triangles | All numerical checks |
| --- | ---: | ---: | --- |
| Touching start | -5.933e-11 | -8.431e-11 | Pass / pass |
| Penetrating start | -5.933e-11 | -8.431e-11 | Pass / pass |
| No contact forces | -1.549e-3 | -4.582e-3 | Fail / fail |
| Tiny penetration | -5.933e-11 | -8.431e-11 | Pass / pass |
| Conflicting hold | -2.000e-3 | -2.000e-3 | Fail / fail |

The three viable contact starts converge in 32–34 iterations on the coarse
mesh and 79–80 on the finer mesh. They retain exact holds and shared material.
For the ordinary penetrating start, the final relative length errors are
`5.077e-7` and `8.102e-6`; crease errors are `7.539e-6` and `4.530e-10`
radians. The no-contact controls converge too, but retain substantial
penetration and fail the crease check. Conflicting holds never converge and
leave relative length errors above `0.006`; blocked search stages remain in
the diagnostic JSON instead of disappearing behind a final failure label.

Contact reduces the ordinary `0.002` penetration by more than twenty million
times at both resolutions. Yet **every stored endpoint still has a negative
gap**, including the endpoint that began with no penetration. The raw force
gap agrees with the separate reference to about `1e-17` here. This is
consistent with a finite contact penalty balancing other forces: a quadratic
cost has zero slope at zero penetration, so a small negative gap can supply
a nonzero restoring force. Convergence to this penalized balance does not
establish exact nonintersection. Neither does passing a tolerance check.

The page magnifies only the negative part of each gap, with independently
labelled vertical scales before and after correction. Diagnostic FOLDs retain
the stored coordinates. Complete-sheet GLBs include all triangles but round
positions for display, so their clean appearance cannot resolve the residual.
No accepted-model label or continuous folding route is implied.

The [follow-up experiment](nonnegative-crease-contact.md) requires every
upper-minus-lower gap to be nonnegative on this same fixture, comparing
residuals, material error and convergence with this finite-penalty baseline.
Increasing a penalty alone is not a guarantee of exact contact and can make the numerical system harder to solve. Keep the
incompatible hold as a refusal control. Returning to the larger crane body,
calibrating physical paper properties and certifying flexible motion remain
separate work.
