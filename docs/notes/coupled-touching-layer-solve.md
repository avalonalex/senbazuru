# Solve the shared movement of touching layers

The [folded diamond](two-held-paper-layers.md) has two distinct material points
at each touching location, except on its shared root crease. Moving both
points up by the same amount does not change their separation. The solver
must distinguish that easy shared movement from pushing the upper point
through the lower one.

The original solve rescaled each coordinate independently before applying
conjugate gradients, an iterative method for solving the linear equations of
one numerical correction. At the final penalty stage, contact has weight
`1e10`, material lengths `1e8`, and panel bending uses illustrative stiffness
`0.2`. These large differences make some motions much harder to compute than
others. Independent rescaling cannot describe the shared movement of two
layers. The 16-division bend failed to establish linear convergence after
about 701 CPU seconds, despite small length error and passing endpoint contact.

`SparseSolve` now builds a coupled preconditioner for the held-contact mode.
A preconditioner supplies an easier system whose solution helps choose the
next search direction. Here it factors the same linear equations into two
triangular parts and a diagonal part, called `L D L^T`. Triangular means that
each unknown can be recovered in order once the previous ones are known.
The implementation first eliminates an unknown with the fewest remaining
connections, limiting the new matrix entries created during elimination.
It uses the existing damping, a small movement cost that gives otherwise
unconstrained corrections a unique answer. Exact held vertices are removed
before any matrix is built. This is a full sparse factor, not a new material
force, an equality gluing the layers, or a change to the contact tolerance.
A failed factor falls back to the earlier diagonal preconditioner.

Floating-point factorization is approximate. Before accepting an inner solve,
the code recomputes its residual—the difference between the requested and
achieved right-hand sides—using the original gradient rows. If the recursively
updated residual looked small but that direct check fails, the iteration
restarts from the direct residual within the same work limit. The absolute
residual floor remains `1e-6`, with relative tolerance `1e-8`. The outer
elastic solve still requires a full proposed movement at most `1e-7` sheet
units, in addition to its material-length and contact checks. A tiny movement
after shortening a rejected step cannot establish equilibrium. See
[Netlib's Templates](https://www.netlib.org/templates/templates.html) for
background on preconditioning and iterative residual tests.

Run `stack run senbazuru-material-study -- --wing-layers build/fold-material`.
The compiled 40-degree controls produced these measurements on 2026-09-13,
with the same held regions and grip placement at every resolution:

| Divisions | Triangles | Relative edge error | Panel energy | CPU seconds |
| --- | --- | --- | --- | --- |
| 8 | 128 | 2.11e-8 | 0.0352917 | 0.83 |
| 16 | 512 | 5.89e-8 | 0.0366799 | 6.75 |
| 24 | 1,152 | 9.29e-8 | 0.0372966 | 35.71 |

All three converge and pass the independent contact check over every triangle
pair. Held-point error is exactly zero; the original root angle stays within
`1e-12` radians of 180 degrees. Their final original-system linear residuals
are `7.71e-10`, `1.03e-8` and `1.23e-7`, all below `1e-6`; full proposed
movements are below `3.2e-8`. The finer solve consumes eleven outer iterations
instead of exhausting the old run's 212. This is one machine's comparison,
not a runtime guarantee.

At the 81 material points common to each pair of grids, the largest position
change drops from `0.001345` sheet units (8 to 16) to `0.000418` (16 to 24).
Relative energy changes drop from 3.93% to 1.68%. The two material halves
remain separate in this comparison; they happen to settle to nearly identical
positions, within `1e-13` sheet units. This agrees with the single-layer
experiment's shape and approximately doubles its energy. It is evidence of
improving mesh agreement, not proof of a continuum limit or calibrated paper
physics. The gallery publishes these comparisons and the final equilibrium
reports in `checks.json`.

The initially penetrating guess still corrects to a passing endpoint. Lifting
only the upper grip still opens a real gap. Holding it underneath the lower
grip still fails, even though that control's inner linear solve succeeds:
solving a correction equation does not make incompatible constraints feasible.
No material identities, contact weights, clearance, grip targets or stopping
tolerances changed. Sparse factors can gain many entries on larger meshes;
this study implementation is not a bounded-memory general-purpose solver.

The next bounded experiment under [#195](https://github.com/avalonalex/senbazuru/issues/195)
is to spread one wing of the existing connected crane and measure which
body regions must move for a compatible static shape. Preserve the original
creases and tail/body orders. Flexible motion, friction and finite-thickness mechanics remain
separate: these numerical correction paths can still stretch or cross paper.
