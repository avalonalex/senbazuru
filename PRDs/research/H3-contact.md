# H3. Contact and self-collision for layered paper

Research slice H3, written 2026-09-28 against `main` at `83fc960` (clean tree
apart from an untracked `.claude/`). Nothing under the repository was modified.
Every command below wrote only to this slice's scratch folder
(`scripts/H3-contact/`), which holds the scripts, their outputs, the fetched
papers and a regenerated whole-crane archive.

> **Verification, 2026-09-28.** [V](V-verification.md) re-checked this note.
> Corrections: of finding 17's 206 coincident crease pairs, **87** are nested,
> and the heights-only contradiction of finding 18 applies to those; finding 16's
> zero-distance pairs do not all lie in planes containing the x axis; IPC's
> tables use d̂ = 1e-3 ℓ in 12 of 15 rows (finding 4); OGC's 50-layer example is
> about 7.6× slower than real time (finding 7); the card-shuffle spacing is
> 0.311 mm along the normal (finding 11); Sim-FAST is CC BY 4.0 (finding 14).
> Finding 8's "nothing was installed" is stale: [H7](H7-tooling.md) and
> [X3](X3-crane-opening.md) installed and ran `ipctk` 1.6.0, whose PyPI wheel
> statically links LGPL-2.1 filib. Phase A (a creep solve) is still untested;
> [X3](X3-crane-opening.md) demonstrated a different start, cut at the folds
> and stitched back under contact.

This note builds on [research G](../../PRDs/research/G-realistic-rendering-and-simulation.md)
(written 2026-09-14), findings 7, 13 and implication 6 in particular. Where it
agrees it cites G by number. Where it goes further or disagrees, it says so.

## Summary

The study's contact machinery could not open the crane body. The reason is not
the choice of barrier. **Every robust contact method in the literature assumes
an intersection-free, strictly separated starting state, keeps it, and does not
make one.** That covers IPC, C-IPC, injective deformation processing, Offset
Geometric Contact and ZOZO's cubic-barrier solver. The study kept trying to
*make* such a start by microscopic moves from states that touched or crossed.
The git log shows 31 merged PRs from #318 to #396 with "body" in the subject.

Measured on this repository's own meshes:

- **The closed crane is valid but touching everywhere.** It has 0 crossings,
  yet 27,286 vertex–triangle and edge–edge pairs sit at distance zero.
- **The preferred "More tucked" sketch crosses itself.** It has 345 crossing
  triangle pairs and 373 zero-distance primitive pairs.
- **Thickness alone does not fix the start.** In the folded crane, 206 pairs of
  *different* creases lie on the same folded line. For such nested creases no
  choice of heights separates the layers. The outer crease has to move
  outward, the bookbinder's *creep*.

Recommended strategy: **topology first, then unsigned contact.**

1. Build one thick, intersection-free start from a state that is already valid:
   the closed crane, using its face orders, the wrap count of each crease and
   explicit creep. The fallback is to follow the certified bird-base route
   from the flat square.
2. After that, move the paper only with an IPC-style solver: an unsigned
   distance barrier with a thickness offset, and a step filter that never lets
   paper pass through paper. The prescribed shape sketches become *targets*
   that handles are pulled toward, in the IDP style, and never geometry.
3. Keep the directional layer orders as an after-the-fact audit, not as a
   constraint.

