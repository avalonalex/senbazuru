# A decision point for length and width refinement

The [8×1 study](band-refinement-8.md) reduces the latest length-refinement
shape change, but its opening and separate bending energies still move.
Before enlarging the crane body patch, add `8×2` under the same policy:

```bash
stack run senbazuru-material-study -- --band-refinement-8x2 build/fold-material
```

Matched holds, a distributed upper-panel bend preference and that preference
with contact disabled are each solved on `4×2`, `8×1` and `8×2`. These meshes
have 256, 256 and 512 triangles. Material coordinates locate the same points
on the unfolded sheet; the [glossary](../glossary.md) defines the paper terms.
The comparison `4×2→8×2` doubles length resolution while keeping width fixed;
`8×1→8×2` doubles width while keeping length fixed. Neither changes the sheet,
held regions, original crease, passive bending rule or
[band bounds and integrated control strength](distributed-bend-preference.md).

Every run uses length weights `1e2`, `1e4`, `1e6`, `1e8`, `1e9`, `1e10`,
progressive contact exchange and forty iterations per stage, through the
same constructor as the preceding two galleries. Endpoint acceptance still
requires numerical convergence, relative edge error at most `1e-5`, original
crease error at most `1e-5` radians, unchanged material/shared vertices and
exact holds, nonnegative exact lower/upper gaps and the independent whole-sheet
contact check at its `1e-7` distance tolerance. Crossing contact-off endpoints
remain diagnostic regardless of their numerical convergence.

