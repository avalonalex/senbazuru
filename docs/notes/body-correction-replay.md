# A smaller correction can preserve the geometry checks

The [contact diagnosis](body-contact-diagnosis.md) found three shallow crossings
in correction 2 of the refined body patch. Its saved full proposal lets us ask
one narrower question: can we shorten that same direction enough to lower cost
**and** keep the existing geometry checks? [#325](https://github.com/avalonalex/senbazuru/issues/325)
answers this without a new solve or a changed contact policy. See the
[glossary](../glossary.md) for material coordinates, layers and contact.

```bash
stack run senbazuru-material-study -- --body-replay build/fold-material/body-subdivision build/fold-material
```

For each vertex, the trial is `start + fraction * (fullProposal - start)`.
These are numerical candidates, not intermediate folding instructions: the
straight displacement can stretch or cross paper. We test the existing search
budget, `1, 1/2, …, 2^-30`, and retain the unchanged start and original quarter-step
as controls. All costs use the same length weight `1e8`, contact multiplier
`100`, material and angular preferences. The independent geometry gate keeps
one connected sheet, unchanged material identities, exact holds, relative edge
error at most `1e-5`, and crossing/contact/order checks at `1e-7` sheet units.
A cost gate requires strict total descent. Neither gate replaces convergence.

**The first fraction passing both gates is 1/64.** Its largest vertex movement
is `1.82350e-5` sheet units, sixteen times smaller than the original quarter-step.
At 600 pixels per sheet unit that is at most `0.01094` pixels before projection.
It lowers cost by `2.34597e-5`, or **0.177505%**. This leaves a descending
correction rather than an immediate stall, but does not establish useful
progress over a sequence of later corrections.

| Fraction | Largest movement | Maximum relative edge error | Reported crossings | Total cost | Both gates |
| --- | ---: | ---: | ---: | ---: | --- |
| Unchanged start | 0 | 1.62098e-6 | 0 | 0.01321638 | No descent |
| 1 | 1.16704e-3 | 1.49386e-4 | 14 | 355.6611 | Fail |
| 1/2 | 5.83522e-4 | 3.73497e-5 | 9 | 0.7295319 | Fail |
| 1/4 (original) | 2.91761e-4 | 9.34135e-6 | 3 | 0.01293612 | Fail |
| 1/8 | 1.45880e-4 | 2.34052e-6 | 2 | 0.01304250 | Fail |
| 1/16 | 7.29402e-5 | 1.67004e-6 | 2 | 0.01312503 | Fail |
| 1/32 | 3.64701e-5 | 1.64564e-6 | 1 | 0.01316986 | Fail |
| 1/64 | 1.82350e-5 | 1.63334e-6 | 0 | 0.01319292 | Pass |

Every smaller tested fraction also passes both gates (25 passing fractions in
all). Fractions 1 and 1/2 have twenty and eight reversed layer orders,
respectively; the rest have none. All candidates preserve the three exact
holds and the connected 87-vertex, 120-triangle material mesh.

The last reported crossing is pair **22–63** at 1/32, with intersection length
`3.62415e-6`; that pair has no intersection at 1/64. Pair 46–70 still has a
`1.24312e-6` mathematical intersection at 1/64. One triangle extends only
`8.91652e-8` through the other's plane, below the unchanged `1e-7` straddling
tolerance. Thus passing the checks does not mean exact separation. The gallery
shows all three original pairs in matched magnified crops; its full-sheet
views and measurements cover every candidate and all 7,140 triangle pairs.

Unlike the original quarter-step, the selected fraction lowers every separate
cost compared with the start:

| Cost | Start | Original 1/4 | First passing 1/64 |
| --- | ---: | ---: | ---: |
| Original creases | 0.01198610 | 0.01176675 | 0.01197215 |
| Panel bending | 0.001213801 | 0.001100864 | 0.001204355 |
| Length penalty | 0.0000158921 | 0.0000658625 | 0.0000158358 |
| Contact penalty | 0.000000592825 | 0.00000264617 | 0.000000580146 |

These totals use half the solver's squared-residual objective, preserving its
ordering. The original full and half-step refusals and quarter-step cost are
reproduced. The saved linear solve passed, but its **full** movement
`0.00116704` is still about 11,670 times the equilibrium limit `1e-7`.
Reducing the applied fraction cannot turn that into an equilibrium certificate.
There is no accepted opened endpoint or continuously checked flexible motion.

The shared archive reader validates source material, topology, metadata, exact
holds, fresh measurements and trace linkage before writing. It also checks
full-proposal holds and movement. Original bytes are copied alongside all 32
FOLD exports. Independent calculations reproduce edge and angular costs,
contact penalties, movement, holds, connectivity and crossings across all
228,480 candidate/pair combinations; source hashes are unchanged. A six-vertex
regression keeps the 1/32→1/64 crossing transition in CI without a new solve.

Next, try **one bounded continuation from the saved passing start with cost
and geometry gates on every accepted candidate**, keeping the original run
as its control. Record full proposals and every refusal; keep all weights,
constraints, tolerances and convergence tests. Determine whether later
corrections keep descending or stall at the geometry boundary. This replay
supports testing that policy on this specimen, not adopting it as a general
contact solution or claiming an inflated whole crane.
