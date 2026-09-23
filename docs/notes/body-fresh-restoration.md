# The contact repair works again after refreshing the direction

[The fresh material direction](body-fresh-direction.md) starts from the earlier
repaired state. Its 1/256 fraction passes geometry, but 1/128 again crosses at
triangles 46–70. Applying **one** minimum-movement repair to that fresh 1/128
trial makes it pass the unchanged geometry, guard and actual-cost checks.
The largest repair is **2.973729e-12 sheet lengths**.
[#354](https://github.com/avalonalex/senbazuru/issues/354) tracks this repeat under
[#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).
See [the glossary](../glossary.md) for material coordinates, panels and contact.

```bash
stack run senbazuru-material-study -- --body-fresh-restoration build/fold-material/body-fresh build/fold-material
```

The four states are the fresh direction's repaired start, its saved passing
1/256, its refused 1/128, and one repair of that refused trial. The main material
direction is saved data. The only new calculation repeats
[the earlier projection](body-contact-restoration.md): recompute the derivative
of vertex 27's distance to triangle 70's moving plane, exclude held coordinates,
and take the smallest sum of squared vertex movements that recovers the lost
distance in the local prediction. All four relevant vertices are free: 27 and
the plane's corners 81, 71 and 20. Exact holds elsewhere do not move.

The target is **this direction's repaired starting distance**,
`-9.999883680226335e-8`, rather than the older attempt-ten distance. It restores
the existing negative floor, not zero separation. The plane extends beyond the
finite triangle, so this remains a conservative rule for the diagnosed case.
Keep contact tolerance `1e-7`, relative length tolerance `1e-5`, length weight
`1e8`, contact weight `1e10` and every material preference unchanged. Check the
twelve original overlap guards and plane guard against the total displacement,
then the overlap derivatives refreshed at the refused trial against the repair.
The linear residual cap remains `1e-12`. Remeasure actual geometry and costs
before calling the candidate usable. No further material solve, repeated repair
or continuation runs.

| State | Plane margin above −1e-7, ×1e-12 | Geometry | Actual total cost |
| --- | ---: | --- | ---: |
| Repaired start of fresh direction | +1.163196 | Pass | 0.012967223114007682 |
| Saved fresh 1/256 | +0.045232 | Pass | 0.012963453167721534 |
| Saved fresh 1/128 | −3.308665 | Fail: 46–70 | 0.012959705575584384 |
| One repair at fresh 1/128 | +1.163197 | Pass | 0.012959705234960362 |

These margins use independent 60-digit arithmetic on the exported coordinates.
In the executable's arithmetic, the restored distance ends about `8.7e-19`
above its target. The installed correction's linear restoration residual is
about `-4.3e-19`: coordinate rounding can put this tiny residual on either side
of zero, well within the unchanged cap. All original and refreshed overlap
margins stay positive; their minima are `6.007240e-12` and `4.481107e-12`.
The original plane guard has `4.471866e-12` of linear margin.

The repair keeps the fresh 1/128 trial's maximum relative edge error
`2.235040e-6`, exact holds, 87 shared vertices, 120 triangles and one connected
component. All 7,140 triangle pairs pass the crossing check, and inherited
layer orders are not reversed. Cost falls another **3.406240e-10** from the
refused trial. Its separate changes are:

| Contribution | Change caused by the repair |
| --- | ---: |
| Crease preferences | 0 |
| Panel bending | +3.971641e-13 |
| Material lengths | −6.244550e-13 |
| Contact | −3.403967e-10 |

Relative to the fresh direction's start, the repaired larger trial lowers cost
**0.057976%**, compared with 0.029073% for the saved passing half-sized trial.
This gain comes from retaining the larger material correction; the repair
itself is minute. Main trial movement is `7.110663e-6` sheet lengths, or
**0.004266 drawing pixels** at the 600-pixel scale. The repair adds only about
`1.8e-9` drawing pixels. Body depth is unchanged by repair at exported precision.
A geometric intersection segment remains inside the existing tolerance. This
is not exact separation, a visible body opening or an equilibrium: the saved
full material proposal remains about 9,102 times above the movement limit.

The new source reader validates the fresh material rows, contact guards and
recorded forces without solving the quadratic again. Their sum with material
and damping forces must satisfy the original force-balance limit. It replays
all 31 saved fractions and remeasures their geometry/cost decisions; previous
readers validate the source repair and older controls. The shared gallery
calculation now accepts either source archive. The previous repair's **810
assets and HTML regenerate byte-for-byte unchanged**, and all **1,035** fresh
source assets remain unchanged. An altered contact multiplier fails the new
force-balance check before any output is written. Independent calculations
verify all four states, separate costs, all-pair contact, 4,944 exported face
orders, plane derivatives,
raw/installed movement and both sets of twelve overlap guards. This opt-in
experiment adds no material solve to the default test suite. All 1,878 tests
pass in 172.5 seconds after a warning-free cold build. Formatting, HLint 3.10
(including the CI JSON command), study JavaScript and inline-script checks pass.
All six gallery views load without browser errors.

Two consecutive examples now show that one repair can retain a larger trial
after a fresh direction is computed. The next useful experiment is a **bounded
loop of up to ten material corrections**, allowing at most one plane restoration
per trial before further halving. Keep the same material/holds, refreshed
pair/plane guards, original 31 fractions and actual geometry/cost checks.
Only install a verified passing candidate; stop or retain diagnostics when a
direction, repair or all-pair check fails. Record every restoration separately
and retain the full-proposal equilibrium test. This would test sustained
progress without interpreting numerical trials as a checked flexible motion.
It has not been run here, and no whole-crane opening is claimed.
