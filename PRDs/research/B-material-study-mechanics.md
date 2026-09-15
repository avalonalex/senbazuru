# B. Material study mechanics: what exists, and what "settle this state as real paper" would need

Researcher slice B. Read-only survey of `study/fold-material/*` mechanics, the
notes they cite, and issues #114, #195, #106, #64, #208. Nothing was built or
run; every number below is one the repository recorded, not one re-measured.
Paths are relative to the repository root.

## Summary

The study has a working **static, zero-thickness, held-boundary** solver:
Gauss-Newton on material edge lengths, angular springs at creases and inside
panels, penalty contact along one fixed model axis, exact grips, and a sparse
factor. It turns a rigid `Folded` crane into a bent wing that passes
independent length, crease-angle and whole-sheet contact checks, in seconds to
about a minute. It fails as soon as more body paper is released (unconverged
after ~9 CPU minutes, 49 crossing triangle pairs). Exact (nonnegative) contact
exists only for a two-panel fixture. Rounded creases are a prescribed formula
on a unit square; the 3:1 radius packing rule was shown to stretch paper;
thickness is stored metadata that nothing interprets. Stiffnesses are
illustrative and results change 2-4% (occasionally qualitatively) under
refinement.

A crucial point for the PRDs: a checked rigid state is **already an
equilibrium** of this model when rest angles equal its fold angles, so
"settle" alone produces nothing new. Realism has to come from an explicit
difference: holds released, a grip moved, or rest angles that differ from the
achieved ones. The smallest general entry point is feasible; hold selection,
contact order for non-flat states, and failure policy are not yet general.

## Findings

### Capability table (question a)

**1. Mechanics capabilities, measured maturity and cost.** "General" means it
accepts any `MaterialMesh`/`Surface V2`; "fixture" means hard-coded geometry,
ids or owners.

