# Geometry checks stop the body correction at a boundary

The [saved-direction replay](body-correction-replay.md) found one shortened
correction that lowered cost and passed the existing geometry checks. Could
later corrections keep doing that? [#327](https://github.com/avalonalex/senbazuru/issues/327)
resumes the same saved step-1 shape for **at most forty corrections**, with both
gates on every accepted candidate. The result is **seven tiny moves, followed
by a blocked search**. Keeping the geometry checks works; this direction does
not produce sustained opening. See the [glossary](../glossary.md) for material
coordinates, panels, contact and layers.

```bash
stack run senbazuru-material-study -- --body-geometry build/fold-material/body-subdivision build/fold-material
```

Only candidate acceptance changes. The 87 vertices, 120 triangles, original
material, three exact holds, angular preferences, contact orders, length weight
`1e8`, contact multiplier `100` and search fractions `1, 1/2, …, 2^-30` stay the
same. The gate requires one connected sheet, unchanged material identities,
exact holds, relative edge error at most `1e-5` and passing crossing/order
checks at `1e-7` sheet units. Original crease angles remain soft preferences.
The original forty-correction archive and quarter-step remain controls, copied
without rerunning them. The new counter starts at zero for saved step 1.

The first full proposal matches the archive and selects **1/64**, reproducing
the replay. After that, the useful fraction shrinks rapidly:

| Correction | Accepted fraction | Installed movement | Full proposed movement | Cost decrease |
| --- | ---: | ---: | ---: | ---: |
| 1 | 1/64 | 1.82350e-5 | 1.16704e-3 | 2.34597e-5 |
| 2 | 1/256 | 4.47375e-6 | 1.14528e-3 | 5.70997e-6 |
| 3 | 1/2048 | 5.56582e-7 | 1.13988e-3 | 7.09177e-7 |
| 4 | 1/65536 | 1.73829e-8 | 1.13921e-3 | 2.21445e-8 |
| 5 | 1/131072 | 8.69130e-9 | 1.13919e-3 | 1.10720e-8 |
| 6 | 1/262144 | 4.34561e-9 | 1.13918e-3 | 5.53590e-9 |
| 7 | 1/134217728 | 8.48748e-12 | 1.13917e-3 | 1.08131e-11 |
| 8 | None; all 31 refused | 0 | 1.13917e-3 | 0 |

All eight linear solves pass their residual check. There are **134 refused
trials: 16 fail cost descent and 118 fail geometry**. The last search retains
the seventh accepted shape and stops, leaving the unused iteration budget
alone. Its full proposed movement is still about **11,392 times** the `1e-7`
equilibrium limit. Applied movements below that limit from correction 4
onward therefore cannot certify convergence.

Pair **22–63** blocks the last descending trials. Its two triangle planes
still straddle each other; the common intersection segment is the quantity
reaching the reporting threshold. Independently calculated segment lengths
are `9.99996935e-8` in the retained shape and `1.00000223e-7` in the smallest
refused trial (`2^-30`). These near-threshold numbers describe numerical
classification, not a resolved physical clearance. Passing the unchanged
checks still permits smaller mathematical intersections. Adding more halvings
would chase this threshold rather than establish useful progress.

Every returned shape passes the independent geometry checks. At the endpoint,
maximum relative edge error is `1.63680e-6`, with no reported crossings or
reversed orders. Total cost falls **0.226368%**:

| Cost | Saved start | Last retained shape |
| --- | ---: | ---: |
| Original creases | 0.0119860962 | 0.0119682881 |
| Panel bending | 0.0012138010 | 0.0012017776 |
| Length penalty | 0.0000158921 | 0.0000158226 |
| Contact penalty | 0.000000592825 | 0.000000576159 |
| Total | 0.0132163821 | 0.0131864645 |

These costs use half the solver's squared-residual objective, with identical
ordering. Maximum movement from the start is `2.32958e-5` sheet units: at most
**0.01398 pixels** at the gallery's 600 pixels per sheet unit, before projection.
Body depth changes from `0.03619204` to `0.03619281`. The free neck and tail
attachment landmarks move `3.33662e-6` and `6.17948e-6` respectively; the centre
and two wing holds stay exact. The largest crease-angle change is about
`0.028663°`. There is no meaningful visual opening gain or accepted settled
endpoint. This free-boundary specimen still excludes the surrounding crane's
loads, and no continuous flexible path or pressure response is certified.

The opt-in solver entry point checks the held starting shape, then uses the
existing line search with an additional geometry refusal. Ordinary entry points
keep their acceptance behavior. Small CI fixtures verify unchanged behavior
with a passing gate, refusal of a bad held start, successful backtracking with
unchanged full-proposal convergence, and stopping without installing refused
paper. The body solve stays outside CI. The gallery retains ten FOLD states,
all proposals/refusals, separate costs, angles, attachment positions, actual-size
views and three matched close-ups. Independent calculations reproduce all
exported measurements, every trial's cost and rejection, and all retained
crossing checks; the source archive's hashes remain unchanged.

Next, compare **one contact-aware correction direction at the blocked shape**
with this saved proposal, beginning with pair 22–63. That means asking the
correction calculation to respect the limiting separation before shortening
its result. Keep the same final geometry checks and report failure if the new
direction cannot descend. This small direction experiment is more informative
than a longer run of the unchanged search. The artistic target remains a
plausible coupled body opening: energy calibration and refinement convergence
stay deferred unless they change the drawing or make its controls unreliable.
