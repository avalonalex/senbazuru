# G. Realistic rendering of folded paper, and the models that produce its geometry

Researcher slice G, written 2026-09-14 against branch `docs/prds-sequence-language`
(clean tree, HEAD `568dcb6`). Nothing was built or run; every repository claim is
from reading the file cited. External files marked "via `gh api`" were fetched
from the project's default branch on that date.

## Summary

In production, senbazuru renders only rigid flat panels: zero thickness, flat
normals, no animation, two colours from opposite-wound copies of each face.
The material study goes further. It prototypes rounded creases and shows they
stretch paper where folds cross. It bends panels with Discrete-Shells-style
springs and a directional contact barrier. Its checked routes are sampled
states, not animations.

glTF limits:

- `KHR_materials_diffuse_transmission`, the one extension naming paper, is a
  release candidate that three.js and Blender cannot load.
- `KHR_materials_volume` needs a closed mesh; a sheet is not closed.
- Smooth shading needs normals, split at creases.

Animation:

- **Nested node transforms** pivoting on creases are exact if each key turns
  each crease under 180°.
- **Skinning** collapses rounded creases.
- **Morph targets** reintroduce vertex interpolation.

SVG lines should be classified by material provenance, never by dihedral
thresholds, with silhouettes computed per view.

Warnings: issue #114's premises are stale, and IPC-family contact needs
thickness before starting from a flat stack.

## Findings

### A. What the repository renders today

1. **Production glTF is rigid, faceted and unlit beyond flat shading.**
   `Render.Gltf` writes a "Visible paper" and a "Complete paper" scene at
   unmoved positions (`src/Senbazuru/Render/Gltf.hs:13-19`). The two colours
   come from writing each face twice with reversed winding into two materials
   (`Gltf.hs:33-42`). Those material objects set only base colour, metallic 0
   and roughness 1, and no `doubleSided` (`Gltf.hs:384`). glTF therefore culls
   back faces (spec `Specification.adoc:2468-2470`), so each copy shows from
   one side. No normals are written (`Gltf.hs:49-50`), so the spec obliges
   viewers to compute flat normals (`Specification.adoc:1684`). three.js does
   so by switching to flat shading (`GLTFLoader.js:3554`). No animation is
   written, pending #56 (`Gltf.hs:52-55`). Physical thickness is metadata only
   (`Gltf.hs:29`, `:243`; `src/Senbazuru/Origami/Surface.hs:21-24`, `:298-304`;
   `docs/usage.md:190-191`).

2. **Issue #114's premises are out of date; do not build to them.**
   - **The body.** It says `Render.Gltf` lifts faces by layer number and
     derives a radius from `--thickness` and `layerDepths`. Both the lifting
     and the flag were removed (`docs/notes/paper-thickness.md:3-17`;
     `docs/tour.md:472`; `docs/usage.md:190`). The later note says a display
     layer number does not determine how much material a crease wraps
     (`docs/notes/a-crease-is-a-hinge.md:92-97`).
   - **The second comment.** It claims one connected component per face.
     That is still true of *graphics indices*: `completePaper` gives each piece
     its own corners (`src/Senbazuru/Render/PaperMesh.hs:74-77`), and
     `assemble` concatenates corners per piece into `POSITION`
     (`Gltf.hs:369-371`). But there is no gap. Positions coincide, and material
     connectivity is stored in extras (`docs/notes/visible-paper-mesh.md:64-67`).
     A "mesh is connected" acceptance test must count components through the
     `materialWeights` extras or the source topology, not through glTF index
     adjacency.
   - **Issue #104** cites `docs/notes/inflate-outside-draw-inside.md`, which is
     not in `docs/notes/` (listed; no match).

3. **Bent panels already reach glTF, but only as faceted triangles.**
   - **Planar and convex only.** The visible scene refuses non-planar panels
     (`PaperMesh.hs:69`, `:99-105`), and export refuses non-convex faces
     (`Gltf.hs:276-284`).
   - **Study exports.** The study writes bent endpoints with `CompletePaper`
     (`study/fold-material/CoupledCreaseGallery.hs:80`) or `VisiblePaper`
     (`CraneSpreadGallery.hs:104`). With no `NORMAL` attribute, those shade
     faceted in any viewer (finding 1).
   - **The study's own viewer.** Its WebGL viewer does compute normals. It sums
     them per group, so lighting splits at sharp creases while material indices
     stay shared (`study/fold-material/viewer.html:94`, `:220-237`;
     `docs/notes/sharp-creases-and-opening-panels.md:69-71`).
   - **The roadmap** calls general bent-panel rendering a study-to-production
     gap (`docs/roadmap.md:62`).

