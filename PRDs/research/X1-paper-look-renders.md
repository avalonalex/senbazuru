# X1. Rendering existing crane meshes with a paper look

Experiment X1, run 2026-09-28 against `main` at `83fc960`. Nothing in the
repository was changed; everything ran in a scratch directory. The scripts are
in [`scripts/X1-render/`](scripts/X1-render/). The verification pass
([V](V-verification.md), cluster V2) re-ran the Line Art and pixel
measurements; its corrections are applied below and marked **(V2)**.

## Question

How much of the "unrefined" look is presentation, and how much is geometry?
Render existing geometry with a real paper look and see what improves.

## Setup

Four models, one orthographic camera each, Blender 4.4.1 headless on the
owner's M1 Max (Metal GPU). Every mesh was rebuilt straight from its FOLD
file, not from the GLB ([H5](H5-photoreal.md) finding 2 shows why: the GLB's
two copies of each face confuse a path tracer).

| Model | Faces | Valid paper? |
| --- | ---: | --- |
| Flat-folded crane, `senbazuru fold examples/crane.fold` | 72 | yes |
| Square twist, `examples/squaretwist.fold` (rigid 3D) | 9 | yes |
| Closed crane on the study's mesh, `whole-crane/before.fold` | 448 | yes; the fair control for the sketch |
| **More tucked** sketch, `whole-crane/spread-0.fold` | 448 | no: 57% edge error, 345 crossing pairs ([H1](H1-diagnosis.md) finding 4) |

Three treatments per model:

1. **Baseline.** Workbench, lit the way today's three.js viewer lights
   triangles.
2. **Paper recipe** (Cycles, 128 samples, OpenImageDenoise):
   - Principled BSDF with a little sheen, mixed 12% with a Translucent BSDF;
   - the two sides of the paper coloured differently through the
     *Backfacing* output of the Geometry node;
   - Solidify at 0.1 mm, which is 6.67e-4 of a 15 cm sheet (simple mode; the
     even-thickness mode spiked at 180° folds, as H5 finding 14 also found);
   - normals smooth within a panel and sharp at creases;
   - an area light, a ground plane with a contact shadow, AgX tone mapping.
3. **Paper recipe plus lines**, Freestyle outlines and crease lines.

**Coincident layers.** A flat-folded model has layers at exactly the same
height. For the Cycles renders they were separated by heights computed from
`faceOrders`, with a flat wall where a fold joins layers at different heights.
That is a rendering device only, not paper: it cannot be done without
stretching on one connected sheet ([X3](X3-crane-opening.md),
[H3](H3-contact.md) finding 18). Layer gap 1.1 × thickness.

## Results

![Contact sheet: rows flat crane, square twist, closed crane, More tucked sketch; columns today's output, viewer-style baseline, Cycles paper recipe, paper plus lines](img/X1-contact-sheet.jpg)

**Presentation is most of the gap on valid geometry, and none of it on the
sketch's defects.**

- The twist, the flat crane and the closed crane look like photographed paper
  under the recipe.
- On More tucked the recipe adds depth (shadow, contact, falloff), but the
  wrong-side blotches where the sheet passes through itself, the flat oversized
  wing, the stretched wing roots and the fan-shaped body all stay. They are
  easier to see, because the rest of the image is calmer. H5 finding 4 reached
  the same conclusion independently.

**Line Art intersection lines put a number on the crossings.** Blender's Line
Art can draw where two surfaces pass through each other. With fold walls off
and coincident layers separated by `faceOrders`, the valid closed crane has
0 px of intersection line and More tucked 1,746 px (contours 15,890 and
12,881 px). **(V2)** This holds only in that configuration: with fold walls on,
the valid crane shows 4,234 px of false intersections. It is one camera on one
valid model, so it is an illustration of the defect, not a validated gate. The
gate should be a geometric crossing count.

**Faceting is a small effect under soft light.** Rendering with flat triangle
normals instead of panel-smooth normals changes the More tucked image by a mean
absolute error of about 0.1% (0.13% over RGB, **(V2)**). The heavy faceting in
today's viewer comes from its hard directional light without shadows, not from
the mesh. **(V2)** The pixel counts first reported with this (256 px, 811 px)
did not reproduce under any per-pixel rule and are not quoted.

**Thickness does not rescue the sketch.** At 0.1 mm the difference from zero
thickness is small; at 0.4 mm the valid closed crane turns into cardboard with
a stepped head.

**Normals.** Blender's angle-weighted panel normals and the study's
area-weighted `PaperLighting` normals differ by a median 0.76° over 1,344
corners (95th percentile 8.0°). Eight corners average to a direction behind
their own triangle; these are the eight `PaperLighting` deliberately leaves
flat, and Blender would use the reversed average.

**three.js.** A three.js r186 page with panel normals, soft shadows, GTAO
ambient occlusion and AgX came out harsher than Cycles (hard-edged shadow,
weak occlusion). **(V2)** Loading the study's *complete-paper* GLB, whose
coincident layers sit at the same depth, draws the closed crane 95.2% in the
back colour. The repository's default export already avoids this without
moving any vertex: its *visible-paper* scene drops buried coplanar sides, and
with it the closed crane is 100% front. The whole-crane gallery writes the
complete scene (`WholeCraneGallery.hs:192`). So layer offsets are not needed
for a viewer; using the visible scene is.

| Render (1200 × 1000, M1 Max) | Times, s | Median |
| --- | --- | ---: |
| Cycles paper, closed crane | 12.86, 11.47, 11.85 | 11.9 |
| Cycles paper, More tucked | 21.21, 15.35, 24.75 | 21.2 |
| Cycles paper, square twist | 12.42, 15.88, 12.46 | 12.5 |
| Freestyle lines (one run each) | 20.6–50.3 | — |
| Line Art to SVG (one run each) | 0.007–0.15 | — |

The first-ever Cycles run spent 145 s compiling Metal kernels. Scale: 1,409 px
per sheet side, so 0.1 mm of paper is 0.94 px.

## What it shows

- On valid geometry, a paper recipe (soft light, contact shadow, two-sided
  colour, panel-smooth normals, a little translucency) is most of the way to a
  refined picture.
- On the More tucked sketch, no recipe helps: the defects are in the shape.
- Line Art can make a vector drawing from 3D geometry in about 0.01 s, a
  possible reference for book-style line work on non-flat poses.

## What it does not show

- No physics: nothing here inflates, relaxes or repairs a pose.
- No owner review. "Refined" was judged by the experimenter, from one camera,
  one light setup and one palette (`#eee6cf` and `#c58440`).
- Valid *curved* geometry was not rendered here; [Y1](Y1-valid-curved-looks.md)
  does that.

## Incidental finding

`senbazuru export examples/squaretwist.fold` refuses with "panel 8 needs a
planar surface for the visible glTF scene"; face 8 is out of plane by only
about 1e-6. `--all-layers` works. Re-checked against the HEAD binary on
2026-09-28.

## Reproduce

Run from the repository root with `stack run` (in this checkout `stack exec`
can resolve to a stale 2026-09-06 binary, [V](V-verification.md) cluster V1).
Blender's bundled Python 3.11 runs `scripts/X1-render/mkcfg.py` to write render
configurations; `run_all.sh` renders them with
`Blender -b --factory-startup --python render.py -- configs/NAME.json`;
`contact.sh` assembles the sheets. The three.js stills need `three/server.py`
and `three/index.html?model=spread-0&normals=panels`. The scripts hold the
scratch paths they ran from; change them before rerunning.
