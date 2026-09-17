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
