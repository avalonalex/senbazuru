# The saved angle direction fails arithmetic, not its selected constraints

[#387](https://github.com/avalonalex/senbazuru/issues/387) audits the first
refused direction from [contact-aware angle construction](body-angle-contact.md).
That attempt never changed the body. Its archive contains fourteen numerical
unknowns: thirteen crease-angle increments in degrees and one increment of the
common error bound. It also contains all 1,204 inequalities and the twelve
constraints the optimizer selected as equalities. An inequality permits a
nonnegative gap; treating it as an equality means asking for exactly zero.

```bash
stack run senbazuru-material-study -- --body-angle-audit study/fold-material/fixtures/body-angle-linear.json build/fold-material
```

The checked-in snapshot preserves every original row in order, including
copies, plus the proposed direction, selected row ids, normalization scales
and force coefficients. The unused y/z coordinates were exactly zero and are
omitted. Its provenance records the original `checks.json` SHA256:
`90b62a6266d226e06919e2af6d310ebbbe843acc26ca057d2fb9b3a8b9552ba0`.
No body generation is needed to reproduce this audit.

**The saved selected system has a solution that passes every linear gate.**
Re-evaluating it with exact fractions changes the largest angle increment by
only `1.35125e-7°`. Even rounding that answer once to ordinary `Double`
floating-point numbers passes the unchanged checks. All original inequalities
participate, not just the selected twelve; no new constraint is selected.

| Check | Saved numbers, re-evaluated | Exact fractions | Once rounded to Double | Limit |
| --- | ---: | ---: | ---: | ---: |
| Largest inequality violation | `1.52945e-9` | 0 | `7.09474e-14` | `1e-12` |
| Complementarity | `1.52945e-9` | 0 | `7.09474e-14` | `1e-12` |
| Force balance | `6.94761e-17` | 0 | `1.60949e-17` | `1e-6` |
| Smallest original-row force coefficient | `7.13426e-8` | `7.13426e-8` | `7.13426e-8` | nonnegative |

Complementarity means a separated constraint must exert no force. Balance
compares the objective's force with the sum of constraint forces. These are
numerical optimization quantities, not bending forces measured on paper.
The saved report's `1.52955e-9` differs slightly from the table because it
sums normalized rows using `Double`; this audit evaluates the original rows
exactly. Both refuse the same direction.

Six original rows violate the `1e-12` inequality limit; all six are already
selected equalities. The worst is row **737**, `contact (11,16) corner 305`,
followed by row 853, `contact (17,20) corner 421`. Row ids count from zero in the
saved array; corner ids count the overlap witnesses, not paper vertices.
This is not evidence for another missing pair-specific guard. The exact
selected solution needs only positive force coefficients and satisfies all
unselected rows too.

`QuadraticAudit` converts each input `Double` to its exact binary fraction
using `toRational`; this does not recover precision absent from the saved
numbers. It solves the *same fixed equalities* using fraction arithmetic,
with the original quadratic objective and damping `1e-8`. The objective is
`(common + boundIncrement)^2 + damping * sum(increment^2)`. Eliminating the
fourteen increments leaves a twelve-by-twelve response matrix, describing
how forcing one selected constraint changes the others. Exact elimination
checks this matrix without a numerical rank threshold. All selected equalities
and force balance then hold exactly; this is not a rounded display of a
small residual. The once-rounded check rounds both the direction and the
original-row force coefficients and evaluates their residuals exactly again.

The response matrix, normalized with the saved scale factors, has an
**infinity-norm condition number of about 30.9 million**. This number measures
potential amplification of rounding error when solving the equations. It is
the product of the largest absolute row sum of the matrix and that of its
inverse. Some combinations of selected constraints respond almost alike,
so accurate cancellation matters. Row 737's response scale is about
4.37 million. The old method builds its answer from the constraint forces,
which can preserve excellent force balance while leaving selected equations
inaccurate. The audit locates that arithmetic failure; it does not distinguish
how much originates in factorization versus assembling the final direction.

The original method also stops when recalculating the selected system returns
the identical floating-point direction. With failed checks at iteration 34
of 200, this is its early-return branch. A larger iteration budget alone would
not change that calculation; the arithmetic needs attention before another
body attempt.

An independent 80-digit decimal calculation reproduces the direction change,
all row gaps, positive forces and condition number. Analytic controls retain
refusal for an unselected stricter inequality, a negative force, malformed
input and an exactly dependent selected system. The six audit tests, including
the complete frozen problem, take about 0.22 seconds locally. All 1,922 tests
pass after a warning-free cold build (422.6 seconds for the serial test run);
formatting, HLint 3.10, JavaScript checks and gallery inspection pass. The original
body archive is byte-for-byte unchanged. No new active-set search, body solve,
geometry trial, material correction or barrier solve runs.

The next bounded study should compare a more stable evaluation of this saved
selected system against the exact reference—for example, a direct constrained
factorization or a residual correction checked on the original rows. Keep the
objective, damping, constraints and tolerances fixed. First establish that the
numerical direction passes, then make a separate decision about another body
construction. This audit neither accepts the direction as paper nor certifies
its derivatives, a finite nonlinear step, or a folding route. The starting
body still intersects, and the matched barrier comparison remains blocked.