4. **SVG today has three paths, book notation, and no silhouette pass.**
   - **Paths.** `Render.CreasePattern` chooses between three
     (`CreasePattern.hs:21-34`):
     - `Origami.Visible` for flat models. It subtracts nearer faces and keeps
       an edge only where the paper differs across it (`Visible.hs:26-50`).
     - `Render.Projected` for open convex planar panels. It compares depths at
       the corners of overlapping shadows. It declines intersecting,
       non-planar, concave and unresolved-tie cases (`Projected.hs:1-23`;
       `docs/notes/projected-panel-visibility.md:44-49`).
     - An older painter fallback for everything else.
   - **Line vocabulary.** It is the printed-book one (`Diagram/Style.hs:12-23`).
     A folded form is drawn with solid lines only. The dotted x-ray line is
     deliberately unused, because drawing every hidden edge would be the
     wireframe again (`Style.hs:35-47`).
   - **Offset view.** It uses two weights, with buried sheets at a third of a
     crease (`CreasePattern.hs:69-76`; `Style.hs:176-184`).
   - **Silhouettes.** #104 is open (`docs/roadmap.md:222-227`). One
     measurement matters here: dropping non-silhouette edges from the crane's
     offset view removed only 6 of 242 edge copies, because nearly every
     crease of a folded model already separates faces at different depths
     (`docs/notes/layer-numbers.md:111-115`).

5. **What the material study covers.**
   - **(a) Rounded creases.** `FoldMaterial` replaces a crease with a band of
     width πr bent into a half-cylinder (`FoldMaterial.hs:1-16`, `:61-78`).
     - For one fold this is isometric, meaning surface lengths are preserved
       (`docs/notes/two-bends-need-more-than-radii.md:27-34`).
     - Turn the packet about a perpendicular crease, reusing the same band for
       the second bend, and the outer layer's band stretches 200%. The surface
       gains 4.71% area, and shrinking r narrows the band without reducing the
       stretch (`two-bends…:47-60`).
     - The note calls this a controlled counterexample, not a physics model
       (`:87-93`).
   - **(b) Bent panels.** Every shared triangle edge gets an angular spring.
     Crease segments get stiffness κ·l; panel-interior edges get B·l/h. The
     solve relaxes with staged length penalties
     (`docs/notes/crease-and-panel-energy.md:19-43`;
     `FoldBending.hs:18-23`). The constants are illustrative, not measured
     (`crease-and-panel-energy.md:30-31`).
   - **(c) Contact.** A barrier acts on a *directional* distance to violating
     a retained above/below order (`docs/notes/directional-contact-distance.md:18-50`;
     `SurfaceContact.hs:33-38`). Its scope limits are in `:75-81` of that note.
   - **(d) Routes.**
     - Checked rigid flap turns with whole-interval contact checks
       (`Origami/Flap.hs:1-24`; `HingeSweep.hs:1-11`).
     - Composed recipes such as the blintz (`BlintzSequence.hs:1-15`).
     - The bird petals, with 23 exported states
       (`study/fold-material/README.md:48-57`).
     - The state selector jumps between computed poses and never interpolates
       (`README.md:325-328`).
     - There are no intermediate states of the double fold's second fold,
       because that needs a path between curved panels (`README.md:311-318`).
   - **(e) Explicitly open.** Physical thickness, paper calibration and general
     continuous collision checking (`README.md:303-304`).
   - **Animation.** Searching `src`, `app` and `study/fold-material/*.hs` for
     `animations` finds nothing; no glTF animation exists anywhere.

### B. Geometry models, and whether a sequence could feed them

6. **Rigid panels with sharp creases (senbazuru).**
   - **The model.** One angle per crease is the state; positions are derived.
     Interpolating positions, or scaling all angles by t, leaves the set of
     angles that close every loop (`docs/notes/fold-angles-are-the-state.md:11-31`).
   - **The transforms.** `foldFrameWith` returns one `Rigid` per face,
     `foldedPlacements`, keyed against the *cut* pattern (`Origami/Folding.hs:283-323`).
     They are computed by `spanningWalk` (`:572`).
   - **Inputs.** A DSL has these natively.
   - **Output, cost, maturity.** Faceted, with exact lengths; cheap; production.
     Licence MIT.
   - **Physical limit** (from the repo's own summary of Lechenault et al. 2014
     and Rao et al. 2013, not re-fetched here):
     - Real folds have a minimum radius of about one thickness.
     - The crease-opening versus panel-bending length L\* is about 200
       thicknesses, roughly 2 cm for 0.1 mm paper.
     - Hence flanks on hand-sized models are curved, not flat
       (`a-crease-is-a-hinge.md:36-48`, `:56-70`).

