# Ten short corrections of the body patch

The [third-pair experiment](body-third-contact.md) found a usable **1/8**
correction of the saved body shape, but no settled opening. This experiment
starts from that same archive and attempts at most ten corrections. After each
retained shape it recomputes the material equations and contact guards for
22–63, 14–55 and 46–70. A guard predicts how the gap at a corner of two
triangles' projected overlap changes. The original layer orders stay fixed.
[#339](https://github.com/avalonalex/senbazuru/issues/339) tracks the work;
[the glossary](../glossary.md) defines material coordinates, panels and contact.

**All ten attempts retain a passing shape, but the movement remains tiny and
the late steps shrink toward another contact obstruction.** Total cost falls
**1.604856%**; the maximum displacement from the saved start is **0.112272
pixels** at 600 pixels per sheet unit. Body depth increases only `7.95365e-6`
sheet units. The final full proposal still moves `0.000903601` sheet units,
**9,036 times** the equilibrium limit. This is diagnostic progress, not a
settled or visibly opened body.

```bash
stack run senbazuru-material-study -- --body-short build/fold-material/body-geometry build/fold-material
```

A correction here means computing one direction and checking its full step
and thirty successive halvings. The first fraction with lower total cost and
passing geometry can become the next shape, provided the quadratic itself
passes its numerical checks. A quadratic is the local approximation that
squares linear predictions of each error. The loop stops at equilibrium, ten
corrections, an unverified/failed quadratic, or a search with no passing trial.
Failure leaves the last valid shape in place. All 31 fractions are exported as
diagnostics; passing endpoints do not certify motion between them.

The sheet still has 87 shared vertices, 120 triangles and three exact holds.
Length weight `1e8`, contact weight `1e10`, damping `1e-3`, the 100-iteration
quadratic budget and all crease/panel preferences are unchanged. Geometry
checks still require relative edge error ≤ `1e-5`, exact holds, one connected
material surface and the all-pair contact/order checks at `1e-7`. The first
attempt exactly reproduces #337's raw direction, quadratic report and all
31 trial positions and decisions.

| Attempt | Retained fraction | Retained movement, sheet units | Full proposed movement | Refusal at the next larger fraction |
| ---: | ---: | ---: | ---: | --- |
| 1 | 1/8 | 1.42975e-4 | 1.14380e-3 | 46–70 crosses |
| 2 | 1/16,777,216 | 1.23999e-10 | 2.08035e-3 | Cost rises; 44–92 and 48–92 cross |
| 3 | 1/128 | 7.60013e-6 | 9.72817e-4 | 66–82 crosses |
| 4 | 1/32 | 2.97425e-5 | 9.51759e-4 | 46–70 crosses |
| 5 | 1/256 | 3.56460e-6 | 9.12536e-4 | 46–70 crosses |
| 6 | 1/512 | 1.77311e-6 | 9.07834e-4 | 46–70 crosses |
| 7 | 1/1,024 | 8.84273e-7 | 9.05495e-4 | 46–70 crosses |
| 8 | 1/2,048 | 4.41567e-7 | 9.04329e-4 | 46–70 crosses |
| 9 | 1/8,192 | 1.10321e-7 | 9.03746e-4 | 46–70 crosses |
| 10 | 1/32,768 | 2.75757e-8 | 9.03601e-4 | 46–70 crosses |

The second attempt is almost motionless. Its cost decreases by only
`1.46824e-11`; the next larger trial fails both cost and geometry. The following
attempt recomputes 535 objective rows instead of 500, including all current
negative-gap penalties, and proposes a substantially different direction.
The underlying cause of this sensitivity is not isolated here. It is a
reason to keep the rejected trials, not to describe the run as smooth physical
motion. Every quadratic is verified, with force-balance residual below
`1.67e-8`, twelve guards and the same two active corners at 22–63 and 55–14.
The four 46–70 guards remain inactive throughout.

| Cost component | Saved start | Retained correction 10 |
| --- | ---: | ---: |
| Crease bending | 0.0119682881 | 0.0118278470 |
| Panel bending | 0.00120177763 | 0.00112409653 |
| Length penalty | 0.000015822639 | 0.000019359922 |
| Contact penalty | 0.000000576159 | 0.000003537370 |
| Total | 0.0131864645 | 0.0129748408 |

Lower total cost therefore does not mean every component improves. Every
retained shape passes the independent contact/order checks, while tolerated
negative gaps still contribute contact cost. The final maximum relative
length error is `2.25969e-6`, and its most negative solver gap is `-1.08723e-8`.
No tolerance or gap was rounded away to accept these shapes.

At attempt ten, 46–70's minimum signed height gap actually improves in both
the retained trial and the next larger refusal. Nevertheless the latter fails
the whole-triangle crossing check. As explained in the
[third-pair note](body-third-contact.md), that check measures whether both
triangles extend beyond the other's plane and share an intersection segment;
it is not simply the minimum vertical gap. Fresh height predictions alone
have not removed this obstruction.

The gallery keeps the eleven retained states separate from the 310 trial
states, along with raw corrections, refreshed equations, all-pair refusals,
separate costs and 3,720 overlap witnesses for the three guarded pairs. Fixed
actual-size and magnified views use the same positions. Each tip crop is a
0.002-unit square around its closest original overlap corner; larger trials
can leave it, so the broader overlap view remains available. Independent
calculations verify all 321 FOLD states, lengths, angles, separate costs,
attachments, holds, crossings/order, every trial fraction, quadratic balance
and the retained chain. All 3,210 SVGs parse successfully; browser inspection
covers every attempt and the actual-size and magnified views. Finite differences check all 120 refreshed
corner gradients with maximum error `2.63e-10`. Source archives and the
previous direction comparisons remain unchanged. The opt-in experiment adds
no expensive fixture to the default tests.

The next bounded step is to **inspect the saved final attempt at 46–70,
without new solves**: compare the retained and next-larger refused trial's
plane distances and intersection with the height-gap guards. That can identify
what a different contact constraint would need to control before another
continuation. Preserve the almost-motionless second step as a separate
sensitivity diagnostic. More iterations, automatic contact discovery and
whole-crane inflation are not established by this result.
