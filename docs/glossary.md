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
| **Plastic hinge** | What a pressed crease physically is: a strip of broken fibres a few thicknesses wide that bends far more easily than the paper either side of it. Once formed, more force barely tightens the fold. See [notes/a-crease-is-a-hinge.md](notes/a-crease-is-a-hinge.md). |
| **Rest angle** | The angle a creased sheet's two panels settle at when nothing is loading them. Set by the material's yield stress, independent of thickness, and not zero. See [notes/a-crease-is-a-hinge.md](notes/a-crease-is-a-hinge.md). |
| **Fold angle** | The dihedral angle at a crease, in degrees, from −180 to 180. Negative is a mountain, positive a valley, and ±180 means folded flat back on itself. |
| **Flat-folded** | Folded so the whole model lies in a plane. Every fold angle is exactly ±180°. |
| **Flat-foldable** | Of a crease pattern: it *can* be folded flat along exactly those creases. Cheap to rule out one vertex at a time, [NP-hard](notes/flat-foldability-is-hard.md) to decide for a whole sheet. |
| **Sector** | The wedge of paper between two creases that are next to each other around a vertex. Kawasaki's theorem is a statement about sector angles. |
| **Star** | Every crease meeting one vertex, in rotational order, with the sectors between them. What both flat-foldability theorems are computed from. See `Senbazuru.Origami.FlatFold`. |
| **Maekawa's theorem** | At a flat-foldable interior vertex, mountains minus valleys is ±2. See [notes/maekawa.md](notes/maekawa.md). |
| **Kawasaki's theorem** | A vertex's angles admit a flat fold exactly when its sectors alternate to zero. See [notes/kawasaki.md](notes/kawasaki.md). |
| **Big-Little-Big lemma** | A sector strictly smaller than both its neighbours is bounded by one mountain and one valley. The condition on the *arrangement* that the other two theorems miss. See [notes/big-little-big.md](notes/big-little-big.md). |
| **Base** | A standard intermediate shape many models start from — preliminary, waterbomb, bird, frog. |
| **Flap** | A part of the sheet that can be lifted or folded over. It may contain several faces and several layers; it is not necessarily one polygon. |
| **Book fold** | Folding a sheet in half so two opposite edges meet. |
| **Cupboard fold** | Folding two opposite edges to meet at the centre line, like a pair of cupboard doors. Also called a gate fold. |
| **Squash fold** | Opening a doubled flap into a pocket, then pressing it flat along a different pair of creases. Four squash folds followed by four petal folds turn a square base into a frog base. |
| **Rabbit-ear fold** | Gathering a triangular region along its angle bisectors into a pointed flap, then laying that flap to one side. Two make the traditional fish base. See [notes/fish-and-bird-endpoints.md](notes/fish-and-bird-endpoints.md). |
| **Petal fold** | Lifting a flap while folding its sides inward to make a longer, narrower flap. Applying it to both sides of a square base makes a bird base. See [notes/fish-and-bird-endpoints.md](notes/fish-and-bird-endpoints.md). |
| **Puff** | Expanding a folded pocket into a three-dimensional body, often by blowing into it, as with a crane's body or a waterbomb. Its motion can involve opening creases and bending panels. A prescribed opening and a pressure-driven simulation are different ways to model it; see [notes/connected-paper-surface.md](notes/connected-paper-surface.md). |
| **Waterbomb** | The traditional paper balloon: folded flat, then puffed into something close to a cube. Distinct from the *waterbomb base* it is folded from, which is a base in the sense above. |
| **Collapse** | Forming many creases at once rather than in sequence. How tessellations and most complex designs are actually folded. |
| **Through all layers** | An instruction creasing every layer of paper under the line, as against one that catches only the near ones. On the flat sheet it is one crease per face the line crosses, and their kinds alternate — see [notes/creasing-through-layers.md](notes/creasing-through-layers.md). |
| **Fold arrow** | The curved mark saying which paper moves where. Drawn on the step *before* the fold. FOLD records none, so senbazuru subtracts one frame from the next — see `Senbazuru.Origami.Step`. |
| **Layer order** | Which face is on top of which, wherever a folded model overlaps itself. Stored as `faceOrders`, or worked out by `Senbazuru.Origami.Stacking` when the file has none. A model usually has several valid ones — the crane has five. See [notes/taco-taco.md](notes/taco-taco.md) and [notes/several-stackings.md](notes/several-stackings.md). |
| **Taco** | Two faces joined along an edge of a folded form that lie on the *same* side of it: the paper folded back on itself. Nothing may lie between them that runs across their fold line. |
| **Tortilla** | Two faces joined along an edge that lie on *opposite* sides of it: the paper continuing flat across the line. Nothing may pass through it. |
| **Visible region** | The part of one face a viewer can actually see: the face minus every face nearer the viewer that overlaps it. What a picture of a folded model is made of, rather than whole faces. See [notes/visible-regions.md](notes/visible-regions.md). |
| **Hidden-line removal** | Not drawing the edges that are behind paper. In a flat-folded model an edge survives exactly where the topmost face differs across it. |
| **Offset view** | A drawing that steps the layers of a folded model a little apart, so a stack that lands on one spot can be read as a stack. The picture a book uses where hidden-line removal has nothing to reveal — the quarter fold is four squares in exactly the same place. |
| **Hair** | The distance below which two points on a model are the same point, and a **speck** is the same for an area. Both are relative to the model's size — a hair is a billionth of it — so they are numbers a `.cp` on a 400-unit square and a unit square do not share. `Senbazuru.Origami.Flat`'s `sheetHair` and `sheetSpeck`. |
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

