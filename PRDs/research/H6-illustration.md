# H6. Instruction-book illustration from 3D: line drawing, line style and tone

Research slice H6, written 2026-09-28 against `main` at `83fc960` (clean tree
apart from an untracked `.claude/`). It builds on
[G](G-realistic-rendering-and-simulation.md) (cited as "G finding n") and on
[PRD 08](../08-prd-realistic-rendering.md) W1. Links are written for this
note's intended home, `PRDs/research/`. Nothing
in the repository was changed. Every measurement below was run on output this
slice regenerated into its scratch directory with the already-built study
binary, and every script is kept beside this note in `scripts/H6-illustration/`.
Third-party files downloaded only to measure them (papers, the Wikimedia
crane SVGs) are in `scripts/H6-illustration/third-party-do-not-vendor/` and must not
be copied into the repository.

> **Verification, 2026-09-28.** [V](V-verification.md) re-checked this note.
> Finding 2: 74–78% of *emitted* contour ink is one copy of an exactly
> coincident pair; that is 58–64% of the distinct contour length drawn twice,
> and de-duplication removes 37–39% of contour ink. [H1](H1-diagnosis.md)'s
> 22–28% measures near-parallel ink, a second defect that de-duplication does
> not remove. Finding 4 is confirmed and strongly enriched against a 1.8% base
> rate. `dedup_chain.py` and `book_v2_prototype.py` use different tolerances,
> so their stroke counts differ. The third-party SVGs it measured are not kept.

The regenerated gallery reproduces the committed note's numbers exactly (421,
394, 312 and 514 visible pieces; 25, 30, 18 and 46 omitted crease fragments,
longest 1.52, 1.95, 1.57 and 1.85 px), so the measurements describe the drawing
the owner has seen.

```bash
# from the repository root; writes only to the scratch directory
S=<scratch>/research/H6-illustration
.stack-work/install/aarch64-osx/<hash>/9.6.7/bin/senbazuru-material-study \
  --whole-crane-start study/fold-material/fixtures/whole-crane-body.fold $S/build
```

## Summary

The owner's feeling that the crane drawings are "not refined" has two causes,
and they need different remedies.

**The ink is unrefined, and that part is cheap to fix.** The study's book
drawing emits 74–78% of its contour ink twice, once for each side of the
boundary. An anti-aliased double stroke puts about 29% more ink on the page than
a single one, so interior lines come out heavier than the outline, which is the
reverse of a book's line hierarchy. Its 447 contour segments reduce to 81
strokes once duplicates are removed and the segments are joined end to end.
Nineteen of those 81 strokes are shorter than 5 px. Every contour has one weight,
and crease lines run all the way into edges. A 200-line Python prototype restyles the
same SVG without moving any paper, cutting 617 paths to 162:

- each boundary drawn once;
- outline, interior contour and crease drawn at three weights;
- dangling stubs removed;
- a small gap, or *halo*, left where a line stops against another.

Human diagrammers do the same:

- two line weights, about 2:1 or 3:1 (Lang, Petty);
- a crease stops short of an edge;
- unimportant creases are omitted consistently;
- one tone per side of the paper, with a linear gradient where paper curves.

A published vector crane on Wikimedia Commons has 17 paths and no curves at
all.

**The geometry limits the rest, and no ink can fix it.**

- In the More tucked pose, 5 of the 76 panels contain two triangles whose
  normals are more than 90° apart, although no crease runs between them.
- 23 panels exceed 30°.
- In the upright view, seven contour lines end in the middle of the paper. Six
  of those ends lie within 0.01 px of a place where two layers pass through each
  other.

Smoothing these away would hide defects that the owner's direction of
2026-09-26 says a reviewed illustration must not hide.

Recommended order:

1. Restyle the ink in the study (S–M).
2. Add per-panel gradient and stepped tones through a new `Paint` in `Diagram` (M).
3. Produce denser geometry rather than 2D curve fitting (M).
4. Build a production book renderer on PRD 08 W1's exact visibility (L). It
   should classify lines by what the reader sees, not by FOLD assignment.

Blender Line Art is useful as a reference renderer. It is not a dependency.

## Findings

### A. What the current book drawing is made of

1. **The pipeline.** [code]
   - **Visibility.** `WholeCraneDrawing.depthDrawing` projects every triangle
     and subtracts from it the convex parts of other triangles that are nearer
     the camera. Depth is a plane per triangle, so overlaps can be clipped
     exactly where two planes cross (`WholeCraneDrawing.hs:37-71`). This is
     what the literature calls a **planar map**: the page cut into regions,
     each labelled with the one piece of paper visible there (Bénard &
     Hertzmann §4.8). It is internally consistent by construction, because the
     regions tile the visible image.
   - **Contours.** `CraneBookDrawing.contourSegments` calls a region's edge a
     *contour* unless an oppositely directed edge at the same depth covers it
     (`CraneBookDrawing.hs:101-116`).
   - **Tones.** Each source panel gets one of three tones from its
     area-weighted normal (`:52-86`, thresholds at `:84`).
   - **Creases** come from the visible feature edges.
   - **Output.** Contours are drawn at 1.15 and creases at 0.65, with no
     chaining (`:126-130`).
   - **Cost.** Neither step has a broad phase. `occluders a = map (hide a)
     shadows` clips every pair of triangles (`WholeCraneDrawing.hs:57`), and
     `covers` scans every edge against every edge (`CraneBookDrawing.hs:111`).

