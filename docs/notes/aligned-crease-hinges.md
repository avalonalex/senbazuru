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

So a caller that knows only which way the paper should go cannot choose the
sign either: "towards +z" is +180 against a stationary face lying top up and
−180 against one lying upside down. `prepareFlapToward` takes the side and
reads the sign from the first segment's stationary face, whose way up is its
placement applied to +z, not the winding of its ring. On the quarter fold
after its first step, one valley is travel +180 with edge 9 listed first and
−180 with edge 11 first, because face 0 beside edge 9 lies top up and face 3
beside edge 11 upside down.

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
