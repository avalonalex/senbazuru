# How senbazuru is put together

The map of the code: what flows where, what each module holds, and the rules
about which module may know about which. Read this before adding a module.

For what the tool *does*, the [README](../README.md); for how to run it,
[usage.md](usage.md); for the vocabulary any of it assumes,
[glossary.md](glossary.md).

## The pipeline

One direction of flow, no cycles:

```
 .fold bytes
     |  Senbazuru.Fold.Load          I/O boundary: read + decode, errors as values
     v
 FoldFile / Frame                    Senbazuru.Fold.Types
     |                               a faithful, permissive mirror of the format
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
     v
 Diagram                             Senbazuru.Diagram
     |                               backend-independent: shapes + strokes
     |  Senbazuru.Render.Svg         + Senbazuru.Geometry for the page transform
     v
 SVG text
```

| Module | Holds |
| --- | --- |
| `Senbazuru.Geometry` | `V2`, `Box`, `Transform`. No FOLD, no SVG. |
| `Senbazuru.Geometry.VectorSpace` | The arithmetic 2D and 3D points share. |
| `Senbazuru.Geometry.V3` | Points in space, the cross product, and whether a set of points is flat. |
| `Senbazuru.Geometry.Rigid` | 3×3 matrices and motions that turn and slide but never deform. |
| `Senbazuru.Geometry.Polygon` | Convex polygons in the plane: area, clipping, and whether two overlap. |
| `Senbazuru.Fold.Types` | The FOLD document model and its JSON instances. |
| `Senbazuru.Fold.Load` | The only I/O in the library. |
| `Senbazuru.Fold.Query` | Validation and refinement of a `Frame`: `Crease`, `Face`. |
| `Senbazuru.Diagram` | The drawing IR: `Shape`, `Stroke`, `Diagram`. |
| `Senbazuru.Diagram.Style` | Every decision about how diagrams *look*. |
| `Senbazuru.Diagram.Layout` | Several figures on one page, at one shared scale. |
| `Senbazuru.Render.Steps` | A whole folding sequence as one page of figures. |
| `Senbazuru.Origami.Flat` | A model folded flat, as convex polygons in one plane. Shared by the two modules that reason about layers. |
| `Senbazuru.Origami.FlatFold` | Maekawa's and Kawasaki's theorems, vertex by vertex. |
| `Senbazuru.Origami.Folding` | Crease pattern + fold angles → folded form. |
| `Senbazuru.Origami.Layers` | `faceOrders` + a viewing direction → an order to draw in, how deep in the stack each face is, and which side of the paper it shows. |
| `Senbazuru.Origami.Stacking` | A flat-folded frame → its `faceOrders`, solved from taco and tortilla constraints, one independent component at a time. |
| `Senbazuru.Origami.Step` | Two frames → what moved between them. |
| `Senbazuru.Origami.Visible` | A flat-folded frame + `faceOrders` + which side it is seen from → the paper that shows and the edges that are not hidden. |
| `Senbazuru.Render.Camera` | Orthographic projection: 3D → the page. |
| `Senbazuru.Render.CreasePattern` | FOLD frame → `Diagram`, and which view to use. |
| `Senbazuru.Render.Svg` | `Diagram` → SVG text. |
| `Senbazuru.Cli` (in `app/`) | Flag parsing. Not part of the library. |

## Where the files are

```
src/Senbazuru/     the library, as above
app/               the command-line interface
test/              property, example and golden tests
examples/          sample .fold files, with their provenance in examples/README.md
docs/              this, and everything else that is prose
docs/notes/        one idea per file: theorems, algorithms, techniques
```

## Layering rules

- `Senbazuru.Geometry` depends on nothing in the project. Keep it that way.
- `Senbazuru.Diagram` must not know what FOLD is.
- `Senbazuru.Origami.*` is what senbazuru knows about paper, as opposed to what
  it knows about drawing. Nothing in it may mention a diagram, a page or a
  colour; it is a second consumer of `Fold.Query`, not a stage on the way to
  SVG.
- `Senbazuru.Render.Svg` must not know what a mountain fold is.
- Only `Senbazuru.Fold.Load` does I/O. Everything else takes and returns values,
  which is what makes the rest testable without a filesystem.
- New output backends (PDF, PNG) become new consumers of `Diagram`, never a
  second traversal of `Frame`.

## Testing

Three kinds, used for different things: property tests for the geometry layer,
example tests for decoding, golden tests for whole-document output. Which, and
why each, is in [CLAUDE.md](../CLAUDE.md#testing).
