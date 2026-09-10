# Contact and order answer different questions

Put two square panels at heights `z = 0` and `z = -0.1`. They do not intersect,
so a collision check alone accepts them. But if the second panel was supposed to
stay above the first, the folded state is wrong. The study therefore keeps two
questions: do panel interiors cross, and do declared lower/upper pairs respect
their order? Beige and orange belong to the two sides of the paper; neither colour
identifies a layer.

The kite declares two flaps above its centre; the blintz declares four. Each panel
name is anchored by a point inside that panel on the original sheet. For example,
`[0.8, 0.1]` identifies the kite's lower-right flap even after it rotates and the
folding engine renumbers faces. No relative order is needed between flaps that do
not overlap. The relation is a partial order: `A < B` and `B < C` imply `A < C`,
while a cycle is contradictory. Coplanar contact means two surfaces occupy the
same plane; an overlapping patch then needs an order, but a shared edge does not.

For crossings, cut each convex polygon (one without inward dents) by the plane
of the other. Their cuts lie
on the same line. Overlapping intervals indicate an interior crossing only when
both polygons extend to both sides of the other's plane. This last condition
allows a shared crease to stay joined. Comparing the complete intervals catches
crossings that a vertex-only check would miss, including vertical flaps.

Order uses a different construction. Project the lower panel along the declared
direction, clip the upper polygon to that outline, and compare heights at every
corner of the clipped polygon. Height difference is linear, so its largest and smallest values occur
at those corners. Keeping the actual 3D corners matters: a vertical flap projects
to a line but its top and bottom still have different heights. If one panel is
vertical, the other can supply the height function; if both are, the order is
reported as unchecked.

The tests cover all three panel pairs in each kite state and all ten pairs in
each blintz state, including their 90° flaps. Closing all flaps to 180° permits
ordered contact. Folding them instead to −175° reports reversed orders despite
no interior crossings. The distance tolerance is `1e-7` on the unit sheet.
These reports inspect individual rigid, zero-thickness states. They neither
correct a failed pose nor prove the motion between states safe; those remain
separate work. The implementation and assumptions live in
[PanelContact](../../study/fold-material/PanelContact.hs).
