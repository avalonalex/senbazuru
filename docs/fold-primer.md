# A primer on FOLD and origami diagrams

Background for someone comfortable with Haskell but new to origami and to
computational geometry. Nothing here is Haskell-specific; it is the domain
knowledge the code assumes.

## 1. What an origami diagram actually is

Open any origami book and you will see the same notation, largely unchanged
since Akira Yoshizawa developed it in the 1950s and Samuel Randlett and Robert
Harbin popularised it in English. It survived because it is language-independent:
a Japanese diagram is readable by someone who reads no Japanese.

Each step is a picture of the paper plus **arrows** saying what to do next. The
picture uses a small line vocabulary:

| Line | Meaning |
| --- | --- |
| solid | edge of the paper |
| dashed | **valley fold** — crease this so the paper sinks away from you |
| dash-dot-dot | **mountain fold** — crease this so the paper rises towards you |
| thin/light solid | a crease that already exists but is currently flat |
| dotted | an edge hidden behind other layers ("X-ray" view) |

Two things about mountain and valley are worth internalising early:

- **They are the same physical crease seen from opposite sides.** Fold a piece
  of paper, turn it over: every mountain is now a valley. So "mountain" is not a
  property of a crease, it is a property of a crease *plus a viewing side*. A
  file format has to fix a convention, and FOLD does.

- **The dash-dot-dot line is borrowed from technical drawing**, where it means a
  centreline. It was chosen because it is instantly distinguishable from a plain
  dashed line even in cheap printing.

Arrows carry the rest of the meaning — a solid arrowhead for a normal fold, a
hollow one for "fold then unfold", a looped arrow for turning the model over.
Senbazuru draws the first of those, worked out by comparing one frame of a file
with the next (`--arrows`). The other two mark steps whose paper does not
visibly go anywhere, and it draws nothing for those rather than guessing.

## 2. Crease pattern vs. folded form

Two very different pictures come out of the same data.

A **crease pattern** is the sheet, flat and unfolded, with every crease drawn on
it. This is the easy case for a renderer: the coordinates in the file are already
the coordinates on the page. Drawing one is just "draw each edge with the right
line style".

A **folded form** is the model after folding — the same vertices and edges, but
with coordinates moved to where they end up, usually in 3D. Drawing this properly
is much harder, because paper is opaque and layers overlap. You need to know
which layer is on top of which, and hide what is behind. FOLD stores that
information in `faceOrders`, and senbazuru paints faces in the order it gives.
A flat-folded form that arrives without one has its order worked out from the
creases, which is a small constraint problem — see
[notes/taco-taco.md](notes/taco-taco.md).

## 3. FOLD in one page

A `.fold` file is JSON. The whole format rests on one idea: the paper is a
**planar graph**, and the file is a set of parallel arrays describing it.

Keys are named `object_property`, and every such key is an array indexed by
object id. Ids are simply **zero-based indices into those arrays** — there is no
`"id"` field anywhere in the format.

```jsonc
{
  // COORDINATES. Vertex 0 is at (0,0), vertex 1 at (1,0), and so on.
  // This is the only array here that holds positions.
  "vertices_coords":  [[0,0], [1,0], [1,1], [0,1]],

  // INDICES into the array above -- not positions.
  // [3,1] means "the edge from vertex 3 to vertex 1", i.e. from (0,1)
  // to (1,0): the diagonal. It does NOT mean the point (3,1).
  "edges_vertices":   [[0,1], [1,2], [2,3], [3,0], [3,1]],

  // Edge 4, the diagonal, is a valley fold. The other four are the
  // border of the paper.
  "edges_assignment": ["B",   "B",   "B",   "B",   "V"],

  // INDICES again. The diagonal cuts the square into two triangles.
  "faces_vertices":   [[0,1,3], [1,2,3]]
}
```

Everything in that file lies inside the unit square. This is worth dwelling on,
because it is the first thing that trips people up: **`vertices_coords` holds
positions, and every other `_vertices` array holds indices into it.** They are
all written as `[a, b]` pairs and look identical. Read `[3,1]` as a point and
the shape appears to spill outside the paper; read it as a pair of vertex ids
and it is the diagonal.

### What a face is