| Capability (entry point) | Inputs | Outputs | General vs fixture | What the measurements say | Recorded cost |
| --- | --- | --- | --- | --- | --- |
| Length restoration `FoldRelaxation.relaxLengths` (FoldRelaxation.hs:219-220) | `Settings`, `MaterialMesh` | `Relaxation` (checkpoints, `converged`) | General | Lengths alone leave neighbours free to rotate and produced a 2.9e-4 layer crossing (restoring-material-lengths.md:19-25) | not recorded |
| Packet contact `relaxPacket` + `FoldContact` (FoldRelaxation.hs:224-225; FoldContact.hs:143-148) | `FoldCase` (`Single`/`Double`) | as above | **Fixture**: layer order hard-coded from `u`,`v` of the unit square | Double fold 2,048 triangles reached 0.000852% edge error at iteration 69 with no order violations (restoring-material-lengths.md:87-97) | not recorded |
| Crease and panel springs `FoldBending.buildSurfaceHinges` / `buildSelectedSurfaceHinges` / `buildPanelHinges` (FoldBending.hs:146-191) | `Bending{creaseStiffness,panelStiffness}`, refinement level, `Surface V2`, `Map EdgeId Double` rest angles | `RefinedSurface`, `[Hinge]` | General; `buildHinges` (121-136) is fixture (`u = 0.5` test) | Stiffer panels bend less but miss crease targets more: at B=5, creases reach 179.30-179.71° for a 170° target (crease-and-panel-energy.md:71-78) | not recorded |
| Staged elastic solve `relaxBending` / `relaxHinges` (FoldRelaxation.hs:227-242) | `Settings`, `[Hinge]`, mesh | `Relaxation` + `EquilibriumCheck` | `relaxHinges` general, no contact force; `relaxBending` uses packet contact | Penalty stages 1e2..1e8, contact weight 100x, damping 1e-3, full-step movement <= 1e-7 required (FoldRelaxation.hs:491, 584-586, 645) | - |
| Exact grips `relaxPinnedHinges` (FoldRelaxation.hs:244-251) | `IntMap V3` pins keyed by **refined mesh vertex id** | `Relaxation` | General | Held wing at 8/16/24 divisions all converge; 16->24 changes positions 0.000418, energy 1.7% (held-wing-bending.md:30-42); known strip recovered within 1.3e-7 (44-50) | - |
| Held contact `relaxPinnedContact` + `SurfaceContact.prepareContact` + `SparseSolve` factor (FoldRelaxation.hs:253-261, 609) | pins, hinges, `OrderedContact` (clearance, direction, lower/upper `FaceId` pairs, owner per triangle) | `Relaxation` | General in type; **one fixed direction** and **supplied orders** | Two layers 8/16/24 divisions converge (coupled-touching-layer-solve.md:47-59). Crane wing with body held passes at 392 and 1,192 triangles (spreading-connected-wing.md:35-46). Releasing four body panels: unconverged after 118 iterations, edge error 3.75e-5, angle error 0.0187 rad, 49 crossing pairs (body-angle-preferences.md:73-80; wing-root-holds.md:73-79) | 0.83/6.75/35.71 CPU s (two layers); 0.47/5.76/64.30 s (crane wing); ~9 CPU min each failed body trial (body-angle-preferences.md:80); 549 and 468 s internal diagnostics (internal-crease-diagnostic.md:105-106) |
| Audit and continuation `diagnosePinnedContact` / `continuePinnedContact` (FoldRelaxation.hs:263-278) | same | + `TrialDiagnostics` | General | 80 more final-stage iterations: edge error 3.75e-5 -> 2.07e-5 but angle error 0.0187 -> 0.0194; still invalid (internal-crease-diagnostic.md:40-46) | +452 CPU s |
| Declared / discovered panel order `relaxSurfaceContact`, `relaxDiscoveredContact` (FoldRelaxation.hs:280-289; ContactDiscovery.hs:1-24) | orders, or a **separated reference pose** | `Relaxation` | General, but discovery refuses any pair not ordered in the reference (ContactDiscovery.hs:208-216) | Small controls only | - |
| Local triangle contact and growing history `relaxLocalContact`, `relaxLocalHistory` (FoldRelaxation.hs:291-306; LocalContactDiscovery.hs:1-32) | `LocalReference` (clearance, search distance, axis) | `Relaxation`, learned reference | General; history only from accepted steps | Small curl fixtures | - |
| Path-checked corrections `relaxSweptLocalHistory` + `CorrectionSweep` (FoldRelaxation.hs:408-412; CorrectionSweep.hs:1-21) | + `CorrectionSettings` (default depth 16, budget 1024; CorrectionSweep.hs:58-59) | `SweptRelaxation` with accepted paths | General, exact rational Bernstein bounds | Closing strip stalls at 1.13% edge error because the penalty jumps discontinuously when shadows first overlap (rejected-bending-trials.md:3-5, 29-40) | not recorded |
| Distance barrier `relaxBarrierLocalHistory` + `DirectionalDistance` (FoldRelaxation.hs:414-417; SurfaceContact.hs:203-238) | + activation distance `h` | as above | General for disjoint triangle pairs | Same closing strip settles in 99 corrections at 1.18e-8; also at h = 0.0005 and 0.002 (directional-contact-distance.md:52-61) | not recorded |
| Exact nonnegative contact `ContactQuadratic` + `CreaseInequality` (ContactQuadratic.hs:1-16; CreaseInequality.hs:96-120) | material rows, linear gap inequalities | step + `QuadraticReport` | **Fixture**: dense working set "deliberately limited to the small fixture" (ContactQuadratic.hs:16); whole lower panel must be held (CreaseInequality.hs:102) | 32/64 triangles: exact minimum gap 0 where the penalty leaves -5.9e-11/-8.4e-11 (nonnegative-crease-contact.md:69-77) | recorded in gallery JSON, not in note |
| Both panels moving `CreasePairContact` + `CoupledCrease` / `UnequalCrease` | owners must be `FaceId 0`/`1` (CreasePairContact.hs:62), facing preserved (76), all shared crease vertices held (CoupledCrease.hs:75), repair only along z | `InequalityResult` | **Fixture** | Symmetric: gap 0, edge error 7.39e-7/3.22e-6 (coupled-crease-contact.md:63-71). Unequal preference: max gap 7.271e-7 at 32 triangles becomes 0.007009 at 64 (unequal-crease-controls.md:56-61, 87-93) | - |
| Exact prescribed references `ClosedCrease`, `FoldMaterial` rounded bends | subdivision / `FoldCase` | meshes | **Fixture**, "not equilibria or folding paths" (ClosedCrease.hs:12; FoldMaterial.hs:18-19) | Rounded double fold stretches 200% in the upper band, +4.71% area (two-bends-need-more-than-radii.md:53-60) | - |
| Measures `principalStrains`, `maxLengthError` (FoldRelaxation.hs:189-217); `meshEdges`, `edgeStrains`, `componentCount` (FoldMaterial.hs:179-217) | mesh | numbers | General (but live in a fixture module) | - | - |
| Surface export adapters `UncreasedSurface`, `WingLayers.layersSurface`, `ClosedCrease.closedSurface`, `CraneSpread.spreadSurface` | solved mesh + ids | `Surface V2` (triangle faces, J joins, source metadata) | Four near-copies; `spreadSurface` is the general one (CraneSpread.hs:185-232); `UncreasedSurface` is one panel only (UncreasedSurface.hs:7-10) | Feeds `renderSurfaceGlb` (CraneSpreadGallery.hs:104) | - |
| Acceptance predicates `spreadAccepted`, `rootAccepted`, `bodyAccepted` (CraneSpread.hs:179-183; CraneRoot.hs:126-130; CraneBody.hs:101-106) | fixture, `Relaxation`, mesh | `Bool` | Fixture-bound, general pattern | converged and edge error <= 1e-5 and held error == 0 and crease error < 1e-5 and `contactPassed` | - |

