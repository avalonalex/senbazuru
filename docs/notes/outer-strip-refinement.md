# Refining only the strip outside the band

The [saved-location study](bending-energy-locations.md) found a reverse bend
outside the loaded band on the finer mesh. Refine that short strip separately
from the rest of the paper:

```bash
stack run senbazuru-material-study -- --outer-strip build/fold-material
```

Open `outer-strip.html` on the study server. Material coordinates locate
points on the unfolded sheet; a panel is allowed to bend between its mesh
triangles. The [glossary](../glossary.md) defines the paper terms. The upper
band occupies distances `1/8` to `7/16` from the shared crease. The strip
through `1/8` and the outer edge at `1/2` are held on both panels. The last
coarse strip, from `7/16` to `1/2`, has no transverse bend inside it: no mesh
edge parallel to the shared crease where that strip can change angle.

| Mesh | Rest of panel | Outer strip | Triangles on both panels |
| --- | --- | --- | ---: |
| Coarse | Original 2×1 columns | One strip | 64 |
| Outer only | Unchanged from coarse | Split at 15/32 | 72 |
| Rest only | Original 4×1 columns | One strip | 120 |
| Fine | Original 4×1 columns | Split at 15/32 | 128 |

The rest-only mesh is fine with the column at `15/32` removed. Both panels
change together and width stays fixed. Every starting vertex comes from the
same exact rational profile; rebuilding material cells changes the available
bends without changing the seed shape. This is a comparison of static meshes,
not vertex interpolation along a folding motion. The shared crease remains
one set of vertex identities, and touching layers elsewhere stay distinct.

Each mesh runs matched holds, the upper band, and the same band without
contact, under original and fractional loading rules: 24 solves. They keep
passive bending coefficient `0.2`, the closed crease, length weights `1e2,
1e4, 1e6, 1e8, 1e9, 1e10`, progressive contact exchange, 40 iterations per
stage and all acceptance caps. An accepted endpoint still requires
convergence, relative edge error at most `1e-5`, original crease error at most
`1e-5` radians, exact holds and material identities, independent triangle
contact at `1e-7`, and nonnegative exact directional gaps. No new long solve
runs in the regular test suite.

Uneven columns require explicit spring supports. A transverse edge represents
the interval halfway to its neighbors; clip that to the fixed band. If the
covered fraction is `f`, the fractional rule uses the equivalent spring
`target/f` and `stiffness*f²`. At `7/16`, `f` is `1/2` on both uniform
meshes, `2/3` on outer-only and `1/3` on rest-only. The band extent, total
preferred turn and flat-paper load energy remain fixed, but the discrete
coefficients do not. Passive stiffness also follows the changed triangle
heights. The original-rule band springs on outer-only retain the coarse
loading coefficients; under the fractional rule the end coefficient changes.
This experiment therefore isolates local mesh refinement, including its
changed approximation of bending, rather than an extra degree of freedom
with an otherwise identical matrix.

Adding only the outer column is enough to produce a visible opening. Maximum
separation, in sheet lengths, is:

| Mesh | Original rule | Fractional rule |
| --- | ---: | ---: |
| Coarse | 0.0000008014 | 0.0000012618 |
| Outer only | 0.00280753 | 0.00271015 |
| Rest only | 0.00084965 | 0.00433645 **unconverged** |
| Fine | 0.00376000 | 0.00361987 |

The new upper bend at `15/32` turns back at 2.2404 / 2.1175 radians per
sheet length under the two rules, compared with 3.1853 / 3.0403 on fine.
That bend's passive energy is 0.016292 / 0.014639, versus 0.000244 in the
matched control. Here passive energy measures resistance to panel bending;
the imposed band preference is accounted for separately. Outer-only reaches
about three quarters of fine's maximum opening, but that is not a percentage
of causation: shape and energy changes do not add across the two refinements.
Under the original rule, refining the rest still changes positions by
0.002534 at matching material vertices and creates a smaller opening without
the outer bend. The fractional rest-only endpoint has not settled, so it
cannot establish the corresponding comparison.

Matched holds remain essentially touching. Passive energy on each panel is
0.0994134 on coarse, 0.0997355 on outer-only, 0.1083465 on rest-only and
0.1086840 on fine. Refining the outer strip changes this by about 0.32%;
refining the rest changes it by about 8.99%. The larger matched energy change
therefore persists without the added outer bend. The loaded opening and the
matched energy sensitivity need not have the same explanation.

Of 24 solves, 22 converge and 15 of 16 contact-enabled endpoints pass.
All eight contact-off endpoints cross and remain diagnostic. Two runs use
all 40 iterations of the final length-weight stage without meeting the
`1e-7` movement stopping threshold:

| Run | Last full proposed movement | Other endpoint checks |
| --- | ---: | --- |
| Rest-only, fractional band | 1.2213e-7 | Geometry/contact pass; relative edge error 1.0436e-6 |
| Outer-only, original band, contact off | 6.9995e-7 | Crosses; relative edge error 9.8193e-7 |

Their final local quadratic solves (the approximate bending/contact problem
used to propose one step) converge and the full proposed steps are accepted.
This is exhaustion of the existing outer iteration budget, not a
refused contact step. Neither is relabeled converged because its geometry or
last movement looks close enough. All twelve uniform reference histories and
geometry/energy measurements reproduce the previous study; evaluating both
cost rules for reporting differs only by floating-point roundoff below
`1e-14`. The 24 opt-in solves took 375.3 local CPU seconds.

The gallery keeps every original, repaired and solved numerical state as
FOLD/GLB, with side profiles, signed gaps, fixed-location contact maps and
spring records. Four endpoint cards and normalized turn profiles stay on the
solved states while the detailed viewer selects a numerical stage. Failed
endpoints remain visible and cannot pass a comparison. Empty states are not
replaced by the starting guess in an endpoint comparison. Region costs keep
all transverse, lengthwise and diagonal springs and account for the original
closed crease separately; they are discrete bookkeeping, not energy per area.

Independent calculations from 72 exported FOLD states check material cells,
held and shared vertices, edge lengths, signed angles, all 9,312 spring
records, supports, energies and matching-vertex comparisons. Rational
triangle clipping independently reproduces all 24 endpoint gap extrema and
38,400 fixed-location samples. All 232 SVGs parse; the 108 uniform-reference
profile/gap/map SVGs and normalized FOLD geometry reproduce exactly, and the
archived inputs are unchanged. Browser checks cover all 72 state selections
and 96 panel/energy selections, a missing-endpoint control and the connected
3D viewer. Six fast fixture, analytic and rejection tests
bring the cold warning-free suite to 1,508 passing examples; formatting,
HLint 3.10 and JavaScript checks pass.

Next, give the two exhausted cases a separate extra-work control: restart
their stored endpoints at the same final length weight, with unchanged
material, holds, contact policy and stopping thresholds. Keep the original
40-iteration results and compare the resumed movement, openings and energies.
That tests whether more work settles these endpoints before drawing stronger
refinement conclusions. It does not establish a global energy minimum.
The matched interior energy change, `4×2`, real-paper calibration and
material/illustration acceptance remain separate questions; neither band
rule becomes the default from this experiment.
