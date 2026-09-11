# Why the old layer-spacing export was replaced

The first glTF exporter lifted every flat-folded face by its layer number
multiplied by a small display spacing. This resolved depth ties in a generic
viewer, but opened gaps at shared creases. Calling the parameter `--thickness`
also confused a drawing convention with a physical property of the sheet.

That approach has been removed. The [current export](visible-paper-mesh.md)
keeps every material position, derives exposed regions for its default scene,
and retains the complete sheet in a second scene. It can display a pinwheel's
circular interleaving without inventing a height for each whole flap.

Physical [thickness](../glossary.md) remains useful for future packing and
clearance checks. It is optional data on the shared surface; it is not the old
spacing under a new name. A connected surface with a boundary also need not be
[watertight](../glossary.md): joining creases and enclosing a volume are separate
questions.
