# Several creases, one hinge

Fold a square diagonally in half. Now bring one corner of the doubled
triangle to its opposite tip, turning both layers together. That second move
has one physical hinge, but each layer has its own material crease. In the
helmet fixture those are edges 10 and 12. They were perpendicular on the open
sheet; after the diagonal fold they occupy the same line in space.

`prepareFlapAlong` takes an explicit list of crease ids. Remove all those
edges from the graph whose nodes are paper faces and whose links are shared
edges, then follow the remaining links from the selected moving face. Every
removed crease must have moving paper on one side and stationary paper on
the other. Every segment must also lie on the same line in the **folded**
configuration. A missing segment leaves an alternate connection; an extra
segment can fail to separate the two sides. Neither selection describes the
requested rigid turn.

The first segment defines the supplied change in FOLD angle. FOLD measures
that angle against the adjacent faces' orientation, not a world axis (see
[the glossary](../glossary.md)). In the helmet's first doubled corner, edge
10 closes from 0° to +180°, while edge 12 closes from 0° to −180°. Its
stationary face is upside down and orients the hinge in the opposite direction.
Giving both edges +90° would tear the intermediate sheet, even though +180°
and −180° produce the same endpoint geometry. The operation reads each
stationary face's directed edge to derive the sign, then checks both a
midpoint and the endpoint against the one rigid hinge motion. Every requested
pose is re-folded and compared in the same way.

The three-move recipe runs with:

```bash
stack run senbazuru-material-study -- --helmet build/fold-material
```

The generated `checked-helmet/checks.json` records moving faces `[3,4,5]`,
then `[1,5]`, then `[2,3]`, using the recipe's reordered material pattern.
Each complete turn is resolved in one interval by the existing
[hinge-sweep checker](hinge-sweep-contact.md). Accepted contact orders pass
between moves alongside the angles. Distinct material vertices remain
distinct, and the two touching layers have no display displacement.

This extends selection along one fixed axis. It does not find a route or
coordinate creases on different axes. The checker still uses zero-thickness
geometry and floating-point interval bounds with numerical guards. Reversed
departure orders, unknown touching stacks and exhausted checks still refuse
the motion. The recipe's sampled length, shared-vertex, achieved-angle and
contact diagnostics supplement that whole-turn check; they do not replace it.

The sign rule also limits what a caller can ask for. Knowing only the
direction of a turn, towards +z or −z, does not give its travel, the change in
the first segment's FOLD angle. A positive change moves the face beside a
crease towards that face's own top, so a turn that sets the moving paper off
towards +z is +180 where the moving face lies top up and −180 where it lies
upside down. `prepareFlapToward` takes the direction and reads the sign from
the moving face beside each segment. Which way up a face lies is where its
placement, the rigid motion folding gives the face, sends +z, not the winding
of its ring. On the quarter fold after its first step, one turn towards +z is
travel +180 with edge 9 listed first and −180 with edge 11 first, because
face 1 beside edge 9 lies top up and face 2 beside edge 11 upside down.

Every segment's moving face is read, and the readings must agree. They do
whenever the moving paper lies on one side of the hinge line. They part when
it lies on both, because a turn lifts the paper on one side of its line and
lowers the paper on the other, and then the turn is refused. The first
version read the face held still beside the first segment instead. On an
open hinge the two faces beside a crease are one flat piece of paper and
give the same answer, but on a page turn, whose held faces lie on both sides
of the line, that reading depended on which crease was listed first.
