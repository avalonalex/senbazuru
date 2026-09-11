# An open fold can reuse the flat visibility renderer

Imagine a long panel whose height rises from zero to ten, and a small flap
above its low end at height two. The long panel's centre is higher than the
flap's centre, but the flap covers that end when seen from above. Sorting by
centres would paint the wrong paper there.

Instead, project both panels onto the page and compare depths only where
their shadows overlap. A **panel** is one planar piece of the sheet; an
**orthographic projection** keeps parallel lines parallel, as explained in
the [glossary](../glossary.md). Depth on each panel is a linear function of
position on the page. The difference between two depths is also linear, so
checking every corner of the overlap determines which panel is nearer
throughout it. If that order reverses inside the overlap, this path declines:
the panels intersect and cannot be painted by one relation for that pair.

These viewing relations let `Render.Projected` build a temporary flat frame
of the shadows and pass it to `Origami.Visible`. The latter already subtracts
covered regions, removes buried creases, and groups fills by the side of the
paper. The temporary frame is a drawing calculation. It is never exported as
material, and no vertex in the actual folded frame is moved to separate layers.

Coplanar panels have equal depths: geometry cannot say which is on top.
Their `faceOrders` supply that information, with the sign interpreted against
the second face's normal. Looking underneath reverses the viewing relation.
The bird study expands its named order chains, then exports only relations
between panels that share an area in the same plane. Separated panels obtain
their viewing order from geometry. The distinction is the difference between
describing paper and describing one camera's view of it.

The bird sequence is the first regression fixture for this boundary. Its
sixteen ordinary FOLD frames retain thirteen material vertices and sixteen
panels, with the study's fixed reference frame and achieved crease angles.
The source endpoint marks some guides flat even though they bend earlier;
their intermediate assignments become mountain or valley so those real folds
remain visible. See [the two-petal construction](two-petals.md).

`BirdSequenceSpec` compares the exported geometry with the checked study,
tests visible regions for unwanted overlaps in three views, and pins two SVG
pages. `ProjectedSpec` checks the sloping-panel example, covered crease
segments, reversed winding, underside order and intersecting panels. These
tests supplement the study's material and contact checks; they do not replace
them with a plausible picture.

This path covers convex planar panels. An edge-on panel contributes no fill
and can be omitted when its edges are also carried by surviving neighbours.
Free edge-on outlines, unresolved coplanar ties, nonplanar or concave panels,
and crossing depths retain the older fallback. This is visibility at supplied
states, not a general folding-sequence solver or continuous collision proof.
