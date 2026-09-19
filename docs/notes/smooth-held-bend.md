# Smoother curvature does not guarantee a smaller refinement gap

The [held-bend reference](prescribed-held-bend.md) joins a circular arc to
straight paper. Its tangent, the direction along the profile, is continuous,
but its curvature, the turning rate per unit material length, jumps at both
joins. This control replaces those jumps with a fixed smooth transition while
keeping the same original grip positions and available paper length.

```bash
stack run senbazuru-material-study -- --smooth-bend build/fold-material
```

Open `smooth-bend.html`. It compares the circular and smooth families on the
same coarse, outer-only, rest-only and fine meshes (64/72/120/128 triangles).
Each has common-curve samples, full-length segments with diagnostic grip drift,
and full-length polygons fitted to both grips. The material coordinates,
springs, shared crease, hold identities, contact policy and acceptance caps
are unchanged. This is a prescribed reference, not an equilibrium or a route.

The inner strip stays flat through material distance `1/8`. Let `A` be the
length of the bending region and `u` run from zero to one through it. Let `k`
be its mean curvature. Prescribe the tangent angle as:

```text
angle(u) = k A (3u² − 2u³)
curvature(u) = 6k u(1 − u)
```

Curvature starts and ends at zero and peaks at `1.5k`. Integrating the unit
vector `(cos angle, sin angle)` along the material gives the side profile;
a straight tangent section uses the remaining length. No new crease is added.
The polynomial shape is fixed before comparing energies; there is no smoothing
width tuned to pass a threshold.

A bounded geometric fit adjusts `k` and `A` to the original outer position
`(0.467267166025, 0.141636737774)` while preserving the full `1/2` material
length from the crease. The smooth reference needs six steps. Integrals use
weighted function samples (eight-point Gauss-Legendre integration) on four
equal subintervals, independent of the paper mesh. A different rule, composite
Simpson integration, uses many equally spaced samples to check coordinates
and energies independently. Finite differences check parameter derivatives,
including the change in integration limits when `A` moves. No material energy
is consulted by either the common-reference or per-mesh fit.

The new common reference bends over `A = 0.143022684385`, compared with
`0.163868215857` for the circle. Its mean curvature is `3.381591624734` and
peak curvature `5.072387437101`, versus the circle's constant
`3.058080151255`. The same grips require a shorter, more concentrated bend in
this family. Thus the experiment tests whether smoothness alone is sufficient;
it cannot isolate the removal of curvature jumps from all other shape changes.

Passive costs per panel are:

| Construction | Circular coarse | Circular rest-only | Change | Smooth coarse | Smooth rest-only | Change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Common curve, sampled or full-length | 0.125641304 | 0.139131537 | 10.74% | 0.156778511 | 0.183683999 | 17.16% |
| Full-length, fitted to grips | 0.123916895 | 0.138760413 | 11.98% | 0.155472076 | 0.182672703 | 17.50% |

Adding only the outer column at `15/32`, in straight paper, changes these
costs only by roundoff. Both layers give the same costs; neither is welded to
the other away from the original crease.

The larger gap does not mean every smooth approximation is less accurate.
The exact continuous comparison for the smooth profile is `0.12 k² A`, from
integrating squared curvature with the same passive coefficient `0.2`.
The circle gives `0.1 k² A`; the factor changes because the curvature varies,
not because the material stiffness changes. These are model costs, not joules.
For the common references:

| Family | Continuous cost | Coarse underestimation | Rest-only underestimation |
| --- | ---: | ---: | ---: |
| Circular | 0.153247166 | 18.01% | 9.21% |
| Smooth | 0.196258506 | 20.12% | 6.41% |

The finer smooth approximation is closer to its own continuous reference even
though its coarse-to-fine gap is larger. The exported transverse intervals
cover the entire bending region: their continuous integrals sum to the full
cost. Neighboring chord directions average curvature differently; their
angular costs remain separate from the interval integrals and any diagonal
costs. This accounts for the prescribed references, not the old solved 8.99%
difference or a calibrated physical stiffness.

All four fitted smooth meshes retain exact grips and touching order, with
one component, shared crease vertices 0/1/2, original-angle error below
`2.45e-16` radians and relative edge error at most `1.12e-15`. The largest grip
copy is `4.45e-15`, allowed only after the raw fit reaches the existing `1e-14`
cap; every edge is measured afterward. Their coarse/rest-only matching vertices
move `0.001046794` sheet lengths, slightly above the study's `0.001` target,
and energy misses its 5% target. These comparison targets are distinct from
the passing endpoint geometry checks. They do not bound surface movement
between matching vertices.

The smooth controls remain diagnostic: common-curve samples shorten edges by
up to `0.00315288` / `0.00100919` relative to material length, and unfitted
full-length segments miss the outer grip by `0.000308144` / `0.0000780169`
sheet lengths. Length, crease and passive costs remain separate in the exports.
Fitted mean curvature changes from `3.245615199338` to `3.344425141821`, and
bend length from `0.151042521014` to `0.145122257917`. Their continuous costs
change too; they are not the same smooth surface.

A useful next control is a cheap refinement ladder evaluating these fixed
common curves against their analytic continuous costs. Keep curve parameters
fixed and keep length-valid and sampled controls separate, before choosing
additional mesh density or running another material solve. This would measure
absolute approximation error rather than relying on two successive totals
agreeing. Grips on full-length approximations can drift and must remain explicit.
It would not calibrate real paper or certify a flexible folding route. See
[#291](https://github.com/avalonalex/senbazuru/issues/291), continuing
[#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).

Independent exported-coordinate checks reproduce 24 FOLDs, 2,832 springs,
4,080 material edges, thirty comparisons and every geometric fit step.
Exact rational triangle clipping confirms all contact extrema. All 49 SVGs
and 48 browser selections are checked. The original circular JSON and FOLDs
reproduce byte-for-byte, and 726 archived assets remain unchanged. The 28
prescribed-reference regressions pass in about 1.16 seconds, including three
new analytic tests and existing invariant checks extended to the smooth family.

All 1,567 tests pass after a cold, warning-free build (400.9 seconds for the full suite). Formatting, HLint 3.10 and JavaScript checks pass.
