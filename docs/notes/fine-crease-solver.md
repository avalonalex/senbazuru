# Two different reasons for a stalled fine-mesh solve

The [refinement study](unequal-crease-refinement.md) found two failures on the
same 128-triangle sheet. Its matched and contact-off controls nearly stopped
moving, but missed the relative edge-length cap. The upper bend preference
stopped earlier, with a failed constrained step. Changing both controls at
once would hide which failure each change addresses.

```bash
stack run senbazuru-material-study -- --fine-crease build/fold-material
```

Keep length × width `4×1`, the original held material strips and edges, and
the same upper bend springs. Compare four numerical policies on matched,
upper-preference and contact-off controls. The original stages use length
weights `1e2`, `1e4`, `1e6`, `1e8`; the stronger policy adds `1e9`. These
weights multiply squared absolute edge-length errors. They do not change
the final relative length cap `1e-5`, crease cap `1e-5` radians, held positions
or contact checks. Intermediate stages may retain length error; the final
one must meet the cap as well as the existing movement/convergence tests.

For the matched case, the extra stage reduces relative length error from
`1.043e-5` to `1.191e-6` and gives a passing endpoint. The contact-off control
also converges below the length cap, but still crosses its partner. More
penalty resolves this particular length failure; it cannot replace contact.
A separate probe ending at `1e10` reduces the matched error to `1.443e-7`,
but the weaker `1e9` endpoint already meets the original requirement.

The failed contact step has a different cause. Its working set is the small
selection of inequalities currently treated as touching equalities. A new
row almost parallel to this set cannot safely be added to its dense matrix,
yet it can require a slightly stricter separation. The original method skips
adding that row, then refuses convergence because it still checks every
inequality. On the recorded upper-preference endpoint, row 143 is violated
by `5.423e-12` while the nearly parallel row 144 is in the working set.
The permitted inner residual is `1e-12`; neither the physical nor numerical
threshold should be enlarged to hide this discrepancy.

A small example makes the distinction visible without paper geometry.
Minimize `(x+1)^2 + (y+2)^2 + x^2 + y^2` subject to `x >= 0` and
`x + 1e-7*y >= 0`. Selecting only the first contact gives `(0,-1)`, which
violates the second by `1e-7`. Replacing the first with the second gives
approximately `(1e-7,-0.99999995)` and satisfies both. The almost parallel
rows need not be imposed simultaneously as equalities to obey both inequalities.

The opt-in exchange method tries replacing one selected equality with a
violated contact when the original iteration stalls. It accepts a candidate
only when all original gap inequalities pass and the contact forces are
nonnegative; the ordinary next iteration also checks force balance and
complementarity (a separated contact must exert no force). No inequality is
removed from validation. If no single exchange passes, the solver still
reports failure. The work remains bounded by the original iteration budget.

Replaying the same stored fine-mesh endpoint reduces maximum inequality
violation from `5.423e-12` to `3.176e-18` with six selected constraints and
one additional iteration. Complementarity is `8.274e-18`; force balance is
`8.396e-10`, within its unchanged `1e-6` cap. `contact-step.json` saves the
66 free vertex ids, 390 material rows, 194 contact rows and both reports.
These are measurements of a linearized numerical step, not physical forces.

The complete upper-preference solves on 2026-09-15 show why both changes matter:

| Policy | Relative edge error | Maximum gap | Accepted endpoint |
| --- | ---: | ---: | --- |
| Original | 9.026e-4 | 0.004421 | No: inner contact solve fails |
| Extra length stage only | 9.026e-4 | 0.004421 | No: inner contact solve still fails |
| Contact exchange only | 2.477e-5 | 0.005591 | No: length cap fails |
| Both | 3.961e-6 | 0.005510 | Yes |

Distances are fractions of the unit sheet's side. The combined endpoint also
passes material identity, original crease angle, exact holds, nonnegative
stored-coordinate gaps and the independent whole-sheet contact check. Every
recorded contact-enabled iterate retains nonnegative exact gaps and every
accepted update decreases that stage's material energy after repair. A stage
change changes the objective, so energy is not compared across stages.

The old entry points retain their original policies so earlier measurements
remain reproducible. This new comparison is an opt-in study, not a general
solver upgrade. It handles a single contact exchange, assumes known order
along z and does not certify motion between endpoints. The follow-up
[combined refinement](combined-crease-refinement.md) reruns the length/width
grid with this policy on every mesh. Comparing a stronger-penalty fine mesh
directly with an older coarse mesh would change two things at once; this
passing endpoint alone does not establish shape convergence or calibrated
paper mechanics.
