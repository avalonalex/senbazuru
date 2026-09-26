# One larger opening from the recovered body shape

[#393](https://github.com/avalonalex/senbazuru/issues/393) follows the
[visible-layer comparison](body-visible-layers.md). The question is whether
one bounded run can produce a visibly useful opening, rather than reduce
invisible numerical errors. The specimen is still sixteen panels cut from the
crane's body and wing attachments: 120 triangles, 87 shared vertices and three
held points. Removing the rest also removes its loads and contacts; the free
neck/tail landmarks measure attachment response, not a complete crane.

The centre stays fixed and the two wing holds move from the original 5°
construction to 10°. These are grip settings, not measured crease angles or
a promise that the body depth doubles. For each free vertex the initial guess
is `recovered + (analytic10 - analytic5)`. It retains the old solver correction
while changing the target; using `analytic10` alone would throw away the
recovered shape. The held vertices receive their new exact coordinates.
This guess may strain or cross paper and is not a physical folding path.

The issue declares the experiment before running: one continuation, at most
40 corrections at length weight `1e8` and contact weight `1e10`, with unchanged
bending preferences and strict convergence checks. No single-pair repairs or
budget extensions follow a failure. The solve writes `run.json` before any
rendering; the separate view command regenerates drawings without new solves.
The validated source archive is copied byte for byte.

At 600 px per sheet side, provisional endpoint screens require at most 0.1 px
of absolute edge-length error, reversed layer height, and intersection length
for triangle pairs rejected by the strict checker. The last two measure depth
through paper and distance along paper, respectively. Local relative edge
strain must stay below 0.1%. Body depth is the world-Z range of the eight
central panels; a useful candidate must add at least 2 px to the recovered
seed's depth. The three new holds must remain exact, with unchanged material
coordinates, triangle indices and crease identities. These screens require
visible-layer review; they do not certify equilibrium, thickness or motion.

The single run uses all 40 corrections. Central depth grows from **21.715 px
to 43.488 px**, a **21.773 px gain**. The wing holds each move 10.841 px;
the free neck and tail attachments move 1.742 and 1.883 px. This is a visible
opening, particularly from the low side view, with no broken shared vertices.

| Measurement | Recovered seed | 10° initial guess | After 40 corrections |
| --- | ---: | ---: | ---: |
| Maximum edge error, px | 0.0000563 | 2.0735 | 0.001020 |
| Maximum local edge strain, % | 0.000162 | 1.3828 | 0.001762 |
| Maximum wrong-side height, px | 0.00000345 | 9.3195 | 0.0000220 |
| Longest strictly failing intersection, px | 0 | 0 | 0.23175 |
| Crease preference energy | 0.0119861 | 0.0525389 | 0.0462814 |
| Uncreased panel energy | 0.00121380 | 0.00120660 | 0.00463627 |
| Length penalty | 0.00001589 | 10112.0 | 0.00117784 |
| Contact penalty | 0.000000593 | 65911997.9 | 0.000008872 |

Zero strict crossings in the initial guess does not make it valid: its layers
are already reversed by 9.32 px. The endpoint removes that large defect and
passes the provisional length, strain and order-height screens, but **misses
the declared intersection-length screen**. Triangle pair 2–39 intersects over
0.23175 px, while 46–70 contributes 0.000129 px. No tolerance is enlarged after
seeing this result. The endpoint stays diagnostic for explicit visual review.
Strict geometry fails both the original `1e-5` relative-length check and contact;
all 7,140 triangle pairs are checked, with no missing order checks.

The last accepted correction is 1/65,536 of its proposal. The full proposal
would still move a vertex by 0.308 px, 5,138 times its strict movement stopping
threshold. Forty cheaper corrections therefore do not demonstrate equilibrium.
Larger crease and panel energies than the seed are expected when the holds ask
for more opening; comparing their magnitudes is not a convergence test.

All endpoint pair orders resolve under the established 0.1 px depth-tie policy.
The largest overridden depth is only 0.000180 px. Top and both 45° views cover
the sheet; the low view retains 0.000443 px² of uncovered paper. The recovered
seed's earlier top/below coverage residuals remain in comparison uncertainty.
At actual size, the side views show a wider lower opening and more cream inner
paper; magnification keeps the small numerical residuals inspectable.

**Next:** review this visibly opened static specimen and the small failed
intersection in drawing context before choosing any follow-up. Do not resume
individual-pair precision repairs or extend the solve automatically. This
experiment supplies an inspectable larger opening, not an accepted whole-crane
inflation or proof that a broader parameter range works.

The gallery uses one extent and scale across seed, guess and endpoint for each
of the established top, 45° above, 45° below and 15° above cameras. It retains
the 0.1 px visibility allowance and reports unresolved overlaps and coverage
uncertainty. FOLD exports contain the raw mesh, including any refused geometry;
SVG visibility does not change those positions. Full proposals, rejected
trials, every retained checkpoint, attachment positions and achieved crease
angles remain available alongside separate crease, panel, length and contact
costs. Independent NumPy calculations reproduce lengths, opening, holds, crease/panel
energies, the reported intersections and the saved trial positions. Shapely/GEOS
reproduces all sixteen difference-mask shapes within `5e-9 px²` of symmetric
area difference. Two source-owner masks contain nearly coincident overlapping
pieces, so summing their floating-point polygon areas overstates the union by
up to **0.02034 px²**. The gallery therefore adds ±0.05 px² reporting uncertainty
to area intervals, alongside uncovered-paper uncertainty. This does not change
a contact or length screen, and the drawn masks remain the review evidence.
Small tests exercise the guess and its input refusals without running this
body solve in CI.

Reproduce once with the existing recovered archive:

```bash
stack run senbazuru-material-study -- --body-larger-opening build/fold-material/body-subdivision build/fold-material
```

For later drawing changes, use `--body-larger-opening-view build/fold-material`.
The solve command refuses an existing `run.json` to prevent an accidental
second experiment. Open `body-larger-opening.html`.
