# A reference pose can supply contact order

The previous opposing-flap control declared three relationships: the middle
panel below both flaps, and the left flap below the right. We can recover those
relationships from a suitable starting shape. Set the crease angles to 145°
and 125°: the flaps overlap when projected along the model's vertical direction,
but remain separated in 3D. Their heights tell us their order without a pair
list. The older 145° / 105° pose does not yet have overlapping flap projections,
so it cannot supply the same information by this method.

`SurfaceContact.overlapCandidates` scans triangles belonging to different
source panels, meaning the original regions between crease lines. Projected
bounding boxes cheaply discard impossible overlaps; clipping decides the
remaining cases. A shared edge or corner alone supplies no order. An upright
flap is different: its projection is a line, but clipping its actual 3D
triangle can retain a patch with positive area and distinct endpoint heights.
When both triangles are upright and their projected boxes meet, the scan
conservatively reports a comparison that this direction cannot resolve.

`ContactDiscovery.discoverReference` groups these triangle candidates by source
panel and examines their minimum and maximum height differences. If every
measurable overlap agrees which panel is above, that gives a relationship.
Opposite signs indicate crossed or inconsistent reference panels; overlapping
coplanar panels are ambiguous. Both are errors. A cycle of inferred
relationships is also refused by the existing directional-order model.
The input is mesh, ownership, direction and numerical clearance; no authored
lower/upper pairs are consumed.

The learned order belongs to the reference, not to each candidate shape. If we
re-inferred it after two panels crossed, the result could simply bless their
new, reversed order. Instead, `discoveredContacts` preserves the reference
relationships and rescans current geometry. A newly overlapping pair is allowed
only when those relationships already determine its order, including through
intermediate panels: A below B and B below C implies A below C. Otherwise the
query returns `NewContactPair`. The solver rejects such trial steps, and a
stalled correction remains unconverged. This is deliberately more restrictive
than inventing a folding history.

`ReferenceContact` hides both its constructor and record fields. Its public
accessors are ordinary functions: exporting a Haskell record field would also
allow updates that replace the learned relationships while retaining the old
prepared constraints. The type therefore keeps the history and constraints
together after preparation.

Run `stack run senbazuru-material-study -- --bending build/fold-material` and
choose **Opposing flaps · discovered contact**. On the 24-triangle unit sheet,
the reference scan finds 46 triangle overlaps and learns the three expected
panel relationships. The corrected endpoint has 78 overlaps, still governed by
those same relationships. It settles in 140 numerical iterations, reaches
approximately 160.06–160.12° / 139.47–139.48°, and has maximum relative edge error
`8.80 × 10⁻⁸`. All 276 independent triangle-pair checks pass. The unconstrained
endpoint reaches 150° / 150° but has six crossing pairs and eight reversed
orders. On the same reference pose, the discovered and authored corrections
produce identical positions. The six earlier gallery runs retain their previous
meshes and measurements.

This is discovery along a fixed direction from a suitable reference, not general
contact-history inference. It cannot start from an ambiguous flattened stack,
learn an initially unrelated pair's order during a fold, or discover contact
inside one bent source panel. It does not certify continuous motion between
iterates. The unchanged `10⁻⁶` numerical clearance between unjoined panels is
still separate from physical thickness. The [correction note](ordered-flap-contact.md)
explains that margin and the solver. This increment is tracked in
[#156](https://github.com/avalonalex/senbazuru/issues/156).
