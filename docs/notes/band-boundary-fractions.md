# Measure the part of the turn that the band covers

The [prescribed-bend study](prescribed-bend-energy.md) finds a control-energy
change even when every mesh samples the same cylinder. At the ends of the
imposed bending band, a triangle edge represents only part of its neighboring
material interval. The existing rule shortens its preferred turn to that part,
but measures the full actual turn between the triangles. This comparison
attributes the same fraction of actual turn to the band, assuming curvature
is constant across those two strips. No optimizer or contact correction runs:

```bash
stack run senbazuru-material-study -- --prescribed-bend build/fold-material
```

The updated `prescribed-bend.html` retains the original 32 shapes and their
measurements, adds both control energies and separates full from partial
intervals. A diagram locates those intervals on unfolded paper; see the
[glossary](../glossary.md) for material coordinates. The selected width row is
representative: every width segment has the same intervals in these probes.
The candidate remains an experiment, and the default fixtures and solver
still use the original rule.

For a concrete example, at length subdivision two the full neighboring
interval has length `h = 0.0625`. The interval at the band's start covers half
of it, `d = 0.03125`, so its represented fraction is `f = d/h = 0.5`. The
cylinder's full actual turn is `-0.075` radians. The preferred turn for this
partial interval is `-0.1165827`; the negative sign follows the upper panel's
material winding. The old rule compares `-0.075` with that target. The
candidate compares `-0.0375` with it, so its cost is **higher on this same
shape**. That change is a different measurement of the same bend, not an
optimization moving the paper.

An angular spring has energy half stiffness times squared angular error.
For old stiffness `K`, partial-interval target `t` and full actual angle
`theta`, compare:

```text
current:    E = K * (theta - t)^2 / 2
candidate:  E = K * (f*theta - t)^2 / 2
```

The candidate is an ordinary full-angle spring with target `t/f` and
stiffness `K*f²`. This uses the existing spring code unchanged. Both changes
are needed: dividing the target without adjusting stiffness would alter the
flat-paper reference cost. Use the existing convention of wrapping the full
angle error to the branch nearest its target, then scale it by `f`; every
probe here stays away from the branch boundary. The angular energy derivative
is `K*f*(f*theta-t)`, not `K*(f*theta-t)`. The extra factor matters when a later
optimizer asks which direction should lower the energy.

On a cylinder, `theta = -k*h`, with curvature `k = 1.2`. The band has desired
total turn `Theta`, width `W = 5/16` and bending weight `B`. Its old stiffness
is `B*w/d` for width segment `w`; its partial target is `Theta*d/W`.
The candidate therefore contributes
`B*w*d*(-k-Theta/W)^2/2`. Summing interval lengths to `W` and width segments
to one gives `B*W*(-k-Theta/W)^2/2 = 0.8343544095831836`, independently of
length and width resolution. This is a check of a constant-curvature
approximation, not a calibrated paper law or a proof for varying curvature.

Both cylinder probes give:

| Length subdivision | Current total | Candidate total | Full intervals, both rules | Current partial | Candidate partial |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.713620 | 0.834354 | 0.667484 | 0.0461363 | 0.166871 |
| 2 | 0.713620 | 0.834354 | 0.667484 | 0.0461363 | 0.166871 |
| 4 | 0.773987 | 0.834354 | 0.750919 | 0.0230682 | 0.0834354 |
| 8 | 0.804171 | 0.834354 | 0.792637 | 0.0115341 | 0.0417177 |

Width subdivision leaves these totals unchanged. The maximum difference from
the analytic candidate energy is `1.56e-15` across the sixteen cylinder
measurements. Both rules retain the flat reference energy `1.813241893` and
the total preferred turn allocated to the band. Full intervals retain exactly
the same springs. For these eight meshes every partial fraction is one half;
length one has only one partial boundary because the far band end lies
between columns. The comparison explicitly supports these length subdivisions
`1, 2, 4, 8`, and refuses an incompatible neighboring-strip size.

The fixed-corner control still changes with refinement. Its candidate energy
is `0.621746`, `0.933458`, `1.556881`, `2.803727` at lengths 1, 2, 4, 8,
versus the original `0.510502`, `1.021004`, `2.042009`, `4.084017`.
Concentrating a finite corner in progressively narrower strips remains a
different problem from representing a smooth bend. Passive energies, length
penalties and original-grip displacements are unchanged in every probe.
The sampled cylinders still miss the existing length cap, and these static
shapes still do not impose the old grips or certify a folding route.

Per-segment JSON records retain both spring targets/stiffnesses, the interval,
fraction, actual and allocated angles, energies and angular derivatives.
Seven fast tests cover the full-interval identity, normalization, both
cylinders, fixed corners, scalar and spatial derivatives, and refused inputs.
Independent reconstruction checks all 984 control records from the 32 shapes.
All original scalar measurements and 64 original SVG/FOLD files are unchanged;
32 new SVGs show the material intervals. The exact stored-coordinate contact
checks continue to report touching without reversal. All 1,494 tests pass in
a cold warning-free build; formatting, HLint 3.10 and the JavaScript
regressions pass. Browser checks cover all 32 shape/width/interval selections
and all 48 shape/width/length-penalty selections.

This supports testing the candidate on a small solve; it does not adopt it.
Next compare original and fractional band controls on `2×1` and `2×2`, with
matched and contact-off controls, the original holds, the same six-stage
length schedule and progressive contact policy. Keep the old rule as a
reference and every convergence, material, crease and contact cap unchanged.
Compare shapes and separate energies as well as whether each solve converges;
do not enlarge the mesh or infer success for the crane from the cylinder test.
The broader material-refinement, tighter-solve and illustration decisions
remain open under [#195](https://github.com/avalonalex/senbazuru/issues/195).
