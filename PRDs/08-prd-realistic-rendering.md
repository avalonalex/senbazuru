# 08 — Realistic rendering (feature 3b)

Written 2026-09-15 against `568dcb6`; requirements only, nothing implemented.
Terms are defined in one clause and linked to
[glossary-additions.md](glossary-additions.md) or
[the glossary](../docs/glossary.md). Decisions are cited from
[decisions.md](decisions.md), the record every PRD file follows; this file
specifies [D19](decisions.md#d19-realistic-rendering), and every other decision cited
below is also said in a clause. Sketches are marked **SKETCH**; web
sources were fetched on 2026-09-15. *Spec* means the glTF 2.0 specification,
`specification/2.0/Specification.adoc` in KhronosGroup/glTF at commit
`c18432787e6d545a1218c1926ccdcfaffd4c116b` (committed 2026-09-12); schema files
are under `specification/2.0/schema/` at the same commit.

## Summary

"Realistic" is four independent *fidelity axes*, the dimensions every new
output records its position on
([glossary-additions](glossary-additions.md#realistic-rendering)): geometry,
motion, appearance and lines. This PRD owns them and four pieces of work:

1. **Fidelity metadata.** New output modes say where they sit, in glTF
   `extras.senbazuru.fidelity` and in an SVG `<desc>`. Default outputs and the
   33 tracked goldens do not change.
2. **M7a, a smooth-shaded GLB mode.** Lighting normals split at *feature edges*
   (every edge that is not a `J` join,
   [glossary-additions](glossary-additions.md#realistic-rendering)), and texture
   coordinates from material coordinates. Shown first on bent meshes that the
   study (the material-bending experiments in `study/fold-material`, not library
   code) already accepts; needs nothing else from this series.
3. **M7b, motion and lines.** "G1", animation of checked rigid *routes* (paths
   between states, [glossary-additions](glossary-additions.md#assurance)), as nested
   glTF nodes; W1, an exact hidden-line drawing of any surface, with
   `--lines features|mesh`; glTF crease lines as a measured spike. "G1" is the
   level "G0 animated along a checked route" of research G's fidelity ladder, G0
   being today's static rigid output
   ([G](research/G-realistic-rendering-and-simulation.md) "E. Proposed fidelity
   ladder, with repository coverage", finding 23); it is unrelated to gap G1, the
   rule for an anchor that a new crease passes through
   ([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)).
4. **Honesty.** For a rigid sequence these add motion, texture coordinates and
   perhaps crease lines, **not realistic paper**. No bent paper comes out of the
   `senbazuru` CLI before M8.

Producing bent paper is [07](07-prd-material-consumption.md); the records read
here are [01](01-architecture.md); milestone order is
[10](10-roadmap-risks-questions.md).

## Problem and evidence

### What the GLB writes today

A GLB is glTF's binary 3D file ([glossary](../docs/glossary.md#this-project)).

| Property | Today | Where |
| --- | --- | --- |
| Scenes | "Visible paper" (buried coplanar paper removed) and "Complete paper" | [`Gltf.hs:13-20`](../src/Senbazuru/Render/Gltf.hs#L13-L20), [`:231-235`](../src/Senbazuru/Render/Gltf.hs#L231-L235) |
| Two colours | Each face written twice, the second with reversed *winding* (corner order), into `paper` and `paper underside` | [`:31-42`](../src/Senbazuru/Render/Gltf.hs#L31-L42), [`:344-346`](../src/Senbazuru/Render/Gltf.hs#L344-L346) |
| Materials | Base colour, metallic 0, roughness 1; no `doubleSided`, so viewers skip triangles seen from behind (*back-face culling*) | [`:384`](../src/Senbazuru/Render/Gltf.hs#L384); spec `Specification.adoc:2470` |
| Normals | None: "flat is exactly right for paper" | [`:49-50`](../src/Senbazuru/Render/Gltf.hs#L49-L50) |
| Lines, animation | None | [`:52-55`](../src/Senbazuru/Render/Gltf.hs#L52-L55) |
| Metadata | `extras.senbazuru`: `version`, `frame`, optional `physicalThickness`, `layerRequirements`; frame extras cut to three keys | [`:236-243`](../src/Senbazuru/Render/Gltf.hs#L236-L243) |
| Positions | Rounded to 1e-6 of the model's span through an `Integer` | [`:261-264`](../src/Senbazuru/Render/Gltf.hs#L261-L264), [`:311-314`](../src/Senbazuru/Render/Gltf.hs#L311-L314) |

A *normal* is the unit direction perpendicular to a surface, which lighting
reads ([glossary](../docs/glossary.md#geometry)). With none written, viewers
compute one per triangle and three.js (the JavaScript 3D library the study's
viewer pages load) shades flat
([G](research/G-realistic-rendering-and-simulation.md) "A. What the repository
renders today", finding 1, code read). That is right for rigid panels. The
study's bent meshes are hundreds of planar triangles joined by `J` (join) edges,
which mark two triangles as one piece of paper
([`CraneSpread.hs:210-214`](../study/fold-material/CraneSpread.hs#L210-L214),
[`UncreasedSurface.hs:1-10`](../study/fold-material/UncreasedSurface.hs#L1-L10)),
exported through this path
([`CraneSpreadGallery.hs:103-105`](../study/fold-material/CraneSpreadGallery.hs#L103-L105),
[`WingBendingGallery.hs:85-87`](../study/fold-material/WingBendingGallery.hs#L85-L87)),
so a curved wing shows its facets. The study's WebGL viewer instead averages
normals "within a panel only"
([`viewer.html:218-229`](../study/fold-material/viewer.html#L218-L229)), the rule
M7a adopts, but it reads embedded JSON, not glTF
([C](research/C-renderers-cli-formats.md) "(b) glTF today", finding 13).

### What the SVG draws on a bent mesh

For paper in the air, `Render.CreasePattern` tries `Render.Projected`, else falls
back to *the painter*, which paints whole faces back to front with "every crease …
drawn over them, buried or not"
([`CreasePattern.hs:235`](../src/Senbazuru/Render/CreasePattern.hs#L235),
[`:250-259`](../src/Senbazuru/Render/CreasePattern.hs#L250-L259)). Three
tolerances disagree:

| Where | Tolerance | Effect |
| --- | --- | --- |
| `Render.Projected` | depth gaps at `1e-9 ×` model span ([`Projected.hs:55-57`](../src/Senbazuru/Render/Projected.hs#L55-L57)) | gaps changing sign beyond it decline the view ([`:148-154`](../src/Senbazuru/Render/Projected.hs#L148-L154)); a coverage failure is `ImpossibleStacking` ([`:77-78`](../src/Senbazuru/Render/Projected.hs#L77-L78)) |
| `Origami.Contact` | `panelTolerance = 1e-7` ([`Contact.hs:83-84`](../src/Senbazuru/Origami/Contact.hs#L83-L84)) | what the study's contact check accepts |
| `Render.PaperMesh` | coplanar groups at `1e-6 ×` span ([`PaperMesh.hs:106-112`](../src/Senbazuru/Render/PaperMesh.hs#L106-L112)) | the GLB visible scene |

In one study construction two layers pass through each other by 6.21e-9 (a
*crossing*: their minimum gap is −6.21e-9,
[B](research/B-material-study-mechanics.md) "Risks (question d)", finding 15,
repository notes). That is inside contact's 1e-7, so the contact check passes
it, and beyond `Projected`'s hair, so `Projected` declines and the drawing goes
to the painter, which draws every crease on top, buried or not. The GLB's visible
scene groups layers at 1e-6 of the span, too coarse to show such a crossing at
all (same finding). The docs record the painter's result on the crane-root
meshes (the wing-root study's, `senbazuru-material-study --crane-root`,
[`usage.md:446`](../docs/usage.md)): "The SVG
outline path also retains some buried crease lines here"
([`usage.md:464-465`](../docs/usage.md), [`tour.md:596-597`](../docs/tour.md)).
[#206](https://github.com/avalonalex/senbazuru/issues/206) records
`ImpossibleStacking` on an accepted 4,312-triangle crane-root mesh. Whether the
crane-spread meshes (the crane's wing bent open by the study's solver with every
body vertex held, 392 and 1,192 triangles,
[`spreading-connected-wing.md:25`](../docs/notes/spreading-connected-wing.md))
reach the painter is recorded nowhere. Today's nearest "wireframe", `--no-fill`,
strokes buried creases too ([C](research/C-renderers-cli-formats.md) "(a) What
each backend consumes, and the layering rule", finding 3).

### Nothing records what an output claims

`Page`'s one text field, `pageTitle`, becomes `<title>`
([`Svg.hs:81-94`](../src/Senbazuru/Render/Svg.hs#L81-L94),
[`:143-145`](../src/Senbazuru/Render/Svg.hs#L143-L145)). A settled wing's GLB cannot say it is an illustrative
zero-thickness solve. The project made this mistake once: a display spacing named
`--thickness` shipped and was removed
([paper-thickness.md](../docs/notes/paper-thickness.md)).

### Silhouettes

A *silhouette* is where a surface turns away from the viewer
([glossary-additions](glossary-additions.md#realistic-rendering)). On flat panels
it lies only on creases and boundaries: dropping non-silhouette edges from the
crane's offset view removed 6 of the 242 edge strokes it draws
([`layer-numbers.md:111-115`](../docs/notes/layer-numbers.md)). On a curved mesh
it crosses panels. `examples/puffed-square.fold` is a hand-made dome:

```bash
jq -c '{vertices: (.vertices_coords|length), faces: (.faces_vertices|length), edges: (.edges_vertices|length), assign: (.edges_assignment|group_by(.)|map({(.[0]): length})|add)}' examples/puffed-square.fold
```

prints `{"vertices":121,"faces":200,"edges":320,"assign":{"B":40,"F":280}}`. With
`--hide-flat`, "Of 320 drawn paths 40 remain"
([`the-puff-is-a-drawing.md:117-118`](../docs/notes/the-puff-is-a-drawing.md)).
[#104](https://github.com/avalonalex/senbazuru/issues/104) proposes a silhouette
pass in the default renderer.

### No motion

Nothing writes glTF animation ([G](research/G-realistic-rendering-and-simulation.md)
"A. What the repository renders today", finding 5, grep).
[#56](https://github.com/avalonalex/senbazuru/issues/56) proposes one node per face
with rotation and translation *keys* (values at chosen times that a viewer
interpolates between). glTF interpolates translations linearly and rotations
along the short great-circle arc, *slerp* (spec `Specification.adoc:3560-3600`).
A face turning about a hinge that misses its node's origin needs a translation
that is not linear in time, but glTF interpolates translations linearly, so the
hinge comes apart between keys: halfway through a half turn the gap equals the
hinge's distance from the node's origin ([G](research/G-realistic-rendering-and-simulation.md)
"C. glTF realism", finding 18a, derived). The per-face transforms #56 calls
discarded exist as `foldedPlacements`
([`Folding.hs:283-323`](../src/Senbazuru/Origami/Folding.hs#L283-L323)).

## Goals

1. Every new output mode records its fidelity on four axes; default outputs and
   the 33 goldens (`git ls-files test/golden | wc -l`) stay byte-identical.
2. Bent meshes shade smoothly in any glTF viewer, positions and material
   references unchanged (M7a).
3. An SVG line drawing of any surface whose hidden lines agree with the contact
   check that accepted it (W1).
4. Checked rigid routes play in generic viewers with no face changing shape and
   no crease of the node tree opening between keys (motion level G1).
5. Nothing about glTF lines is required before it is measured.

## Non-goals

| Out of scope | Why |
| --- | --- |
| Thickness offsets, rounded creases (*fillets*) | Research: a second bend rounded over a first stretches 200% ([two-bends-need-more-than-radii.md](../docs/notes/two-bends-need-more-than-radii.md)) |
| Animated flexible routes | No checked flexible path exists ([G](research/G-realistic-rendering-and-simulation.md) "E. Proposed fidelity ladder, with repository coverage", finding 23) |
| Changing the default render or export, #104's silhouettes included | Goldens stay byte-identical |
| Drawing x-ray lines or cut-aways (W2, [#48](https://github.com/avalonalex/senbazuru/issues/48), [#49](https://github.com/avalonalex/senbazuru/issues/49)) | W1 computes the hidden intervals; choosing what to show is those issues |
| Calibrated appearance; material extensions by default | Sheen on paper is untested ([G](research/G-realistic-rendering-and-simulation.md) "Unverified") |
| Settle requests, holds, settled files and failure scope | [07](07-prd-material-consumption.md) |

## What this makes realistic, and what it does not

| Axis and level | Rigid sequence (planar panels) | Bent mesh (settled wing, `puffed-square.fold`) |
| --- | --- | --- |
| Appearance A1, split normals | identical to the flat normals viewers already compute | smooth within panels, sharp at creases |
| Appearance A2a, texture coordinates | invisible until a texture exists | invisible until a texture exists |
| Lines W1 | the creases and boundaries today's drawing shows | adds silhouettes; hides what contact says is buried |
| Motion G1 | **new**: checked routes play | not offered |
| glTF crease lines | new, if the spike passes | new, if the spike passes |

Why A1 cannot change a rigid picture: take fixture state 2 of
`examples/quarter-fold-steps.fold`, the square folded into quarters. The script
reads `file_frames[1]`, which is state 2, not an off-by-one: FOLD's top-level
object is the fixture's state 0, as [D16](decisions.md#d16-testing-and-acceptance) numbers
it. There edge 9 is a *valley* (positive *fold angle*,
[glossary](../docs/glossary.md#origami)) at +180°:

```bash
python3 -c '
import json
d = json.load(open("examples/quarter-fold-steps.fold"))
fr = d["file_frames"][1]; P = fr["vertices_coords"]; F = fr["faces_vertices"]; a, b = fr["edges_vertices"][9]
def n(r):
    # Newell: the face normal scaled by twice the face area
    s = [0.0, 0.0, 0.0]
    for i in range(len(r)):
        p = P[r[i]] + [0]*(3-len(P[r[i]])); q = P[r[(i+1)%len(r)]] + [0]*(3-len(P[r[(i+1)%len(r)]]))
        s[0] += (p[1]-q[1])*(p[2]+q[2]); s[1] += (p[2]-q[2])*(p[0]+q[0]); s[2] += (p[0]-q[0])*(p[1]+q[1])
    return s
fs = [i for i, r in enumerate(F) if a in r and b in r]
print(fr["edges_assignment"][9], fr["edges_foldAngle"][9], fs, [n(F[i]) for i in fs])'
```

prints `V 180 [0, 1] [[0.0, 0.0, 0.5], [0.0, 0.0, -0.5]]`. `n` is Newell's
formula, which returns a face's normal scaled by twice its area; these faces have
area 1/4, so ±0.5 is ±z. A viewer computes those normals anyway, and their
average across the crease is zero.
That zero is why normals and line offsets split at every feature edge and use
each side's own normal.

**For a rigid sequence, M7 adds animation, optional texture coordinates and
optional glTF crease lines, not realistic paper.** A1 and W1 matter on meshes
that are not flat: settled surfaces, future thickness offsets, and non-planar
inputs such as `puffed-square.fold`. **No bent paper is reachable from the
`senbazuru` CLI before M8**; until then it comes from
`senbazuru-material-study --sequence` (M6, [07](07-prd-material-consumption.md)).

## Users and scenarios

1. **A study reader** opens the crane-spread curved wing in Blender and sees a
   bending wing, not 392 facets; its extras say `"geometry": "bent zero-thickness"` (M7a).
2. **An author** runs `senbazuru run blintz.foldseq -o blintz.glb --animate`,
   watches four corners fold in a browser, and `--report` counts keys and
   refolds (M7b).
3. **A diagrammer** runs `senbazuru render wing.fold --view iso --lines features`
   for a settled wing drawn with no buried creases (M7b).
4. **A maintainer** reads `<desc>` or `extras.senbazuru.fidelity` before
   trusting a screenshot, and adds `--lines mesh` to see the triangulation.

## Requirements

### Fidelity metadata

- **R-08-1.** Every output of a new mode records geometry, motion, appearance and
  lines ([D19](decisions.md#d19-realistic-rendering)): the M7a GLB mode, crease-line and animated GLBs, W1 SVGs, and the settled
  files of [07](07-prd-material-consumption.md). glTF writes
  `extras.senbazuru.fidelity` beside `frame`; SVG writes `<desc>`.
- **R-08-2.** `Render.Svg.Page` gains `pageDescription :: Maybe Text`, `Nothing`
  in `defaultPage`; `renderSvg` emits `<desc>` right after `<title>`, through
  `escapeXml`, only when it is `Just`.
- **R-08-3.** Levels are one closed type rendered by one function for both
  writers. A level gets its constructor in the PR that first writes it, so a level
  nothing can produce (thickness offsets, animated flexible) has none.
- **R-08-4.** Default outputs carry no fidelity record.

### Feature edges

- **R-08-5.** A realistic output's *feature edges* are every edge of the written
  state whose assignment is not `J`, at any angle, boundaries included
  ([glossary-additions](glossary-additions.md#realistic-rendering)). They are not
  `Origami.Surface.surfaceFeatures`.

### M7a: normals and texture coordinates

- **R-08-6.** A new GLB mode writes `NORMAL`. Faces form *smoothing regions*,
  connected across `J` edges only. Each material vertex gets one normal per
  region: its faces' unnormalised normals, computed from **packed** (rounded, as
  written) positions, summed and normalised. A clipped visible-scene corner
  combines its face's corner normals by its `materialWeights` (the weighted
  original vertices it records), then normalises.
- **R-08-7.** The underside primitive has its own `NORMAL` accessor, the negation
  of the top's (negated on purpose: lighting reads `NORMAL` as written, see
  Design); both share one `POSITION` accessor.
- **R-08-8.** A summed normal of zero length is refused naming vertex and face.
- **R-08-9.** Only the entry point taking `Surface V2` writes `TEXCOORD_0`:
  `(s, t) = ((u − u₀)/S, 1 − (v − v₀)/S)` (`1 −` because glTF's t runs down the
  image, see Design), `(u₀, v₀)` the material bounding box's south-west corner,
  `S` its larger side, rounded to 1e-6 through an `Integer`. The
  `Surface material` entry point cannot, and records the omission.
  `export --fold --smooth` must keep the `Folded` that `foldFrameWith` returns and
  build its surface with `surfaceFromFolded`, so that it reaches the `Surface V2`
  entry point. Today `paperFor` returns only a `Frame`
  ([`Cli.hs:775`](../app/Senbazuru/Cli.hs#L775)) and `renderGlb` builds a
  `Surface (Maybe V2)` with `surfaceFromFrame`
  ([`Gltf.hs:210`](../src/Senbazuru/Render/Gltf.hs#L210)).
- **R-08-10.** On planar panels every normal equals its face's flat normal. The
  mode adds no texture, material extension or `doubleSided`.
- **R-08-11.** The study's gallery programs (`CraneSpreadGallery`,
  `WingBendingGallery`) write a smooth GLB beside every accepted crane-spread and
  wing-bending GLB (wing-bending: a triangular sheet held at its wide root and
  bent by a small grip near its tip, [`usage.md:357-360`](../docs/usage.md)), each passing `study/gltf/validate.cjs` with 0
  errors and 0 warnings.

### glTF crease lines: a spike

- **R-08-12.** A spike, not a requirement, writes `mode` 1 (`LINES`) primitives in
  visible-scene exports only, built as in Design, with the display offset
  `lineLift` in `extras.senbazuru.lineLift` beside `frame`, never inside it.
  Complete-scene exports carry no lines. Its measurements go into a
  `docs/notes/` note.
- **R-08-13.** If any measurement fails, the fallback ships: segments as data in
  `extras.senbazuru.lines`, drawn by `study/gltf/viewer.html`, and no `LINES`.

### Textures (A2b) and translucency (A3)

- **R-08-14.** Texture work starts after owner decision 6; image bytes are
  deterministic; a vendored image has provenance in `examples/README.md`.
- **R-08-15.** A3 (`KHR_materials_diffuse_transmission`) is written only behind a
  flag, keeps the core material as fallback, and is listed in `extensionsUsed`,
  never `extensionsRequired`.

### W1: an exact line drawing

- **R-08-16.** A pure library function draws a surface as lines for an
  orthographic basis, returning a `Diagram` and a `LineReport`.
- **R-08-17.** Candidates: feature edges; silhouettes, meaning every edge shared
  by two faces of which one faces away from the reader (n̂ · forward > 1e-9,
  Design step 2) and the other does not, **of any assignment**; every edge of one
  face. An edge-on face counts as not away, so a band of edge-on faces between
  two slopes gives one outline, not two. Both the any-assignment rule and the
  1e-9 edge-on threshold are [D19](decisions.md#d19-realistic-rendering)'s.
- **R-08-18.** Visibility is exact per segment interval (Design), with band
  τ = `panelTolerance × S`. Faces containing a segment's edge never occlude it (a
  crease always lies within the band of its own faces, so they would hide it).
- **R-08-19.** Inside the band, triangle-level `faceOrders` (which face lies over
  which, [glossary](../docs/glossary.md#the-fold-format)), closed transitively,
  decide; unordered ties are drawn and their total length reported and written in
  `<desc>`; a cycle is refused by name.
- **R-08-20.** A fill through `projectedForm` is optional; `Nothing` or
  `Left ImpossibleStacking` yields the line drawing alone, recorded.
- **R-08-21.** CLI: `render --lines features|mesh` and
  `run -o x.svg --lines features|mesh`; without the flag, today's path runs;
  refused with `--offset`.
- **R-08-22.** `features` styles provenance lines as `strokeFor` does for a folded
  form (`--hide-flat` hides `F`, `U`) and silhouettes at crease weight whatever
  their assignment; `mesh` adds visible non-silhouette `J` at `themeBuriedWidth`.

### G1: animating checked rigid routes

- **R-08-23.** An animated GLB is a new file shape (`run -o x.glb --animate`);
  static exports stay byte-identical.
- **R-08-24.** One node hierarchy per *checkpoint interval*, the steps between two
  `checkpoint`s or between one and the start or end
  ([glossary-additions](glossary-additions.md#the-sequence-language)), over that
  interval's final cut pattern (creases split where they cross), along
  `Origami.Folding`'s own *spanning walk*, the tree of crossings from the anchor
  face that places each face once, read through `foldedWalk` (05 L15); its
  creases are *tree creases*. A hinge node and a mesh node per face; meshes in
  material coordinates. The hierarchy is per interval because a `checkpoint`
  may remove creases ([D19](decisions.md#d19-realistic-rendering)).
- **R-08-25.** An earlier state keys each tree crease at the angle of that state's
  crease containing its segment, or 0 if none exists yet.
- **R-08-26.** *Presentation*, turning the whole model for the reader
  ([glossary-additions](glossary-additions.md#running-a-sequence)), is a pivot
  node per presentation move, origin at the centre of the displayed model's
  bounding box before the move (the point
  [D5](decisions.md#d5-presentation-and-the-readers-side) turns about,
  [02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper)), outermost
  last, keys at most 90° apart: at least three keys per half turn, the fewest
  evenly spaced keys that keep every interval under the 180° at which slerp's
  direction is ambiguous (Design, "Why nested nodes").
- **R-08-27.** A new sub-hierarchy starts at each *re-anchor*
  ([glossary-additions](glossary-additions.md#running-a-sequence)) and each
  `StateOnly` transition (a state claimed without a checked route,
  [glossary-additions](glossary-additions.md#assurance)); they switch by scale 0/1
  under `STEP` interpolation, which holds each key's value until the next, at one
  key time, recorded in `extras.senbazuru.keys`
  ([D19](decisions.md#d19-realistic-rendering)).
- **R-08-28.** Keys come from `recordPoseAt … (PoseOnRoute p)`
  ([02 §10](02-language-semantics.md#10-assurance)). `RunSettings.keyDensity` n
  places n + 1 keys per route, at p = 0, 1/n, …, 1, independent of `sample`; an
  interval turning any tree crease by 180° or more gets a key at its middle `p`,
  repeatedly.
- **R-08-29.** Each key interval is refolded once at the per-crease mean of its two
  keys' angles, the pose the viewer shows halfway (a *midpoint refold*). A failure
  inserts the route pose at the interval's middle `p` (a *subdivision*) and
  refolds both halves. After `RunSettings.keySubdivisionBudget` subdivisions on
  one route, a counted budget whose default is set when A-22 is measured, the run
  refuses naming the step. `--report` counts keys, midpoint refolds and
  subdivisions.
- **R-08-30.** The animated scene is complete paper; no morph targets, skins,
  `KHR_animation_pointer` or `KHR_node_visibility`.

### #104

- **R-08-31.** M7b advances #104 without closing it; silhouettes appear only with
  `--lines`; its done-when names `--view front`, as [D19](decisions.md#d19-realistic-rendering)
  decides and [§3](decisions.md#3-recorded-text-this-design-changes) row 7
  records (Design, "#104, amended").

## Design

### The four axes and where they are written

| Axis | Levels | Today |
| --- | --- | --- |
| Geometry | rigid panels · bent zero-thickness ([07](07-prd-material-consumption.md)) · thickness offsets (research) · as read (a file senbazuru did not produce) | rigid |
| Motion | static · animated rigid (checked routes) · animated flexible (research) | static |
| Appearance | A0 two flat colours · A1 split normals · A2a `TEXCOORD_0` · A2b textures · A3 diffuse translucency | A0 |
| Lines | W0 book notation on planar panels · W1 exact line drawing · W2 x-ray lines and cut-aways | W0 |

**SKETCH.**

```haskell
-- Senbazuru.Render.Fidelity
data Geometry   = RigidPanels | BentZeroThickness | AsRead     -- AsRead: a file senbazuru did not produce
data Motion     = Static | AnimatedRigid
data Appearance = FlatColours | SplitNormals | SplitNormalsAndTexcoords
data Lines      = BookNotation | ExactLines LineReport | NoGltfLines | GltfLines Double | GltfLinesInExtras
data Fidelity   = Fidelity { geometry :: Geometry, motion :: Motion, appearance :: Appearance
                           , lines :: Lines, omissions :: [Text] }
fidelityJson :: Fidelity -> Data.Aeson.Value
fidelityText :: Fidelity -> Text                               -- one line, for <desc>
```

Renderers fill in motion, appearance and lines. Geometry comes from the producer,
because a `Surface` cannot tell a settled mesh from a rigid state: the runner says
`RigidPanels`, a settle `BentZeroThickness`, `export` of a file `AsRead`. That
last level exists because `export --smooth` of an arbitrary file cannot know
whether its panels are rigid (`puffed-square.fold` is a hand-made dome), so it
must not claim either ([D19](decisions.md#d19-realistic-rendering)). What a
crane-spread smooth GLB (bent) and a W1 SVG of the rigid folded crane would carry
(**SKETCH**):

```text
"fidelity": {"geometry": "bent zero-thickness", "motion": "static", "appearance": "A1+A2a", "lines": "none"}
<desc>senbazuru: geometry rigid; motion static; appearance A0; lines W1 (unordered ties 0 sheet lengths; fill not asked)</desc>
```

Only new modes, because any key in default output moves `crane-folded.glb`,
`quarter-fold-folded.glb` and `simple.glb`
([`GltfSpec.hs:644-658`](../test/Senbazuru/Render/GltfSpec.hs#L644-L658)).
`pageDescription` breaks no call site: every other `Page` in `src`, `app`, `test`
and `study` is a record update of `defaultPage`, or of `testPage`, itself one
(`grep -rn --include='*.hs' -E "Page \{|defaultPage \{" src app test study`; e.g.
[`Cli.hs:909-916`](../app/Senbazuru/Cli.hs#L909-L916),
[`SvgSpec.hs:141-147`](../test/Senbazuru/Render/SvgSpec.hs#L141-L147)).

Rejected: a sidecar file, which does not travel with the picture; fidelity inside
`frame`, which is FOLD data a reader may reload. [D19](decisions.md#d19-realistic-rendering)
rejects both.

### Feature edges

Every non-`J` edge of the written state, so `run -o x.glb --smooth` and
`export x.fold --smooth` agree on any written frame. Not `surfaceFeatures`, which
keeps `F` only at a nonzero angle
([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278)), while the state
rule writes a flat precrease as `F` at exactly 0
([D4](decisions.md#d4-written-frames-follow-the-state-rule)); `examples/crane.fold` has 20 such edges
(`jq -c '.edges_assignment|group_by(.)|map({(.[0]): length})|add' examples/crane.fold`
prints `{"B":10,"F":20,"M":58,"V":41}`). Not dihedral
thresholds ("draw an edge when its faces meet at more than some angle"): a crease
at 0 would vanish, and a relaxed double fold bends 2.017° across internal triangle
edges, so three.js's `EdgesGeometry`, which by default draws an edge where faces
meet at more than 1°, draws its triangulation
([G](research/G-realistic-rendering-and-simulation.md) "D. SVG wireframe of a 3D
paper surface", findings 19-20). Where a settled panel bends across an `F`
precrease, shading splits there, as it should: the paper has a crease there.

### M7a: normals and texture coordinates

**SKETCH.**

```haskell
-- Senbazuru.Render.Gltf
data Shading    = FlatShading | SplitNormals
data GlbOptions = GlbOptions { glbScenes :: ExportMode, glbShading :: Shading
                             , glbLines :: CreaseLines, glbGeometry :: Geometry }
renderSurfaceGlbWith  :: GlbOptions -> Budget -> Maybe Text -> Surface material -> Either GltfError ByteString
renderMaterialGlbWith :: GlbOptions -> Budget -> Maybe Text -> Surface V2       -> Either GltfError ByteString
renderSurfaceGlb budget mode = renderSurfaceGlbWith (plainGlb mode) budget   -- no NORMAL, UVs, lines, fidelity
```

Only `renderMaterialGlbWith` writes `TEXCOORD_0`: the type that promises material
coordinates is the permission to write them
([`Surface.hs:15-19`](../src/Senbazuru/Origami/Surface.hs#L15-L19)). A caller
holding `Surface (Maybe V2)` calls `requireMaterialCoordinates` first
([`:215-222`](../src/Senbazuru/Origami/Surface.hs#L215-L222)) or accepts the
omission. `export --fold --smooth` is that second caller today, because its
`Folded` is dropped before the GLB writer sees it; R-08-9 requires keeping it for
`surfaceFromFolded`, which knows material coordinates. `--smooth` and `--animate`
are proposed spellings the PRs settle.

**Regions.** `spreadSurface` marks an edge `J` exactly when no source edge
contains it ([`CraneSpread.hs:210-214`](../study/fold-material/CraneSpread.hs#L210-L214)),
so a crane-spread region is one source panel's triangles, and a wing piece is one
region. A vertex on a crease between panels gets two normals; one inside a panel
gets one. Regions come from `J` connectivity, not `senbazuru:source_panels`,
because `transformSurface` drops frame extras
([`Surface.hs:287-292`](../src/Senbazuru/Origami/Surface.hs#L287-L292)); a test
checks both agree where both exist. An unnormalised face normal's length is
twice its area ([`Gltf.hs:278`](../src/Senbazuru/Render/Gltf.hs#L278)), so large
triangles weigh more, as in the study viewer. Normals come from packed positions
so their bytes depend only on bytes already written; raw positions computed
through `sin` and `cos` can differ in their last bits between platforms
([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
"Platform-sensitive bytes (for task d)", findings 12 and 14).

**Two lines that look like typos.**

- **The underside's normal is negated.** Both copies share one `POSITION`
  accessor ([`Gltf.hs:380`](../src/Senbazuru/Render/Gltf.hs#L380)). The underside
  copy is wound to face down, but lighting reads `NORMAL` as written; sharing the
  top's would light the underside from inside the paper. With `doubleSided`
  false nothing flips it (spec `Specification.adoc:2470-2472`).
- **`t = 1 − (v − v₀)/S`.** glTF puts texture coordinate (0, 0) at the image's
  upper-left corner (spec `Specification.adoc:2141`); the sheet compass puts north
  at +v ([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)). On a
  unit square, corner north-west
  (0, 1) becomes (0, 0), the image's top-left, and south-east (1, 0) becomes
  (1, 1). Without `1 −`, a north-up texture lands upside down.

Both spec lines:

```bash
curl -sS https://raw.githubusercontent.com/KhronosGroup/glTF/c18432787e6d545a1218c1926ccdcfaffd4c116b/specification/2.0/Specification.adoc | grep -n "upper left corner\|back-face culling"
```

| Rejected | Why |
| --- | --- |
| `doubleSided: true`, one primitive | One material for both sides ([G](research/G-realistic-rendering-and-simulation.md) "C. glTF realism", finding 15) |
| One region for the whole surface | "Smoothing across a crease makes it look rolled" ([`viewer.html:218`](../study/fold-material/viewer.html#L218)) |
| Regions by dihedral threshold or `source_panels` | Feature edges above; extras are lost through `transformSurface` |

**Demonstration.** M7a ships on existing meshes: the crane-spread curved
(392 triangles) and fine (1,192) wings, solved in 5.76 and 64.30 CPU seconds
([`spreading-connected-wing.md:37-39`](../docs/notes/spreading-connected-wing.md)),
and the wing-bending pieces. Its golden, `test/golden/bent-strip-smooth.glb`, uses
the analytic bent strip already pinned as `bent-strip.svg`, which needs no solve
([`WingBendingSpec.hs:94-100`](../test/WingBendingSpec.hs#L94-L100)).

### glTF crease lines: a spike before a requirement

glTF has no *polygon offset*, a depth bias that keeps lines drawn in front of the
triangles they lie on; Origami Simulator needs `polygonOffset` to keep raster
lines above its paper ([G](research/G-realistic-rendering-and-simulation.md)
"B. Geometry models, and whether a sequence could feed them", finding 10), and
whether three.js and Blender show `LINES` lying on triangles is unmeasured
([C](research/C-renderers-cli-formats.md) "Open questions", item 8). The spike:

1. Takes each coplanar group's feature edges.
2. For each side, keeps the stretches on that side's exposed pieces from
   `visiblePaper` ([`PaperMesh.hs:145-149`](../src/Senbazuru/Render/PaperMesh.hs#L145-L149)),
   judging a stretch along a piece's edge by `distanceOutside` at its midpoint,
   never by clipping (AGENTS.md "Gotchas";
   [`Polygon.hs:381`](../src/Senbazuru/Geometry/Polygon.hs#L381)).
3. Offsets each side's copy by `lineLift` along **that side's** panel normal; an
   averaged normal vanishes at a flat-folded crease (the quarter-fold numbers).
4. Picks `lineLift` above `quantumFor span`
   ([`Gltf.hs:261-264`](../src/Senbazuru/Render/Gltf.hs#L261-L264)), or packing
   rounds the line back onto the paper. This PRD states no value.
5. Uses an unlit ink material: lines with no `NORMAL` "SHOULD be rendered without
   lighting" and "SHOULD have widths of 1px" (spec `Specification.adoc:2491-2494`).

The complete scene keeps coincident layers, so lines there would show buried
creases. The fallback's viewer today "does not interpret material metadata"
([`study/gltf/README.md:3-5`](../study/gltf/README.md)).

### Textures (A2b) and translucency (A3)

A2b is owner decision 6. The library depends only on aeson, base, bytestring,
containers, filepath, tagsoup and text ([C](research/C-renderers-cli-formats.md)
"(e) Dependencies", finding 22), and nothing in the repository writes an image.

| Content | Encoder | Provenance |
| --- | --- | --- |
| Procedural (ours): fibre noise, or crease memory drawn from the pattern | PNG from stored (uncompressed) deflate blocks with CRC-32 and Adler-32 on `bytestring`; or `zlib-0.6.3.0` or `JuicyPixels-3.3.9` from lts-22.44 | ours; a texture drawn from a pattern inherits its design-licence position (AGENTS.md "Third-party material") |
| Vendored image | none | `examples/README.md` |

The lts-22.44 YAML, extracted from Stack's pantry cache (under the directory
`stack path --stack-root` prints, which is `~/.stack` unless `STACK_ROOT` says
otherwise) with

```bash
sqlite3 -readonly "$(stack path --stack-root)"/pantry/pantry.sqlite3 "select writefile('lts.yaml', contents) from blob where id = (select blob from url_blob where url like '%lts/22/44.yaml')"
```

hashes to the lock file's sha256 `238fa745…a1a9` ([C](research/C-renderers-cli-formats.md)
"(e) Dependencies", finding 23) and lists `JuicyPixels-3.3.9` (line 368) and `zlib-0.6.3.0` (line
13468). Their licences were not checked. PNG is a core glTF image type (spec
`Specification.adoc:447`, `:2135`).

A3's extension is a release candidate that three.js's `GLTFLoader` and Blender's
importer do not load ([G](research/G-realistic-rendering-and-simulation.md)
"C. glTF realism", findings 14 and 16); the core fallback keeps it safe. It has no
milestone.

### W1: an exact line drawing

**Concrete first.** From `--view front` (looking along +y,
[`Camera.hs:140-141`](../src/Senbazuru/Render/Camera.hs#L140-L141)), 90 of
`puffed-square.fold`'s 200 faces turn away, 20 are edge-on, and 27 shared `F`
edges separate a face turned away from the reader from one that is not: the
hump's outline, before visibility. Counting an edge wherever its faces' classes
differ at all gives 46, because a band of edge-on faces has an edge on each side;
R-08-17 takes one. From `--view iso` (direction (−1, 1, −1),
[`:135-136`](../src/Senbazuru/Render/Camera.hs#L135-L136)), no face turns away, so
the outline is the boundary.

```bash
python3 -c '
import json, math
d = json.load(open("examples/puffed-square.fold")); P = d["vertices_coords"]; F = d["faces_vertices"]
def n(r):
    # Newell: the face normal scaled by twice the face area, then made unit length
    s = [0.0, 0.0, 0.0]
    for i in range(len(r)):
        p, q = P[r[i]], P[r[(i+1)%len(r)]]
        s[0] += (p[1]-q[1])*(p[2]+q[2]); s[1] += (p[2]-q[2])*(p[0]+q[0]); s[2] += (p[0]-q[0])*(p[1]+q[1])
    return [x / math.sqrt(sum(y*y for y in s)) for x in s]
N = [n(r) for r in F]; own = {}
for i, r in enumerate(F):
    for j in range(len(r)): own.setdefault(tuple(sorted((r[j], r[(j+1)%len(r)]))), []).append(i)
shared = [v for v in own.values() if len(v) == 2]
print("upward normals:", sum(m[2] > 0 for m in N))
for name, f in [("iso", (-1, 1, -1)), ("front", (0, 1, 0))]:
    l = math.sqrt(sum(x*x for x in f)); c = [sum(m[k]*f[k] for k in range(3))/l for m in N]
    cls = ["away" if x > 1e-9 else "edge-on" if x >= -1e-9 else "towards" for x in c]
    print(name, "away:", cls.count("away"), "edge-on:", cls.count("edge-on"),
          "silhouettes:", sum((cls[i] == "away") != (cls[j] == "away") for i, j in shared),
          "classes differ:", sum(cls[i] != cls[j] for i, j in shared))'
```

prints `upward normals: 200`, then
`iso away: 0 edge-on: 0 silhouettes: 0 classes differ: 0` and
`front away: 90 edge-on: 20 silhouettes: 27 classes differ: 46`. It classifies
faces as step 2 below does. Faces are trusted as wound: every one of the 200
normals has a positive z component, so the dome is wound consistently upward.

**The algorithm.** Inputs: a `Surface material` with planar faces, an
orthographic `Basis` (*orthographic projection* flattens along parallel lines,
[glossary](../docs/glossary.md#geometry)), its `faceOrders`, the theme. *Depth*
is distance along the view direction, larger further away
([`Camera.hs:238-247`](../src/Senbazuru/Render/Camera.hs#L238-L247)).

The line that looks like a typo is step 6's "not containing the segment's edge".
A crease between touching layers always lies inside the band of the faces around
it; letting them decide would hide every crease on its own paper, and orders are
what tell the layer above from the crease's own layer.

1. **Band.** τ = `panelTolerance × S`. `S` is the length contact normalises by,
   since its tolerance is "a distance in the input coordinates" for "a unit sheet"
   ([`Contact.hs:22-24`](../src/Senbazuru/Origami/Contact.hs#L22-L24)): the
   material bounding box's larger side for `Surface V2`, the positions' `modelSpan`
   otherwise.
2. **Facing.** With n̂ the unit normal and forward pointing from the reader into
   the page, a face is away when n̂ · forward > 1e-9, towards when it is below
   −1e-9, and edge-on when `|n̂ · forward| ≤ 1e-9`, `Projected`'s threshold ([`Projected.hs:123`](../src/Senbazuru/Render/Projected.hs#L123)).
3. **Candidates** per R-08-17, each labelled with its assignment or as a
   silhouette.
4. **Project** a segment P₀P₁ onto the page; its depth is linear in t ∈ [0, 1].
5. **Broad phase.** Skip faces whose projected bounding box, grown by τ, misses
   the segment's.
6. **For each remaining face T not containing the segment's edge:**
   1. Clip t to T's projected outline (convex); an edge-on T occludes nothing.
   2. The gap g(t) = segment depth − T's depth is linear, because T is planar.
   3. Split where g = τ and g = −τ. Each piece is wholly g > τ (T nearer: hidden),
      g < −τ (T behind: no effect) or within the band (a tie).
   4. A tie goes to orders: nearness from `faceOrders`, read against the second
      face's normal and the view as `Projected.suppliedNearness` does
      ([`Projected.hs:127-146`](../src/Senbazuru/Render/Projected.hs#L127-L146)),
      closed as `Origami.Contact.closure` does
      ([`Contact.hs:152-164`](../src/Senbazuru/Origami/Contact.hs#L152-L164)).
      T nearer than every face containing the segment: hidden. Some face
      containing the segment nearer than T: no effect. Otherwise (unordered
      against at least one, and nearer than none): drawn, length added to the
      report. A cycle is refused, as contact
      refuses one ([`Contact.hs:132-134`](../src/Senbazuru/Origami/Contact.hs#L132-L134)).
7. **Draw** the complement of the hidden pieces as `Polyline`s
   ([`Diagram.hs:187-188`](../src/Senbazuru/Diagram.hs#L187-L188)).
8. **Optionally fill** through `projectedForm` (R-08-20).

τ is contact's tolerance, so a mesh that passes contact draws under the tolerance
that accepted it.

| Line | Stroke | Where |
| --- | --- | --- |
| `B`, `C` | border 1.6 | [`Style.hs:213`](../src/Senbazuru/Diagram/Style.hs#L213), [`:270-271`](../src/Senbazuru/Diagram/Style.hs#L270-L271) |
| `M`, `V` | crease 1.0, solid as on a folded form | [`:214`](../src/Senbazuru/Diagram/Style.hs#L214), [`:286-289`](../src/Senbazuru/Diagram/Style.hs#L286-L289) |
| `F`, `U` | ghost 0.6 unless `--hide-flat` | [`:215`](../src/Senbazuru/Diagram/Style.hs#L215), [`:274-279`](../src/Senbazuru/Diagram/Style.hs#L274-L279), [`Cli.hs:556-557`](../app/Senbazuru/Cli.hs#L556-L557) |
| silhouette, any assignment | crease 1.0, even with `--hide-flat` | #104: "drawn whether or not `--hide-flat` is on" |
| `J`, `--lines mesh` only | `themeBuriedWidth` 0.35 | [`Style.hs:233`](../src/Senbazuru/Diagram/Style.hs#L233) |

`Render.LineDrawing` produces a `Diagram` for `Render.Svg`, the rule for 2D
backends ([`architecture.md:176-182`](../docs/architecture.md)), and imports
`Style`, not `Render.CreasePattern`.

**SKETCH.**

```haskell
data LineMode   = FeatureLines | MeshLines
data FillResult = Filled | FillDeclined | FillNotAsked
data LineReport = LineReport { candidateSegments :: Int, pairsAfterBroadPhase :: Int
                             , unorderedTieLength :: Double, fillResult :: FillResult }
lineDrawing :: Theme -> LineMode -> Basis -> Surface material -> Either LineError (Diagram, LineReport)
```

| Rejected | Why |
| --- | --- |
| `Projected` on refined triangles, refusing where it declines | Refuses meshes contact accepts |
| Point-sampled depth tests | A sampling density to choose; exact intervals cost the same broad phase |
| A raster depth buffer | No vector output ([G](research/G-realistic-rendering-and-simulation.md) "B. Geometry models, and whether a sequence could feed them", finding 10) |
| Silhouettes from `J` edges only | Finds none of `puffed-square.fold`'s 27, which are `F` |

### "Wireframe": features or mesh

A conventional wireframe shows the triangulation, which is what shows curvature
on a flat page. W1 by default draws what the paper has plus silhouettes;
`strokeFor Join` is already `Nothing`
([`Style.hs:281`](../src/Senbazuru/Diagram/Style.hs#L281)). Which the request's
"SVG wireframe" means is owner decision 5. `--lines features` is the default;
`--lines mesh` adds visible `J` edges at the buried-sheet weight through the same
visibility.

### G1: animating checked rigid routes

**Why nested nodes.** In the blintz, the south-east corner turns about the crease
(1/2, 0)–(1, 1/2). `Origami.Folding` places a child face by a turn of the negated
fold angle about its parent's ring edge `a → b`
([`Folding.hs:650-653`](../src/Senbazuru/Origami/Folding.hs#L650-L653)), composed
as ``parent `after` turn`` ([`:619-624`](../src/Senbazuru/Origami/Folding.hs#L619-L624));
the central square's counterclockwise ring runs (1/2, 0) → (1, 1/2), so the
recipe's −180° *mountain* (negative fold angle) is a +180° turn about that direction. Python applying
Rodrigues' formula (the standard rotation of a point about an axis) as
`rotationAbout` does
([`Rigid.hs:114-129`](../src/Senbazuru/Geometry/Rigid.hs#L114-L129)):

| Turn | Corner (1, 0, 0) lands at | Node rotation as a *quaternion* (x, y, z, w), glTF's four-number rotation |
| --- | --- | --- |
| 90° | (0.75, 0.25, −0.3536) | (0.5, 0.5, 0, 0.7071) in FOLD axes; (0.5, 0, −0.5, 0.7071) after the (x, z, −y) swap ([`Gltf.hs:295-300`](../src/Senbazuru/Render/Gltf.hs#L295-L300)) |
| 180° | (0.5, 0.5, 0) | (0.7071, 0.7071, 0, 0) in FOLD axes; (0.7071, 0, −0.7071, 0) after the swap |

Half-way, the corner is below the sheet, as a mountain should be. With keys only
at 0° and 180°, the quaternions (0, 0, 0, 1) and (0.7071, 0.7071, 0, 0) have dot
product 0 in either axes; slerp "follows the short path along the great circle" (spec
`Specification.adoc:3596`), and there are two. Hence the 180° rule. Under 180°,
slerp between two turns about one fixed axis is a turn by the linearly
interpolated angle ([G](research/G-realistic-rendering-and-simulation.md)
"C. glTF realism", finding 18a, derived), so a crease with axis and origin fixed in its parent's
frame stays closed at every instant.

**The node pair.** For face f with parent p across tree crease a → b: hinge node
H_f, child of p's mesh node, with translation `a` and a keyed rotation about
`b − a` by the negated fold angle; and mesh node M_f, child of H_f, with
translation **`−a`**, holding f's mesh in material coordinates. The `−a` under the
`a` looks like a typo. Together they are `T(a) · R · T(−a)`, which is
`rotationAbout a (b − a) (−θ)` ([`Rigid.hs:114-117`](../src/Senbazuru/Geometry/Rigid.hs#L114-L117)),
so each mesh node's world transform is its parent's `after` the turn, exactly
`Folding`'s rule, and every translation is constant.

`spanningWalk` returns placements, not its tree
([`Folding.hs:572-577`](../src/Senbazuru/Origami/Folding.hs#L572-L577)). The
exporter needs each face's parent and crossing edge from **that** walk, because
there is to be "one spanning walk and not two implementations of it that can
drift" ([`:328-330`](../src/Senbazuru/Origami/Folding.hs#L328-L330)).
So `Origami.Folding` exports that tree as
`foldedWalk :: Folded -> IntMap (FaceId, EdgeId)` (**SKETCH**, 05 L15, at M7b,
[§5](decisions.md#5-type-sketch)): each face's parent and crossing edge, keyed
like `foldedPlacements` by the faces of `foldedPattern`, the cut pattern the walk
ran on ([`Folding.hs:318-322`](../src/Senbazuru/Origami/Folding.hs#L318-L322)),
with no entry for the root face ([D19](decisions.md#d19-realistic-rendering)).

**Earlier states.** Over the checkpoint interval's final cut pattern, a crease
made at step 5 has its node from the first key. Cutting only subdivides, and
vertex ids and material coordinates survive
([D6](decisions.md#d6-crease-graphs-grow-between-frames)'s *prefix rule*: each frame's
vertex list begins with the previous frame's,
[05 L5](05-prd-library-additions.md#l5-motionsacross-creasestocome-and-a-non-convex-point-test)),
so each final face lies in one face of any earlier state and moves with it; a
crease not yet made lies inside such a face and is keyed at 0. This is not the
*backfill* [D6](decisions.md#d6-crease-graphs-grow-between-frames) rejects, writing the final crease graph into every frame so that
creases are drawn before they are made, because at 0 the triangles draw no
crease. Unborn crease lines are omitted, or `STEP`-scaled in if the lines spike
passes. A `checkpoint` may remove creases and so breaks the prefix rule
([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused),
[02 §9](02-language-semantics.md#9-repeat-checkpoint-not-modelled-expect-refused)),
which is why the final pattern is per checkpoint interval.

**Presentation.** Records are unpresented, holding folded geometry with no
presentation turn. Each keeps presentation and anchor placement as separate
(before, after) pairs, `recordPresentation` and `recordPlacement`, which
`displayBefore` and `displayAfter` compose (presentation `after` placement) and
only writers and renderers apply ([D14](decisions.md#d14-material-consumption),
[01 §2.2](01-architecture.md#22-contract-1-moverecord)). Animation reads the two
pairs separately: presentation becomes the pivot nodes described here, and
placement the root of each segment below. Presentation move k gets a pivot node
(translation c_k, rotation keyed from identity to the move's turn) with an
unpivot child (translation −c_k); c_k is the point
[D5](decisions.md#d5-presentation-and-the-readers-side) turns about, the centre of
the displayed model's bounding box before the move
([02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper)). Later pivots
are outermost, so none is ever reset. A half turn's direction is a fixed
right-hand choice, display only.

**Segments.** A segment is part of a checkpoint interval with one anchor and no
`StateOnly` transition, with its own sub-hierarchy under the pivots, rooted at its
anchor face and carrying its anchor placement, from its records'
`recordPlacement`; meshes are shared. At a re-anchor (the runner handing the
anchor to another face when a move carries its face,
[D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)) or a
`StateOnly` transition, the old segment's scale goes 1 → 0 and the new one's 0 → 1
at one key time, both `STEP`. A rotation channel cannot jump instead: sampler times
must be "strictly increasing" (`schema/animation.sampler.schema.json:12`), and a node
path may be targeted once per animation (spec `Specification.adoc:2796`). Scale is
a separate target, and zero scale "provides a mechanism to animate visibility"
(`:938`). Both segments show the same positions at the switch, because every step
passed the *join check*, which requires positions to agree within
1e-12 × `modelSpan`
([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs),
[glossary-additions](glossary-additions.md#running-a-sequence)).

**Keys and checks.**

- `recordPoseAt r (PoseOnRoute p)` ([02 §10](02-language-semantics.md#10-assurance)),
  over `flapPoseAt` and `macroPoseAt` ([05](05-prd-library-additions.md)), at the
  n + 1 values of p that `keyDensity` n gives; `sample` adds none. An interval
  turning a tree crease by ≥ 180° gets its middle p, repeatedly.
- **Midpoint refold.** Fold at the per-crease average of the two keys' angles
  through `foldFrameWith`, whose `TornAt` and `loopsClose` checks
  ([`Folding.hs:154`](../src/Senbazuru/Origami/Folding.hs#L154),
  [`:377`](../src/Senbazuru/Origami/Folding.hs#L377)) decide. Those are the
  angles the viewer shows halfway, because slerp turns each tree crease by the
  linearly interpolated angle. Folding at the route's middle p instead would
  check a pose the viewer never shows, so passing it would say nothing about the
  picture. A failure is a subdivision: insert the route pose at the middle p and
  refold both halves (R-08-29).
- For `SweptHinge` the two coincide: a flap's angles are
  `angle + progress × travel`, linear in progress
  ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
  "Platform-sensitive bytes (for task d)", finding 16). Only `Sampled` macro
  routes, whose angles are formulas, can fail.
- Refolds are counted, not timed
  ([D16](decisions.md#d16-testing-and-acceptance): budgets are counted work,
  [09 §6.1](09-testing-and-acceptance.md#61-budgets-count-work)). Moves with no frames (`not modelled`,
  `expect refused`) add no keys. Seconds per route is a render option with no
  default fixed here.

**Scene.** Complete paper. Where layers touch at flat keys a generic viewer may
flicker, as the complete scene already may
([`Gltf.hs:17-20`](../src/Senbazuru/Render/Gltf.hs#L17-L20)); switching visible
pieces per key is a measured follow-up.

| Rejected | Why |
| --- | --- |
| One flat node per face (#56) | Hinges open between keys (G "C. glTF realism", finding 18a) |
| Skinning | Equals nodes for rigid panels; collapses rounded creases (G "C. glTF realism", finding 18b) |
| Morph targets | Straight-line vertex paths: a flap turning 180° about x = 0 is a line at weight ½ (G "C. glTF realism", finding 18c) |
| Scaling every angle by t | Leaves the loop-closure surface ([`fold-angles-are-the-state.md:17-31`](../docs/notes/fold-angles-are-the-state.md)) |
| `KHR_node_visibility` | Absent from three.js's and Blender's loaders (G "C. glTF realism", finding 18d) |

### #104, amended

[01 §4.7](01-architecture.md#47-corrections-to-six-issues) writes out #104's
premises and its amended text. In short, its done-when lets `simple.fold` and
`squaretwist.fold` under `--view iso` change, and both are goldens
(`simple-iso.svg`, `squaretwist-iso.svg`), so M7b advances #104 without closing
it.

The amended done-when names a view. #104's first bullet asks that "`render
examples/puffed-square.fold --view iso --hide-flat` draws the dome's outline".
From `--view iso` no face of `puffed-square.fold` turns away (the W1 measurement
above), so no silhouette pass can add a dome outline there, and that bullet
cannot be met ([§10](decisions.md#10-corrections) item 27; issue text read with
`gh issue view 104`). The done-when [D19](decisions.md#d19-realistic-rendering) decides,
recorded as [§3](decisions.md#3-recorded-text-this-design-changes) row 7: the
default render is byte-identical, and
`render examples/puffed-square.fold --view front --hide-flat --lines features`,
the view of #104's second bullet, draws the visible boundary and silhouette, as a
new golden (27 silhouette candidates before visibility).

### What stays research

Thickness offsets, fillets and crease radii at vertices; animated flexible routes;
how sheen or translucency looks on paper; W2 (milestone R,
[10](10-roadmap-risks-questions.md)).

## Acceptance criteria

"Manual" results go in the PR and a `docs/notes/` note.

| # | Criterion | Turns red when |
| --- | --- | --- |
| A-1 | On the committed branch, `git diff --name-only --diff-filter=MD origin/main...HEAD -- test/golden/` prints nothing, and the same with `--diff-filter=A` lists only goldens this feature adds ([D16](decisions.md#d16-testing-and-acceptance)); both print nothing at `568dcb6` | a default path writes `NORMAL`, `<desc>` or fidelity |
| A-2 | Each new mode's output decodes a four-axis fidelity record; default output has none | a new mode omits it, or it is written unconditionally |
| A-3 | `renderSvg testPage {pageDescription = Just "a & b"}` contains `<desc>a &amp; b</desc>` after `<title>`; `Nothing` emits none | escaping skipped; `<desc>` for `Nothing` |
| A-4 | One `F` crease at 0 between two bent regions: two normals along it, and W1 draws it | feature edges taken from `surfaceFeatures` |
| A-5 | Folded quarter fold and crane, smooth mode: every `NORMAL` is its face's unit normal from packed corners | a region spans a feature edge |
| A-6 | Quarter fold fixture state 2 (`file_frames[1]`): faces 0 and 1 beside edge 9 get (0, 0, 1) and (0, 0, −1); each underside accessor negates its top | faces joined across the crease; one shared `NORMAL` accessor |
| A-7 | A 2 × 1 sheet with material corners (1, 1) and (3, 2), so `S` = 2: corner north-west (1, 2) gets `TEXCOORD_0` (0, 0.5) and south-east (3, 1) gets (1, 1). A unit square stays as the readable case: north-west (0, 0), south-east (1, 1) | `1 −` dropped (south-east t = 0); `S` not applied (s = 2); `u₀` not subtracted (s = 1.5) |
| A-8 | `renderSurfaceGlbWith` on `Surface (Maybe V2)` writes no `TEXCOORD_0` and records why; `export examples/crane.fold --fold --smooth` writes `TEXCOORD_0` | folded x, y written as texture coordinates; `export` still building its surface with `surfaceFromFrame` |
| A-9 | `bent-strip-smooth.glb` golden: each interior material vertex has one normal | per-triangle normals |
| A-10 | Crane-spread curved and fine smooth GLBs: validator 0/0; a three.js screenshot shows no facets (manual) | a non-unit normal |
| A-11 | **W1, before any W1 test:** record whether `projectedForm` declines (`Right Nothing` or `Left ImpossibleStacking`) on the crane-spread curved and fine meshes. A-13 needs a mesh where it does, because only there does today's painter draw buried creases for W1 to remove. If neither declines, A-13's failing case is the 4,312-triangle crane-root mesh from #206 | — (a measurement) |
| A-12 | **Lines spike:** validator 0/0; three.js `GLTFLoader` screenshots (from `study/gltf`) of quarter fold and crane from both sides, lines visible without z-fighting (a line and a triangle at one depth flickering through each other) (manual); headless Blender `bpy` import counts loose edges equal to segments written; that loose edges do not render in Blender is **UNVERIFIED** and recorded | `lineLift` at or below one packing quantum |
| A-13 | **W1 (a):** the crane-spread solves hold every body vertex where it lies in the flat folded crane they start from ([`spreading-connected-wing.md:16`](../docs/notes/spreading-connected-wing.md); a *hold*, [glossary-additions](glossary-additions.md#material)), and so does #206's flat-preference control ([`CraneRoot.hs:68`](../study/fold-material/CraneRoot.hs#L68), [`CraneRootGallery.hs:51`](../study/fold-material/CraneRootGallery.hs#L51)), so the body's creases do not move. On crane-spread curved and fine and the 4,312-triangle crane-root mesh (slow job), from top-down and from bottom-up: the *wing's shadow* is the part of the page the wing covers in the flat start or in the settled state. Outside it, W1's drawn length of each body crease equals `visibleForm`'s on the flat folded crane, within τ | ties decided without orders; band shrunk |
| A-14 | **W1 (b):** tests dropping the order tie-break and shrinking τ to `1e-9` each fail on the mutated code, shown in the PR | a mutation passes, so the test cannot fail |
| A-15 | **W1 (c):** candidate × face pairs after the broad phase, 3–5 compiled runs at 392, 1,192 and 4,312 triangles; no size promised before | — (a measurement) |
| A-16 | W1 top-down on the folded crane draws the stretches `visibleForm` draws, compared by length within τ | faces containing a segment allowed to occlude it |
| A-17 | `puffed-square.fold --view front --hide-flat --lines features` golden: boundary and silhouette | silhouettes limited to `J` |
| A-18 | `--lines mesh` draws visible `J` at 0.35; `features` draws none | `J` styled through `strokeFor` |
| A-19 | **G1:** at every key of the blintz sequence, each final face's corners under the exporter's `Double` node transforms equal that state's displayed placement within `1e-12 × modelSpan`. The test reads `Double` keys, never the file's `float32`, which keeps about seven digits | keys taken from an earlier state's face ids |
| A-20 | **G1 re-anchor:** blintz with `anchor (7/8, 1/8)` then `fold behind corner south-east to centre`; evaluated with the spec's lerp (linear interpolation) and slerp at the interval midpoint, the central square moves less than `1e-9 × modelSpan` | one hierarchy rooted at the old anchor |
| A-21 | **G1 180° rule:** at `keyDensity` 1 (keys at p = 0 and 1), A-20's 180° corner turn gets one extra key at p = 1/2, counted by `--report` | the rule removed |
| A-22 | **G1 midpoint refold, added in M5's PR:** on a `Sampled` macro fixture and `keyDensity` that PR names, the midpoint refold tears with subdivision disabled and passes with it; the PR shows the tear. No `Sampled` route exists before M5, so which fixture and density is **UNVERIFIED** | check made at the route's middle p |
| A-23 | Animated blintz GLB, and the animated quarter fold of [09 §2.2](09-testing-and-acceptance.md#22-test-1-folding-equivalence-m2)'s three-state sequence: validator 0/0; Blender imports the animation; three.js plays it with no face changing shape (manual); static exports byte-identical; `docs/tour.md` and the `Render.Gltf` header state the nested-node interpolation and its 180° rule. Together these are #56's done-when, with nested nodes replacing its approach | a non-unit quaternion; a `STEP` rotation channel; the interpolation caveat missing from either document |

A-20's anchor, checked with exact fractions on `examples/blintz-base.fold`
(`python3` with `fractions.Fraction`; the file records no `faces_vertices`, so the
two faces were written from its eight vertices): (7/8, 1/8) lies strictly inside
the corner triangle (1/2, 0), (1, 0), (1, 1/2) of area 1/8 and on no edge, and
the central square across edge 8 (`M`, −180) has area 1/2. So the move carries
the anchor, and [D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)'s rule (the
stationary face beside the hinge with the largest material area becomes the
anchor's face) re-anchors on the central square. The runner's behaviour is
**UNVERIFIED**; it is not built.

## Dependencies

| Needs | For | Owner |
| --- | --- | --- |
| `recordPoseAt`, `PoseRef` ([D10](decisions.md#d10-assurance-as-evidence-values)) | G1 keys | [02 §10](02-language-semantics.md#10-assurance) |
| `flapPoseAt`, `macroPoseAt`, `RoutePose` | G1 keys | [05 L4](05-prd-library-additions.md#l4-flapstationaryface-flapposeat-and-routepose), [05 L13](05-prd-library-additions.md#l13-origamimacro-checkedmacro-and-macroposeat) |
| `Origami.Folding.foldedWalk`, each face's parent and crossing edge from the library's own walk ([D19](decisions.md#d19-realistic-rendering), [§5](decisions.md#5-type-sketch)) | G1 hierarchy | 05 L15, at M7b ([05](05-prd-library-additions.md)) |
| `MoveRecord` with `recordPresentation` and `recordPlacement` ([D14](decisions.md#d14-material-consumption)); re-anchoring ([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)); the axis point of [D5](decisions.md#d5-presentation-and-the-readers-side) | G1 | [01 §2.2](01-architecture.md#22-contract-1-moverecord), [02 §2.3](02-language-semantics.md#23-the-anchor), [02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper) |
| Material-identity matching across states ([D6](decisions.md#d6-crease-graphs-grow-between-frames)) | G1 earlier states | [05 L5](05-prd-library-additions.md#l5-motionsacross-creasestocome-and-a-non-convex-point-test) |
| M2 (`SweptHinge`); M5 (`Sampled`) | G1 | [§8](decisions.md#8-milestones), [10](10-roadmap-risks-questions.md) |
| Accepted crane-spread and wing-bending meshes (exist) | M7a | study |
| M6 settled illustrations | `bent zero-thickness` fidelity on settled files | [07](07-prd-material-consumption.md) |
| #206's mesh, from the long crane-root gallery | A-11, A-13 | [#206](https://github.com/avalonalex/senbazuru/issues/206) |

M7b closes #56 (nested nodes replace its approach; A-23 covers its done-when), advances #104 and #48, and
leaves #49 and [#114](https://github.com/avalonalex/senbazuru/issues/114) open.

## Risks

| Risk | Mitigation |
| --- | --- |
| The lines spike fails in a viewer | R-08-13's extras fallback |
| W1 cost at 4,312 triangles is unknown | A-15 measures before any promise |
| Crane-spread meshes never reach the painter | A-13's failing case moves to crane-root, in the slow job (owner decision 12) |
| Animated files flicker where layers touch | Recorded; visible-piece switching measured later |
| Animated and textured bytes carry platform trigonometry | No byte golden; tests read `Double` values and validator counts |
| A per-edge silhouette test leaves outline gaps on coarse meshes | Measured on `puffed-square.fold` and a settled wing ([G](research/G-realistic-rendering-and-simulation.md) "D. SVG wireframe of a 3D paper surface", finding 19) |

## Open questions for the owner

Numbered as in [§9](decisions.md#9-owner-decisions), which gives each a
recommended default, and [10 §6](10-roadmap-risks-questions.md#6-owner-decisions):

- **5.** "SVG wireframe": feature lines only, or triangulation too? Default
  `--lines features`; `--lines mesh` adds visible triangle edges.
- **6.** Textures: procedural and ours, or vendored; and which encoder. Default
  none: M7a ships normals and texture coordinates only.
- **10.** Eighth-turn presentation: animated eighth turns carry trigonometry in
  their keys, as written frames do. Default trigonometry, with platform bits
  stated.
- **12.** Default CI or slow job for W1's 4,312-triangle acceptance. Default a
  separate slow job that is a required check.

## Research links

- [G — realistic rendering and simulation](research/G-realistic-rendering-and-simulation.md):
  "C. glTF realism" (findings 14-18), "D. SVG wireframe of a 3D paper surface"
  (19-22), "E. Proposed fidelity ladder, with repository coverage" (23).
- [C — renderers, CLI and formats](research/C-renderers-cli-formats.md): "(a) What
  each backend consumes, and the layering rule", "(b) glTF today", "(e) Dependencies".
- [B — material study mechanics](research/B-material-study-mechanics.md): "Risks
  (question d)", finding 15.
- [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md):
  "Platform-sensitive bytes (for task d)".

The recorded text for #104, #56 and #114 is written out in
[01 §4.7](01-architecture.md#47-corrections-to-six-issues) and scheduled in
[10 §3](10-roadmap-risks-questions.md#3-recorded-text-changes-by-milestone); GLB
extras' unrounded fold angles are
[10 §7.2](10-roadmap-risks-questions.md#72-new-issues-to-file) item 22. That
#104's `--view iso` bullet cannot be met on `puffed-square.fold` is
[§10](decisions.md#10-corrections) item 27.
