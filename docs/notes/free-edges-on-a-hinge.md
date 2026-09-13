# A free edge can rest on a crease without becoming joined to it

Divide a unit square into three equal vertical strips. Fold the right third
onto the middle third. Its original outer edge at material x = 1 now lies at
spatial x = 1/3, exactly on the next crease. Lifting the middle strip carries
both layers, while that outer edge stays on the rotation axis. In the
[flap demo](../usage.md#checked-flap-motion), free corners 3 and 4 coincide
with crease corners 1 and 6. All eight original vertices remain distinct.

The [common-motion rule](moving-touching-layers.md) already keeps the two
moving layers together. The new pair to check is the upper layer against the
stationary left strip: their motions differ, and they do not share material
along the hinge. Treating every coincident edge as a crease would erase that
distinction and permit an unrelated seam without any explanation.

`HingeSweep.checkSweepWithRigidContacts` uses the declared touching partner
as evidence. That partner must have shared material with the opposite
triangle on the hinge, covering the entire contact between the free edge and
that triangle. Splitting a panel into triangles can leave a triangle meeting
the hinge at only one corner; a shared corner supports only that point, not
an overlapping edge. The same rule works when the stack stays still and the
opposite flap moves. It does not infer undeclared stack partners.

This only permits the boundary contact. The stationary triangle's plane must
contain the rotation axis, its interior must lie on one side of that axis,
and the turning triangle's interior must stay strictly on one side of the
plane. For flat endpoints, the existing half-turn sine argument supplies
that check; between open poses, bounded projection ranges do it. An allowed
hinge edge therefore does not excuse a triangle passing through the paper.
New flat overlaps still produce approach/departure orders, and reopening
still has to respect them.

The generated lift and lowering each clear in one interval check. Their
maximum relative material-edge error is `5.55e-16`; all saved states retain
order `[2,1,1]`. The equal-width opposing stack still hits the left flap
during a full turn, with both moving layers reported at progress `0.125`.
That is a collision witness, not a first-impact time.

The free edge's distance from the hinge uses the same `64 * 2^-52` allowance
as endpoint coplanarity, on normalized coordinates (about `1.42e-14` of the
sheet's span). No positions or material ids are changed by this rule. It is
a numerical zero-thickness model, not a claim about arbitrarily tiny gaps.
Sliding along a contact, bending, and several creases moving together remain
separate work. The strict sweep entry points retain their previous policy.