A **face** is a region of paper bounded by edges — a polygon.
`faces_vertices[i]` lists the vertices around face `i`, counterclockwise. Above,
the diagonal splits the square into two triangles:

| Face | Vertices | Positions |
| --- | --- | --- |
| 0 | `[0,1,3]` | `(0,0)`, `(1,0)`, `(0,1)` — lower-left triangle |
| 1 | `[1,2,3]` | `(1,0)`, `(1,1)`, `(0,1)` — upper-right triangle |

Those two triangles are the flaps: fold along the valley diagonal and one lands
on the other.

Faces carry three things edges alone cannot. They are what you *fill* to draw
paper as paper rather than as a wireframe. They are what gets stacked in a
folded model, which is what `faceOrders` orders. And their counterclockwise
winding defines which way the face points — which is precisely why mountain and
valley depend on the side you are viewing from.

### The parts that catch people out

**The top-level object is both the file and its first frame.** FOLD supports
multiple frames — one state of the paper each, which is how a step-by-step
sequence is stored. Frames after the first live in `file_frames`. The *first*
frame is not in that array; its keys sit directly at the top level, mixed in with
the `file_*` metadata. Senbazuru's decoder separates them so nothing downstream
has to remember this.

**Almost everything is optional.** A file with `{}` is valid FOLD. Arrays that
ought to correspond may be missing or, worse, present with mismatched lengths.

**Coordinates may be 2D or 3D.** `[0, 0]` and `[0, 0, 0]` are both fine, and
both appear in real files.

**Extensions use a colon.** Custom keys are namespaced, e.g. `"cpedit:page"`.
A decoder must ignore keys it does not recognise — this is not hypothetical,
the upstream example file `diagonal-cp.fold` contains exactly that key.

**`file_spec` is a number, not an integer.** Real files say `1.1`. Typing it as
an integer rejects valid input.

### Edge assignments

| Code | Name | Fold angle |
| --- | --- | --- |
| `B` | border — edge of the paper | — |
| `M` | mountain | `[-180, 0)` |
| `V` | valley | `(0, 180]` |
| `F` | flat — a crease that is not folded | `0` |
| `U` | unassigned — not yet decided | unknown |
| `C` | cut / slit in the paper | — |
| `J` | join — the two faces are really one piece | — |

`edges_foldAngle` gives the dihedral angle in degrees. The sign is what
distinguishes mountain from valley: negative is a mountain, positive a valley,
and ±180 means the paper is folded flat back on itself.

## 4. The bit of geometry you need

Only two ideas from computational geometry are used so far, and neither is deep.

**Bounding boxes.** The smallest axis-aligned rectangle containing a set of
points. Used to work out how much of the page the drawing needs. The only subtle
part is the degenerate cases: no points at all, or all points on a single line,
which give a box with zero width or height. Dividing by that produces infinity,
so those cases have to be handled rather than assumed away.

**Affine transforms.** Mapping model coordinates onto the page. Senbazuru only
needs scale-and-translate, no rotation, but three things happen inside it:

1. *Uniform scale* — the same factor for x and y, so a square sheet stays square.
2. *Centring* — a uniform scale generally cannot fill the page exactly, so the
   slack is split evenly.
3. *Y flip* — **mathematical coordinates have y increasing upwards; SVG and every
   other screen coordinate system have y increasing downwards.** Getting this
   wrong renders everything upside down, and it is the single most common bug in
   any renderer.

A worked example, mapping a unit square onto a 200×200 page with a 10-point
margin. The content area runs from 10 to 190, so the scale is 180:

| Model point | | Page point |
| --- | --- | --- |
| `(0, 0)` — bottom-left | → | `(10, 190)` — *bottom*, so a large y |
| `(1, 1)` — top-right | → | `(190, 10)` |
| `(0.5, 0.5)` — centre | → | `(100, 100)` |

That first row is the whole y-flip in one line: the model's origin is at the
bottom of the page, which in page coordinates is the *largest* y.

## 5. Further reading

- [FOLD specification](https://github.com/edemaine/FOLD/blob/main/doc/spec.md) —
  the authoritative reference, and short.
- Robert Lang, *Twists, Tilings, and Tessellations* — the standard reference for
  the mathematics of crease patterns.
- Erik Demaine and Joseph O'Rourke, *Geometric Folding Algorithms* — the
  computational geometry, if you want the theory.
