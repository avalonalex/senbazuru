# Asking a region of paper to bend

The [six-mesh line-load study](two-direction-crease-refinement.md) asks the
upper panel to turn at three material lines. Refining the mesh leaves each
requested angle unchanged, but narrows the triangles that must carry that
turn. Here the control instead asks a fixed region of paper to bend. Both
panels remain flexible, with the same held strips, passive material springs,
closed crease and contact order (see the [glossary](../glossary.md)). Generate
the comparison with:

```bash
stack run senbazuru-material-study -- --band-refinement build/fold-material
```

The band covers distances `0.125` to `0.4375` from the shared crease on the
unfolded upper panel, in fractions of the unit sheet's side. Its width is
`0.3125`. It includes the three old lines and excludes fully held edges.
Each triangle edge running across the panel's width represents the material
interval halfway to its neighbors, clipped at the band's ends. At length
subdivision one, the edge at `0.125` receives `[0.125, 0.1875]`; at subdivision four, it receives
`[0.125, 0.140625]`. The band does not shrink when its triangles do.

Normalize the control once against the original coarse three-line fixture.
Its summed desired turn is `Theta = -1.1658271779` radians, and its imposed
energy on flat paper is `Eflat = 1.8132418925`. The negative sign follows the
upper panel's material winding, not the camera. For an edge representing
material length `d` and width segment `w`, with total band width `W`, set:

```text
preferred turn = Theta * d / W
spring stiffness = B * w / d
B = 2 * Eflat * W / Theta² = 0.8338105979
```

An angular spring contributes half its stiffness times the squared difference
between actual and preferred turn. On flat paper the actual turn is zero,
so this rule contributes `B * w * d * Theta² / (2 * W²)`. Summing over the
unit-wide band gives `Eflat`, at every refinement. Summing desired turns
weighted by their width segments gives `Theta`. Both angle and stiffness
must change: dividing only the angle would weaken the total control as more
edges are added. The normalization matches these two quantities, not forces
or energy on the curved starting shape.

Partial intervals remain at the band boundaries. `bandInterval` clips exact
rational bounds before converting to floating point: at subdivision three,
column eleven's interval only touches the band end and must contribute
nothing. A tiny rounding sliver would otherwise create an enormous stiffness
through the division by `d`. Even at a clipped boundary the measured turn is
still the angle between the existing triangles. This is an explicit discrete
loading experiment, not a calibrated law for continuous paper.

The opt-in gallery compares matched holds, the original three-line preference,
the band preference and contact-off versions of both loads on six meshes.
Every run uses the same combined solver: length weights through `1e9`, contact
exchange and forty iterations per stage. Acceptance limits are unchanged.
The fast tests check band width, total desired turn, flat-reference energy,
boundary handling and unchanged material/holds at length subdivisions one,
two, three, four and eight, each at both widths. They add no expensive solve
to the routine test suite.

On 2026-09-16 four of the six contact-enabled band endpoints pass:

| Length × width | Iterations | Relative edge error | Maximum gap | Converged and accepted |
| --- | ---: | ---: | ---: | --- |
| 1×1 | 30 | 2.468e-7 | 7.901e-9 | Yes |
| 2×1 | 44 | 1.336e-5 | 7.723e-5 | No |
| 4×1 | 77 | 7.890e-6 | 0.004120 | Yes |
| 1×2 | 27 | 1.341e-7 | 3.987e-9 | Yes |
| 2×2 | 31 | 6.229e-6 | 3.383e-5 | No |
| 4×2 | 80 | 6.224e-6 | 0.003712 | Yes |

All six retain exact minimum gap zero, the original crease angle, material
identities and exact holds, and pass independent whole-sheet contact checks.
Every recorded constrained gap is nonnegative; every accepted correction
decreases its own stage's energy after repair. The two failures are in the
inner contact solve: its last maximum inequality violations are `3.444e-11`
and `9.629e-12`, both above the unchanged `1e-12` residual cap. The `2×1`
endpoint also exceeds the `1e-5` relative length cap. The `2×2` endpoint meets
that cap but remains unconverged. Safe geometry alone does not establish a
settled shape.

Every band contact-off endpoint crosses, by `0.002089` to `0.002606` sheet
lengths. The four coarser contact-off solves converge. The `4×1` and `4×2`
contact-off solves also fail convergence: their relative length errors remain
`1.124e-5` and `1.104e-5` despite proposed movements below `4e-9` and successful
inner solves. Their final energy searches accept no step. This is distinct
from the constrained middle meshes' failed contact equations. At `1×1`, where
both solves converge, enabling contact changes the lower panel by `0.001671`.
Only the upper panel receives an imposed bend preference, so the other panel
responds through contact.

The old eighteen solves converge and all twelve old constrained endpoints
pass. All fifty-four original FOLD states reproduce #234 unchanged. The
expanded gallery retains ninety complete FOLD/GLB states and 270 SVG plots.
Independent checks recompute reported control angles and spring energies from
exported coordinates, verify band totals at every stage, and confirm unchanged
topology, material identities and holds. The browser exposes all ninety
selections, including the failed endpoints.

The accepted fine band shapes open less than the line-load references. At
`4×2`, maximum gap falls from `0.005676` to `0.003712`. The energy comparison is:

| Loading and mesh | Lower passive | Upper passive | Imposed control |
| --- | ---: | ---: | ---: |
| Three lines, 4×1 | 0.11865 | 0.48050 | 0.36054 |
| Band, 4×1 | 0.11282 | 0.16689 | 0.45142 |
| Three lines, 4×2 | 0.12000 | 0.48619 | 0.35836 |
| Band, 4×2 | 0.11257 | 0.14581 | 0.49931 |

The preferred turn is distributed among more edges, so the per-edge angle is
smaller. At distance `0.25` on `4×2`, the band asks for `-0.1166` radians and
achieves `-0.0523` to `-0.0477` across the width; the three-line reference asks
for `-0.3909`. These are preferences competing with the passive material and
holds, not exact prescribed angles. `checks.json` retains every segment's
clipped interval, achieved/preferred turn, stiffness and energy.

Matching-position changes for `1×1→2×1` and `2×1→4×1` are `0.002577` and
`0.003383`; at width two they are `0.002373` and `0.003074`. Each comparison
includes an unconverged middle mesh, so it cannot establish length convergence.
The accepted `4×1→4×2` width comparison changes matching positions by
`0.0005894`. Its maximum opening changes by about 9.9%, and near-contact
samples change from 894 to 630 of 1480 overlapping locations. Thus fixing the
loading integrals does not by itself settle the shape or contact region.

The [follow-up replay](several-contact-exchanges.md) isolates the two failed
inner contact steps: several selected contact equalities need replacing.
Progressive replacements give accepted endpoints on both middle meshes while
retaining the original policy and all residual limits. The historical results
above remain reproducible. Next, test stronger length enforcement on the fine
contact-off controls, then rerun the full grid with one policy before drawing
conclusions from the length series or enlarging the crane body patch.
Known z order, held crease strips,
uncalibrated stiffness and static endpoints remain limitations; this work
does not certify a continuous flexible route.
