# Length refinement under both band rules

The [small solve comparison](fractional-band-solves.md) accepts the fractional
band rule as an experiment, but does not show a stable response across mesh
sizes. Double only the number of subdivisions along the panels, from `2×1`
to `4×1`, keeping width fixed:

```bash
stack run senbazuru-material-study -- --boundary-length build/fold-material
```

Each mesh is one connected folded sheet, with distinct touching layers that
share vertex identities along their joining crease. Material coordinates
identify locations on the unfolded sheet; the [glossary](../glossary.md)
defines the paper terms. The meshes have 64 and 128 triangles. Each runs
matched holds, an upper bending band, and the same band with contact disabled,
under both original and fractional rules: twelve solves in total.

Only the band rule changes between the two selections on a given mesh. At a
partly covered interval, the fractional rule measures the same fraction of
actual and preferred turn. For preferred turn `t`, stiffness `K` and covered
fraction `f`, the equivalent angular spring uses target `t/f` and stiffness `K*f²`; full intervals are unchanged. The
[boundary note](band-boundary-fractions.md) explains the cylinder check and
its limits. Both rules retain the passive springs that resist bending within
each panel, the original closed crease, seed geometry, held strip and outer
edge, six length weights `1e2, 1e4, 1e6, 1e8, 1e9, 1e10`,
[progressive contact exchange](several-contact-exchanges.md) and forty
iterations per stage. Acceptance still requires convergence,
relative edge error at most `1e-5`, original crease error at most `1e-5`
radians, unchanged material and holds, whole-sheet contact at tolerance
`1e-7`, and nonnegative exact directional gaps.

All twelve solves converge; all eight contact-enabled endpoints pass. The
four contact-off endpoints cross and remain diagnostic. All six `2×1` runs
reproduce the prior study's measurements, step histories and ninety exported
assets exactly, excluding measured runtime. The original-rule `4×1` runs
reproduce the earlier common-policy grid. Matched fixtures and histories are
identical under both rule selections. The constrained band results are:

| Mesh | Rule | Iterations | Relative edge error | Maximum opening | Near-contact / overlap samples |
| --- | --- | ---: | ---: | ---: | ---: |
| 2×1 | Original | 59 | 1.596e-7 | 8.014e-7 | 1368 / 1480 |
| 2×1 | Fractional | 59 | 1.483e-7 | 1.262e-6 | 1368 / 1480 |
| 4×1 | Original | 94 | 1.361e-6 | 0.003760 | 503 / 1480 |
| 4×1 | Fractional | 75 | 1.262e-6 | 0.003620 | 609 / 1480 |

Every constrained endpoint has exact minimum gap zero and unchanged holds;
original crease errors remain below `2.5e-16` radians. The fractional rule
modestly reduces the band's length-refinement displacement, from `0.003290`
to `0.003016` sheet lengths. Both exceed the `0.001` target in
[#195](https://github.com/avalonalex/senbazuru/issues/195). The control with
matched holds moves by `0.0009395`, just within that target, and remains
nearly touching on both meshes.

Both band rules change from microscopic opening at `2×1` to a separated
region at `4×1`. Their absolute maximum-opening changes are `0.003759` and
`0.003619` sheet lengths. Percentages against those tiny coarse openings
are about 469,057% and 286,778%; neither is near the 5% target. The gallery
shows absolute changes alongside those percentages. On the fixed 40×40
projected sample grid, 865 locations change category under the original rule
and 759 under the fractional rule. Matched controls change none. These are
sampled categories at the existing `1e-7` threshold, not exact contact areas;
the broad touching/separated regions do not persist across this refinement.

The energy components also remain sensitive to length refinement:

| Control / rule | Lower passive change | Upper passive change | Imposed change |
| --- | ---: | ---: | ---: |
| Matched / either | +9.33% | +9.33% | zero on both |
| Band / original | +9.57% | +57.27% | −10.74% |
| Band / fractional | +7.87% | +54.20% | −18.37% |

These changes use each rule's own objective, divided by the coarser magnitude.
Every nonzero component exceeds the 5% target. In particular, even the matched
control has an energy change with no imposed band at all: correcting partial
band intervals cannot remove every source of refinement sensitivity. This
does not by itself distinguish ordinary coarse-mesh approximation from a
remaining numerical or modeling problem.

Measure both band costs on each endpoint to separate a change of shape from
a change of measurement. At `4×1`, the original endpoint costs `0.469568`
under its own rule and `0.504593` under the fractional rule; the fractional
endpoint costs `0.493423` and `0.497566`, respectively. The two endpoints
also differ in passive energy, so their band costs alone cannot rank total
equilibrium objectives. Changing the rule moves matching lower/upper points
by up to `0.0007974 / 0.0008547`. With contact disabled the lower change is
only `7.93e-8`, while the upper change is `0.001009`. The invalid controls
help isolate the lower panel's response through contact; their minimum gaps
are still negative (`−0.001642` original, `−0.002252` fractional at `4×1`).

The gallery keeps paired endpoint profiles, both band costs, target tables
for each rule, and side-by-side refinement contact maps. Its 36 FOLD/GLB
states and 108 SVGs retain original, repaired and solved numerical states;
these are not a folding sequence. Independent coordinate reconstruction
checks material/topology, holds, lengths, shared crease angles, passive and
imposed energies and matching-point changes. Separate rational clipping
reproduces all twelve exact endpoint gap extrema and 19,200 fixed-location
samples. The twelve solves took 166.4 local CPU seconds and remain opt-in;
no long solve is added to CI. Fast fixture checks now include `4×1`.
Browser checks cover all 36 new selections, 21 earlier endpoint selections
and an unavailable-endpoint control; paired maps and the complete paper were
inspected at normal display size. All 1,497 tests pass in a cold build without
compiler warnings; formatting, HLint 3.10 and JavaScript regressions pass.

The fractional rule remains useful for its prescribed-cylinder consistency,
but this comparison does not meet the material study's exit criteria. Before
another mesh increase, compare where the saved `2×1` and `4×1` endpoints put
their turns and bending energy: near the held strip, at the band ends and in
the interior, with the matched control beside the loaded case. This needs no
new solve and can guide whether the next experiment should change numerical
accuracy or test a different approximation of bending. Keep `4×2`, tighter-solve
confirmation, physical calibration, the illustration decision and a checked
flexible route separate; neither rule becomes the default from this result.
