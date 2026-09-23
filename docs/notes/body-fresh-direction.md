# A fresh direction after contact repair still takes a tiny step

[The preceding repair](body-contact-restoration.md) makes the saved 1/128
trial pass geometry. From those repaired vertices, **one fresh material
direction selects 1/256**, lowering actual cost by **0.029073%**. Its next larger
fraction, 1/128, again crosses at triangles 46–70. Repair permits another small
correction; it does not remove the finite-motion limit or settle the body.
[#351](https://github.com/avalonalex/senbazuru/issues/351) tracks this experiment
under [#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).
See [the glossary](../glossary.md) for material coordinates, panels and contact.

```bash
stack run senbazuru-material-study -- --body-fresh build/fold-material/body-restoration build/fold-material
```

A direction says how to move every free vertex to improve the material cost.
Here it comes from a quadratic: a sum of squared local predictions of length,
crease-angle, panel-bending and contact errors. Rebuild those predictions at the
saved repaired state, together with the twelve overlap-corner guards for pairs
22–63, 14–55 and 46–70 and the vertex 27–plane 70 guard. The latter plane extends
beyond the finite triangle; it remains an explicit conservative rule for this
specimen. Each guard retains its `min(0, starting value)` floor rule, evaluated
at the repaired start. It limits predicted worsening, not actual finite motion.

Keep length weight `1e8`, contact weight `1e10`, damping `1e-3`, the original
100-iteration quadratic budget, and every material preference and exact hold.
One quadratic is solved, with no new restoration or continuation. Its full
proposal and thirty halvings are separate trials from the same repaired start.
Only a verified direction may select a trial, and that trial must lower actual
cost while passing all-pair contact, material validity, exact holds and the
`1e-5` relative length limit. The contact tolerance stays `1e-7` sheet lengths.

The quadratic verifies in four iterations, with three active guards: one
overlap corner of 22–63, one of 14–55, and the plane guard. Its stationarity
residual (the remaining imbalance of objective and guard forces) is about
`1.22e-8`, below the unchanged `1e-6` cap. The largest inequality violation is
about `3.08e-20`, below `1e-12`. This verifies the local approximation, not the
full proposed shape.

| State | Plane margin above −1e-7, ×1e-12 | Geometry | Actual total cost |
| --- | ---: | --- | ---: |
| Saved repaired start | +1.163196 | Pass | 0.012967223114007682 |
| Fresh direction at 1/128 | −3.308665 | Fail: 46–70 | 0.012959705575584384 |
| Fresh direction at 1/256 | +0.045232 | Pass | 0.012963453167721534 |

These plane margins use independent 60-digit arithmetic on the exported
coordinates. The linear prediction preserves the starting distance, while the
finite 1/256 trial loses about `1.118e-12` sheet lengths of distance. The larger
trial loses about four times as much. This is consistent with the nonlinear
loss seen in [the earlier distance accounting](body-plane-loss.md); this study
does not repeat that decomposition. The actual overlap gap improves at both
fractions. All-pair geometry still rejects 1/128 because vertex 27 crosses the
plane threshold outside triangle 70's projected outline.

At the selected trial, the sheet retains 87 shared vertices, 120 triangles and
one connected component. All 7,140 triangle pairs pass the unchanged crossing
check, inherited layer orders are not reversed, and hold error is exactly zero.
The largest relative material-edge error falls from `2.247410e-6` to
`2.239876e-6`. Separate costs show what improves and what is traded:

| Cost contribution | Repaired start | Selected 1/256 | Change |
| --- | ---: | ---: | ---: |
| Crease preferences | 0.0118226627213 | 0.0118200900219 | −2.572699e-6 |
| Panel bending | 0.0011216568212 | 0.0011204579913 | −1.198830e-6 |
| Material lengths | 0.0000194029246 | 0.0000194225577 | +1.963317e-8 |
| Contact | 0.0000035006469 | 0.0000034825968 | −1.805011e-8 |

A smaller worst edge error can accompany a larger total length penalty: the
penalty adds squared errors over every edge. Total cost falls `3.769946e-6`.
Body depth increases only `1.590556e-7` sheet lengths. The maximum selected
movement is `3.555332e-6` sheet lengths, or **0.002133 drawing pixels** at the
existing 600-pixel scale. Full proposed movement remains `9.101649e-4`, about
**9,102 times above** the equilibrium limit. This is numerical progress with
no visible new opening. A geometric intersection segment still exists inside
the contact tolerance; a passing report does not mean exact separation.

The source reader checks the saved repair against its raw correction, original
and refreshed guards, four saved states, material identities and separate costs.
It delegates both preceding directions and all 372 earlier trial fractions to
the existing archive readers. All 810 source assets remain byte-identical.
Independent calculations recheck all 32 new states, material lengths and costs,
all-pair crossings, 39,556 exported face orders, the plane gradient and the
quadratic force balance. All 192 SVGs parse; six shared views compare the saved
start with the selected or diagnostic fractions. This opt-in calculation adds
no material solve to the default test suite. All 1,878 tests pass in 164.4
seconds after a warning-free cold build; formatting, HLint 3.10 (including the
CI JSON command), study JavaScript checks and the new inline script are clean.
All 31 fraction controls and six views work in the browser without errors.
An altered saved raw correction is refused before any output is written.

[The follow-up](body-fresh-restoration.md) now applies **one restoration at the
fresh refused 1/128 trial**, using this direction's repaired start as the
plane-distance target. It passes retained/refreshed guards and actual geometry
and cost again. This establishes a second successful repair after rebuilding
the material direction; a bounded correction loop is the next experiment.
This patch still supplies neither settled inflation nor a certified flexible
route or whole-crane deformation.
