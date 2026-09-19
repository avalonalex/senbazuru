# More bending locations, a different total

The [outer-strip experiment](outer-strip-refinement.md) kept the same held
paper but changed where its triangles could bend. Its matched-hold control
applies no preferred bending band. Adding only the outer bend changed passive
energy by 0.32%; refining the rest changed it by 8.99%. Where did that second
difference come from?

Re-read the four saved endpoints, without an optimizer or contact repair:

```bash
stack run senbazuru-material-study -- --matched-energy \
  build/fold-material/outer-strip build/fold-material
```

`matched-energy.html` compares 64, 72, 120 and 128 triangles. The two
rule-labelled matched archives have identical positions and measurements,
because neither has an imposed band spring. They give four unique endpoints,
not eight independent experiments. All retain their convergence and pass fresh
material, hold, original-angle and contact checks. Source FOLD files are copied
byte-for-byte. This analysis changes no acceptance criterion.

For the upper panel, coarse → rest-only changes passive energy from
`0.09941344468` to `0.10834645477`: a rise of `0.00893301009`, or **8.9857%**.
These are model energy costs, not measured joules.
Each [panel bend](../glossary.md) contributes its entire cost at the midpoint
of its edge on the original sheet. Distance is measured from the shared crease
in units of the square's side:

| Material location | Signed energy change |
| --- | ---: |
| Held strip, below 1/8 | 0 |
| Held boundary, at 1/8 | −0.00413054121 |
| Interior, between 1/8 and 7/16 | +0.01412731188 |
| Reference line, at 7/16 | −0.00107596185 |
| Outer strip, beyond 7/16 | +0.00001220127 |
| **Total** | **+0.00893301009** |

The 7/16 line locates the band end in the loaded experiment; here it imposes
neither a load nor a hold. Refining the interior with the outer bend already
present gives almost the same change, `+0.00894853700`. Adding only the outer
bend gives `+0.00032200727` from coarse or `+0.00033753417` from rest-only.
The gallery and report retain both panels rather than assuming symmetry.

The finer interior adds transverse bends, edges parallel to the shared crease,
at `5/32`, `7/32`, and subsequent odd thirty-seconds. The first two new
locations contribute `+0.01986751644` and `+0.01356275273`, summed across the
panel width. Those increases are partly cancelled by cheaper bends at existing
locations. Counting only positive additions would greatly overstate the net
change. Transverse contributions dominate, but every diagonal and lengthwise
bend remains in the totals.

An edge is paired across meshes by its two material endpoints, not its vertex
ids. For coarse → rest-only, one panel has 17 shared, 56 added and 21 removed
edge locations. These counts include zero-cost bends inside the held strip.
A shared edge need not represent the same angular spring: its two neighboring
triangles may be narrower. Its coefficient `k` is `0.2 × edge length / mean
triangle height`, where height is the perpendicular distance from the opposite
vertex to the edge. Its turn `θ` is measured between those neighbors.
Refinement changes both what is measured and its weight.

For a shared edge, `E = k θ² / 2`. Average the two possible expansion orders
to write its exact change as:

```text
coefficient term = (k₁ − k₀)(θ₀² + θ₁²) / 4
angle term       = (k₀ + k₁)(θ₁² − θ₀²) / 4
```

Across the shared upper edges these give `+0.06412971489` and
`−0.10300096663`. Added bends contribute `+0.04786357120`; removed bends
contribute `−0.00005930937`. Together they recover `+0.00893301009`.
This is algebraic accounting, **not independent physical causes**: the angles
span different material neighborhoods and the optimized shapes also differ.
The maps are discrete spring costs, not continuous energy per unit area.

The next bounded question is whether the same nonuniform meshes change the
passive cost of a *prescribed* bend, before allowing the optimizer to choose
different shapes. Compare a smooth cylindrical reference and a reference
whose bend starts at the held boundary, with explicit sampling/length error.
That would separate discretization of a known shape from the response of the
solved shapes. It does not yet call for another large grid, a new default
bending rule, looser material thresholds, or a decision about illustration
quality. See [#272](https://github.com/avalonalex/senbazuru/issues/272),
continuing [#195](https://github.com/avalonalex/senbazuru/issues/195) and
track A of [#269](https://github.com/avalonalex/senbazuru/issues/269).

Independent coordinate calculations reproduce all 472 spring records and
their region, direction and edge totals, including the coefficient/angle
identity. Exact triangle clipping reproduces all four gap extrema and 6,400
sampled gaps. The 52 SVGs, ten browser selections, eight unchanged FOLD copies
and the complete GLB positions are checked. Fast analytic/accounting and
archive-refusal tests add no optimizer work to the regular suite. All 1,516
tests pass in a cold warning-free build; formatting, HLint 3.10 and JavaScript
checks pass.