[#195](https://github.com/avalonalex/senbazuru/issues/195) now records agreed
engineering targets for ending this small material study. They ask for a
repeatable, non-crossing response that changes little under refinement;
they are not calibrated standards for real paper or a mathematical proof
of a limiting shape:

| Quantity | Target under both length and width refinement |
| --- | --- |
| Matching material positions | Maximum change below `0.001` sheet lengths (0.1% of its unit side) |
| Maximum opening | Change below 5% of the coarser reference magnitude |
| Lower passive, upper passive and imposed energies | Each changes by less than 5% of its own coarser reference magnitude |
| Contact regions | Main touching and separated regions persist in the fixed-location gap maps |
| Numerical robustness | A tighter-solve confirmation stays within the same budgets |

The gallery compares endpoints for the selected control, independently of the
numerical stage being viewed. Percentages use absolute differences. At a
near-zero reference it instead shows the absolute change: opening at or below
`1e-7` uses the existing near-contact threshold, and energy at or below
`1e-12` is treated as numerically negligible. It reports whether both values
remain near zero, without dividing by zero or calling a tiny reference a
meaningful percentage. The matched reference should remain nearly touching.
Invalid or unconverged endpoints retain their numbers without a target-pass
label. Passing the displayed numbers alone does not complete the study:
contact maps still need inspection, and this mesh comparison does not perform
the tighter-solve confirmation.

The two reference endpoints already prevent both directions from meeting
all targets in this run. The `4×2` and `8×1` band openings are `0.003287` and
`0.004151`; their 5% intervals are `0.003123–0.003452` and
`0.003944–0.004359`, which do not overlap. The upper passive energies likewise
have disjoint intervals. Thus a single `8×2` endpoint cannot satisfy both
comparisons. The experiment locates the remaining sensitivity; it cannot
by itself complete the refinement gate, regardless of numerical convergence.

Each case retains its original guess, repaired numerical guess and endpoint:
twenty-seven complete FOLD/GLB states, 81 SVG plots and solver diagnostics in
`checks.json`. The gap maps use the same 40×40 positions and `1e-7` threshold;
counts describe sampled locations, not exact contact area. Numerical
corrections are not a physical folding sequence. The long solves are opt-in
and add no default CI workload.

All nine solves converge. All six contact-enabled endpoints pass, and all
three contact-off endpoints still cross. The new `8×2` outcomes are:

| Control | Iterations | Relative edge error | Minimum exact gap | Maximum opening | Accepted |
| --- | ---: | ---: | ---: | ---: | --- |
| Matched | 60 | 3.207e-7 | 0 | 2.943e-14 | Yes |
| Band | 101 | 2.483e-6 | 0 | 0.004528 | Yes |
| Band, contact off | 83 | 5.120e-6 | -0.001696 | 0.003863 | No |

All 95 held vertices remain exact, the two panels retain their shared crease
ids, and original crease error remains below `2.5e-16` radians. The band
passes endpoint checks but misses the study's refinement targets:

| Band quantity | 4×2 → 8×2 (length) | 8×1 → 8×2 (width) | Target |
| --- | ---: | ---: | --- |
| Matching positions | 0.001770 | 0.0004075 | Below 0.001 |
| Maximum opening | +37.74% | +9.07% | Absolute change below 5% |
| Lower passive energy | +6.67% | +0.06% | Absolute change below 5% |
| Upper passive energy | +31.44% | -13.34% | Absolute change below 5% |
| Imposed energy | -12.00% | +16.08% | Absolute change below 5% |

The matched reference meets the position target in both directions
(`0.0006160` and `0.0001068`) and remains nearly touching. Even there, length
refinement changes each passive energy by `6.47%`, above the energy target;
width changes them by only `0.0856%`. Contact-off band energies also remain
sensitive: upper/imposed changes are `+37.58%` / `-15.59%` for length and
`-12.63%` / `+17.20%` for width. That comparison stays invalid, but shows that
contact alone cannot explain all of the sensitivity.

At `8×2`, the band has 499 near-contact samples and 981 separated samples,
with no crossing among the 1480 overlap samples. Compared with `8×1`, the
near-contact count changes by only one, but 51 locations change between
near contact and separation (25 one way, 26 the other). Compared with `4×2`,
128 locations switch. Similar counts therefore do not mean identical contact
regions. Visual comparison retains the broad held strip and separated area,
but thin near-contact regions change shape and split; region stability is
not established. Enabling contact changes the lower endpoint by `0.001105`
and the upper by `0.0005861`; the upper preference still influences the lower panel.

The compiled run records `2491.6` CPU seconds for the `8×2` band solve,
about 41.5 minutes, versus `204.1` seconds for the replayed `8×1` band and
`240.6` for `4×2`. The matched and contact-off `8×2` solves take `166.8` and
`5.3` CPU seconds. These are local solve measurements, excluding exports and
independent reports, not a profile identifying the bottleneck. The gallery
exposes these times; no expensive solve was added to the default test suite.

Independent coordinate checks cover all twenty-seven states' lengths, exact
holds, material/shared topology, original crease angles, band integrals and
control turns. Passive energies are reconstructed from material triangle
heights and spatial normals, separately from the report's control-edge
breakdown. Rational polygon clipping reproduces exact contact extrema at
all nine endpoints and all 14,400 fixed-location gap samples. Matching
positions and contact-mediated panel changes agree with the exported
coordinates; all eighteen reference FOLD states reproduce #242/#244.
Accepted corrections decrease their own stage's repaired energy and
converged inner steps meet the unchanged residual caps. The cold build passes
all 1451 tests without warnings; formatting, HLint 3.10 and the focused
JavaScript reporting checks pass. All twenty-seven browser selections show
the expected plots, downloads and target labels. Contact maps were compared
at all three meshes, and the fine band was inspected in 3D from above and below.

This completes the `8×2` experiment, not the material study's exit criteria.
Stop increasing mesh size for now. The next bounded study should evaluate
known prescribed bends on the existing meshes, without optimization or
contact correction, and compare passive/control energies and the length
penalty. That separates how the mesh represents the same bend from the
solver's choice of shape. The current data does not identify which term
causes the remaining drift. Profile the costly accepted band solve under
[#208](https://github.com/avalonalex/senbazuru/issues/208) before another large
solve. A tighter-solve confirmation, real-paper calibration, general contact
discovery and a continuously checked flexible route remain open.