**2. CI already pays for these solves.** The test suite compiles
`study/fold-material` (senbazuru.cabal:190-193) and runs short crane solves
(e.g. `Settings 20 1e-5` at refinement 3, test/CraneSpreadSpec.hs:27). #208
records a 10m48s `stack test` step, with the `CraneRoot` group ~164.87 s and
`CraneSpread` ~97.48 s (approximate wall times, different runners).

### The implicit material API (question b)

**3. What a solve needs from its caller.** Reconstructed from the one
end-to-end path that starts at a rigid fold, `CraneSpread.craneSpreadWith`
(CraneSpread.hs:80-115) and `solveSpread` (136-139):

1. **A `Surface V2`**, i.e. known original-sheet coordinates. Only
   `surfaceFromFolded` guarantees them, and it requires the pattern to lie at
   z = 0 (Surface.hs:201-211). A standalone folded `.fold` gives
   `Surface (Maybe V2)` unless it carries `senbazuru:material_coords`
   (Surface.hs:14-19).
2. **A refinement.** `refineSurfaceWithEdges` or
   `refineSelectedSurfaceWithEdges`, level 0-5, every panel planar and convex
   (fan triangulation), no joined cuts (Surface.hs:335-345 and the
   `planarConvex` check that follows). Source edge ids survive as segments.
3. **Rest angles for every active interior crease**, radians, in the **cut
   pattern's** edge numbering, sign matching mountain/valley; the current
   `edges_foldAngle` is deliberately never used as a default
   (FoldBending.hs:138-145, 177-182). `CraneSpread` supplies ±π for existing
   folds and converts the reference state's degrees for the new hinge
   (CraneSpread.hs:89-94).
4. **Stiffness** `Bending 1 0.2` in every crane/wing fixture (e.g.
   CraneSpread.hs:98), explicitly illustrative (crease-and-panel-energy.md:26-35).
5. **Holds**: an `IntMap V3` keyed by refined mesh vertex id, installed before
   the first measurement (FoldRelaxation.hs:244-247). Every fixture chooses
   them by coordinate tests on its own geometry: body = vertices of unselected
   panels, root/grip = y-fraction bands (CraneSpread.hs:101-107).
6. **Target geometry for moved grips**: a prescribed curve (`bentPoint`,
   CraneSpread.hs:117-134). The "load" is a displacement, not a force.