2. **Three quarters of the contour ink is drawn twice.** [ran
   `scripts/H6-illustration/duplicates.py build/whole-crane/book-checks.json`]
   - **The cause.** A boundary between two regions at different depths appears
     once as the near region's edge and once as the far region's. Neither
     cancels, because the cancelling rule requires equal depth.
   - **How much.** An opposite-direction contour overlaps 6064 of 7775 px of
     contour ink in the upright view (78%). The opposite, low and top views
     give 78%, 74% and 74%. No same-direction overlap occurs.
   - **What is single.** The unduplicated remainder, about 1.7k px, should be
     the outline against empty page, since a single copy has paper on only one
     side. [reasoned; not checked piece by piece]
   - **Why it matters.** A doubled stroke is darker. Rasterised by `rsvg-convert`,
     one 1.15-wide line covers 0.80% of a 100×100 tile and two coincident lines
     cover 1.03%, 29% more ink (`scripts/H6-illustration/double.svg`, measured with
     ImageMagick). So the interior lines of the current drawing print heavier
     than its outline, which inverts the line hierarchy.
   - **Production already avoids this.** `Origami.Visible` gathers collinear
     edges into one `Track`, asks once per stretch whether the paper differs
     across it, and joins neighbouring stretches with `joinRuns`. Its comment
     calls that the difference between an outline drawn as one stroke and as
     nine (`Visible.hs:336-372`, `:390-400`). The 3D study code has no
     equivalent.

3. **The strokes are fragments.** [ran `dedup_chain.py`, `book_v2_prototype.py`]
   Once duplicates are removed, contour pieces can be *chained*: joined end to
   end through every point where exactly two meet, giving longer strokes.

   | View | Contour segments drawn | Unique pieces → strokes | Strokes < 5 px | Median stroke |
   | --- | ---: | ---: | ---: | ---: |
   | upright | 447 | 256 → 81 | 19 | 20.0 px |
   | opposite | 471 | 285 → 93 | 23 | 19.9 px |
   | low | 340 | 211 → 68 | 19 | 18.4 px |
   | top | 411 | 229 → 67 | 10 | 33.2 px |

   All lengths are at the gallery's 600 px per sheet unit. The SVG emits one
   `<path>` per segment: 447 contour paths and 167 crease paths out of 617 in
   the upright view (counted with `grep`).

   `scripts/H6-illustration/H6-upright-comparison.png` shows the current upright
   drawing beside the prototype restyle of the same SVG (Implications I1–I3),
   both at 1.6×.

4. **Seven lines stop in mid-paper in the upright view.** [ran
   `book_v2_prototype.py`, appended free-end count]
   - **What counts.** After the stubs under 5 px are removed, a contour end that
     touches neither another contour nor a crease is a *loose end*. The four
     views have 7, 6, 2 and 12. The longest belong to strokes of 112, 102, 80
     and 70 px.
   - **Why it is a defect.** On opaque paper that does not pass through itself,
     a contour ends only where it meets another line or at a **cusp**, the
     point where the surface turns out of sight behind itself (Bénard &
     Hertzmann §4.3).
   - **The cause is layers passing through each other.** [ran
     `loose_vs_crossings.py loose-upright.json`]
     - The gallery's `checks.json` lists 345 crossing triangle pairs for More
       tucked. The narrower-body pose in the pillow-target note has 266.
     - Projecting each pair's 3D intersection segment into the upright page puts
       six of the seven loose ends within 0.01 px of one, and the seventh within
       0.62 px.
     - The cancelling rule does not draw an intersection line, so a flap edge
       that passes into another layer simply stops.

5. **Where the contour ink comes from.** [ran `contour_sources.py`]
   - **Along which edges.** Nearly every drawn contour lies along a projected
     mesh edge; only one segment per view does not. In the upright view, 70% of
     the contour length lies on crease edges, 18% on the sheet's boundary, and
     12% on *triangle joins* (`J`, the edges that only subdivide a panel). The
     other views give 8–10% on joins.
   - **Why joins matter.** Ink along a join is a turning contour inside a bent
     panel drawn along the mesh's facets. That is the faceted look.
   - **The same, before visibility.** In the upright view, 22 join edges
     separate a triangle facing the camera from one facing away. Together they
     are 1093 px long.
   - **The smooth alternative.** Replace each triangle's normal by one averaged
     at the corners within its panel, as `PaperLighting` does. Then find where
     that averaged normal turns edge-on inside each triangle. That *interpolated
     contour* (finding 9) is 23 segments and 212 px long, about a fifth of the
     length.
   - **What the gap means.** Much of the join-edge ink is zigzag and clusters
     from crumpled triangles rather than the outline of a smooth bend.

6. **The geometry is crumpled inside panels.** [ran `panel_bend.py` over every
   saved `*.fold`] A *panel* is the paper between creases. Measure the largest
   angle between two triangle normals inside the same panel:

   | Pose | Panels > 5° | > 30° | > 90° | Max |
   | --- | ---: | ---: | ---: | ---: |
   | closed (`before`) | 0 | 0 | 0 | 0° |
   | first candidate (`after`) | 25 | 4 | 0 | 62° |
   | **More tucked** (`spread-0`) | 59 | 23 | 5 | 176° |

   - **The other sketches** (`compact`, `narrow`, `pillow` and the other spread
     settings) all have 4–6 panels over 90°.
   - **A panel over 90°** folds back on itself where the pattern has no crease.
   - **Lighting inside a four-triangle panel** spans more than the whole 0–1
     brightness scale in some views ([ran `panel_gradients.py`]: panel 58, span
     1.04, upright).
   - **What that means for this slice.** No line style, tone or smoothing makes
     that panel look like paper. This bounds what H6 can deliver.

7. **The current tones hide the side of the paper on purpose.** [code and note]
   - `CraneBookDrawing` uses one palette for both sides of the paper
     (`crane-book-drawing.md`).
   - The whole-crane note says two-sided colouring exposes "large reverse-side
     patches" (`whole-crane-candidate.md`).
   - Books do the opposite (findings 20 and 21). Colour-side versus white-side
     is the first thing a diagram's tone says. The study's choice is a
     reasonable workaround for defective geometry, not a style to keep.

8. **Line weight follows assignment in production. A 3D drawing needs the role
   a line plays instead.** [code]
   - **Production.** `Style.strokeFor` draws `B`/`C` at 1.6 and `M`/`V` at 1.0
     solid on a folded form. The comment calls a fold "an edge in a folded form"
     (`Style.hs:262-289`). That is right for a flat-folded model, where every
     visible `M`/`V` stretch is a folded edge.
   - **A bent 3D form breaks this.** A partly open crease between two visible
     panels is a crease *mark*: same sheet on both sides, no depth jump. The
     same crease seen edge-on is an *outline*.
   - **The book convention.** Diagrams draw the model's visible edges heavy and
     crease marks light (finding 17).
   - **Disagreement with PRD 08.** W1's line table styles a silhouette "crease
     1.0, even with `--hide-flat`" (PRD 08 §W1 table). Its outline would then
     print lighter than a raw edge beside it.
   - **The study already has the right idea.** `CraneBookDrawing` decides
     contour versus crease by depth jump, not by assignment.

