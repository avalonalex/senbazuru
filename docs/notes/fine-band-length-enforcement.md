# A small correction is not an exact length constraint

The [fixed-band experiment](distributed-bend-preference.md) leaves the `4×1`
and `4×2` contact-off controls just outside the relative edge-length cap.
These are the two fine meshes, with 128 and 256 triangles. Disabling contact
removes its forces and separation repairs; it does not remove the independent
checks that report crossing. Generate this isolated comparison with:

```bash
stack run senbazuru-material-study -- --band-length build/fold-material
```

The length term in the objective is `weight * sum (current - original)²`,
using every unique triangle edge. The original lengths come from coordinates
on the unfolded sheet. This is a penalty: changing a length costs something,
but is not mathematically forbidden. The angular springs asking the panels
to bend compete with that cost. These illustrative weights are numerical
controls, not measured elastic properties of real paper.

Acceptance asks a different question: is every `abs(current / original - 1)`
at most `1e-5`? For the worst edge on `4×1`, vertices 93–96, the original
length is `0.03125` and the current length is `0.031250351095576`. An absolute
extension of about `3.51e-7` sheet lengths is a relative error of `1.124e-5`,
just above the cap. A small absolute error is not automatically a small
relative error on a short edge. The worst `4×2` edge is 155–160, also of
original length `0.03125`, with relative error `1.104e-5`.

Both failed solves finish at weight `1e9`. Their last inner force residuals
are below `3e-15`; their full proposed movements are `3.666e-9` and `1.219e-9`
sheet lengths, well below the `1e-7` movement threshold. The final energy
search finds no decrease. The length gate correctly refuses convergence:
a small proposed move alone would accept these errors.

Restart each exact failed endpoint, preserving its holds and bending
preferences. At the same weight, both restarts stop after one attempted
correction with exactly unchanged coordinates. A fresh forty-iteration
budget therefore does not address this stall. Increasing only the weight
to `1e10` changes the objective enough to move both cases below the same
length cap. On 2026-09-16 the isolated restarts give:

| Mesh | Restart weight | Iterations | Relative edge error | Minimum exact gap | Numerically converged |
| --- | ---: | ---: | ---: | ---: | --- |
| 4×1 | 1e9 | 1 | 1.124e-5 | -0.002232 | No |
| 4×1 | 1e10 | 12 | 2.271e-6 | -0.001642 | Yes |
| 4×2 | 1e9 | 1 | 1.104e-5 | -0.002089 | No |
| 4×2 | 1e10 | 11 | 2.289e-6 | -0.001811 | Yes |

A negative gap means the upper panel crosses through the lower one. Stronger
length enforcement reduces that crossing but does not eliminate it. Contact
remains disabled, so neither numerically converged endpoint is accepted as
valid paper. Exact holds and material identities survive, and the original
closed-crease angles remain within their unchanged tolerance.

The page also compares complete solves from the original seed, with schedules
through `1e9` and through `1e10`, plus matched-hold references at each width.
It retains the original failures. Its replay table always refers to the
original failed contact-off endpoint at the selected width, regardless of
the control or stage displayed above it. Downloadable replay JSON records
source and final coordinates, every edge's lengths, complete step histories
and independent endpoint measurements. Numerical corrections are not a
physical folding sequence.

The complete stronger schedules finish in 78 and 83 iterations, with relative
edge errors `2.271e-6` and `2.289e-6`. Their coordinates differ from the
isolated stronger restarts by at most `1.334e-10` and `1.756e-12` sheet lengths.
Only the final stage requires the length cap as well as small movement;
appending a stage lets the preceding `1e9` stage finish sooner. This explains
why a stronger complete solve can use fewer total iterations than the failed
baseline. The fresh-endpoint restarts above isolate extra work without that
change in stage stopping.

Stronger enforcement changes matching positions by at most `0.0005185` and
`0.0006706` from the old band endpoints. Both matched-hold references still
pass every independent check, with edge errors `1.443e-7` and `1.096e-7`.
All eight solves retain their exact holds, material and original crease
angles. Six converge numerically; only the four matched references are
accepted paper. Changing the weight changes the objective, so energies at
different weights are not a descent comparison. Every accepted correction
still reduces its own stage's objective.

Independent checks recompute every edge's original/current length and the
weighted final objective from the exported coordinates, retain the intended
order for every reported triangle overlap, and verify all 24 FOLD/GLB states
and 72 SVG plots. The twelve baseline FOLD states reproduce #236 apart from
comparison titles. Both restart vectors match a separate saved-endpoint
probe; all 24 browser selections show the corresponding measurements and
downloads. The long solves remain opt-in and add no default CI test workload.

This experiment does not change the solver, its default schedule, any
acceptance cap, or the physical controls. It tests a bounded stronger penalty;
it does not prove global optimality or provide an adaptive enforcement rule.
The next step is a full band grid with one common length/contact policy,
including the [progressive contact repair](several-contact-exchanges.md).
Only then compare length and width refinement again. Static checks remain
separate from mesh independence and a continuously checked flexible route.