7. **Rounded crease fillets (#114).**
   - **Inputs.**
     - A rigid state.
     - Physical thickness t.
     - A per-crease wrap count n, giving r ≈ n·t/2 (`a-crease-is-a-hinge.md:83-86`).
     - A rule for vertices where fillets meet; the #114 body, step 4, leaves
       this undecided.
   - **Can a DSL feed it?** Angles and face orders, yes. The wrap count must be
     derived from the face orders along each crease, not from display layer
     numbers (`a-crease-is-a-hinge.md:92-97`).
   - **Output quality.**
     - Right for isolated parallel folds.
     - Stretches where a second fold wraps an already-bent stack (finding 5a).
     - Undefined at vertices.
   - **Cost and maturity.** Cheap; a study counterexample only.
   - **Scale, derived here.** The study uses r = 0.015 on a unit sheet, so
     adjacent layers are 3% of the side apart (`two-bends…:13-15`).
     - On a 15 cm sheet that is 4.5 mm.
     - A real single wrap puts layers about one thickness, 0.1 mm, apart
       (`a-crease-is-a-hinge.md:43-44`, `:85-86`).
     - So the study's picture is about 45× exaggerated. True-scale fillets are
       invisible at whole-model zoom.
     - Any renderer needs a named *display exaggeration* distinct from
       physical thickness. That is the confusion `paper-thickness.md:3-17`
       records the project already made once.

8. **Thick panels (Tachi 2011; offset panel technique).**
   - **Tachi's construction.** Tapered or two-ply constant-thickness plates,
     with hinge axes kept exactly on the ideal zero-thickness edges and volumes
     trimmed by bisecting planes.
     - The thick model follows ideal rigid-origami kinematics.
     - Each crease can reach only π−δ, with tan(δ/2) proportional to
       thickness, so the model *cannot fold completely flat*.
     - Non-adjacent collisions need extra trimming.
     - The method suits simultaneous-motion mechanisms.
     - Shifting axes instead over-constrains interior vertices, giving six
       constraints instead of three
       ([PDF](https://origami.c.u-tokyo.ac.jp/~tachi/cg/ThickRigidOrigami_tachi_5OSME.pdf),
       pp. 1-7).
   - **Offset panel technique.** Preserves zero-thickness kinematics over the
     full range of motion, with uniform or varying thickness and gaps
     (Edmondson et al. 2015 abstract,
     <https://scholarsarchive.byu.edu/facpub/1605>; Morgan et al. 2016 abstract,
     <https://scholarsarchive.byu.edu/facpub/1619>).
   - **Inputs.** Crease pattern, angle range, thickness; a rigid route can
     feed them.
   - **Why it is the wrong model for paper.** Paper makes room for its
     thickness by bending around the layers it wraps (finding 6), not by
     trimmed rigid plates. Tachi's plates cannot reach flat, which is where
     most diagram steps end.
   - **Where it is useful.** A possible "rigid thick material" mode, such as
     card. No reusable code was verified; Tachi's implementation was a
     Grasshopper/VC# script (p. 7).

9. **Bar-and-hinge models (MERLIN; Filipov et al. 2017).**
   - **Filipov et al.** A simple, efficient reduced model of three behaviours:
     in-plane stretching and shear, panel bending, and crease folding
     ([Semantic Scholar record](https://api.semanticscholar.org/graph/v1/paper/DOI:10.1016/j.ijsolstr.2017.05.028)).
   - **Liu & Paulino 2017**
     ([PMC5666233](https://pmc.ncbi.nlm.nih.gov/articles/PMC5666233/)):
     - Bars lie along fold lines and across panels.
     - Rotational springs along creases model folding; springs across panels
       model bending.
     - Quadrilaterals are split along the shorter diagonal.
     - Inputs are node coordinates, connectivity, rest angles, modulus and
       thickness, with crease moment scaled by crease length.
     - Springs stiffen as the dihedral angle approaches 0 or 2π, preventing
       *local* interpenetration at a hinge.
     - Code is MATLAB supplementary material; the licence is not stated.
   - **Can a DSL feed it?** Yes. FOLD vertices and fold angles are exactly its
     inputs. But layer order is not an input, and contact between separated
     layers is not modelled.
   - **Output, derived from the discretisation.** A panel can bend only about
     its chosen diagonals, so curvature is coarse.
   - **SWOMPS** (<https://github.com/zzhuyii/OrigamiSimulator>) adds compliant
     creases and inter-panel contact (README). GitHub reports no licence file
     (`gh api …/license` returns 404), so its code is not reusable.
   - **Relation to the study.** The study cites Filipov's separation of
     behaviours but not its calibrated law (`crease-and-panel-energy.md:32-35`).

10. **Origami Simulator (Ghassaei, Demaine & Gershenfeld, 7OSME 2018).**
    - **Licence and method.** MIT (GitHub licence field). An explicit method
      computed on the GPU in WebGL
      ([paper page](http://erikdemaine.org/papers/OrigamiSimulator_Origami7/)).
    - **Motion.** It starts flat and folds every crease simultaneously, then
      exports FOLD/STL/OBJ and can visualise strain
      ([README](https://github.com/amandaghassaei/OrigamiSimulator)).
    - **Default constants.** Axial stiffness 20, crease 0.7, panel 0.7,
      face 0.2, damping 0.45 (`js/globals.js:50-56`, via `gh api`).
    - **Crease targets.** Each target is `targetTheta * u_creasePercent` in the
      shader (`index.html:278`). The fold-percent slider scales every angle
      linearly, the move `fold-angles-are-the-state.md` rules out for rigid
      paper. A compliant model tolerates it by stretching.
    - **No collision.** The string `collision` does not occur in `index.html`
      (count 0) or `js/dynamic/dynamicSolver.js`.
    - **Rendering.**
      - Two meshes, `FrontSide` and `BackSide`, with flat-shaded Phong
        materials in two colours (`js/model.js:106-122`).
      - A `LineSegments` object per FOLD assignment M/V/F/B/U/C (`model.js:14-28`).
      - `polygonOffset` pushes the paper behind the lines (`model.js:83-111`).
      - The lines are raster, relying on the depth buffer; there is no vector
        output.
    - **Can a DSL feed it?** Target angles, yes. Steps, anchoring and layer
      order, no. A multi-layer flat state has nothing keeping its layers apart.

11. **Discrete elastic shells (Grinspun, Hirani, Desbrun & Schröder, SCA 2003).**
    - **Energy.** W = W_M + k_B·W_B
      ([PDF](http://www.cs.columbia.edu/cg/pdfs/10_ds.pdf)):
      - Membrane terms penalise changes in edge length and triangle area.
      - Bending is W_B = Σ_e (θ_e − θ̄_e)²·|ē|/h̄_e, where h̄_e is a third of
        the average height of the two triangles (eq. 2, p. 2).
      - Non-flat rest shapes come from storing the undeformed mesh in 3D (p. 3).
      - Time stepping is Newmark; runs took minutes to hours on a 2 GHz
        Pentium 4 (p. 4).
    - **The study already sits in this family.** Its panel term B·l/h uses the
      *mean* height (`FoldBending.hs:18-23`; `crease-and-panel-energy.md:26-31`).
      That is the same form, up to the constant in h. What the study lacks is
      a calibrated k_B and a membrane energy; it enforces lengths by penalty
      instead.
    - **Inputs.** Rest mesh (the material coordinates), a per-edge rest angle
      (a crease rest angle from a sequence) and stiffnesses.
    - **Licence.** Paper only; no code checked.

12. **Elastic fold mechanics (Jules, Lechenault & Adda-Bedia, Soft Matter 2019).**
    - **The model.** Faces and crease are one thin sheet with a non-flat
      reference shape, replacing the hinge-plus-flat-faces picture. It shows a
      marked asymmetry between tension and compression, and derives the local
      shape of the crease ([arXiv abstract](https://arxiv.org/abs/1808.04892)).
    - **What it is.** Not a simulator. It is the argument that a crease's
      width and rest angle are material properties, and that faces near a
      crease are not flat. A sequence should not have to state these; they
      belong to a material description (compare `a-crease-is-a-hinge.md:98-100`).

13. **Robust thin-sheet contact: IPC (Li et al. 2020) and C-IPC (Li, Kaufman & Jiang 2021).**
    - **IPC.** Guarantees intersection- and inversion-free trajectories
      regardless of material, step size or deformation. Demonstrations reach
      2.3 M tetrahedra and 498 K contacts per step
      (<https://ipc-sim.github.io/>). Code: `ipc-sim/IPC` MIT and
      `ipc-sim/ipc-toolkit` MIT (GitHub licence fields).
    - **C-IPC.** Unifies shells, rods and particles. Distance-offset barriers
      give shells a geometric thickness. It adds a C² strain-limiting barrier
      and an additive continuous collision detection; one demonstration has 54
      interleaved cards (<https://ipc-sim.github.io/C-IPC/>). Code:
      `ipc-sim/Codim-IPC` Apache-2.0.
    - **Against the study's barrier.**
      - The study reuses IPC's scalar barrier `-(h-d)² log(d/h)`
        (`directional-contact-distance.md:39-45`). But it applies it to a
        *directional* distance, which resists a layer reversal before shadows
        overlap (`:1-16`). An unsigned distance cannot say which layer is on
        top.
      - Conversely, the study's barrier forbids passing around another layer
        even without collision, and needs a separated reference encounter
        (`:75-79`). IPC permits any collision-free path.
      - Both are undefined at zero distance. Trials outside the barrier's
        domain are refused (`:48-49`).
    - **Consequence, derived.** A flat-folded zero-thickness stack has
      touching layers at distance zero; every exported corner of a quarter
      fold has height zero (`visible-paper-mesh.md:30-34`). Such a stack cannot
      be the *starting* state of an IPC-style solve without a thickness offset,
      and C-IPC's offset is exactly that. Thickness therefore comes before
      general contact.

### C. glTF realism

14. **Extension status** (registry README, via `gh api` of
    <https://github.com/KhronosGroup/glTF/blob/main/extensions/README.md>).
    - **Ratified.** Under "Ratified Khronos Extensions": `KHR_materials_sheen`,
      `KHR_materials_transmission`, `KHR_materials_volume`, `KHR_materials_unlit`,
      `KHR_animation_pointer`, `KHR_mesh_quantization` and
      `KHR_texture_transform` (lines 8-34).
    - **Release candidate.** `KHR_materials_diffuse_transmission` (line 52, and
      the Status section of its own README).
    - **Fallback.** Khronos material extensions are designed to fall back
      safely, and normally should not be listed in `extensionsRequired`
      (README `:159`, `:174`).

15. **Two-sided paper.**
    - **`doubleSided` does not give two colours.** `doubleSided: true` disables
      culling and flips back-face normals for lighting, with the *same* material
      (`Specification.adoc:2468-2472`). None of the ratified, multi-vendor or
      vendor extension names on the registry page is a per-side material
      (names at README `:81-125`; not every vendor spec was read).
    - **The portable answer** is senbazuru's two reversed-winding primitives.
      Viewers map `doubleSided` differently: Blender inverts it into Backface
      Culling (`docs/blender_docs/scene_gltf2.rst:488-499` in
      [glTF-Blender-IO](https://github.com/KhronosGroup/glTF-Blender-IO),
      Apache-2.0), and three.js maps it to `DoubleSide`
      (`GLTFLoader.js:3718-3720` in [three.js](https://github.com/mrdoob/three.js),
      MIT).
    - **With thickness, derived.** Once a sheet has thickness offsets, front
      and back become separate offset surfaces. The trick becomes real
      geometry, with no coincident triangles.

16. **Physically based materials for paper.**
    - **Diffuse transmission.** The extension models diffuse light passing
      through infinitely thin surfaces, naming leaves and paper
      (`KHR_materials_diffuse_transmission/README.md:32`). But it is only a
      release candidate. It is absent from three.js GLTFLoader's extension
      handlers (grep of `KHR_`/`EXT_` names) and from the Blender add-on's
      *Import* list (`scene_gltf2.rst`, "Extensions" rubric). Those viewers
      fall back to the core material.
    - **Transmission.** Thin-walled *specular* transparency, aimed at glass and
      plastics (`KHR_materials_transmission/README.md:68-70`).
    - **Volume.** A nonzero thickness requires a closed manifold mesh
      (`KHR_materials_volume/README.md:90`, `:112`). A folded sheet is not
      watertight (`docs/glossary.md:125`), so volume does not apply to a sheet.
    - **Sheen.** Models velvet-like micro-fibres
      (`KHR_materials_sheen/README.md:38`, `:80`).
      - three.js `MeshPhysicalMaterial` has `sheen`, `transmission`,
        `thickness`, `ior` and `dispersion` (`src/materials/MeshPhysicalMaterial.js`).
      - model-viewer's scene-graph material references sheen, transmission and
        volume (`packages/model-viewer/src/features/scene-graph/material.ts`
        in [model-viewer](https://github.com/google/model-viewer), Apache-2.0).
      - Whether sheen reads as paper fibre is untested.

17. **Normals, fibre textures, crease memory.**
    - **Normals.** Flat normals are right for rigid panels and wrong for bent
      ones (finding 1). A bent panel needs a `NORMAL` attribute, with vertices
      duplicated at creases. The repo already allows lighting duplicates that
      still name one material point (`docs/notes/connected-paper-surface.md:14-16`).
    - **Textures.** Normal maps (core `normalTexture`, spec example at `:2407`)
      need `TEXCOORD_0` (`:1735`).
    - **Material coordinates as UVs, derived.** Material coordinates (u, v)
      name the same bit of paper in every state (`Surface.hs:15-19`). Used as
      UVs, one fibre texture, and one "crease memory" texture drawn along the
      crease pattern, would follow the paper through every step. A standalone
      folded file may lack material coordinates (`Surface.hs:15-19`), so it
      would have no UVs.

18. **Animating a folding sequence.** Core glTF animates only node TRS
    (translation, rotation, scale) and morph weights (`Specification.adoc:2622`).
    Interpolation is `LINEAR`, `STEP` or `CUBICSPLINE` (`:2804`). `LINEAR` is
    lerp for translation (`:3566`) and short-path slerp for rotation
    (`:3579`, `:3596`).
    - **(a) One node per face (the approach in #56).**
      - **Flat nodes open the crease, derived.** Take a face turning about a
        hinge through point h. It needs translation T(t) = h − R(t)·h, which
        is not linear in t.
        - Put the hinge at distance d from the node origin, and turn 180°
          between two keys.
        - At t = ½ the true T is (d, −d) but lerp gives (d, 0), so the hinge
          point drifts by d.
        - #56 already expects that a crease "may briefly not close".
      - **Exact alternative, derived.** Nest nodes along the folding spanning
        tree (`spanningWalk`), with each child's origin on its parent crease
        and its local rotation about that crease's axis, which is fixed in the
        parent's frame.
        - A rotation about axis n by φ is the quaternion (cos φ/2, sin φ/2·n).
        - Two such quaternions have dot product cos(Δφ/2), positive when
          |Δφ| < 180°.
        - Slerp between them is then a rotation about n by the linearly
          interpolated angle. The hinge stays closed at every instant.
      - **Two conditions**, both following from that derivation:
        1. Each key must turn each tree crease by less than 180°. A −90° →
           +135° step would slerp the wrong way.
        2. Loop-closing (non-tree) creases still tear between keys unless the
           keys are dense (`fold-angles-are-the-state.md:26-31`).
      - **Viewer support.**
        - Blender imports keyframe animation (`scene_gltf2.rst:39`, `:718`).
        - model-viewer plays named clips (`animation-name`, `autoplay`,
          `availableAnimations` in `packages/modelviewer.dev/data/docs.json`)
          on a three.js peer dependency `^0.183.0` (`package.json:90`).
    - **(b) Skinning, one joint per panel.**
      - **How it works.** Only joint transforms apply; the skinned node's own
        transform is ignored (`:1856`). The per-vertex matrix is a linear
        weighted sum (`:177-178`, `:1904`), with four joints per attribute set
        (`:1958`).
      - **Rigid panels.** With weight 1 it equals (a).
      - **Across a fillet, derived.** Blending the identity with a 180° turn
        about z at weights ½ gives diag(0, 0, 1). The middle of a
        half-cylinder collapses onto its axis.
    - **(c) Morph targets.**
      - **How they work.** Attributes are base plus a weighted sum of deltas
        (`:1697`). That is straight-line vertex interpolation, the #52 trap.
      - **Derived failure.** A unit flap turning 180° about x = 0 at weight ½
        has every point at x = 0: the flap becomes a line.
      - **Where it is acceptable.** Only as a crossfade between densely sampled
        states that have each been checked. Clients should support at least
        eight morphed attributes and may drop the rest (`:1799-1801`). A
        POSITION+NORMAL crossfade of two adjacent keys uses four.
      - **Storage and support.** Accessors are full-count unless sparse
        (`:1762`, `:1371`). Blender imports shape keys (`:39`).
    - **(d) The visible scene through time.**
      - **The problem.** `visiblePaper` clips pieces per state
        (`PaperMesh.hs:79-93`), so the pieces change between keys.
      - **Core glTF.** It can switch pieces only through TRS, for example a
        STEP-keyed scale of 0 or 1 (derived).
      - **Extensions.** `KHR_node_visibility` is absent from both three.js
        GLTFLoader's handlers and Blender's import list.
      - **The complete scene** avoids switching but flickers where layers touch
        (`visible-paper-mesh.md:70-76`).

### D. SVG wireframe of a 3D paper surface

19. **How other tools classify lines.**
    - **Blender Freestyle**
      ([line_set.rst](https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/render/freestyle/view_layer/line_set.rst)):
      - *Silhouette*: normals flip between facing towards and away from the
        camera.
      - *Border*: an edge with one face.
      - *Crease*: a dihedral angle beyond a threshold.
      - *Edge Mark*: manually marked edges.
      - Visibility options are visible, hidden, or a range of *quantitative
        invisibility* (QI), the number of occluding surfaces.
    - **three.js `EdgesGeometry`** draws an edge when adjacent face normals
      differ by more than `thresholdAngle`, default 1° (`src/geometries/EdgesGeometry.js`
      constructor docs).
    - **Origami Simulator** draws per-assignment raster lines (finding 10).
    - **Mesh contours** are prone to topological errors such as gaps in the
      outline (Bénard, Hertzmann & Kass 2014,
      <https://www.labri.fr/perso/pbenard/publications/contours/>). The
      Bénard & Hertzmann tutorial surveys contour extraction and visibility,
      exact and hardware-accelerated (<https://arxiv.org/abs/1810.01175>,
      abstract).

20. **Dihedral thresholds are the wrong classifier for origami (derived).**
    - **Two failures.** A crease at angle 0, unfolded or reopened, has no
      dihedral angle and would vanish. The relaxed double fold bends up to
      2.017° across internal triangle edges (`crease-and-panel-energy.md:71-74`),
      so the 1° default would draw that sheet's triangulation.
    - **The right classifier.** The repository already carries source edge ids
      through refinement (`Surface.hs:10-13`, `:96-106`). That is Freestyle's
      *Edge Mark*.
    - **Precedent.** `examples/puffed-square.fold` assigns its edges 280 `F`
      and 40 `B` (jq). Its lines come from assignment, which is why
      `--hide-flat` leaves only the boundary (`the-puff-is-a-drawing.md:117-127`).

21. **Silhouettes on folded paper (derived).**
    - **Planar panels.** The sign of normal·view can change only between
      panels, so a silhouette lies on a crease or boundary. The crane
      measurement in finding 4 agrees.
    - **Bent panels.** Silhouettes cross panel interiors along edges that
      provenance would otherwise hide. That is #104's case. Its rule, a sign
      change across a shared edge with boundaries always drawn, is Freestyle's
      silhouette plus border definitions, applied per edge of the mesh.

22. **Hidden lines and line weight.**
    - **Visibility.** It is already computed per view by subtraction for convex
      planar faces (`Visible.hs:26-50`; `Projected.hs:1-23`). A bent panel
      refined into triangles is a set of such faces. What still declines is
      intersecting panels, coplanar ties and free edge-on outlines
      (`Projected.hs:17-23`).
    - **Book conventions.** Yoshizawa–Randlett uses solid edges, dashed
      valleys, dash-dot mountains, thin existing creases and dotted hidden
      lines (<https://en.wikipedia.org/wiki/Yoshizawa%E2%80%93Randlett_system>).
    - **Depth and weight.** Freestyle's QI range generalises the x-ray line:
      draw QI = 1 dotted for a chosen flap (#48). For depth, the repo's one
      precedent is a lighter weight for buried sheets (finding 4).

### E. Proposed fidelity ladder, with repository coverage

23. **The ladder.** Animation of *rigid* routes sits low, because it needs no
    new physics and its failure modes are exactly derivable (finding 18a).
    Animated *flexible* routes sit last, because no checked flexible path
    exists (`README.md:311-318`; `directional-contact-distance.md:77-79`).

    | Level | Data a sequence must supply | glTF output | SVG output | Coverage today |
    | --- | --- | --- | --- | --- |
    | **G0** rigid, faceted, zero thickness, static states | Crease pattern; a complete angle list per state (`StudyCase.hs:5-10`) or folded frames; face orders for coplanar overlap; anchor face (`BlintzSequence.hs:5-8`) | Two scenes, flat normals, two sides by winding | Visible/Projected, book notation | **Production** (findings 1, 4); study checked states (5d) |
    | **G1** G0 animated along a checked route | G0 plus an ordered list of checked states, dense enough for loop closure; per-face `Rigid` | Spanning-tree node hierarchy, TRS keys under 180° per crease; STEP visibility switching or the complete scene | Step pages, or one figure per key | States exist (`README.md:48-57`; `Flap.hs:19-24`); **no animation** (#56; grep) |
    | **G2** rounded creases plus thickness offsets | G0 plus physical thickness, display exaggeration, per-crease wrap count from face orders, a vertex rule | Connected fillet strips, offset front/back surfaces, `NORMAL` on fillets | Spine bands in offset or side view (#114, #50) | **Study prototype and counterexample** (5a); thickness as metadata (`Surface.hs:298-304`) |
    | **G3** bent panels with contact, static endpoints | G2 plus crease rest angles and stiffness, panel stiffness, held/grip regions and targets (`WingBending.hs:1-10`), directional layer requirements (`Surface.hs:118-121`), a checked G0 start | Smooth-normal bent panels, provenance kept in extras | Provenance lines, silhouettes (#104), visibility | **Study only** (5b, 5c; `README.md:64-95`); constants illustrative; thickness absent; rendering gap (`roadmap.md:62`) |
    | **G4** animated flexible route | G3 plus time-parameterised controls; a checked mesh per key | Morph crossfade of dense keys, or per-key meshes | Frames | **None** (`README.md:311-318`) |

    Two axes run alongside the ladder:
    - **Appearance.** A0 flat colours on two sides (today); A1 smooth normals
      and tuned roughness; A2 material-coordinate UVs with fibre and crease
      textures; A3 diffuse translucency once loaders support it.
    - **Line drawing.** W0 book notation on planar panels (today); W1
      provenance lines plus silhouettes on bent meshes; W2 QI x-ray and
      cut-away (#48, #49).

### Sources fetched (with licences where they matter)

- **glTF.** Registry README and 2.0 specification source, via `gh api` of
  `KhronosGroup/glTF`; registry.khronos.org returned HTTP 403.
  - `KHR_materials_sheen`, `_transmission`, `_volume` and
    `_diffuse_transmission` READMEs.
- **Viewers.**
  - three.js (MIT): `GLTFLoader.js`, `EdgesGeometry.js`, `MeshPhysicalMaterial.js`.
  - glTF-Blender-IO (Apache-2.0): `docs/blender_docs/scene_gltf2.rst`.
  - model-viewer (Apache-2.0): `package.json`, `docs.json`, `material.ts`.
- **Simulators.**
  - Origami Simulator (MIT): README, `js/model.js`, `js/globals.js`,
    `js/dynamic/dynamicSolver.js`, `index.html`.
  - SWOMPS: README; no licence file.
  - IPC and ipc-toolkit (MIT); Codim-IPC (Apache-2.0).
- **Papers and pages.**
  - Tachi 2011 and Grinspun et al. 2003 PDFs (pages read).
  - Liu & Paulino 2017 (PMC).
  - Filipov et al. 2017 (Semantic Scholar record).
  - Jules et al. 2019 (arXiv abstract).
  - Offset panel technique abstracts (BYU ScholarsArchive).
  - IPC and C-IPC project pages.
  - Blender Freestyle manual source.
  - Bénard/Hertzmann/Kass project page and Bénard & Hertzmann tutorial abstract.
  - Wikipedia's Yoshizawa–Randlett article.

## Implications for the design

1. **PRD 3 must name its fidelity level, and the output must record it.**
   Write it into glTF `extras.senbazuru` and SVG metadata. A G2 fillet on
   crossing folds stretches the paper (5a). If it could be mistaken for a G3
   solve, it would violate the project's rule that schematics say so
   (`the-puff-is-a-drawing.md:87-95`).

2. **Define "realistic" as properties a test can check, not a look.** For
   example:
   - material connectivity counted through extras (finding 2);
   - strip isometry within tolerance (#114, second comment);
   - no interpenetration and no layer reversal;
   - fillet radius derived from thickness and wrap count.

   Paper calibration is open (`README.md:303-304`) and the study's stiffnesses
   are illustrative. A PRD promising paper-accurate shapes would be promising
   something nobody can verify.

3. **What the sequence language should carry, and what it should not.**
   - **Per state:** complete angle lists, or operations that resolve to them;
     face orders where coplanar; the anchor face.
   - **In a separate optional material block:** physical thickness, a *distinct*
     display exaggeration, crease rest angles and stiffnesses. Models 11 and
     12 treat these as material properties, and step geometry should not
     restate them.
   - **Never:** vertex positions as interpolation targets.

   Sequences produced by the DSL always have material coordinates (the
   `Surface V2` type records that they are known), so they get UVs, strain and
   provenance for free. Keep that guarantee.

4. **Derive wrap counts from face orders along each crease, not from layer
   numbers.** Consider letting sequences pin an order explicitly. #114's second
   comment reports that thickness is what makes a roll fold's order unique;
   that is unverified here.

5. **The glTF animation PRD should build nested nodes along the spanning tree,
   with hinge-located origins.**
   - Refuse, or subdivide, keys that turn any crease 180° or more.
   - Check loop-closing creases at sampled midpoints: the gap should be zero
     within tolerance.
   - Keep `materialWeights`.
   - Do not use skinning for fillets. Use morph targets only for dense, checked
     keys.
   - Never list material extensions in `extensionsRequired`.
   - Treat changing visible pieces as a separate decision.
   - Animation is a new file shape. #56 already requires single-frame exports
     to stay byte-identical, which matches the "keep the default output
     unchanged" practice.

6. **Order the work thickness, then contact.** An IPC-style unsigned barrier
   cannot start from a zero-thickness flat stack (finding 13). The study's
   directional barrier keeps diagram-relevant order but forbids physically
   legal paths. A PRD should say which one each level uses, and why.

7. **SVG for 3D surfaces: classify by provenance, then add silhouettes per view.**
   - Draw an edge because it came from a source crease or boundary, never
     because of a dihedral angle.
   - Add silhouettes as a pass that depends on the view.
   - Keep book notation: solid lines on folded forms, x-ray lines rare and
     chosen. QI is the mechanism for x-ray lines.
   - Planar-panel drawings must stay byte-identical.

8. **Materials.** Stay with core metallic-roughness by default. Offer diffuse
   transmission only behind a flag, with core fallback. Never use volume on a
   sheet. Use material coordinates as `TEXCOORD_0` when textures arrive.

9. **External solvers run as out-of-process tools whose frames are read back.**
   This is the #53 route, not vendoring. MIT and Apache-2.0 tools (Origami
   Simulator, IPC, Codim-IPC) can be driven. Code with no stated licence
   (SWOMPS, MERLIN's supplementary material) cannot be copied. GPL references
   remain research-only.

10. **Thick-panel methods (Tachi, offset panel technique) are not a route to
    realistic *paper*.** They cannot reach flat. List them as a possible
    separate material mode, not as a rung of the ladder.

## Open questions

- **What is drawn where fillets meet at a vertex?** The quarter fold's centre
  needs an answer (#114, step 4). Is a labelled non-isometric patch
  acceptable at G2?
- **Can G2 ship as a labelled schematic** for crossing folds, or must it wait
  for a G3 solve that makes the strips isometric?
- **Where do material parameters live** in the sequence language (per
  sequence, per step, per region), and in what units? Is display exaggeration
  a render option rather than sequence data?
- **Hierarchy re-rooting.** Recipes sometimes reorder the anchor face
  (`BlintzSequence.hs:5-8`). How should a TRS hierarchy handle an anchor that
  changes mid-sequence without a visible jump?
- **How dense must animation keys be** for loop-closing creases to stay within
  tolerance? This is measurable with the existing checks, not yet measured.
- **Visible pieces in an animation.** Should animated exports switch them with
  STEP scale, wait for `KHR_node_visibility` support, or use thickness
  offsets (G2) so depth ties disappear physically?
- **Licences.** Is an Apache-2.0 solver acceptable as an optional external
  dependency under the repo's third-party rules, which are written for
  vendored material?
- **Silhouette smoothness.** Should silhouettes on bent meshes come from
  interpolated vertex normals, to avoid mesh-contour topology errors, rather
  than the per-edge sign test #104 specifies?
- **Is #104 still accurate?** Does `examples/puffed-square.fold` now go
  through `Render.Projected` rather than the painter fallback #104 describes?
  If so, its silhouette premise needs rechecking.

## Unverified

- The content of Lang, Tolman, Crampton, Magleby & Howell, "A Review of
  Thickness-Accommodation Techniques in Origami-Inspired Engineering", Appl.
  Mech. Rev. 70(1) 010805 (2018). I confirmed only the citation, from search
  results. The list of techniques (tapered panel, offset panel, membrane and so
  on) and their properties came from search-engine summaries, not a fetched page.
- MERLIN2 (Liu & Paulino): only the paper title, from search results. No
  abstract, code or licence was fetched.
- Filipov et al. 2017 specifics: panel discretisations (N4B5/N5B8), stiffness
  calibration and accuracy against finite elements. Only the abstract was read.
- Details of the Origami Simulator paper beyond its landing page. The 22.6 MB
  PDF was too large to fetch. Solver facts above come from its source code.
- Ratification status of `KHR_node_visibility`. A WebFetch summary listed it
  as ratified; the raw README grep did not cover it. That three.js and Blender
  lack loaders *is* verified.
- Whether model-viewer enables every extension its three.js peer supports. Only
  its `material.ts` references and peer version were seen.
- Support lists are from default branches on 2026-09-14. Released three.js,
  Blender and model-viewer versions may differ.
- Whether sheen, or transmission, looks right for paper. "Transmission reads as
  cellophane" is an inference from its glass/plastic scope, not a test.
- #114's second comment on the roll fold's "3 valid orders" output; not rerun.
- The Lechenault et al. 2014 and Rao et al. 2013 numbers (L\* ≈ 200t, minimum
  radius ≈ 1.25t). They come via `a-crease-is-a-hinge.md` and were not
  re-fetched.
- The ≈45× exaggeration figure. It assumes a 15 cm sheet and 0.1 mm paper, the
  repo note's figure for origami paper.
- The cost of IPC or C-IPC on origami-scale sheets with many touching layers.
  Only the project pages' demonstrations were read; nothing was measured.
- Whether the #104 per-edge rule produces visibly broken outlines at the mesh
  densities senbazuru uses. The Bénard et al. page supports the general risk
  only.
- Freestyle's depth-dependent thickness modifiers were not fetched.