### B. Line drawing from 3D models: what the literature says

Terms, following Bénard & Hertzmann:

- The **contour generator** is the curve on the surface where it turns from
  facing the viewer to facing away.
- The **occluding contour** is its visible projection.
- The **silhouette** is only the part of that contour against the background.
- **Boundaries** are the paper's own edges.

9. **Mesh contours of a smooth shape are messy. Interpolated contours help but
   do not line up with the mesh.** [paper: Bénard & Hertzmann 2019, §6.1–6.2]
   - **The problem.** Convert a smooth surface to triangles and take the edges
     where front meets back, and the contours branch, zigzag and break into
     many short chains.
   - **No clean-up fixes it.** The authors are blunt that heuristic clean-ups
     never reach correct topology: "Efforts to turn these clever solutions
     into perfect results have always failed."
   - **Interpolated contours** (Hertzmann & Zorin 2000) give each vertex an
     area-weighted normal *n*. For a view direction *v*, set *g* = *n*·*v* and
     interpolate it linearly across each triangle. Draw the segment where
     *g* = 0, whose ends are at *t* = *g*ᵢ / (*g*ᵢ − *g*ⱼ) along two edges. The
     result is smooth and cannot branch.
   - **The mismatch.** The interpolated curve is not the polygon mesh's
     contour. Visibility against the mesh becomes a heuristic, voting over
     several ray tests.
   - **The halo region.** The polygons still stick out past the curve, and the
     band between the two can wrongly hide what lies behind it. Bénard &
     Hertzmann call it the *halo region* (§6.2.4, Fig. 6.6).
   - **Why it matters here.** senbazuru fills its polygons, so the fill would
     also poke out past a line drawn along the interpolated contour.

