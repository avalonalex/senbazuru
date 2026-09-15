# C. Output backends, CLI and file formats: where a sequence language and realistic rendering plug in

> **Erratum (from [Z-critic](Z-critic.md), spot check 32).** Finding 27 says
> #95's proposed half turn keeps the model's centre fixed. #95 specifies
> `(x, y, z) ↦ (−x, y, −z)`, a half turn about the page axis at x = 0, so the
> quarter fold (x ∈ [0.5, 1]) moves across the page and `Step` would report a
> translation. [D](D-docs-issues-constraints.md) C5 and
> [gap-step-annotation-channel](gap-step-annotation-channel.md) findings 12–14
> have it right.

Researched 2026-09-14 on branch `docs/prds-sequence-language` (clean tree). Nothing
was built or run except read-only inspection (`jq`, `grep`, `sqlite3 -readonly`,
`gh issue view`, directory listings).

## Summary

SVG renders a `Frame` (a `Surface` is flattened back to one) into a 2D
`Diagram`. glTF takes an `Origami.Surface`, and the steps page takes `[Frame]`.
Nothing consumes a "sequence" or a "move", so a DSL fits every backend unchanged
if it emits an ordinary multi-frame `FoldFile`.

The code imposes four constraints on that output:
- every frame shares one crease graph, or `motionsBetween` refuses;
- frames are already folded, since `--steps` refuses `--fold`;
- coplanar layers carry `faceOrders`;
- `frame_title` is read only by the CLI.

A scheme is a program, not a `Frame`. Its output can obey "becomes a Frame and
stops there", but its parser does not belong in `Import.*`. `Fold.Load` should
not dispatch to an interpreter either: the I/O boundary would then depend on
`Origami.*`, which nothing in `Fold/` or `Import/` imports.

The locked LTS 22.44 snapshot has megaparsec 9.5.0 (BSD-2-Clause) and
parser-combinators 1.3.0 (BSD-3-Clause).

glTF today writes flat-shaded triangles with no normals, one colour per side, no
lines, no animation, and thickness only as metadata. The nearest SVG wireframe
is `--no-fill`, which strokes every crease, buried ones included.

## Findings

### (a) What each backend consumes, and the layering rule

1. **Three renderer input types, one flow.**
   - `Render.CreasePattern.creasePatternFrom :: Theme -> Budget -> Notation -> Basis -> Frame -> Either FoldError Diagram` (`src/Senbazuru/Render/CreasePattern.hs:174-179`).
   - `creasePatternAuto` picks the notation and camera from the frame (`CreasePattern.hs:495-499`).
   - `surfaceDiagram` is literally `creasePatternAuto theme budget view . surfaceFrame` (`CreasePattern.hs:156-157`). It discards everything `Surface` adds: material coordinates, thickness and directional layer requirements, as its own comment says (`CreasePattern.hs:152-155`).
   - `Render.Steps.stepPage` takes `[Frame]` (`src/Senbazuru/Render/Steps.hs:90-100`).
   - `Render.Gltf.renderSurfaceGlb` takes `Surface material` (`src/Senbazuru/Render/Gltf.hs:219`). `renderGlb` is its `Frame` entry point: it traces faces with `withPlanarFaces`, then builds a surface (`Gltf.hs:200-211`).
   - `Render.Svg.renderSvg :: Page -> Diagram -> Text` (`src/Senbazuru/Render/Svg.hs:118`) is the only consumer of `Diagram`.

2. **The layering rule for backends.**
   - New 2D backends must consume `Diagram` and must never traverse `Frame` a second time. The one stated exception is a 3D backend, because `Diagram` is `V2` with no depth (`docs/architecture.md:176-182`; `Gltf.hs:62-70`).
   - `Render.Gltf` must not import `Render.CreasePattern`. The two share only `Origami.Stacking.layerOrderFor` (`architecture.md:180-182`). `Gltf.hs:126-142` confirms it imports only `Diagram`'s `Colour`, the two paper colours from `Diagram.Style`, and `Render.Camera` / `Render.PaperMesh`.
   - `Diagram` must not know FOLD, and `Render.Svg` must not know what a mountain fold is (`architecture.md:149, 154`).
   - The two-unit rule is a hard constraint on anything a sequence page adds (captions, arrow kinds): model-unit coordinates, page-unit widths and sizes (`src/Senbazuru/Diagram.hs:21-47`). `Arrow`, `Label` and `Offset` are the three shapes that are finished by the backend (`Diagram.hs:186-222`).

