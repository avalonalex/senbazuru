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
| **Flap root** | The line a flap turns from: the line furthest from its tip at which a hinge still creases only the flap's own paper. Past it, the hinge would also crease the paper beside the flap, which would have to move with it. Found from the folded outline; see [notes/flap-roots.md](notes/flap-roots.md). |
| **Book fold** | Folding a sheet in half so two opposite edges meet. |
| **Pre-crease** | Folding along a line and unfolding again, so that the paper keeps a crease there, flat, until a later move uses it. Instruction books' word for this fold. A sequence source writes it `pre-crease` (also `precrease` or `fold and unfold`), and it is one move, whose only lasting change is the crease. See [why a pre-crease can stay flat](notes/precreases-and-target-states.md). |
| **Page turn** | Turning a flap from one side of a line to the other, like the page of a book. The flap is joined to paper on both sides of the line, so the turn opens one crease and closes another. Not a page of drawings, and not turning the whole model over. |
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
| **Hair** | The distance below which two points on a model are the same point, and a **speck** is the same for an area. Both are relative to the model's size — a hair is a billionth of it — so they are numbers a `.cp` on a 400-unit square and a unit square do not share. `Senbazuru.Origami.Flat`'s `sheetHair` and `sheetSpeck`. A view of an open fold measures its speck against the picture rather than the model, because the areas it judges are the picture's (`Senbazuru.Render.Shadows`). |
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
| **State rule** | How every frame a fold sequence writes letters its creases: by the angle the crease is at now, not the direction it was made in. A mountain below −10⁻¹⁰ degrees, a valley above +10⁻¹⁰, and `F` between, with the angle then written as exactly 0; `B`, `C` and `J` keep their letters, and `U` is never written. So a valley folded and laid flat again is written `F`. See `Fold.Query.assignmentAtRest`. |
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
| **Panel** | A region of paper between material creases. A bending study can subdivide one panel into many numerical triangles without treating their internal edges as additional creases. |
| **Rest angle** | The angle a crease spring prefers when other constraints do not oppose it. The achieved angle can differ; a rest angle is not an exact hold. |
| **Bending stiffness** | How strongly the model resists a change in angle. The studies use illustrative values, not measurements of a particular paper. Crease and panel springs have different geometric weights; see [notes/wing-root-holds.md](notes/wing-root-holds.md). |
| **Numerical equilibrium** | A solver state whose full proposed correction is below a stated tolerance and whose correction equations have passed their residual check. The material studies still check lengths, contact and holds separately; solver equilibrium alone does not certify valid paper. |
| **Winding** | The direction a face's vertices are listed in. FOLD specifies counterclockwise, which would define the face's normal and therefore which side is up — but real files disagree, so senbazuru does not trust the stated winding. Filling does not care; anything needing a normal must compute the orientation. |
| **Normal** | The direction perpendicular to a face, pointing out of the side the winding defines. |
| **Rigid transform** | A motion that rotates and translates but never bends, stretches or scales. What a face undergoes when paper folds. See `Senbazuru.Geometry.Rigid`. |
| **Loop closure** | The condition that the turns round an interior vertex compose back to nothing. Only angles satisfying it describe paper that can actually fold; a spanning tree cuts the loops and so never tests it. See [notes/fold-angles-are-the-state.md](notes/fold-angles-are-the-state.md). |
| **Tear** | What a folding algorithm produces from angles that fail loop closure: the faces round a vertex disagree about where it goes, so the sheet is pulled apart. Plausible-looking and wrong. Watching the vertices is not enough on its own — two faces across a crease share only that crease's endpoints, which sit on its rotation axis and agree however the crease is folded, so a loop the walk closed by turning *nothing* leaves no vertex disagreeing. `Senbazuru.Origami.Folding` therefore also checks that each crease's own angle came out. |
| **Orthographic projection** | Flattening 3D onto a page along parallel lines, with no perspective. Parallel edges stay parallel. |
| **Isometric** | An orthographic view whose direction has equal magnitude on all three axes, so all three foreshorten equally. |
| **Basis** | Three perpendicular unit vectors defining a view: right, up, and forward. |
| **Convex hull** | The smallest convex polygon containing a set of points. See [notes/convex-hull.md](notes/convex-hull.md). |
| **Chord** | The straight line between two points. On the flat sheet it is the way along the paper only while it stays on the paper, which is why the no-stretch floor takes only such pairs; between two points of bent paper it is shorter than the way along the paper. |
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

## Fold sequences

The words of the language for writing down how a model is folded. Only the ones
the docs already use are here; the rest of the language's vocabulary is in
[PRDs/glossary-additions.md](../PRDs/glossary-additions.md) until the code that
needs each word exists.

