# Refining the same unequal-panel experiment

The [unequal controls](unequal-crease-controls.md) produced nearly touching
paper at 32 triangles, but separation at 64. Both meshes had only three rows
across the width. Is the difference caused by that sparse width, and does
further refinement settle it? Keep the same held material regions and upper
bend preferences, then vary the two mesh directions independently.

```bash
stack run senbazuru-material-study -- --unequal-refinement build/fold-material
```

A length multiplier divides each of the four original profile segments;
a width multiplier divides each of the two original width intervals. Thus
`2×1` has eight segments from crease to outer edge and three width rows,
while `1×2` has four segments and five rows. Both have 64 triangles, but
resolve different directions. All share vertices along the crease and keep
the contacting material elsewhere distinct. The same material strips within
`0.125` of the crease and outer edges at `0.5` stay held.

The extra upper bend preferences stay at material coordinates `-0.125`,
`-0.25` and `-0.375`. Their stiffness is eight times each segment's material
length: adding width rows splits a control without strengthening it. Total
control stiffness remains 24. Passive panel springs keep their existing
material-geometry weighting; the held crease's total stiffness also stays
unchanged. These are controlled numerical experiments, not calibrated paper.

The compiled run on 2026-09-15 uses the same solver settings as #225: 40
iterations per length-weight stage, ending at weight `1e8`, with relative
edge-error cap `1e-5`. The upper-preference results are:

| Length × width | Triangles | Maximum gap | Near-contact samples / overlap samples | Relative edge error | Accepted |
| --- | ---: | ---: | ---: | ---: | --- |
| 1×1 | 32 | 7.271e-7 | 1281 / 1480 | 8.560e-7 | Yes |
| 2×1 | 64 | 0.007009 | 400 / 1480 | 3.747e-6 | Yes |
| 4×1 | 128 | 0.004421 | 400 / 1480 | 9.026e-4 | No |
| 1×2 | 64 | 3.385e-7 | 1416 / 1480 | 4.434e-7 | Yes |
| 2×2 | 128 | 0.006907 | 400 / 1480 | 2.496e-6 | Yes |

Distances are fractions of the unit sheet's side. Maximum gaps come from
exact arithmetic on all projected triangle-overlap corners. A separate map
samples 40×40 fixed cell centres over `x=0..0.5`, `y=-0.5..0.5`; the same
locations are used on every mesh. A nonnegative gap up to `1e-7` is called
near contact. Missing overlap is explicit, never counted as touching.
These counts describe sampled regions, not exact contact areas, and the
finite grid is never used to certify non-crossing. The 400 near-contact
samples on the finer length meshes all lie in the held strip; separation
extends over the sampled free region. Tiny gaps on the coarse meshes straddle
the plotting threshold, so their differing counts are not proof of a major
physical change in contact area.

Doubling width changes matching upper-preference material positions by
`1.333e-5` at the coarse length and `1.706e-4` at the finer length. The latter
maximum gap changes by about `1.015e-4`. Width refinement therefore retains
the substantial opening at the finer length; it does not explain it away.
This does not establish convergence in either direction.

Every mesh also has matched and contact-off controls. All four lower-resolution
matched endpoints pass, and all four converged contact-off endpoints cross.
Their lower panels match the corresponding reference to numerical precision;
enabling contact changes the lower endpoint by `0.002116` to `0.002611`
sheet lengths across those meshes. This preserves the evidence that contact
transmits the upper preference to its partner. The eight accepted endpoints
retain original holds, material identities, lengths, authored crease angles
and the independent whole-sheet contact check. All ten contact-enabled runs,
including the failures, retain nonnegative exact gaps at every recorded step.

The `4×1` failures prevent a stronger conclusion. Its matched and contact-off
runs stop with relative edge errors about `1.043e-5`, just above the unchanged
cap, despite proposed movements around `1e-9`. A finite length penalty is not
an exact length constraint. The upper-preference run instead fails the inner
constrained-step convergence test: its largest inequality violation and
contact-force/gap consistency residual are both `5.423e-12`, above the inner
solver's `1e-12` thresholds. The force-balance residual `1.161e-9` is within
its separate `1e-6` cap. Length error remains `9.026e-4`. These failures are not
simply the outer iteration limit, and their displayed shapes are not accepted
equilibria. The apparent gap reduction at `4×1` cannot be read as convergence.

The follow-up [fine-mesh solver comparison](fine-crease-solver.md) isolates
these failures: first the matched/contact-off length penalty, then the
upper-preference constrained-step residual. It keeps all acceptance caps
fixed and obtains a passing fine endpoint with both numerical changes.
The [common-policy rerun](combined-crease-refinement.md) then accepts all ten
constrained endpoints, but the length-refined shapes still have not stabilized.
Known order along z, retained triangle facing directions and static endpoints
remain limitations; no continuous flexible route has been checked.
