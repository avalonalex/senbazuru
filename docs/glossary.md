# Glossary

Every term the docs and the code assume, in one place. Grouped by where it comes
from, because "mountain fold" and "spanning tree" are borrowed from very
different traditions and it helps to know which is which.

For the ideas rather than the definitions, start with
[fold-primer.md](fold-primer.md).

## Origami

| Term | Meaning |
| --- | --- |
| **Crease pattern** | The flat, unfolded sheet with every crease marked. Its coordinates are already page coordinates, so drawing one needs no simulation. |
| **Folded form** | The same graph with vertices moved to where they end up after folding. Often 3D — but not always: the traditional crane folds flat, so its folded form is 2D. |
| **Mountain fold** (`M`) | A crease that rises towards the viewer. Drawn dash-dot-dot. |
| **Valley fold** (`V`) | A crease that sinks away from the viewer. Drawn dashed. |
| **Fold angle** | The dihedral angle at a crease, in degrees, from −180 to 180. Negative is a mountain, positive a valley, and ±180 means folded flat back on itself. |
| **Flat-folded** | Folded so the whole model lies in a plane. Every fold angle is exactly ±180°. |
| **Base** | A standard intermediate shape many models start from — preliminary, waterbomb, bird, frog. |
| **Collapse** | Forming many creases at once rather than in sequence. How tessellations and most complex designs are actually folded. |
| **Yoshizawa–Randlett** | The standard diagram notation: solid paper edges, dashed valleys, dash-dot-dot mountains. The dashes mark folds still to be made, so a folded form is drawn with solid edges only. See `Senbazuru.Diagram.Style`. |
| **Assignment colour convention** | The *other* notation, used by on-screen editors: red mountains, blue valleys, uniform line weight. We target the printed-book one. |
| **Huzita–Hatori axioms** | The seven ways a single fold can be specified by aligning points and lines. See [notes/huzita-hatori.md](notes/huzita-hatori.md). |

## The FOLD format

| Term | Meaning |
| --- | --- |
| **Frame** | One state of the paper. A multi-frame file is how a diagram sequence is stored. |
| **Border** (`B`) | The edge of the paper. Not a fold. |
| **Flat** (`F`) | A crease line that exists but is not folded. |
| **Unassigned** (`U`) | A crease whose direction is not yet decided. |
| **Cut** (`C`) / **Join** (`J`) | A slit in the paper / two faces that are really one piece. |
| **Face ordering** | Which sheet of paper is on top where, stored in `faceOrders`. See [notes/layer-ordering.md](notes/layer-ordering.md). |

Every key with its type and our support status: [fold-reference.md](fold-reference.md).

## Geometry

| Term | Meaning |
| --- | --- |
| **Face** | A region of paper bounded by edges — a polygon. |
| **Winding** | The direction a face's vertices are listed in. Counterclockwise in FOLD, which is what defines the face's normal and therefore which side is up. |
| **Normal** | The direction perpendicular to a face, pointing out of the side the winding defines. |
| **Rigid transform** | A motion that rotates and translates but never bends, stretches or scales. What a face undergoes when paper folds. |
| **Orthographic projection** | Flattening 3D onto a page along parallel lines, with no perspective. Parallel edges stay parallel. |
| **Isometric** | An orthographic view whose direction has equal magnitude on all three axes, so all three foreshorten equally. |
| **Basis** | Three perpendicular unit vectors defining a view: right, up, and forward. |
| **Convex hull** | The smallest convex polygon containing a set of points. See [notes/convex-hull.md](notes/convex-hull.md). |
| **Orientation predicate** | The test for whether a point lies left of, right of, or on a line. See [notes/robust-predicates.md](notes/robust-predicates.md). |

## Graphs

| Term | Meaning |
| --- | --- |
| **Planar graph** | A graph drawn in the plane with edges meeting only at vertices. A crease pattern is one; edges that cross without a vertex are invalid. |
| **Degree** | How many edges meet at a vertex. |
| **Interior vertex** | A vertex away from the edge of the paper, with creases all the way round it. The theorems in [notes/maekawa.md](notes/maekawa.md) and [notes/kawasaki.md](notes/kawasaki.md) apply only to these. |
| **Face-adjacency graph** | Faces as nodes, shared creases as links. |
| **Spanning tree** | A way of reaching every node from a starting one without revisiting any. Has no cycles — which is the point, and often the catch. |
| **Half-edge / DCEL** | A structure giving constant-time "next edge around this face". See [notes/half-edge.md](notes/half-edge.md). |

## This project

| Term | Meaning |
| --- | --- |
| **Model space** | Coordinates as the FOLD file gives them. Mathematical convention: `y` increases upwards. |
| **Page space** | SVG user units. Screen convention: `y` increases *downwards*. Every model-to-page transform flips `y`. |
| **Extent** | The model-space region a page should show. Stored on a `Diagram` rather than derived, so every step of a sequence draws at one scale. |
| **Golden test** | A test pinning exact expected output in a committed file. Read the diff before accepting one. |
