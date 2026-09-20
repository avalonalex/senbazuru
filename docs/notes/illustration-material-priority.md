# Plausible illustrations set the next material milestone

Owner decision, 2026-09-20, after [#314](https://github.com/avalonalex/senbazuru/pull/314):
prioritize a plausible spread wing and opened crane body. Defer further work
whose only benefit is closer agreement between internal bending costs. Return
to that work when it changes the drawing or prevents a usable, repeatable pose.
This sets the next milestone for [#195](https://github.com/avalonalex/senbazuru/issues/195)
and track A of [#269](https://github.com/avalonalex/senbazuru/issues/269).
[#315](https://github.com/avalonalex/senbazuru/issues/315) records the scope change.

The [saved 512-triangle layouts](held-layout-costs.md) differ by 10.36% in
passive bending cost, which penalizes bending within panels between creases.
Yet corresponding material positions differ by at most `0.000849586` of the
sheet's side. The centre-row profiles nearly overlap at the gallery's drawing
size. A cost discrepancy does not measure a percentage difference in the
picture. Neither the positional threshold nor that one overlay establishes
visual agreement for other poses, layers or cameras.

For the illustration milestone, the criteria have these roles:

| Check | Role |
| --- | --- |
| Connected material, shared vertices and real crease identities | Required. Touching layers remain distinct pieces of the same sheet; they must not be welded together. |
| Material lengths, declared angle controls, exact holds, contact and layer order | Required under the existing endpoint checks. Retain the `1e-5` relative length-error limit; the current small examples already pass it. |
| Numerical solve acceptance | Retain existing convergence/refusal checks for outputs presented as solved. An exhausted or invalid trial stays diagnostic. |
| Silhouette, visible creases, exposed layers and plausible bulging | Review at a declared drawing size and intended cameras, alongside a modest refinement comparison. Keep SVG and GLB on the same geometry. |
| Less than 5% change in each energy component or opening under refinement | Retain as material-research diagnostics; no longer prerequisites for starting or completing the illustration milestone. |
| Physical stiffness calibration and independence from mesh layout | Deferred research. Label the chosen material response illustrative. |

The existing two-pixel comparison at 600 pixels per sheet unit is a
**provisional drawing budget**, not a universal visibility threshold. Choose
views and scale before judging a new example. Review the overlay at actual
size and magnify differences to locate them. A changed visible layer, lost
crease, wrong overlap or obvious kink deserves attention even if an aggregate
number is small. A tiny exposure difference may be acceptable after explicit
review of that feature and view; there is no blanket small-area waiver. Previous
exposed-layer cases remain in review until that review happens. Energy and
opening differences remain in reports, including failed historical targets.

The next bounded study returns to a small crane-body patch connected to both
wing roots, using the existing [material map](crane-pocket-map.md). Name a few
increasing spread/opening controls and the body creases allowed to change angle.
Check the declared angle policy, rather than requiring an opening crease to
retain its old closed angle. Preserve the same sheet and allow its panels to
bend. Measure the neck/tail attachment response without assuming its direction
from a photograph. Authored grips or opening preferences may guide a plausible
pose; the checked geometry still has to accommodate them.

Earlier body-release trials failed lengths and contact as well as convergence.
Those are still blockers for an accepted pose. Isolate that compatibility
problem before enlarging the free region. The first deliverable is a small set
of accepted static poses, or a specific reproducible geometry/solver blocker,
with side, top and underside views, body dimensions, wing shape and attachment
movement. Declare the fixture, holds, angle policy, work budget and comparison
views before solving. Do not automatically advance to a full-crane sweep.

Controlled pocket opening comes before simulated air pressure. The mapped
body patch is not a sealed cavity, as the [opening study](opening-a-crane.md)
explains. Separate valid endpoints also do not certify the flexible path
between them. The material-consumer and library-graduation contracts in
[PRD 07](../../PRDs/07-prd-material-consumption.md) remain separate: this decision
does not feed a settled illustration back into later rigid folding steps.

Keep the proposed shape-preserving width subdivision and further cost-refinement
work on the deferred list. Revisit it when mesh choice produces a visible
artifact, changes meaningful layer behavior, or makes the authored controls
unreliable; a future requirement to predict real forces would also reopen the
material-accuracy question. Start from a concrete failing illustration or
control and the saved diagnostics. This changes the order of work and the
illustration milestone, not the archived measurements, solver defaults or
results of the stronger material study.
