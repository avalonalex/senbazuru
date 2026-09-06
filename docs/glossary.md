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
| **Flat-foldable** | Of a crease pattern: it *can* be folded flat along exactly those creases. Cheap to rule out one vertex at a time, [NP-hard](notes/flat-foldability-is-hard.md) to decide for a whole sheet. |
| **Sector** | The wedge of paper between two creases that are next to each other around a vertex. Kawasaki's theorem is a statement about sector angles. |
| **Star** | Every crease meeting one vertex, in rotational order, with the sectors between them. What both flat-foldability theorems are computed from. See `Senbazuru.Origami.FlatFold`. |
| **Maekawa's theorem** | At a flat-foldable interior vertex, mountains minus valleys is ±2. See [notes/maekawa.md](notes/maekawa.md). |
| **Kawasaki's theorem** | A vertex's angles admit a flat fold exactly when its sectors alternate to zero. See [notes/kawasaki.md](notes/kawasaki.md). |
| **Big-Little-Big lemma** | A sector strictly smaller than both its neighbours is bounded by one mountain and one valley. The condition on the *arrangement* that the other two theorems miss. See [notes/big-little-big.md](notes/big-little-big.md). |
| **Base** | A standard intermediate shape many models start from — preliminary, waterbomb, bird, frog. |
| **Collapse** | Forming many creases at once rather than in sequence. How tessellations and most complex designs are actually folded. |
| **Fold arrow** | The curved mark saying which paper moves where. Drawn on the step *before* the fold. FOLD records none, so senbazuru subtracts one frame from the next — see `Senbazuru.Origami.Step`. |
| **Layer order** | Which face is on top of which, wherever a folded model overlaps itself. Stored as `faceOrders`, or worked out by `Senbazuru.Origami.Stacking` when the file has none. A model usually has several valid ones — the crane has five. See [notes/taco-taco.md](notes/taco-taco.md) and [notes/several-stackings.md](notes/several-stackings.md). |
| **Taco** | Two faces joined along an edge of a folded form that lie on the *same* side of it: the paper folded back on itself. Nothing may lie between them that runs across their fold line. |
| **Tortilla** | Two faces joined along an edge that lie on *opposite* sides of it: the paper continuing flat across the line. Nothing may pass through it. |
| **Visible region** | The part of one face a viewer can actually see: the face minus every face nearer the viewer that overlaps it. What a picture of a folded model is made of, rather than whole faces. See [notes/visible-regions.md](notes/visible-regions.md). |
| **Hidden-line removal** | Not drawing the edges that are behind paper. In a flat-folded model an edge survives exactly where the topmost face differs across it. |
| **Offset view** | A drawing that steps the layers of a folded model a little apart, so a stack that lands on one spot can be read as a stack. The picture a book uses where hidden-line removal has nothing to reveal — the quarter fold is four squares in exactly the same place. |
| **Layer number** | How many sheets deep a face sits: the longest chain of faces below it, not a count of what it covers. What an offset view steps each face by. See [notes/layer-numbers.md](notes/layer-numbers.md). |
| **Step** | One picture of a diagram sequence: the paper as it is, plus the instruction for reaching the next. Stored in FOLD as consecutive frames of `file_frames`. |
| **Figure** | One drawing on a page of several. `Senbazuru.Diagram.Layout` arranges figures at one shared scale, so a folded model is drawn smaller than the sheet it came from. |
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
| **Face ordering** | Which sheet of paper is on top where, stored in `faceOrders` as `[f, g, s]`. The sign is read against *`g`'s normal*, so it describes the paper and not the picture: turning it into a drawing order needs a viewing direction too. See [notes/layer-ordering.md](notes/layer-ordering.md). |

Every key with its type and our support status: [fold-reference.md](fold-reference.md).

## Geometry

