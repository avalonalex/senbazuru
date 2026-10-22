# Snap an edge that lies along a clip line

Terms are in [the glossary](../glossary.md). The material study checks that
one layer of paper stays above another
([ordered-flap-contact](ordered-flap-contact.md)). Where two paper triangles
overlap when seen from above, `SurfaceContact` clips one triangle's shadow by
the other's sides ([convex clipping](convex-clipping.md)) and measures the
height gap at each corner of the overlap: one *contact row* per corner. Each
gap carries its derivative with respect to every mesh vertex, so the solver
knows which way to move the paper when a gap is negative.

Clipping by a side finds where an edge of the other triangle crosses the side's
line. If the edge's ends are at distances `dp` and `dq` from the line, on
opposite sides, the crossing is the fraction `t = dp / (dp - dq)` of the way
along the edge. That is well behaved when the edge cuts the line at an angle.
It is not when the edge almost lies along the line. In `SurfaceContactSpec`'s
pair, an edge of length 0.3 has one end 5e-13 above the line and the other
1e-11 below. The crossing is 5% of the way along, 0.014 from the near end.
Move the near end 5e-13, onto the line, and the crossing slides that 0.014 to
the end. So `t`'s derivative is about 1e11. The gap changes along the edge, so
the gap at the crossing inherits that derivative: unsnapped, the contact row's
gradient is 2.7e10. That derivative is not a mistake. It is the true
derivative of a corner that exists only while the edge stays within 1e-11 of
the line.

Stacked layers of a folded model are full of such edges. Where one layer lies on
the next, their triangles' edges run along the same crease lines and differ
only by rounding. On the crane wing, the rounding left by the fold and the
solve puts them a few times 1e-13 off each other's lines, on either side.

So the clip snaps. A corner nearer the line than a band is on it, and its
distance is the constant 0, with no derivative. An edge with both ends in the
band does not cross the line. An edge with one end in the band crosses at that
end, and the crossing has no derivative. The band is 1e-12 as a distance from
the line, as in `Senbazuru.Origami.Contact.clipBy`. The clip computes a cross
product, the clipping side's length times the corner's distance, so the number
it compares against is 1e-12 times that length.

## On the crane wing

The crane-spreading gallery's `curved` control settles the wing by
Gauss-Newton: it linearises every penalty (on lengths, bending and contact)
about the current positions and solves the linear system by conjugate
gradients, preconditioned by a sparse factor. Its stopping
test asks that solve to reach `max(1e-6, 1e-8 · |right-hand side|)` within 3000
iterations. A penetrating contact row with a large gradient makes the
right-hand side 1e4 to 1e7, and the system too ill-conditioned for that: the
factor is refused, or the solve stalls. The solve converges only if no such row
is penetrating when it ends.

The band was 1e-14, and the snapped distance kept its derivative, until
[#566](https://github.com/avalonalex/senbazuru/issues/566). With the hinge moved
from `wingRoot` by d = 0, ±1e-13, ±3e-13, ±1e-12 and ±1e-11 (GHCi probes on
2026-10-21, one run each):

| Clip | Converged | Rows with gradient above 1e3 at the end |
| --- | --- | --- |
| band 1e-14, derivative kept (before #566) | 5 of 9 | 25 at d = 0 (largest 1.3e12, none penetrating); 52 at d = +1e-13 (16 penetrating, largest 2.4e9) |
| band 1e-14, derivative dropped | 9 of 9 | 1 to 16 at every hinge, largest 4.9e9 to 3.3e11, none penetrating |
| band 1e-12, derivative dropped | 9 of 9 | none; the largest gradient is 6.6 |
| band 1e-12 as a distance, derivative dropped (since #607) | 9 of 9 | 8 rows near 7e9 at 2 of the 9, none penetrating |

The second row was the first fix tried. It converged at every hinge, but only
because no remaining row was penetrating at the end: less luck, not none. The
finer mesh, `fine`, solved at d = 0 and +1e-13, kept 17 and 5 such rows, up to
3e10, under that rule. The third row, a band of 1e-12 of the cross product
(owner decision 59), left no row above 1e3 there, and `fine` none either
(largest 6.2). It turned out to break another control, and the fourth row
replaced it (below).

Holding `t` fixed while differentiating would bound every gradient: the
crossing would move with its edge but not along it. On the crane wing the
largest gradient is then 2.2. But that is the wrong force, as
[ordered-flap-contact](ordered-flap-contact.md) says. With it, the
crease-correction study's six viable starts, which otherwise converge in 31 to
80 iterations, no longer converge, and the body patch's solves block stages.
Away from the line, the slide along the edge is real information.

The band does not bound the derivative. A crossing whose ends are both past it
still differentiates as about `1 / (dp - dq)`: ends at 1.1e-12 and −1e-11 give a
gradient of 2.4e10, and ends at ±1e-9 give 8e7. The band works because it is
wider than the rounding that separates coincident edges. A fold whose
coincident edges land more than 1e-12 apart would bring the problem back.

Fewer large rows did not mean more reliable convergence. The crane-root
gallery's released strip ([wing-root-holds](wing-root-holds.md)), hinged at y =
1/4, converged at all 19 positions probed within 1e-9 of its own hinge before
the fix, and at only 14 with the band at 1e-12 of the cross product (GHCi probes
on 2026-10-22, one run each). It stalls for a different reason than `curved`
did. The solver adds a contact row to its linear step only once the row
penetrates. Rows sitting about 8e-10 clear of contact were left out, so the full
step drove them to −1.7e-7, and the line search accepted almost none of it, step
after step. Which rows sit just clear depends on where the band puts their
corners. With the band as a distance, the released strip converges at all 19
positions and `curved` still at all 19, as with 1e-13 or 1e-14
([#607](https://github.com/avalonalex/senbazuru/issues/607), owner decision 62).
Changing the solver to add the rows a step would carry into contact fixed the
released strip but broke crease correction and the body patch.

The clip is shared. Its gradients reach the solves of 26 study galleries and its
values another 42. On 2026-10-21 every one of them that can still run was run
twice, just before and just after the fix, and each note whose figures the fix
changed says so in a dated paragraph
([#605](https://github.com/avalonalex/senbazuru/issues/605),
[C118](../../PRDs/decisions.md#changes-since-draft-v2)). The body galleries
below `--body-subdivision` cannot run: they refuse a body-subdivision archive
made since the fix, and their notes are kept as a record of the runs made before
it ([the subdivision note](recovered-body-subdivision.md), owner decision 60).
Owner decisions 58 and 59
([#566](https://github.com/avalonalex/senbazuru/issues/566)) set how far the fix
reaches and the band's first width, and owner decision 62
([#607](https://github.com/avalonalex/senbazuru/issues/607)) made it a distance.
The galleries' dated paragraphs from 2026-10-21 were measured with the first
width; [#613](https://github.com/avalonalex/senbazuru/issues/613) measures them
again with this one.
