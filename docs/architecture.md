# How senbazuru is put together

The map of the code: what flows where, what each module holds, and the rules
about which module may know about which. Read this before adding a module.

For what the tool *does*, the [README](../README.md); for how to run it,
[usage.md](usage.md); for the vocabulary any of it assumes,
[glossary.md](glossary.md).

## The pipeline

One direction of flow, no cycles:

```
 .fold bytes    .cp / .opx bytes
     |               |               Senbazuru.Import.Cp / .Opx / .Segments
     |               |               a list of segments in, one Frame out:
     |               |               no faces, no fold angles, no second frame
     |  Senbazuru.Fold.Load          I/O boundary: read + decode, errors as
     v               v               values; the extension picks the reader
 FoldFile / Frame                    Senbazuru.Fold.Types
     |                               a faithful, permissive mirror of the format
     |  Senbazuru.Fold.Creasing      draw a new crease: a Frame in, a Frame
     |                               out, and back through the two below
     |                               (Origami.ThroughLayers draws one on the
     |                               folded model instead, and comes back here)
     |  Senbazuru.Fold.Crossings     cut the creases where they meet, so the
     |                               drawing is a planar graph
     |  Senbazuru.Fold.Faces         the faces a file did not record, traced
     |                               from the creases; asked for by whatever
     |                               needs paper rather than lines
     |  Senbazuru.Fold.Query         validate + refine: indices become real points
     v
 [Crease]                            3D geometry that cannot be structurally wrong
     |                               |
     |                               +--> Senbazuru.Origami.FlatFold
     |                               |    origami knowledge, no drawing: is this
     |                               |    pattern locally impossible to fold?
     |                               +--> Senbazuru.Origami.Folding
     |                               |    fold it: a Frame in, a folded Frame
     |                               |    out, straight back into this pipeline
     |                               +--> Senbazuru.Origami.Layers
     |                               |    which face is in front, and how deep
     |                               |    in the stack, given where the viewer
     |                               |    is standing
     |                               +--> Senbazuru.Origami.Stacking
     |                               |    which face is on top of which, when
     |                               |    the file does not say: faceOrders out
     |                               +--> Senbazuru.Origami.Visible
     |                               |    what of a flat-folded model can be
     |                               |    seen: regions of paper and the edges
     |                               |    that are not buried
     |                               +--> Senbazuru.Origami.Step
     |                                    subtract two frames: which paper moved
     |                                    and where it went, i.e. the arrow
     |  Senbazuru.Render.CreasePattern
     |  + Senbazuru.Render.Camera    orthographic projection to the page
     |  + Senbazuru.Diagram.Style    origami line conventions
     |
     |    Senbazuru.Render.Gltf       the one backend that does not go through
     |      |                         Diagram, because Diagram is 2D: faces in
     |      v                         space, layers lifted apart, two-sided paper
     |    .glb bytes
     v
 Diagram                             Senbazuru.Diagram
     |                               backend-independent: shapes + strokes
     |  Senbazuru.Render.Svg         + Senbazuru.Geometry for the page transform
     v
 SVG text
```

The top of that diagram is the only part that also runs backwards:
`Senbazuru.Fold.Load` encodes and writes as well as reading and decoding, so a
`FoldFile` can go back out as bytes. It is a second door in the same wall rather
than a cycle — nothing further down the page is involved, and the only thing
that reaches for it is a caller holding a `Frame` it built or folded.