| Term | Meaning |
| --- | --- |
| **Anchor** | In a fold sequence, the point of paper that stays still while the rest moves, so that a model does not wander across the page from one picture to the next. A material point, not a face, because faces are renumbered when a crease cuts them. By default the vertex mean (the average of the corners) of the sheet's largest face. See `Senbazuru.Sequence.Run`. |
| **Core move** | A move as a run performs it, with no shorthand left: no `let` and no line known only by a name. A *pre-crease* is one core move. *Elaboration* makes them; each remembers the move the author wrote. See `Senbazuru.Sequence.Elaborate`. |
| **Elaboration** | The pass between checking a fold sequence and running it, which rewrites its shorthand as *core moves*. It needs no paper and cannot fail. |
| **Fold sequence** | The list of instructions that takes a sheet of paper to a model, as a `Sequence` value. It can be written two ways, as Haskell or as a *sequence source*, and both make the same value. Not the same thing as a **step** sequence in a FOLD file, which is the *output*: consecutive frames, one per picture. See `Senbazuru.Sequence.Syntax`. |
| **Fold state** | The paper between two moves of a run: the *working pattern* and the *anchor*, so far. The runner keeps it to itself; a reader of a run gets *move records*. See `Senbazuru.Sequence.Run`. |
| **Let** | `let NAME = …` in a fold sequence: a name for a point or a line, standing for it wherever it is used and worked out afresh each time. It pins nothing to the paper; a `mark` does that, naming the paper that is at a point when the mark is made. |
| **Move** | One thing done to the paper, or to how it is shown: a fold, an unfold, turning the model over. A **step**, the instruction for one picture, holds one or more moves, because "fold and unfold both diagonals" is one picture of two moves. |
| **Move record** | What a run hands back for each move, every move but `let`, `not modelled` and `expect refused`: the folded surface just before the move and just after it and the check that the move could be made, and for a turn about a hinge, the creases it turned about, the paper that moved and the face held still. The material study, the page of steps and the animated export read records rather than the frames a run writes. Its surfaces are *unpresented*: as folding computed them, never turned over or spun for a page. See `Senbazuru.Sequence.Record`. |
| **Near miss** | A point typed as numbers, such as `(1/2, 0.207)`, that lies near a vertex without being on it: within a thousandth of a sheet length, and outside the sheet's tolerance. A run refuses it and names the vertex, because the author almost certainly meant the vertex and rounded it. A typed point within the tolerance is taken as the vertex. See `Senbazuru.Sequence.Resolve`. |
| **Presentation** | How a fold state is shown to the reader: the rigid motion from where the paper is folded to where the reader sees it. `turn over` and `rotate` change it and move no paper, each about an axis through the model's own middle as shown; the states a run writes are presented, so a state after a turn-over is written showing the paper's other side, and one after a rotate turned on the page. A presentation is always a *proper rotation*, never a mirror, which would show a different model. See `Senbazuru.Sequence.Run`. |
| **Reader's side** | The side of the model facing the reader, model +z of the model as shown: the coloured side until a turn-over, which a rotate leaves as it is. `valley` (or `in front`) sends paper towards it and `mountain` (or `behind`) away from it, so after a turn-over the same word sends paper the other way on the sheet. |
| **Sequence file** | The FOLD file a run writes: a key frame holding only the file's metadata, then every state the run reached as `file_frames`: state 0 the sheet laid flat, and one state for each step but one whose moves were all `expect refused`. Each frame follows the *state rule*, and is titled with the caption of the step that leaves it. An ordinary FOLD file: `render --steps` draws it and `export --frame` takes a state from it, counting the key frame as frame 0, so state k is `--frame k+1`. See `Senbazuru.Sequence.Write`. |
| **Sequence source** | The text file, `.foldseq`, in which an author writes a fold sequence. A program, not an input format: it becomes FOLD only when it is run. See [architecture.md](architecture.md#layering-rules). |
| **Sheet** | The paper a fold sequence starts from: a plain unit square, or the first frame of a FOLD file the source names. It is a second file, which is one of the two reasons a sequence source cannot be read the way a crease pattern is. |
| **Sheet length** | The unit a fold sequence names paper in: the sheet's bounding box has its south-west corner at (0, 0) and its longer side 1, whatever units the file uses. So `(1/2, 1/2)` is the centre of any square sheet. Not a *sheet unit*, which is the file's own unit. |
| **Working pattern** | The crease pattern a run folds: the sheet's creases cut at every crossing, vertices in material coordinates, each crease's angle and the layer orders written on it. A move changes only the angles and orders, and the pattern is folded afresh from them; folded coordinates never come back as material. A crease lying flat keeps the M or V it was made with, its *intent*. |

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
| **Paper screen** | The measurements written beside a gallery pose drawn as paper that say whether paper could take its shape: *principal strain*, the *no-stretch floor*, crossing pairs with their largest *reach-through*, *false-crease* turning, and, on the whole crane, two readings of the body core, the middle of the sheet that becomes the crane's body. Its head-to-tail length and how far it stays folded along the creases through the sheet's centre tell a *pod*, a body swung open about its spine with those creases still folded, from a *pillow*, whose centre is opened flat and lengthened. A pose passes with at most 1% strain (owner decision 16; 0.1% is reported beside it), a floor of at most 1 px at that strain, in pixels at its page's *page scale* (owner decision 30), and no false creases (PRD 11's targets); crossings are reported, not judged ([PRD 11](../PRDs/11-prd-refined-final-forms.md#1-the-paper-screen)). A pose that is not *made again* has its false creases judged on its own mesh, and the finer level *not measured*, which neither passes nor fails (owner decision 27). |
| **Principal strain** | A triangle's largest stretch and largest squash in any direction, measured against its flat material triangle. A triangle can stretch although none of its edges lengthens, so a check that only stops edges lengthening misses stretch. |
| **No-stretch floor** | Half the largest amount by which two material points are further apart in a pose than on the flat sheet. Paper cannot stretch, so every shape paper can take puts some point at least this far from where the pose puts it: a lower bound on the distance to every paper shape. The half is because the two points can share the correction. It holds after projection too. On a sheet that is not convex it is taken over the pairs whose straight line on the flat sheet stays on the paper, and a sheet with a slit is refused. See [notes/no-stretch-floor.md](notes/no-stretch-floor.md). |
| **False crease** | A join inside a panel (`J`) bent past a threshold (45° on a pose) where the pattern has no crease. Measured as the sum of length × angle over such joins, which stays the same for a fold and falls to zero for a curve sampled finely enough. The paper screen measures it on the pose's mesh and, where the pose is made again, with every triangle split into four. A bend narrower than the triangles keeps its sum like a fold until the mesh is fine enough to follow it ([notes/fold-or-curve.md](notes/fold-or-curve.md)). |
| **Shape sketch** | A pose built by placing vertices where the shape should be, rather than by folding or settling paper. It can look right and still be a shape no paper can take. The whole-crane gallery records the geometry level `as prescribed` in such a pose's GLB, and says "shape sketch" on its drawings and cards (owner decision 17, [PRD 11](../PRDs/11-prd-refined-final-forms.md#1-the-paper-screen)). |
| **Fidelity record** | What an output says about how true to paper it is, on four independent axes: geometry (folded with rigid panels; settled by a solver as a bending sheet, `bent zero-thickness`, naming what the solve held that the model leaves free, owner decision 39; or placed, a *shape sketch*), motion, appearance and lines. Written into a GLB as `extras.senbazuru.fidelity` only when the caller says where the positions came from; default outputs carry none. `Senbazuru.Render.Fidelity`. |
| **Reach-through** | Of two triangles that cross: for each, how far it reaches past the other's plane on its shorter side, and the smaller of the two. No pair passes further through than this, so it is an upper bound on how deep a crossing is, and the pair with the largest bound need not be the deepest. A count of crossings on touching paper only measures rounding. See [notes/crossing-counts-on-touching-paper.md](notes/crossing-counts-on-touching-paper.md). |
| **Sheet unit** | One unit of length in the flat sheet's *material coordinates*. The crane's square is one sheet unit on a side. The wing studies fold a test wing, a sheet of its own and not the crane's wing, one sheet unit long from root to tip. The paper screen gives its floors and reach-throughs in pixels at its page's *page scale*, and its false-crease turning in sheet units × degrees. |
| **Page scale** | The scale at which a gallery page's paper screen gives its pixels, in pixels to a *sheet unit*: the largest at which the gallery draws the paper, in the figures on the page or the drawings it writes beside them, so that a pose that passes passes in every one of them (owner decision 30). A pose drawn in none of them is screened at it too. A plot of measurements, such as crane-root's side profiles, is not a drawing of the paper and does not count (owner decision 38). A page that draws no paper has no page scale: its gallery writes its measurements without screens and publishes no page. |
| **Made again** | Of a pose: built a second time one level finer, on its sheet with every triangle split into four, so that the paper screen can measure its false creases there as well. A folded pose is made again by folding the finer sheet the same way, and a placed pose by placing it by the same rule. A solved pose can be made again only by solving it again, which the screen does not do (owner decision 27), so its finer level is *not measured*, as is that of any pose not made again. The one exception is a gallery that already solves the same *control* on the pose's mesh split into four and *accepts* that solve: it counts as the pose made again where it holds the sheet at the same points, holding the coarser mesh's held vertices in the same places, and the two solves agree within the floor limit at every vertex of the coarser mesh (owner decisions 29 and 31). |
| **Control** | In a study gallery, one solve's set-up: which points of the sheet are held and where, the stiffness of its creases and panels, the order its layers must keep, and the solver's settings. Two solves of one control may differ in their mesh or in where the solver starts; the wing-layers gallery's 40° bend whose upper layer starts inside the lower solves the same control as its plain 40° bend. |
| **Accepted** | Of a solve in a study gallery: passing the gallery's own checks, so that the gallery treats it as a finished shape. Each gallery sets its own. The wing-bending gallery asks that the solve converged and passes its endpoint contact check; the wing-layers gallery asks as well that its grips hold exactly and its root crease stays folded flat. A finer solve its gallery does not accept does not count as a pose *made again* (owner decision 31). |
