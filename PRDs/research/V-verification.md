# V. Verification of the refined-forms research

Adversarial verification, run 2026-09-28 against `main` at `83fc960`, of the
load-bearing claims in research slices [H1](H1-diagnosis.md)–[H7](H7-tooling.md)
and experiments [X1](X1-paper-look-renders.md)–[X3](X3-crane-opening.md),
before [PRD 11](../11-prd-refined-final-forms.md) was written. It does not
cover the second-round experiments [Y1](Y1-valid-curved-looks.md)–[Y6](Y6-fea-oracle.md),
which ran at the same time; they are single runs. Five verifiers
worked independently of the researchers, each told to default to "not
confirmed" unless they reproduced a claim: re-ran the script, recomputed the
number, or fetched the source and found the statement. Nothing in the
repository was changed.

A claim is **confirmed** when it was reproduced; **corrected** when its
substance holds but a number or wording was wrong; **refuted** when it is
false. The notes themselves are kept as written, with an erratum block at the
top pointing here, the practice of [A2](A2-study-recipes-as-proto-dsl.md) and
[C](C-renderers-cli-formats.md).

## What held

Every load-bearing geometry figure reproduced exactly, several by independent
reimplementation rather than by re-running the original script:

- More tucked (`spread-0`): 57.29% largest edge error, principal strain
  +106.8% / −83.6%, 74.2% of the sheet's area strained by more than 10%,
  345 crossing triangle pairs (identical pair set from a reimplementation of
  `Senbazuru.Origami.Contact.crosses`), 1,982 reversed and 32 unchecked layer
  orders, 99 vertices whose angle sum changed by more than 5°, 15 panel joins
  bent more than 45° (largest 172.6°), 5 panels with triangle normals more than
  90° apart.
- The closed crane: 0 crossings and 27,286 vertex–triangle and edge–edge pairs
  at distance zero.
- The book drawing's measurements: 23.6 bounding-box diagonals of ink against
  4.8 for the production flat crane; 617 paths restyled to 162; seven loose
  contour ends in the upright view, six within 0.01 px of a projected crossing
  (strongly enriched against a 1.8% base rate for random contour points).
- X1's Line Art intersection length (0 px valid, 1,746 px sketch), H5's
  44.5% / 1.6% wrong-side pixels, X2's volumes, X3's linear program and stitched
  metrics, the stroke widths, and the paper arithmetic of H2 findings 8, 9 and
  21 and H4 findings 8 and 9.
- The literature claims on which the design rests: IPC needs strictly positive
  separation at the start (Li et al. 2020, p. 12) and caps each step with CCD;
  C-IPC's thickened barrier and card-shuffle numbers; IDP does not disentangle
  intersecting input (§5.6); OGC needs an intersection-free start (eq. 27);
  English & Bridson's and Goldenthal et al.'s locking arguments; Skouras et al.'s
  tension-field timings; the Siéfert et al. regime; the Mylar constants;
  Lechenault et al.'s κ, φ₀ and L*.
- Licences: ipc-toolkit, IPC and Origami Simulator MIT; Codim-IPC and IDP
  Apache-2.0; LibShell MPL-2.0; better-bending MIT; SWOMPS without a licence;
  Developability of Triangle Meshes GPL-2.0; Mitsuba 3 BSD-style;
  `KHR_materials_diffuse_transmission` still a release candidate, read by
  Babylon.js and not by three.js r186.
- Timings: the readable Haskell LDLᵀ, Eigen and the hyper-dual Hessian
  (39–40 µs) reproduce.

## Corrections that change a number or a statement