10. **Exact smooth contours are research-grade and not needed here.**
    [fetched ConTesse arXiv 2111.06006; Algebraic Smooth Occluding Contours
    arXiv 2306.01973; Hertzmann's 2023 blog post; `gh api` licence]
    - **ConTesse** (Liu, Bénard, Hertzmann, Hoshyari, ACM TOG 2022/23) states
      when a sampled contour has consistent visibility. It then builds a new
      triangle mesh whose own contour *is* the sampled curve, so the drawing and
      the mesh agree.
    - **Its cost.** Hertzmann's blog calls it expensive, a proof of concept.
    - **The newer method.** Capouellez, Dai, Hertzmann & Zorin (2023) fit a
      smooth piecewise-quadratic surface whose contours have closed form, which
      is much faster.
    - **Licence.** The ConTesse code is Apache-2.0 (`squidrice21/ConTesse`).
    - **The lesson for senbazuru:** lines and fills must come from **the same
      surface**. Either draw the fine mesh you fill, or change the mesh so its
      own contours are the smooth ones. Drawing smooth lines over coarse fills
      is the one combination that cannot agree.

11. **Contours on paper differ from the textbook case.** [paper §3.3; fetched
    Blender manual `line_set.rst`]
    - **The textbook assumption.** A closed surface or a restricted camera means
      back faces are never visible.
    - **Paper breaks it.** Paper is an open, two-sided sheet, and both sides
      show.
    - **Freestyle's silhouette type.** Blender's manual says its *Silhouette*
      edge type "cannot render open mesh objects like open cylinders and flat
      planes". For paper the usable Freestyle types are *Contour*, *Border* and
      *Edge Mark*.
    - **senbazuru already handles both sides.** `Region.regionTopSide` records
      which side of the paper shows, and the planar map (finding 1) treats a
      back-facing triangle as visible paper wherever nothing covers it.
    - **So** the textbook back-face shortcuts must not be copied.

12. **Image space and object space.** [paper §2, §2.1]
    - **Image space.** Saito & Takahashi (1990) find contours by edge-detecting
      a depth buffer. Adding normal and object-id buffers finds creases and
      separates nearby objects.
    - **Its limits.** It is simple and naturally drops tiny detail. It gives no
      curves to style, can miss or invent edges, and changes with resolution.
    - **Vectorising the result** adds inaccuracy.
    - **Agreement.** This matches PRD 08's rejection of a raster depth buffer for
      W1, and nothing found here changes it. senbazuru needs byte-stable
      vectors.

13. **On unstretched paper, contours inside a bent panel are straight, and so
    are the lines of equal shade.** [fetched Wikipedia *Developable surface*;
    reasoned]
    - **Developable surfaces.** Paper bent without stretching is
      *developable*: it can be flattened with no distortion. Such a surface is
      made of straight lines called *rulings*, and its tangent plane does not
      twist along a ruling. So the normal is constant along each ruling.
    - **Contours.** Whether *n*·*v* = 0 is the same all along a ruling, so the
      contour generator inside a bent panel is a union of whole rulings. That is
      a straight segment in 3D and on the page, orthographic or perspective:
      along a ruling *r*, *n*·*r* = 0, so *n*·(*p* − *c*) does not change.
    - **Shading.** Diffuse brightness *n*·*l* is also constant along rulings.
    - **Cylinders.** For a cylindrical bend (parallel rulings), one SVG
      `linearGradient` whose axis crosses the projected rulings reproduces the
      shading exactly, given enough stops.
    - **Cones.** For a conical bend (rulings through an apex), the shade is
      constant along rays from the apex. SVG has no angular gradient, so a
      linear gradient is an approximation.
    - **What this means for drawing.**
      - Curved lines in a correct paper drawing come mostly from curved
        *boundaries and creases*, which are space curves.
      - Contour lines inside panels are straight.
      - A wiggly contour inside a panel is a sign of stretched or crumpled
        geometry, as in finding 6.

14. **Styling lines: chaining, simplifying, halos and weight.** [paper §9.1–9.3;
    fetched Appel et al. 1979 via search abstract; Goodwin et al. 2007 PDF; Cole
    et al. 2008 project page]
    - **Chaining.** Segments are joined greedily into chains. At a
      **T-junction**, where a nearer line crosses in front of a farther one, the
      nearer line continues and the farther one stops. At a **Y-junction**, where
      a contour meets a boundary, the contour continues. Smoothing each chain on
      its own can break a T-junction, so the junction must be held fixed.
    - **Simplification** (Bénard et al. 2014, summarised in §9.3):
      - A *candidate* is a run of visible curve with no junction in it, shorter
        than a threshold. The authors used 10–20 px.
      - Remove a candidate that connects a junction to a dead end, a dead end to
        a dead end, or a vertex to itself.
      - Also remove a candidate that another chain overlaps on the page.
      - Repeat until nothing changes.
    - **Relevance** for omission: one proposed measure is the largest depth jump
      along a line (§9.3).
    - **Halos** (Appel, Rohlf & Stein, SIGGRAPH 1979): a line passing behind
      another gets a small gap next to it, as if the nearer line had an opaque
      halo. This is the technical-illustration form of the origami rule that a
      crease stops short of an edge (finding 17).
    - **Weight.** Goodwin, Vollick & Hertzmann (NPAR 2007) note that constant
      width looks mechanical and tapered ends look pleasing. They derive
      thickness from shading, but their method is written for smooth surfaces
      without creases or boundaries, so it does not transfer to paper as-is.
      Gooch et al. (1999, as cited there) make thickness fall with depth.
    - **What artists draw.** Cole et al. (SIGGRAPH 2008) found that artists'
      lines agree with each other (75% within 1 mm of another artist's line),
      mostly along occluding contours. That supports spending ink on contours
      first.

15. **Fitting curves in 2D is the wrong tool here.** [ran
    `book_v2_prototype.py --curves`; fetched Yuksel et al. 2011; ran
    `svg_segments.py`]
    - **Uniform Catmull–Rom.** A smooth curve forced through every drawn vertex
      of the chained strokes left the polyline by up to 4.6, 5.6, 8.1 and 5.3 px
      in the four views. It overshoots where long and short segments meet.
    - **Centripetal Catmull–Rom**, which Yuksel, Schaefer & Keyser prove never
      forms cusps or self-intersections within a segment, stayed within 0.5 px.
      The chord was kept wherever that bound would be broken. Of 337 segments,
      310 became curves (upright).
    - **The mismatch.** The fills stay polygons, so line and fill now disagree
      by up to 0.49 px, finding 10's mismatch in miniature.
    - **The visual gain is small**, because the wing outline has few vertices to
      curve between.
    - **"Refined" does not mean curved.** Binnette's vector crane on Wikimedia
      has 17 paths, 67 straight segments and **no curves**. Densify the geometry
      instead (Implication I6).

16. **Blender Freestyle and Line Art.** [fetched Blender manual sources from
    `projects.blender.org` (`line_set.rst`, `line_art.rst`,
    `grease_pencil_svg.rst`); fetched `extensions.blender.org`; ran a headless
    spike]

    **What they offer.**
    - **Freestyle.**
      - Edge types: Silhouette, Crease (dihedral threshold), Border, Edge Mark,
        Contour, External Contour, Material Boundary, Suggestive Contour and
        Ridge & Valley.
      - Visibility: visible, hidden, or a *quantitative invisibility* range,
        which counts how many surfaces cover a line.
      - SVG goes out through the *Freestyle SVG Exporter*. It became an
        extension in Blender 4.2, is GPL-2.0-or-later, and has "limited
        support".
    - **Line Art** (a Grease Pencil modifier).
      - Edge types: Contour, Crease, Intersections, Material Borders, Edge Marks
        and Loose, plus occlusion levels.
      - Chaining options: *Image Threshold* joins nearby ends, *Smooth
        Tolerance*, *Angle Splitting*, *Preserve Details*, *Geometry Space*.
      - *Overlapping Edges as Contour* handles coincident edges.
      - SVG goes out through *File → Export → Grease Pencil as SVG*, which
        exports from the largest 3D viewport.

    **The spike.** Blender 4.4.1, `-b --factory-startup`, upright orthographic
    camera; scripts `scripts/H6-illustration/lineart/run.py` and `run_fold.py`.
    - **From the study's GLB, defaults:** 179 strokes, 41 under 5 px. Much of the
      right wing is missing. The GLB carries each triangle twice, once per side
      (2688 vertices, 896 triangles for 448 triangles of paper). Twin
      coincident faces confuse occlusion.
    - **From `spread-0.fold`**, with every `M`/`V`/`F`/`U`/`B` edge marked
      (276 of 684 edges) and no dihedral crease threshold: 56 strokes, 5 under
      5 px, median **70 px**, one weight (`lineart/fold-plain.svg`). This
      confirms G finding 20 in practice. Lines by provenance, not by dihedral
      angle, give a clean drawing.
    - **With Intersections on:** 82 strokes, and the wing shows wandering lines
      where its layers pass through each other (`lineart/fold-intersections.svg`).
      That is a useful diagnostic image of findings 4 and 6. The two
      renderings are side by side in `lineart/fold-lineart-pair.png`.
    - **Licence.** Running Blender is not vendoring (D17).
    - **Not tested:** whether Line Art's output is byte-stable across runs and
      versions. **UNVERIFIED.**

### C. How human diagrammers draw

17. **Robert Lang, *Origami Diagramming Conventions*.** [fetched
    langorigami.com]
    - Professional diagrams use two line weights, about 1 pt for edges and 0.5 pt
      for creases.
    - With a single weight, a crease line stops short of the edge it ends on,
      except where it runs under another layer.
    - Unimportant creases may be left out for clarity, but consistently through
      the sequence.
    - Diagrams deliberately distort the model for clarity: gaps and separated
      layers.
    - Heavy-circled cut-away views replace x-ray lines for complex hidden moves.
    - The article says nothing on shading the coloured side or on drawing
      inflated models.

18. **David Petty, British Origami Society, *Origami diagramming*.** [fetched
    britishorigami.org]
    - Pens: 0.1 mm for creases, 0.3 mm for folds and outlines, 0.5 mm for
      enlarged views, a 3:1 ratio.
    - Dot shading, in his experience, gives the strongest sense of depth.
    - 3D steps are hard even for experienced diagrammers. Petty's fall-back is
      to photograph the model and trace it.
    - Colour side, white side and raw versus folded edges must all read in the
      drawing.
    - His summary: "Diagrams are controlled distortions of reality."

19. **The Yoshizawa–Randlett symbols.** [fetched Wikipedia, CC BY-SA 4.0; fetched
    origami-resource-center.com]
    - Line types: thick edges, dashed valley folds, dash-dot mountain folds,
      thin existing creases, dotted hidden lines.
    - Yoshizawa introduced "inflate" and "round" symbols. The Wikipedia text does
      not describe how they are drawn.
    - The Origami Resource Center describes a rotund (round-bodied) arrow for
      push in, pull out or inflate.
    - PRD 06's step symbols would carry that arrow. The finished figure after
      it is what this slice draws.

20. **Andrew Hudson's Public Diagram Project crane** (`Tsuru_wiki.svg`,
    Wikimedia Commons, CC BY 3.0). [fetched; measured with `rsvg-convert`,
    ImageMagick and a regex count]
    - **Weights.** Edges are black at width 1. Creases are 0.625 and 0.5, a
      ratio of 1.6–2. Which width goes with which line type was read off the
      rendered image.
    - **Tones.** The coloured side is flat grey (`#b3b3b3`, 57 fills) and the
      white side white.
    - **Gradients.** The file has 34 `linearGradient`s, white to grey. They sit
      on lifted, curving flaps; steps 3, 8 and 11 were inspected at 2×. In step
      8, the reverse side of the opened flap shades from white at the rim to
      grey inside.
    - **Curves only where the paper curves.** Step 3's opened pocket, inspected
      at 2×, is outlined with curved edges and shaded with a gradient. The flat
      steps are straight lines.
    - **Offset layers.** Stacked layers are drawn slightly apart.
    - **The finished crane** (steps 16–17) is seen from a raised angle, in one
      flat tone with heavy outlines and about twenty strokes. It is not inflated.
    - The images are not vendored.

21. **Binnette's vector crane** (`Origami_-_Crane.svg`, Wikimedia Commons, CC
    BY-SA 3.0, 2009; the reference `crane-book-drawing.md` already links).
    [fetched; ran `svg_segments.py`]
    - 17 paths, 67 straight segments, no curves.
    - 31 linear gradients, roughly one per visible panel.
    - Black strokes at two widths (3 and 4 on a 1752 px canvas).
    - Its refinement comes from few, long lines, a clean silhouette and one
      gradient per panel. Our upright book drawing has 617 paths.