## The other two formats

| Term | Meaning |
| --- | --- |
| **`.cp`** | The crease-pattern format Orihime and Oriedita write: one crease to a line of text, as `type x1 y1 x2 y2`. No vertices, no faces, no metadata. |
| **`.opx`** | ORIPA's crease-pattern format: the same list of creases serialised as a Java bean in XML. |
| **Auxiliary line** | A line drawn on a crease pattern as a construction guide and not folded when the model is. Both formats have a code for it; FOLD calls the same thing `F`. |
| **Segment list** | A crease pattern given as loose line segments, with the shared endpoints left for the reader to match up. What both formats above are, and the reason reading one needs a tolerance. See [notes/cp-and-opx.md](notes/cp-and-opx.md). |

## Geometry

| Term | Meaning |
| --- | --- |
| **Face** | A region of paper bounded by edges — a polygon. |
| **Material coordinates** | A point's position on the original, unfolded sheet. They identify the same piece of paper as its current position changes during folding; two touching layers can occupy the same current position while having different material coordinates. |
| **Winding** | The direction a face's vertices are listed in. FOLD specifies counterclockwise, which would define the face's normal and therefore which side is up — but real files disagree, so senbazuru does not trust the stated winding. Filling does not care; anything needing a normal must compute the orientation. |
| **Normal** | The direction perpendicular to a face, pointing out of the side the winding defines. |
| **Rigid transform** | A motion that rotates and translates but never bends, stretches or scales. What a face undergoes when paper folds. See `Senbazuru.Geometry.Rigid`. |
| **Loop closure** | The condition that the turns round an interior vertex compose back to nothing. Only angles satisfying it describe paper that can actually fold; a spanning tree cuts the loops and so never tests it. See [notes/fold-angles-are-the-state.md](notes/fold-angles-are-the-state.md). |
| **Tear** | What a folding algorithm produces from angles that fail loop closure: the faces round a vertex disagree about where it goes, so the sheet is pulled apart. Plausible-looking and wrong. Watching the vertices is not enough on its own — two faces across a crease share only that crease's endpoints, which sit on its rotation axis and agree however the crease is folded, so a loop the walk closed by turning *nothing* leaves no vertex disagreeing. `Senbazuru.Origami.Folding` therefore also checks that each crease's own angle came out. |
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
| **Z-fighting** | What a 3D viewer shows where two faces lie at exactly the same depth: a shimmer of both, because its depth buffer has no way to say which is in front. The default glTF scene removes buried coplanar regions; the complete inspection scene retains them. See [notes/visible-paper-mesh.md](notes/visible-paper-mesh.md). |
| **Thickness** | The physical distance between the two sides of real paper. An optional property in the material surface, in model units; current rendering and contact checks do not use it to displace the sheet. |
| **Primitive** | glTF's unit of drawing: one list of triangles with one material. The export writes up to two per scene, one per paper colour; an unused colour needs no primitive. |
| **Watertight** | Of a mesh: every edge shared by exactly two triangles, so it encloses a volume. A connected sheet with a boundary need not be watertight: it is a surface, not a closed volume. Rendering both sides does not make it a solid. |
| **Rigid origami** | Folding in which every face stays flat and only the creases bend, so the paper is a mechanism of rigid plates. What the folding computes, and what the last steps of a crane are not quite. |
| **Ear clipping** | Triangulating any simple polygon by repeatedly cutting off a corner whose triangle contains no other vertex. Not built: the export fans convex faces and refuses the rest. |