| Source | Was | Is |
| --- | --- | --- |
| H1 F4, summary | 13.0% of area above 50% strain | about 13%: two triangles sit exactly at 50.0%, so the bin reads 12.7–13.3% with rounding. The 74.2% above 10% is exact |
| H1 F6 | 99 vertices "lost" angle sum | 54 decreased and 45 increased; 92 interior, 7 on the boundary. Distortion of both signs, not specifically a dome's |
| H1 F15, D2 baseline | 22–28% of contour ink doubled | Two different defects. 22–28% runs 0.02–1 px from a *near-parallel* contour (still 16.6% after de-duplication). Separately, 74–78% of emitted contour ink is one copy of an *exactly coincident* pair. Report both, named separately |
| H6 F2 | 74–78% of contour ink drawn twice | That share of emitted ink is one of a coincident pair: 58–64% of the distinct contour length is drawn twice, and de-duplication removes 37–39% of contour ink |
| H1 F16 | material previews fill 381 triangles separately | 381 is the path count; `material-sharp-single` holds 2,048 triangles in 188 fill paths. The seams are real: 11,003 and 12,583 lighter interior pixels there, and 1,401 at 1× (6,085 at 4×) in the whole-crane preview's `after` figure, whose two `#eee6cf` paths hold 163 and 145 rings |
| H1 F3 | 111 study commits since 09-10, 31 since 09-20 | a bare `--since` date takes the time of day; whole days give 119 and 35 |
| H1 F1 | "31 body PRDs" | 31 body *PRs* among 45 merged in #318–#396; #228–#314 holds 42 PRs (34 study, 8 sequence) |
| H3 F16 | the 373 zero-distance pairs lie in planes containing the x axis | false; normals' x component reaches 0.53 |
| H3 F17, summary | 206 nested crease pairs | 206 coincident pairs, of which **87** are nested (one crease's faces strictly between the other's). The heights-only contradiction applies to the 87 |
| H3 F4 | IPC's tables use d̂ = 1e-3 ℓ | 12 of 15 rows do |
| H3 F7 | OGC shows 50 cloth layers in real time | 6.3 ms per 1/1200 s step, about 7.6× slower than real time |
| H3 F11 | cards offset 0.22 mm, more than 0.3 mm | offset 0.22 mm in both x and y on cards turned 45°, so 0.311 mm along the normal |
| H2 F2, F20 | study stages give γ ≈ 1.2e3…1.2e9; kami-matching weight 4.3e6; last stage 20× kami | the study's panel hinge weight `P` corresponds to a plate stiffness `D` ≈ 2`P`, up to 5.8`P` across right-triangle diagonals. So γ ≈ 5.8e2…5.8e8, kami-matching weight ≈ 0.85–1.4e7, last stage 7–12× kami. Kami still lies between stages 3 and 4. L* is unaffected |
| H2 F3 | Tamstorf & Grinspun §4; "Botsch" | the Hessian split is eq. 3 in §2; the Gauss–Newton remark credits Fröhlich and Botsch; 7× is against autodiff for forces and gradients |
| H2 F7 | virgin die creases L* 1.6–64 mm | 1.6–133 mm |
| H2 F10 | MERLIN search returned nothing | the cited `gh api … -f q=…` POSTs and errors; a correct `-X GET` search also finds nothing. The code downloads from liukepku.com without a stated licence |
| H2 F11, H3 F14 | Sim-FAST has no licence | SWOMPS has none; **Sim-FAST and Sim-FAST-PY declare CC BY 4.0** in their READMEs. Reuse is an owner decision, not a block |
| H4 F8 | wrinkle wavelengths 1.4–4.6 cm | Cerda & Mahadevan's prefactor is 2√π, not √(2π): **2.0–6.5 cm** (1.7–5.4 cm for kami). The conclusion, wavelength as long as the model, gets stronger |
| X2 | Mylar exact volume 1.2186; tea bag published 0.2055–0.217 | 1.2185; 0.2176 is Kepert's heuristic bound under two unproved assumptions |
| X2 | membrane stiffness above 1e3 irrelevant; clamped rise 3% | true for the free-rim tea bag only; the clamped rise falls as stiffness^(−1/3): 1.45% at 1e4, 0.67% at 1e5 |
| X2 | "15–25% excess material" | local to edge midpoints; the sheet average is 5.9% |
| X2 | kami at `ks` 1e4–1e5, `kb` 5e-3–5e-2 | `ks` 8e3–8e4; the hinge gives `D` ≈ 2.9–4.5 `kb`, so `kb` ≈ 1.1e-3–1.8e-2 |
| X1 | faceting changes 256 px, thickness 811 px | these counts do not reproduce under any per-pixel rule; the MAEs reproduce only with alpha averaged in. The qualitative result stands |
| X1 | layer offsets are mandatory in the GLB | the default *visible-paper* scene already draws the closed crane 100% front-side; the wrong side appears only in the *complete-paper* scene the whole-crane gallery writes |
| X1 | Line Art intersections as a gate | holds only with fold walls off after `faceOrders` offsets; an illustration, not a validated gate |
| X3 | one-piece sheet has no layer-offset start at all | only a **heights-only** start is ruled out (proved independently); a start with creases moving sideways (creep) is open |
| X3 | stitched and opened states intersection-free | only among triangles sharing no material vertex; ipctk's own check finds 172–251 vertex-sharing crossings, some far from the stitch |
| X3 | mid-wing crossing probably Additive CCD | supported by one A/B re-run of step 6: Additive reproduces it, Tight Inclusion does not (147 s against 54 s). The `+300 iterations` state has 4 unreported crossing pairs |
| H7 F5, F7 | `SparseSolve` 99.4 s; CHOLMOD 18–21 ms; the gap is supernodal BLAS | re-run three times at low load: 61.7–66.5 s; CHOLMOD 14.9–16.6 ms; CHOLMOD chose a *simplicial* factor on these matrices, so the gap is kernel efficiency and more of it is recoverable in Haskell |
| H7 F13 | the double fold stalled (0.77° in 622 s) | a prototype limitation: fixed barrier stiffness 1, finite-difference gradients, a 60-iteration cap. At κ = 1e4 the second fold followed its target to −113.8° / +105.8° with no intersections and ±0.13% edge strain, still at the iteration cap. Whether a full 180° double fold is reachable remains open |
| H5 F21, H7 F14 | an MIT `bpy` script appears permissible | Blender's FAQ says published scripts using its API must be "licensed as GNU GPL as well", stricter than its licence page's "GPL compliant". Owner decision |
| all | ipctk is MIT | the *source* is MIT; the PyPI *wheel* statically links LGPL-2.1 filib. Fine as a user-installed oracle, not to vendor or redistribute |
| H4, `docs/related-projects.md` | Blender is GPL-2.0 | Blender's licence page (fetched 2026-09-28, <https://www.blender.org/about/license/>) gives the source as GPL-2.0-or-later and binaries as GPL-3.0-or-later |