`Senbazuru.Fold.Creasing` is the first such caller, and the first module that
goes *in* at the top and comes *out* at the top: a frame in, a frame out, no
picture anywhere. Everything an authoring vocabulary
([#60](https://github.com/avalonalex/senbazuru/issues/60)) adds will have that
shape, and will reach the rest of the pipeline the way a file does — by being
a `Frame` that `Fold.Query` cannot tell from one somebody wrote by hand.

| Module | Holds |
| --- | --- |
| `Senbazuru.Explain` | The one method every error type in the library answers: turn yourself into a message. No FOLD, no geometry, no drawing — just `Text`. |
| `Senbazuru.Geometry` | `V2`, `Box`, `Transform`. No FOLD, no SVG. |
| `Senbazuru.Geometry.VectorSpace` | The arithmetic 2D and 3D points share. |
| `Senbazuru.Geometry.V3` | Points in space, the cross product, and whether a set of points is flat. |
| `Senbazuru.Geometry.Rigid` | 3×3 matrices and motions that turn and slide but never deform, and the inverses that undo them. |
| `Senbazuru.Geometry.Polygon` | Convex polygons in the plane: area, clipping, and whether two overlap. |
| `Senbazuru.Fold.Types` | The FOLD document model and its JSON instances. |
| `Senbazuru.Fold.Load` | The only I/O in the library, in both directions. Also picks a reader from a file's extension. |
| `Senbazuru.Import.Segments` | A list of line segments → a `Frame`, merging the endpoints that coincide. What the two other-format readers share. |
| `Senbazuru.Import.Cp` | Orihime and Oriedita `.cp` text → segments. |
| `Senbazuru.Import.Opx` | ORIPA `.opx` XML → segments. |
| `Senbazuru.Fold.Query` | Validation and refinement of a `Frame`: `Crease`, `Face`. |
| `Senbazuru.Fold.Faces` | The faces a file does not record, traced from the creases. Refuses a drawing whose regions would not be its faces. Owns `Sheet`, the drawing itself. |
| `Senbazuru.Fold.Crossings` | Cuts creases at the points where they meet, so a drawing `Fold.Faces` refuses becomes one it can trace. `withPlanarFaces` is the pair — cut, then trace — that every backend calls. |
| `Senbazuru.Fold.Creasing` | Draws new creases on a pattern: the one operation that changes a crease pattern rather than reading one. Adds the lines and hands the frame straight back to `Fold.Crossings` — once for the whole batch, because that handing back is nearly all the cost. |
| `Senbazuru.Diagram` | The drawing IR: `Shape`, `Stroke`, `Diagram`. |
| `Senbazuru.Diagram.Style` | Every decision about how diagrams *look*. |
| `Senbazuru.Diagram.Layout` | Several figures on one page, at one shared scale. |
| `Senbazuru.Render.Steps` | A whole folding sequence as one page of figures. |
| `Senbazuru.Origami.Flat` | A model folded flat, as convex polygons in one plane. Shared by the two modules that reason about layers. |
| `Senbazuru.Origami.FlatFold` | Maekawa's and Kawasaki's theorems, vertex by vertex. |
| `Senbazuru.Origami.Folding` | Crease pattern + fold angles → folded form, and the rigid motion that placed each face. |
| `Senbazuru.Origami.Layers` | `faceOrders` + a viewing direction → an order to draw in, how deep in the stack each face is, and which side of the paper it shows. Reads orders; never computes them. |
| `Senbazuru.Origami.Stacking` | A flat-folded frame → its `faceOrders`, solved from taco and tortilla constraints, one independent component at a time. Also `layerOrderFor`, the one policy for *which* orders a frame gets — its own, or solved, or none — shared by the SVG and 3D backends. |
| `Senbazuru.Origami.Step` | Two frames → what moved between them. |
| `Senbazuru.Origami.ThroughLayers` | A line drawn on the model a pattern folds into → the creases it makes on the pattern, one per face it crosses, each of the kind that layer's own way up asks for. |
| `Senbazuru.Origami.Visible` | A flat-folded frame + `faceOrders` + which side it is seen from → the paper that shows and the edges that are not hidden. |
| `Senbazuru.Render.Camera` | Orthographic projection: 3D → the page. |
| `Senbazuru.Render.CreasePattern` | FOLD frame → `Diagram`, and which view to use. |
| `Senbazuru.Render.Svg` | `Diagram` → SVG text. |
| `Senbazuru.Render.Gltf` | FOLD frame → glTF binary: a 3D model, with a flat-folded model's layers lifted apart so a depth buffer can tell them apart. |
| `Senbazuru.Cli` (in `app/`) | Flag parsing. Not part of the library. |

## Where the files are

```
src/Senbazuru/     the library, as above
app/               the command-line interface
test/              property, example and golden tests
examples/          sample .fold and .cp files, with their provenance in examples/README.md
docs/              this, and everything else that is prose
docs/notes/        one idea per file: theorems, algorithms, techniques
```

## Layering rules

- `Senbazuru.Geometry` depends on nothing in the project. Keep it that way.
- `Senbazuru.Explain` depends on nothing in the project either, and every layer
  that has an error type may import it. That is the price of one name for
  "print this error": the class has to sit below the error types rather than
  beside them, which is also why it holds no error type of its own. It does not
  reopen the rule above — `Senbazuru.Geometry` has no error type, and giving it
  one is the change to argue about, not the import that would follow.
- `Senbazuru.Diagram` must not know what FOLD is.
- `Senbazuru.Origami.*` is what senbazuru knows about paper, as opposed to what
  it knows about drawing. Nothing in it may mention a diagram, a page or a
  colour; it is a second consumer of `Fold.Query`, not a stage on the way to
  SVG.
- `Senbazuru.Render.Svg` must not know what a mountain fold is.
- Only `Senbazuru.Fold.Load` does I/O, reading and writing alike. Everything
  else takes and returns values, which is what makes the rest testable without a
  filesystem. `Senbazuru.Import.*` is no exception: those modules take `Text`
  and return values, and `Fold.Load` is what turns a path into bytes for them.
- **Whatever needs faces asks `Fold.Faces` for them, and does not refuse a
  frame without any.** Most files record none — no `.cp` or `.opx` can — and
  the creases determine them, so `Origami.Folding` and `Render.Gltf` both call
  `Fold.Crossings.withPlanarFaces`, which is one function rather than a pair of
  calls at each backend precisely so a third backend cannot half-apply it. `Render.CreasePattern` deliberately does
  *neither*, and the reason is not golden churn: tracing can *fail* on a
  drawing no amount of cutting fixes — a crease that stops in the middle of
  the paper has no face round it — and a drawing must not stop working because
  its faces cannot be worked out. Filling optimistically, whenever the trace
  happened to succeed, would make the picture of a pattern depend on a property
  of it nobody looking at the page can see.
- **A new input format becomes a `Frame`, and stops there.** `Senbazuru.Import.*`
  may know what FOLD is, because producing a `Frame` is its whole job; nothing
  downstream may know that a frame came from anywhere but a `.fold` file. Where
  a format cannot say something FOLD can — neither `.cp` nor `.opx` has faces —
  the frame simply does not say it either, and the layer above deals with the
  gap the way it deals with a `.fold` file that left the same key out.
- New output backends (PDF, PNG) become new consumers of `Diagram`, never a
  second traversal of `Frame`. **The one exception is a 3D backend.** `Diagram`
  is two-dimensional — `V2`, no depth — so `Senbazuru.Render.Gltf` reads
  `Fold.Query`'s faces directly. That is a stated exception, chosen over a 3D
  intermediate representation for a single consumer; a second 3D format would
  be the moment to build one. It still must not import `Render.CreasePattern`:
  what the two share — which layer order to use — is
  `Origami.Stacking.layerOrderFor`.

## Testing

Three kinds, used for different things: property tests for the geometry layer,
example tests for decoding, golden tests for whole-document output. Which, and
why each, is in [CLAUDE.md](../CLAUDE.md#testing).