3. **What "wireframe" means today: stroked creases, not mesh edges.**
   - `Theme.themePaper = Nothing` is the wireframe switch (`src/Senbazuru/Diagram/Style.hs:195-203`). `--no-fill` sets it (`app/Senbazuru/Cli.hs:559-565, 898-900`).
   - With no paper, both notations draw `everyCrease`: every edge in `edges_vertices`, sorted by `creaseOrder`, projected and stroked. Nothing is hidden (`CreasePattern.hs:205, 213, 243-246`).
   - A folded form with paper but no layer order falls back to projected visibility, else to `everyCrease` (`CreasePattern.hs:222-224, 250-254`).
   - So today's SVG "wireframe" draws buried edges at full weight. It is explicitly an escape hatch for files whose layers cannot be stacked (`docs/usage.md:116`).
   - The hidden-edge dotted line is in the notation table and unused (`Style.hs:22, 41-47`). Selective x-ray lines are issue #48, which is open.
   - No silhouette pass exists. Issue #104 proposes one, and its own text says a curved mesh with `--hide-flat` loses its outline. That claim is not verified here; see Unverified.

4. **Feature edges versus triangulation edges.**
   - `Origami.Surface.surfaceFeatures` returns border, mountain, valley, unassigned and cut edges, plus any edge with a nonzero angle. Mesh diagonals never enter that list (`src/Senbazuru/Origami/Surface.hs:272-285`).
   - The study turns a curved triangle mesh into a renderable `Surface` by marking interior mesh edges `J` (join) and boundary edges `B`. It does this in `UncreasedSurface` (`study/fold-material/UncreasedSurface.hs:1-4, 36-41`) and `CraneSpread` (`study/fold-material/CraneSpread.hs:214`).
   - `strokeFor` returns `Nothing` for `Join` (`Style.hs:280-281`), so **triangulation edges already disappear from SVG, and feature edges remain**. That is the right split for a wireframe of a curved model.
   - glTF writes no lines of any kind (`Gltf.hs:52`). `PaperPiece` carries corners and a panel id, not edges (`src/Senbazuru/Render/PaperMesh.hs:47-54`).
   - The study's WebGL viewer draws feature lines itself. `authoredValue` emits `lines` once per owning panel (`study/fold-material/Main.hs:192-217`, see line 213), and the viewer draws them with `gl.LINES` (`study/fold-material/viewer.html:241-244, 286-290`).
   - `docs/tour.md:596-597` says the SVG outlines of those relaxed meshes still retain some buried crease lines, and points readers to the 3D views.

5. **The SVG visibility machinery has limits a realistic wireframe would hit.**
   - `Render.Projected` handles only convex, planar, non-intersecting open panels. It returns `Nothing`, and so falls back, for non-planar, non-convex, intersecting or depth-tied panels (`src/Senbazuru/Render/Projected.hs:17-23, 120-125, 148-154`).
   - It compares every pair of panels (`Projected.hs:70`, `tails` over panels).
   - `docs/architecture.md:402-407` records that corrected (relaxed) meshes are shown in the depth-buffered viewer "because the SVG painter assumes the very layer order those meshes can violate".

### (b) glTF today

6. **Structure.**
   - GLB container with a hand-rolled JSON writer (`Gltf.hs:335-384, 423-474`).
   - `scene: 0`. One node per scene, carrying the mesh and an optional name (`Gltf.hs:359-361`).
   - Scenes: `VisiblePaper` writes two, "Visible paper" and "Complete paper". `CompletePaper` writes only "Complete paper" (`Gltf.hs:147-148, 231-235`).
   - The CLI maps `--all-layers` to `CompletePaper` (`Cli.hs:776`).
   - The node name comes from `frameTitle frame <|> fileTitle f` (`Cli.hs:779`).

