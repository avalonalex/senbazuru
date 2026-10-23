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
only by rounding. At the end of the crane wing's `curved` solve, a corner near
another triangle's side is most often 1e-11 to 1e-9 from its line, on either
side; its cross product with that side is most often 1e-13 to 1e-10 (GHCi,
2026-10-21).

So the clip snaps. A corner nearer the line than a band is on it, and its
distance is the constant 0, with no derivative. An edge with both ends in the
band does not cross the line. An edge with one end in the band crosses at that
end, and the crossing has no derivative. The band is 1e-12 as a distance from
the line, the test `Senbazuru.Origami.Contact.clipBy` makes. The clip computes a
cross product, the clipping side's length times the corner's distance, so the
number it compares against is 1e-12 times that length.

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

Until [#566](https://github.com/avalonalex/senbazuru/issues/566) the band was
1e-14 of the cross product, and the snapped distance kept its derivative. With
the hinge moved from `wingRoot` by d = 0, ±1e-13, ±3e-13, ±1e-12 and ±1e-11
(GHCi probes, one run each, on 2026-10-21 for the first three rows and
2026-10-22 for the last):

| Clip | Converged | Rows with gradient above 1e3 at the end |
| --- | --- | --- |
| 1e-14 of the cross product, derivative kept (before #566) | 5 of 9 | 25 at d = 0 (largest 1.3e12, none penetrating); 52 at d = +1e-13 (16 penetrating, largest 2.4e9) |
| 1e-14 of the cross product, derivative dropped | 9 of 9 | 1 to 16 at every hinge, largest 4.9e9 to 3.3e11, none penetrating |
| 1e-12 of the cross product, derivative dropped (owner decision 59) | 9 of 9 | none; the largest gradient is 6.6 |
| 1e-12 as a distance, derivative dropped (owner decision 62, since #614) | 9 of 9 | 8 at each of 2 hinges, near 7e9, none penetrating |

The second row was the first fix tried. It converged at every hinge, but only
because no remaining row was penetrating at the end: less luck, not none. The
finer mesh, `fine`, solved at d = 0 and +1e-13, kept 17 and 5 such rows, up to
3e10, under that rule. The third row left no row above 1e3, and `fine` none
either (largest 6.2), and both converged. It turned out to stall another
control, and the fourth row replaced it (below). The fourth is the second
row's case again, less often. Probed at 19 hinges within 1e-9 of `wingRoot` on
2026-10-22, `curved` converges at all 19 under each of the last three rows, and
rows above 1e3 remain at the end at 19 of them under the second, 2 under the
third and 5 under the fourth, none penetrating. `fine` converges at both its
hinges under the fourth too (largest gradient 6.2 and 11.4).

Holding `t` fixed while differentiating would bound every gradient: the
crossing would move with its edge but not along it. On the crane wing the
largest gradient is then 2.2. But that is the wrong force, as
[ordered-flap-contact](ordered-flap-contact.md) says. With it, the
crease-correction study's six viable starts, which otherwise converge in 31 to
80 iterations, no longer converge, and the body patch's solves block stages.
Away from the line, the slide along the edge is real information.

The band does not bound the derivative. A crossing whose ends are both past it
still differentiates as about `1 / (dp - dq)`: ends at 1.1e-12 and −1e-11 give a
gradient of 2.4e10, and ends at ±1e-9 give 8e7. A band helps only where it is
wider than the rounding that separates coincident edges. The crane's mesh
sides are mostly 0.006 to 0.1 long, so the third row's band, 1e-12 of the cross
product, is 1e-11 to 2e-10 as a distance there. The fourth row's is 1e-12,
narrower on every side shorter than 1, and its rows near 7e9 are edges with ends
about 2e-12 off a side 0.5 long. Those solves converge because none of the rows
is penetrating when they end.

Fewer large rows did not mean more reliable convergence. The third row's band
stalled the crane-root gallery's released strip
([wing-root-holds](wing-root-holds.md)), and the fourth's does not. The band's
edge is itself a jump in the contact penalty, and where a solve's corners lie
against that edge decides whether a stage can finish:
[snap-band-edge](snap-band-edge.md) ([#607](https://github.com/avalonalex/senbazuru/issues/607),
owner decisions 62 and 63).

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
reaches and the band at 1e-12 of the cross product, and owner decision 62
([#607](https://github.com/avalonalex/senbazuru/issues/607)) made it a distance.
The galleries' dated paragraphs from 2026-10-21 were measured with decision 59's
band. #614 measured the crane-root, crane-spreading and quick-tier galleries
again with the distance band, and
[#613](https://github.com/avalonalex/senbazuru/issues/613) measures the rest.