| Term | Meaning |
| --- | --- |
| **Face** | A region of paper bounded by edges — a polygon. |
| **Winding** | The direction a face's vertices are listed in. FOLD specifies counterclockwise, which would define the face's normal and therefore which side is up — but real files disagree, so senbazuru does not trust the stated winding. Filling does not care; anything needing a normal must compute the orientation. |
| **Normal** | The direction perpendicular to a face, pointing out of the side the winding defines. |
| **Rigid transform** | A motion that rotates and translates but never bends, stretches or scales. What a face undergoes when paper folds. See `Senbazuru.Geometry.Rigid`. |
| **Loop closure** | The condition that the turns round an interior vertex compose back to nothing. Only angles satisfying it describe paper that can actually fold; a spanning tree cuts the loops and so never tests it. See [notes/fold-angles-are-the-state.md](notes/fold-angles-are-the-state.md). |
| **Tear** | What a folding algorithm produces from angles that fail loop closure: the faces round a vertex disagree about where it goes, so the sheet is pulled apart. Plausible-looking and wrong. |
| **Orthographic projection** | Flattening 3D onto a page along parallel lines, with no perspective. Parallel edges stay parallel. |
| **Isometric** | An orthographic view whose direction has equal magnitude on all three axes, so all three foreshorten equally. |
| **Basis** | Three perpendicular unit vectors defining a view: right, up, and forward. |
| **Convex hull** | The smallest convex polygon containing a set of points. See [notes/convex-hull.md](notes/convex-hull.md). |
| **Convex** | Of a polygon: turns the same way at every corner, so it is the intersection of the half-planes of its edges. What lets two polygons be clipped against each other in one pass. See [notes/convex-clipping.md](notes/convex-clipping.md). |
| **Orientation predicate** | The test for whether a point lies left of, right of, or on a line. See [notes/robust-predicates.md](notes/robust-predicates.md). |
| **Half-plane** | Everything on one side of a line, boundary included. Clipping by one is the single step convex clipping and convex subtraction are both built from. |
| **Arrangement** | The subdivision of the plane produced by a set of segments: its **cells** are the regions no segment crosses. The usual route to drawing a folded model, and the one [notes/visible-regions.md](notes/visible-regions.md) avoids. |

## Graphs

| Term | Meaning |
| --- | --- |
| **Planar graph** | A graph drawn in the plane with edges meeting only at vertices. A crease pattern is one; edges that cross without a vertex are invalid. |
| **Degree** | How many edges meet at a vertex. |
| **Interior vertex** | A vertex away from the edge of the paper, with creases all the way round it. The theorems in [notes/maekawa.md](notes/maekawa.md) and [notes/kawasaki.md](notes/kawasaki.md) apply only to these. |
| **Face-adjacency graph** | Faces as nodes, shared creases as links. |
| **Spanning tree** | A way of reaching every node from a starting one without revisiting any. Has no cycles — which is the point, and often the catch. |
| **Connected component** | A piece of a graph with no edge leaving it. The layer solver's constraint graph usually falls into several, and they can be solved and counted separately. See [notes/several-stackings.md](notes/several-stackings.md). |
| **Half-edge / DCEL** | A structure giving constant-time "next edge around this face". See [notes/half-edge.md](notes/half-edge.md). |

## This project

| Term | Meaning |
| --- | --- |
| **Model space** | Coordinates as the FOLD file gives them. Mathematical convention: `y` increases upwards. |
| **Page space** | SVG user units. Screen convention: `y` increases *downwards*. Every model-to-page transform flips `y`. |
| **Two-unit rule** | Shape coordinates are in model units and are scaled to the page; stroke widths, dash lengths, arrowheads, type sizes and layer offsets are in page units and are not. See `Senbazuru.Diagram`. |
| **Extent** | The model-space region a page should show. Stored on a `Diagram` rather than derived, so every step of a sequence draws at one scale. |
| **Golden test** | A test pinning exact expected output in a committed file. Read the diff before accepting one. |
| **glTF / GLB** | The 3D file format `export` writes: glTF 2.0, in its self-contained binary container (`.glb`). A JSON description of meshes and materials, plus a binary buffer of positions and triangle indices. Y is up, where FOLD's is z. |
| **Z-fighting** | What a 3D viewer shows where two faces lie at exactly the same depth: a shimmer of both, because its depth buffer has no way to say which is in front. A flat-folded model is nothing but such faces, which is why the export gives paper a thickness. See [notes/paper-thickness.md](notes/paper-thickness.md). |
| **Thickness** | In the 3D export, how far each layer of a flat-folded model is lifted above the one below it: the layer number times a step, a thousandth of the model by default. Not a property of the paper in the file, which has none. |
| **Primitive** | glTF's unit of drawing: one list of triangles with one material. The export writes two per model, one for each side of the paper. |
| **Watertight** | Of a mesh: every edge shared by exactly two triangles, so it encloses a volume. The export is deliberately not — a folded sheet is a surface, and its faces are lifted to different heights. |
| **Rigid origami** | Folding in which every face stays flat and only the creases bend, so the paper is a mechanism of rigid plates. What the folding computes, and what the last steps of a crane are not quite. |
| **Ear clipping** | Triangulating any simple polygon by repeatedly cutting off a corner whose triangle contains no other vertex. Not built: the export fans convex faces and refuses the rest. |
