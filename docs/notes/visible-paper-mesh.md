# Show exposed paper without moving its creases

A quarter fold places four different parts of a square on top of one another.
Their coordinates agree, but their [material identities](../glossary.md) do not:
opening the fold must separate them again. A generic glTF viewer compares
triangle depths and cannot read origami layer order. The exporter must decide
what to draw where those depths tie.

`Render.PaperMesh` groups panels that lie in the same plane and finds the
exposed regions from each side. It uses the existing layer solver for a whole
flat model, or supplied orders for coplanar parts of an open model. It then
subtracts buried regions using the same visibility code as SVG. The output is
independent of the viewing camera: panels in different planes retain their
actual depth. A circular interleaving such as the pinwheel is allowed, while
contradictory orders over a common patch are refused.

The resulting graphics pieces are a view of the material, not a replacement
for it. A quarter-fold export contains four triangles in the default Visible
paper scene and sixteen in Complete paper, counting both sides. Every corner
in both scenes still has height zero. Independent per-face lifting has been
removed; physical thickness does not change the output coordinates.

Clipping can introduce a corner inside an existing panel. Suppose its original
vertices are `A`, `B` and `C`, and clipping lands at `0.25 A + 0.75 B`. The new
graphics corner records `[(A, 0.25), (B, 0.75), (C, 0)]`. These weighted
references identify a point within the panel; they do not interpolate between
folding states. An original corner simply records `[(A, 1)]`. Separate layers
at one position remain separate because their vertex ids differ.

The GLB records these references in application-specific `extras`:

- Root `extras.senbazuru` has `version: 1` and a FOLD `frame` containing the
  original topology, packed current positions and supplied `faceOrders`.
  Positions here use FOLD axes; graphics buffers use glTF axes `(x, z, -y)`.
  A supplied `senbazuru:material_coords` map survives; other frame extensions
  are discarded because packing rounds positions and could stale their claims.
- Mesh `extras.materialWeights` has one weighted reference list per POSITION.
- Primitive `extras.materialFaces` has one original panel id per triangle.
- Optional root `physicalThickness` and `layerRequirements` preserve the
  surface's stored properties. A requirement contains a FOLD-axis `direction`
  and `lowerUpper` panel pairs. These are constraints, not a new contact report.

Ids refer to the prepared surface, after crossing cuts have introduced any
new vertices or panels; they need not match the input file's numbering.

A complete scene's graphics indices may duplicate a material point for
lighting or colour, but its material id still names just one position. Cuts
remain distinct even if their coordinates coincide. The source topology is
therefore the place to recover connectivity; graphics adjacency alone is not.
Missing original-sheet coordinates are not reconstructed from a folded pose.

The [glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
provides multiple scenes and application-specific extras. A viewer that shows
only the default scene can open a separate `--all-layers` export to inspect the
complete sheet. That scene deliberately retains coincident triangles and can
flicker. Neither scene supplies general collision detection, panel bending,
thickness clearance or a motion between checkpoints. The visible path requires
convex planar panels and explicit orders where depth alone cannot decide.

The [preview](../../study/gltf/README.md) uses a standard Three.js GLTFLoader.
A near clipping plane set much closer than the model needs wastes depth
precision: an intermediate bird fold showed pale lines at touching edges until
the preview's near distance changed from `radius / 10000` to `radius / 10`.
That fix changes the camera, not the material or the exported mesh.