## One refutation

**H1 F15**: "no contour segment has a free end, so strokes that seem to stop in
mid-paper are doubled outlines of thin exposed strips." The degree test passed
only because every boundary is emitted twice and each stroke's own twin shares
its endpoints. All seven loose ends in the upright view are single boundaries,
drawn twice, that genuinely end in mid-paper, six of them where two layers pass
through each other (H6 finding 4).

## Tooling note

In this checkout `stack exec -- senbazuru` can resolve to a stale binary from
2026-09-06 (install root `a9ea60a7…`) that has no `fold`, `crease` or `run` and
writes no visible-paper scene; the current build is under `6ae009cc…`. Commands
in PRD 11 use `stack run`, which builds first.

## Conflicts resolved

- **Parameters for paper.** H2 used kami at 72 µm with an assumed 4 GPa
  (B = 1.31e-4 N·m); H4 used 0.1 mm at 3 GPa (2.7e-4); X2 used 0.08 mm; H3, H7
  and PRD 07 use 1/1500 of the sheet. PRD 11 takes kami, `t` = 72 µm
  (OrigamiUSA's measurement of one brand), `E` stated as an unmeasured 3–4 GPa,
  and reports results in the groups that do not depend on `E` (γ, L*/t, the
  puff amount p̂).
- **Strokes stopping in mid-paper**: H6 is right (see the refutation above).
- **Crossing counts** on More tucked: 345 is the strict count and the reference;
  H3's own 512 adds touching pairs at penetration about 1e-16; H5's 289 used a
  different test and was not checked.
- **Whether thickening the closed crane is impossible**: only by heights. Creep
  (creases moving sideways) and rounded folds remain open routes
  ([H3](H3-contact.md) finding 18).

## Not checked

H5's 289 crossings; H1's pale-strip image and lighting counts; runtimes the
notes quote from earlier repository notes; the Blender Mylar case at
compression 0.1; per-call CCD timings; three.js frame time; the licences inside
the ARCSim and MERLIN downloads. Timings not re-run three times here were taken
at load averages of 175–235 and are marked as single runs where cited.
