# One more length doubling for the band

The [common-policy grid](combined-band-refinement.md) accepts all constrained
endpoints, but its second length doubling changes the band shape more than
the first. Add `8×1` while keeping width fixed. Compare matched holds, the
distributed-band preference and the same preference with contact disabled
on `2×1`, `4×1` and `8×1`:

```bash
stack run senbazuru-material-study -- --band-refinement-8 build/fold-material
```

These meshes have 64, 128 and 256 triangles. Material coordinates label points
on the unfolded sheet; refinement adds vertices without changing the material
region or its held boundaries. The [band preference](distributed-bend-preference.md)
occupies distances `0.125` to `0.4375` from the shared crease and retains its
total desired turn and flat-paper control energy. Both panels remain flexible,
and share vertex identities only along their joining crease. The
[glossary](../glossary.md) defines the paper terms.

All nine solves use progressive contact exchange, length weights `1e2`,
`1e4`, `1e6`, `1e8`, `1e9`, `1e10`, and forty iterations per stage. The old
grid and this follow-up share one policy constructor. Neither physical
controls nor acceptance limits change: relative edge error must be at most
`1e-5`, original crease error at most `1e-5` radians, exact lower/upper gaps
nonnegative, and independent whole-sheet contact must pass its existing
`1e-7` distance tolerance. Held positions and material identities remain exact.
A converged solver and valid geometry are separate requirements; a crossing
contact-off endpoint is diagnostic even if its length error is small.

The opt-in gallery retains the original guess, repaired numerical guess and
endpoint for each run: twenty-seven complete FOLD/GLB states, 81 SVG plots
and step reports in `checks.json`. The 40×40 gap-map locations and `1e-7`
near-contact threshold match the previous study. Sample counts describe
separation at those locations, not exact contact area. Compare matching
material positions and passive/control energies as well as maximum opening.
These numerical states are not a physical folding sequence.

All nine solves converge. All six contact-enabled endpoints pass every
unchanged check; the three contact-off endpoints still cross and remain
invalid paper. The band results are:

| Mesh | Iterations | Relative edge error | Maximum opening | Near-contact samples / overlap |
| --- | ---: | ---: | ---: | ---: |
| 2×1 | 59 | 1.596e-7 | 0.0000008014 | 1368 / 1480 |
| 4×1 | 94 | 1.361e-6 | 0.003760 | 503 / 1480 |
| 8×1 | 90 | 3.570e-6 | 0.004151 | 498 / 1480 |

Every band endpoint has exact minimum gap zero, unchanged holds, and original
crease error below `2.5e-16` radians. At `8×1`, the matched reference keeps
all 1480 overlap samples near contact and reaches relative edge error
`4.734e-7`. The contact-off control reaches `4.508e-6` but penetrates by
`0.001493` sheet lengths: convergence and accurate lengths do not establish
contact order.

Maximum movements of matching material points, in sheet lengths, are:

| Control | 2×1 → 4×1 | 4×1 → 8×1 |
| --- | ---: | ---: |
| Matched holds | 0.0009395 | 0.0006894 |
| Band preference | 0.003290 | 0.001233 |
| Band, contact off (invalid) | 0.003437 | 0.001173 |

The band's latest change is about 63% smaller than the preceding doubling.
Its opening grows about 10%, while its sampled near-contact count changes
little. This is encouraging evidence that length refinement is settling,
but one smaller change does not demonstrate a limiting shape. Bending energies
still change: lower passive, upper passive and imposed energies go from
`0.11271`, `0.16177`, `0.46957` at `4×1` to `0.11986`, `0.21744`, `0.38397`
at `8×1`. The finer upper panel pays more passive bending cost while satisfying
its imposed preference better. These are illustrative spring energies, not
calibrated measurements of real paper.

Enabling contact at `8×1` changes the lower endpoint by `0.0008843` and the
upper by `0.0005272`, compared with the contact-off control. Only the upper
panel has the added preference, so the lower movement records the coupling
through contact. Comparing this way retains the contact-off failure instead
of treating that endpoint as another valid fold.

Independent coordinate checks cover all twenty-seven exported stages:
material and shared vertex identities, lengths, exact holds, original crease
angles, control angles, band integrals and energies. The eighteen reference
FOLD states reproduce the preceding `2×1` and `4×1` study. Separate rational
polygon clipping reproduces all nine endpoints' exact gap extrema and all
14,400 fixed-location gap samples. Matching-position and contact-response
comparisons are recomputed from coordinates. Accepted solver corrections
decrease their own stage's repaired energy, and converged inner steps meet
the unchanged residual caps. The gallery's twenty-seven selections show
the corresponding plots, downloads and verdicts; the fine band endpoint is
also inspected in 3D from above and below. The cold build passes all 1451
tests without warnings; formatting and HLint 3.10 are clean. Long solves
remain opt-in and add no default CI workload.

The next bounded experiment is `8×2` with these same three controls and
numerical policy. Compare `4×2→8×2` for another length doubling and
`8×1→8×2` for width sensitivity, checking acceptance before interpreting
shape or energy. A shared numerical policy does not remove mesh dependence
from finite length penalties or discrete bending springs. Keep the crane
body patch small until these changes are understood. General contact
discovery and a continuously checked flexible route remain separate work.
