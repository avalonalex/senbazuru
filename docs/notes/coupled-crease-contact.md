# Contact when both panels bend

The [previous experiment](nonnegative-crease-contact.md) keeps the lower paper
fixed. Its upper partner can bend, but every contact is measured against a
known stationary shape. Release the lower interior too: now both sides of a
contact move, and neither supplies a fixed reference. The small sheet still
has two [panels](../glossary.md), joined at one fully closed crease.

```bash
stack run senbazuru-material-study -- --coupled-crease build/fold-material
```

Hold the three shared crease vertices and the outer quarter of each panel.
Each interior has six free vertices at 32 triangles, or fifteen at 64. These
vertices can move in all three directions. Only the real crease shares
material vertices: touching layers are not welded. The material springs,
length-weight stages and damping stay the same as in the fixed-panel solve.
Equal holds and material preferences deliberately make this a symmetric case.

The touching start is the original bent reference. Two other starts move
each free side inward, giving relative penetrations up to `0.002` or `2e-8`
sheet lengths. An incompatible control additionally holds an interior row on
each side in those penetrating positions. The fixed-lower baseline still
runs its original solver, with the original upper-only perturbation.

Contact is measured between the **current triangles of both panels**.
Project them onto xy and find the corners of each overlap: a vertex inside
the other triangle, or two intersecting edges. Their height difference is
linear over the overlap, so the smallest corner gap bounds the whole region.
Touching edges and points count too. Stored coordinates become exact fractions;
no tolerance turns a negative gap into zero.

Each corner retains signed **barycentric weights**: fractions contributed by
the upper triangle's vertices, minus those from the lower. Shared vertex
contributions cancel by id. Moving either triangle also moves the overlap
corner. A vertex/face contact uses the face's normal; an edge/edge contact uses
a direction perpendicular to both edges. These directions express how the
gap changes as vertices move. Using a separate normal for each triangle would
instead freeze the overlap point in space and give the wrong derivative.
A finite-difference test moves a lower edge to check this distinction.

The existing constrained quadratic uses those gap derivatives to propose a
material step. It may release touching contacts when the paper wants to
separate; no equation requires the layers to stick. The proposed geometry is
then measured again. If it penetrates, a repair raises all free upper vertices
and lowers all free lower vertices by the smallest common amount that fixes
every negative corner. It keeps x/y and all holds unchanged. Exact weights
determine that amount, heights round outward, and the stored result must pass
the exact check. A negative gap with only held contributions is refused.
This is a symmetric numerical repair, not a physical motion or paper thickness.

The recorded repair amount is **per side**: `0.001` upward and `0.001` downward
can repair `0.002` relative penetration where both sides are fully movable.
Initial repairs remain separate from settled endpoints. The line search tests
material energy after repair; convergence still requires the full repaired
step to be at most `1e-7` sheet lengths and the constrained quadratic to pass
its original force and gap checks. Final relative edge error must be at most
`1e-5`; early numerical iterates are not folding states.

The compiled gallery on 2026-09-14 gives nearly identical endpoints for the
three compatible starts at each resolution:

| Measurement | 32 triangles | 64 triangles |
| --- | ---: | ---: |
| Exact minimum gap | 0 | 0 |
| Maximum relative edge error | 7.390e-7 | 3.221e-6 |
| Maximum authored crease error, radians | < 5e-14 | < 1.4e-13 |
| Lower movement from the original bent reference | 0.001788 | 0.004269 |
| Upper movement from the original bent reference | 0.001788 | 0.004269 |
| Recorded solver iterations | 36 | 43 |

All six endpoints preserve material identities, shared vertices and exact
holds. They pass the whole-sheet contact check at its unchanged `1e-7`
distance tolerance, and every recorded iterate has a nonnegative exact gap.
Both incompatible controls are refused. The largest accepted subsequent
repair is about `3.689e-6` per side on the finer penetrating case; additional
rounding stays below `7e-18`.

Both interiors really move: displacement is measured from the unperturbed
reference, so repairing the starting penetration cannot supply that evidence
by itself. The two movement plots share one scale across both panels and all
stages of a run. Complete FOLDs retain the measured coordinates; complete-sheet
GLBs round for display and cannot establish microscopic contact.

The symmetric endpoints remain almost coincident: even their maximum gaps
are below `1.3e-14`. That is a result of these boundary conditions, not a weld.
Refinement changes matching material positions by up to `0.001558` sheet
lengths. Two passing resolutions therefore do not establish a mesh-independent
shape or calibrated paper stiffness. Exact clipping supplies both constraints
and repair; prescribed-profile tests and the separate whole-sheet contact
checker provide additional verification.

The [unequal-control follow-up](unequal-crease-controls.md) changes an upper
grip or bend preference with narrow strips beside the crease held. It shows
both separation and contact changing the lower panel, but the coarse and fine
contact patterns differ. Further refinement is needed before returning to the
crane body patch. Both experiments assume known order along z and triangles
that retain their original facing directions. General contact discovery and a
certificate for continuous flexible motion remain separate work.
