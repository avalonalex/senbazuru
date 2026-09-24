# Change the body contact method before repairing another pair

Owner direction, **2026-09-24**, after merged
[#375](https://github.com/avalonalex/senbazuru/pull/375): pause further repairs
chosen one triangle pair at a time. The body study has supplied the
**specific reproducible geometry/solver blocker** allowed by the
[illustration milestone](illustration-material-priority.md). This completes
that branch of the first deliverable; it does not establish an accepted opened
body, physical impossibility, or completion of
[#195](https://github.com/avalonalex/senbazuru/issues/195).
[#377](https://github.com/avalonalex/senbazuru/issues/377) records this roadmap
update for track A of [#269](https://github.com/avalonalex/senbazuru/issues/269).

The [latest saved repair](body-overlap-restoration.md) removes the reported
14–55 crossing but violates neighboring 55–93 guards. A guard is a linear
prediction of how a gap changes when vertices move; the actual finite movement
needs a separate geometry check. The repair moves vertices by at most
`2.64e-11` sheet units and creates no new visible opening. The full material
proposal remains 5,456 times above its movement stopping tolerance. Preserve
these results as evidence of the current method's limitation. The previously
proposed joint repair at that same trial is deferred.

The next proposed study compares the existing
[directional distance barrier](directional-contact-distance.md) with the
contact penalty proportional to the squared negative gap on this body patch.
A barrier resists approaching
zero separation and is undefined once the required gap is nonpositive; the
finite penalty can instead trade a small negative gap for less bending energy.
The barrier settled the recorded strip control where the penalty stalled.
Whether that benefit transfers to the body is still untested.

1. **Declare the experiment before solving.** Identify the saved starting mesh
   and the archive it came from, numerical clearance, the distance over which
   the barrier acts and its strength, material weights, construction method and finite work
   budgets. Bound initialization separately from material corrections and
   trial step lengths. Keep the three exact holds, material coordinates,
   shared vertices, crease preferences and inherited layer relationships.
2. **Attempt one separated initialization.** A positive gap is required for
   disjoint layers, while triangles joined along a material crease must remain
   connected. Moving layers independently would tear the sheet. Check lengths,
   all triangle pairs, inherited orders and the barrier domain before running
   the comparison. If the bounded construction fails, publish that failure
   and stop; it is an initialization blocker, not a failed barrier solve or
   proof that every possible initialization is impossible.
3. **Compare both methods from the same successful start.** Extend the barrier
   entry point to honor exact held vertices; its current API does not take
   holds. Use matching material settings, work budgets and accepted-path checks
   for the barrier and penalty controls. Discover relevant nearby contacts and
   preserve their history consistently with inherited orders, rather than
   adding another hand-selected pair list. Keep the old penalty archive as
   historical context, since its different start and path policy do not isolate
   the effect of changing contact energy.
4. **Report useful shape and acceptance.** Measure body depth, wing-root shape,
   neck/tail attachment movement, lengths, holds and contact/order results.
   Show side, top and underside views at 600 pixels per sheet unit and enlarged
   details. Report separate bending, length and contact costs, full proposed
   movement, accepted corrections and runtime. Totals from different contact
   energy formulas do not rank physical quality. Keep the existing `1e-5`
   relative edge-error limit and all other endpoint/convergence checks;
   strict numerical-path checks are additional evidence, not a physical folding
   certificate.
5. **Stop at the declared budget.** A useful accepted static pose is progress;
   a reproducible initialization, path-check or convergence blocker is also a
   valid study conclusion. A new limiting pair does not authorize another
   repair series. Retain refused states and identify which condition stopped
   the run before deciding whether further work benefits the illustration.

Numerical clearance, the distance over which a barrier acts, and physical paper
thickness are separate choices. [C-IPC](https://ipc-sim.github.io/C-IPC/)
models thickness by enforcing minimum distances between sheet surfaces;
[Zhu and Filipov](https://pmc.ncbi.nlm.nih.gov/articles/PMC6834023/) also study
how contact parameters change origami geometry. A thickness comparison needs
its own declared model and owner decision. Keep it separate from this first
barrier comparison. If hard contact constraints are revisited later, consider
nearby constraints together instead of repairing one pair independently.

This decision changes the next experiment, not solver defaults, tolerances or
archived verdicts. No body barrier solve has run as part of this roadmap update.
Pressure, whole-crane inflation and continuously checked flexible folding stay
later work. The [material-consumer contract](../../PRDs/07-prd-material-consumption.md)
also remains unchanged: a flexible illustration does not silently replace the
state used by the next rigid folding instruction.

**Initialization result, 2026-09-24:**
[#379](https://github.com/avalonalex/senbazuru/issues/379)
[runs the separately bounded construction](body-separated-initialization.md).
It stops after four retained corrections with negative gaps, excess length
error and failed contact checks. No candidate can enter the barrier, so step 3
has not run. This meets step 2's prescribed stop at an initialization blocker;
another method needs a new scoped decision before further construction or
material solves.
