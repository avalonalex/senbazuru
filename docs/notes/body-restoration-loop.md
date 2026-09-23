# Ten material corrections with one repair per trial

Starting from [the saved fresh repair](body-fresh-restoration.md), all **ten**
material corrections retain a shape passing the unchanged geometry and cost
checks. Three selected candidates needed a contact repair. Total cost falls
**1.720266%**, but net movement is only **0.165283 drawing pixels** at 600 pixels
per sheet length. The run exhausts its ten-correction budget; the last full
proposal remains **5,326 times** above the equilibrium movement limit.
[#356](https://github.com/avalonalex/senbazuru/issues/356) tracks this experiment
under [#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269). See
[the glossary](../glossary.md) for material coordinates, panels and contact.

```bash
stack run senbazuru-material-study -- --body-restoration-loop build/fold-material/body-fresh-restoration build/fold-material
```

A material direction is a proposed movement of every free vertex, computed
from a local approximation to the squared material errors. Rebuild that
approximation at each retained shape, together with the twelve overlap guards
for pairs 22–63, 14–55 and 46–70, and the vertex 27–plane 70 guard. Keep the same
100-iteration quadratic budget, damping `1e-3`, exact holds, length weight `1e8`
and contact weight `1e10`. A verified quadratic is required before searching
its full proposal and up to thirty halvings.

For each fraction, try the original candidate first. If it fails and has lost
plane distance, permit one minimum-squared-movement repair targeting that
**direction's starting distance**, with held coordinates excluded. The repaired
candidate must pass the original thirteen guards, the twelve overlap guards
refreshed at the refused shape, and its restoration-plane equation. A changed
list of overlap vertices prevents this repair; it does not license guessing
which old guard corresponds to a new corner. Failed repairs lead to the next
fraction of the original proposal, never another repair of the repaired trial.

Both original and repaired candidates must pass actual all-pair contact,
material connectivity, exact holds, relative length error `1e-5`, and strict
total-cost descent from the current retained shape. The contact tolerance stays
`1e-7` and linear guard residual stays `1e-12`. Tiny selected fractions or
repairs never replace the full-proposal equilibrium test. These are numerical
corrections, not a continuously checked motion through folded states.

| Correction | Selected fraction | Repair movement, sheet lengths | Total cost after |
| --- | ---: | ---: | ---: |
| Start | — | — | 0.012959705235 |
| 1 | 1/128 | 2.883513e-12 | 0.012952315100 |
| 2 | 1/128 | 2.796055e-12 | 0.012945050630 |
| 3 | 1/256 | None | 0.012941469820 |
| 4 | 1/4 | 2.734208e-9 | 0.012768613307 |
| 5 | 1/8,388,608 | None | 0.012768613240 |
| 6 | 1/32,768 | None | 0.012768611360 |
| 7 | 1/32 | None | 0.012752773922 |
| 8 | 1/64 | None | 0.012745243703 |
| 9 | 1/64 | None | 0.012740340282 |
| 10 | 1/128 | None | 0.012736763811 |

The first two repairs behave like the earlier isolated examples. In correction
three, the next larger trial changes the overlap vertices, so its repair is
refused. Correction four permits a much larger 1/4 fraction after one repair;
its next larger 1/2 fails both material lengths and other triangle contacts
even after repair. Recovering one plane distance does not fix every contact.

Progress then slows sharply. Correction five's next larger fraction crosses
48–92 and increases cost; correction six's next larger fraction passes geometry
but increases cost. Later directions regain larger usable fractions. In the
last correction, **1/64 lowers cost but crosses 55–93**. Vertex 27 has not lost
its target plane distance there, so this particular repair cannot help. The
unmodified 1/128 passes. The experiment saves these refusals, rather than
extending the named-pair policy to make them disappear.

| Measured quantity | Start | Last retained shape |
| --- | ---: | ---: |
| Crease preference cost | 0.011817518477 | 0.011621582109 |
| Panel bending cost | 0.001119271500 | 0.001061594437 |
| Length penalty | 0.000019450315 | 0.000047886349 |
| Contact penalty | 0.000003464943 | 0.000005700916 |
| Maximum relative edge error | 2.235040e-6 | 6.380501e-6 |
| Body depth, sheet lengths | 0.036201401889 | 0.036235262957 |

Bending costs decrease while length and contact penalties increase. The latter
remain within the unchanged acceptance limits; reduced total cost is not a
claim that every contribution improves. All retained states have 87 shared
vertices, 120 triangles, one component, exact holds, no reversed inherited
orders and no crossing above tolerance among 7,140 pairs. Body depth increases
only `3.386107e-5` sheet lengths, or **0.020317 drawing pixels**. A geometric
intersection segment at 46–70 remains within tolerance; this is neither exact
separation nor settled crane inflation.

The archive reader shares the earlier repair checks without changing them,
then authenticates the fresh repaired coordinates and their source chain.
The gallery records every visited raw fraction and repair separately from the
retained chain; the original 31-fraction budget is unchanged, and search stops
at its first passing candidate. Its six views share camera, scale and fixed
contact crops. Fast search-policy tests exercise one-repair limits, errors,
selection order and exhaustion without adding a material solve to default CI.

Independent calculations verify **137 exported states**: 96 visited original
trials, 30 repairs and 11 retained states including the start. They remeasure
separate energies, material lengths, exact holds, all-pair contact, source
orders and body depth; check the ten quadratic force balances and selected
fractions; and verify plane derivatives with 60-digit arithmetic and overlap
derivatives by finite differences. The largest overlap-derivative discrepancy
is `2.78e-10`. All **169,217 exported face orders** preserve material ownership
and winding. All **1,064 source assets** are unchanged, and changing one saved
repaired coordinate is rejected before an output directory is created.
The six gallery views load for all ten corrections without browser errors.
All **1,883 tests pass in 179.4 seconds** after a warning-free cold build;
Ormolu 0.7.2.0, HLint 3.10 (including the CI JSON command), study JavaScript
and inline-script syntax checks pass.

The next bounded study should **inspect 55–93 in the last saved 1/64 refusal,
without new solves**. Compare the signed plane distances, projected overlap,
material ownership and contact derivatives with the passing 1/128 and its
starting state. This identifies whether the next limitation needs another
local guard or a different contact policy before committing to either. The
surrounding crane's loads and a checked flexible route remain outside this
body-patch experiment.
