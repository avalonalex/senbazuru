# Count the sheets over a vertex, not the layer a face is in

Terms used here are defined in [../glossary.md](../glossary.md).

A fanned figure moves each corner of a folded model toward the page's lower
left by how many sheets lie over it, so a stack shows its layers as a fan of
edges. The number it needs is a fact about one *vertex* seen from one side, its
**fan count**: of the faces with a corner there, the fewest sheets nearer the
viewer over that corner, the least of them.

The tempting number is the [layer number](layer-numbers.md) the offset view
already has, read from the other side: the longest chain of sheets *over* a
face rather than under it. It is the wrong one, because it is about a whole face
and is decided anywhere on it. A flap covering half of a face's corner makes the
face as deep as the flap, though the other half of that corner is bare.

The helmet base after its second step shows it. Its state 2, seen from above,
as `helmet.foldseq`'s run writes it (`file_frames[2]`):

| Vertex | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Fan count | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |
| Least layer number, read from below, of a face cornered there | 0 | 3 | 0 | 2 | 0 | 0 | 0 | 1 | 1 |

Three vertices lie at (1, 0). Vertex 0 is a corner of a flap of two sheets,
faces 1 and 5; vertex 1 is a corner of face 0, the bottom sheet; and vertex 3 a
corner of face 4, the sheet lying on it. The flap's fold runs out of that point
along x + y = 1 and covers only the half of each corner between that line and
the bottom edge. Over that half, face 0 has three sheets on it and face 4 has
two, which are their layer numbers read from below. Over the other half only
face 4 lies on face 0, and nothing lies on face 4. Moved by layer numbers, the
fan would pull vertices 1 and 3 away from paper that lies flat on them.

So `Senbazuru.Origami.Visible.fanCounts` asks about directions out of the
vertex, not about faces. The sides through the vertex cut the directions into
wedges, and over one wedge the same sheets lie throughout. A face's cover is the
fewest sheets nearer than it over any wedge of its own corner. Directions,
because a point a hair from a vertex can land on a fold line and belong to both
faces or neither. Its header has the rest.

The first row is pinned by `stack test --ta '--match "the layers over each
vertex"'`. The second row is the least, over the faces with a corner at each
vertex, of `Senbazuru.Origami.Layers.layerDepths (V3 0 0 (-1))`, computed on
2026-11-01. Its argument points towards the viewer, here one below the paper,
so each face's number is the longest chain of sheets above it.
