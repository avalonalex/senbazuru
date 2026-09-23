# Two contact guards permit a larger body correction

The [one-pair experiment](body-contact-direction.md) could take only 1/128 of
its proposed correction: guarding triangles 22–63 exposed a crossing at 14–55
in the next larger trial. [#333](https://github.com/avalonalex/senbazuru/issues/333)
guards both pairs from exactly the same saved shape. The first usable fraction
becomes **1/8**, lowering total cost **1.256878%** with the unchanged geometry
checks passing. The next larger fraction, 1/4, crosses **46–70**. This is a
better local correction, still not a settled or visibly opened body. See the
[glossary](../glossary.md) for material coordinates, panels, contact and layers.

```bash
stack run senbazuru-material-study -- --body-pairs build/fold-material/body-geometry build/fold-material
```

Reuse the saved blocked archive; this command does not repeat its continuation.
The 87 vertices, 120 triangles, original material, three exact holds, crease
preferences and panel bending are unchanged. So are the length weight `1e8`,
contact weight `1e10`, damping `1e-3`, 100-iteration quadratic budget and all
31 trial fractions. A quadratic approximates the length, angle and gap errors
as linear functions of a displacement, then minimizes their squared sum.
Its contact inequalities guide a direction; the actual displaced triangles
still need independent checks.

Each pair has four corners in its projected overlap. A signed gap is the
upper triangle's height minus the lower triangle's height at a corner.
For 22–63, triangle 63 is above 22. For 14–55, **14 is above 55**, so the
exported contact rows retain the order `[55,14]`. Sorting these ids without
preserving their roles would reverse the physical requirement. The new pair's
gaps are `1.63995e-10`, `6.38379e-10`, `5.68123e-4` and `2.57619e-4` sheet units.

The same guard `a · d + max(0,g) ≥ 0` applies at all eight corners: `g` is the
starting gap, `d` the correction and `a` its gap derivative, including movement
of the overlap corner. A negative gap cannot worsen to first order; a positive
gap may close to zero. The small negative starting gap at 22–63 stays in the
original cost. No clearance, thickness or tolerance is added.

| Direction | Active guards | First usable fraction | Cost decrease | Geometry-passing fractions |
| --- | ---: | ---: | ---: | ---: |
| Archived ordinary proposal | — | none | — | 0 / 31 |
| Matched unconstrained quadratic | 0 | none | — | 0 / 31 |
| Guard 22–63 | 1 | 1/128 | 0.085385% | 24 / 31 |
| Guard both pairs | 2 | 1/8 | 1.256878% | 28 / 31 |

The new quadratic converges in three internal iterations. Its two active
constraints are corner 3 at 22–63 (starting gap `-2.41513e-12`) and corner 4
at 55–14 (`1.63995e-10`); corner ids index the exported constraint array.
“Active” means the local calculation treats that inequality as an equality.
Inequality violation is zero, complementarity residual `2.45e-20`, and force
balance `1.45e-8`, below the unchanged `1e-6` cap. Complementarity means a
separated contact exerts no attractive force. Raw correction vectors are
exported so rounding the full positions does not obscure force balance.

| Measurement | Saved shape | Two-pair 1/8 trial |
| --- | ---: | ---: |
| Crease cost | 0.0119682881 | 0.0118605080 |
| Panel bending cost | 0.0012017776 | 0.0011403707 |
| Length cost | 0.0000158226 | 0.0000189828 |
| Contact cost | 0.000000576159 | 0.000000865242 |
| Total cost | 0.0131864645 | 0.0130207267 |
| Maximum relative edge error | 1.63680e-6 | 2.26002e-6 |
| Body depth | 0.0361928140 | 0.0361985598 |

Cost is half the squared-error objective, excluding numerical damping.
Both length and contact costs **increase**, while lower bending costs reduce
the total. Passing contact/order checks does not require their penalty to be
zero: the minimum ordered gap is `-7.94888e-9`, within the unchanged `1e-7`
tolerance. Neither guarded pair has a mathematical intersection at 1/8;
all-pair crossings and reversed orders above tolerance are absent. All holds
stay exact, and the sheet remains connected with unchanged vertex identities.

The 1/4 trial decreases cost 2.038457% and passes the length limit, with no
reversed orders. Both guarded pairs pass, but **46–70 crosses**, so the full
geometry gate rejects it. At still larger fractions even a guarded pair can
cross: the linear prediction cannot replace nonlinear triangle checks.
All four directions decrease cost at 29 fractions; cost descent alone would
therefore accept invalid paper in this comparison.

The selected movement is `1.42975e-4` sheet units, at most **0.0858 pixels** at
600 pixels per sheet unit. Neck and tail attachments move `2.07166e-5` and
`3.84254e-5`; the largest crease-angle change is `0.175016°`. Full proposed
movement remains `1.14380e-3`, **11,438 times** the equilibrium threshold.
Actual-size views do not show a meaningful body opening; magnified contact
views explain the numerical change. The surrounding crane's loads, flexible
motion between trials and pressure remain outside this specimen.

The gallery keeps 125 FOLD states, 1,000 SVG views, every trial decision,
separate costs, equations and active-constraint identities. Each pair has a
fixed overlap and tip crop shared by all trials; for 14–55, which does not
intersect at the start, the tip crop centres on the two closest overlap corners.
Large rejected proposals can leave these crops. Independent calculations
verify all saved lengths, angles, energies, attachment positions, crossings
and ordered gaps, plus the quadratic force balance. Finite differences of
all eight corner derivatives differ by at most `2.50e-11`. The three controls'
meshes, existing drawings and measurements match the preceding experiment;
source archives remain byte-for-byte unchanged. One small analytic regression
checks interacting guards in CI; the body experiment remains opt-in.

Next, compare adding **46–70** at this same saved shape, retaining the two-pair
result as a control. This isolates the remaining 1/4 obstruction before
choosing a bounded continuation that refreshes its guards as the paper moves.
A fixed list of these pairs is not a general contact-discovery policy.