22. **Books that draw inflated finished models** (Lang, Montroll, Kasahara). Not
    fetched, since their illustrations are not publicly posted in a form that
    could be checked. **UNVERIFIED.**
    - `the-puff-is-a-drawing.md` describes the finished figure as an outline, a
      handful of structural creases and a three-quarter view. That is the
      repository's own reasoning, consistent with findings 20 and 21, not a
      survey.
    - What would check it: a library copy of Lang's *The Complete Book of
      Origami* (Dover) and a Montroll title, examining the final crane and
      waterbomb figures.

### D. Tone

23. **Technical illustration keeps shading to the mid-tones.** [fetched Gooch et
    al. 1998 abstract page] Gooch, Gooch, Shirley & Cohen change hue as well as
    brightness to show which way a surface faces. They keep the darkest and
    lightest values for edge lines and highlights. The book tones should
    therefore never reach the ink colour, so that lines always read.

24. **What SVG can paint.** [fetched W3C SVG issues list, Feb 2026; fetched
    librearts.org, May 2018; ran `rsvg-convert` on Binnette's file]
    - `linearGradient` and `radialGradient` render in `rsvg-convert` (31
      gradients drawn).
    - Mesh gradients and `hatch` were removed from SVG 2 in 2018 because only
      Inkscape implemented them.
    - A February 2026 proposal to delete the `meshgradient` web-platform tests
      reports all seven failing in every rendering engine.
    - So smooth 2D shading in SVG means linear or radial gradients. Hatching
      means explicit strokes.
    - **Stepped (cel) tone.** Two stops at the same offset make a hard band edge.
      [ran `seam-stepped.svg`] The band edge is then a straight line across the
      panel instead of a staircase of triangles. That is the "jagged colour
      boundaries on the curved wing" that `crane-book-drawing.md` gave up on.
      [reasoned]

25. **Gradient fills obey the same seam rule as flat fills.** [ran
    `seam-*.svg` in `scripts/H6-illustration/`, pixel at the shared diagonal by
    ImageMagick]
    - **The test.** A square split into two triangles, both with the same
      gradient.
    - **Two paths** leave a pale seam: (226,218,206) on the diagonal against
      (216,206,190) beside it.
    - **One path holding both rings** shows no seam, (216,206,190) on both.
    - **An underlay** of a nearby solid colour cuts the seam to (212,201,181).
    - **So** `Diagram`'s `Fill` contract carries over as one path per panel
      paint. Between panels a crease line normally covers the seam. Where a
      crease is omitted, an underlay is needed.

26. **How much a gradient buys on the tucked crane.** [ran `panel_gradients.py`,
    per triangle, `CraneBookDrawing`'s light direction, no visibility]
    - **Upright view.** 60 of 76 panels vary in brightness by more than 0.05.
      Across those, the root-mean-square error of one flat tone is 0.102, and of
      one linear gradient fitted in page coordinates 0.061.
    - **Top view.** 0.138 falls to 0.087.
    - **Where gradients cannot help:** the worst panels (spans 1.04–1.37) are
      the crumpled ones from finding 6.
    - **So** gradients help wherever the paper actually bends. On the rest, a
      gradient would advertise the defect.

## Implications for senbazuru

### A book renderer for a curved surface

This is the design the findings point to. It extends PRD 08 W1, whose exact
visibility and provenance classification it reuses. W1 specified visibility and
line classes. It did not specify roles, chaining, simplification, hierarchy,
halos or tone.

1. **Surface.** A `MaterialMesh` with provenance: source panel per triangle, and
   source edge and assignment per mesh edge (`senbazuru:source_panels` and
   `senbazuru:source_edges` in the saved FOLD). Also a camera `Basis` and a
   declared page scale.
2. **Planar map.** Exact convex subtraction, as `depthDrawing` does now or as
   W1's interval visibility, with a broad phase added.
3. **Boundary graph.** Cut region boundaries into maximal stretches, the way
   `Visible` cuts `Track`s. Emit each stretch **once**, labelled with its left
   and right regions and their depths. This removes finding 2 by construction.
4. **Role, never dihedral angle** (G finding 20):
   - `Outline`: paper on one side, empty page on the other.
   - `FoldEdge`: a depth jump along an `M`/`V`/`F`/`U` edge.
   - `RawEdge`: a depth jump along `B`/`C`.
   - `TurningContour`: a depth jump along a `J` edge, the outline of a bent
     panel.
   - `CreaseMark`: a crease with the same sheet and equal depth on both sides.
   - `Intersection`: equal depth, different sheets, no shared edge. This is a
     defect. It is never inked in book mode and always reported.
5. **Chaining.** Walk through every vertex where exactly two stretches meet.
   Classify each end as free, continuing, the stem of a T or the bar of a T. Start
   each chain at its lexicographically smallest end, as `closedPathData`
   already canonicalises rings, so output does not depend on traversal order.
6. **Simplification.**
   - Bénard 2014's four rules, with a threshold stated in page px at the
     declared scale (start at 5 px, measured below).
   - The existing 2 px crease cutoff.
   - An optional crease-mark policy: keep marks with |fold angle| ≥ θ, or on the
     step's moving flap. Lang's "omit consistently" becomes a declared rule,
     not a length heuristic.
7. **Style.**
   - Outline ≥ 1.5× fold/raw edge ≥ 2× crease mark (Lang 2:1, Petty 3:1).
   - A halo of about 1.5 px on every T-stem, and on crease ends meeting ink
     (Lang's gap).
   - Optional tapering at free ends later. SVG strokes have one width per
     element, so a taper must be emitted as a filled outline. [reasoned]
8. **Tone.**
   - Paper side is the first tone: colour side and white side, as in finding
     20.
   - Lighting is second, confined to mid-tones (finding 23).
   - Each panel gets either a flat tone or one `linearGradient`, smooth or
     stepped. The gradient axis comes from a least-squares fit of brightness
     over the panel's pieces, which equals the cross-ruling direction for
     cylindrical bends (finding 13).
   - A panel whose normals spread beyond a declared angle keeps a flat tone and
     is listed in the report.
9. **Determinism.**
   - Every number goes through `formatNumber`.
   - Gradient ids are numbered in document order inside one `<defs>`.
   - Strokes are sorted by role, then first point.
   - Ties use the existing `1e-9` policy and `faceOrders`.
   - The tutorial's fix for degenerate geometry, jittering vertices at random
     (§3.5), must **not** be used: it breaks goldens.

SKETCH, not a committed interface:

```haskell
data LineRole = Outline | FoldEdge | RawEdge | TurningContour | CreaseMark | Intersection
data Junction = FreeEnd | Continues | TStem | TBar
data Chain = Chain { chainRole :: LineRole, chainPoints :: [V2], chainEnds :: (Junction, Junction) }
data Paint = Solid Colour | Linear V2 V2 [(Double, Colour)]  -- ends in model units; backend projects
data BookReport = BookReport
  { reportLooseEnds :: [V2], reportIntersections :: Double, reportCrumpledPanels :: [FaceId]
  , reportDroppedStrokes :: Int, reportStrokes :: Int }
bookDrawing :: BookStyle -> Basis -> MaterialMesh -> Either BookError (Diagram, BookReport)
```

`Paint` changes `Fill` from `Fill Colour [[V2]]` to `Fill Paint [[V2]]`.
`-Wincomplete-patterns` names every place that must handle it, as the `Shape`
header describes. The default output stays byte-identical, because nothing
default uses `Linear`, which keeps PRD 08's A-1 and the "keep the default output
unchanged" rule.

### Work items

| # | Change | Where | Effort | Evidence it works |
| --- | --- | --- | --- | --- |
| I1 | Emit each contour boundary once: keep the nearer piece's copy of opposite-direction overlapping stretches | `CraneBookDrawing.contourSegments` (study) | S | `duplicates.py` reports 0 px overlapped, down from 74–78%; the outline prints heaviest |
| I2 | Role weights (outline 1.6, interior 1.0, crease 0.5), halos and crease-end gaps of 1.5 px | `bookShapes` (study) | S | Prototype: 19 outline, 58 interior and 82 crease paths; owner A/B (below) |
| I3 | Chain through degree-2 vertices; drop dangling strokes under 5 px; one path per stroke | study, then I7 | M | Upright: 617 paths to 162 in the prototype; path count and stubs as in the acceptance table |
| I4 | Report loose ends, intersection length and crumpled panels in `book-checks.json`; draw them in a review overlay, never in book mode | study | S | Current baseline: 7, 6, 2 and 12 loose ends |
| I5 | `Paint`: per-panel linear or stepped gradients, one path per panel paint, underlay where creases are omitted; side colour first | `Senbazuru.Diagram`, `Render.Svg` | M | Seam test (finding 25) as a unit test; RMS 0.102 to 0.061 on bent panels; goldens byte-identical |
| I6 | Densify in 3D, not in 2D: build the whole-crane shape sketch on a finer material mesh, or tessellate bent panels for display (Phong tessellation, α = 3/4, keeps original vertices); add a broad phase to `depthDrawing` | `WholeCrane`, `WholeCraneDrawing` (study) | M | Join-edge contour ink and sharp turns inside strokes fall; fill and line agree exactly (no 2D fit) |
| I7 | Production `Render.BookDrawing` (or W1 extended): boundary graph, roles, chaining, style, tone, report | `src/` | L | PRD 08 A-13 to A-17 plus the acceptance table below on `puffed-square.fold` and a bent-strip fixture as goldens |
| I8 | Blender Line Art as an *oracle*: a study script that renders the FOLD sheet with provenance edge marks, plus an intersections view | `study/` script | S | Stroke count and positions compared with I7's chains; intersections image matches `reportIntersections` |
| I9 | Interpolated contours (Hertzmann–Zorin) per panel, fills cut to match | research | L | Only if I6 cannot reach sub-pixel faceting at acceptable cost |
| I10 | ConTesse-class exact smooth contours | not recommended | XL | — |

Two notes on I6:

- **Phong tessellation** (Boubekeur & Alexa 2008) replaces each triangle by a
  quadratic patch that passes through the original vertices. It needs only
  that triangle's vertices and normals.
- **Cracks along creases are a risk.** A crease vertex has a different normal on
  each side, which can bend the two neighbouring patches' shared edge
  differently. Whether this leaves a gap is **UNVERIFIED**. A spike should test
  it, keeping crease edges straight if it does.

Two notes on cost:

- **The pair counts.** At 448 triangles, `depthDrawing` clips about 200k
  triangle pairs per view. At 4× and 16× refinement that becomes about 3.2M and
  51M. [reasoned from `WholeCraneDrawing.hs:57`]
- **Measure before choosing a density.** Compiled, three to five runs per
  size, as `AGENTS.md` asks. The full `--whole-crane-start` run took 3 min 49 s
  wall for every pose and view together [ran, once]. That is not a timing of the
  drawing.

What H6 cannot do: make More tucked look like one sheet of paper while 5 panels
fold back on themselves (finding 6). Those go to the geometry slices. This
renderer should make them *visible* in review and quiet in the book view, never
silently absent.

## Acceptance ideas

What "refined" means on this axis, measured at the declared 600 px per sheet
unit, per view. Baselines were measured on the current upright, opposite, low
and top views.

| Criterion | Baseline | Target | Turns red when |
| --- | --- | --- | --- |
| Contour ink drawn twice | 78 / 78 / 74 / 74% | 0% | stretches emitted per piece, not per boundary |
| Paths per view | 617 / 640 / 465 / 606 | ≤ 200 (prototype: 162 / 169 / 128 / 147) | no chaining |
| Strokes < 5 px after de-duplication and chaining | 19 / 23 / 19 / 10 (the prototype removes 19 / 17 / 7 / 16 of them as dangling) | 0 dangling | threshold ignored |
| Loose contour ends (not at a cusp) | 7 / 6 / 2 / 12 | 0 on an accepted pose; reported otherwise | intersections cancelled instead of reported |
| Line hierarchy | one weight, and doubled lines print 29% darker | outline : interior : crease ≈ 1.6 : 1.0 : 0.5, measured in raster darkness | a role mapped to the wrong width |
| Crease ends meeting ink | touch | stop 1–2 px short, except under a layer | halo dropped |
| Line and fill agreement | exact (polylines) | exact, or within 0.5 px if any 2D smoothing is kept | a curve fit without a bound |
| Seams inside a panel | none (flat fills) | none with gradients: one path per paint | gradient pieces emitted separately |
| Panels with normal spread over 90° | 5 (More tucked) | 0 for "book quality"; listed otherwise | — (geometry, not ink) |
| Determinism | byte-identical regenerations (226 archives, pillow-target note) | two runs byte-identical; goldens on fixtures | random jitter or hash-order ids |

**Owner review protocol.**

1. **Fixed conditions.**
   - Cameras: upright three-quarter, top and low. The finished figure is a
     raised three-quarter view (`the-puff-is-a-drawing.md`).
   - Page scale: 600 px per sheet unit.
   - Viewing sizes: the book size, and a thumbnail about 150 px wide for a
     squint test of the silhouette.
2. **Blind pairs.** Show current and candidate side by side with the order
   randomised and labels hidden. Ask for a preference and one sentence on why.
   Record it in the note for the change.
3. **Then the magnified view (2×) and the review overlay:**
   - loose ends and intersections in pink;
   - crumpled panels hatched;
   - omitted creases highlighted, as the current gallery already does.
4. **A checklist** against the conventions in findings 17–21:
   - Does the outline read first?
   - Are crease marks quieter than edges?
   - Does any line hang in mid-paper?
   - Does the tone say which side of the paper shows?
   - Are there fewer lines than the reader needs to count?
5. **A failure is routed, not patched.**
   - A geometry defect (crumpled panel, loose end) goes to the geometry work.
   - A style defect goes to I1–I5.
   - No tolerance is widened after seeing a result, matching
     `illustration-material-priority.md`.

## Sources fetched

All fetched 2026-09-28.

- Bénard & Hertzmann, *Line Drawings from 3D Models: A Tutorial*,
  Foundations and Trends in Computer Graphics and Vision 11(1–2), 2019.
  arXiv 1810.01175 v2: <https://arxiv.org/abs/1810.01175>. Read in full text:
  §1.2, §1.5, §2, §3.3–3.7, §4.7–4.8, §6 and §9.1–9.4.
- Liu, Bénard, Hertzmann, Hoshyari, *ConTesse: Accurate Occluding Contours for
  Subdivision Surfaces*, ACM TOG 2022/23: <https://arxiv.org/abs/2111.06006>.
  Code licence Apache-2.0 (`gh api repos/squidrice21/ConTesse/license`).
- Capouellez, Dai, Hertzmann, Zorin, *Algebraic Smooth Occluding Contours*,
  2023: <https://arxiv.org/abs/2306.01973>.
- Hertzmann, *Occluding Contour Breakthroughs, Part 2*, 2023:
  <https://aaronhertzmann.com/2023/07/31/occluding-contours-part-2.html>.
- Hertzmann & Zorin, *Illustrating Smooth Surfaces*, SIGGRAPH 2000. Search
  abstract only, via <https://cims.nyu.edu/gcl/papers/hertzmann2000iss.pdf>
  listing. The method details come from the tutorial.
- Appel, Rohlf & Stein, *The Haloed Line Effect for Hidden Line Elimination*,
  SIGGRAPH 1979. Search abstract only; the ACM page and PDF returned 403.
- Goodwin, Vollick & Hertzmann, *Isophote Distance*, NPAR 2007:
  <https://www.dgp.toronto.edu/papers/tgoodwin_NPAR2007.pdf>. Abstract and §1
  read.
- Cole et al., *Where Do People Draw Lines?*, SIGGRAPH 2008:
  <https://gfx.cs.princeton.edu/pubs/Cole_2008_WDP/>.
- Gooch, Gooch, Shirley & Cohen, *A Non-Photorealistic Lighting Model for
  Automatic Technical Illustration*, SIGGRAPH 1998:
  <https://users.cs.northwestern.edu/~ago820/SIG98/abstract.html>.
- Boubekeur & Alexa, *Phong Tessellation*, SIGGRAPH Asia 2008:
  <https://perso.telecom-paristech.fr/boubek/papers/PhongTessellation/>. PDF
  read: §3–4, α = 3/4, interpolates vertices.
- Yuksel, Schaefer & Keyser, *Parameterization and Applications of
  Catmull–Rom Curves*, CAD 2011. Search abstract.
- Blender manual sources: `render/freestyle/view_layer/line_set.rst`,
  `grease_pencil/modifiers/generate/line_art.rst` and
  `files/import_export/grease_pencil_svg.rst` at
  <https://projects.blender.org/blender/blender-manual>. docs.blender.org
  returned 403.
- Freestyle SVG Exporter:
  <https://extensions.blender.org/add-ons/freestyle-svg-exporter/>
  (GPL-2.0-or-later, limited support). Blender is GPL. It was run, not vendored
  (D17).
- Wikipedia, *Developable surface*: <https://en.wikipedia.org/wiki/Developable_surface>
  (CC BY-SA 4.0).
- Wikipedia, *Yoshizawa–Randlett system*:
  <https://en.wikipedia.org/wiki/Yoshizawa%E2%80%93Randlett_system> (CC BY-SA
  4.0).
- Lang, *Origami Diagramming Conventions*:
  <https://langorigami.com/article/origami-diagramming-conventions/>.
- Petty, *Origami diagramming*, British Origami Society:
  <https://www.britishorigami.org/academic/davidpetty/origami_diagramming.htm>.
- Origami Resource Center, *Origami Symbols*:
  <https://origami-resource-center.com/origami-symbols/>.
- Hudson, *Orizuru* diagram, Public Diagram Project, CC BY 3.0:
  <https://commons.wikimedia.org/wiki/File:Tsuru_wiki.svg>. Downloaded to
  scratch for measurement only; **not to be vendored**.
- Binnette, *Origami - Crane.svg*, CC BY-SA 3.0:
  <https://commons.wikimedia.org/wiki/File:Origami_-_Crane.svg>. Downloaded to
  scratch for measurement only; **not to be vendored**. CC BY-SA is not MIT.
- LaFosse, *Origami Activities for Kids* (Tuttle), excerpt at
  <https://www.cutoutandkeep.net/projects/origami-crane-3>. Only the text
  was retrievable, not the illustrations.
- W3C public-svg-issues, Karl Dubost, 2026-02-09:
  <https://lists.w3.org/Archives/Public/public-svg-issues/2026Feb/0029.html>.
- Libre Arts, *Gradient meshes and hatching to be removed from SVG 2.0*,
  2018: <https://librearts.org/2018/05/gradient-meshes-and-hatching-to-be-removed-from-svg-2-0/>.

## Open questions

1. **Tone by side.** Should the book view colour the two sides of the paper
   differently, as every diagram does? That would expose the reverse-side
   patches `whole-crane-candidate.md` warned of, and the choice turns on
   whether geometry work removes them first.
2. **Which creases.** Which crease marks belong in a finished-model figure? The
   options are a fold-angle threshold θ, "only creases the next step
   references", or an authored list. Lang only asks that the rule be
   consistent.
3. **Where the book renderer lives.** Is it a mode of PRD 08's W1
   (`--lines book`), or a separate `Render.BookDrawing`? The role table in
   finding 8 argues W1's line table should change either way. Assigning
   silhouettes crease weight contradicts the book convention.
4. **Refinement density.** How dense must the display mesh be before joins stop
   showing at 600 px per unit? Is the O(n²) planar map affordable there, or does
   it need a broad phase first? Both need measuring (I6).
5. **Stippling or hatching.** Petty recommends dots for depth. Should the book
   style ever use them, or should it stay with the flat and gradient tones of
   findings 20 and 21? If stippling is used, its dots should be placed by
   material coordinates so they stay put between views and runs.

## Unverified

- **The seventh loose end.** Whether the one loose end 0.62 px from a projected
  crossing (finding 4) comes from a crossing or from something else. Check:
  inspect that end in 3D.
- **Line Art stability.** That Line Art's output is byte-stable across runs and
  Blender versions. Check: two runs and a `cmp`.
- **Phong tessellation.** Whether it leaves cracks along creases when each side
  has its own normals. Check: a two-panel fixture, measuring the gap between
  the two patches' shared edge curves.
- **Cost.** How long the planar map takes on the whole crane at 448, 1792 and
  7168 triangles. Check: a compiled benchmark, three to five runs each.
- **Books.** How Lang, Montroll and Kasahara draw finished inflated models
  (finding 22). Check: library copies.
- **The halo paper.** Appel et al. 1979's gap size and method were read only
  from a search abstract. Check: the full paper through a library.
- **Interpolated contours.** That finding 5's interpolated-contour length would
  survive visibility. It was measured before any visibility test. Check:
  implement I9's visibility on one view.
- **The binary.** That the study binary used was built from exactly `83fc960`.
  Its timestamp is today and its outputs match the committed note's numbers,
  but its build inputs were not hashed.
