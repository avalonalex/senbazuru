# Fractional band turns in small coupled solves

The [prescribed-bend comparison](band-boundary-fractions.md) removes a
boundary-energy drift on a known cylinder. A solved sheet has additional
constraints: its outer edges and a strip beside the shared crease are held,
and the two layers cannot pass through each other. Test the candidate under
those constraints before assuming that a consistent cylinder measurement
also gives a stable paper shape:

```bash
stack run senbazuru-material-study -- --boundary-solves build/fold-material
```

This runs twelve static solves: original and fractional band rules on
`2×1` and `2×2`, each with matched holds, an upper-panel bend band and the
same band with contact disabled. The numbers subdivide the original mesh
along length and width; these two meshes have 64 and 128 triangles. Material
coordinates identify points on the unfolded sheet; the [glossary](../glossary.md)
defines the paper terms. Both layers belong to one connected sheet and share
the original closed crease. Matching holds leave the two panels' bending
preferences equal; the added band asks only the upper panel to turn further.

At a band boundary, the fractional rule measures the same fraction of actual
and preferred turn. Its equivalent full-angle spring has target `t/f` and
stiffness `K*f²`, where `f` is the fraction of the neighboring material
interval inside the band. Construct it from the original fixture each time
so the fraction cannot be applied twice. Only partial band springs change;
full intervals, passive springs, seed coordinates, material identities,
shared crease and holds are identical. Matched controls contain no band,
so selecting either rule must reproduce the same solve.

Every run uses the existing length weights `1e2, 1e4, 1e6, 1e8, 1e9, 1e10`,
[progressive contact exchange](several-contact-exchanges.md) and forty
iterations per stage. This method can replace several equations that enforce
touching while retaining every non-crossing inequality. The relative
length-error cap remains `1e-5`, the original-crease angle cap `1e-5` radians,
and whole-sheet contact tolerance `1e-7` sheet lengths. Exact directional
gaps between the stored triangles must also be nonnegative. Convergence
requires a full proposed movement at most `1e-7` and the unchanged inner
material/contact residual checks: the errors in the linear equations used
to propose a step. Original commands retain their policies;
the candidate is an explicit experiment, not a new default paper law.

All twelve solves converge. All eight contact-enabled endpoints pass the
independent geometry checks; the four contact-off endpoints cross and remain
diagnostics. The matched endpoints and their histories reproduce exactly
under both rule selections. Original-rule results reproduce all eighteen
original, repaired and solved states from the [common band grid](combined-band-refinement.md),
apart from descriptive titles. The loaded contact-enabled results are:

| Mesh | Rule | Iterations | Relative length error | Maximum opening | Near-contact / overlap samples |
| --- | --- | ---: | ---: | ---: | ---: |
| 2×1 | Original | 59 | 1.596e-7 | 8.014e-7 | 1368 / 1480 |
| 2×1 | Fractional | 59 | 1.483e-7 | 1.262e-6 | 1368 / 1480 |
| 2×2 | Original | 39 | 7.172e-8 | 3.412e-7 | 1447 / 1480 |
| 2×2 | Fractional | 43 | 6.413e-8 | 4.933e-7 | 1441 / 1480 |

All constrained minima are exactly zero, including the held touching strip;
original crease errors are below `2.5e-16` radians and held positions are
unchanged. Changing the rule moves corresponding points by at most
`0.0006636` at `2×1` and `0.0006482` at `2×2`, with nearly equal changes on
both panels. The lower panel's springs never changed. In the contact-off
comparison its rule-dependent change is only `7.03e-12` / `4.08e-8`, while
the upper changes by `0.0008123` / `0.0007910`. This distinguishes the lower
panel's response through contact from changing its own material controls.
Contact-off minimum gaps worsen from `-0.002433` / `-0.002307` to
`-0.002783` / `-0.002701`; neither rule makes those endpoints valid paper.

Energy costs under different rules cannot directly rank the shapes. Evaluate
both rules on each identical endpoint instead. The imposed costs at `2×1`
are:

| Solved using | Measured with original rule | Measured with fractional rule |
| --- | ---: | ---: |
| Original | 0.526063 | 0.615810 |
| Fractional | 0.533797 | 0.609567 |

Each endpoint has the smaller imposed cost under its own rule in this
comparison. The lower/upper passive energies change from `0.102864 / 0.102864`
to `0.102910 / 0.102911`. At `2×2`, they change from
`0.102742 / 0.102742` to `0.102794 / 0.102794`; the imposed cost under the
rule used for solving changes from `0.526786` to `0.610155`. The gallery and
raw report retain both costs, every controlled-edge angle and the full step
history. None of these illustrative units are calibrated paper stiffness.

The candidate does **not** improve width sensitivity here. Matching-position
change from `2×1` to `2×2` is `0.0001536`, versus `0.0001188` for the original
rule. Its maximum opening changes by 60.91%, versus 57.43%. These are tiny
absolute openings; prior length-penalty experiments already show that such
small gaps can be numerical-policy dependent. Neither percentage passes the
existing 5% opening target. Equal contact counts also hide changed locations:
although both `2×1` rules report 1368 near-contact samples, sixteen locations
switch between touching and separated. Six switch at `2×2`. Refining width
changes 73 categories with the fractional rule, versus 79 with the original.
These use the same 40×40 projected grid and `1e-7` threshold, not exact contact
areas or a proof of contact-map stability.

The gallery retains 36 complete FOLD/GLB states and 108 SVG profiles, gap
plots and maps. Independent coordinate reconstruction checks lengths, holds,
shared topology, passive/control energies, both cost measurements and all
position comparisons. Separate rational polygon clipping reproduces all
twelve exact endpoint gap extrema and all 19,200 fixed-location samples.
All 36 browser selections and 51 endpoint selections from three older study
datasets pass with the updated shared template; the candidate model was
inspected in 3D from above and below. The three added fast regressions check
fixture isolation, contact-off equivalence, flat normalization and refused
inputs. The twelve opt-in solves take 164.2 local CPU seconds in total and
add no solver workload to default CI. All 1,497 tests pass in a cold build
without warnings; formatting, HLint 3.10 and JavaScript regressions pass.

This passes the small-solve gate for trying length refinement; it does not
establish the material study's exit criteria. Next compare both rules at
`4×1` against these `2×1` references, with the same matched/contact-off
controls, holds, numerical policy and acceptance caps. That tests the first
length doubling without also changing width. Retain the original rule and
measure shapes, separate energies and contact locations before considering
`4×2` or returning to `8×2`. The tighter-solve confirmation, real-paper
calibration, general contact discovery, continuous flexible motion and the
illustration decision remain open under [#195](https://github.com/avalonalex/senbazuru/issues/195).

The [fixed-width length comparison](fractional-band-length.md) now records
that next experiment and its remaining sensitivity.
