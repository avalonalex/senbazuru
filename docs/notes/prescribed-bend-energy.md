# The same bend can have a different numerical cost

The [8×2 comparison](band-refinement-8x2.md) still changes shape and energy
under refinement. Before asking the optimizer for another shape, place known
bends directly on the existing eight meshes, from `1×1` through `8×2`:

```bash
stack run senbazuru-material-study -- --prescribed-bend build/fold-material
```

Open `prescribed-bend.html`. Each mesh keeps the same material coordinates,
triangle connectivity, shared central crease and passive/angular-control
constants as the unequal-panel study. Material coordinates locate a point on
the unfolded sheet; see the [glossary](../glossary.md). Both panels occupy the
same surface, with opposite facing directions. The crease stays closed at
180°. The previous boundary grips are **not applied**: these are diagnostic
shapes, not equilibria or accepted endpoints of the earlier problem. The
report includes their displacement from those grips. No optimizer or contact
correction runs, and no acceptance tolerance changes.

Four probes separate effects that can otherwise look alike:

- **Flat:** coincident flat panels check zero passive and length costs. The
  upper-panel band preference still has its known flat energy `1.813241893`.
- **Fixed corners:** the existing four straight strips keep their original
  three turns, even when each strip gains more triangles. This is exactly the
  same shape at every mesh, but not a smooth bend.
- **Sampled cylinder:** at distance `s` from the crease, put the point at
  `(sin(k*s)/k, y, (1-cos(k*s))/k)`, with `k = 1.2` radians per sheet length.
  Matching material points have identical positions on every mesh. The code
  uses `2*sin(k*s/2)^2` for the last numerator to avoid subtracting almost
  equal numbers. Straight triangle edges are chords, shorter than the curved
  material arcs; the mesh therefore records compression.
- **Full-length edges:** multiply the cylinder's x/z coordinates by
  `(k*h/2)/sin(k*h/2)`, where `h = 1/(8*n)` and `n` is length subdivision.
  This gives each straight profile segment its full material length and the
  same angle as the cylinder's chord. It approximates the cylinder without
  stretching any triangle; matching material points now move slightly under
  refinement. It is not an exact sampling of the same continuous surface.

For the two cylinder probes, the angle between consecutive strips is `k*h`.
The passive spring stiffness is `0.2*w/h`, where `w` is a width segment.
There are `4*n-1` such turns per panel, with no passive spring at its outer
boundary or at the original central crease. Summing half stiffness times
squared turn gives `0.1*k²*(0.5-h)` per panel. The cylinder's limiting value
for this discrete extrusion is `0.072`; this is a reference for the existing
rule, not a calibrated property of real paper.

Measured energies at width one are:

| Length subdivision | Fixed-corner passive, per panel | Cylinder passive, per panel | Cylinder upper-band control | Sampled-cylinder length energy at weight `1e10` |
| --- | ---: | ---: | ---: | ---: |
| 1 | 0.0906621 | 0.05400 | 0.713620 | 1711.555 |
| 2 | 0.1813242 | 0.06300 | 0.713620 | 52.0192 |
| 4 | 0.3626484 | 0.06750 | 0.773987 | 1.61344 |
| 8 | 0.7252968 | 0.06975 | 0.804171 | 0.0503237 |

The two cylinder probes have the same angles and therefore the same angular
energies. Their length energies differ: full-length edges stay below
`2.8e-21` at weight `1e10` across all eight meshes, consistent with numerical
roundoff. Fixed-corner passive and band energies both double on each length
doubling. Keeping a finite corner while narrowing its neighboring strips
raises this bending cost; equal pictures alone are not equal material costs.

The cylinder's remaining control drift has a concrete source. The
[band rule](distributed-bend-preference.md) clips each edge's represented
interval at the band ends. Its preferred angle uses that clipped interval,
but its achieved angle still comes from the two full neighboring strips.
For interval length `d`, its unit-width energy is
`B/(2*d) * (-k*h - Theta*d/W)^2`; the negative sign comes from the upper
panel's material winding. `B`, `Theta` and band width `W` are unchanged.
At subdivisions 2, 4 and 8 the partial-boundary contribution is `0.0461363`,
`0.0230682` and `0.0115341`; the full-interval contribution is `0.667484`,
`0.750919` and `0.792637`. Their sum approaches `0.8343544`. Thus the
4→8 control change is **3.90% even on this prescribed smooth bend**;
the passive change is 3.33%. The first two control totals happen to agree
because the coarsest mesh puts the far band boundary between columns.
Agreement of one pair is not evidence of a settled limit.

The length objective has a different mesh dependence. It sums squared
**absolute edge-length errors**, with no area normalization. Its energy is
half that sum times the selected numerical weight. The line search reports
twice the complete energy, including angular terms; both conventions are
explicit in JSON. A cylinder chord has length `2*sin(k*h/2)/k`. At `8×1`,
the maximum relative edge error is `1.46484e-5`, still above the unchanged
`1e-5` cap. Doubling width leaves this error and every angular energy unchanged,
but increases the length energy from `0.0503237` to `0.0840792`, because more
edges carry length residuals. All sampled-cylinder probes are labeled
length-invalid diagnostics. Nothing is repaired or silently accepted.

All 32 shapes preserve material/triangle identities, one connected component
and the original shared crease. The exact directional contact audit reports
zero lower/upper gap throughout each stored triangle pair; this remains a
known-order check, not general collision discovery. The gallery saves 32
shared-scale side-profile SVGs, 32 FOLDs and per-edge/per-hinge JSON records.
Eight fast analytic regressions cover the formulas above, topology, signed
crease angles, matching points, objective accounting and contact. Independent
reconstruction from the exported coordinates verifies triangle normals,
material stiffnesses, band intervals, length sums, energy totals and FOLD
positions. Identical monotone extruded triangle sets on both sides separately
confirm their complete touching surfaces. All 1,487 tests pass in a cold
warning-free build; formatting, HLint 3.10 and the JavaScript checks pass.
All 48 browser selections were exercised. The compiled generator took
2.75 seconds locally; no long solve was added to CI.

This identifies discretization effects without establishing which one drives
the optimized unequal-panel response: these probes have no width-varying bend,
no separation and, except for the fixed-corner control, different boundary
positions. Do not change the solver or increase the mesh on this evidence
alone. The next bounded experiment can compare the current band-boundary rule
with a rule that measures the same fraction of actual and preferred turn on
these prescribed probes, retaining the original as a control. Any proposed
change then needs a small matched/contact-off solve before the expensive
`8×2` case. The stronger material-refinement targets, tighter-solve check and
illustration review remain open under [#195](https://github.com/avalonalex/senbazuru/issues/195).
