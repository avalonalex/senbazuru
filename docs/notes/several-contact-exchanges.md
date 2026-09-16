# Repairing several weak contacts in one numerical step

The [band-loading experiment](distributed-bend-preference.md) leaves two
middle meshes unconverged even though their stored paper never crosses.
The failed quantity is a proposed numerical correction: its linear gap
inequalities are not all satisfied closely enough. A safe current shape and
a valid next correction are separate requirements. Generate the isolated
comparison with:

```bash
stack run senbazuru-material-study -- --band-contact build/fold-material
```

The working set is the small selection of contact inequalities treated as
touching equalities while solving for a correction. Some remaining rows are
too close to that set's span to add safely to its matrix. They can still ask
for stricter separation and must remain in validation. The
[single-exchange method](fine-crease-solver.md) replaces one selected equality
with a violated row, but accepts the replacement only if it fixes every gap.
Here several contacts need changing, so no one replacement qualifies.

A four-coordinate example makes that restriction visible. For each of two
independent pairs `(x, y)`, minimize `(x+1)² + (y+2)² + x² + y²` subject to
`x >= 0` and `x + 1e-7*y >= 0`. The last two squares represent damping, which
makes the proposed correction resist large movement. Selecting the first
contact in each pair gives `(0, -1)` twice: both stricter contacts are violated
by `1e-7`. Replacing either one improves that pair but leaves the other
violation unchanged. No single replacement fixes both, and even the largest
violation does not decrease after the first improvement.

The opt-in `ProgressiveContactExchange` method permits a sequence of
replacements. Each must strictly decrease the sum of squared negative gap
residuals, measured in the original rows' units, and keep contact multipliers
nonnegative. Those multipliers are the numerical forces enforcing the selected
equalities; a negative one would pull separated paper together like glue.
In the example, the summed squared violation falls from about `2e-14` to
`1e-14` and then nearly zero. Both pairs reach approximately
`(1e-7, -0.99999995)`. The ordinary work budget also limits these exchanges.

An improving replacement can still violate another inequality. It is an
internal candidate, never permission to move the paper. Convergence still
requires maximum violation and complementarity at most `1e-12`, force balance
at most `1e-6`, and nonnegative multipliers. Complementarity means a separated
contact exerts no force; force balance checks material, contact and damping
against the original equations. Removed equalities remain inequalities in
these checks. The existing exact geometry repair and endpoint checks are
unchanged. A regression stops after one replacement and verifies that this
partial improvement remains unconverged.

Replaying the saved band endpoints at length weight `1e9` and damping `1e-3`
on 2026-09-16 gives:

| Mesh | Single-exchange violation | Progressive violation | Replacements | Final force-balance residual |
| --- | ---: | ---: | ---: | ---: |
| 2×1 | 3.444e-11 | 1.003e-13 | 2 | 3.675e-9 |
| 2×2 | 9.629e-12 | 6.691e-13 | 3 | 2.394e-9 |

Both replays now meet every unchanged inner residual cap. The earlier original
working-set method gives the same failed residuals as the single exchange on
these problems. Constraint ids below index the deduplicated nonzero rows;
the downloadable replay also maps each id to all original source rows.
On `2×1`, rows 46, 74 and 77 start below tolerance. Replacing 47 with 46,
then 78 with 74, resolves them. On `2×2`, rows 67, 68, 70 and 100 start below
tolerance. The sequence is 71→67, 67→70 and 97→100. One replacement can repair
several similar rows, while another may need further replacement itself.

The replay JSON retains the original material/contact equations, free vertex
ids, proposed vectors, final contact residuals, selected rows and normalized
multipliers, plus every successful exchange's before/after squared violation.
The page displays the original failed band replay at the chosen width even
when another control or later endpoint is shown. These are optimizer steps,
not physical folding instructions.

The complete material solves use identical holds, bending preferences,
length-weight stages and work budgets. Only the contact method changes:

| Mesh | Policy | Converged and accepted | Relative edge error | Maximum opening |
| --- | --- | --- | ---: | ---: |
| 2×1 | Single exchange | No | 1.336e-5 | 7.723e-5 |
| 2×1 | Progressive | Yes | 1.483e-6 | 8.008e-6 |
| 2×2 | Single exchange | No | 6.229e-6 | 3.383e-5 |
| 2×2 | Progressive | Yes | 6.541e-7 | 3.409e-6 |

Openings are in sheet-length units. Both accepted endpoints retain exact
minimum gap zero, unchanged held positions and material identities, and
passing original-crease and independent whole-sheet contact checks. Their
maximum position changes from the failed endpoints are `0.0002566` and
`0.00007525`. Near-contact samples on the fixed grid increase from 1193 to
1239 and from 1342 to 1370 of 1480 overlapping locations; this sampled count
does not measure exact contact area. The matched-hold, original line-load
and both contact-off endpoints are unchanged at each width. Contact-off
still crosses. Eighteen of twenty solves converge; the two retained failed
band references account for the other two.

Validation independently recomputes replay gaps and force balance from the
saved equations, proposed vectors and contact multipliers. It also checks
all sixty FOLD/glTF exports, 180 SVG plots, material identities and holds,
endpoint caps, and nonnegative gaps and decreasing repaired energy at every
accepted constrained step. The thirty single-exchange reference states
reproduce #236 apart from their comparison titles. Fast analytical tests
exercise independent contacts, reordered/duplicated constraints and an
exhausted work budget; the expensive material comparisons remain opt-in.

This is a bounded numerical repair, not a general convergence guarantee or
a calibrated paper model. The [next isolated experiment](fine-band-length-enforcement.md)
tests stronger length enforcement for the `4×1` and `4×2` band contact-off
controls. Repeat the whole band grid with one solver policy before comparing
refinement. These two corrected meshes alone do not establish a mesh-independent shape, and
static endpoint checks do not certify a continuous flexible route.
