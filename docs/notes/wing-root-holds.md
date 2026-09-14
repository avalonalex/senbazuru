# The root hold is not the root material

The [connected crane experiment](spreading-connected-wing.md) fixes a strip at
the wing's root at 30 degrees, while its tip grip turns to 50 degrees. The
root is the line where the wing meets the body. Fixing that strip already
determines a sharp change of direction there, regardless of what its crease
spring prefers. Remove the hold before asking whether a different spring
produces a smoother transition.

Run the comparisons from the repository root:

```bash
stack run senbazuru-material-study -- --crane-root build/fold-material
```

Every control uses the same connected crane, tip grip, original material
coordinates and 902 source layer orders. Refine four wing panels and the four
body panels directly across their root edges. The eight-span mesh has 609
vertices and 1,176 triangles; sixteen spans give 2,193 vertices and 4,312
triangles. Both sides of a material edge share its inserted midpoint ids;
coincident layers never acquire a shared id merely because they touch.
See the [glossary](../glossary.md) for panels, material coordinates and layer order.

The controls distinguish three choices. A hold fixes a position exactly. A
rest angle is a spring's preferred angle, which the rest of the sheet can
prevent it from achieving. Stiffness sets how strongly that spring resists
departing from its preference. The weaker-root control multiplies only the
four root springs' stiffness by 0.1. The flat-preference control sets only
their rest angles to zero. Both release the exact root-strip hold, and keep
the body and tip fixed.

The fixed-body results measured on 2026-09-14 all pass the endpoint checks:

| Control | Root turn | Maximum relative edge error |
| --- | ---: | ---: |
| Held root strip | 30.00° | 2.92e-7 |
| Released strip, 30° preference | 31.27° | 8.06e-7 |
| Released strip, ten-times weaker spring | 31.45–31.46° | 8.93e-7 |
| Released strip, flat preference | 28.22° | 1.73e-7 |
| Flat preference, finer mesh | 27.39° | 3.64e-7 |

The root stays sharply turned in all five cases. Weakening its spring allows
a larger turn in this experiment. A flat preference reduces that turn without
removing it. The finer flat-preference solve moves matching material points
by at most `0.000145` model units; total crease-plus-panel bending energy
changes by about 2.57%. The root angle's remaining 0.83-degree change is a
reason to retain the refinement comparison, not claim a mesh-independent value.

The generated side profiles follow the wing's middle into the body, selecting
one layer by source-panel ownership and its original normal. They use actual
mesh positions at one scale; changing shading or hiding a line cannot change
their measured turn. The JSON keeps signed angles for every root segment.
The two layers' material normals point in opposite directions, so a geometric
turn can have opposite signed angles; the displayed ranges use magnitudes.

Acceptance requires relative material edge errors at most `1e-5`, exact
remaining holds, independent triangle contact and retained-order checks, and
the solver's equilibrium checks. Original mountain/valley crease angles must
remain within `1e-5` radians. The four added root springs are deliberately
excluded from that last angle gate: a soft preference cannot simultaneously
be required as an exact equality. Their achieved angles remain reported.
The incompatible grip control is still refused when its upper layer is pushed
`0.005` below its partner.

The body-release control gives the four root neighbours freedom while holding
every vertex incident to another panel. Thus the outer boundary, other wing,
neck and tucked tail stay fixed. It also needs contacts between newly free
body panels and the surrounding stack. First expand the source orders, then
select pairs involving free vertices: if A is below held B and B below held C,
dropping B–C first loses the requirement that moving A remain below C. The
regression keeps that inherited relation even when B and C cannot move.

The finer accepted mesh exposes a separate stable-view export refusal
([#206](https://github.com/avalonalex/senbazuru/issues/206)). Its complete-sheet
GLB succeeds. The gallery retains physical acceptance, geometry and measurements
while recording the rendering failure separately; the stable-view selector
omits that mesh. No physical position or layer order is changed for display.

A zero rest angle still leaves a crease spring at the authored wing-root
line. It does not replace that line with ordinary uncreased panel material.
`FoldBending` weights a crease spring by its material length; a panel bend
also uses the areas of the two adjoining triangles. A weaker line can therefore
concentrate rotation rather than distribute it through the nearby paper.
The next material comparison should distinguish these two root models, and
diagnose any failed body solve before treating its shape as a physical result.

These are static experiments with specified holds and illustrative stiffness.
The optimizer can stretch or cross paper between numerical iterates. A failed
attempt establishes neither physical impossibility nor the absence of another
compatible grip or held region. Unheld equilibrium, two-wing spreading, body
inflation and continuously checked flexible routes remain later work under
[#195](https://github.com/avalonalex/senbazuru/issues/195).
