# Touching at the end of a checked turn

Fold a square in half. Its two panels are separate during the turn, but lie
on one another at 180°. A check demanding a positive gap cannot accept that
last state, however small its time intervals become. Skipping the last
interval would leave exactly the part we want checked unexamined.

For one fixed hinge, there is a simpler geometric argument. Take the plane
of a stationary triangle and require the hinge to lie in it. If a rotating
corner also ends in that plane, its signed distance from the plane is
`b * sin(theta - thetaEnd)`. Here `b` is the rate of change of distance per
radian at the endpoint. Over a half-turn or less, the sine has no zero in
the interior. When every corner away from the hinge has the same nonzero
sign, the whole moving triangle stays on one side. No time sampling is
needed for this particular pair. Other pairs still need their own checks.

`HingeSweep.checkSweepWithFlatEndpoints` uses this argument at either end.
It also checks the boundaries on the hinge: a permanent shared edge must
have shared material ids in this endpoint-only entry point. The separate
[stack rule](free-edges-on-a-hinge.md) can support an unjoined boundary.
Merely sharing a corner does not exempt a pair.
An overlapping endpoint records the stationary triangle, moving triangle and
side. Splitting a face into triangles sharing its first corner (a fan)
preserves its [winding](../glossary.md), so `Flap` can
translate these signs directly into FOLD `faceOrders`. Reopening must agree
with the given initial order; absent orders let departure select the unknown
side. The returned surface carries these orders into FOLD, SVG and both glTF
scenes, without moving the layers apart. The strict `checkSweep` entry point
remains available to callers that do not carry endpoint layer information.

The computation is numerical. On the normalized unit sheet, `64 * 2^-52`
(about `1.42e-14`) recognizes a rounded endpoint in the same plane: `sin(pi)` is about
`1.22e-16`, not exactly zero in floating-point arithmetic. This is a stated
precision limit, not a proof for arbitrarily small gaps. The magnitude of `b` must
still exceed the existing `1e-10` separation guard, and a small overshoot
outside the rounding allowance is refused. No positions are snapped and no
short time interval is omitted.

The [demo](../usage.md#checked-flap-motion) closes a fold from 0° to 180° and
reopens it. Each motion clears in one interval check, with maximum relative
edge-length error `1.11e-16` across its four saved states. Tests cover either sign and moving side, reverse order notation,
scaled and rotated geometry, small overshoots, separate hinge seams, and
departure through the resting layer. A contact plane away from the hinge and
coupled crease motion remain outside this rule. Persistent contact within a
rigid stack is covered by the separate [common-motion rule](moving-touching-layers.md).
