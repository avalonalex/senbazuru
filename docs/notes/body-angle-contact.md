# Contact-aware angles still need a verified correction direction

[#385](https://github.com/avalonalex/senbazuru/issues/385) follows the
[angle-only construction](body-crease-seed.md). That construction joins the
panels without stretching, but places some layers through others. This study
includes the inherited layer relationships while choosing angles, instead of
checking them only after the angle search finishes.

```bash
stack run senbazuru-material-study -- --body-angle-contact build/fold-material/body-crease-seed build/fold-material
```

The saved `angles.fold` is the only starting point. Patch edge 4 remains at
−175°; the other thirteen physical crease angles retain their signs and
magnitudes between 150° and 179.99°. Flat connections stay at zero. The same
material, stiffness preferences, three grip identities and inherited orders
are retained. As in #383, a new joined pose would determine new grip positions.

During construction, each panel has a provisional rigid placement: a turn and
translation obtained by walking through the crease connections. Different
routes around a loop may disagree. Each triangle therefore has independent
*temporary* corner coordinates for measuring contact. Welding those corners
would hide a tear. Original material ids still determine which pairs share
paper: such pairs target zero separation, while vertex-disjoint triangles
(those with no shared corner) target `1e-6` sheet units. These temporary copies
are numerical work space, never exported as continuous paper.

Every inherited projected overlap participates, including currently positive
gaps. The contact derivative follows the moving overlap corner, then combines
its positional derivative with the change in panel placement per angle.
Central differences at `1e-6` radians estimate those placement derivatives.
A small strip control checks the resulting gap derivative away from a clipping
event, where an overlap corner appears or disappears.

One additional unknown bounds both signs of every loop residual and every
contact deficit. A **deficit** is how far a gap falls below its target. The
objective lowers the largest remaining error, so improving many contacts
cannot hide a worse one. Translation and orientation residuals are numerical
components in this unit-sheet construction, not a physical bending energy.
Residuals are divided by `0.01` and angle increments use degrees. The existing
`ContactQuadratic` original working-set method chooses a subset of constraints
to treat as equalities while computing a direction. It uses damping `1e-8`, with 200
inner iterations per direction. Original constraint, complementarity and
balance checks still decide whether that direction is usable. Complementarity
means a separated constraint must not exert a contact force; balance compares
the objective's force with the selected constraint forces.

There are at most forty outer corrections, a 5° change limit per angle, and
trial fractions `1, 1/2, …, 1/4096`. Every trial recomputes loops and overlaps
and must lower the actual worst residual. A candidate can become shared paper
only after loop disagreement is at most `1e-10` and production folding passes
both shared-vertex and achieved-angle checks. Coarse and subdivided poses then
face the unchanged length, inherited-order, all-pair contact, positive-clearance,
local-reference and strict static checks. No angle-search score substitutes
for those gates.

**The 2026-09-24 run stops before its first geometry trial.** The linear problem
has thirteen angle increments and one common-bound increment, with 1,204
inequalities: 432 loop bounds, 718 overlap-corner bounds, 26 angle bounds,
26 step bounds and two common-bound constraints. These rows are not independent
contacts: several refer to the same overlapping triangles or loop.

| Measurement | Result |
| --- | ---: |
| Inner iterations / declared limit | 34 / 200 |
| Selected working constraints | 12 |
| Largest linear constraint violation | `1.52955e-9` |
| Complementarity residual | `1.52955e-9` |
| Required limit for each of those residuals | `1e-12` |
| Balance residual, limit `1e-6` | `1.11e-16` |
| Retained angle corrections / geometry trials | 0 / 0 |
| Construction CPU time, excluding setup and export | 0.547 s |

The original-row verification refuses the direction, despite good balance.
The common-bound prediction would fall from `0.00785563` to `0.000383049`, but
that prediction was **not installed or evaluated as a trial pose**. The table's
linear residuals refer to scaled optimization inequalities, not measured new
paper crossings. A coupled-vertex control also exposes the original method's
refusal; the regression checks that an unverified direction cannot update the
stored pose. An existing contact-exchange alternative was evaluated only on
that small control and also failed its checks. The body used the predeclared
original method once, with no parameter retry or tolerance change.

The returned joined mesh is exactly the saved start. Its body depth remains
`0.0254940`; relative edge errors remain below `2.2e-11`; the same shape has
four coarse or eighteen subdivided crossing pairs. There is no new opening,
accepted material endpoint, barrier-ready start or body barrier solve. The
failure is numerical verification of this constrained direction, not proof
that the angle bounds or inherited layer arrangement are geometrically
impossible.

The gallery shows the saved and returned poses at drawing size and 4×, with
side, top, underside and material views. It explicitly says that nothing
changed. The archive records every inequality, the proposed direction,
constraint force coefficients, original-row residuals and empty trial list.
Independent calculations reproduce the panel transforms, all 718 moving
overlap gaps, loop derivatives, linear verification and unchanged exported
geometry. All 34,764 older archive files retain their bytes. All 1,916 tests
pass in 159 seconds after a warning-free cold build; formatting, HLint 3.10,
JavaScript checks and all sixteen gallery combinations pass. The full body
experiment is opt-in; it is not added to CI.

Stop here. This is a reproducible solver blocker, satisfying the diagnostic
branch of the [illustration milestone](illustration-material-priority.md),
without providing a useful opened body. Before another body run, decide whether
to audit/replace the reduced angle solver using this saved linear problem, or
to derive a starting pose from a known valid folding route. Neither a new
pair-specific guard nor an automatic tolerance waiver follows from this result.
The [matched barrier comparison](body-barrier-comparison.md) remains blocked.
