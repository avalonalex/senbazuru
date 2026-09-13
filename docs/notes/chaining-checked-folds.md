# Carry the accepted paper into the next fold

Fold the four corners of a square to its centre: that is a blintz base.
Each corner can turn about one fixed crease while the rest of the sheet
stays still. The [demo](../usage.md#checked-blintz-sequence) follows those four
turns with reopening the first corner. Each is accepted by the library's
[flap operation](checked-flap-operation.md), including its full angular interval.

The endpoint is more than a list of positions. It also records crease angles
and which touching layer lies on which side. The next turn copies those
angles and orders onto the original material pattern, then folds it again.
Copying the folded positions into that pattern would describe different
paper; re-solving its layer order could silently choose a different stack.

There is another boundary to check: two individually accepted turns can
disagree about where the whole model sits. `foldFrameWith` anchors its first
face. In the original blintz fixture that is a corner, so folding that corner
with `flapAt` holds the centre still, while independently refolding the same
angles holds the corner still. Both shapes satisfy the angles, but joining
them would insert a rotation of the whole sheet. The recipe puts the central
face first before any folding and keeps that material numbering throughout.
It still compares each accepted endpoint with the next start, refusing a
position change beyond `1e-12` of the sheet's span.

In this route the four corners rest on different regions of the centre face,
so no order between the corners is needed. Their tips meet at one position
but retain four distinct material ids. Reopening removes only that corner's
contact with the centre; the other three orders survive. Tests measure the
signed angles, within-panel distances, shared-vertex placements and static
contact at eleven points per move, and compare the finished shape with the
existing fixture after aligning its centre. Those sampled measurements
check exported states; the separate interval check covers the turns between
them. The result remains numerical zero-thickness geometry, with the
same [endpoint allowances](flat-flap-endpoints.md) as the underlying operation.

This is a complete checked route for one base, not a general authoring
language. A physical hinge made of several crease segments, or a move that
needs several angles to change together, requires a broader operation.
