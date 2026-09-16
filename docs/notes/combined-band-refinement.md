# One numerical policy for the whole band grid

The [contact replay](several-contact-exchanges.md) repairs the two middle
meshes, and [stronger length enforcement](fine-band-length-enforcement.md)
repairs the fine contact-off solves. Those isolated results use different
numerical policies. Before comparing mesh refinement again, apply both
changes to every mesh and every control:

```bash
stack run senbazuru-material-study -- --combined-band-refinement build/fold-material
```

The six length × width meshes are `1×1`, `2×1`, `4×1`, `1×2`, `2×2`, `4×2`,
with 32, 64, 128, 64, 128 and 256 triangles. Each has matched holds, the
original three-line bending preference, the [fixed-band preference](distributed-bend-preference.md),
and contact-off versions of both preferences (paper terms are in the
[glossary](../glossary.md)). The band occupies the same
material region, with the same total desired turn and flat-paper control
energy, at every resolution. Material coordinates identify the original
points on the unfolded sheet; matching those coordinates lets us compare
shapes even when refinement adds more vertices.

Every solve uses length weights `1e2`, `1e4`, `1e6`, `1e8`, `1e9`, `1e10`,
progressive contact exchange and forty iterations per stage. Held regions,
passive springs, imposed preferences and all acceptance limits stay fixed.
The relative edge-length cap is still `1e-5`, the original crease-angle cap
is `1e-5` radians, and the complete stored geometry must have nonnegative
exact gaps in the prescribed lower/upper order. Independent whole-sheet
contact checks retain their `1e-7` distance tolerance. Numerical convergence
also requires a small full proposed correction and passing inner material
and contact equations. The previous commands keep their original policies.

The gallery retains the original guess, repaired numerical guess and final
endpoint for each run: ninety complete FOLD/GLB states, 270 SVG plots and
step histories in `checks.json`. It separates convergence from acceptance,
and reports passive and imposed energies separately. All gap maps use the
same 40×40 projected locations and `1e-7` near-contact threshold. Counts at
those sample locations describe separation; they do not measure exact contact
area. Solver corrections are not a physical folding sequence.

On 2026-09-16 all thirty solves converge. All eighteen contact-enabled
endpoints pass, including every band mesh; all twelve contact-off endpoints
still cross and remain invalid paper. Every constrained step retains a
nonnegative exact gap. Material identities, shared crease vertices and held
positions remain unchanged, and original crease errors stay below `2.5e-16`
radians. The band results are:

| Length × width | Iterations | Relative edge error | Maximum gap | Near-contact / overlap samples |
| --- | ---: | ---: | ---: | ---: |
| 1×1 | 32 | 2.475e-8 | 8.159e-10 | 1480 / 1480 |
| 2×1 | 59 | 1.596e-7 | 8.014e-7 | 1368 / 1480 |
| 4×1 | 94 | 1.361e-6 | 0.003760 | 503 / 1480 |
| 1×2 | 29 | 1.330e-8 | 4.075e-10 | 1480 / 1480 |
| 2×2 | 39 | 7.172e-8 | 3.412e-7 | 1447 / 1480 |
| 4×2 | 98 | 9.364e-7 | 0.003287 | 573 / 1480 |

Gaps and position changes are in sheet-length units. Every constrained
minimum gap is exactly zero, including the held touching region. Band
contact-off crossings range from `0.001642` to `0.002433`; the worst relative
length error across all thirty solves is `2.289e-6`. The four fine matched
and band contact-off endpoints exactly reproduce the stronger schedules
from the isolated length experiment. All sixty original and repaired guesses
reproduce the old band grid apart from titles.

Stronger enforcement also changes accepted shapes. Relative to the earlier
progressive-contact results, the middle band openings shrink from `8.008e-6`
to `8.014e-7` and from `3.409e-6` to `3.412e-7`. A tenfold increase in length
weight reduces these small gaps by roughly tenfold. Their numerical
acceptance does not make those openings robust physical predictions. At
`4×1` and `4×2`, the new band coordinates change from the original band grid
by at most `0.0006069` and `0.0003586` respectively.

The accepted endpoints still do not establish shape convergence. Matching
material points move by:

| Refinement | Maximum band position change |
| --- | ---: |
| 1×1 → 2×1 | 0.002403 |
| 2×1 → 4×1 | 0.003290 |
| 1×2 → 2×2 | 0.002320 |
| 2×2 → 4×2 | 0.002800 |
| 4×1 → 4×2 | 0.0006094 |

The second length doubling changes more than the first at both widths.
Width refinement retains the fine opening but changes its size and the
sampled near-contact region. The original line-load controls also remain
length sensitive: their second doublings change matching positions by
`0.004231` and `0.004152`. The distributed preference reduces that change
in this grid, without making it disappear.

At `4×2`, the band's lower passive, upper passive and imposed energies are
`0.11243`, `0.14337` and `0.50648`; the line-load values are `0.12016`,
`0.48650` and `0.35851`. Their maximum openings are `0.003287` and `0.005707`.
The gallery retains each achieved/preferred turn and both spring stiffnesses
for inspection. Enabling band contact changes the lower panel by `0.001336`
at this resolution even though only the upper receives an imposed preference.
The contact-off comparison isolates that response while remaining invalid.

Independent coordinate checks cover every exported stage's lengths, holds,
shared topology, material ids, control angles, band integrals and energies.
A separate rational polygon-clipping calculation reproduces exact gap
extrema at all thirty endpoints and their 48,000 fixed-location gap samples.
Matching-position and panel-response comparisons are recomputed from material
coordinates. Accepted corrections decrease their own stage's repaired energy;
all converged inner steps meet the unchanged residual caps. The long solves
remain opt-in and add no default CI workload. All ninety browser selections
show their corresponding plots, downloads and verdicts; the finest band
endpoint was also inspected in 3D from above and below.

The next bounded experiment is `8×1` with matched holds, the band preference
and its contact-off control under this same policy. Compare `4×1→8×1` with
`2×1→4×1`, checking acceptance before interpreting the new opening, energies
or sampled contact region. This doubles length resolution without also
changing width. A common numerical policy does not calibrate the material or
prove a continuum limit: the absolute length penalty and discrete bending
springs still depend on the mesh. Keep the crane body patch small until these
shape changes are understood. General contact discovery and a continuously
checked flexible route remain separate work.
