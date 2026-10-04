# H5. Photoreal 3D rendering of folded paper

Research slice H5, written 2026-09-28 against `main` at `83fc960` (clean tree
apart from an untracked `.claude/`). Nothing in the repository was changed.
Every experiment ran on a copy of the repository in a scratch directory; the
study's `--whole-crane-start` command regenerated the whole-crane archive there,
and Blender 4.4.1 (installed at `/Applications/Blender.app`) rendered its
**More tucked** pose (`spread-0`, the owner's preferred shape). Images and
scripts named below live beside this note in `scripts/H5-photoreal/`.

> **Verification, 2026-09-28.** [V](V-verification.md) re-checked this note.
> Finding 2's 44.5% / 1.6% wrong-side pixels reproduce; the claim that the
> two-copy GLB breaks *every* path tracer was measured on Cycles only.
> Finding 21: Blender's FAQ says published scripts using its API must be
> "licensed as GNU GPL as well", stricter than its licence page; whether a
> `bpy` script may live in the MIT tree is an owner decision. The default
> GLB's visible-paper scene already draws coincident layers correctly in
> three.js ([X1](X1-paper-look-renders.md)). The PNG comparisons it names are
> not kept.

It builds on [research G](G-realistic-rendering-and-simulation.md) ("G"), section
C, and on [PRD 08](../08-prd-realistic-rendering.md) M7a. Where it agrees it cites
G by finding number; where it goes further or disagrees it says so.

Evidence tags: **[code]** a file and line read; **[ran]** a command run here, given
in the finding or in `scripts/H5-photoreal/`; **[fetched]** a page fetched on 2026-09-28,
with its URL in "Sources fetched"; **[paper]** a paper or abstract read;
**[reasoned]** derived here. **UNVERIFIED** marks anything not checked, with what
would check it.

A few words used throughout, for a reader who has never rendered anything:

- **Rasterizer.** A renderer that draws triangles one by one into the screen and
  keeps the nearest at each pixel (three.js, Blender's EEVEE, every browser 3D
  viewer). Fast; light bouncing between surfaces has to be faked.
- **Path tracer.** A renderer that follows rays of light around the scene (Blender
  Cycles, Mitsuba, three-gpu-pathtracer). Slow; bounced light, soft shadows and
  light passing through paper come out naturally.
- **Normal.** The direction perpendicular to a surface at a point; brightness is
  computed from it ([crane-panel-lighting.md](../../docs/notes/crane-panel-lighting.md)).
- **BSDF.** The rule saying how much light arriving from one direction leaves in
  another. Its reflected part is a BRDF; its transmitted part a BTDF.
- **Diffuse / specular.** Diffuse light leaves in all directions (matte);
  specular leaves near the mirror direction (a highlight).
- **Sheen.** Extra brightness at grazing angles from fine fibres standing out of
  a surface; velvet is the extreme case.
- **Diffuse transmission (translucency).** Light passing *through* a thin sheet
  and leaving in all directions on the far side. It is why a lampshade glows.
- **Ambient occlusion (AO).** Darkening where surrounding surfaces block light
  from arriving, as in the bottom of a pocket.
- **Tone mapping.** Squeezing the range of computed brightness into what a screen
  can show. The choice changes colours, not just contrast.
- **HDRI.** A panoramic photograph of real surroundings used as a light source.
- **Z-fighting.** Two surfaces at the same depth: a rasterizer cannot tell which is
  nearer, so pixels flicker between them.

## Summary

The quickest route to a "refined" 3D crane is not a better paper BSDF but
removing four artefacts, then lighting it like a product photograph. Measured
on the More tucked crane:

1. **The GLB's two-copy sheet breaks every path tracer.** senbazuru writes each
   face twice at the same position, one copy per side, and relies on the viewer
   skipping triangles seen from behind. Cycles does not skip them: 44.5% of
   paper pixels showed the wrong side, against 1.6% in EEVEE, a rasterizer.
   Offline renders must rebuild one two-sided surface.
2. **Smooth normals need PaperLighting's rule.** Without it, Blender's own
   smoothing left black holes at the wing roots; with it they vanished. PRD 08's
   R-08-6 omits the rule and should adopt it.
3. **Thickness cannot be added by offsetting the surface.** Blender's even-thickness
   shell moved vertices up to 2,165 half-thicknesses at the 180° folds, and a
   plain shell of true 0.1 mm thickness brings 203 more triangle pairs into
   contact. Real thickness waits for a layout that keeps layers apart.
4. **Realism exposes the shape.** Two colours and backlit translucency both reveal
   the candidate's crossings, which plain lighting hides.

Beyond artefacts, the paper look is five cues in order of payoff:

1. soft studio lighting with contact shadows;
2. colour-preserving tone mapping (Khronos PBR Neutral);
3. panel-smooth normals;
4. backlit diffuse translucency;
5. crease-memory lines drawn in material coordinates.

Fibre texture and edge thickness are about one pixel at hero size, so they come
last. `KHR_materials_diffuse_transmission` is still a release candidate. Babylon.js
and the Khronos sample viewer load it; three.js r186 and Blender do not.

A Cycles still costs 15 to 54 s on the owner's M1 Max. The recipe below splits
into a no-geometry-change viewer pass (S), a study-only offline still generator
(M), and material-space textures (M, needs owner decision 6).

## Findings

### A. What the 3D views do today, and what fails first

1. **The study's crane viewer is lit like a quick preview.**
   - **Setup** [code] (`study/fold-material/whole-crane-3d.html`):
     - a hemisphere light and one directional light (`:65-67`);
     - ACES Filmic tone mapping (`:61`);
     - a flat background colour (`:64`);
     - no environment map, no shadows and no ambient occlusion (grep of the file
       for `shadow`, `environment` and `AO` finds none).
   - **Materials.** They are the GLB's own: base colour, metallic 0, roughness 1
     (`src/Senbazuru/Render/Gltf.hs:418`) [code]. The page only swaps the colour
     and toggles flat shading (`whole-crane-3d.html:166-172`).
   - **What PaperLighting adds.** Normals averaged per original panel, joined to
     GLB corners by material reference (`study/fold-material/PaperLighting.hs`;
     `paper-lighting.mjs:12-17`) [code]. Downloads keep flat lighting
     (`docs/notes/crane-panel-lighting.md:37`) [code].
   - **The consequence** [reasoned]:
     - a model with no shadow cannot sit on anything;
     - ACES shifts pale colours (finding 20).

2. **senbazuru's two-copy sheet is correct in rasterizers and wrong in path
   tracers.**
   - **The design.** Each face is written twice, wound oppositely, with no
     `doubleSided`, so that back-face culling shows one copy per side
     (`Gltf.hs:33-42`; G finding 15, which this confirms for rasterizers).
   - **What Blender imports** [ran]. `spread-0.glb` becomes one object with 896
     faces, 448 per material, each material flagged `use_backface_culling =
     True` (`scripts/H5-photoreal/glb_probe.py`).
   - **Only EEVEE honours the flag** [fetched]. The Blender 5.2 manual documents
     backface culling under EEVEE's material settings; Cycles' material settings
     have no such option, and its object "Culling" is camera and distance
     culling of whole objects.
   - **The measurement** [ran]. Recolour the two sides red and blue and render the
     same close-up three ways (`scripts/H5-photoreal/compare-sides.png`; left to right in
     the table):

     | Route | Wrong-side pixels | Unclassified (red and blue mixed) |
     | --- | ---: | ---: |
     | GLB imported, Cycles | 44.5% | 10.3% |
     | GLB imported, EEVEE | 1.6% | 6.0% |
     | FOLD rebuilt as one two-sided surface, Cycles (the reference) | — | — |

     Each is a share of 611,392 paper pixels (`side_mismatch.py`).
   - **Why** [reasoned]. The two copies are equally near, so a path tracer takes
     whichever its search finds first, triangle by triangle.
   - **Beyond G** [reasoned]. G stopped at "`doubleSided` does not give two
     colours". The next consequence is that no GLB viewer that traces rays can use
     today's file for offline work; the offline route must rebuild the sheet
     (Implication 3).
   - **UNVERIFIED.** That Mitsuba and three-gpu-pathtracer fail the same way.
     Rendering `spread-0.glb` in each would check it.

3. **Smoothing needs PaperLighting's "behind" rule; PRD 08 R-08-6 lacks it.**
   - **The rule.** PaperLighting keeps a triangle's own flat normal wherever the
     panel average points behind it (`PaperLighting.hs:46`) [code].
   - **The experiment** [ran] (`scripts/H5-photoreal/compare-normals.png`):
     - *Without the rule:* Blender's built-in smoothing, split only at
       source-panel boundaries, put black triangles at the wing roots.
     - *With the rule:* the same normals set as custom normals removed them.
     - *Deviation cap:* capping at 30° as well made no visible difference (34
       corners flat instead of 8).
   - **Deviation statistics** [ran] (`normal_dev.py` on `spread-0.fold`):
     - 1,344 corners, 8 of them kept flat, which matches the note's "eight"
       (`crane-panel-lighting.md:41-42`);
     - median deviation from the triangle's own normal 2.2°, 90th percentile
       12.7°, 99th percentile 38.5°, maximum 69.8°;
     - 26 corners deviate by more than 30°.
   - **What PRD 08 says.** R-08-6 specifies "summed and normalised" and R-08-8
     refuses only a zero sum (`PRDs/08-prd-realistic-rendering.md:271-280`)
     [code]. Neither keeps the flat normal when the sum points behind, so a GLB
     written to R-08-6 would reproduce the black holes in any viewer.

4. **Realistic rendering exposes the candidate's shape defects rather than
   hiding them** [ran] (`scripts/H5-photoreal/compare-full.png`, bottom row).
   - **Two colours.** Red and white sides show jagged white patches on the body,
     the reverse-side patches `whole-crane-candidate.md` reports for cream and
     ochre.
   - **Backlight.** With translucency 0.3, buried flaps show through the body as
     darker shapes, crossings included (`compare-backlight.png`).
   - **Crossings measured** [ran] (`near_pairs.py`): a BVH overlap test finds 289
     triangle pairs that cross and share no vertex. The pillow note counts 266
     "strict crossing pairs" on a different pose and definition
     (`crane-pillow-target.md:78`), so the numbers are not comparable.
   - **Consequence.** Photorealism is not a way around the shape work. It raises
     the bar for it.

### B. What real paper looks like

5. **Paper is a thin, two-sided scatterer with four visible components** [paper].
   - **Papas, de Mesa & Jensen (EGSR 2014)** measured matte and glossy paper. They
     found a mix of four components:
     - subsurface scattering;
     - specular reflection;
     - retroreflection, meaning extra light sent back toward the light;
     - surface sheen.
   - **Why ordinary models fail.** Standard microfacet and diffuse models cannot
     produce the double-sided look of a thin layer.
   - **Their model** turns a multi-layer subsurface model into a BSDF with both
     reflection and transmission (abstract via OpenAlex; full text is closed
     access).
   - **Beyond G** [reasoned]. G left sheen "untested" (Unverified list). This is
     measured support that sheen and retroreflection belong in a paper recipe;
     their parameter values remain **UNVERIFIED**, needing the paper's tables.

6. **Rough-diffuse models capture the matte, back-scattering part, and support is
   arriving** [fetched].
   - **The model.** EON, an energy-preserving Oren–Nayar model (Portsmouth, Kutz &
     Hill, JCGT 14(1), 2025, revised December 2025), models flatter,
     more back-scattering rough surfaces.
   - **Support:**
     - Cycles exposes it as *Diffuse Roughness* on the Principled BSDF (Cycles
       only, Blender 5.2 manual). Blender 4.4 has the input (`probe.py`) [ran].
     - three.js merged it into `MeshPhysicalMaterial.diffuseRoughness` on
       2026-09-09 for milestone r187, not r186 (PR #34379; r186's
       `MeshPhysicalMaterial.js` has no such field). Its `GLTFLoader` on `dev`
       reads `KHR_materials_diffuse_roughness`.
     - Babylon.js has a loader for it.
     - The Khronos extension itself is an open pull request (KhronosGroup/glTF
       #2481, updated 2026-08-17). It is not in the registry.

7. **Translucency is the cue that most separates paper from plastic, and it
   reveals structure** [ran] (`compare-backlight.png`).
   - **Backlit without transmission,** the shadow side is a flat grey.
   - **With a Translucent BSDF mixed at 0.3,** the wings glow and overlapping
     layers read as darker bands, the look of a real backlit crane.
   - **The colour of transmitted light** [reasoned]. Light crossing the sheet
     passes through both dye layers, so both sides see the same transmitted
     colour (light paths are reversible). The experiment used
     `sqrt(front × back)` per channel as that colour.
   - **Transmittance is UNVERIFIED.** A search result attributes "less than 25%"
     transmission to dry white paper to a paper-microfluidics article, but
     ScienceDirect refused the fetch. A photograph of a kami crane on a light
     box would settle it.

8. **At drawing and hero scale, fibre texture and edge thickness are about one
   pixel** [reasoned].
   - **Inputs:**
     - The study's drawing scale is 600 px per sheet side
       (`illustration-material-priority.md`).
     - Kami is commonly a 15 cm square of about 60 gsm [fetched, kamiori-studio].
     - OrigamiUSA's review measured one kami at 72 microns and 63 gsm [fetched].
     - The repo takes 0.1 mm as origami-paper thickness
       (`a-crease-is-a-hinge.md:44`); 0.072 mm is a measured kami value inside
       that.
   - **Arithmetic:**
     - One drawing pixel is 150 mm / 600 = 0.25 mm, so the sheet's thickness is
       0.3–0.4 px.
     - In a 1600-px still where the wingspan, 0.774 sheet sides for `spread-0`
       [ran, gallery log], fills about 1,000 px, a pixel is about 0.12 mm.
   - **Consequence:**
     - Paper edges and crease radii, about 1.25 thicknesses at their tightest
       (`a-crease-is-a-hinge.md:60-67`), are about one pixel.
     - Fibres, much finer, are invisible except in macro shots.

9. **What a crease looks like, at that scale** [reasoned, partly fetched].
   - **A folded crease** is a sudden change of normal. Split normals already draw
     it (finding 3).
   - **A crease that was folded and opened again** stays as a faint groove or
     ridge, "crease memory". The crane's body is covered in them, and no
     geometry records them: 42 edges of `spread-0.fold` are `F` (flat), and
     crease assignments count M 120, V 82 and F 42 [ran].
   - **Dyed paper can show its white side along folds and corners.** OrigamiUSA's
     kami review saw the white side through cracks in the coloured side, and
     white points at corners where the colour scraped off [fetched]. That review
     used a tessellation, so how often a crane's mountain creases show it is
     **UNVERIFIED**; a photograph of the owner's paper would settle it.
     Coated-paperboard studies describe cracking of the coating along fold lines
     (search summaries only).
   - **Highlights on rounded edges.** Blender's Bevel shader node rounds shading
     at edges without changing geometry. It costs about 20% render time and is
     Cycles only [fetched, Blender manual].
   - **Density of crease memory.** 244 source crease segments were rasterised
     into a 2048² texture over the sheet, 0.073 mm per texel [ran]. They are
     invisible at whole-crane scale and visible in close-ups.

### C. glTF extensions and viewer support, September 2026

10. **Registry status** [fetched: `gh api repos/KhronosGroup/glTF/contents/extensions/README.md`;
    last registry update 2026-09-03, commit `81762cc328`].
    - **Ratified:**
      - `KHR_materials_sheen`, `KHR_materials_specular`, `KHR_materials_volume`,
        `KHR_materials_transmission`, `KHR_texture_transform`;
      - `KHR_node_visibility`, which G listed as **UNVERIFIED**; that is now
        settled.
    - **Release candidate.** `KHR_materials_diffuse_transmission`, unchanged since
      G. Its README last changed 2025-10-13 (#2537).
    - **Initial draft.** `KHR_materials_subsurface`.
    - **The dollar-bill example.** The diffuse transmission README shows a single
      plane with one side's colour in `baseColorTexture` and the other's in
      `diffuseTransmissionColorTexture`. Two-sided appearance through
      transmission is therefore anticipated by the extension; two-sided
      *reflection* is still not.

11. **Which loaders read which extension** [fetched, 2026-09-28]:

    | Loader | sheen | specular | texture_transform | diffuse_transmission | node_visibility | diffuse_roughness |
    | --- | --- | --- | --- | --- | --- | --- |
    | three.js `GLTFLoader` r186 (released 2026-09-24) | yes | yes | yes | **no** | **no** | no (dev: yes) |
    | Blender importer (glTF-Blender-IO `main`) | yes | yes | yes | **no** | no | no |
    | Babylon.js loader (master; 9.28.0 released 2026-09-24) | yes | yes | yes | **yes** | yes | yes |
    | Khronos glTF Sample Renderer | yes | yes | — | **yes** | — | — |
    | model-viewer v4.3.1 | via its three.js peer `^0.183.0` | | | no (three.js lacks it) | | |

    Sources:
    - three.js: `grep` of `GLTFLoader.js` at `r186` and `dev`.
    - Blender: the "Import" rubric of `scene_gltf2.rst`, and a code search
      returning 0 hits for `diffuse_transmission`.
    - Babylon.js: the file listing of
      `packages/dev/loaders/src/glTF/2.0/Extensions`.
    - Khronos Sample Renderer: its README checklist.
    - model-viewer: its `package.json`.

    Two cells stay open. Whether model-viewer enables every extension its peer
    supports is **UNVERIFIED**, as in G. So is whether Babylon's
    `KHR_node_visibility` loader shipped in 9.28.0.

12. **Volume and transmission stay wrong for a sheet** [fetched]. `KHR_materials_volume`
    needs a closed, manifold mesh for any nonzero thickness. `KHR_materials_transmission`
    is specular (glass-like). This agrees with G finding 16.

13. **Baked ambient occlusion has two carriers, and they differ** [fetched,
    `Specification.adoc`].
    - **`COLOR_0`** multiplies base colour, so it darkens direct light too. It is
      portable and needs no texture.
    - **`occlusionTexture`** affects only indirect light, which is the physically
      right one. It needs `TEXCOORD_0` and an image.
    - **Per side** [reasoned]. Each side of the paper already has its own material
      (`paper`, `paper underside`). Front and back can therefore carry different
      occlusion textures while sharing material coordinates, which PRD 08
      R-08-9 already maps to `TEXCOORD_0`.

### D. Geometry for rendering

14. **Offsetting the surface ("solidify") cannot give this crane thickness today**
    [ran]. Blender's Solidify modifier offsets the surface into two shells. Three
    measurements on `spread-0.fold` with thickness t = 0.000667 sheet units
    (0.1 mm on a 150 mm sheet):
    - **Even-thickness correction explodes at 180° folds**
      (`shell_extent.py`).
      - With it, shell vertices move up to 2,165× the half-thickness, and 129 of
        474 exceed twice it.
      - Without it, the maximum is exactly t/2.
      - The correction scales each vertex's offset up by how far its averaged
        normal leans from its faces. At a flat fold the two faces' normals are
        opposite and their average nearly cancels [reasoned; Blender's exact
        formula not read]. It appears in
        `scripts/H5-photoreal/compare-thickness.png` (right) as a bloated tail with a
        black gap.
    - **Plain shells bring new pairs into contact** (`near_pairs.py`). Counting
      triangle pairs that share no vertex, lie within distance t of each other
      and do not already cross:

      | t (sheet units) | 0.000667 | 0.002 | 0.005 | 0.015 | 0.03 |
      | --- | ---: | ---: | ---: | ---: | ---: |
      | New near pairs | 203 | 352 | 1,017 | 3,095 | 6,380 |

      On the closed flat crane (`before.fold`) the count at 0.000667 is 16,693:
      a flat-folded model has its layers touching.
    - **The payoff is small anyway.** At true thickness the shelled tail is
      indistinguishable from zero thickness at 320 mm lens framing
      (`compare-thickness.png`, left and middle).
    - **Agreement with G.** This agrees with G findings 7 and 13 (thickness
      before contact; display exaggeration is a different number), and adds the
      measurement and the even-offset failure.

15. **Rim-only thickness is a cheaper cue, still bounded by layer contact**
    [fetched, reasoned].
    - **The option.** Blender's Solidify has "Only Rim", which keeps only the
      strip joining the two shells. A strip of width t along boundary edges
      would draw the paper's white edge without moving any surface.
    - **The catch.** Where a flap lies on another layer, a centred strip pokes
      t/2 through that layer. A one-sided strip needs the free side from the
      layer order.
    - **A texture line instead.** Drawing a 1–2 texel light line along boundary
      edges in material coordinates gives the same cue at hero scale with no
      geometry (Implication 4).

16. **Smooth silhouettes need moved vertices, which conflicts with a standing
    rule** [paper, fetched, code].
    - **Phong Tessellation** (Boubekeur & Alexa, SIGGRAPH Asia 2008) observes that
      interpolated normals already hide facets inside a shape. What remains is
      polygonal *silhouettes* and interior contours. Their fix moves new vertices
      onto curved patches built from vertex normals alone [paper, pp. 1-2].
    - **Subdivision surfaces** with crease tags do the same across the whole mesh:
      Hoppe et al. 1994 introduced sharp-feature handling [paper, abstract], and
      Blender uses OpenSubdiv with per-edge crease values [fetched].
    - **The conflict** [reasoned]. Both change positions, and the owner's
      milestone rule is to keep SVG and GLB on the same geometry
      (`illustration-material-priority.md:56`) [code]. A display-only
      silhouette refinement must therefore be applied to both, or labelled
      display-only in the fidelity record (PRD 08 R-08-1). The crane's panels
      are nearly flat (median normal deviation 2.2°, finding 3), so the payoff
      today is small. The puffed bodies of other slices would change that.

17. **Coincident layers flicker in real-time viewers, and three options exist**
    [code, fetched, reasoned].
    - **Why depth tricks fail.** The complete-sheet GLB keeps touching layers at
      equal depth (`crane-pillow-target.md`, "may show touching-surface
      flicker"). No depth-buffer precision trick separates equal depths:
      three.js r186 offers `logarithmicDepthBuffer` and `reversedDepthBuffer`
      (`WebGLRenderer.js:83`, `:3699-3701`), but both only redistribute
      precision.
    - **(a) Physical separation.** A solver-side remedy (finding 14).
    - **(b) Per-layer depth bias in the viewer.** three.js `Material` has
      `polygonOffset`, `polygonOffsetFactor` and `polygonOffsetUnits`
      (`Material.js:375-391`). The viewer could bucket faces by a rank taken from
      the directional layer requirements and give each bucket a larger offset.
      It changes no positions and opens no gaps (unlike the removed layer-spacing
      export, `paper-thickness.md`). It fails where the order is cyclic, as in a
      pinwheel. **UNVERIFIED**: whether one rank exists for the crane's overlap
      groups.
    - **(c) Clipping per view,** as the study's depth preview does. It is
      view-dependent, so it cannot live in a static GLB.

### E. Renderers, lighting and cost

18. **three.js r186 already has what a refined viewer needs** [fetched, file tree
    at tag `r186`].
    - **Tone mapping.** `AgXToneMapping` and `NeutralToneMapping` (`constants.js:473`,
      `:483`).
    - **Environment lighting.** `RoomEnvironment`, a procedural studio, for image
      lighting with no asset.
    - **Ambient occlusion.** `GTAOPass` for WebGL and `GTAONode`/`SSGINode` for
      WebGPU.
    - **Soft shadows.** The `webgl_shadowmap_pcss`, `_vsm` and `_progressive`
      examples. `PCFSoftShadowMap` is deprecated since r186 in favour of
      `PCFShadowMap` (`constants.js:73`).
    - **Materials.** `MeshPhysicalMaterial` with `sheen`, `sheenRoughness`,
      `specularIntensity`, `transmission` and `thickness`.
    - **Missing:** diffuse transmission (finding 11). A search of three.js issues
      for "diffuse_transmission" found none open.
    - **Third-party AO:**
      - N8AO: CC0-1.0 (`gh api …/license`), last pushed 2026-08-10.
      - realism-effects: MIT, but last pushed 2024-02-04.
      - pmndrs/postprocessing: Zlib.

19. **What each light does for paper** [ran, reasoned] (`compare-full.png`,
    `hero-recipe.png`).
    - **Environment alone** gives flat, even brightness. That is today's look.
    - **A large soft key light and a ground plane** give the shape a direction
      and a contact shadow.
    - **A light behind the model,** with translucency, gives the glow of
      finding 7.
    - **The test scene.** The recipe used Blender's bundled "studio" HDRI at
      strength 0.15–0.2 with a key area light and a back area light. The
      bundled HDRIs are CC0 from Poly Haven (the `license.txt` in Blender's
      `studiolights/world`) [ran]. All Poly Haven assets are CC0, with
      redistribution allowed [fetched].

20. **Tone mapping changes the paper's colour, and ACES is the wrong default for
    it** [fetched].
    - **The claim.** The model-viewer write-up says ACES and AgX, designed for
      film, desaturate and shift bright colours. Khronos PBR Neutral keeps hue
      and saturation up to a brightness of 0.8. The write-up says base colours
      below sRGB 231 are reproduced faithfully under even white light.
    - **Where it is available.** In three.js as `NeutralToneMapping`; in Blender
      4.4 as the "Khronos PBR Neutral" view (`config.ocio:60`) [ran].
    - **Why it matters here.** Paper is judged against a swatch. The crane viewer
      uses ACES today (finding 1).

21. **Offline renderers: cost, licence, and what each gives paper.**
    - **Blender Cycles** [ran, fetched].
      - *Cost.* 128 samples at 1200×900 took 15–33 s per still on the M1 Max GPU
        (Metal); 256 samples at 1600×1200 took 53.65 s. The first run paid about
        80 s compiling Metal kernels.
      - *Paper support.* Blender 5.2's Principled BSDF adds a *Thin Wall* mode
        described as suited to paper and leaves (manual, `blender-v5.2-release`
        branch). The local 4.4 lacks it, so the experiment mixed in a Translucent
        BSDF.
      - *Licence.* Blender is GPL. The Cycles engine alone is Apache-2.0
        (`blender/cycles`).
      - *The script question.* Blender says Python scripts using its API must,
        if published, be under a GPL-compliant licence, and that renders belong
        to their author. Whether an MIT-licensed `bpy` script in this repository
        satisfies that is an owner question (Open questions).
    - **Mitsuba 3** [fetched].
      - *Licence.* BSD-3-Clause plus an enhancements clause.
      - *Paper support.* Its `twosided` BSDF accepts two BRDFs, one per side. Its
        `principledthin` has `diff_trans`. It loads OBJ, PLY and its own
        formats, not glTF.
      - *Precedent.* Narain, Pfaff & O'Brien rendered their crumpled-paper
        results with Mitsuba (SIGGRAPH 2013, acknowledgements) [paper].
      - **UNVERIFIED:** how `twosided` combines with transmission.
    - **three-gpu-pathtracer** [fetched].
      - *Licence.* MIT.
      - *Limits.* v0.0.25 (2026-09-28) requires WebGPU and supports only
        `MeshStandardMaterial` and `MeshPhysicalMaterial`.
      - *Two sides.* It would need one two-sided surface as Cycles does
        (finding 2, **UNVERIFIED** for this renderer).

22. **The recipe works on the existing More tucked geometry** [ran].
    - **What it is** (`render_paper.py`):
      - one mesh from `spread-0.fold`;
      - PaperLighting normals as custom split normals;
      - a two-sided Principled BSDF through the Geometry node's *Backfacing*
        output, with roughness 0.8, diffuse roughness 0.5, specular IOR level
        0.35 and sheen 0.15 at roughness 0.6;
      - a Translucent BSDF mixed at 0.18–0.3;
      - a bump from crease memory plus fine noise in material coordinates;
      - PBR Neutral tone mapping.
    - **What it did.** The facets and wrong-side patches of the plain GLB import
      are gone (`compare-full.png` top left against top right). The backlit
      still (`hero-recipe.png`) reads as paper.
    - **What it is not.** The constants are starting points chosen by eye, not
      calibrated.

## Implications for senbazuru

Ordered by payoff per effort. None changes default outputs or goldens.

1. **Viewer pass on `whole-crane-3d.html` and the generic study viewer, effort S.**
   No change to the GLB, positions or downloads.
   - **Tone mapping and lights:**
     - switch ACES for `NeutralToneMapping`;
     - add `scene.environment` from `RoomEnvironment` through `PMREMGenerator`,
       at an environment intensity of about 0.3–0.6;
     - add one key `DirectionalLight` with `castShadow`, a `normalBias` of about
       0.2% of the model's radius, and PCF or VSM soft shadows;
     - add a large ground plane with `ShadowMaterial`, or a matching light floor.
   - **Ambient occlusion.** `GTAOPass` (or N8AO, CC0), with a radius of 2–5% of
     the model's size.
   - **Material.** `MeshPhysicalMaterial` per side with roughness 0.8–0.9,
     `specularIntensity` about 0.5, and `sheen` 0.15–0.25 at `sheenRoughness`
     about 0.6.
   - **Normals.** Keep PaperLighting's.
   - **How we would know:**
     - screenshots at the page's four fixed cameras, before and after;
     - the frame rate on the owner's machine at 448 and 4,312 triangles;
     - the owner's review against the cue checklist below.
   - **Risk.** Shadow acne on zero-thickness sheets. `shadowSide` and
     `normalBias` exist for that; **UNVERIFIED** until tried.

2. **Amend PRD 08 R-08-6, effort S.**
   - **The rule.** If a region's summed normal at a vertex points behind a
     triangle (dot product ≤ 0 with that triangle's own normal), that corner
     gets the triangle's flat normal and the vertex is split, as
     `PaperLighting.hs:46` already does.
   - **The acceptance row it needs.** Count such corners on the crane (8 today)
     and render a close-up with no black triangles.
   - **Evidence.** Finding 3. Without the rule, the M7a GLB reproduces the
     black-hole artefact in every viewer that trusts `NORMAL`.

3. **Offline still generator, study only, effort M.**
   - **The pipeline.** A script reads a FOLD frame with `senbazuru:source_panels`
     and `senbazuru:material_coords`, or a GLB with its extras. It builds **one**
     two-sided surface, applies the recipe, and writes stills for the gallery,
     never for CI.
   - **Engine.** Blender (run, not vendored, D17) is proven here. Mitsuba 3 is the
     alternative with a permissive licence and a Python API.
   - **Budget.** 15–60 s per still.
   - **Never render the GLB as imported** (finding 2).
   - **How we would know.** The side-correctness check (A1 below) against the
     SVG two-colour views, and owner review.
   - **Licence.** Blocked on the `bpy` licence question if the script is to live
     in the MIT tree.

4. **Material-space textures, effort M.** This is PRD 08's A2b. It needs owner
   decision 6 (encoder and provenance). One PNG per side, drawn by
   senbazuru from the crease pattern, so provenance is "ours":
   - **Base colour** carries:
     - *crease memory:* every M, V and F source crease as a 1–2 texel line, very
       slightly darker, and lighter on the dyed side of mountains if the
       white-line cue is confirmed;
     - *edge lines:* along `B` edges, the colour of the paper's core;
     - *fibre noise:* optional, and only worth it for macro shots.
   - **An `occlusionTexture` per side,** baked by ray casting against the
     surface.

   Cost [reasoned, not measured]:
   - 1,344 corners × 64 rays × 448 triangles is about 3.9 × 10⁷ tests without an
     acceleration structure;
   - at 4,312 triangles a bounding-volume tree is needed.

   A 2048² texture is 0.073 mm per texel on a 15 cm sheet (finding 9).
   Deterministic bytes are required (R-08-14).

5. **Optional material extensions behind a flag, effort S.**
   - **The flag writes** `KHR_materials_specular` and `KHR_materials_sheen`
     (ratified; read by three.js, Blender and Babylon), and optionally
     `KHR_materials_diffuse_transmission`. Diffuse transmission is a release
     candidate read only by Babylon and the Khronos sample renderer; its
     transmitted colour would be the product-of-sides colour of finding 7.
   - **Never** in `extensionsRequired`; never volume or transmission (finding
     12; agrees with G implication 8 and PRD 08 R-08-15).
   - **The fidelity record** says appearance A1, A2 or A3.

6. **Translucency in the three.js viewer, effort M, prototype first.**
   - **In three.js.** A shader chunk that adds light arriving from behind
     (`max(0, −N·L)`) times the transmission colour to the diffuse term, through
     `onBeforeCompile`. It is ours to maintain until three.js loads diffuse
     transmission.
   - **In Babylon.js.** The alternative is a Babylon.js viewer page that loads
     the extension natively. That is a new dependency (Apache-2.0).

7. **Per-layer depth bias for coincident layers in the viewer, effort M–L.**
   - **The approach** is finding 17(b).
   - **The metric.** Measure flicker (A3 below) first; if the complete scene
     flickers under 0.1% of paper pixels, skip this.

8. **Physical thickness and rounded folds in renders, effort L–XL.**
   - **Depends on** the solver slices keeping layers at least t apart and
     rounding 180° folds (finding 14).
   - **Until then,** use the texture edge line (Implication 4) and no shells.
   - **When it lands,** use plain (not even-thickness) offsets with a rim, a
     white-core rim material, and the display exaggeration named separately from
     physical thickness (G finding 7).

9. **Silhouette smoothing, effort M, deferred.** Revisit when a puffed body
   (waterbomb, crane pillow) shows polygonal outlines at the declared drawing
   size. Apply it to SVG and GLB alike, or record it as display-only
   (finding 16). Prefer finer solver meshes.

**Not recommended:**

- `KHR_materials_volume` or `KHR_materials_transmission` on a sheet;
- normal-map wrinkles that the geometry does not have (they would claim a puff the
  solver did not produce; `the-puff-is-a-drawing.md` requires schematics to say
  so);
- even-thickness solidify;
- path-tracing the GLB as exported.

### The paper-look recipe

These are starting values from this experiment, to be tuned by owner review.
They are not calibrated.

| Aspect | GLB viewer (three.js r186) | Offline still (Cycles; Mitsuba analogue) |
| --- | --- | --- |
| Surface | Two copies with back-face culling (today's file) | One surface; the side is chosen by *Backfacing* (Mitsuba: `twosided` with two BRDFs) |
| Normals | PaperLighting, including the "behind" rule; later `NORMAL` per amended R-08-6 | The same normals as custom split normals |
| Diffuse | Base colour per side; roughness 0.8–0.9; `diffuseRoughness` about 0.5 once r187 ships | Principled roughness 0.8; Diffuse Roughness 0.5 |
| Specular and sheen | `specularIntensity` about 0.5; `sheen` 0.15–0.25 at `sheenRoughness` about 0.6 | Specular IOR level 0.35; Sheen 0.15 at roughness 0.6 |
| Translucency | Custom chunk (Implication 6), or none | Translucent BSDF mixed at 0.15–0.3, colour `sqrt(front × back)`; Blender 5.2: Thin Wall |
| Crease memory and edges | `baseColorTexture` per side (Implication 4) | Bump from the same texture; optional Bevel node at about 0.05 mm |
| Occlusion | GTAO or N8AO, radius 2–5% of the model; later a baked `occlusionTexture` | Path-traced |
| Light | `RoomEnvironment` at 0.3–0.6; soft key with shadows; ground shadow catcher | Studio HDRI at 0.15–0.2; large key area light; back light for glow; ground plane |
| Tone map | `NeutralToneMapping` | "Khronos PBR Neutral" view |
| Cost | Real-time; **UNVERIFIED** frame rate | 15–54 s per still measured (M1 Max, Metal) |

## Acceptance ideas

How we would measure "refined" on the appearance axis.

**Automatic checks**, each able to fail:

- **A1. Side correctness.**
  - *The check.* Render with the two sides coloured red and blue from four
    cameras. Compare with an independent reference: the SVG two-colour views
    (`*-colours.svg`) rasterised with `rsvg-convert` at a matched orthographic
    camera. At most 1% of paper pixels may show the wrong side.
  - *Baseline.* 44.5% for the Cycles GLB import and 1.6% for EEVEE (finding 2).
    The matched-camera reference is not built; **UNVERIFIED**.
- **A2. No inverted shading.**
  - *In the data.* The count of written corner normals with a dot product of
    zero or less against their triangle is zero.
  - *In a render.* No pixel of front-facing geometry has a shading normal facing
    away from the viewer, read from Cycles' Normal pass.
- **A3. Flicker.**
  - *The check.* Render the complete-scene viewer twice with a 0.01° camera
    jitter; side-ID changes stay at or below 0.1% of paper pixels.
  - *First step.* Measure today's value before promising one.
- **A4. Colour fidelity.** A panel facing the camera under even white light
  renders within ΔE ≤ 3 of the declared paper sRGB. PBR Neutral's stated range
  makes this achievable below sRGB 231.
- **A5. Validity and determinism.** `study/gltf/validate.cjs` reports 0 errors
  and 0 warnings. Any texture bytes are identical across runs. Default exports
  and the 33 goldens are unchanged (PRD 08 A-1).
- **A6. Cost.**
  - *Offline.* At most 60 s per 1600×1200 still at 256 samples on the owner's
    machine (53.65 s measured).
  - *Viewer.* At least 30 frames per second at 1080p with AO and shadows,
    measured at 448 and 4,312 triangles.

**Owner judgement, recorded in a `docs/notes/` note:**

- **A7. Cue checklist.**
  - *How it is scored.* Side by side with reference photographs, at a matched
    camera and a similar light. The references are Andreas Bauer's crane on
    Wikimedia Commons (CC BY-SA 2.5), Tinygami's opening sequence (already cited
    in `crane-pillow-target.md`), and the owner's own photograph of a kami crane.
    Photographs are not vendored. Each cue is scored yes, partly or no.
  - *The cues:*
    1. no facets inside a panel;
    2. crisp creases;
    3. a contact shadow grounding the model;
    4. darkening inside pockets and openings;
    5. paper colour matching the swatch;
    6. glow and darker layered regions under backlight;
    7. faint crease memory in close-up;
    8. paper edges readable at flap tips in close-up;
    9. no speckle, flicker or wrong-side patches;
    10. no polygonal silhouette on a curved panel at the declared size.
  - *Pass.* A "refined" pass is yes on 8 of 10, with 9 mandatory.
- **A8. Blind A/B.** The owner picks between two recipe variants at fixed
  cameras (for example ACES against Neutral, or translucency 0 against 0.25).
  Record the choice and keep the losing variant reproducible.

## Reproducing the experiments

Run from a copy of the repository at `83fc960`. The inputs used are kept in
`scripts/H5-photoreal/data/` with these SHA-256 values:

- `spread-0.fold`: `ff972384…2e82359`
- `spread-0.glb`: `99686e64…1922b`
- `before.fold`: `44e866b2…3b947de9`

```bash
stack run senbazuru-material-study -- --whole-crane-start \
  study/fold-material/fixtures/whole-crane-body.fold build/fold-material   # 11 min 55 s wall, cold study build
B=/Applications/Blender.app/Contents/MacOS/Blender                          # 4.4.1
$B -b --factory-startup --python render_paper.py -- spread-0.glb  glb.png   glb   samples=128 res=1000x750 lens=200 aim=0.03,0,-0.12 glbfront=c0392b glbback=2e6fd8
$B -b --factory-startup --python render_paper.py -- spread-0.fold flat.png  flat  samples=128 res=1000x750 lens=200 aim=0.03,0,-0.12 front=c0392b back=2e6fd8
$B -b --factory-startup --python side_mismatch.py -- flat.png glb.png         # finding 2
python3 normal_dev.py spread-0.fold                                           # finding 3
$B -b --factory-startup --python near_pairs.py  -- spread-0.fold 0.000667 0.002 0.005 0.015 0.03   # finding 14
$B -b --factory-startup --python shell_extent.py -- spread-0.fold 0.000667   # finding 14
$B -b --factory-startup --python render_paper.py -- spread-0.fold hero.png paper samples=256 res=1600x1200 \
  world=0.15 key=140 fill=5 backlight=2 transl=0.25 backpos=-0.6,1.3,0.8 view=1,-1.5,0.55 dist=1.9 exposure=-0.5 front=efe7d6 back=efe7d6
```

The finding 2 renders also passed `world=0.2 key=110 fill=8 exposure=-0.4
dist=1.7`, and the EEVEE variant added `engine=BLENDER_EEVEE_NEXT`.

## Sources fetched

All fetched 2026-09-28. Licences are given where code or assets might be used.

**glTF:**

- Registry README: `gh api repos/KhronosGroup/glTF/contents/extensions/README.md` (CC-BY-4.0 text).
- Extension READMEs via `gh api`: `KHR_materials_diffuse_transmission`, `_sheen`, `_specular`, `_volume`, `KHR_texture_transform`, `KHR_node_visibility`.
- Specification source: <https://raw.githubusercontent.com/KhronosGroup/glTF/main/specification/2.0/Specification.adoc>.
- Diffuse roughness proposal: <https://github.com/KhronosGroup/glTF/pull/2481>.

**three.js** (MIT; `gh api repos/mrdoob/three.js/license`):

- `examples/jsm/loaders/GLTFLoader.js` at `r186` and `dev`.
- `src/materials/MeshPhysicalMaterial.js`, `src/constants.js`, `src/materials/Material.js` and `src/renderers/WebGLRenderer.js` at `r186`.
- The r186 file tree.
- The release list.
- PR #34379 (EON): <https://github.com/mrdoob/three.js/pull/34379>.

**Other viewers and tools:**

- Blender glTF importer, glTF-Blender-IO (Apache-2.0): `docs/blender_docs/scene_gltf2.rst` and the repository tree.
- Babylon.js (Apache-2.0): loader extension directory and release list.
- Khronos glTF Sample Renderer (Apache-2.0): README.
- model-viewer (Apache-2.0): `packages/model-viewer/package.json` and the release list.
- glTF-Transform (MIT): repository tree, which includes `khr-materials-diffuse-transmission`.

**Blender manual** (`projects.blender.org/blender/blender-manual`, `main` and `blender-v5.2-release`):

- `render/shader_nodes/shader/principled.rst`, `render/materials/settings.rst`, `render/eevee/material_settings.rst`, `render/cycles/material_settings.rst`, `render/shader_nodes/input/{bevel,ao,geometry}.rst`.
- `modeling/modifiers/generate/{solidify,subdivision_surface}.rst`.
- `manual/conf.py` (version 5.3) and the branch list.

**Licences, tone mapping and assets:**

- Blender licence page: <https://www.blender.org/about/license/>.
- Cycles (Apache-2.0): `gh api repos/blender/cycles`.
- Mitsuba 3 (BSD-3-Clause plus an enhancements clause): `LICENSE`, `src/bsdfs/twosided.cpp`, `src/bsdfs/principledthin.cpp` and the `src/shapes` listing.
- three-gpu-pathtracer (MIT): README and `package.json`.
- N8AO (CC0-1.0), pmndrs/postprocessing (Zlib), realism-effects (MIT): `gh api` licence fields.
- Khronos PBR Neutral: `gh api repos/KhronosGroup/ToneMapping/contents/PBR_Neutral/README.md` (CC-BY-4.0), and <https://modelviewer.dev/examples/tone-mapping>.
- Poly Haven licence: <https://polyhaven.com/license> (CC0).

**Papers and abstracts:**

- M. Papas, K. de Mesa, H. W. Jensen, "A Physically-Based BSDF for Modeling the Appearance of Paper", *Computer Graphics Forum* 33(4), EGSR 2014, <https://doi.org/10.1111/cgf.12420>. Abstract via <https://api.openalex.org/works/doi:10.1111/cgf.12420>; the publisher pages returned 403.
- J. Portsmouth, P. Kutz, S. Hill, "EON: A practical energy-preserving rough diffuse BRDF", JCGT 14(1) 2025, <https://arxiv.org/abs/2410.18026> (abstract).
- T. Boubekeur, M. Alexa, "Phong Tessellation", ACM TOG 27(5) 2008, <https://perso.telecom-paristech.fr/boubek/papers/PhongTessellation/PhongTessellation.pdf> (pp. 1-2 read).
- H. Hoppe et al., "Piecewise smooth surface reconstruction", SIGGRAPH 1994, abstract via OpenAlex.
- R. Narain, T. Pfaff, J. F. O'Brien, "Folding and Crumpling Adaptive Sheets", SIGGRAPH 2013, <http://graphics.berkeley.edu/papers/Narain-FCA-2013-07/Narain-FCA-2013-07.pdf> (acknowledgements read).

**Reference photographs and pages:**

- Wikimedia Commons metadata for `File:Origami-crane.jpg` (Andreas Bauer, CC BY-SA 2.5) and `File:Origami_-_Crane.svg` (Binnette, CC BY-SA 3.0).
- Kami weight and size: <https://kamiori-studio.jp/blog/origami-paper-guide>.
- Kami thickness (72 µm, 63 gsm) and the white side showing through cracks:
  OrigamiUSA, "Paper Review #12: Kami",
  <https://origamiusa.org/thefold/article/paper-review-12-kami>.
- Wikipedia's "Origami paper" (no thickness given).

## Open questions

- **`bpy` licence.** Blender says scripts using its API must be published under
  a GPL-compliant licence. Is an MIT `bpy` script in the MIT tree acceptable,
  since MIT is GPL-compatible? Or should the offline driver live outside the
  tree, or use Mitsuba (BSD) instead?
- **Plain paper or two colours for the illustration milestone?** Two colours and
  translucency expose the candidate's crossings (finding 4). Is photoreal
  shown only for poses whose crossings are resolved?
- **The white line at mountain creases on kami.** Is it a cue the owner wants?
  It needs a photograph to confirm on the paper the owner folds with.
- **Viewer library.** Stay on three.js with a custom translucency chunk, or add a
  Babylon.js page for native diffuse transmission?
- **Is a hybrid the real "refined" target?** For example, a photoreal render
  with book-style ink lines on top (contours and crease marks as in
  `crane-book-drawing.md`). That is a question for the drawing slice as much
  as this one.
- **Where do per-paper appearance constants live** (colour per side,
  translucency, gloss)? In the material block G implication 3 proposes for
  thickness and stiffness, or as render options?

## Unverified

- Parameter values from Papas et al. 2014: only the abstract was read.
- Paper transmittance ("less than 25%" for dry white paper): search summary only.
- How often a crane's mountain creases show kami's white side: the OrigamiUSA
  review saw it in a tessellation, not a crane.
- Blender's even-thickness formula (finding 14): the explanation is reasoned from
  the measured overshoot, not read from Blender's source.
- That Mitsuba 3 and three-gpu-pathtracer show the two-copy failure of finding 2:
  not run.
- How Mitsuba's `twosided` combines with transmission: not tested.
- Frame rate of the proposed three.js viewer pass: not measured. three.js was not
  installed here, because installing packages was out of scope for this slice.
  The real-time look was approximated with EEVEE only for the side-correctness
  test.
- Shadow acne and self-shadowing of zero-thickness sheets in three.js: not tried.
- Whether a single layer rank exists for the crane's overlap groups (finding 17b).
- Whether model-viewer enables every extension of its three.js peer, and whether
  Babylon's `KHR_node_visibility` shipped in 9.28.0.
- The EEVEE 1.6% residual in finding 2: its causes (edges, shading-dependent
  classification) were not separated.
- Baked-AO cost (Implication 4): arithmetic only.
- All recipe constants: chosen by eye on one pose, not calibrated against
  photographs.
