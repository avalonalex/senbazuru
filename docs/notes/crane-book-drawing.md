# Choosing ink without changing the crane

The owner prefers the **More tucked** whole-crane pose and asked on 2026-09-27
how to balance faithfulness with an attractive instruction-book drawing. The
comparison at `crane-book.html` holds the paper and camera fixed. It offers the
existing plain drawing, three tones with all visible crease marks, and the same
three tones with very short crease fragments omitted. The full-detail version
is the default: omission is a choice to inspect, not an automatic improvement.

The distinction matters because faithfulness has several parts. A drawing can
keep the paper's shape and which layer is visible without reproducing every
lighting variation. [Binnette's vector crane](https://commons.wikimedia.org/wiki/File:Origami_-_Crane.svg)
and [Andreas Bauer's photograph](https://commons.wikimedia.org/wiki/File:Origami-crane.jpg)
show this clearly. The [Tuttle book illustration](https://www.cutoutandkeep.net/projects/origami-crane-3)
uses broad fills and a few curves to suggest a fuller body. These are visual
references; no reference drawing or mesh is copied into the repository.

`CraneBookDrawing` consumes the same visible paper regions as the existing SVG.
A [panel](../glossary.md#origami), the paper between creases, receives one of
three warm tones from its area-weighted average surface direction. Both sides
use the same palette. This deliberately leaves out subtle shading inside a
curved panel; the actual outline and crease positions remain. An initial
comparison that divided smooth brightness into three bands produced jagged
colour boundaries on the curved wing. A single tone per original panel avoids
turning its triangle approximation into extra visual detail.

A **contour** is an edge of visible paper against empty space or another layer
at a different depth. Contours use heavier ink than crease marks. The visible
polygons have been cut into pieces by nearer paper; merely drawing every piece
would expose those cuts and the internal triangle joins. The renderer cancels
oppositely directed shared boundary stretches only when their depths agree at
both ends. This removes joins inside a surface while retaining the outline of
a flap over another layer. One long stretch can cancel against several short
ones. Neither matching coordinates alone nor matching endpoint pairs suffices.

The selective treatment omits crease fragments shorter than **2 drawing pixels**
at **600 pixels per sheet unit**. It never omits contours. This is a simple
size-based experiment, not an understanding of which folds matter to an
instruction. The gallery can highlight every omitted mark and switch between
fitted, actual-size and magnified drawings. Four cameras expose the other side,
a lower view and the top. The SVG downloads preserve this declared scale.

The three tone fills retain exactly the source polygons, grouped by colour;
the existing paper-side diagnostic remains available. The complete-sheet FOLD
and GLB files, old SVGs and material/contact measurements stay unchanged.
Tests cover curved panels, boundaries split by clipping, overlap edges at
different depths, paper-side reversal and the distinction between omitted
crease ink and retained contours.

An independent comparison of exported polygon coordinates finds the same
421, 394, 312 and 514 visible pieces in the upright, opposite, low and top
views respectively. All 242 pre-existing archive, measurement and drawing
files retain their hashes. The selective views omit 25, 30, 18 and 46 crease
fragments; their longest omitted fragments are 1.52, 1.95, 1.57 and 1.85 pixels.
The silhouettes and overlap contours are the same in both treatments.

This treatment makes no new claim of valid paper or successful inflation. The
pointed joins at the wing roots and the angular lower body remain visible.
Judge the drawing at its intended size, then revise those shapes if they still
interrupt the impression of one folded sheet. A quieter illustration is useful
evidence for that decision, not a reason to resume microscopic contact repair.