A pure-Haskell uniform-grid broad phase handles 7,168 triangles and 47,645
near pairs in 0.22–0.26 s per full evaluation, so candidate search is not the
bottleneck. The linear solve will be. An external `ipctk` prototype, or a
Haskell implementation, would test the strategy with the experiment in
[§ The experiment](#the-experiment-on-the-crane).

## Terms used here

A few words recur. The [glossary](../../docs/glossary.md) has **layer order** and
**thickness**. These are not in it yet:

- **Primitive pair.** A contact solver on a triangle mesh never asks whether
  two triangles are close. It asks about their corners and sides. A
  **vertex–triangle pair** is a corner of one triangle and a different
  triangle. An **edge–edge pair** is two sides. A pair is **incident** when the
  two share a mesh vertex, like a triangle and its own corner. Incident pairs
  are skipped, because their distance is zero by construction.
- **Unsigned distance.** The ordinary distance between two primitives, never
  negative. It cannot say which one is on top.
- **Barrier.** An energy term that is zero beyond an **activation distance**
  `d̂` ("d-hat") and grows without bound as a primitive distance falls to a
  floor. The floor is zero in IPC, and the thickness `ξ` ("xi") in C-IPC. A
  solver that minimises energy therefore never lets a pair reach the floor.
- **CCD (continuous collision detection).** Given every vertex's position
  before and after a proposed step, CCD finds the earliest fraction of the step
  at which any pair would touch. A **CCD-filtered line search** shortens every
  step to less than that fraction, so the straight-line motion between
  accepted states can never pass paper through paper.
- **Broad phase / narrow phase.** The broad phase cheaply lists the pairs that
  *might* be close, for example because their boxes overlap. The narrow phase
  computes the exact distances for those pairs only.
- **Wrap count** of a crease. The number of layers lying *strictly between*
  the two faces the crease joins, measured just inside the fold. With `n` such
  layers, the two faces' mid-surfaces sit `(n + 1)·t` apart for paper
  thickness `t`, so the fold's mid-surface radius is about `(n + 1)·t/2`.
  [a-crease-is-a-hinge.md](../../docs/notes/a-crease-is-a-hinge.md) writes
  `n·t/2`, and G finding 7 cites it. The two differ only in whether `n`
  counts the folding sheet itself [reasoned]. For `n = 0` the formula gives `t/2`, below the measured minimum radius of
  about 1.25 `t` in the same note. So the smallest radii below are lower
  bounds.
- **Creep.** The outward shift a fold must make to go round the layers inside
  it. Bookbinders correct for it with printed-page offsets
  ([a-crease-is-a-hinge.md](../../docs/notes/a-crease-is-a-hinge.md)).

## Findings

### A. What the study's contact is, and where it stopped

1. **The study's contact is directional, declared and zero-thickness.**
   - **What a contact is.** A contact is a *retained* lower/upper relationship
     between triangles, along a fixed direction attached to the model. It is
     learned from a separated reference pose, and refused for any pair that
     has no such history.
     [code] `study/fold-material/SurfaceContact.hs:1-38`,
     `LocalContactDiscovery.hs:1-31`, `ContactDiscovery.hs:1-24`.
   - **What distance it measures.** Distance to *violating the order*, not
     distance between paper: `DirectionalDistance.hs:1-8` says so explicitly.
     [code]
   - **Clearance.** The clearance is numerical, `5e-7`–`1e-6` sheet units, "not
     physical paper thickness" (`SurfaceContact.hs:19-22`). Triangles that
     share a vertex get zero clearance, so the sheet stays joined. [code]
   - **What it is not.** The header states it is not continuous collision
     detection, friction or general self-contact (`SurfaceContact.hs:28-31`).
     Separately, a straight-line correction can be certified by an
     exact-rational Bernstein-sign sweep (`CorrectionSweep`;
     [checking-numerical-corrections.md](../../docs/notes/checking-numerical-corrections.md)).
     That certificate is the study's CCD. [code]

   **What this buys.** Orders stay exactly as the diagram states them. **What
   it costs.**
   - Every new partner needs a separated earlier encounter.
   - A flap may not go *around* another one, even without touching it (G
     finding 13).
   - A fixed direction cannot judge surfaces that have turned. In the whole
     crane, 32 orders are "unchecked" in every opened state. [ran: `checks.json`
     of the regenerated archive, below]

2. **Four initialisation attempts failed, each at the start condition, not in
   a barrier solve.**
   - **Weighted separation (#379).** It lowered its cost but left negative
     gaps (`−7.74e-9`). Its length error rose to `3.18e-5` against a `1e-5`
     limit.
     [doc] [body-separated-initialization.md](../../docs/notes/body-separated-initialization.md)
   - **Constraint-first (#381).** 5,812 inequalities, 115 iterations and
     487.93 CPU s. A violation of `4.07e-8` exceeded the `1e-12` gate.
     [doc] [body-feasible-initialization.md](../../docs/notes/body-feasible-initialization.md)
   - **Angles-only (#383).** The loops closed to `1.45e-11`, but the result had
     4 coarse and 18 refined crossing pairs. The worst reversal was 4.71 px.
     [doc] [body-crease-seed.md](../../docs/notes/body-crease-seed.md)
   - **Contact-aware angles (#385).** It stopped at a `1.53e-9` violation
     against `1e-12`. An exact recomputation later found every one of the 1,204
     inequalities satisfied.
     [doc] [body-angle-contact.md](../../docs/notes/body-angle-contact.md),
     [body-barrier-comparison.md](../../docs/notes/body-barrier-comparison.md)

   The body barrier comparison never ran. **Pattern [reasoned]:** each attempt
   tried to reach a separated state by moving at most `0.001` sheet units from
   an intersecting or touching one. None of the literature methods below can
   do that either (finding 6).

3. **The whole-crane candidates are shape sketches with many crossings.**
   - **What was run.** I regenerated the archive with the built study binary,
     output to scratch:
     `senbazuru-material-study --whole-crane-start study/fold-material/fixtures/whole-crane-body.fold <scratch>/wc`.
     It took 5 min 18 s wall and 124 s user; the repository was unchanged.
   - **Crossings and reversals** (study checker, tolerance `1e-7`,
     `checks.json`):

     | State | Crossing pairs | Reversed orders | Unchecked orders |
     | --- | ---: | ---: | ---: |
     | Closed crane | 0 | 0 | 0 |
     | First candidate | 683 | 3,060 | 0 |
     | Narrower body | 266 | 1,927 | 32 |
     | More tucked (`spread-0`, −70° root tangent) | 345 | 1,982 | 32 |

   - **Edge error.** More tucked has a 57.29% maximum relative edge error
     (stdout of the same run).
   - **Which pose is More tucked.** It is `spread-0`: the slider runs from −70°
     (more tucked) to −30° in 10° steps
     ([crane-pillow-target.md](../../docs/notes/crane-pillow-target.md), lines 44-55).
   - **A correction to the task brief.** "448–1,344" is triangles and
     triangle *corners*: 448 × 3 = 1,344
     ([crane-panel-lighting.md](../../docs/notes/crane-panel-lighting.md), line 39).
     The meshes have 448 triangles and 237 vertices. [ran]

### B. What robust contact methods guarantee, and what they require

4. **IPC (Li et al. 2020).**
   - **Guarantee.** Trajectories stay intersection-free and inversion-free,
     whatever the step size or material.
   - **Barrier.** `b(d, d̂) = −(d − d̂)² ln(d/d̂)` for `0 < d < d̂`, zero
     beyond (eq. 6). The implementation evaluates it on *squared* distances.
   - **Contact set.** Only pairs within `d̂` enter the energy.
   - **Line search.** Each step is capped by conservative CCD before
     backtracking (§4.4).
   - **Stiffness κ.** Adapted per iterate: too small forces tiny gaps, too
     large makes the problem ill-conditioned (derivation in the Supplemental).
   - **Friction.** Lagged: sliding bases and normal forces are frozen from the
     previous solve. There is no convergence guarantee, and the paper usually
     applies one lagging iteration.
   - **Requirement.** The barrier needs positive separation at the start: it
     "requires nonzero separation distances to be strictly satisfied at
     initialization" (p. 12). Starting at zero distance is neither possible nor
     meaningful, because the barrier is infinite there.
   - **`d̂` in practice.** The statistics tables use `d̂ = 10⁻³·ℓ`, with `ℓ` the
     bounding-box diagonal.

   [paper] *Incremental Potential Contact*, Li, Ferguson, Schneider, Langlois,
   Zorin, Panozzo, Jiang, Kaufman, ACM TOG 39(4):49, 2020,
   <https://ipc-sim.github.io/file/IPC-paper-350ppi.pdf>, text extracted with
   `pdftotext`: lines 155-185, 440-560, 800-870.
   This agrees with G finding 13. It adds the explicit precondition, and
   confirms that the study borrowed only IPC's scalar barrier
   ([directional-contact-distance.md](../../docs/notes/directional-contact-distance.md)).

5. **C-IPC (Li, Kaufman & Jiang 2021): a thickness offset makes the start
   condition stricter.**
   - **Thickened barrier.**

     ```
     b_ξ(d, d̂) = b(d² − ξ², 2ξd̂ + d̂²)
     ```

     The second argument looks like a typo for `d̂²`. It is not.
     - Because `b` is written on squared distances, the pair activates when
       `d² − ξ² = (ξ + d̂)² − ξ² = 2ξd̂ + d̂²`, that is at `d = ξ + d̂`.
     - It diverges at `d = ξ`.
     - Broad-phase boxes grow by `ξ/2`.
   - **What it guarantees.** Mid-surfaces never come closer than `ξ`.
   - **What it requires.** Every non-incident pair must start at `d > ξ`, not
     merely `d > 0`.
   - **Elastic layer.** A larger `d̂` gives an elastic "thickness layer" that
     resists compression.
   - **Strain limiting.** A barrier bounds each triangle's singular values,
     `σ < s`. Its stiffness starts at 1 kPa and doubles, up to 0.1 MPa,
     whenever a triangle's strain gap stays under `10⁻⁴(s − ŝ)` for two
     iterations.
   - **Additive CCD (ACCD).** It accumulates a lower bound on the time of
     impact by conservative advancement. On the paper's benchmark, other CCDs
     returned tiny times of impact on thickness-offset scenes.
   - **Closest example: the card shuffle.**
     - 54 cards with offset 0.1 mm and `d̂` 0.2 mm.
     - 6.1K nodes, 36.2K contacts per step on average (46.5K maximum).
     - 0.7 min and 35.2 Newton iterations per step, on 6 cores.
     - The final stack is 15.4 mm tall.

   [paper] *Codimensional Incremental Potential Contact*, Li, Kaufman, Jiang,
   ACM TOG 40(4), 2021, arXiv 2012.04457v3 (text lines 386-560, 1110-1235,
   1355-1395). **Further than G finding 13:** G reads the offset as the fix for
   starting from a flat stack. The offset is really a stricter *requirement*
   that the start must meet. It does not construct the start.

6. **Injective Deformation Processing (IDP; Fang, Li, Jiang & Kaufman 2021)
   makes a sketch into a target.**
   - **How it works.** IDP runs IPC barriers and CCD with artificial time
     steps. It drives handles to prescribed positions over `m` steps, with a
     quadratic pull whose stiffness doubles when the solver stalls short of the
     target.
   - **Animation clean-up.** It solves `x_s = argmin ½‖x − f_s‖²_M + h·E(x, f_s)`
     from the previous clean frame. Each frame `x_s` is the closest
     intersection-free shape to an intersecting input frame `f_s`.
   - **What it requires.** A globally injective start: no crossings and no
     touching. If no intersection-free path satisfies the handles, the target
     is simply not reached.
   - **What it does with crossings.** Crossings present in the start are
     preserved: IDP "does not fail for self-intersecting input and also does
     not disentangle" (§5.6). Finding injectivity from a non-injective input is
     named as open work (§9).
   - **Scale.** Examples include folding a thin box into petals with handles.
     The dumpling fold used up to 14K nodes, 5.7K constraints and 35
     iterations per frame. Timings ranged from 0.5 s to 12 min per frame.

   [paper] *Guaranteed Globally Injective 3D Deformation Processing*, ACM TOG
   40(4):75, 2021, <https://ipc-sim.github.io/IDP/file/paper_small.pdf>. Code
   `ipc-sim/IDP`, Apache-2.0 [fetched, `gh api`].
   **Consequence [reasoned]:** the More-tucked sketch is usable as the target
   frame `f`, and its wing-tip positions can be handle targets. It cannot
   be the start.

7. **OGC (Chen et al. 2025) swaps CCD for a per-vertex movement bound.**
   - **The contact model.** Each face is offset along its normal, which keeps
     contact forces orthogonal to the surface.
   - **The bound.** From Wu et al. 2020, each vertex may move at most
     `b_v = γ_p · min(d_min,v, d^E_min,v, d^T_min,v)` per iteration, with
     `0 < γ_p < 0.5`. The minima are the vertex's distances to non-incident
     primitives. If two primitives each move less than half their separation,
     they cannot meet. Vertices that exceed the bound are truncated.
   - **What it requires.** An intersection-free starting state `X_prev`
     (eq. 27, text lines 535-560).
   - **What it claims.** More than two orders of magnitude faster than
     IPC-based simulation. The project page shows 50 cloth layers (246K
     vertices) in real time on an RTX 4090.
   - **Why it matters here [reasoned].** The bound needs only nearest
     distances, which a broad phase already has. That makes it a much simpler
     Haskell step guard than exact CCD. The study's rational Bernstein sweep
     could stay as a final audit.

   [paper] *Offset Geometric Contact*, Chen, Hsu, Liu, Macklin, Yang, Yuksel,
   ACM TOG 44(4), 2025,
   <https://graphics.cs.utah.edu/research/projects/ogc/Offset_Geometric_Contact-SIGGRAPH2025.pdf>.
   An automated summary of the project page claimed OGC needs no
   collision-free start. The paper's eq. 27 contradicts it, and I use the
   paper.

8. **IPC Toolkit and `ipctk` (current state, 2026-09-28).**
   - **Licence and release.** GitHub licence MIT. The latest release is v1.6.0,
     published 2026-07-15.
   - **Default broad phase.** LBVH (a bounding-volume tree) replaced the hash
     grid in v1.6.0: roughly 2× faster than the removed SimpleBVH and 6–8×
     faster than the old hash grid on large scenes.
   - **Other v1.5–1.6 additions.**
     - OGC trust-region step filters, including `planar_filter_step`.
     - The Geometric Contact Potential.
     - A barrier stiffness κ inside `BarrierPotential`.
     - Composable collision filters, for example excluding pairs that share a
       patch label or both belong to static obstacles.
   - **API.**
     - `compute_collision_free_stepsize(mesh, V0, V1, min_distance)`, whose
       header says it assumes `V0` is intersection-free.
     - `is_step_collision_free`.
     - `has_intersections`.
     - `NormalCollisions.build(mesh, V, dhat, dmin)`: `dmin` is the C-IPC
       offset.
     - `initial_barrier_stiffness` and `update_barrier_stiffness`. The update
       raises κ when the minimum distance is falling and below
       `dhat_epsilon_scale · diag`.
   - **Python wheels.** `ipctk` 1.6.0 was uploaded 2026-07-15, with
     `requires_python >=3.6`. There are wheels for CPython 3.10, 3.11, 3.12,
     3.13 and 3.14 on:
     - macOS arm64 (`macosx_11_0`);
     - Linux x86_64 (`manylinux_2_27`/`2_28`);
     - Windows amd64.
   - **Gaps in the wheels.** There is no macOS x86_64 or Linux aarch64 wheel
     for 1.6.0, and the PyPI licence metadata field is empty.
   - **Fit for this machine.** It is an Apple M1 Max with Homebrew Python 3.14
     and a pyenv 3.11, so wheels exist. **Nothing was installed**, and no
     NumPy is present.

   [fetched] `gh api repos/ipc-sim/ipc-toolkit/license` and `/releases`;
   `src/ipc/ipc.hpp`; `normal_collisions.hpp`; `adaptive_stiffness.hpp`;
   `curl https://pypi.org/pypi/ipctk/json`, parsed locally. An automated
   WebFetch summary of the PyPI page gave wrong dates and wheel tags, so I
   report the raw JSON.

9. **Tight-Inclusion CCD (Wang et al. 2021).**
   - Interval root-finding in Snyder's style, with modern predicates.
   - Conservative: it never misses a collision.
   - Supports a minimum separation, which is what a thickness offset needs.
   - Lets the caller trade runtime against false positives.
   - Code MIT; a GPU version (Scalable-CCD) is Apache-2.0.

   [paper] arXiv 2009.13349 abstract; [fetched] `gh api` licences.

10. **ZOZO's contact solver (Ando's cubic barrier) now runs on this hardware.**
    - Apache-2.0.
    - Its README (fetched 2026-09-28) states it is penetration-free *when it
      finds a solution*.
    - Since 2026-09-19 it supports Apple-silicon Metal and arm64 CPU backends.
    - It warns that an intersection error can mean an impossible setup, for
      example pinned panels driven through each other.
    - Its stacked-sheet example places sheets at `gap · i`.

    [fetched] `gh api repos/st-tech/ppf-contact-solver/readme`. This is a
    second external-tool option under D17. It was not run.

### C. How practitioners get an intersection-free start

11. **Separate objects are simply placed apart.**
    - **C-IPC card shuffle.** Codim-IPC's script places the *n*-th card at an
       offset of `0.22e-3·n` m, more than the 0.1 mm offset plus the 0.2 mm
       `d̂`. [fetched]
       `ipc-sim/Codim-IPC/Projects/FEMShell/8_precision_card_shuffle.py`
    - **ZOZO's stacked sheets** use the same trick (finding 10).
    - **Why it fails for us [reasoned].** It works because cards are separate
      bodies. A folded sheet's layers are joined at creases, so moving each
      layer as a whole opens the creases. That is the defect
      [paper-thickness.md](../../docs/notes/paper-thickness.md) records for
      the old layer-spacing export.

12. **Model the whole process from a valid rest shape.**
    - **Examples.** IDP folds petals and dumplings from a thin box by handles
      (finding 6). C-IPC drapes garments from flat patterns.
    - **For origami [reasoned].** This means folding from the flat square:
      trivially valid, one layer, no contacts.
    - **Assets that exist.**
      - `CheckedBird` composes four *certified* rigid paths from a prepared
        square to the bird base (`CheckedBird.hs:1-14`) [code].
      - `examples/traditional-crane.foldseq` has 28 steps. It is checked
        without geometry, and the runner that would produce frames is
        milestone M4/M5. [ran]
        `senbazuru run examples/traditional-crane.foldseq --check` →
        "28 steps, 35 moves, checked without geometry".
    - **Theory.** Demaine, Devadoss, Mitchell and O'Rourke (CCCG 2004) show
      that any well-behaved folded state can be reached from the unfolded
      paper by a continuous motion. UNVERIFIED beyond the search-result
      summary; the PDF is at
      <https://erikdemaine.org/papers/PaperReachability_CCCG2004/paper.pdf>.

13. **Untangle intersecting geometry globally.**
    - **Baraff, Witkin & Kass 2003, "Untangling cloth".** Global intersection
      analysis, history-free, which also resolves tangled initial conditions.
      [fetched] abstract,
      <https://history.siggraph.org/learning/untangling-cloth-by-baraff-witkin-and-kass/>.
    - **Volino & Magnenat-Thalmann 2006.** Moves vertices down the gradient
      of the *length of the intersection contour*, the curve where two
      surfaces pass through each other.
    - **Their reach, per ContourCraft (2024).** Baraff et al. address closed
      contours, and not open contours that run to a mesh boundary.
      [fetched] <https://arxiv.org/html/2405.09522v2>, §2 and §4.5.
    - **Buffet et al. 2019, "Implicit untangling".** Untangles any number of
      garment layers to a collision-free state, **using a layer order the user
      specifies**. [fetched] search abstract, HAL `hal-02129156`.
    - **Assessment for the crane [reasoned].**
      - Origami has what Buffet has to ask the user for: a complete layer
        order.
      - But the More-tucked sketch has 345 crossing pairs and 1,982 reversed
        orders over a sheet with open boundaries. That is deep, global
        tangling, where these methods are weakest.
      - Untangling ends at *touching* (`d ≈ 0`), so a thickness step would
        still follow.
      - Not recommended as the primary route. The layer-order idea feeds the
        thickening instead (Implications, item 3).

### D. Origami-specific contact

14. **Zhu & Filipov 2019** (bar-and-hinge contact).
    - **Model.** A node-to-panel potential,
      `k_e{ln sec(π/2 − πd/2d₀) − ½(π/2 − πd/2d₀)²}` for `d ≤ d₀`, which
      diverges at `d → 0`. `d₀` approximates thickness.
    - **Pairs.** Point–triangle only, found by a double loop.
    - **Cost.** The interlocking Miura example took 57 s, 80% of it in contact
      detection.
    - **Code.** MATLAB, in the supplementary material; licence unstated.
    - **Unknowns.** No CCD, and no initial-separation construction, are
      described in the summary I read (UNVERIFIED in full text).

    [paper] Proc. R. Soc. A 475:20190366, <https://pmc.ncbi.nlm.nih.gov/articles/PMC6834023/>.
    `zzhuyii/Sim-FAST` (pushed 2026-09-27) and `zzhuyii/OrigamiSimulator` have
    no licence file (`gh api …/license` → 404). **Ideas only.**

15. **Newer origami solvers still avoid layer-to-layer contact.**
    - **Solid-shell origami (arXiv 2601.00569, 2026).** It prevents
      self-intersection only by penalising crease angles near ±π, and shows no
      stacked-layer examples. [fetched]
    - **ThinShellLab (arXiv 2404.00451).** Penalty contact, mostly on
      single-layer tasks. [fetched]
    - **Origami Simulator.** Has no collision (G finding 10).
    - **Unknowns.** FoldingAgent (SIGGRAPH Asia 2026, arXiv 2609.00377)
      "verifies physical plausibility", but the abstract does not say how
      (UNVERIFIED). Tu & Filipov 2025 (arXiv 2507.00341) use bar-and-hinge on
      *spaced* layers.
    - **Reading [reasoned].** Robust contact for *touching* multi-layer paper
      is a graphics result (the IPC family), not yet an origami-engineering
      one.

### E. Measurements on the crane

All scripts are in `scripts/H3-contact/`. Sheet units: the sheet is the unit
square, and the study draws at 600 px per unit.

16. **How far each saved state is from IPC's precondition.**
    `python3 ipc_precondition.py <file>` (pure Python) checks every non-incident
    vertex–triangle and edge–edge pair whose boxes, padded by `0.01`, overlap.

    | State | Triangles | Zero-distance pairs (`≤ 1e-9`) | Pairs `≤ 6.7e-4` (≈ 1/1500) | Pairs `≤ 3e-3` | Minimum distance |
    | --- | ---: | ---: | ---: | ---: | ---: |
    | Body fixture (#394 endpoint) | 120 | 76 | 292 | 439 | `5.0e-13` |
    | Closed crane (`before`) | 448 | **27,286** | 27,596 | 28,814 | `4.3e-32` |
    | Narrower body | 448 | 373 | 425 | 958 | 0 |
    | More tucked | 448 | 373 | 456 | 1,114 | 0 |

    [ran] `ipc_precondition.out`.
    - **Where the zero-distance pairs are.** In More tucked, the 373 pairs
      involve 51 triangles from 12 of 76 source panels. All lie in tilted
      planes containing the model's x axis. That fits layer packs the sketch
      rotated together, but which flaps they are is UNVERIFIED. [ran]
    - **My own crossing test disagrees with the study's.** It flags 512 pairs
      in More tucked. That is a superset of the study's 345. The 167 extra
      pairs are mostly touching pairs whose penetration depth is about
      `1e-15`. The study's strict checker is the reference; mine only confirms
      it misses nothing. [ran] `crossing_tol.py`.

17. **Layers, wrap counts and nested creases of the folded crane.**
    `senbazuru fold examples/crane.fold -o crane-folded.fold` (0.11 s) gives 72
    faces and 892 face orders. `info --fold` reports 2 components and 5 valid
    orders. Then `python3 crane_layers.py examples/crane.fold crane-folded.fold`
    reads the orders with `s` against **g's** normal
    (`docs/notes/layer-ordering.md`). My first pass used f's normal, found
    cycles, and was wrong.
    - **Stack depth.** The global order is acyclic. Its longest chain is **32
      levels**, but at most **24 layers** overlap at any sampled point (a
      240×240 grid). Every grid point has a consistent local order.
    - **Nested creases.** **206 pairs** of distinct mountain/valley crease
      edges overlap along a positive length of the same folded line.
    - **Wrap counts** of the 99 mountain/valley crease segments (maximum over
      samples at ¼, ½ and ¾ of each):

      | Wrap count | 0 | 2 | 3 | 4 | 6 | 10 | 12 | 14 |
      | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
      | Crease segments | 57 | 18 | 1 | 9 | 11 | 1 | 1 | 1 |
      | Length (sheet units) | 10.14 | 2.66 | 0.50 | 0.74 | 1.55 | 0.10 | 0.10 | 0.10 |
      | Fold radius `(n+1)ξ/2` at `ξ = 1/1500`, px | 0.2 | 0.6 | 0.8 | 1.0 | 1.4 | 2.2 | 2.6 | 3.0 |

      [ran] `crane_layers.out`, `wrap_lengths.out`. The total mountain/valley
      length is 15.88 sheet units. `ξ = 1/1500` is 0.1 mm on a 15 cm sheet,
      G finding 7's figures.
    - **Global levels exaggerate.** The largest *global* level difference
      across one crease is 21, while the largest local wrap is 14. Heights
      assigned from global levels would over-open folds.

18. **Why nested creases rule out any height-only thickening [reasoned].**
    - **Concrete case.** Fold a strip in half at `x = 0`, then fold the
      two-layer strip in half again at `x = 1`. Each layer gets its own crease
      at `x = 1`: an outer crease joining faces `g` (bottom) and `f` (top), and
      an inner one joining `k` and `h`. Bottom to top near `x = 1`, the layers
      are `g, k, h, f`.
    - **The contradiction.** Suppose both creases stay on the line `x = 1`,
      at heights `z_o` (outer) and `z_i` (inner).
      - `k` above `g` right up to the crease needs `z_i ≥ z_o + ξ`.
      - `f` above `h` needs `z_o ≥ z_i + ξ`.

      Both cannot hold.
    - **The resolution.** The outer crease must move outward in the plane by
      about `ξ` per wrapped layer: creep.
    - **Why sharp hinges do not help.** A hinge opened by angle `φ` fits `n`
      wrapped layers only at distance `x ≥ (n+1)ξ/φ` from it. With `n = 14`,
      `ξ = 1/1500` and `φ = 10°`, that is `0.057` sheet units, **34 px**. A
      rounded fold of radius `(n+1)ξ/2` needs **3 px**.
    - **So:** a tight-looking thick crane needs rounded creases resolved by the
      mesh, at least where the wrap count is above zero.
    - **Crease-strip estimate [ran].** 6 rows across wrapped creases, 2 across
      unwrapped ones, 2 triangles per cell. At along-crease spacing 0.05 that
      is **2,190** triangles; at 0.02 it is **5,475**. This goes further than
      G finding 7, which derived radii but not the impossibility or the
      triangle budget.
    - **A hypothesis, untested.** The same argument at numerical clearance
      would explain #379's length error. Separating `c = 1e-6` with `n + 1 = 3`
      needs creep of about `1.5e-6`. The body fixture's material edges run
      from 0.040 (shortest) to 0.074 (median) sheet units [ran], so absorbing
      that creep as stretch is a relative strain of `2.0e-5`–`3.7e-5`. The
      observed maximum was `3.18e-5`, against a `1e-5` limit. Re-running #379 with the owner's 0.1% strain screen would
      test it.

19. **Broad phase cost in pure Haskell.**
    - **Fixture.** `prep_stack.py` lifts each closed-crane triangle to
      `z = level · ξ`, using its longest-path level in the 10,051 triangle
      orders (32 levels, as in finding 17), then splits it into 4 or 16. It
      tears creases, so it is a timing fixture, not paper.
    - **Program.** `BroadPhase.hs` (GHC 9.10.3, `-O2`, single thread, list
      based, `containers` and `array`) finds pairs on different levels whose
      boxes, padded by `d̂/2`, overlap. It then takes the minimum of 6
      vertex–triangle and 9 edge–edge distances and counts pairs within `d̂`.
    - **Settings.** `d̂ = ξ = 6.67e-4`. Five repetitions each on an Apple M1 Max;
      the grid and brute force agree on every count.

      | Triangles | Candidate pairs | Within `d̂` | Grid (0.03 cell), s | Brute force, s |
      | ---: | ---: | ---: | --- | --- |
      | 1,792 | 14,278 | 10,477 | 0.044–0.052 | 0.056–0.065 |
      | 7,168 | 73,965 | 47,645 | 0.22–0.24 | 0.52–0.91 |

      [ran] `broadphase.out`.
    - **Reading [reasoned].**
      - Candidate search and distances are fine in plain Haskell at this size.
      - The *number* of active contacts is the cost: a flat stack puts almost
        every overlapping pair inside `d̂`.
      - Each of about 50k pairs couples 4 vertices in the Hessian.
      - `SparseSolve` is explicitly "not a bounded-memory solver for arbitrary
        meshes" (`SparseSolve.hs:15-18`) [code]. The linear solve, not the
        broad phase, will limit a Haskell implementation. UNVERIFIED, not
        measured.
      - For scale: the C-IPC card shuffle carried 36K contacts at 0.7 min per
        step on 6 cores (finding 5).

### F. What unsigned contact would have done differently, and what it loses

20. **What an IPC-style solver would have done on the same inputs [reasoned
    from findings 1-6 and 16].**
    - **It would have refused to start.** The closed crane has 27,286
      zero-distance pairs; the body fixture has 76 and crosses itself, by at
      most `2.42e-7` of the sheet (corrected 2026-09-29,
      [note](../../docs/notes/crossing-counts-on-touching-paper.md)). That
      puts the start question first, before any pair repair.
    - **No partner lists and no history.** Every pair within `d̂` is active
      automatically, so the whole of discovery, reference encounters and
      "unknown new overlap" refusals disappears.
    - **No fixed direction.** The 32 unchecked orders cannot occur, and a
      surface that turns is not misread as a reversal. The 1,982 "reversed
      orders" in More tucked mean nothing to IPC.
    - **Any collision-free path is allowed**, including a flap going around
      another one.
    - **κ adapts automatically.** It replaces the study's staged penalty
      weights (`1e8`, `1e10`) and its fixed four-stage tightening.
    - **Float CCD** (conservative, Tight-Inclusion) replaces the exact-rational
      sweep: the same guarantee at far lower cost.

21. **What would be lost.**
    - **An explicit, checkable statement of diagram intent.** "Flap A is in
      front" is no longer an input; it is only preserved because paper cannot
      pass through paper. The study's audit can still report reversals
      afterwards, and a reversal then means the paper went *around*, not
      *through*.
    - **Zero-thickness coincident layers.** Every state has `d ≥ ξ`. A GLB
      shows real stacks, up to 24ξ ≈ 9.6 px at true thickness, and SVG has to
      decide what to do with them.
    - **Exact arithmetic** in the certificate, unless the sweep is kept as an
      audit.
    - **The existing contact modules as solvers.** `SurfaceContact`,
      `DirectionalDistance` and both discovery modules become diagnostics.
    - **Acyclic-order simplicity.** Nothing is lost here: IPC needs no order,
      and handles circular stackings, like a twist, natively.

## Assessment of the start options for the crane

| Option | Needs | Crane status today | Main risk | Effort |
| --- | --- | --- | --- | --- |
| Fold from the flat square along a route, with CCD (IDP-style tracking of rigid frames or handles) | Frames or handles for every step | Bird base: certified route exists. Later steps: runner not built (M4/M5) | Petal and reverse folds may need scripted handles; long pipeline | L to bird base, XL to crane |
| Thicken the valid closed crane from its face orders | Face orders (have), wrap counts (finding 17), creep solve, rounded creases | Closed crane valid: 0 crossings, 0 reversed | Nested-crease creep (206 pairs); vertices where several rounded creases meet | M at numerical `ξ0`, L at display `ξ` |
| Untangle the intersecting sketch | Layer order as the side oracle | 345 crossings, 1,982 reversals, open contours | Deep global tangling; ends at `d ≈ 0` | L, low confidence |
| Separate opened states by local moves (status quo) | Separated reference | Failed four times (finding 2) | — | stop |

## Implications for senbazuru

**Recommended contact strategy: topology first, unsigned contact after.**

1. **Adopt IPC's precondition as a gate** on every saved state that might
   start a solve (S).
   - Report the minimum non-incident primitive distance, the pair counts at or
     below `ξ` and `d̂`, and strict crossings, next to the existing
     `checks.json` fields.
   - It is about 200 lines of study Haskell, or `ipctk.has_intersections` in a
     prototype.
   - Finding 16's table is the baseline.
   - *Risk:* none. It changes no archived verdict.
2. **Stop starting solves from opened or crossing states. Treat sketches as
   targets** (S, a documentation change).
   - The prescribed whole-crane shapes become IDP frames `f`, or handle
     targets such as the 51 pins, never initial geometry.
3. **Build one thick start from the closed crane** (M at numerical `ξ0`).
   - **Where the method is valid.** Use the study's directional machinery in
     the one setting where its fixed direction is valid: the *flat* closed
     crane with z as the direction.
   - **What moves.** Crease vertices are free in the plane, so creep can
     happen.
   - **Targets.** Grow the gap target from 0 to `ξ0 = 1e-5` sheet units
     (0.006 px) under the owner's 0.1% local-strain screen
     ([illustration-material-priority.md](../../docs/notes/illustration-material-priority.md)),
     not the `1e-5` edge limit.
   - **Fallback, if it stalls within a declared budget.** Follow `CheckedBird`
     from the flat square with an IPC-style solver (L).
   - *Risk:* the creep solve may still be ill-conditioned; the 206 nested
     pairs couple distant flaps.
4. **Add unsigned contact with a thickness offset** (L in Haskell, M as an
   `ipctk` prototype).
   - **Barrier and step filter.** The C-IPC barrier `b(d² − ξ², 2ξd̂ + d̂²)`
     over all non-incident pairs from a uniform grid. Either CCD
     (`compute_collision_free_stepsize` with `min_distance = ξ`), or OGC's
     per-vertex bound `b_v = 0.45 · min distance` as the Haskell-native guard.
   - **κ** as in ipctk: initialise from gradients and raise it when distances
     fall.
   - **`d̂ = 1e-4`** (0.06 px). Resting gaps are then invisible against the
     0.1 px screens.
   - **Friction.** None at first. Add lagged friction only if flaps visibly
     slide.
   - **External tool.** A Python `ipctk` bridge that reads and writes FOLD is
     an external tool (D17), not vendoring. It needs the owner's approval to
     install `ipctk`, NumPy and SciPy.
5. **Grow thickness from `ξ0` to display `ξ` by a homotopy** (M).
   - Raise `d̂` so the elastic layer pushes layers apart (C-IPC §5). Then raise
     the floor `ξ` to 0.9 × the current minimum distance, and repeat.
   - At `ξ = 1/1500`, first refine the crease strips according to wrap counts
     (the 2,190–5,475 triangle estimate). Otherwise the folds open visibly
     (finding 18).
6. **Keep the directional order audit, downgraded to a diagnostic** (S).
   - Report reversals against the closed crane's orders after each run. Never
     feed them back as constraints.
7. **Carry thickness through rendering** (M; shared with other slices).
   - `Origami.Surface` already carries an optional thickness, unused
     ([paper-thickness.md](../../docs/notes/paper-thickness.md)).
   - Solver output would be the first real use.
   - Book-style SVG must choose whether a 24ξ stack edge is drawn.

## The experiment on the crane

Declared before running, in the style of the study's bounded experiments.

**Question.** Can unsigned contact with a thickness offset open the crane from
a valid thick start toward the More-tucked target, with zero crossings and
small strain, where the prescribed sketch has 345 crossings and 57% edge
error?

**Inputs.**

- `whole-crane/before.fold` (448 triangles, 237 vertices, 10,051 triangle
  orders, 0 crossings), from `--whole-crane-start` on the committed body
  fixture. Its SHA-256 is recorded in
  [whole-crane-candidate.md](../../docs/notes/whole-crane-candidate.md).
- Target: the two wing-tip positions of `whole-crane/spread-0.fold`, whose
  wing-tip separation is 464.49 px.
- The body-centre vertex held, plus only enough extra coordinates to stop the
  crane rotating away, following the grip plan in
  [opening-a-crane.md](../../docs/notes/opening-a-crane.md), lines 60-80.
  Neck, tail and the pocket walls are free.

**Phase A: thick start** (gate; M).

- **Method.** Directional separation in the flat state (z direction), gap
  target growing to `ξ0 = 1e-5`, crease vertices free in the plane.
- **Budget.** Declared: at most 40 corrections and no parameter retry.
- **Pass requires all of:**
  - 0 strict crossings with the study checker;
  - every non-incident primitive distance above `ξ0`, checked independently
    by `ipc_precondition.py` or `ipctk`;
  - maximum local strain ≤ 0.1%;
  - 0 reversed orders.
- **On failure,** record a start blocker and run the fallback: `CheckedBird`
  tracking from the flat square to a thick bird base, with the same gates.

**Phase B: opening by handles** (L; M with `ipctk`).

- **Handle path.** 20 increments along the straight line from the closed
  position to the target of each wing tip. Only the *handles* move straight;
  mesh positions are never interpolated.
- **Energy.**
  - The existing `FoldBending` crease and panel terms, labelled illustrative.
  - The length penalty `1e8`.
  - The C-IPC barrier, `ξ = ξ0`, `d̂ = 1e-4`, adaptive κ.
  - An IDP pull on the handles that doubles when the solver stalls.
- **Step filter.** CCD, or the OGC bound. At most 50 Newton iterations per
  increment.
- **Recorded per increment:**
  - strict crossings, required to be 0;
  - minimum distance, required to be ≥ `ξ0`;
  - handle error in px;
  - body depth and wing-tip separation in px, the study's measures;
  - maximum edge error and local stretch;
  - reversed and unchecked orders against the closed crane, as a diagnostic;
  - active pair count, Newton iterations and wall-clock time.

**Phase C: display thickness** (L).

- Refine the crease strips according to wrap counts, grow `ξ` to `1/1500`,
  and settle.
- Measure the achieved fold radii against `(n+1)ξ/2` (0.2–3.0 px).

**Success.** The end state must meet all of these:

- 0 crossings;
- minimum distance ≥ `ξ`;
- local strain ≤ 1% everywhere, with the 0.1% screen reported;
- wing-tip separation ≥ 80% of the target (371.6 px);
- a body opening that *emerged*: world-Z depth > 0 without prescribing body
  vertices.

It must also pass visual review at the three existing cameras, through
`CraneBookDrawing` and `PaperLighting`, against the More-tucked sketch.

**Informative failure.** A stall short of the target means that, under these
energies, no intersection-free path takes the handles there. Per IDP §5.5, that
is a *result*. It points at friction and sliding, grip placement, or missing
creep, not at another pair repair.

## Acceptance ideas: measuring "refined" on the contact axis

- **Valid.** 0 strict crossings, *and* every non-incident primitive distance
  ≥ `ξ` at every accepted iterate. That is IPC's precondition and C-IPC's
  guarantee, checkable with finding 16's script.
- **Invisible slack.** Resting gaps between touching layers are ≤ `ξ + d̂`,
  with `d̂` ≤ 0.1 px at 600 px per unit, matching the owner's 0.1 px screens.
- **Believable thickness.**
  - Stack height at the 24-layer point is within 10% of `24ξ`.
  - Fold radius at each wrapped crease is within 50% of `(n+1)ξ/2`.
  - Creep at the 14-wrap crease is about 3 px at `ξ = 1/1500`.
- **Faithful layering.** 0 reversals of the closed crane's orders, or every
  reversal explained by a continuous route around.
- **Honest material.** Local strain distribution reported; maximum ≤ 1%,
  0.1% screen stated.
- **Stable.** Same silhouette within 2 px under one level of mesh refinement.
- **Affordable.** Wall-clock per increment and active pairs reported. The
  target is under a minute per increment at 448–5,500 triangles.

## Sources fetched (2026-09-28)

| Source | Licence (code) | Used for |
| --- | --- | --- |
| Li et al., *IPC*, TOG 2020, <https://ipc-sim.github.io/file/IPC-paper-350ppi.pdf>; <https://ipc-sim.github.io/> | `ipc-sim/IPC` MIT | Finding 4 |
| Li, Kaufman, Jiang, *C-IPC*, arXiv 2012.04457v3 | `ipc-sim/Codim-IPC` Apache-2.0 | Findings 5, 11 |
| Codim-IPC `Projects/FEMShell/8_precision_card_shuffle.py` (`gh api`) | Apache-2.0 | Finding 11 |
| Fang, Li, Jiang, Kaufman, *IDP*, TOG 2021, <https://ipc-sim.github.io/IDP/file/paper_small.pdf>; <https://ipc-sim.github.io/IDP/> | `ipc-sim/IDP` Apache-2.0 | Finding 6 |
| Chen et al., *Offset Geometric Contact*, TOG 2025, <https://graphics.cs.utah.edu/research/projects/ogc/Offset_Geometric_Contact-SIGGRAPH2025.pdf> | not stated | Finding 7 |
| IPC Toolkit: licence, releases v1.5.0/v1.6.0, `ipc.hpp`, `normal_collisions.hpp`, `adaptive_stiffness.hpp` (`gh api`); <https://ipctk.xyz/tutorials/getting_started.html>, `/ogc.html`, `/faq.html` | MIT | Finding 8 |
| <https://pypi.org/pypi/ipctk/json> (curl) | PyPI field empty; GitHub MIT | Finding 8 |
| Wang et al., *Tight Inclusion CCD*, arXiv 2009.13349 | `Tight-Inclusion` MIT, `Scalable-CCD` Apache-2.0 | Finding 9 |
| `st-tech/ppf-contact-solver` README (`gh api`) | Apache-2.0 | Finding 10 |
| Baraff, Witkin, Kass 2003 abstract, SIGGRAPH history page | — | Finding 13 |
| Grigorev et al., *ContourCraft*, <https://arxiv.org/html/2405.09522v2> (summary of Volino 2006 and Baraff 2003) | — | Finding 13 |
| Buffet et al. 2019, search abstract (HAL `hal-02129156`) | — | Finding 13 |
| Zhu & Filipov 2019, <https://pmc.ncbi.nlm.nih.gov/articles/PMC6834023/> | MATLAB ESM, licence unstated; `zzhuyii/*` no licence file | Finding 14 |
| arXiv 2601.00569 (solid-shell origami), 2404.00451 (ThinShellLab), 2507.00341 (Tu & Filipov), 2609.00377 (FoldingAgent) | — | Finding 15 |
| Demaine et al., CCCG 2004, search summary | — | Finding 12 |

No GPL material was read for this note.

## Open questions

- **Display thickness.** True `ξ = 1/1500` (0.4 px per layer, 9.6 px for 24
  layers at 600 px per unit), or a declared exaggeration? G finding 7 asked
  this; it now also sets the mesh budget.
- **May a prototype install `ipctk`, NumPy and SciPy wheels?** They would run
  out of process, reading and writing FOLD (D17). Or must contact be Haskell
  from the start?
- **May neck, tail and outer wing packs be rigid for contact** (IPC Toolkit
  patch filters), cutting the active pairs to the body region?
- **Is frictionless sliding acceptable** in the opened body, or do reviewers
  expect layers to hold?
- **When the sequence runner (M4/M5) lands,** should route tracking replace
  Phase A as the canonical source of thick states?
- **How should book-style SVG treat thickness:** outline stack edges, or keep
  zero-thickness notation and use thickness only for depth ordering?
- **Which directional reversals are acceptable** once order is a diagnostic,
  for example a flap that legitimately goes around?

## Unverified

- The creep explanation of #379's `3.18e-5` length error (finding 18). The
  arithmetic is consistent; the construction was not re-run.
- Whether Phase A converges; whether 448 triangles suffice at `ξ0`; any
  runtime for Phases A–C.
- The Haskell linear-solve cost at about 50k active pairs. Only broad and
  narrow phase were timed.
- The `ipctk` runtime on these meshes. Not installed.
- Internals of Baraff–Witkin–Kass (flood-fill region colouring) and of
  Volino's contour minimisation beyond ContourCraft's summary. Buffet et al.
  beyond the abstract.
- The Demaine et al. continuity theorem beyond the search summary.
- OGC's real-time figures (project page only). Its dependence on Wu et al.
  2020 is taken from OGC's own citation; the Wu paper was not read.
- Zhu & Filipov details beyond the PMC summary: CCD, initial separation,
  exact pair culling.
- Which flaps carry More tucked's 373 zero-distance pairs (finding 16: tilted
  packs containing the x axis).
- Wrap counts are sampled at three points per crease segment. They assume the
  layers counted at a sample reach the crease.
- The broad-phase fixture tears creases (per-face heights), so its pair counts
  indicate order of magnitude, not the counts a valid thick crane would have.
