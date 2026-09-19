# More iterations at the same length weight

The [outer-strip experiment](outer-strip-refinement.md) left two endpoints
unfinished. Their final local quadratic solves converged and their full
proposed steps were accepted, but all 40 iterations at length weight `1e10`
were used. Continue those stored shapes without changing the problem:

```bash
stack run senbazuru-material-study -- --outer-continuation \
  build/fold-material/outer-strip build/fold-material
```

Open `outer-continuation.html` on the study server. The source directory must
contain the original `checks.json` and both selected `-after.fold` files.
The gallery verifies each saved run's material identities, held points,
springs, measurements and six-stage policy before either solver runs. It
copies the source report and selected FOLDs byte-for-byte into a separate
output directory. The original 40-iteration results are never relabeled.

A saved shape supplies starting positions, not a new rest shape. The unfolded
material still defines edge lengths, and the original fixture supplies the
held points and preferred crease/bending angles. See the
[glossary](../glossary.md) for these paper terms. Both continuations allow up
to 40 more iterations at `1e10`, with progressive contact exchange, unchanged
contact policy and the original acceptance caps. Feasibility checking on
restart changes no vertex in either case.

| Case | Additional iterations | Last full proposed movement | Result |
| --- | ---: | ---: | --- |
| Rest-only, fractional upper band | 2 | 8.80646e-8 | Converged; all endpoint checks pass |
| Outer-only, original band, contact off | 15 | 9.33112e-8 | Converged; still crosses |

Both fall below the original `1e-7` movement threshold. The final iteration
checks the proposed step without taking it: there is one accepted new step
in the first case, fourteen in the second. Total iteration counts become
118 and 166, with 42 and 55 at the final weight. No stopping tolerance was
loosened, and neither restart adds a new long CI test. These two solves took
about 1.03 local CPU seconds in total; this is one run, not a performance
benchmark.

| Measurement | Rest-only: original → continued | Contact-off: original → continued |
| --- | ---: | ---: |
| Maximum separation | 0.0043364545 → 0.0043365252 | 0.0019615383 → 0.0019614774 |
| Minimum signed gap | 0 → 0 | −0.0013542167 → −0.0013542077 |
| Largest vertex displacement | 1.03711e-7 | 2.76636e-7 |
| Maximum relative edge error | 1.0436239e-6 → 1.0437116e-6 | 9.8192673e-7 → 9.8190559e-7 |

Distances use the original sheet's side length as one unit. The held points
and shared crease identities remain exact, original crease error is about
`2.45e-16` radians, and the independent whole-sheet contact check passes only
the contact-enabled case. A converged contact-off result remains diagnostic:
settling a problem that permits crossing does not remove the crossing.

The total energy decreases by about `2.81e-11` and `9.06e-10`, respectively.
Keep the components separate: for rest-only, imposed-band energy rises by
`4.17e-7` while passive bending and length costs fall. For contact-off, upper
passive energy falls by `1.40e-6` while imposed and length costs rise. The
original crease cost is unchanged. The gallery uses half the weighted sum
of squared errors; its total is half the solver's line-search objective.
Small net changes can hide exchanges between larger component costs.

The two unfinished statuses were resolved by more iterations at the same
weight, with negligible shape changes. That removes the convergence blocker
for the fractional rest-only endpoint; it does not establish agreement
between meshes, a global energy minimum, a calibrated paper model or a
continuously checked folding route. The existing four-mesh study remains a
record of its original budget.

Independent calculations from six exported FOLD states reproduce material
cells, holds, shared vertices, edge lengths, signed angles, all 810 spring
records, separate energies and restart displacements. Exact rational triangle
clipping reproduces all six gap extrema and 9,600 fixed-location samples.
All 18 SVGs parse and all six GLBs have valid containers. Every one of the
403 archived source files retains its original hash. The browser exercises
both cases, all six state selections, a missing-endpoint control and the
connected-paper viewer.
Four fast archive-policy, refusal, strained-restart and measurement-binding
tests cover the new boundary; the expensive solves remain opt-in. Command-line
controls also refuse changed policies or measurements before either solve.
The cold warning-free build and all 1,512 tests pass (390.9 seconds for the
suite), with formatting, HLint 3.10 and JavaScript checks clean.

The next material question is the matched-hold passive-energy change: refining
the rest of the panel changed it by about 8.99%, even without the extra outer
bend. Compare those costs by material region using the saved four-mesh
endpoints before adding another solve. Performance work stays in #208;
`4×2`, default bending-rule changes, and the material/illustration acceptance
decisions remain separate.
