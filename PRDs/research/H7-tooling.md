# H7. Implementation paths, libraries and architecture fit

Research slice H7, written 2026-09-28 against `main` at `83fc960` (clean tree
apart from an untracked `.claude/`). It asks one question of the owner's
request: *if* senbazuru is to render non-flat origami from a mesh of the paper
bent by a real material solve — a crane's body opened, a waterbomb inflated, a
wing spread — **what software would compute that, where would it live, and
what would it cost?**

> **Verification, 2026-09-28.** [V](V-verification.md) re-checked this note.
> Re-run three times at low load, `SparseSolve` took 61.7–66.5 s at 6,912
> unknowns (not 99.4 s) and CHOLMOD 14.9–16.6 ms; CHOLMOD chose a *simplicial*
> factor on these matrices, so finding 7's explanation of the gap by supernodal
> BLAS is dropped, and more of it is recoverable in Haskell. Finding 13's
> double-fold stall is a prototype limitation: with barrier stiffness 1e4 the
> second fold followed its target to about 110° with no intersections, still at
> the iteration cap; a full 180° double fold is open. Finding 11: the PyPI
> `ipctk` wheel statically links LGPL-2.1 filib (MIT source). Finding 14:
> Blender's FAQ requires published `bpy` scripts to be GPL. The benchmark
> matrices and meshes it names are not kept.

Everything below was either run on this machine, read in the repository, or
fetched on 2026-09-28. Nothing under the repository was changed. Scripts,
logs, meshes and images are in
`scripts/H7-tooling/` beside this note (a scratch directory, not
the repository); the commands are quoted where the numbers are.

This note builds on [G](G-realistic-rendering-and-simulation.md) (2026-09-14).
It agrees with G's findings 11 and 13 and with implication 9 (external solvers
run out of process), goes further on G's finding 13 with measurements, and
disagrees with one of G's framings in finding 22 below.

## Words used here

These are defined once, for a reader who knows Haskell and no numerical
simulation. The glossary (`docs/glossary.md`) and PRDs' glossary additions
already define *crease*, *layer*, *material coordinates*, *settle*, *penalty
contact* and *barrier contact*.

- **Degree of freedom (DOF).** One unknown number. A mesh vertex that may move
  has three (x, y, z), so a 2,000-vertex sheet is a 6,000-DOF problem.
- **Energy minimisation.** The study finds a shape by writing down a number
  that is small when the paper is happy — edges at their original lengths,
  creases at their preferred angles, layers apart — and moving vertices to make
  it smaller. A *static* solve looks only for the resting shape; there is no
  time and no motion in it.