7. **Contact**: `prepareContact clearance direction pairs owners mesh`
   (SurfaceContact.hs:131-144), with clearance 0, direction `V3 0 0 1`, owners
   = `refinedPanels`, and pairs converted from the flat state's `faceOrders`
   by the sign of each reference face normal (CraneSpread.hs:108-114), then
   transitively closed **before** dropping pairs with no free vertex
   (CraneSpread.hs:141-148).
8. **`Settings`**: iteration limit **per stage** (four stages) and length
   tolerance (FoldRelaxation.hs:113-121, 491). Everything else is a hidden
   constant: contact weight, damping, CG limit 3000 and floor 1e-6, movement
   1e-7, 30 halvings, `contactTolerance` 1e-7 (FoldRelaxation.hs:584-611, 643;
   FoldContact.hs:43-44).

**4. What it returns.** `Either RelaxError Relaxation`: sparse checkpoints (at
iterations 0,1,2,5,10,20,50 and the end; FoldRelaxation.hs:567), `converged`
(from the final stage only), and `EquilibriumCheck` (linear report, full
proposed movement, whether factored; 176-184). Non-convergence is a `Right`,
not a `Left`. Validity is decided **afterwards** by the caller: independent
`Origami.Contact.checkTriangleContact` (Contact.hs:98), angle errors, held
error, then an adapter to `Surface V2` for the renderers.

**5. Newcomer traps in this API** (each earned in a note):

- A rest angle is a preference; an angle cap is an acceptance gate. Removing
  the gate cannot move a vertex (body-angle-preferences.md, first section).
- Holding a crease *line* fixes its position, not the orientation of the
  paper beside it (unequal-crease-controls.md:13-17).
- Touching layers have opposite material normals, so equal geometric turns
  carry opposite signed angles (CraneRoot.hs:80-82).
- Near ±180° `angleError` picks the branch nearest the rest angle; it does
  not record motion through 180° (FoldBending.hs:11-16).
- Solver iterates are not a folding motion and may stretch or cross paper
  (FoldRelaxation.hs:9; CraneSpread.hs:11-12).
- Coincident is not shared: only real crease vertices are shared ids
  (WingLayers.hs:1-4).
- `hingesWith` refuses material triangles that are not counterclockwise
  (FoldBending.hs:202-206). `Folding` re-winds every face counterclockwise as
  it lay in the pattern (Folding.hs:244-252), so the `Folded` path satisfies
  this; a frame read from a file does not get that guarantee.

**6. A rigid state is already a settled state.** The rigid 30° crane control
solves to edge error 1.39e-11 and panel energy 1.44e-27
(spreading-connected-wing.md:37). With holds at rigid positions and rest
angles equal to achieved angles, nothing moves. Visible bending appeared only
when a grip was turned 20° further. The PRDs cannot promise that "settle"
makes an unaltered rigid step look more realistic.

### Realism (question c)