7. **Materials.**
   - Exactly two: `"paper"` and `"paper underside"`. Each is `pbrMetallicRoughness` with `baseColorFactor` converted from sRGB to linear, `metallicFactor` 0 and `roughnessFactor` 1 (`Gltf.hs:364, 384`, `linearOf` at `Gltf.hs:322-329`).
   - The colours are the SVG theme's constants, `#faf8f3` and `#e5ded1` (`Style.hs:113-114, 131-132`).
   - No textures, no UVs, no `doubleSided`. Two-sidedness comes from writing each side as a separate index list with reversed winding, one per material, and relying on back-face culling (`Gltf.hs:31-42, 344-346, 380`).
   - The glTF material schema gives `doubleSided` a default of `false`, meaning culling is on (https://raw.githubusercontent.com/KhronosGroup/glTF/main/specification/2.0/schema/material.schema.json).
   - Faces are fanned from their first corner, so concave faces are refused (`GltfConcaveFace`, `Gltf.hs:158-161, 276-284`).

8. **extras and material references.**
   - Root `extras.senbazuru` holds `version: 1`, a FOLD `frame` with packed positions, optional `physicalThickness` and optional `layerRequirements` (`Gltf.hs:236-243`).
   - That frame's `frameExtras` is filtered down to exactly `senbazuru:material_coords`, `senbazuru:source_panels` and `senbazuru:source_edges` (`Gltf.hs:241-242`). **Any other vendor key a sequence language writes, such as a move description, is dropped from the glTF.**
   - Each mesh's `extras.materialWeights` lists weighted original vertex ids per POSITION. Each primitive's `extras.materialFaces` gives one original panel id per triangle (`Gltf.hs:380-382`; layout documented in `docs/notes/visible-paper-mesh.md`).

9. **Thickness.**
   - Metadata only. "Optional physical thickness remains a property; it does not move vertices" (`Gltf.hs:29`).
   - `withPhysicalThickness` says no current renderer interprets it as an offset (`Surface.hs:298-304`).
   - The old display-spacing `--thickness` was removed because it opened gaps at creases (`docs/notes/paper-thickness.md:1-18`).

10. **No normals, so faceted shading.**
    - "No normals are written" (`Gltf.hs:49-50`).
    - The glTF spec requires clients to compute **flat** normals when none are given (https://raw.githubusercontent.com/KhronosGroup/glTF/main/specification/2.0/Specification.adoc). Flat is right for rigid panels. A refined curved surface will show its triangle facets in any glTF viewer.
    - The study viewer instead averages normals **within a panel only**, "smoothing across a crease makes it look rolled" (`viewer.html:218-228`). This is the per-feature-edge normal split a realistic export would need.

11. **No animation (#56).**
    - The header defers it: the per-face transforms exist, but a real sequence is needed (`Gltf.hs:52-55`).
    - Issue #56 (text, not evidence) proposes one node per face with rotation and translation keyframes. Its step 1 says the transforms are "currently discard[ed]". **That is stale**: `Folded` already carries `foldedPlacements :: IM.IntMap Rigid` (`src/Senbazuru/Origami/Folding.hs:283-322`), returned by `foldFrameWith` (`Folding.hs:331`).
    - glTF's channel target paths are `translation`, `rotation`, `scale` and `weights`. Sampler interpolation is `LINEAR` (slerp for rotation), `STEP` or `CUBICSPLINE` (https://raw.githubusercontent.com/KhronosGroup/glTF/main/specification/2.0/schema/animation.channel.target.schema.json, .../animation.sampler.schema.json). Skins with `joints` and `inverseBindMatrices` exist too (.../skin.schema.json).
    - So vertex-level motion of a *bending* surface can only be expressed through morph targets (`weights`) or skinning. Rigid per-face nodes cannot express bending.
    - The Khronos extensions index lists `KHR_animation_pointer` as ratified (https://github.com/KhronosGroup/glTF/blob/main/extensions/README.md).

12. **What is missing for "realistic", by component.**
    - *Curved panels.* The visible scene requires planar panels (`PaperNotPlanar`, `PaperMesh.hs:99-105`). Shared refinement requires convex planar panels (`usage.md:201-203`). A curved sheet must arrive as many planar triangles joined by `J` edges (finding 4), and each triangle then becomes its own coplanarity group (`PaperMesh.hs:106-112`).
    - *Rounded creases.* Exist only as study constructions (`FoldMaterial` rounded variants, `docs/architecture.md:233`), with the material-budget caveat in `docs/notes/two-bends-need-more-than-radii.md`.
    - *Thickness.* Metadata only (finding 9).
    - *PBR paper.* One factor per side. The extensions index lists `KHR_materials_sheen`, `KHR_materials_transmission`, `KHR_materials_volume` and `KHR_materials_specular` as ratified, and `KHR_materials_diffuse_transmission` as a release candidate (extensions README URL above).
    - *Crease lines.* None. Primitive `mode` 1 is `LINES`; the default is 4, `TRIANGLES` (https://raw.githubusercontent.com/KhronosGroup/glTF/main/specification/2.0/schema/mesh.primitive.schema.json).
    - *Animation.* None (finding 11).
    - *Smooth normals split at feature edges.* None (finding 10).

13. **How 3D output is viewed today.** There are two different viewers, and they disagree on colours.
    - `study/gltf/viewer.html` uses the unmodified Three.js `GLTFLoader` with a scene selector. It is validated with the Khronos validator (`study/gltf/README.md:3-5, 14-19, 29-40`).
    - `study/fold-material/viewer.html` is a custom WebGL page that does not read glTF at all. It embeds the models as JSON (`viewer.html:99-101`) with ochre/cream paper colours (`viewer.html:168`), not the theme's `#faf8f3` / `#e5ded1`.
    - It also breaks depth ties with a per-triangle `contactRank`, but only after contact checks pass (`viewer.html:155, 229-234`). That is display-only behaviour a generic glTF viewer cannot reproduce.

### (c) CLI verb structure

14. **Verbs.**
    - `Command = Render | Info | Check | Export | Crease | Fold` (`Cli.hs:78-85`), registered with `hsubparser` (`Cli.hs:218-247`).
    - Every verb enters through `withFoldFile path k = loadFile path >>= ...` (`Cli.hs:691-698, 800-804`). A scheme file passed to any existing verb would be decoded as FOLD, because `decodeFile` treats every unrecognised extension as FOLD (`src/Senbazuru/Fold/Load.hs:102-106`; help text at `Cli.hs:455-461`). It would fail as a JSON `DecodeFailed`, not as "this is a scheme".
    - Shared parsers: `inputArg`, `outputOption`, `frameOption`, `foldSwitch`, `stackingOption`, `budgetOption` (`Cli.hs:385-537`).
    - Output goes three ways: FOLD through `writeDocument` (`Cli.hs:788-794`), GLB bytes (`Cli.hs:781`), SVG text through `emitWith` (`Cli.hs:943-944`). All default to stdout.

15. **Errors.**
    - `die msg = hPutStrLn stderr ("senbazuru: " <> msg) >> exitFailure` (`Cli.hs:1085-1086`). Each call site composes `"cannot <verb> " <> path <> ": " <> explain err` (for example `Cli.hs:780, 941`).
    - The `Explain` class requires a lower-case sentence fragment with no full stop, so it reads after a colon (`src/Senbazuru/Explain.hs`, class `Explain` haddock).
    - `renderStepPage` takes `StepError i err` apart to put the file name between the index and the reason. `Steps.hs:64-78` documents that this means two spellings of one message. A scheme runner will hit the same tension: move index, line and file.

16. **Flag refusals are part of the contract.**
    - `--arrows` is refused with `--offset` (`Cli.hs:830-831`).
    - `--steps` is refused with `--frame`, `--fold` or `--stacking` (`Cli.hs:843-851`).
    - `--fold` is refused with `--arrows` (`Cli.hs:874-875`).
    - Consequence: **`render --steps` can only lay out frames that are already folded** (`Cli.hs:844`).

17. **The CLI is untested by design.**
    - Its header says it "contains no logic worth testing" (`Cli.hs:5-8`).
    - The test suite's `hs-source-dirs` are `test` and `study/fold-material` (`senbazuru.cabal:190-194`), and no test imports `Senbazuru.Cli` (grep over `test/`).
    - `Render.Steps` is in the library because a copy in the test suite hid a bug (`Steps.hs:9-11`).
    - A scheme interpreter must therefore live in the library, with the CLI as plumbing only.

18. **I/O rule.**
    - "Only `Senbazuru.Fold.Load` does I/O, reading and writing alike". `Import.*` takes `Text` and returns values (`architecture.md:155-158`; `Load.hs:5-10`).
    - No library module other than the CLI imports `Fold.Load`. Only the study executable and the CLI do (grep `import Senbazuru.Fold.Load` over `src app study test`).
    - Precedent for a sequence description naming a source file: the study's `cases.json` has a `source` path (`study/fold-material/StudyCase.hs:63-76`). `Main` resolves it with `loadFoldFile` inside the *executable* (`study/fold-material/Main.hs:94, 177-179`). Architecture calls that manifest "not a new library input format" (`architecture.md:412-413`).

### (d) "A new input format becomes a Frame and stops there"

19. **What the rule says and protects.** `Import.*` may know FOLD because producing a `Frame` is its whole job. Nothing downstream may know where a frame came from. What a format cannot say, the frame does not say (`architecture.md:170-175`; AGENTS.md "Conventions").

20. **The existing pattern for a text reader is small and pure.**
    - `parseCp :: Text -> Either ImportError [Segment]` (`src/Senbazuru/Import/Cp.hs:76-79`) and `parseOpx` on tagsoup tags (`src/Senbazuru/Import/Opx.hs:81, 87-88`).
    - They share `foldFileFromSegments`, which invents no metadata (`src/Senbazuru/Import/Segments.hs:258-278`).
    - Errors name lines (`Segments.hs:89-102, 144-165`).
    - `Load` strips a BOM and decodes leniently before parsing (`Load.hs:108-121`).
    - `Fold/` and `Import/` import nothing from `Origami.*` or `Render.*` (grep).

21. **A scheme does not fit that pattern as-is.**
    - Its value is a program: `[Move]` per #60's sketch, `apply :: Move -> Frame -> Either MoveError Frame` (issue #60 text).
    - Running it needs `Fold.Creasing` (`creaseAlong`, `creaseAllAlong :: … -> Frame -> Either FoldError Frame`, `Fold/Creasing.hs:90, 138`), `Origami.ThroughLayers.creaseThroughLayers` (`ThroughLayers.hs:227`), `Origami.Folding` and `Origami.Flap` (`prepareFlap`, `checkFlap`, `flapAt`, `Flap.hs:154-290`).
    - Putting the interpreter in `Import.*`, or behind `Load.decodeFile`, would make the top of the pipeline import the folding stack. That inverts the drawn flow (`architecture.md:12-73`).
    - It may also need a *second* file read (the starting pattern), which the pure `decodeFile :: FilePath -> ByteString -> Either LoadError FoldFile` signature cannot do.
    - The architecture already predicts the right shape. Authoring moves are "a frame in, a frame out", and reach the pipeline "by being a `Frame` that `Fold.Query` cannot tell from one somebody wrote by hand" (`architecture.md:81-86`).
    - So the rule holds for the scheme's **output**. The **parser plus interpreter** needs a stated position: parse (pure, `Text -> Either SchemeError Scheme`) → interpret (library, beside `Fold.Creasing` / `Origami.*`) → `FoldFile`. `Load` only reads bytes.

### (e) Dependencies

22. **Current `build-depends`, per stanza** (`senbazuru.cabal`):
    - `library` (`:152-159`): aeson ≥2.1 <2.3, base ≥4.17 <4.20, bytestring ≥0.11 <0.13, containers ≥0.6 <0.8, filepath ≥1.4 <1.5, tagsoup ≥0.14 <0.15, text ≥2.0 <2.2.
    - `executable senbazuru` (`:167-172`): base, bytestring, optparse-applicative ≥0.17 <0.19, senbazuru, text.
    - `executable senbazuru-material-study` (`:180-188`): base, aeson, bytestring, containers, directory, filepath, senbazuru, text.
    - `test-suite senbazuru-test` (`:315-325`): base, bytestring, directory ≥1.3 <1.4, filepath ≥1.4 <1.5, hspec ≥2.10 <2.12, QuickCheck ≥2.14 <2.16, aeson, containers, senbazuru, text. Also `build-tool-depends: hspec-discover` (`:314`).
    - The library has no parser-combinator dependency today. Cp is hand-split with `T.words` and `Data.Text.Read` (`Cp.hs:82-108`).

23. **megaparsec and parser-combinators are in the locked snapshot.**
    - `stack.yaml.lock` pins `lts/22/44.yaml` with sha256 `238fa745…a1a9`, size 721141.
    - Stack's pantry cache (the download cache Stack keeps at `$STACK_ROOT/pantry/pantry.sqlite3`, where `$STACK_ROOT` defaults to `~/.stack`; table `url_blob`) holds that URL's blob. Extracted, it hashes to the **same sha256 and size**.
    - It lists `megaparsec-9.5.0` (line 7852), `parser-combinators-1.3.0` (8960), `optparse-applicative-0.18.1.0` (8816), `tagsoup-0.14.8` (11576), `aeson-2.1.2.1` (648), `case-insensitive-1.2.1.0` (2964), `scientific-0.3.7.0` (10424), `prettyprinter-1.7.1` (9496), `trifecta-2.1.4` (12260) and `attoparsec-0.14.4` (2160), with `compiler: ghc-9.6.7` (13490).
    - megaparsec 9.5.0 is BSD-2-Clause and depends on base, bytestring, case-insensitive, containers, deepseq, mtl, parser-combinators, scientific, text <2.2 and transformers (https://hackage.haskell.org/package/megaparsec-9.5.0).
    - parser-combinators 1.3.0 is BSD-3-Clause and depends only on base (https://hackage.haskell.org/package/parser-combinators-1.3.0). Both licences are compatible with MIT.
    - The global package database of the Stack-managed GHC 9.6.7 (under `$STACK_ROOT/programs`) ships mtl-2.3.1, transformers-0.6.1.0, deepseq-1.4.8.1, text-2.0.2, containers-0.6.7 and bytestring-0.11.5.4. All are within megaparsec's bounds.
    - **Trap:** `https://www.stackage.org/lts-22.44/package/megaparsec` returned an **LTS 24.59** page (megaparsec 9.7.0). stackage.org package pages are not evidence for a pinned snapshot.

### (f) Multi-frame sequences today

24. **`render --steps`.**
    - `stepPage` drops frames with no vertices. That is how a metadata-only key frame is skipped (`Steps.hs:84-89, 106, 112`).
    - It chooses **one basis from all frames' vertices** (`Steps.hs:107`) but **the notation per frame** (`Steps.hs:122`).
    - It adds arrows from `motionsBetween fr next` on every figure but the last (`Steps.hs:123-129`).
    - It lays figures out at one shared extent (`src/Senbazuru/Diagram/Layout.hs:8-20, 107-112`) and numbers them with `Label`s (`Layout.hs:146-149`).
    - The CLI titles the page with `fileTitle` only (`Cli.hs:866`).
    - **No library module reads `frameTitle` or `frameDescription`.** The only reads are the CLI's page title, GLB node name and `info` listing (`Cli.hs:779, 879, 981`; grep over `src`). Captions are issue #94, open.

25. **How arrows are inferred.**
    - `motionsBetween before after` first requires equal `vertices_coords` length and **identical `edges_vertices` and `faces_vertices`**. It refuses with `FramesDiffer` / `FramesDisagree` otherwise (`src/Senbazuru/Origami/Step.hs:88-96, 118-126`; pinned in `test/Senbazuru/Origami/StepSpec.hs:116, 124`).
    - A face moved if any vertex moved more than `1e-9 × modelSpan` (`Step.hs:137-142`).
    - Moved faces are split into connected groups through shared ring edges (`Step.hs:175-192`).
    - Each group yields a `Motion` from the centre of its corners before to the centre after (`Step.hs:67-80, 144-145`).
    - `motionCreases` lists edges whose recorded `edges_foldAngle` changed. It is empty when frames carry no angles (`Step.hs:74-76, 150-165`).
    - `withArrows` draws one bowed arrow per motion, and nothing when the projected ends coincide (`CreasePattern.hs:585-605`; pinned by `test/Senbazuru/Render/CreasePatternSpec.hs:400-411`).

26. **What the fixture actually does.**
    - `examples/quarter-fold-steps.fold` has three frames titled "Step 1: the flat sheet", "Step 2: folded in half" and "Step 3: folded in half again".
    - All three have 12 identical `edges_vertices` and 4 faces, with assignments `BBBBBBBBMVMM` in **every** frame. Frame 0's angles are all 0; frames 1 and 2 set −180/180 on the moved creases (jq).
    - So the "flat sheet" already carries the crease of step 3. The golden `test/golden/quarter-fold-steps.svg` has 4 dashed strokes (1 valley `6 3.5`, 3 mountain `9 3 1.2 3 1.2 3`), 2 quadratic arrow paths and 3 `<text>` labels.
    - Step 1 therefore draws all four future creases as instructions. Only frame 0 is `creasePattern`, and only `CreasePatternNotation` dashes (`Style.hs:286-289`).
    - `examples/bird-base-sequence.fold` uses the other convention: an empty key frame and 16 titled `foldedForm` frames, each with `faceOrders` (11-60 entries). That is why `--frame 12` is the 12th state (`usage.md:1017-1019`).
    - FOLD has no key for arrows, operations or captions. `frame_inherit` is decoded but not resolved, so every frame repeats the whole graph (`docs/fold-reference.md:187-200, 219-226`; `src/Senbazuru/Fold/Types.hs:151-153`).

27. **What `Step` cannot infer.**
    - *Turn-over.* The centre does not move on the page, so no arrow is drawn (finding 25). #95's proposed half-turn keeps the centre fixed too.
    - *Rotating the model in the page plane.* It moves every vertex, but for a rotation about the model's centre the two ends coincide. That follows from `Step.hs:144-145` and `CreasePattern.hs:600`.
    - *Mountain vs valley arrow kind.* Not classified (#36).
    - *Fold-and-unfold (precrease).* Within one step the positions return, so nothing moved. Across steps the graph changes when a crease is added, so `motionsBetween` refuses (finding 25).
    - *"Top layer only" versus through all layers.* `Step` reports face ids, not layers, and nothing in a frame records intent.
    - *Where on the flap the arrow starts.* It always starts at the centre (`Step.hs:67-70`).
    - *Captions, repeat marks, "turn the model 90°"* and anything else without a geometric signature.
    - A DSL knows all of these by construction. FOLD can carry only `frame_title` / `frame_description` among them.

## Implications for the design

- **Make the DSL's primary output a `FoldFile`, and change no backend in v1.** SVG steps, single-frame SVG and GLB all work on frames today. The acceptance test is already written: reproduce `examples/quarter-fold-steps.fold` and leave `test/golden/quarter-fold-steps.svg` unmoved (#60 and #97 done-when, issue text).
  - Keep default output byte-identical. The goldens `crane-folded.glb`, `quarter-fold-folded.glb`, `simple.glb` and all `*.svg` in `test/golden/` must not move for features they do not exercise.
- **Specify the frame contract the renderers impose, explicitly:**
  - (i) Every frame of a sequence shares one `edges_vertices` / `faces_vertices`. Otherwise `--arrows` fails with `FramesDiffer`. That means creases added by later moves must be **backfilled** into earlier frames at angle 0, which is what the fixture does.
  - (ii) Backfilling makes step 1 draw every future crease dashed (finding 26). The PRD must either accept that (it matches the current golden) or require a later change: `Step` matching frames by material identity, or a notation that draws only the next move's creases.
  - (iii) Frames are folded coordinates, not angle-only patterns, because `--steps` refuses `--fold`.
  - (iv) Coplanar overlaps carry `faceOrders`, as the bird sequence does. Otherwise open coplanar layers are refused by the default GLB (`usage.md:178-184`) and fall back in SVG.
  - (v) Pick one key-frame convention: metadata-only key frame (bird) or key frame is step 1 (quarter fold). `--frame N`, `info` and `stepPage` numbering all depend on it.
  - (vi) Write `frame_title` per step, and `file_classes: ["diagrams"]`. Say in the PRD that nothing renders titles until #94. `soleFrame` drops `diagrams` if frames are removed (`Types.hs:232-252`).
- **Do not rely on vendor keys to carry move intent** (arrow kind, "top layer only") to the renderers. Transforms drop `frameExtras` (AGENTS.md "Preserve at the boundary") and the GLB keeps only three `senbazuru:` keys (`Gltf.hs:241`). If intent must reach the drawing, the PRD needs a typed channel: a `[Step]` value beside `[Frame]` passed to a library function. Don't make `stepPage` re-infer it.
- **Module placement.** Put the grammar in a new library namespace that is neither `Import.*` nor `Fold.Load`, with a pure parser `Text -> Either SchemeError Scheme` whose target type **is the embedded DSL's AST**. That gives one interpreter for (1) and (2). The interpreter sits beside `Fold.Creasing` and above `Origami.*`, and returns `FoldFile`.
  - Add a layering rule to `docs/architecture.md`: "a scheme is a program; it becomes a `Scheme` value at the boundary and a `FoldFile` when run; nothing downstream may know frames came from a scheme".
  - `Fold.Load` gains at most a bytes-to-`Text` reader. The CLI (or a `Load` helper) resolves any source-pattern path with `loadFile`, mirroring `StudyCase`.
- **The CLI verb.** Add a new `Command` constructor and `hsubparser` entry, for example `run FILE -o OUT.fold` (#97's option 1, issue text). Output goes through `writeDocument`. It must not go through `withFoldFile`, which would decode the scheme as FOLD.
  - Errors: one `Explain` instance whose message names the move index **and** source line/column, as a lower-case fragment. Resolve up front the `StepError`-style tension over where the file name goes (`Steps.hs:64-78`).
  - A megaparsec error bundle's multi-line rendering does not fit the one-fragment convention. The PRD should say whether to take position and message apart, as the CLI does for `StepError`.
- **Dependency.** megaparsec 9.5.0 plus parser-combinators 1.3.0 can be added to the **library** stanza, not the executable, because the embedded DSL and parser must be usable without the CLI (`Cli.hs:5-8`). A bound like `>=9.5 && <9.6` matches the cabal style. The cheaper alternative is a hand-written reader in the `Cp.hs` style. The PRD should pick one by grammar size: a line-per-move syntax is `T.words`-sized, a nested one is not.
- **Realistic rendering PRD (3):**
  - Add a *new* export function or mode rather than changing `renderSurfaceGlb`'s default bytes.
  - Normals split at `surfaceFeatures` edges, averaged within panels (the viewer's rule), so refined curves stop looking faceted.
  - Optional crease lines as `mode: 1` primitives built from `surfaceFeatures`, never from triangulation edges.
  - Thickness as graphics-only offset sheets that do not alter `extras.senbazuru.frame` positions, which the metadata contract says are the material positions.
  - Animation: rigid per-face nodes (#56) suit rigid-panel sequences. Bending sequences need morph targets or skins, since glTF has no other way to move vertices (finding 11).
  - Material extensions for paper (sheen, diffuse transmission) are optional polish, and one of them is not ratified.
  - Colours should come from `Diagram.Style` so the two viewers stop disagreeing (finding 13).
- **SVG wireframe PRD:**
  - Define it as feature edges (`surfaceFeatures`, which excludes `J` triangulation edges) plus a view-dependent silhouette (#104), with hidden-line removal.
  - Explicitly **not** the current `--no-fill` output, which strokes buried edges.
  - It must consume `Diagram` (architecture rule). `surfaceDiagram` currently throws away the `Surface` extras a wireframe of a relaxed mesh might need.
  - Measure the pairwise `Render.Projected` cost on dense meshes before promising it (AGENTS.md "Measure, do not reason about, performance").
- **Issue text is stale in places.** #56 says per-face transforms are discarded, but `foldedPlacements` exists. PRDs should cite code, not the issue.

## Open questions

1. Backfill later creases into earlier frames (current fixture behaviour, which draws future creases at step 1), or teach `Step` / `Render.Steps` to accept a crease graph that grows between frames?
2. Does the DSL output one `FoldFile` only, or also a typed `[StepAnnotation]` (arrow kind, caption, turn-over, layer selection) passed to a new `stepPage` variant? If the latter, does that extend `Diagram` (arrow kinds per #36) before or after the DSL?
3. Key-frame convention for DSL output: metadata-only key frame (bird) or first state as key frame (quarter fold)?
4. Where is a scheme's starting sheet defined: built in (for example "unit square"), or a path to a `.fold`/`.cp`? A path makes the verb do two reads, and the pure interpreter cannot.
5. megaparsec in the library stanza, or a hand-written reader? That depends on the syntax #97 settles (line-per-move vs nested blocks).
6. For realistic glTF, should thickness offsets and smoothed normals be a third scene in the same GLB, or a separate export mode? The default must stay byte-identical either way.
7. Should "SVG wireframe of a realistic model" draw from the relaxed mesh through `Render.Projected`, which declines intersecting panels a relaxed mesh can have by tolerance, or from the rigid frames with a schematic outline?
8. Do generic viewers (Blender, three.js, macOS Quick Look) actually render glTF `LINES`, `KHR_materials_sheen` / diffuse transmission and `KHR_animation_pointer`? Needs a measured check with `study/gltf/validate.cjs` and the local viewers.

## Unverified

- Whether the already-built `megaparsec-9.5.0` and `parser-combinators-1.3.0` would be reused by this project's build is unknown. They sit in one of Stack's per-snapshot build directories under `$STACK_ROOT/snapshots`, a GHC 9.6.7 one, and Stack names each such directory by a hash. I could not map that directory's hash to lts-22.44 without running Stack. The snapshot *listing* in finding 23 is verified; the local-build reuse is not.
- `ghc` on this shell's PATH reports 9.10.3 and ghcup has only 9.10.3, while `stack.yaml` sets `system-ghc: true` for 9.6.7. A Stack-managed 9.6.7 exists under `$STACK_ROOT/programs`. How Stack resolves this on this machine was not checked; it affects no claim above.
- The extension statuses in findings 11-12 (sheen, transmission, volume, specular, animation_pointer, mesh_quantization, texture_transform ratified; diffuse_transmission release candidate) came through a summarising fetch of the Khronos extensions README. They were not read line by line.
- The HTML spec at `registry.khronos.org/glTF/specs/2.0/glTF-2.0.html` returned 403. The flat-normals and `scene` statements come from the AsciiDoc source on GitHub via a summarising fetch, which truncated the document. The numeric enums and defaults come from the JSON schema files.
- Issue #104's claim that `render examples/puffed-square.fold --hide-flat` loses the dome's outline was not reproduced; that would need running the renderer.
- The cost of `Render.Projected` and `Render.PaperMesh.visiblePaper` on dense refined meshes (hundreds or thousands of triangles) was not measured. The O(n²) pair loop is read from code, not timed.
- The megaparsec error-bundle rendering format (multi-line with a caret) is from general knowledge of the library, not from a fetched document.
- Doodle's licence is marked "not checked" in `docs/related-projects.md:38`. I did not check it either.
- Whether glTF skins or morph targets can represent paper bending without visible stretching in practice is a design hypothesis, not a verified result.