- **Newton's method.** Repeatedly approximate the energy by a bowl (a quadratic)
  around the current shape and jump to the bottom of the bowl. The bowl's
  steepness in every pair of directions is the **Hessian**, a DOF × DOF matrix
  of second derivatives. **Gauss–Newton**, which the study uses, builds the
  bowl from first derivatives only (it writes the energy as a sum of squared
  "residuals" and uses Jᵀ J, where J holds each residual's first derivatives).
- **Sparse matrix.** Most Hessian entries are zero: a vertex's energy depends
  only on its neighbours. Solving "Hessian × step = −gradient" is the expensive
  part of each Newton iteration. A **sparse Cholesky** (or **LDLᵀ**)
  **factorisation** rewrites the matrix as triangular pieces that are cheap to
  solve with. Factoring creates new non-zeros, called **fill**; the order in
  which unknowns are eliminated, the **ordering**, decides how much. AMD
  (approximate minimum degree) and nested dissection are the two standard
  orderings.
- **Automatic differentiation (AD).** Computing exact derivatives by running
  the energy's own code on special numbers. A **dual number** a + b·ε with
  ε² = 0 carries a value and one first derivative; a **hyper-dual number**
  a + b·ε₁ + c·ε₂ + d·ε₁ε₂ carries one second derivative as well. Issue #62
  proposes writing the dual number by hand rather than depending on the `ad`
  package.
- **IPC (Incremental Potential Contact).** A contact method (Li et al. 2020) in
  which an energy term, the **barrier**, grows without bound as two
  non-neighbouring pieces of surface approach a chosen distance. Newton steps
  are shortened by **CCD** (continuous collision detection: "how far along this
  straight step can every vertex move before two pieces of surface touch?"), so
  every accepted shape is free of intersections. **dmin** is an offset that
  makes the barrier act at distance dmin instead of zero, which is how paper
  thickness enters. An **admissible start** is a shape where every
  non-neighbouring pair is already more than dmin apart; IPC cannot begin
  anywhere else.
- **Oracle.** An independent program whose answer we compare ours against, as
  D17 uses the word. It is never in the build and never in CI.

## Summary

The owner's request needs three things the repository does not have:
**thickness as geometry**, **contact that can start and stay valid**, and
**derivatives and linear algebra fast enough for 5,000–20,000 unknowns**.
Libraries for all three exist, and most of them run on this Mac today. The
architecture decides which of them may live in the repository.

1. **The measured blocker is the start, not the solver.** No crane shape in the
   repository is a valid starting point for a barrier method. ipctk reports the
   closed crane as intersecting, with 17,335 pairs of surface closer than one
   paper thickness (1/1500 of the sheet). The owner's preferred "More tucked"
   candidate has 345 crossing triangle pairs by the study's own check. Giving
   the closed crane naive layer offsets from its `faceOrders` leaves 2,125–2,309
   pairs too close (findings 1–3). Starting **flat and folding with thickness**
   works for one fold. A 16 × 16 sheet folded in half stops at
   179.24°–179.39° with its layers exactly one thickness apart and no
   intersection. But the prototype could not fold the resulting two-layer
   packet a second time: that crease moved 0.77° in 622 s (finding 13). So the
   first research question is whether stacked layers can fold at all this way,
   not how fast.
2. **Haskell can do the linear algebra; the study's `SparseSolve` cannot at
   this scale.** On identical 6,912-unknown matrices, `SparseSolve` took 99.4 s
   to factor. A plain ~150-line Haskell LDLᵀ took 1.06–1.13 s with a nested
   dissection order from the sheet's material grid, and 0.27–0.29 s with an AMD
   order. Eigen took 72 ms and CHOLMOD 18–21 ms (findings 5–7). Hackage has no
   maintained sparse Cholesky whose licence and dependencies suit the project
   (finding 6).
3. **Write the dual numbers by hand, as #62 says.** The `ad` package (BSD-3)
   takes 0.5–3.6 ms per 12-input hinge Hessian here. A hand-written hyper-dual
   type of 35 lines takes 39–40 µs, with the same entries to 1e-14 (finding 8).
4. **ipctk (MIT) is the right prototyping tool.** It installs from a wheel in
   11 s and supplies contact only: barrier, CCD and a thickness offset. A 217-line
   Python prototype inflated a paper envelope at 1.5k, 6.2k and 13.8k DOF in
   0.9 s, 4.2 s and 51 s, with about 1% strain and no intersection; the
   largest stopped at its iteration cap without converging (finding 12).
   Blender (GPL; run, not linked) inflates the same envelope in 2–26 s, but it
   is a dynamic mass-spring cloth whose result depends on frame count
   (finding 14).
5. **Recommended path:** prototype in Python with ipctk, outside CI, as D17
   allows, with the double fold as the go/no-go test. Keep the prototype's
   contract identical to PRD 07's `SettleInput`. Then graduate
   `Numeric.Sparse` and `Numeric.Dual` into Haskell, which pays off either
   way, and an IPC-style `Material.Contact` only if the go/no-go passes. Three owner decisions come
   first: inflation is a D18 non-goal; D14 says settled geometry never feeds a
   later step, while path-following needs exactly that; and thickness as
   geometry is also a D18 non-goal.

## Findings

### A. What the study's current crane actually is, measured

1. **The whole-crane candidates reproduce, and the owner's preferred pose is
   a sketch paper cannot take.** [ran] The committed study binary was run with
   its output in the scratch directory:
   `senbazuru-material-study --whole-crane-start study/fold-material/fixtures/whole-crane-body.fold <scratch>/wc`.
   It took 247.8 s of wall time (122 s user) and changed nothing in the
   repository (`git status` afterwards showed only `.claude/`). From its
   `checks.json`, with 448 triangles in every state:

   | State | Max relative edge error | Local stretch / compression | Crossing pairs | Reversed orders |
   | --- | ---: | ---: | ---: | ---: |
   | `before` (closed crane) | 1.4e-11 | ≈ 0 | 0 | 0 |
   | `after` (first candidate) | 5.26% | +22.30% / −5.73% | 683 | 3,060 |
   | `narrow` | 58.04% | +152.17% / −82.10% | 266 | 1,927 |
   | `spread-0` ("More tucked") | 57.29% | +106.80% / −83.63% | 345 | 1,982 |
   | `spread-100` ("More spread") | 76.13% | +202.93% / −83.93% | 217 | 1,896 |

   The slice brief's "≈58% edge error, ≈152% stretch, ≈266 crossings" is the
   `narrow` state. The "More tucked" pose the owner prefers has 345 crossing
   pairs. Every candidate reports `inflationSimulated: false`,
   `motionChecked: false` and `newSolves: 0`, as `whole-crane-candidate.md`
   says. Paper stretches well under 1% before it tears or crumples, so these
   are shape sketches that paper cannot take.

2. **No crane state in the repository is an admissible start for a barrier
   method.** [ran] `scripts/H7-tooling/ipc_check.py` loads each FOLD file into an ipctk
   `CollisionMesh` and asks `has_intersections`. It then counts collision
   stencils, meaning point–triangle and edge–edge pairs, within 1/1500 of a
   sheet side. That is 0.1 mm on a 15 cm sheet, the thickness PRD 07's material
   block uses.

   | FOLD | `has_intersections` | Stencils closer than 1/1500 | Smallest distance |
   | --- | --- | ---: | ---: |
   | `before` | True | 17,335 | 7.5e-34 |
   | `spread-0` | True | 283 | 6.8e-27 |
   | `narrow` | True | 257 | 6.9e-27 |
   | `after` | True | 680 | 5.0e-13 |

   The closed crane counts as intersecting to ipctk because its layers
   coincide: zero thickness, distance zero. G finding 13 derived that an
   IPC-style solve cannot start from a zero-thickness flat stack. This is that
   derivation measured on the real fixture. **A gotcha for anyone repeating
   this:** `compute_minimum_distance` returns the *squared* distance; the table
   reports its square root.

3. **Naive thickness offsets do not produce an admissible start either.** [ran]
   `scripts/H7-tooling/offset_start.py` gives each face of the closed crane a layer rank
   within its plane. The ranks are longest paths through the `faceOrders` graph.
   It then moves each vertex by the mean of its faces' offsets, rank × t along
   the plane normal. All 448 faces rank, in 4 plane groups with up to 32
   triangle-layers. At t = 1/1500, 3e-3 and 1e-2 the result still intersects,
   with 2,227, 2,125 and 2,309 stencils closer than t and a smallest distance
   around 1e-18.

   A vertex shared by faces in different layers is exactly where paper wraps
   around a crease. Averaging collapses the wrap, which is G finding 7's point
   about fillets, now measured.

   **The line that looks like a typo:** FOLD's `faceOrders` triple
   `[f, g, +1]` puts `f` on the side of **`g`'s** normal, not `f`'s
   ([FOLD spec](https://github.com/edemaine/FOLD/blob/main/doc/spec.md),
   `doc/spec.md:362-365`, via `gh api`). The first version of the script used
   `f`'s normal. Every face then fell into a cycle and none could be ranked.

### B. Haskell: what is on Hackage, and what it costs

4. **The library and the study depend on no numeric package today.** [code]
   The library needs only `aeson`, `base`, `bytestring`, `containers`,
   `filepath`, `megaparsec`, `tagsoup`, `text` and `transformers`
   (`senbazuru.cabal:210-219`). The study executable adds only `directory`
   (`:240-248`). All of the study's linear algebra is `Data.IntMap`, hand-written
   (`study/fold-material/SparseSolve.hs:23-26`). Its derivatives are
   hand-derived gradient rows: `FoldBending.bendingRows` returns
   `[([(Int, V3)], Double)]` from `hingeAngle`'s own gradient
   (`FoldBending.hs:261-268`). Its energies are Gauss–Newton residuals with
   penalty weights 1e8 (lengths) and 1e10 (contact)
   (`BodyFreshGallery.hs:136`; `whole-crane-candidate.md` "One bounded
   adjustment").

5. **`SparseSolve` is the bottleneck well before 20k DOF.** [ran]
   `hsbench/app/SparseBench.hs` builds the study's kind of normal matrix,
   Jᵀ J + 10⁻³ I, on an n × n triangulated sheet. It uses one length row per
   edge (6 unknowns) and one hinge row per interior edge (12 unknowns), with
   deterministic pseudo-random entries. It then calls the study's own
   `factorNormal` and `applyFactor`, copied unchanged into the scratch
   benchmark. GHC 9.6.7, `-O2`, one run per size:

   | Unknowns | Factor + one solve | Second solve |
   | ---: | ---: | ---: |
   | 768 | 0.35 s | 4 ms |
   | 1,728 | 2.47 s | 13 ms |
   | 3,072 | 11.3 s | 34 ms |
   | 6,912 | 99.4 s | 119 ms |

   **Why it is slow.** Between consecutive rows the cost grows as the 2.4th to
   2.7th power of the number of unknowns, so doubling the unknowns multiplies
   it by about six. Two reasons show in the code:
   - It chooses each pivot by scanning every remaining row
     (`foldl' smaller first rest`, `SparseSolve.hs:57`).
   - It stores rows as `IntMap`s. Its header already says it is "not a
     bounded-memory solver for arbitrary meshes" (`:16-17`).

   **What this means for the study today.** The study uses the factor as a
   preconditioner for conjugate gradients. #208's profile attributed 31% of
   time to factorising (PRD 07, "What the tests already pay"). The accepted
   crane-wing meshes have 392 and 1,192 triangles, about 600–1,800 unknowns,
   which is the 0.35–2.5 s row. The study's contact rows couple more pairs than
   this benchmark, so these times are a lower bound [reasoned].

6. **Hackage has no maintained sparse Cholesky that fits.** [fetched
   2026-09-28; `.cabal` files and upload times from hackage.haskell.org,
   Stackage membership from `https://www.stackage.org/lts-22.44/cabal.config`]

   | Package | Licence | In `lts-22.44` | Last upload | Notes |
   | --- | --- | --- | --- | --- |
   | `ad` 4.5.6 | BSD-3 | yes | 2025-03-03 | forward, reverse, sparse, `hessian`, `hessianProduct` |
   | `hmatrix` 0.20.2 | BSD-3 | yes | 2023-01-09 | dense LAPACK; on macOS links `blas lapack` and the Accelerate framework (`hmatrix.cabal:114-129`); sparse support is `GMatrix` and conjugate gradients only, with no sparse direct solver (module docs) |
   | `hmatrix-gsl` | **GPL-3** | yes | — | GPL; ideas only |
   | `hmatrix-sparse` 0.19 | BSD-3 | no | 2018-04-22 | links Intel MKL (`extra-libraries: mkl_intel …`); no MKL on Apple silicon |
   | `sparse-linear-algebra` 0.3.1 | **GPL-3** | no | 2022-12-27 | GPL; ideas only |
   | `eigen` 3.3.7.0 | BSD-3 bindings | no | 2018-12-11 | `tested-with: GHC == 8.6.1`; building it on GHC 9.6 is UNVERIFIED |
   | `sparse-lin-alg` 0.4.3 | BSD-3 | no | 2013-03-23 | unmaintained |
   | `massiv` 1.0.5 | BSD-3 | 1.0.4.1 | 2025-05-31 | dense arrays and stencils; no factorisations in its module list |
   | `sparse` 0.9.2 | BSD-3 | no | — | Morton-ordered sparse matrices; no solver found |
   | `conjugateGradient` 2.2 | BSD-3 | no | — | iterative only |

   Searches for "cholesky" and "suitesparse" on Hackage return nothing relevant
   (`eigen-hhlo` only). There is no `cholmod` package.

7. **A clear Haskell LDLᵀ is fast enough, and the ordering matters more than
   the language.** [ran] `hsbench/app/LdlBench.hs` is an *up-looking* LDLᵀ, a
   textbook method: for each new row, find which earlier columns it touches by
   walking the elimination tree, then do a sparse triangular solve. It uses
   `Data.Vector.Unboxed.Mutable`, about 150 lines, written from the published
   algorithm; the factor and solve are 97 lines of it. SuiteSparse's `LDL` package is LGPL-2.1 (its `License.txt`, via
   `gh api`), so its code was not read or copied. The benchmark reads exactly
   the matrices `SparseBench` wrote. The Python rebuild agrees with them to a
   relative 1e-16 to 3e-16.

   Factor plus one solve, milliseconds, three runs each except where noted:

   | Unknowns | `SparseSolve` (1 run) | Haskell LDLᵀ, material-grid order | Haskell LDLᵀ, AMD order | Eigen `SimplicialLDLT` (median) | CHOLMOD via scikit-sparse (median, two orderings) | SciPy SuperLU (median) |
   | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
   | 768 | 348 | 10–12 | 4–5 | 1.6 | 1.1–1.5 | 2.7 |
   | 1,728 | 2,468 | 57–61 | — | 6.5 | 3.1–3.2 | 9.4 |
   | 3,072 | 11,303 | 195–200 | — | 18.2 | 6.5–7.4 | 26.7 |
   | 6,912 | 99,424 | 1,064–1,134 | 266–285 | 72.0 | 17.6–20.7 | 100.8 |
   | 12,288 | — | 3,502–3,693 | — | 232 | 37.4–41.1 | 296 |
   | 27,648 | — | 19,341–20,840 | 3,513–4,135 | 861 | 142.5–172.9 | 1,908 |
   | 49,152 | — | — | — | 3,015 | 232.6–287.3 | 3,982 |

   **What the table shows.**
   - With CHOLMOD's AMD permutation fed in, the Haskell factor has CHOLMOD's
     fill exactly: 42,330 + 768 diagonal = 43,098 non-zeros at 768 unknowns. At
     6,912 unknowns it is 959,364 plus the diagonal.
   - So the remaining gap to Eigen is about 4× and to CHOLMOD about 13–25×.
     That is kernel speed: supernodal blocking and BLAS, which a learning
     project need not match.
   - The material-grid order was the simplest nested dissection: cut the square
     in half, number the cut line last, recurse. It left 2.7–3.5× more fill than
     AMD.

   **Why material coordinates suit ordering** [reasoned]. However a model is
   folded, its material coordinates lie on the flat square. So the nested
   dissection order can be computed on the sheet, and one order serves every
   state of a sequence. A better separator rule is the obvious next
   measurement.

   **Cost at the target scale.** 20k unknowns is a sheet of about 6,700
   vertices, roughly a crane refined to 13,000 triangles. There the AMD-ordered
   Haskell factor would take about 2–3 s, extrapolated below the measured
   3.5–4.1 s at 27,648. Fifty Newton iterations would then be a few minutes per
   settle, acceptable offline. `SparseSolve` extrapolates to about 26 minutes
   *per factorisation* (99.4 s × (20,000 / 6,912)^2.6), so it should not
   graduate at D15 stage 2 as written.

   **Licences for the ordering.** AMD is BSD-3 (SuiteSparse `AMD/Doc/License.txt`,
   via `gh api`), so porting its algorithm, or even its C code with attribution,
   is compatible with MIT.

8. **Per-element Hessians: a hand-written hyper-dual beats `ad` by 13–92×.**
   [ran] `hsbench/app/AdBench.hs` and `HyperBench.hs` time the Hessian of one
   discrete-shells hinge energy. That is 12 inputs: four vertices, with an
   `atan2` dihedral angle. They also time a St Venant–Kirchhoff membrane
   triangle, 9 inputs. Microseconds per evaluation:

   | What | `ad` generic | `ad` `Numeric.AD.Double` | Hand-written hyper-dual |
   | --- | ---: | ---: | ---: |
   | Hinge value | 0.1–0.5 | — | — |
   | Hinge gradient (reverse) | 8.5–9.0 (2k evals); 19–42 (20k evals) | 6.6–9.7 | — |
   | Hinge Hessian | 785–1,399 (2k); 3,457–3,601 (20k) | 513–841 | **39.2–39.8** |
   | Hinge Hessian, `Numeric.AD.Mode.Sparse` | 2,149–3,237 | — | — |
   | Membrane Hessian | 253–346 (2k); 661–1,540 (20k) | — | — |

   The hyper-dual runs the energy 78 times, once per upper-triangle entry, on a
   four-component number. Its first Hessian row equals `ad`'s to about 1e-14.
   `ad`'s Hessian matches a central difference of its gradient to 6.8e-9.

   `ad`'s times grow with the number of evaluations in a process, which looks
   like garbage-collection pressure [reasoned]. So "3 runs" there means three
   processes of 2,000 evaluations each.

   **What this costs per Newton iteration.** At 20k unknowns there are about
   20k hinges. Their Hessians take 0.8 s by hyper-dual and 10–70 s by `ad`
   [reasoned from the table]. Gauss–Newton, the study's method, needs only
   gradients: 0.2 s by `ad`.

   **Fit with #62.** This is #62's approach extended one order: write the
   number by hand, make `Geometry.V3` polymorphic in its scalar, and evaluate
   one energy at `Double`, `Dual` and `HyperDual`. Its "done when" already has
   the right property test: AD against a central difference. Per-element dense
   Hessians (12 × 12, 9 × 9) are then assembled into the sparse global matrix;
   no AD ever runs over the whole mesh.

9. **Dense LAPACK through `hmatrix` works on this Mac but solves the wrong
   problem.** [ran] `hsbench` built `hmatrix` 0.20.2 against Accelerate with no
   extra install. The first cold `stack build` of the benchmark, compiling `ad`
   and `hmatrix` and their dependencies, took 11 min 24 s. Dense Cholesky took
   0.10 s at 1,000 unknowns, 0.33 s at 3,000 and 1.17 s at 6,000 (one run
   each). Memory grows as n², about 288 MB at 6,000. That is fine for
   per-element work and small studies, but not for a 20k-DOF sheet. Linux CI
   would need BLAS/LAPACK development packages (`hmatrix.cabal:151-157` asks
   for `blas lapack`); the exact apt names are UNVERIFIED.

### C. External tools, as D17 allows them

10. **Environment on this machine.** [ran] Apple M1 Max, 10 cores, 32 GiB;
    Darwin 27.2.0.
    - **Languages.** `python3` 3.14.7 (Homebrew; `python@3.11` also installed);
      `node` v26.8.1.
    - **Haskell.** `stack` 3.11.1, with GHC 9.6.7 in `~/.stack/programs`; the
      `ghc` on `PATH` is 9.10.3.
    - **Build tools.** `cmake` 4.4.3; Apple clang 21.0.0.
    - **Homebrew libraries.** `eigen` 5.0.1, `suite-sparse` 7.14.0
      (`libcholmod.5.3.5`), `openblas`, `gmp`.
    - **Blender** 4.4.1 at `/Applications/Blender.app`. Its bundled Python is
      3.11.11 with NumPy 1.26.4
      (`Blender -b --factory-startup --python-expr "import numpy, sys; …"`),
      and headless start-up took 1.6 s.
    - **A virtual environment** under the scratch directory: `python3 -m venv`
      took 5.8 s. `pip install numpy scipy ipctk` took 10.6 s and gave NumPy
      2.5.3, SciPy 1.18.1 and ipctk 1.6.0, all from wheels.

11. **ipctk: MIT, wheels everywhere we need, contact only.** [fetched
    `https://pypi.org/pypi/ipctk/json`; `gh api repos/ipc-sim/ipc-toolkit/license`
    → MIT, last push 2026-09-17]
    - **Wheels.** Version 1.6.0, uploaded 2026-07-15. There are wheels for
      CPython 3.10–3.14 on macOS arm64, manylinux x86_64 and Windows. It depends
      on `numpy` and `scipy`. Blender's bundled Python 3.11 matches the cp311
      wheel; installing into Blender is UNVERIFIED.
    - **What it provides.** Its documentation
      ([getting started](https://ipctk.xyz/tutorials/getting_started.html)) says
      it provides collision meshes, collision sets, barrier potential value,
      gradient and Hessian, and CCD step sizes. It does *not* provide
      elasticity, a time integrator or a solver. It models shell thickness
      through `dmin`.
    - **Codimensional shells.** The maintainers say the same about cloth
      ([ipc-toolkit discussion #63](https://github.com/ipc-sim/ipc-toolkit/discussions/63),
      answer of July 2022). PolyFEM "does not currently simulate shells or
      rods"; the toolkit lacks the FEM components for them.
    - **The API seen here** (1.6.0): `CollisionMesh`, `NormalCollisions.build(mesh, V, dhat, dmin)`,
      `BarrierPotential(dhat, stiffness)`, `.gradient` and
      `.hessian(…, PSDProjectionMethod.CLAMP)`,
      `compute_collision_free_stepsize(mesh, V0, V1, min_distance)`,
      `has_intersections`, and `AdditiveCCD` and `TightInclusionCCD` narrow
      phases. Also `FrictionPotential` and adhesion potentials.

12. **An envelope inflates in seconds with ipctk, strain about 1%, and IPC
    refused a start closer than the thickness.** [ran]
    `scripts/H7-tooling/pillow_ipc.py`, 217 lines, builds two n × n sheets sewn at
    their boundary: a closed paper envelope, the simplest pocket. It minimises
    this energy:
    - stretching springs at k = 1e4;
    - discrete-shells hinge bending, Gauss–Newton, with *finite-difference*
      hinge gradients (a prototype shortcut);
    - minus pressure × enclosed volume, gradient only;
    - ipctk's barrier with dmin = dhat = 1/1500.

    Newton steps are limited by ipctk's CCD, and each linear solve uses
    CHOLMOD. At pressure 1000 (illustrative units):

    | Sheet | DOF | Newton iterations | Wall | Height | Edge strain | Intersections |
    | --- | ---: | ---: | ---: | ---: | --- | --- |
    | 16 × 16 | 1,542 | 35 | 0.87 s | 0.376 | +0.98% / −1.06% | none |
    | 32 × 32 | 6,150 | 48 | 4.2 s | 0.398 | +0.93% / −1.04% | none |
    | 48 × 48 | 13,830 | 200 (cap) | 51.2 s | 0.395 | about ±1% | none; smallest gap = 1/1500 exactly |

    **Where the 32 × 32 time went:** 2.17 s assembly in NumPy, 1.21 s in linear
    solves, 0.35 s in line search, 0.17 s in CCD and 0.14 s in barrier
    evaluation.

    **The 48 × 48 run did not converge.** Its gradient norm was still 388 at the
    200-iteration cap, and CHOLMOD warned 36 times that the matrix was not
    positive definite, which a growing Levenberg shift absorbed. Leaving the
    pressure Hessian out, and wrinkling, both slow convergence [reasoned].

    **The refusal is the most useful result.** The first 32 × 32 attempt
    started the two sheets `0.02·sin(πu)·sin(πv)` apart. Near the corners that
    is 3.84e-4, less than the 6.67e-4 thickness (`scripts/H7-tooling/init_gap.py`). The
    barrier's Hessian was then undefined, and ipctk raised "unable to project
    matrix onto positive semi-definite cone". The same happens to any folded
    state whose layers start closer than dmin (finding 2). A `sqrt` bump
    (smallest initial gap 0.0092) ran cleanly.

    Two runs of the 16 × 16 case wrote byte-identical OBJ files (SHA-256
    prefix `d3bcbedafb580e80`).

13. **Starting flat and folding with thickness works, but coarse meshes
    exaggerate the crease.** [ran] `scripts/H7-tooling/fold_ipc.py` takes a flat
    16 × 16 sheet, 867 DOF, which is trivially an admissible start. It turns
    the rest angle of the crease `u = 1/2` in 18 increments, one static Newton
    solve each, with the same energies, no pressure, and crease stiffness 0.1.

    **To a target of 178°:** 9.1 s and 938 Newton iterations in total. The
    crease reached 178.0°, edge strain stayed below 1.4e-13, and contact never
    engaged: the closest layers were 0.0022 apart.

    **To a target of 179.99°:** the barrier stopped the crease at
    179.24°–179.39°. The layers sit exactly one thickness apart (smallest
    distance 6.6667e-4), panels bend by up to 2.96° next to the crease, and
    strain stays at or below 6.2e-5. There is no intersection. Nobody
    prescribed a fillet; the paper made room for its own thickness by bending.

    **But it took 342 s** for 970 iterations, averaging 54 per increment against
    a cap of 60. The barrier stiffness was a fixed 1 at dhat = 1/1500, and IPC
    implementations adapt it (ipctk exports `initial_barrier_stiffness` and
    `update_barrier_stiffness`) [fetched API listing via `dir(ipctk)`].

    **And at this resolution the crease radius is set by the mesh, not the
    paper.** The triangles are 1/16 = 0.0625 wide, about 94 thicknesses. So the
    flaps splay: they end 0.058 apart at the far edge, per the printed
    cross-section. A physically sized crease needs elements of a few
    thicknesses near every crease [reasoned]. Gomez-Nogales et al. 2025 report
    the opposite failure at *fine* resolution: neighbouring elements of a
    thickened shell lock against each other
    ([arXiv:2510.10256](https://arxiv.org/abs/2510.10256), abstract; no code
    stated).

    **The double fold did not happen.** `fold_ipc_log.py 8 double 179.99`
    (8 × 8, 243 DOF) first folds the sheet in half. It then turns the crease
    `v = 1/2` of the two-layer packet, so the outer layer must wrap the inner:
    G finding 5a's counterexample.
    - **Result.** The first fold reached 179.69°. The second crease reached
      only ±0.77° of its 180° target after 36 increments, 1,876 Newton
      iterations and 622 s. Every second-fold increment hit the 60-iteration
      cap with about 194 active contact stencils.
    - **What was checked.** The two layers' rest angles have opposite signs,
      because the upper layer lies upside down (AGENTS.md, "Creasing is about
      faces"). By the argument in `fold_ipc.py`'s comment, both layers then
      turn the same way, so a sign conflict is not the obvious cause.
    - **What was not.** Whether the cause is untuned barrier stiffness, a mesh
      too coarse for the outer layer to bend round the inner, or a missing
      sliding freedom is UNVERIFIED.
    - **The CCD choice mattered.** The first attempt used ipctk's default
      narrow phase, Tight Inclusion CCD (tolerance 1e-6, `max_iterations`
      10,000,000). A 16 × 16 run was stopped after 45 minutes without finishing. An
      8 × 8 run spent over 10 minutes on the single increment where the layers
      first touched; macOS `sample` showed it inside `ticcd::edgeEdgeCCD`. With
      `AdditiveCCD` the same 8 × 8 increment took 3 s. Flat-stacked layers
      sliding parallel at distance dmin are the slowest case for that CCD, and
      they are origami's everyday case [ran; reasoned].

14. **Blender inflates the envelope too, but as a dynamic cloth, and its
    licence reaches scripts, not outputs.** [ran; fetched]
    - **The model.** Blender's cloth is "simulated with virtual springs that
      connect the vertices" (manual source,
      `manual/physics/cloth/introduction.rst`, projects.blender.org raw, fetched
      2026-09-28). Its pressure option simulates a filled soft shell, and
      non-manifold meshes "will work … however, pressure will escape out of the
      mesh holes" and cause drift (`physical_properties.rst`, Pressure section).
      A crane body and a waterbomb are open pockets. Both Blender and the ipctk
      prototype, whose volume formula assumes a closed surface, need an
      explicit, non-physical cap to measure volume. #106's approach step 4
      already forbids letting that cap become paper.
    - **The runs.** `scripts/H7-tooling/blender_pillow.py` imports the same 32 × 32
      envelope as OBJ, adds a Cloth modifier with pressure and self-collision
      (`self_distance_min = 1/1500`), steps frames headless, and exports the
      result.

      | Tension stiffness | Pressure | Frames | Sim time | Height | Edge strain |
      | ---: | ---: | ---: | ---: | ---: | --- |
      | 15 (default) | 5 | 60 | 2.0 s | 0.515 | +8.3% / −7.8% |
      | 1,000 | 5 | 60 | 4.7 s | 0.174 | +0.15% / −0.33% |
      | 1,000 | 50 | 60 | 2.8 s | 0.564 | +9.6% / −23.9% |
      | 10,000 | 50 | 60 | 6.3 s | 0.180 | +0.16% / −0.34% |
      | 10,000 | 50 | 240 | 23.0 s | 0.428 | +0.16% / −0.34% |
      | 10,000 | 200 | 240 | 25.8 s | 0.646 | +0.33% / −0.73% |

      The height depends on how many frames ran, because this is motion, not a
      resting shape. Default cloth stretches 8%.
    - **Import quirk.** The OBJ importer kept 4,094 of 4,096 faces. The
      envelope's two corner triangles exist on both sheets with the same three
      vertices, and Blender dropped the duplicates. Coincident layers built
      from distinct vertices, as senbazuru writes them, are not affected.
    - **Determinism.** Three identical runs wrote byte-identical OBJ files
      (SHA-256 prefix `0bbdede7aeb6532b`).
    - **Licence.** Blender is GPL-only (`COPYING`, via `gh api` of the mirror).
      Its licence page says renders and other output belong to the user, and
      that scripts using its Python API must be "GPL compliant" if published
      ([blender.org/about/license](https://www.blender.org/about/license/)).
      MIT is GPL-compatible, so an MIT `bpy` script in the repository appears
      permissible. That is a reading, not legal advice, and an owner decision.
    - **Rendering.** Cycles rendered each envelope and the `spread-0` GLB at
      800 × 600, 64 samples, in 1.7–4.2 s (`blender_render.py`). The GLB import
      kept all 896 triangles, the 448 faces written twice for two sides. Smooth
      shading across every edge made the crane blotchy, which is PRD 08's M7a
      argument for splitting normals at feature edges, seen again.

15. **Mitsuba 3 installs and renders, but adds nothing Blender lacks for this
    use.** [fetched PyPI; ran] Its licence text is 3-clause BSD in form, which
    GitHub's detector reports as `NOASSERTION`. There are wheels for CPython
    3.9–3.14 on macOS arm64, version 3.9.1. It installed in 5.7 s and rendered
    the envelope at 400 × 300, 32 samples, in 0.2 s (`scalar_rgb`). Its LLVM
    variant failed to initialise ("LLVM API initialization failed"); the Metal
    variants are listed. It is scriptable in Python, reproducible and
    permissive. Its advantage over Blender is differentiable rendering, which
    this project does not need [reasoned].

16. **The rest of the field, checked for licence and whether it runs here.**
    [fetched `gh api repos/…` and PyPI JSON, 2026-09-28]

    | Tool | Licence | Runs on this Mac? | Verdict for senbazuru |
    | --- | --- | --- | --- |
    | PolyFEM | MIT | wheels not checked | no shells (finding 11) |
    | Codim-IPC | Apache-2.0; last push 2023-01-29 | no, as-is: `cmake_minimum_required(VERSION 3.2)`, and CMake 4.4.3 refuses anything below 3.5 [ran on a two-line project]; `build_Mac.py` calls `g++-11` (not installed); needs Kokkos, Cabana, TBB, AMGCL and SuiteSparse (`CMakeLists.txt:9-56`), linking GPL CHOLMOD by default (D17) | reference for shells + IPC; building it is its own project |
    | libigl / Python bindings | MPL-2.0 core; the repositories also carry `LICENSE.GPL`, so GitHub reports GPL-3.0; the wheel's classifier says MPL-2.0 | wheels cp39–cp312 arm64 | geometry utilities only; check which modules a wheel links before relying on it |
    | Origami Simulator | MIT | browser app | `?model=FILE` selects only a bundled demo (`js/main.js:67-75`); driving it headless needs browser automation, UNVERIFIED; no collision (G finding 10) |
    | libuipc | Apache-2.0 | no: CUDA only, wheels for Linux and Windows (README) | not here |
    | NVIDIA Warp | Apache-2.0 | macOS arm64 wheel (1.17.0) | cloth in Python; not evaluated |
    | MuJoCo | Apache-2.0 | macOS arm64 wheels (3.14.0) | not evaluated for shells |
    | scikit-sparse | BSD-2-Clause wrapper | sdist only; built in 52.7 s against Homebrew SuiteSparse | see finding 17 |
    | YASPS (SIGGRAPH 2026) | — | JIT-compiles CUDA kernels (arXiv:2605.23088 abstract) | not here |

17. **CHOLMOD's licence is per module, and the Homebrew build uses the GPL
    part.** [fetched `CHOLMOD/Doc/License.txt` via `gh api`; ran]
    - **The split.** CHOLMOD's `Check`, `Cholesky`, `Utility` and `Partition`
      modules are LGPL-2.1+. `Supernodal`, `MatrixOps`, `Modify`, `Demo`,
      `MATLAB` and `Tcov` are GPL-2+.
    - **What ran.** At 13,830 DOF the prototype's failure trace named
      `CHOLMOD/Supernodal/t_cholmod_super_numeric_worker.c`. So the Homebrew
      build ran the GPL supernodal code, even though scikit-sparse reported
      simplicial factors on the smaller benchmark matrices (`is_super=False`).
    - **Consequence for Haskell.** A Haskell FFI to Homebrew's CHOLMOD would
      link GPL code. That is acceptable for a user-installed oracle, not for the
      library.
    - **Eigen** is MPL-2.0 including its AMD ordering. Its `Amd.h` says Davis
      licensed the CSparse-derived code to Eigen under MPL-2.0 (GitLab master,
      fetched). So an FFI shim to Eigen's `SimplicialLDLT` would be
      licence-clean, but it would add a C++ toolchain to the build. Finding 7
      makes that unnecessary.

### D. Interchange, determinism and CI

18. **FOLD with material coordinates is already the interchange format, and it
    survives GLB.**
    - **The write side.** [code] The study writes a settled surface with
      `materialFrame`, which adds `senbazuru:material_coords`, one [u, v] per
      vertex (`src/Senbazuru/Origami/Surface.hs:248-252`). The crane files also
      carry `senbazuru:source_panels` and `senbazuru:source_edges` (the
      `before.fold` keys, [ran]).
    - **The read side.** `surfaceFromFrame` reads the key back and refuses a
      wrong count (`Surface.hs:179-195`).
    - **GLB.** `Render.Gltf` keeps exactly those three keys in its stored frame
      (`Gltf.hs:241-242`).
    - **For an external tool,** this means the round trip is: write FOLD with
      material coordinates, have the tool read positions and faces, move
      vertices only, and write positions back under the same ids. The existing
      Haskell checks and renderers then read the result as they read any
      settled surface. OBJ drops everything except positions and faces, and can
      merge faces (finding 14), so it should only ever be a viewer format.

19. **External outputs are deterministic on one machine; nothing says they are
    across machines.** [ran; reasoned]
    - Blender (3 runs) and the ipctk prototype (2 runs) each reproduced their
      bytes exactly on this machine.
    - Whether results match across machines is UNVERIFIED. In general they do
      not: BLAS, thread counts, CPU instruction sets and tool versions all
      change floating-point results [reasoned].
    - Goldens must therefore never be external outputs. That already follows
      from D17's "no CI job or test depending on it". It also makes any
      external result a *fixture* with provenance in `examples/README.md`, not
      a regenerated artefact.

20. **CI today has room for in-repo Haskell work, not for external tools.**
    [code `.github/workflows/ci.yml`]
    - **The jobs.** Three jobs (`test`, `format`, `lint`) run on
      `ubuntu-latest`, behind a `changes` gate that skips `PRDs/`-only pull
      requests.
    - **Non-Haskell code already runs in CI.** `node` runs two in-repo study
      checks, `check-illustration-metrics.mjs` and `check-paper-lighting.mjs`.
      So in-repo JavaScript is precedent; external programs are not (D17).
    - **The test budget.** #208 measured the suite at 626 s (PRD 07). D15 caps
      default-CI settles at 392 refined triangles.
    - **Could Python run there?** ipctk's manylinux wheels would make a
      Python oracle installable on a runner in seconds [fetched PyPI], but D17
      forbids depending on it.
    - **Dependency cost.** Adding `ad` or `hmatrix` to the library would cost a
      cold-cache CI build of minutes: 11 min 24 s here for the benchmark's
      dependencies, a single run, not measured on a runner. `hmatrix` would
      also need system BLAS/LAPACK.

### E. Architecture fit

21. **A simulation back end plugs in at `Material.Settle.settle`, and only a
    pure one can.** [code; prd]
    - **The contract.** PRD 07 fixes
      `settle :: SettleInput -> Surface V2 -> Either SettleError Settled`
      (PRD 07 "SettleSpec and SettleInput: two contracts"; PRD 01 §2.3). PRD 01
      places `Numeric.*` at row 2, importing only `Geometry.*` and `Explain`,
      and `Material.*` at row 5.
    - **Only `Fold.Load` does I/O** (`docs/architecture.md`, "Layering rules").
      So a back end that runs a subprocess cannot be a `Material.*` function.
      It can live in only three places:
      - (a) the study executable, which already does file I/O;
      - (b) `app/`, behind a flag;
      - (c) a separate tool the user runs, whose FOLD output is then read as a
        fixture.
    - **D17** makes (c) the only option that needs no new decision: an oracle
      with provenance, never ahead of the in-repo path. D14 rejects
      "substituting … an external solver on failure".
    - **The contract itself is solver-neutral.** An IPC back end fits
      `settle`'s type unchanged [reasoned]. But three of `SettleInput`'s
      assumptions change underneath it:
      - **`contact :: [(FaceId, FaceId)]`.** Directional pairs are
        meaningless to an unsigned-distance barrier. It needs dmin instead,
        which today is "stored, not interpreted" (D14).
      - **The start.** `recordBefore` must be flat (`SettleStartNotFlat`), and
        a flat folded stack is not admissible for IPC (finding 2).
      - **Loads.** Pressure has no field at all. D18 lists "pressure or
        inflation (#106)" and "thickness as geometry" as non-goals.

22. **The start problem argues for path-following, which D14 currently
    forbids.** [reasoned from findings 2, 3 and 13; D14]
    - **The only admissible starts found** are the flat sheet and states reached
      from it with the barrier on. So a thick material state has to be carried
      forward move by move: settle(k) starts from settle(k−1), with the rigid
      record as the target it is pulled towards.
    - **Two constraints collide with that.** D14 says settled geometry "never
      enters … a later step". And the study's prescribed sketches (finding 1)
      were used as *initial guesses*, which a barrier method cannot accept.
    - **The resolution I propose:**
      - Keep the rigid run authoritative for every diagram and every later
        rigid step, exactly as D14 says.
      - Add an optional *material track*, a second sequence of states that only
        illustrations read.
      - Use sketches such as `spread-0` as soft *targets* (an energy pulling
        towards them), never as starts.

      This is an owner decision.
    - **Where I disagree with G.** G implication 6 ordered the work "thickness,
      then contact". The measurements say thickness *is* contact here. A
      thickness offset computed separately from the barrier fails at the wraps
      (finding 3), while a barrier with dmin produces the offset as it folds
      (finding 13). The two are one step. That held for one fold. The second
      fold stalled, so "one step" is also where the open research is.

23. **What must stay in Haskell for the learning goal, and what need not.**
    [reasoned from AGENTS.md "clarity over cleverness", issue #62, D15, D17]

    **Stay in Haskell, because that is where the understanding lives:**
    - the energies: stretching, bending, crease, pressure;
    - their derivatives, by hand-written duals and hyper-duals;
    - the Newton loop, line search and verdicts;
    - the distance functions and barrier;
    - the ordering and factorisation (finding 7 shows these are tractable);
    - the checks that accept or refuse a result.

    **May stay outside:**
    - a *second opinion* on intersections and distances: ipctk's
      `has_intersections`, as an oracle;
    - photoreal rendering for review images: Blender Cycles or Mitsuba, as
      viewers of GLB;
    - the exploratory prototypes that decide *which* method is worth
      reimplementing.

    **Should not:** an external solver whose output becomes the published
    illustration. It hides failure (PRD 07 "Rejected alternatives", citing B finding 16), it cannot run in CI, and it
    teaches nothing the project keeps.

## Implications for senbazuru

A staged path, each stage one or a few PRs, each with a stated exit test.
Effort: S ≈ a day or two; M ≈ a week; L ≈ several weeks; XL ≈ a month or more
of focused work.

**Stage 0 (S): decisions before code.**
- **Decisions.** The owner rules on:
  - D18's non-goals "pressure or inflation" and "thickness as geometry";
  - D14's "settled geometry never enters a later step", versus a material
    track that only illustrations read;
  - whether an MIT Python prototype under `study/` is acceptable. It is outside
    CI, like the existing `study/gltf/generate.py`.
- **Paperwork.** Add rows to `docs/related-projects.md` for ipctk (MIT, as
  built from PyPI wheels), SciPy (BSD-style licence text on PyPI), scikit-sparse (BSD-2, linking
  LGPL/GPL CHOLMOD as Homebrew builds it) and Blender (GPL; outputs ours), per
  D17.
- **Exit.** The decisions are recorded in `PRDs/decisions.md`.

**Stage 1 (M): an external prototype harness, as an oracle.**
- **The harness.** `study/sim-prototype/` (Python, MIT) generalises
  `pillow_ipc.py` and `fold_ipc.py`.
  - It reads FOLD with `senbazuru:material_coords` and writes the same ids
    back (finding 18).
  - Its inputs mirror `SettleInput` field for field, plus `thickness` and an
    optional `pressure` with an explicit cap.
  - It replaces finite-difference hinge gradients with analytic ones.
  - It adapts barrier stiffness.
- **Fixtures it should run:** first, and as a go/no-go test, the double fold
  (G 5a's 200%-stretch counterexample), which stalled in finding 13; then the
  quarter fold; the waterbomb base; the crane wing with the
  body held (to compare with the accepted 392/1,192-triangle solves); and the
  pillow envelope.
- **What it answers:**
  - Does path-following with thickness reach recognisable states?
  - How fine must the mesh be near creases?
  - What does pressure need?
  - What does each cost?
- **Exit.** A note in `docs/notes/` with measured answers, and the same FOLD
  outputs readable by `render` and `export`.
- **No-go branch.** Try adaptive barrier stiffness, a finer mesh near the
  crease, smaller increments and Additive CCD. If the double fold still cannot
  be made to fold, Stages 4–5 do not start. The project then keeps the penalty
  study and the owner's drawing-scale tolerances, and uses Stages 2–3 only to
  make those solves faster.
- **Risk.** Scope: this is where the study's 30 PRs of pair repairs went. Cap
  it at the listed fixtures.

**Stage 2 (M): `Numeric.Sparse` in Haskell, replacing `SparseSolve`.**
- **Contents.** An up-looking LDLᵀ over unboxed vectors, as in finding 7, plus
  an ordering: AMD ported from the published algorithm (BSD-3 source
  available), or material-coordinate nested dissection with a proper
  separator.
- **Placement.** It sits at PRD 01 row 2, which D15 stage 2 already reserves.
- **Exit.**
  - A property test that `solve (factor A) b` has a small residual on random
    sparse SPD matrices.
  - A study run whose settles are unchanged within tolerance.
  - The CHOLMOD comparison kept as an oracle script (not CI).
- **Target.** At most 0.3 s at 6,912 unknowns (measured 0.27–0.29 s with AMD).
- **Risk.** Low. The algorithm is textbook and the measurement exists.

**Stage 3 (M): `Numeric.Dual` and `Numeric.HyperDual` (#62, extended).**
- **Contents.** Make `V3`, `Rigid` and `VectorSpace` polymorphic as #62
  scopes. Write the energies once. Assemble per-element Hessians into the
  sparse matrix.
- **Exit.**
  - #62's property test.
  - The same test for Hessians: hyper-dual against a central difference of the
    gradient, to 1e-6 relative.
  - The hinge Hessian under 50 µs (measured 39–40 µs).
- **Risk.** Type-variable spread; #62 already names it.

**Stage 4 (L–XL): an IPC-style `Material.Contact` in Haskell.** Only if Stage 1's
go/no-go passes.
- **Contents.**
  - Point–triangle and edge–edge distances, with their derivatives from Stage 3.
  - The log barrier with a dmin offset.
  - Additive CCD (Li, Kaufman & Jiang 2021, published; ipctk ships
    `AdditiveCCD`).
  - A uniform-grid broad phase.
  - Energy-based projected Newton with a CCD-limited line search.
- **Ideas and code.** ipc-toolkit is MIT, so its code *may* be read, and
  copied with attribution. The learning goal argues for reimplementing from
  the papers.
- **Exit.**
  - On Stage 1's fixtures, the Haskell states match the Python oracle's within
    a declared tolerance (for example RMS vertex distance under 1% of the
    thickness).
  - Every accepted state has no intersection by the in-repo check, confirmed by
    ipctk.
  - The smallest gap is at least 0.99 × thickness.
- **Risk.**
  - Performance of the broad phase and of CCD in Haskell (unmeasured).
  - Barrier stiffness tuning (finding 13 took 342 s untuned).
  - The choice of CCD: Tight Inclusion stalled on flat-stacked layers where
    Additive CCD took 3 s (finding 13).
  - Mesh resolution near creases (finding 13).

**Stage 5 (L): path-following settle and the material track.**
- **Contents.** `Material.Settle` gains a start choice: `FromRecordBefore` (the
  current penalty route, kept) or `FromMaterialState` (the carried track). It
  also gains optional loads: target attraction to a prescribed sketch, and
  pressure with a declared cap.
- **Order.** Waterbomb base, then crane wing spread, then crane body opening,
  then waterbomb inflation.
- **Exit.** `whole-crane`-style galleries whose `checks.json` reports zero
  crossing pairs, local strain under the owner's 0.1% screen or a declared
  looser one, and `inflationSimulated: true` only where pressure actually ran.
- **Risk.**
  - Finding a folding path through the crane's layers at all.
  - Whether illustrations from a material track can drift from the rigid
    figures they sit beside.

**Stage 6 (S–M): rendering hand-off.**
- **Contents.** The repository keeps PRD 08's M7a (normals split at feature
  edges) and W1 lines on the settled meshes. `study/render/` may add MIT
  `bpy` and Mitsuba scripts that turn a settled GLB into review images at fixed
  cameras.
- **Rule.** Those images are never goldens and never published as the
  project's drawing.

**Option B, not recommended: keep an external back end.**
- **What it would take.** Amend D17 so an external settle may produce a
  published illustration, checked by the in-repo verdict.
- **Cost.** Stages 2–5 become S–M, and Stage 1 becomes the product.
- **What is lost.** The learning goal; CI coverage; reproducibility across
  machines; and the licence clarity, since Homebrew CHOLMOD is GPL.
- **When it makes sense.** Only if the owner values the picture now over
  understanding it.

## Acceptance ideas

These are "refined" on the tooling axis, as properties a script can check.
Other slices own the look.

| Check | Today (`spread-0`) | Proposed bar | Turns red when |
| --- | --- | --- | --- |
| Crossing triangle pairs, in-repo check | 345 | 0 | any accepted state intersects |
| Same, ipctk `has_intersections` (oracle, local only) | True | False | the two checkers disagree, or both find a crossing |
| Smallest gap between non-neighbouring elements | 6.8e-27 | ≥ 0.99 × declared thickness | the barrier or the thickness offset is bypassed |
| Largest principal strain in any triangle | +106.8% / −83.6% | ≤ 0.1% (the owner's screen) or a declared looser value, stated in the output | a sketch is passed off as paper |
| Achieved crease angles against declared targets | not reported for the sketch | within a declared tolerance, reported per crease | a target is silently missed |
| Settle cost (refined triangles, Newton iterations) | 247.8 s to build nine sketches, no solve | counted budgets as D15 requires; wall time recorded over 3–5 runs | a budget is exceeded |
| Rerun on one machine | — | byte-identical FOLD and GLB | nondeterminism enters (for example parallel assembly order) |
| Haskell against the prototype oracle | — | RMS vertex distance < 1% of thickness on Stage 1 fixtures | the reimplementation drifts |
| Factor time at 6,912 unknowns | 99.4 s (`SparseSolve`) | ≤ 0.3 s | the ordering regresses |
| Hinge Hessian | hand-derived gradients only | ≤ 50 µs, matches central differences | a derivative is wrong or slow |

## Sources fetched

All fetched 2026-09-28.

- **Python packages** (PyPI JSON):
  - `https://pypi.org/pypi/ipctk/json`: MIT per repository; wheels cp310–cp314.
  - `https://pypi.org/pypi/mitsuba/json`: 3.9.1; BSD-style licence text in the
    repository.
  - `https://pypi.org/pypi/libigl/json`: 2.6.3; MPL-2.0 classifier.
  - `https://pypi.org/pypi/scikit-sparse/json`: BSD-2-Clause; sdist only.
  - `warp-lang` (Apache-2.0), `mujoco` (Apache-2.0), `pyuipc`, `pypbd` (MIT),
    `polyfempy`, `taichi`.
  - `numpy` (BSD-3-Clause AND 0BSD AND MIT); `scipy`; `trimesh` (MIT).
- **Haskell packages:**
  - Hackage `.cabal` files and upload times for `ad`, `hmatrix`,
    `hmatrix-gsl`, `hmatrix-sparse`, `sparse-linear-algebra`, `massiv`,
    `eigen`, `sparse`, `sparse-lin-alg`, `conjugateGradient`, `linear`,
    `vector`, `backprop`, `lapack`, `comfort-array`, `ipopt-hs`,
    `moonlight-linalg`, `dual`, `sparse-tensor`.
  - Hackage search API for "sparse", "cholesky" and "suitesparse".
  - Stackage `lts-22.44/cabal.config`.
- **Haskell documentation:**
  - `Numeric.AD` docs for `ad-4.5.6`.
  - `Numeric.LinearAlgebra` docs for `hmatrix-0.20.2`.
- **GitHub, via `gh api` (licence field, `pushed_at`, files):**
  - `ipc-sim/ipc-toolkit` (MIT), `ipc-sim/Codim-IPC` (Apache-2.0; `README.md`,
    `build_Mac.py`, `CMakeLists.txt`), `ipc-sim/IPC` (MIT).
  - `polyfem/polyfem` (MIT), `polyfem/polyfem-python` (MIT).
  - `libigl/libigl` and `libigl/libigl-python-bindings` (`LICENSE.GPL` and
    `LICENSE.MPL2`; `pyproject.toml`).
  - `amandaghassaei/OrigamiSimulator` (MIT; `js/main.js`).
  - `mitsuba-renderer/mitsuba3` (`LICENSE`), `mitsuba-renderer/drjit`
    (BSD-3-Clause).
  - `blender/blender` (`COPYING`).
  - `NVIDIA/warp` (Apache-2.0), `spiriMirror/libuipc` (Apache-2.0; `README`).
  - `InteractiveComputerGraphics/PositionBasedDynamics` (MIT),
    `zzhuyii/OrigamiSimulator` (no licence), `google-deepmind/mujoco`
    (Apache-2.0), `taichi-dev/taichi` (Apache-2.0).
  - `KhronosGroup/glTF-Validator` (Apache-2.0), `mikedh/trimesh` (MIT),
    `pyvista/pyvista` (MIT), `pmp-library/pmp-library` (MIT).
  - `scikit-sparse/scikit-sparse` (`LICENSE.txt`, BSD-2).
  - `DrTimothyAldenDavis/SuiteSparse`: `CHOLMOD/Doc/License.txt`,
    `AMD/Doc/License.txt`, `LDL/Doc/License.txt`.
  - `edemaine/FOLD` (`doc/spec.md`).
- **Other web pages:**
  - Eigen, GitLab master: `Eigen/SparseCholesky` and
    `Eigen/src/OrderingMethods/Amd.h` (MPL-2.0).
  - [ipctk getting started](https://ipctk.xyz/tutorials/getting_started.html).
  - [ipc-toolkit discussion #63](https://github.com/ipc-sim/ipc-toolkit/discussions/63).
  - [Blender licence page](https://www.blender.org/about/license/).
  - Blender manual source, raw from projects.blender.org:
    `physics/cloth/introduction.rst`, `settings/physical_properties.rst`,
    `settings/shape.rst`. docs.blender.org returned HTTP 403.
  - arXiv abstracts:
    [2510.10256](https://arxiv.org/abs/2510.10256) (Gomez-Nogales, Chen,
    Martin, Garces & Kaufman, "Unlocking Thickness Modeling for Codimensional
    Contact Simulation", 2025) and
    [2605.23088](https://arxiv.org/abs/2605.23088) (Tang, Huang, Bernstein, Li
    & Li, "YASPS", SIGGRAPH 2026).
- **Repository issues:** `gh issue view 62` and `gh issue view 106`.

## Open questions

- **Inflation and thickness.** Will the owner lift D18's "pressure or
  inflation" and "thickness as geometry" non-goals for illustration-only
  outputs? Without that, Stages 4–5 have no home.
- **A material track.** May an illustration-only material state be carried
  from move to move (finding 22)? Or must every settle start from its own
  record, which rules out barrier methods for folded starts?
- **What prototypes may look like.** Is an MIT Python prototype under `study/`
  acceptable, outside CI, as `study/gltf/generate.py` already is? Or must
  prototypes live outside the repository, with only their FOLD outputs
  vendored as fixtures?
- **Mesh resolution near creases.** How fine must it be before the crease
  radius comes from the thickness rather than the mesh (finding 13)? Is
  adaptive refinement along creases, which `refineSelectedSurfaceWithEdges`
  half-supports, the answer, or a display-scale thickness declared as
  exaggeration (G finding 7)?
- **What pressure means for an open pocket.** An explicit cap face that is not
  paper, a volume target measured through a declared opening, or a controlled
  opening distance first, as #106 prefers?
- **A Blender script licence.** Does a `bpy` script in the repository, licensed
  MIT and used only to make review images, meet the owner's reading of
  "GPL compliant" on Blender's licence page?
- **Why did the double fold stall** (finding 13)? The candidates are barrier
  stiffness, mesh coarseness at the crease and missing sliding freedom. This
  is the question Stage 1 exists to answer.
- **Which ordering to write.** AMD, a port of a published algorithm with
  BSD-3 source, or material-coordinate nested dissection, more original but
  2.7–3.5× more fill as first written?

## Unverified

- **Cross-machine determinism** of Blender, ipctk and CHOLMOD results. Only
  same-machine reruns were checked. The check is to run on a Linux x86_64
  runner and compare.
- **Installing ipctk into Blender's bundled Python 3.11** (cp311 wheel). Not
  attempted.
- **Whether the `eigen` Hackage bindings build on GHC 9.6.** Not attempted.
- **Linux package names** for `hmatrix`'s BLAS/LAPACK on `ubuntu-latest`. Not
  checked.
- **Driving Origami Simulator headless** through Playwright or Puppeteer. Not
  attempted: no browser download was made.
- **The cost of Haskell broad-phase and CCD code** (Stage 4). Nothing was
  measured.
- **Extrapolations.** The 2–4 s figure for a 20k-unknown AMD-ordered Haskell
  factor, and the per-iteration Hessian costs at 20k hinges, are extrapolated
  from the measured sizes, not measured at 20k.
- **Single runs.** `SparseSolve`'s timings and the dense `hmatrix` timings are
  single runs, against the repository's rule of 3–5 runs. `SparseSolve` at
  6,912 unknowns took 99 s per run; repeating it would not change the
  conclusion by orders of magnitude.
- **Study-mesh estimates.** The mapping from the study's 392 and 1,192
  triangles to about 600–1,800 unknowns assumes about half as many vertices as
  triangles and ignores holds.
- **Prototype energies** are illustrative, as the study's are. The springs
  (1e4), bending (1e-3), crease (0.1) and pressure (1000) are not calibrated
  paper values. The prototype's hinge gradients are central differences, not
  analytic. Heights and strains compare tools, not paper.
- **Licence readings** (Blender scripts, LGPL/GPL CHOLMOD modules, MPL-2.0
  Eigen, libigl's split licence) are readings of the fetched texts, not legal
  advice.
- **The Tight Inclusion stall's location** comes from one macOS `sample`
  snapshot of the 8 × 8 run; the 16 × 16 run was not sampled.
- **The Codim-IPC build** on this Mac was not attempted beyond confirming that
  its CMake minimum version is refused by CMake 4.4.3. With
  `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`, GCC 11 and its dependencies it might
  build.
- **Papers.** IPC (Li et al. 2020), C-IPC and additive CCD (Li, Kaufman & Jiang
  2021) were not re-fetched here; G fetched their project pages. Only the
  abstracts of arXiv:2510.10256 and arXiv:2605.23088 were read.

## Artefacts

All in `scripts/H7-tooling/` beside this note. None is in the repository.

| File | What it is |
| --- | --- |
| `ipc_check.py` | ipctk intersection and distance check of FOLD files (finding 2) |
| `offset_start.py` | naive layer offsets from `faceOrders`, checked with ipctk (finding 3) |
| `hsbench/` | stack project, `lts-22.44`: `SparseBench.hs` (the study's `SparseSolve`, copied), `LdlBench.hs`, `AdBench.hs`, `HyperBench.hs`, `DenseBench.hs`; `mats/` holds the triplet matrices and AMD orders (findings 5–9) |
| `sparse_compare.py`, `eigen_ldlt.cpp` | SuperLU, CHOLMOD and Eigen on the same matrices (finding 7) |
| `pillow_ipc.py`, `init_gap.py`, `run_N*.json` | envelope inflation with ipctk and its logs (finding 12) |
| `fold_ipc.py`, `fold_ipc_log.py`, `fold_half_N16*.obj`, `n8/double_N8.*`, `n8/fold_double_N8.obj` | folding from flat with thickness, single and double (finding 13) |
| `blender_pillow.py`, `blender_N32_*.json`, `blender_render.py`, `*.png` | Blender cloth runs and Cycles renders (finding 14) |
| `mitsuba_smoke.py`, `mitsuba_pillow.png` | Mitsuba 3 smoke render (finding 15) |
| `wc/whole-crane/` | the whole-crane gallery regenerated from the committed fixture (finding 1) |
