# A pillow-shaped visual target for the whole crane

The owner found [the first whole-crane drawing](whole-crane-candidate.md)
broken and identified both the viewing angle and unfinished body opening.
[#399](https://github.com/avalonalex/senbazuru/issues/399) compares a further
**shape sketches**, retaining the first candidate. They do not produce valid
paper geometry: the new silhouette comes with much worse local distortion.

![Previous and narrower bodies with the same wing angle](../img/crane-pillow-preview.svg)

[Tinygami's photographs](https://tinygami.wordpress.com/2016/02/10/how-to-open-an-origami-crane/)
show the wings moving down and outward while the body fills out like a pillow;
the underside opens too.
[Hans Bodlaender's top and side views](https://webspace.science.uu.nl/~bodla101/d.origami/traditional/crane/crane3.html)
distinguish a broad body top from leaving its point standing up. The
[International Crane Foundation's instructions](https://savingcranes.org/origami-cranes/)
also connect outward wing movement to opening the body. These inform a visual
target, not measured dimensions or evidence for our mathematical construction.
The photographs are not vendored.

There is also a presentation error in the first gallery. The fixture's wings
stand up along **negative Y**, whereas its earlier cameras treated Z as up.
X runs between head and tail; Z separates the two wings. The new three-quarter
and side views use negative Y up. The above/underside cameras have an 8.53°
tilt so the closed, flat crane is not exactly edge-on. Old camera choices remain
available. Both figures share one camera, scale and box, taken over all five
shapes, so changing the comparison cannot silently enlarge one crane.
The 3D viewer's explicit `up=z` option accounts for the export's axis conversion
with a rigid display rotation; exported coordinates are unchanged.

The pillow recipe releases the first candidate's 49 fixed central vertices.
It spreads their original material coordinates into a shallow cushion with
half-width `(sqrt 2 - 1) / 2`, rim at `y=0.44` and centre at `y=0.395`.
A product of two quadratic profiles rounds the top. The wider target’s outer
wing strips follow circular arches, turning from −15° to +15°, with their roots
aligned to that rim. After the owner found the opening too wide, a second
target narrows the body across the wings by 25% and raises each arch by 35°.
The same arch length and 30° turn remain; its tangent now runs from −50° to
−20° relative to horizontal, with negative angles pointing up. The body’s
head-to-tail extent and 27 px rise stay unchanged. This reduces horizontal
reach by turning the wing, without shrinking the entire mesh or drawing.
The latest body-only revision changes its width factor from 0.75 to 0.5,
another one-third reduction, while retaining those raised wing arches. The
wings move inward with their roots; their angle, curve and outer-strip
shape stay fixed. The body’s height and head-to-tail extent remain unchanged.
These controls are authored, not recovered from a pressure model.
Remaining vertex displacements come from a linear graph calculation: neighbouring
material vertices prefer similar displacement, weighted by the inverse square
of their original separation. This avoids assigning most movement to a tiny
edge, but **does not preserve its length**. Neck/head and tail follow through
those shared vertices. No weld joins touching layers; no additional material
relaxation or folding motion is run.

| Measurement, 600 drawing pixels per sheet side | Wider pillow | Raised wings | Narrower body |
| --- | ---: | ---: | ---: |
| Body width across wings (Z range) | 248.53 px | 186.40 px | 124.26 px |
| Wing-tip separation | 841.70 px | 672.29 px | 610.16 px |
| Largest edge error | 110.06 px / 104.48% | 64.22 px / 60.96% | 57.42 px / 58.04% |
| Largest local stretch / compression | +261.46% / −96.17% | +164.60% / −81.93% | +152.17% / −82.10% |
| Strict crossing pairs | 257 | 314 | 266 |

The body-only revision moves the two held outer wing strips inward by
31.07 px each, with no rotation or change of their shape. Its area is 3.46%
smaller than the sheet; neck/head and tail tips move 60.74 and 58.66 px from
the closed crane. The remaining distortion and crossings still make this
an unaccepted visual target.

The earlier raised-wing revision reduces wing-tip separation by **20.13%**. Its lower distortion
still does not make valid paper, and its crossing count rises. Its area is
3.04% larger than the sheet; neck/head and tail tips move 61.03 and 58.67 px
from the closed crane. These are diagnostic results, not acceptance criteria.

The wider pillow's authored rise is 27 drawing pixels. Its area is 10.31% larger than
the sheet, and the neck/head and tail tips move 58.61 and 55.27 pixels from the
closed crane. All 237 shared vertices, 448 triangles, material coordinates and
source identities remain, but connected topology is not enough to make this
paper. Fewer crossing pairs also do not compensate for stretching or crushed
triangles. The gallery puts the invalid-geometry warning before the images.
Plain and two-sided views use identical geometry.

Independent NumPy calculations reproduce lengths, local strains, area,
landmarks and crease angles. GEOS checks silhouette coverage; independent
point/triangle calculations check the nearest surface at visible-piece centres.
The raised-wing revision keeps all pairwise distances between the held samples in each
outer wing strip (maximum difference below 3e-16 sheet units); its shorter
horizontal span comes from raising those strips. The body-only revision is
a pure translation of those held samples (residual below 2e-16 sheet units).
Fresh generation reproduces 90 archives/exports byte for byte, and all
70 single SVG extents match the
shared camera bounds.
The GLB coordinates agree with FOLD within 0.00068 pixels, bounded by the
existing span-dependent export rounding. The first candidate and wider target
retain their positions. Original holds and the raw failed correction remain
unchanged. The tests exercise
connected material, finite positions and distinct wings without a material solve.

Regenerate the comparison with `--whole-crane-view build/fold-material`, or
create a fresh archive using the committed body fixture and `--whole-crane-start`
command in the [study README](../../study/fold-material/README.md). The gallery
now defaults to previous versus narrower body.
`whole-crane/body-width-comparison.svg` and `body-width-top-comparison.svg`
export that pair; `narrow-comparison.svg` compares the closed crane with the
latest target. The earlier pillow and compact files remain.
FOLD/GLB exports retain the full sheet.

Review the silhouette and body-to-wing proportions first. If this target is
useful, the next task is accommodating it with the attached folded paper;
this experiment has not shown that these exact dimensions are achievable.
Do not resume microscopic pair repairs or mistake this drawing for a successful
inflation. Pressure, physical calibration and a checked route remain open.