**7. Rounded creases are research, and the 3:1 rule is known to be
insufficient.** The packing argument says a fold wrapping n layers has radius
about n·t/2, giving the quarter fold's outer crease three times the inner
radius (a-crease-is-a-hinge.md:83-106; #114 body). The study built exactly
that: lower radius r, upper r + 2r = 3r, sharing one material band. The upper
band is extended 200% and the sheet gains 4.71% area; refinement does not fix
it (two-bends-need-more-than-radii.md:47-68). The roadmap records that a 3:1
ratio "can still stretch the paper" (roadmap.md:161-162). `FoldMaterial`'s
radius is a fixed 0.015 "visible demonstration scale" (FoldMaterial.hs:61-64)
on a unit square. No module in `src` produces a crease radius. Current solved
"roundness" is panel bending beside a sharp hinge, not a fillet.

**8. Thickness is metadata only.** `Surface` stores `Maybe Double`;
`withPhysicalThickness` states no renderer or contact check interprets it
(Surface.hs:21-24, 297-304). glTF copies it into `extras` (Gltf.hs:243). Every
distance in the contact code disclaims being thickness: clearance
(SurfaceContact.hs:19-22), search distance (LocalContactDiscovery.hs:17-19),
barrier activation (SurfaceContact.hs:204), repairs (CoupledCrease.hs:10-11).
Uniform positive clearance cannot be added naively: it would contradict a
shared crease (two-held-paper-layers.md:21-23; SurfaceContact.hs:19-21 uses 0
for joined panels). #114's comment notes a roll fold has three valid
zero-thickness stackings and thickness is what picks the real one. The old
display-spacing option was removed on purpose (paper-thickness.md:3-17).

**9. Bending energy is a plausible discrete model, uncalibrated and
mesh-dependent.** E = k(θ-θ₀)²/2; crease weight κ·l, panel weight B·2l²/(sum
of twice triangle areas) (FoldBending.hs:18-23, 218). The note says this is not
Filipov et al.'s calibrated panel law (crease-and-panel-energy.md:31-35).
Liu and Paulino (fetched, https://pmc.ncbi.nlm.nih.gov/articles/PMC5666233/)
also expose separate fold and panel stiffness parameters, with their ratio
controlling how rigid the sheet behaves, and note the triangulation diagonal
choice matters. Our panels are fan-triangulated from the first corner
(Surface.hs `fan`), a different choice. Measured refinement effects: 1.7-3.95%
energy (held-wing-bending.md:40-41; spreading-connected-wing.md:47-48), 0.83°
root angle (wing-root-holds.md:44-47), and a qualitative change from touching
to 0.007 separation (unequal-crease-controls.md:87-93).

**10. The rest angle is where realism would come from, and that zone is where
the solver fails.** Real creases spring back to a nonzero rest angle; the note
reports Mylar settling 30-40° open (a-crease-is-a-hinge.md:28-33). The study's
170° packet default (FoldBending.hs:77-78) produced achieved 173.8-177.2° on
the double fold (crease-and-panel-energy.md:71-74). On the crane, a 170°
preference left the selected folds at essentially 180° inside a failed solve
(body-angle-preferences.md:73-85).

**11. Contact barrier versus penalty.** The penalty used by every crane solve
leaves negative gaps at equilibrium (a quadratic cost has zero slope at zero
penetration); even a perfectly touching start ends at -5.9e-11
(contact-correction-at-a-crease.md:79-86). The directional barrier fixes the
discontinuity that stalls path-checked solves (directional-contact-distance.md:1-9,
52-61) but is wired only into the local-history mode, not into
`relaxPinnedContact`. Exact nonnegative contact is fixture-limited (finding 1).
IPC (fetched, https://ipc-sim.github.io/) claims intersection-free
trajectories for its full method; the repo note says it borrows only the
scalar barrier and is "not an implementation of that paper's full method"
(directional-contact-distance.md:44-48).

**12. Readiness for an arbitrary DSL-authored model.**

- *Ready (in `src`)*: material identity through refinement, `Surface V2`
  export to both renderers (`renderSurfaceGlb`, Gltf.hs:219;
  `surfaceDiagram`, CreasePattern.hs:156-157), independent static contact
  checks (`Origami.Contact`, tolerance 1e-7, Contact.hs:83-84).
- *Demonstrated but fixture-driven*: held bending of a small free region with
  most of a nearly flat model held, crease springs at ±π, penalty panel-order
  contact along z. This is the crane wing.
- *Research*: releasing large regions (body), general 3D contact direction,
  exact contact at scale, rounded crease radii, thickness as geometry,
  calibrated stiffness, unheld equilibrium (wing-root-holds.md:98-100), pocket
  opening (#106), and any certificate of motion between states.
- *SVG wireframe*: J edges are not drawn as creases (held-wing-bending.md:55-58),
  but the SVG painter assumes layer order and would hide violations, which is
  why unfinished solves get OBJ/FOLD and a depth viewer, never SVG
  (restoring-material-lengths.md:114-118).

### Risks (question d)

**13. Performance.** A short profile (8 iterations) spent ~68% in contact-row
evaluation and ~31% in sparse factorisation, with 281 GB cumulative
allocation. Contact derivatives are computed even when the line search needs
only energies (internal-crease-diagnostic.md:90-104; #208). `SparseSolve` is
"not a bounded-memory solver for arbitrary meshes" (SparseSolve.hs:15-18;
coupled-touching-layer-solve.md:76-77). From reading the code (not measured):
`prepareContact` expands each ordered panel pair to all triangle pairs
(SurfaceContact.hs:141), `localOverlapCandidates` scans all i<j pairs (262-268),
and `CorrectionSweep` checks all triangle pairs in rationals
(CorrectionSweep.hs:132). Cost grows at least quadratically in triangles,
multiplied by steps in a sequence. All recorded timings are single runs on one
machine; the notes themselves disclaim them as guarantees
(coupled-touching-layer-solve.md:57-59).

**14. Non-convergence has several distinct forms.** Budget exhausted while
still improving (internal-crease-diagnostic.md:40-46); blocked line search
(rejected-bending-trials.md:52-58); incompatible holds that a successful
linear solve cannot rescue (coupled-touching-layer-solve.md:71-75;
spreading-connected-wing.md:64-69); and converged-but-invalid, e.g.
contact-off endpoints that converge while crossing (unequal-crease-controls.md:66-70).
"Converged" is necessary, not sufficient.

**15. Tolerance-sized wrongness.** A real crossing of -6.21e-9 passes the
1e-7 checker (near-closed-crease.md:42-46). GLB packs positions at 1e-6 of the
model span, so it cannot show these residuals (visible-paper-mesh.md:17-28;
contact-correction-at-a-crease.md:88-92). Rendering can fail independently of
physical acceptance: an accepted fine crane-root mesh is refused by the
stable-view export (`ImpossibleStacking`, #206) while the complete scene works.

**16. The study's own failure policy.** Failed solves are published only as
labelled diagnostics; only accepted endpoints enter 3D selectors; positions
are never snapped and grips never silently moved to manufacture success
(spreading-connected-wing.md:64-69; body-angle-preferences.md:63-65;
wing-root-holds.md:81-85; WingLayers.hs:99-101).

### Graduation (question e)

**17. Layering is already respected.** No `src` or `app` module imports a
study module (grep; architecture.md:401-405 says the same). The mechanics
modules import only `Explain`, `Geometry.*`, `Fold.Types/Query`,
`Origami.Surface/Contact/HingeSweep` (import headers of FoldRelaxation.hs:94-111,
FoldBending.hs:43-55, SurfaceContact.hs:53-64). None mentions `Render` or
`Diagram`, so they would satisfy the `Origami.*` rule (architecture.md:150-153).

**18. But the general core is entangled with fixtures.** Study-internal
imports (grep of import lines):

```
FoldContact    <- FoldMaterial            (fixture formulas)
FoldBending    <- FoldMaterial
SurfaceContact <- DirectionalDistance FoldContact   (only for ContactRow)
FoldRelaxation <- ContactDiscovery CorrectionSweep FoldBending FoldContact
                  FoldMaterial LocalContactDiscovery SparseSolve SurfaceContact
SparseSolve, DirectionalDistance, CorrectionSweep, CreasePairContact <- (nothing)
```

`FoldRelaxation`'s `ContactMode` includes `PacketContact FoldCase`
(FoldRelaxation.hs:297, 470-472), so the solver cannot move without dragging
the unit-square packet along. Generic measures (`meshEdges`, `edgeStrains`,
`componentCount`) live in the fixture module `FoldMaterial`.

**19. Error types would need work.** Several study errors are `newtype ... Text`
built by `explain`ing a lower error (`SpreadError`, CraneSpread.hs:70, 253-254;
`InequalityError`, CreaseInequality.hs:46). AGENTS.md:160-162 requires error
types that point at the offending element; a Text wrapper loses that
structure. `RelaxError`, `BendingError` and `ContactError` are already
structured.

## Implications for the design

**PRD (3) must not describe "settle" as a pure function of the rigid state.**
Per finding 6 it would be a no-op. Require the step to state what differs from
rigid: released regions, moved grips, or rest angles that are not the achieved
fold angles. Say which is default, and say plainly that a default springback
rest angle is not yet supported on anything bigger than a two-crease packet.

**Proposed smallest general signature** (a sketch for the PRD; names
illustrative). It is shaped by what the crane path already consumes, with
mesh-id details hidden because a DSL author cannot know refined vertex ids:

```haskell
data SettleSpec = SettleSpec
  { settleRefinement :: Refinement               -- Uniform Int | Selected Int (Set FaceId)
  , settleStiffness  :: Bending                    -- illustrative until calibrated
  , settleRest       :: RestAngles                -- AchievedAngles | Explicit (Map EdgeId Double)
  , settleHolds      :: [Hold]                    -- HoldPanels (Set FaceId) | HoldMaterialRegion ... | Grip ...
  , settleContact    :: ContactSpec               -- FromFaceOrders V3 | Declared V3 [(FaceId, FaceId)] | NoContact
  , settleBudget     :: Settings
  }

settle :: SettleSpec -> Surface V2 -> Either SettleError Settled

data Settled = Settled
  { settledSurface :: Surface V2                  -- triangle faces, J joins, source panel/edge ids, orders
  , settledReport  :: SettleReport                -- converged, EquilibriumCheck, max strain, crease errors,
  , settledVerdict :: Verdict                     --   held error, ContactCheck, energies
  }
data Verdict = Accepted | Diagnostic [Reason]
```

Why this shape: holds in panel ids or material coordinates survive refinement
(finding 3.5); `FromFaceOrders` encodes the transitive-closure-before-filter
rule once (CraneSpread.hs:141-148) instead of per fixture; the verdict makes
"converged but invalid" unrepresentable as success (finding 14); returning a
`Surface V2` means both renderers work unchanged (finding 12).

**Not yet general, and the PRD should say so rather than hide it:**

- Contact direction: one fixed axis, and a pair where both triangles stand
  parallel to it is an error (SurfaceContact.hs:190-191). A step with a flap
  raised to 90° is not supported by the crane solver's contact mode.
- Contact order source: `faceOrders` exist for coplanar flat states;
  otherwise orders must come from a separated reference pose
  (ContactDiscovery.hs:125-134).
- Hold selection: no rule exists; every fixture hand-picks. The DSL needs a
  primitive for it (hold/grip), or the PRD must defer settle.
- Exact contact: only the two-panel fixture. The general path is penalty,
  with negative residuals.
- Panels must be convex for refinement (Surface.hs `planarConvex`); the
  roadmap expects non-convex faces in real files (roadmap.md:151-155).

**Failure policy for renderers.** Follow the study's existing discipline
(finding 16). Recommended:

1. The library returns the verdict; it never substitutes rigid geometry
   itself.
2. When the user explicitly asks for a material render, the CLI refuses on
   `Diagnostic` (errors are values) and names the reasons. An opt-in
   fallback renders the checked rigid state, and records in the output (glTF
   `extras`, SVG caption) that material settling failed.
3. A diagnostic export of the unaccepted mesh is a separate, labelled flag.
   It goes to FOLD/GLB complete scene, never through the SVG painter
   (finding 12).
4. Physical acceptance and render success are separate outcomes (#206).

**Sequencing across steps.** A settled mesh cannot be carried to the next
step by vertex id. Creasing re-cuts and renumbers, and transforms are against
the cut pattern (AGENTS.md "A fold's transforms are against the cut pattern").
Either settle each step independently from its rigid state (simplest,
consistent with "static endpoints") or specify a material-coordinate mapping.
The first is the only one the study supports.

**Graduation order** (each step is a self-contained PR, nothing research-grade
first):

1. Split generic pieces out of fixtures: `ContactRow` and generic mesh
   measures out of `FoldContact`/`FoldMaterial`; delete `PacketContact` from
   the solver's `ContactMode` (finding 18).
2. `SparseSolve` and `DirectionalDistance` (no study dependencies). Decide
   placement: they "know no paper" (ContactQuadratic.hs:4, SparseSolve.hs:1-14),
   so `Origami.*` may be the wrong home; `Geometry` must depend on nothing
   (architecture.md layering rules), which `SparseSolve` satisfies apart from
   `Geometry.V3`.
3. Surface-based `FoldBending` (drop `buildHinges`, `PacketRestAngles`).
4. `SurfaceContact` panel-order preparation and penalty rows (+ barrier rows).
5. `relaxPinnedHinges` / `relaxPinnedContact` with `fixedPolicy` and the
   bounded diagnostics; structured errors (finding 19).
6. One export adapter generalised from `spreadSurface`, replacing the four
   copies; one acceptance report generalised from `spreadAccepted`.
7. Only then `settle` itself.

Stay in `study/`: `ContactQuadratic`, `CreasePairContact`, `CoupledCrease`,
`UnequalCrease`, `CreaseInequality` (fixture-limited); `ContactDiscovery`,
`LocalContactDiscovery`, `CorrectionSweep` modes (correct but quadratic and
not used by the crane path); `ClosedCrease`, `FoldMaterial` rounded bends;
all `Crane*`, `Wing*` recipes and galleries.

**Performance gate.** Before any of this reaches a CLI default, #208's
value-only line-search evaluation should land with equal energies and
unchanged accepted/rejected controls. PRD (3) should state a triangle budget,
and whether settle is opt-in per step.

## Open questions

1. What drives realism by default: released holds, springback rest angles, or
   thickness? Finding 6 says one must be chosen; finding 10 says the obvious
   one (rest angle < 180°) is where the crane solve fails.
2. How does a DSL step name holds and grips so they survive refinement and
   re-cutting? Material points, panel ids, "the stationary side of this fold"?
3. Which contact direction and orders apply to a non-flat step (e.g. a flap
   at 90°)? Is discovery from the previous rigid pose acceptable, given it
   refuses unknown pairs?
4. Can thickness become geometry without contradicting shared creases? Per-pair
   clearance for unjoined panels exists (SurfaceContact.hs:19-21), but no
   crease radius model does.
5. Should a settle failure at step k block steps after k, or only mark that
   step's render?
6. Is `SparseSolve` paper knowledge (`Origami.*`) or numerics (a new layer
   that the architecture doc does not yet name)?
7. How should an unheld (free-floating) settle fix rigid-body motion? Only
   damping does today (FoldRelaxation.hs:579-584), and the sparse factor is
   used only when pins are non-empty (609). No unheld crane solve is recorded.
8. What CPU budget per step is acceptable for the CLI, given 5-64 s for the
   accepted crane wing and ~9 min for failed body trials?

## Unverified

- **Lechenault, Thiria, Adda-Bedia (2014).** Fetched
  https://arxiv.org/abs/1404.1243: the abstract supports the hinge model and
  a characteristic length from bending versus hinge stiffness. It did **not**
  state the "about 200 thicknesses" scaling or the 30-40° Mylar rest angle.
  Those come only from a-crease-is-a-hinge.md:28-41.
- **Rao et al.** minimum radius ~1.25 thicknesses, **Benusiglio et al.**
  logarithmic opening, **Kodak Preps** creep formula, **Filipov et al.**
  bar-and-hinge framework: cited in repo notes, not fetched.
- **IPC barrier equation and code licence.** https://ipc-sim.github.io/ was
  fetched but showed neither the barrier formula nor a licence; the equation
  attribution rests on directional-contact-distance.md:44-48.
- **MERLIN licence** (Liu and Paulino's software): not shown in the fetched
  page.
- **Quadratic scaling** of contact preparation, discovery and correction sweep
  is inferred from reading pair enumerations, not measured.
- **All runtimes** are the repository's single recorded runs on one machine
  (dates 2026-09-12 to 2026-09-14); none was repeated here.
- **Clockwise faces from a file-read `Surface`** failing `hingesWith` is
  inferred from FoldBending.hs:202-206 plus `fan` preserving ring order; not
  tested.
- **Whether DSL-authored rigid states commonly produce non-convex panels**
  that `refineSurface` refuses is not known; the roadmap only expects some
  (roadmap.md:151-155).
- **Whether `relaxPinnedContact` behaves with an empty pin map** on a real
  model: untested and unrecorded.
