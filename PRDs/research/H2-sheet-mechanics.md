# H2. Sheet mechanics, finite elements and mesh modelling for folded paper

Researcher slice H2, written 2026-09-28 against `main` at `83fc960`. Nothing in
the repository was modified. Web pages and papers were fetched on 2026-09-28.
Two small scripts were run; they sit beside this note in
`scripts/H2-sheet-mechanics/` and every number they produced is quoted with the
command. This slice builds on [research G](G-realistic-rendering-and-simulation.md),
findings 6-13, and cites it as "G*n*" rather than repeating it.

> **Verification, 2026-09-28.** [V](V-verification.md) re-checked this note.
> Corrections: the study's panel hinge weight `P` corresponds to a plate
> stiffness `D` of about 2`P` (up to 5.8`P` across right-triangle diagonals),
> so finding 2's γ values and kami-matching weight are about 2× off: γ ≈
> 5.8e2…5.8e8, the matching weight ≈ 0.85–1.4e7, the last stage 7–12× kami
> (kami still lies between stages 3 and 4; L* is unaffected). Finding 3's
> Hessian split is Tamstorf & Grinspun eq. 3 in §2, and the Gauss–Newton remark
> credits Fröhlich and Botsch. Finding 7's virgin die-crease L* spans
> 1.6–133 mm. Finding 10's GitHub search command was malformed; a correct one
> also finds nothing. Finding 11: Sim-FAST and Sim-FAST-PY declare CC BY 4.0;
> only SWOMPS is unlicensed. **R4's thickness-offset start** is ruled out for
> heights alone ([X3](X3-crane-opening.md), [H3](H3-contact.md) finding 18);
> R2's symmetric membrane is the wrong model where paper gathers
> ([H4](H4-inflation.md) finding 4, [X2](X2-inflating-paper.md)).
> [PRD 11](../11-prd-refined-final-forms.md) decides both. Summary point 3 and
> finding 13's claim that locking explains the crane's false creases is
> **refuted** by [Y3](Y3-locking.md): the construction makes them; locking costs
> up to a few pixels where curvature runs across mesh lines, and one refinement
> mostly cures it.

**Evidence tags.** `[code]` a repository file read at the lines given;
`[ran]` a command actually run; `[fetched]` a page or PDF fetched on
2026-09-28; `[paper]` a paper whose text was read (always also fetched);
`[reasoned]` derived here. Anything else is listed under
[Unverified](#unverified).

**Words used throughout.** A *membrane* energy charges the sheet for
stretching or shearing within its own surface. A *bending* energy charges it
for curving. The *bending stiffness* `B = E t³ / 12(1 − ν²)` of a sheet of
Young's modulus `E`, Poisson ratio `ν` and thickness `t` is the moment per unit
width needed per unit curvature (N·m). The *stretching stiffness* is
`Y = E t` (N/m). A *crease* is a pressed fold line; a *panel* is the paper
between creases ([glossary](../../docs/glossary.md)). A *rest angle* is the
angle a crease returns to when nothing loads it. The *Hessian* is the matrix of
second derivatives of an energy; *Newton's method* uses it to jump towards a
minimum, and a *line search* shortens that jump until the energy actually
drops. A *barrier* is an energy that grows without bound as a distance goes to
zero. *CCD* (continuous collision detection) asks whether two triangles cross
anywhere along a motion, not just at its ends.

## Summary

The material study already *is* a discrete-shell model in everything but
name: hinge bending on a triangle mesh, crease springs with rest angles, exact
grips and a barrier contact. What makes its crane look unrefined is not a
missing finite-element theory. It is four specific things, each checkable:

1. **The chosen crane shape is not paper by construction.** The "More tucked"
   body maps material across the wings at half width, a 50% compression written
   into the target, and fills the rest by a linear smoothing that does not keep
   lengths (finding 4). No solver can make that shape paper.
2. **Opened shapes are solved from guesses, not reached along a path.** Every
   crane body attempt started from a prescribed, intersecting pose (finding 4).
   The tools that open real folded sheets (IPC, MERLIN, SWOMPS, ARCSim) all walk
   there in small steps from a valid state.
3. **The membrane is a penalty, not a material, and it locks.** Edge springs
   stiffened to `1e8` make a nearly inextensible triangle mesh, which can bend
   only along its own edges (findings 2, 13).
4. **Display facets and sampling.** 448 flat triangles for a whole crane are
   ten times coarser than the curvature length of real paper asks for
   (findings 8, 17).

Measured paper numbers settle what "refined" should look like on a 15 cm kami
crane (findings 5-9): creases are sharp at any diagram scale (fold radius
0.36 px at 600 px per sheet). Panels longer than 11-16 mm bend smoothly
instead of reopening their creases. A smooth pillow body needs about 3%
compression, so real paper forms ridges and crimps instead. Gravity is on the
edge of visible.

The recommended stack is the study's own energy with physical parameters and
a real membrane, an unsigned thickness barrier, and a Newton solver driven
along a *folding path*. The path is a quasi-static continuation of rest angles,
grips and pressure, with CCD-capped steps, starting from a thickness-offset
flat state. Loop subdivision with sharp crease tags supplies the display
surface. Geometric isometry projection is the cheap alternative for authored,
contact-free poses such as wing curl.

## Findings

### A. What the study's model is, in mechanics terms

1. **The bending energy is Discrete Shells plus crease hinges, as G11 said.**
   - **Panels.** Every interior edge carries `½ k (θ − θ₀)²` with weight
     `panelStiffness · 2 l² / (twice the two triangles' area)`, which equals
     `k · l / h_mean` (`[code]` `study/fold-material/FoldBending.hs:212-223`,
     line 221; header `:18-23`).
   - **Creases.** A crease segment gets `creaseStiffness · l` (`FoldBending.hs:221`).
     That is Lechenault's hinge `M = κ W (φ − φ₀)` per unit length (finding 7),
     so the study's `κ` and a measured `κ` are the same kind of number.
   - **Angle.** The signed dihedral and its gradient are the standard hinge
     formulas (`FoldBending.hs:231-254`).
   - **Constants.** They are labelled illustrative: `Bending 1 5` by default
     (`FoldBending.hs:60-69`) and `Bending 1 0.2` in the crane fixtures
     (`WholeCrane.hs:334`, `CraneSpread.hs:121`).
   - **Missing next to Filipov et al.'s three behaviours** (stretch/shear, panel
     bending, crease folding; `[paper]` Filipov et al. 2017, §8.1): a membrane
     that is a material rather than a penalty.

2. **The membrane is an edge-spring lattice, and its penalty stages sweep
   through real paper's stiffness.**
   - **The energy.** It is `w Σ (l − l₀)²` over all material edges
     (`FoldRelaxation.hs:670-677`, `:703-711`), with stages
     `w = 1e2, 1e4, 1e6, 1e8` (`:543`) and contact at `100 w` (`:638`).
   - **What a spring lattice is equivalent to.** An equilateral triangular
     lattice of springs `k` behaves like a sheet with 2D Young's modulus
     `2k/√3` and Poisson ratio exactly 1/3, whatever its spacing. Checked
     numerically `[ran]` (`python3 scripts/H2-sheet-mechanics/lattice_check.py` →
     `Poisson 0.3333  Y 1.15470  2k/sqrt3 1.15470`). With `k = 2w` the study's
     lattice modulus is about `4w/√3`. Its right-triangle meshes change that
     by a factor of order one (`[reasoned]`).
   - **Where real paper sits.** The dimensionless ratio that matters is the
     *stretch-to-bend ratio* `γ = Y L² / B = 12(1 − ν²)(L/t)²` at sheet side
     `L`. For 15 cm kami it is `4.9e7` (finding 8). Against the crane's
     `B = 0.2`, the study's stages give `γ ≈ 1.2e3, 1.2e5, 1.2e7, 1.2e9`
     `[ran]` (`python3 scripts/H2-sheet-mechanics/paper_scales.py`). Real paper lies
     between the third and fourth stage.
   - **What that means.** The final stage is about 20× stiffer in-plane than
     kami: a constraint rather than a material. The weight that would match
     kami is `w ≈ 4.3e6` at `B = 0.2`, or `2.1e6` at `B = 0.1` `[ran]`.
   - **Poisson ratio.** A spring lattice fixes it at 1/3. Measured paper gives
     0.23 (finding 6). MERLIN2 hits the same wall with its bars and assigns bar
     areas that match a continuous panel's energy under uniform stretching
     (`[paper]` Liu & Paulino 2018, eq. 15).

3. **The solver is Gauss-Newton, which drops half the bending Hessian.**
   - **What the code does.** Each hinge is a residual `√k · angleError`
     (`FoldBending.hs:298-307`). The step solves `JᵀJ + 10⁻³ I` by conjugate
     gradients (`FoldRelaxation.hs:631-663`), and a line search halves the step
     up to 30 times (`:687`, `:697`).
   - **What it leaves out.** Tamstorf & Grinspun write the bending Hessian as
     two parts (`[paper]` 2013, §4): the outer product `ψ'' ∇θ ∇θᵀ`, and the
     angle's own Hessian weighted by `ψ' = k(θ − θ₀)`. Gauss-Newton keeps only
     the first. Their paper notes that Botsch avoided Hessians exactly this way.
   - **Why it matters here** (`[reasoned]`). The dropped term vanishes only
     where every hinge sits at its rest angle. The study's own measurements
     show creases missing their targets at equilibrium
     (`docs/notes/crease-and-panel-energy.md:71-78`), and there Gauss-Newton
     converges linearly, not quadratically. The closed-form Hessian costs
     little: the paper reports up to 7× faster than automatic differentiation.

4. **The crane shapes are static solves or constructions, never paths, and the
   preferred target is non-isometric by construction.**
   - **Static solves.** Installing a grip "starts a static solve; neither that
     installation nor its iterations is a folding path"
     (`FoldRelaxation.hs:48-51`). The body-barrier study stopped at three
     separate initialization blockers: #379, #381 and #383
     (`docs/notes/body-barrier-comparison.md:84-116`).
   - **The body is squashed by the recipe.** The pillow recipe maps material
     `(u, v)` to `x = (1 − u − v)/√2`, `z = (u − v)/√2`, adds a dome of height
     0.045, and then multiplies `z` by `bodyWidthScale` (`WholeCrane.hs:357-363`).
     The owner's "More tucked" pose uses the narrow body, `bodyWidthScale = 0.5`
     (`WholeCrane.hs:291`, `:299-307`;
     `docs/notes/crane-pillow-target.md:148`). That is a 50% compression across
     the wings, written into the target.
   - **The rest is not length-preserving either.** It is filled by a
     least-squares graph smoothing weighted by inverse edge length
     (`WholeCrane.hs:384-387`, `:420-426`), which "does not preserve its
     length" (`crane-pillow-target.md:58-61`).
   - **Consequence** (`[reasoned]`). The recorded +152% / −82% local strains
     (`crane-pillow-target.md:72-78`) measure the recipe, not a failure of
     mechanics. Any physical solve that starts there must either move far from
     the silhouette the owner chose or keep the strain.

### B. Paper: measured numbers and what they mean for a 15 cm crane

5. **Thickness and weight.**
   - **Kami.** OrigamiUSA's review measured 63 gsm (60 stated) and 72 µm
     (`[fetched]` origamiusa.org "Paper Review #12: Kami"). The same review
     gives printer paper as 105 µm.
   - **Other papers.** origami.me lists kami at about 60-63 gsm and printer
     paper at about 90-100 gsm (`[fetched]` origami.me/paper).
   - **The repository's figure.** `docs/notes/a-crease-is-a-hinge.md:43` and
     PRD 07's `thickness 0.1mm` example (`PRDs/07-prd-material-consumption.md:668`)
     use 0.1 mm, which is printer paper rather than kami.

6. **In-plane stiffness of paper varies 2-3× between papers and directions.**
   Paper is *orthotropic*: stiffer along the machine direction (MD), in which
   the fibres were laid, than across it (CD).
   - **Daler-Rowney Canford, 150 gsm** (not copy paper): `E_MD = 6.83 GPa`,
     `E_CD = 3.11 GPa`, `G₁₂ = 2.17 GPa`, `ν₁₂ = 0.23` (`[paper]` Nayakanti,
     Tawfick & Hart 2017, arXiv 1707.03673, supplementary Table 1).
   - **Kent drafting paper, 0.2-0.3 mm:** `E ≈ 2.45-3.27 GPa` (`[fetched]`
     Isobe & Okumura 2016, Sci. Rep., PMC4846813).
   - **Woodfree uncoated paper, 0.129 mm** (Pradier et al. 2016):
     `E_MD = 4 GPa`, as tabulated by Filipov et al. (`[paper]` 2017,
     Table 1, row 8).
   - **Kami itself.** No measured modulus was found. This note assumes 4 GPa
     and says so wherever it matters (see [Unverified](#unverified)). Two of
     the quantities that matter most do not depend on it: `γ` below and the
     ratio `L*/t`.

7. **Crease stiffness is measured only through the length `L* = B/κ`, and
   history changes it.**
   - **The Mylar measurements.** Lechenault, Thiria & Adda-Bedia defined
     `L* ≡ B/κ` and found crease rigidity `κ = 0.029 N` with rest opening
     `φ₀ = 27°` at 130 µm, and `L* ≃ 200h` (`[paper]` arXiv 1404.1243, pp. 3-4).
     This confirms the figures G6 took from the repository without
     re-fetching. A 27° opening between the panels is a FOLD fold angle of
     about 153°.
   - **Filipov et al.'s survey of nine experiments** (`[paper]` 2017,
     Appendix B, Table 1):

     | Material, `t` | `L*` | `L*/t` |
     | --- | ---: | ---: |
     | Pradier 2016, uncoated paper, pre-folded, 0.129 mm | 19 mm | 147 |
     | Yasuda 2013, paper, pre-folded, 0.27 mm | 50 mm | 185 |
     | Lechenault 2014, Mylar, 0.13 / 0.35 / 0.5 mm | 28 / 60 / 94 mm | 215 / 171 / 188 |
     | Virgin die creases on paperboard, 0.33-0.9 mm | 1.6-64 mm | — |

     The `L*/t` column is `[ran]`, from `paper_scales.py`.
   - **No law, only data.** The authors decline to fit it: fabrication and
     history matter more than thickness. For 0.36 mm they suggest a flexible
     cycled fold at `L* = 80 mm` and a stiff virgin one at `25 mm`. They give
     panel-to-fold stiffness ratios `K_B/K_F` of 1/3 to 20 as realistic.
   - **In series with the panel.** A crease's local stiffness
     `K = L_F · B / L*` acts in series with the panel material beside it:
     `K_F = 1/(1/K + 1/K_m)` (eqs. 10-11).
   - **History moves the rest angle.** Jules, Lechenault & Adda-Bedia (2020)
     find that plasticity mostly changes a crease's rest angle, and that it
     ages with a double-logarithmic time evolution (`[fetched]` arXiv
     2004.11825 abstract). A crease's rest angle is therefore a record of what
     was done to it, not a constant.

8. **The numbers for a 15 cm kami crane.** All `[ran]`
   (`python3 scripts/H2-sheet-mechanics/paper_scales.py`); `E = 4 GPa` and `ν = 0.23`
   assumed; `t = 72 µm`; 63 gsm.

   | Quantity | Value | In sheet units / at 600 px per sheet |
   | --- | ---: | ---: |
   | Bending stiffness `B` | 1.31e-4 N·m | — |
   | Stretch-to-bend ratio `γ = Y L²/B` | 4.9e7 | independent of `E` |
   | `L*` at 147-215 `t` | 10.6-15.5 mm | 0.071-0.103 sheet; 42-62 px |
   | Crease stiffness `κ = B/L*` | 8.5e-3 to 1.2e-2 N | — |
   | Thickness | 72 µm | 0.29 px |
   | Tightest fold radius, about 1.25 `t` (from G6, Rao et al.) | 90 µm | 0.36 px |
   | Elastogravity length `(B/ρg)^⅓` | 60 mm | 0.40 sheet |
   | Droop of a single-layer 7 cm flap under its own weight | 14 mm | — |

   - **Elastogravity length.** Below this length a sheet holds itself up
     against its own weight. It scales as `E^⅓`: 0.85× to 1.19× over the
     2.45-6.83 GPa range `[ran]`.
   - **What the table says** (`[reasoned]`):
     - **Creases are lines.** No fold radius or crease width is visible at
       diagram scale. Drawing creases infinitely sharp is physically right.
       This goes further than G7, which already found true-scale fillets
       invisible.
     - **Loaded panels bend.** Crane panels are about 2-7 cm, several times
       `L*`. A load such as spreading a wing therefore bends panels over a
       zone about `L*` (40-60 px) wide beside each crease, rather than only
       reopening creases. That is the curved flank `a-crease-is-a-hinge.md:43-48`
       predicted. Its `L* ≈ 2 cm` used 0.1 mm paper and the Mylar ratio; for
       kami the paper data give 11-16 mm.
     - **The study is close on creases.** It uses `κ = 1, B = 0.2`, so
       `L*_study = 0.2` sheet, 30 mm: 2-3× the physical value. `Bending 1 5`
       would be 50-70× too stiff in the panels.
     - **Gravity is borderline.** A single-layer flap as long as the
       elastogravity length droops visibly. A crane wing is several layers and
       curved, which stiffens it by an unknown amount. In units where
       `L = B = 1`, gravity is a load of `(L/ℓ_g)³ ≈ 16`.

9. **A smooth pillow is not a paper shape; paper answers with ridges and
   crimps.**
   - **How much a dome must shrink.** Bend a flat disc into a spherical cap
     keeping its radial lines at their length, and the rim must shrink. The
     hoop strain is `R sin(s/R)/s − 1`, about `−(2/3)(h/s)²` for rise `h` over
     radius `s` `[ran]`:

     | Rise / radius | Hoop strain at the rim |
     | ---: | ---: |
     | 0.1 | −0.67% |
     | 0.2 | −2.72% |
     | 0.3 | −6.28% |
     | 0.4 | −11.61% |

   - **The pillow target's own proportions.** It rises 0.045 over half-width
     `(√2 − 1)/2`, a ratio of 0.217 (`WholeCrane.hs:357-363`). Made smooth,
     that shape needs about 3.2% compression at its rim `[ran]`. That is 30×
     the owner's provisional 0.1% local-strain screen
     (`docs/notes/illustration-material-priority.md:14-17`).
   - **What paper does instead.** Real sheets resolve this by crimping. The
     "paper bag" or "teabag" problem asks for the largest volume of an inflated
     pillow of two unit squares of inextensible material. Kepert's bounds put
     it between 0.2055 and 0.217 of the side cubed. Robin's approximate formula
     ignores the crimping round the bag's equator (`[fetched]` Wikipedia,
     "Paper bag problem").
   - **Why the crimps are sharp.** At large bending angles an origami panel's
     stiffness scales as `θ^{4/3}`, with bending focused into a narrow ridge
     (Lobkovsky 1995, via `[paper]` Filipov et al. 2017, §4.2 and §8.3).
     MERLIN2 motivates its diagonals with the same stress focusing (Witten
     2007, cited in `[paper]` Liu & Paulino 2018, §1).
   - **For the crane and the waterbomb** (`[reasoned]`): a *refined* inflated
     body is either near-isometric with a few sharp ridges and crimps near its
     rims, or a declared schematic carrying a few percent of compression. The
     current target is neither: it carries 50% compression across the body
     (finding 4).

### C. Model families, beyond G6-G12

10. **MERLIN and MERLIN2 (Liu & Paulino).** `[paper]` IASS 2016 (MERLIN) and
    Origami 7, 2018 (MERLIN2), both read from the authors' PDFs.
    - **Model.**
      - **Bars and panels.** Bars along creases and panel diagonals. Panels are
        split N4B5 (four nodes, five bars: one diagonal) or N5B8 (an interior
        node and four triangles). MERLIN2 generalises both to convex polygons,
        placing N5B8's interior point to favour short diagonals.
      - **Accuracy.** On a twisted Mylar hexagon, N5B8 matched the physical
        shape better and N4B5 was stiffer.
      - **Material inputs.** "Auto mode" takes exactly `E`, `ν`, `t` and
        `L*/L_F` and derives every stiffness from them.
    - **Crease law.** Linear, `M = k₀(θ − θ₀)`, between `θ₁` and `θ₂`. Outside
      that range, `tan` branches send the stiffness to infinity near 0 and 2π,
      which "will prevent local penetration" of the two panels at that hinge.
      The eggbox example uses `θ₁ = π/8`, `θ₂ = 15π/8`, `k_f = 0.1`, `k_b = 2`,
      bar modulus `1e8`, 200 increments. This refines G9's "springs stiffen"
      with the actual law.
    - **Solver.** Force loading uses MGDCM, an arc-length-type continuation.
      *Arc-length* methods step along the equilibrium curve rather than the
      load, so they can follow a structure through a snap. Displacement loading
      uses damped Newton-Raphson over increments whose size adapts to how fast
      each one converged.
    - **Contact.** Only the hinge-local `tan` barrier; no contact between
      separated layers. That agrees with G9.
    - **Licence.** No licence was found. The GitHub search
      `gh api search/repositories -f q="MERLIN2 origami"` returned nothing
      origami-related `[ran]`, and Paulino's software page gave no text to
      curl `[ran]`. Treat the code as not reusable.
    - **For senbazuru** (`[reasoned]`). Its parameters are the right *material
      block* (`E, ν, t, L*`). Its panels, bending only along one or two
      diagonals, are too coarse for smooth illustration surfaces (G9). Its crease
      `tan` stiffening is a cheap, local guard worth copying as an idea.

11. **SWOMPS and Sim-FAST (Zhu & Filipov).**
    - **Contact.** A node-to-triangle potential that switches on inside a
      distance `d₀`, with `d₀` "relatively close to the real panel thickness"
      and around 2-5% of the panel length (`[fetched]` Zhu & Filipov 2019,
      Proc. R. Soc. A, PMC6834023).
    - **Speed and limits.**
      - **Timings.** A self-folding box took 20 s, a locking corner 21 s and
        an interlocking pattern 57 s, single-threaded on an i7-7700.
      - **Limits.** No edge-to-edge contact without extra edge nodes; sparse
        meshes miss panel-to-panel contact; elastic only; frictionless.
    - **Folding by rest angle.** SWOMPS creases have finite width, and its
      solvers include "changing stress-free folding angle for self-folding"
      alongside Newton-Raphson, displacement control, generalised displacement
      control and dynamic loading (`[fetched]` `zzhuyii/OrigamiSimulator`
      README via `gh api`). This drives the fold through its rest angle. It is
      the path-following loading the study lacks (finding 4).
    - **Status and licence.** The README says the author has moved on to
      Sim-FAST. `gh api repos/zzhuyii/{OrigamiSimulator,Sim-FAST,Sim-FAST-PY}/license`
      all return 404 `[ran]`: no licence file, so not reusable. G9 said this
      for SWOMPS; it now also holds for its successor.

12. **Discrete shells and the bending-model zoo.**
    - **Quadratic bending.** Bergou, Wardetzky, Harmon, Zorin & Grinspun (2006)
      derive a bending energy for *isometric* deformations whose Hessian is
      constant, cutting cloth simulation time up to three-fold (`[fetched]`
      Eurographics digital library record and search abstract). It suits
      near-inextensible paper away from creases.
    - **A 2026 benchmark.** Chen, Vouga & Kaufman, *Better Bending* (SIGGRAPH
      2026, TOG 45(4) 101), benchmark ten popular discrete bending models for
      convergence under refinement and mesh dependence, and stress-test them
      at sharp bends (`[fetched]` physicsbasedanimation.com summary; the paper
      PDF was not read).
      - **Their new model.** Bending-Active Cosserat (BAC) measures each hinge
        with `2h·tan(α)`, a barrier as a hinge approaches 180°. It is
        LibShell's `MidedgeAngleTanFormulation` (`[fetched]` READMEs of
        `evouga/libshell` and `alecjacobson/bending-active-cosserat` via
        `gh api`).
    - **LibShell** (MPL-2.0 by `gh api`) implements StVK and neo-Hookean
      membranes, four bending discretisations and a *tension-field* StVK that
      resists only tension. `evouga/better-bending` is MIT.
    - **Subdivision shells.** Cirak, Ortiz & Schröder (2000) build thin-shell
      finite elements on Loop subdivision. Displacements are H², so the
      Kirchhoff-Love energy stays finite, and the elements need no rotation
      unknowns. Loop's rules are extended for creases (`[fetched]` Caltech
      record).
    - **For senbazuru** (`[reasoned]`): the study's hinge model is the
      baseline these papers improve on, not a dead end. Upgrade it only if a
      refinement study shows its mesh dependence at drawing scale. That is the
      rule `illustration-material-priority.md:95-100` already sets.

13. **Inextensible triangle meshes lock, and the study is one.**
    - **Why triangles lock.** Goldenthal et al. (2007) note that constraining
      every edge of a triangle mesh causes *locking*. A triangulation of `n`
      vertices has about `3n` edges against `3n` position unknowns, so almost
      no freedom is left, and locally convex regions are rigid. Their fix is
      quad-dominant meshes (`[paper]` §3).
    - **Other fixes.** English & Bridson (2008) use nonconforming elements,
      with a "ghost" conforming mesh for collisions and rendering (`[paper]`
      abstract). Chen, Kry & Vouga (2019) average strain meshlessly
      (`[fetched]` arXiv 1911.05204 abstract). ARCSim realigns the mesh to the
      bends; its Figure 2 compares locking with remeshing at 8.77k faces
      (`[paper]` Narain, Pfaff & O'Brien 2013).
    - **In the study** (`[reasoned]`, from findings 2 and 3). At `w = 1e8` the
      triangle mesh is effectively inextensible. It can then bend without
      stretching only about lines made of its own edges. Curvature in other
      directions costs stretch, which the penalty refuses. This is a second,
      independent reason bent panels resisted: separate from contact, and not
      cured by more iterations. It is cured by the physical `w`, a triangle
      membrane, finer isotropic meshes, or remeshing.

14. **ARCSim: plastic creases and adaptive remeshing.** `[paper]` Narain,
    Pfaff & O'Brien 2013; `[fetched]` the ARCSim resource page.
    - **Energy.** Membrane from Green strain, bending from a discrete hinge.
    - **Plasticity.** A plastic bending strain per face, updated when bending
      exceeds a yield curvature. Rest angles `θ₀` are derived from it.
      Weakening makes yielded regions easier to re-fold; the paper example
      uses `κ = 200 m⁻¹`, `γ = ½`.
    - **Remeshing.** An anisotropic remesher aligns edges with folds. A plastic
      embedding stops remeshing from blurring creases.
    - **Cost.** Time steps are about 1 ms, with remeshing once per 25 fps
      frame. Average cost per frame ranged from 14.7 s at 2.07k faces
      (airplane) to 168.8 s at 6.95k faces (crumple, contact-bound), on 2013
      hardware (Table 1).
    - **Licence.** Non-profit use, with citation. That is not MIT-compatible
      for vendoring and would need an owner decision even to run.
    - **For senbazuru** (`[reasoned]`): ARCSim's plasticity is the physical
      version of the study's authored `BendControl` curl
      (`FoldBending.hs:6-7`) and of per-crease rest angles. Its remesher is XL
      work and not needed at crane scale if the mesh is crease-aligned and
      fine.

15. **Developable-surface geometry: shape without physics.**
    - **Stein, Grinspun & Crane (2018).** A vertex is *discrete developable* if
      its star is flat or a "hinge": two groups of triangles, each with one
      normal. Driving an energy on vertex-star normals to zero makes the mesh
      evolve into flattenable pieces joined by regular seams (`[paper]` §3,
      Definition 3.1, Theorem 3.3).
      - **Not our sheet.** It makes a surface developable, not isometric to a
        *given* flat sheet. Flattenability is zero angle defect, a separate
        condition, and the method approximates a target shape.
      - **Licence.** Code GPL-2.0 (`odedstein/DevelopabilityOfTriangleMeshes`
        LICENSE via `gh api`). Ideas only.
    - **Rabinovich, Hoffmann & Sorkine-Hornung (2018, 2019).** Discrete
      orthogonal geodesic nets are a quad-mesh analogue of developable
      surfaces. The 2019 paper folds curved creases while bending the sheet,
      constraining isometry through lengths in a reference mesh (`[fetched]`
      project page and the survey arXiv 2304.09587, §4).
    - **Kilian et al. (2008).** An optimisation framework for designing and
      reconstructing curved-fold surfaces without stretching (`[fetched]`
      abstract).
    - **Tachi (2010), Freeform Origami.** Solves developability and
      flat-foldability constraints with a Newton-Raphson step through the
      Moore-Penrose pseudo-inverse. That is kinematics under constraints, with
      no energy (`[paper]` J. Geom. Graph. 14(2), §3).
    - **When geometry beats physics for an illustration** (`[reasoned]`):
      - **Wing curl and spread.** For an open pose with no layer contact, a
        geometric "nearest near-isometric shape to an authored target" is one
        static solve. The terms are lengths, smoothness and anchors. It needs
        no path and gives the author direct control.
      - **Body opening.** Once layers slide past each other, geometry has no
        notion of which layer passes which along the way. The 30-PR body study
        shows the cost of guessing. Physics with a path is needed there.

16. **Solvers, and which one fits "a plausible shape reached by a folding
    path".**
    - **Static Newton with safeguards.** Newton plus a line search and a
      definiteness correction is robust (Martin et al. 2011, as cited by
      `[paper]` Gast et al. 2015, §1). *Definiteness correction* projects each
      element's Hessian so that every step goes downhill.
    - **Implicit Euler as minimisation** (the *incremental potential*). Gast et
      al. recast backward Euler as minimising inertia plus energy, so Newton
      can be stabilised with standard optimisation. It reaches 24 Hz steps
      where plain Newton fails, and folds collisions in as constraints
      (`[paper]` 2015, abstract and §2). IPC adds a barrier and CCD-filtered
      steps with an intersection-free guarantee (G13).
    - **Projective dynamics.** Alternates local projections with one global
      solve against a constant, prefactored matrix. Convergence is linear:
      slower per iteration than Newton, faster per second at interactive
      budgets. It damps motion when stopped early (`[paper]` Bouaziz et al.
      2014, §7.3 and Limitations).
    - **XPBD.** Makes stiffness independent of time step and iteration count.
      Stopping early still leaves "artificial compliance", and the method only
      approximates implicit Euler (`[paper]` Macklin, Müller & Chentanez 2016,
      Limitations).
    - **Explicit damped dynamics.** What Origami Simulator uses, with soft
      axial stiffness 20 and no collision (G10). The largest stable time step
      shrinks as the membrane stiffens, so paper's `γ ≈ 5e7` is out of reach
      without stretch (`[reasoned]`).
    - **Arc-length continuation.** MERLIN's MGDCM (finding 10) follows
      unstable branches through snap-through. Illustrations do not need the
      unstable branch, only where the sheet lands. A little inertia, as in the
      incremental potential, jumps the snap (`[reasoned]`).
    - **The fit** (`[reasoned]`): a *quasi-static continuation*. Move the
      controls (rest angles, grip positions, pressure) in small steps from a
      valid state. Solve each step as an incremental-potential minimisation
      with a barrier, capping the Newton step with CCD. Shrink the step when
      convergence is slow, as MERLIN2 does.
      - **The study has most of the parts.** It has CCD-like interval
        certificates for straight vertex paths, exact rational Bernstein
        bounds (`CorrectionSweep.hs:1-21`), but uses them to *refuse* steps,
        not to cap them.
      - **The missing piece is the outer loop over controls.**

17. **Mesh modelling for display versus simulation.**
    - **Crease tags in subdivision.** Hoppe et al. (1994) tag edges as sharp
      and modify Loop's rules at crease, corner and dart vertices. The surface
      stays smooth everywhere except across tagged edges (`[paper]` §3.1).
    - **Semi-sharp creases.** DeRose, Kass & Truong (1998) add creases whose
      sharpness can vary from smooth to infinitely sharp. Integer sharpness `s`
      means `s` rounds of sharp rules, then smooth ones (`[paper]` §3).
    - **OpenSubdiv's licence** is the "Tomorrow Open Source Technology License
      1.0": Apache-2.0 with a different trademark section (`gh api` LICENSE
      text; the SPDX field reads `NOASSERTION`).
    - **What senbazuru has.** The study already keeps source crease identity
      through refinement (`crease-identity-through-refinement.md`, per G20). It
      averages normals per panel (`crane-panel-lighting.md:14-28`). Both are
      exactly the tags a crease-aware subdivision needs.
    - **What it should do** (`[reasoned]`). Creases are sharper than a pixel
      (finding 8), so tag every source crease and boundary *infinitely* sharp
      and leave panel interiors smooth.
      - **Consequence for silhouettes.** Loop subdivision is approximating, so
        the limit surface moves off the simulated vertices by a small amount.
        Material checks must therefore stay on the simulated (control) mesh,
        and subdivision is display only.
      - **Consequence for the drawing.** Silhouettes computed on the subdivided
        mesh are smooth curves rather than polygons with a kink at every
        triangle.
    - **Simulate on the displayed surface.** Cirak's subdivision shells
      (finding 12) do this. It is the principled unification, but XL work.

18. **Inflation.**
    - **Tension-field theory.** Skouras et al. (2014) design inflatables with
      "accurate coarse-scale simulation using tension field theory"
      (`[fetched]` ETH CGL abstract). A tension-field membrane refuses to carry
      compression, so it predicts the smooth average shape of a wrinkled
      balloon without resolving the wrinkles. LibShell ships one (finding 12).
    - **Pressure as an energy** (`[reasoned]`). Pressure `p` on a closed
      surface contributes `−p·V`. The volume of a closed triangle mesh is
      `V = (1/6) Σ xₐ·(x_b × x_c)`, so each vertex receives `p/3` times the
      summed area-weighted normals of its triangles.
      - **Open pockets.** The crane's body is open underneath
        (`opening-a-crane.md:84-87`). It needs either a declared virtual cap
        that closes the cavity, or a *follower* pressure on the pocket faces,
        which is not the gradient of any energy.
      - **Order of work.** The owner decided that controlled opening comes
        before pressure (`illustration-material-priority.md:88-93`); both need
        the same path-following machinery.

### D. The recommended model stack, and what the study already has

19. **Recommended stack.** Each row names the choice, why, and the study's
    code today.

    | Layer | Recommended | Why | Study today |
    | --- | --- | --- | --- |
    | Membrane | Per-triangle StVK on Green strain, `ν = 0.23`, at physical `γ ≈ 5e7`. Optionally a strain-limit barrier at about 1% on top (C-IPC-style, G13) | A material, not a penalty; sets Poisson; less locking; a 1% cap keeps pictures honest (finding 21) | Edge springs, `w` staged to 1e8, `ν` fixed at 1/3 (`FoldRelaxation.hs:543`, `:670-711`) |
    | Panel bending | Keep the hinge energy `k l/h_mean`, normalised `B = 1`. Move to midedge/BAC only if refinement shows visible mesh dependence | Cheapest; the benchmark says when to upgrade | `FoldBending.hs:221`, illustrative |
    | Crease | `κ l (θ − θ₀)²`, `κ = B/L*`, `L* ≈ 150-215 t` (0.07-0.10 sheet for kami); MERLIN-style stiffening near ±π | Measured (finding 7); guards against hinge flip | Same form, `L*_study = 0.2` (`WholeCrane.hs:334`) |
    | Rest angles and curl | `θ₀` per crease from the step that made it, minus a declared springback. Panel rest curvature (plastic curl) authored by a shaping step | History sets rest angle (Jules 2020); hand-curled wings are plastic (ARCSim) | Fixed authored `θ₀` (`FoldBending.hs:141-148`); `BendControl` (`:6-7`) |
    | Loads | Exact grips; optional gravity (`(L/ℓ_g)³ ≈ 16`); pressure `−pV` over a declared cavity | Inflation; drooping flaps | Grips only (`FoldRelaxation.hs:251-258`); `grep -il "gravity\|pressure"` finds only comments `[ran]` |
    | Contact | Unsigned point-triangle and edge-edge barrier at `d̂` about physical thickness; CCD caps each step; directional checks kept as diagnostics | Order is kept automatically along a path that never crosses (G13) | Directional barrier/penalty on a model axis (`SurfaceContact.hs:1-38`); CCD refuses steps (`CorrectionSweep.hs:1-21`) |
    | Start state | The checked rigid flat-folded state, layers offset by thickness from `faceOrders`, joined by thickness-scale strips | A separated, near-isometric start: the thing #379, #381 and #383 could not build | Prescribed or constructed guesses (finding 4) |
    | Mesh | Crease-aligned refinement (existing `refineSurfaceWithEdges`) to about 5k triangles per sheet (edge ≈ `L*/5`), isotropic triangle orientations within panels | Resolve curvature over `L*`; avoid preferred bend directions | 448 triangles, whole crane (`whole-crane-candidate.md:23-24`); 392 and 1,192, wing (B, finding 1) |
    | Solver | Newton on the total energy with the analytic hinge Hessian and per-element PSD projection; backtracking plus CCD cap; sparse direct factor; outer loop of quasi-static control steps with adaptive size | Quadratic convergence; path-following | Gauss-Newton, damping `1e-3`, CG with LDLᵀ preconditioner, penalty stages, static from guess (`FoldRelaxation.hs:631-702`; `SparseSolve.hs:1-20`) |
    | Display | Loop subdivision of the simulated mesh, source creases and boundaries tagged sharp; limit normals; SVG silhouettes from the subdivided surface | Smooth outlines; no facet seams; sharp creases | Per-panel averaged normals (`PaperLighting`), flat facets in SVG (`crane-panel-lighting.md`, `crane-book-drawing.md`) |

    **Sizing the mesh** (`[reasoned]`). Take the edge length as `L*/5`, about
    0.015-0.02 sheet. A unit square then needs about `2/0.02² ≈ 5,000`
    triangles, some 7,500 position unknowns. That is small for a sparse direct
    solver in C. In Haskell it must be measured, as AGENTS.md requires. The
    crane-wing solves recorded 0.47, 5.76 and 64.30 CPU s at increasing
    refinement, and failed body trials about 9 CPU minutes each (research B,
    finding 1).

20. **Parameter defaults in study units.** Sheet side = 1, bending stiffness
    `B = 1`, from finding 8 (`[ran]`).

    | Parameter | Value |
    | --- | --- |
    | Crease stiffness `κ = 1/L*` | 10-14 |
    | Membrane `γ` | 4.9e7 for 15 cm kami; 2.3e7 for 105 µm printer paper at an assumed 80 gsm |
    | Thickness `t` | 4.8e-4 |
    | Gravity load | about 16 |
    | Crease rest angle | about 150-175° folded. Lechenault's pressed Mylar relaxed to 153°; the study asks 170°; paper-specific values are unmeasured here |

    Everything except `γ` and `L*/t` scales with the unmeasured kami modulus.
    Mark it `illustrative, kami-like` in the output.

21. **What "refined" costs in strain, at drawing scale** (`[ran]`,
    `[reasoned]`). At 600 px per sheet:
    - 1% strain over a 0.2-sheet panel is 1.2 px.
    - Kami's thickness is 0.29 px.
    - The tightest fold radius is 0.36 px.

    So a **1% strain cap is roughly the visibility threshold** for panel
    shapes. The owner's provisional 0.1% screen
    (`illustration-material-priority.md:14-17`) is ten times stricter than
    anything visible. Neither is met by the current targets: 58% edge error,
    +152% local stretch (`crane-pillow-target.md:76-77`).

## Implications for senbazuru

**Effort scale** (`[reasoned]`, one developer familiar with the study): S up to
3 days, M 1-2 weeks, L 3-6 weeks, XL more than 6 weeks. Every item stays in
`study/fold-material` until PRD 07's graduation gates apply. Every item keeps
the default outputs byte-identical, following the repository practice of
adding a second view rather than churning goldens.

- **R1. Put physical parameters behind the illustrative ones (S).**
  - **The change.** Add a `PaperMaterial {thickness, youngs, poisson, lstarOverT,
    grammage}` record that computes `B`, `κ`, `w` (or `γ`) and gravity in
    sheet units, using the formulas in findings 2 and 8. Default to kami at
    72 µm and 63 gsm, with `E` labelled assumed.
  - **The first experiment.** Rerun the saved held-wing and crane-spread
    solves at `κ = 1/L*` and physical `w`, and compare silhouettes at 600 px.
  - **How we would know it worked.** A table of silhouette displacement
    against the current `Bending 1 0.2` result. Silhouette changes under 1 px
    would mean calibration does not matter for pictures, which is itself worth
    knowing.
  - **Depends on:** nothing. **Risk:** softer membranes at physical `w`
    converge differently from the staged penalty; keep the stage schedule
    ending at the physical value rather than `1e8`.

- **R2. Replace edge springs with a triangle membrane (M).**
  - **The change.** A per-triangle Green strain `E = ½(FᵀF − I)`, where `F`
    maps each material triangle to its deformed position, with StVK energy
    `(Y/2(1 − ν²))[(1 − ν) tr(E²) + ν (tr E)²]·area`. It is written as
    residuals so the existing Gauss-Newton path still works, and later with
    its exact Hessian.
  - **How we would know it worked.** The single and double fold controls
    reproduce `crease-and-panel-energy.md`'s angles within stated tolerances,
    and a held-strip bend changes by less than 1 px when the triangulation's
    diagonals are flipped (locking test).
  - **Depends on:** R1. **Risk:** locking persists on coarse meshes (finding
    13); pair it with R7's refinement.

- **R3. A quasi-static path driver (M).** This is the highest-value item for
  the body opening.
  - **The change.** A loop over a control schedule: rest angles, grip
    positions and pressure, each as a function of a path parameter `s` in
    [0, 1]. Each step warm-starts from the previous accepted state and solves
    with the existing machinery.
  - **What a step may do.**
    - Refuse a step whose accepted correction fails the path check
      (`CorrectionSweep`), then halve `Δs`.
    - Grow `Δs` after fast convergence.
    - Record every accepted state as a checked point on the path.
  - **What it replaces.** The prescribed initial guesses of #379-#397.
  - **How we would know it worked.** On the held-wing fixture, a path from
    closed to spread reaches the same endpoint as today's static solve within
    1 px, with every recorded state passing the existing length, contact and
    order checks.
  - **Depends on:** R1. **Risk:** step counts may be large; measure.

- **R4. Thickness-offset start and unsigned barrier contact (L).**
  - **The start.**
    - **Separate the layers.** From a checked rigid flat state and its
      `faceOrders`, offset each layer by its stacking rank × `t` (display
      exaggeration kept separate, G7).
    - **Join them again.** Rejoin creases with strips about `n·t` wide.
    - **Why the strain is harmless** (`[reasoned]`). The two-bends
      counterexample's strain in those strips is large, but only over a width
      proportional to `t`. The absolute length error is then about `t`, 0.3 px.
  - **The energy.** Replace directional contact with an IPC-style unsigned
    barrier at `d̂` of about `t`, and cap each Newton step at the CCD
    time-of-impact instead of refusing it.
  - **How we would know it worked.** The start passes the all-pairs triangle
    check, and the first R3 path on the crane body opens without a single
    refused state for pair repair.
  - **Depends on:** R3. **Risks:**
    - An offset start can still intersect where strips cross at fold
      vertices. That is a hypothesis to test first, on the quarter fold and
      the blintz.
    - An external `ipc-toolkit` (MIT) is a toolchain decision under PRD 07.

- **R5. Gravity and pressure loads (S for gravity, M for pressure).**
  - **Gravity.** A constant force per vertex, `ρ g × vertex area`, on by
    request.
  - **Pressure.** `−pV` over a *declared* closed cavity: the pocket faces
    plus a virtual cap, with the cap excluded from contact and drawing.
  - **How we would know it worked.** A waterbomb inflated to equilibrium has
    volume no larger than the teabag bound, about 0.217 of the side cubed for
    a square pillow (finding 9). A body that exceeds its bound is stretching.
  - **Depends on:** R3 and R4. **Risk:** open pockets (finding 18).

- **R6. Rest-angle history and panel curl as plastic state (M).**
  - **The change.** Each fold step records its commanded angle. On release, a
    declared springback sets `θ₀`. A shaping step (curl a wing) writes panel
    rest angles, the physical reading of today's `BendControl`.
  - **Optionally.** ARCSim-style yield: when elastic curvature exceeds a yield
    curvature, move the rest angle.
  - **How we would know it worked.** Releasing all grips after a shaping step
    leaves the curl in place, within 1 px of the authored target.
  - **Depends on:** R1. **Risk:** a yield model without measured paper values
    is one more illustrative constant; keep it authored first.

- **R7. Refine to the curvature length, crease-aligned (S-M).**
  - **The change.** Choose the refinement level so the longest interior edge
    is at most `L*/5`. Randomise or alternate panel diagonal directions so
    there is no preferred bend line.
  - **How we would know it worked.** A convergence table: silhouette distance
    between successive levels under 1 px at 600 px per sheet.
  - **Depends on:** R2. **Risk:** runtime; profile per AGENTS.md.

- **R8. Newton with the analytic hinge Hessian and PSD projection (M).**
  - **The change.** Implement Tamstorf & Grinspun's closed form, and project
    each element Hessian to positive semi-definite.
  - **How we would know it worked.** Iteration counts to the existing
    `movement ≤ 1e-7` test (`FoldRelaxation.hs:702`) fall on the saved held
    fixtures, with identical endpoints.
  - **Depends on:** R2. **Risk:** small; the Gauss-Newton path stays as a
    fallback.

- **R9. Isometry projection for authored targets (S-M).**
  - **The change.** A local/global (ARAP-style) solve. *ARAP*, "as rigid as
    possible", rotates each triangle to best fit its deformed shape. The solve
    minimises distance to an authored target such as `pillowCraneAtSpread`,
    plus physical membrane and bending, with anchors. That is projective
    dynamics without the dynamics.
  - **What it does and does not claim.** It turns a 58%-error sketch into the
    nearest near-isometric shape. It does not claim contact validity.
  - **How we would know it worked.** For "More tucked": report how far the
    silhouette must move to bring local strain under 1%. That answers the
    open question of whether the preferred look is achievable (finding 4).
  - **Depends on:** R1-R2. **Risk:** the answer may be "not close". That is a
    finding, not a failure.

- **R10. Display subdivision with crease tags (M).**
  - **The change.** Loop subdivision of the simulated mesh, with source
    creases and boundaries tagged infinitely sharp, limit normals, then the
    existing visibility and contour pipeline on the subdivided surface.
  - **Where it runs.** A second view only; the checks stay on the control
    mesh.
  - **How we would know it worked.** The crane book drawing's contours are
    smooth, with turning angle between consecutive contour segments under a
    few degrees, while crease positions stay within 0.5 px of the control
    mesh's.
  - **Depends on:** nothing, though it is best after R7. **Risk:** subdivision
    can pull thin flaps into neighbours; check nearest-surface order on the
    subdivided mesh.

- **R11. External oracles (M, optional).**
  - **The change.** Run LibShell (MPL-2.0) or Codim-IPC (Apache-2.0; build
    without GPL CHOLMOD, PRD 07) on the same mesh and parameters for one
    held-wing pose. Compare silhouettes. Running is not vendoring (D17).
  - **What stays out.** MERLIN, SWOMPS and Sim-FAST have no licence; ARCSim is
    non-profit-only. Owner decision needed even to run them.

- **Not recommended now:** adaptive anisotropic remeshing (XL), subdivision
  shells as the simulation discretisation (XL), arc-length continuation
  (unneeded for endpoints), and commercial FEA (G's related-projects table).

## Acceptance ideas: measuring "refined" on the mechanics axis

All measured at the declared 600 px per sheet and the gallery's cameras.
Thresholds are proposals for the owner.

1. **Material honesty.** Largest principal strain on the control mesh at most
   1%, about 1.2 px on a 0.2-sheet panel, everywhere outside regions declared
   schematic. Report the 0.1% screen alongside. Today it is +152% / −82%.
2. **Path validity.** Every *recorded* state along an R3 path passes the
   existing all-pairs triangle and order checks, not only the endpoint. Count
   refused steps; a refinement-free opening has zero pair repairs.
3. **Mesh convergence.** Silhouette Hausdorff distance between refinement
   levels under 1 px. Crease-angle change under 0.5°.
4. **Parameter robustness.** Changing `B` by 0.5× and 2×, and `L*/t` over
   147-215, moves the silhouette by at most N px. Report N: it tells the owner
   whether paper calibration is visible at all.
5. **Physical sanity checks with known answers.**
   - A uniform strip under its own weight matches the cantilever droop
     `qL⁴/8B` within a few percent.
   - A single crease released from 180° settles at `θ₀`.
   - A panel shorter than `L*` beside a loaded crease stays flatter than one
     longer than `L*`, as in Lechenault's Fig. 5 comparison.
   - An inflated square pillow's volume is at most 0.217 `a³`.
6. **Looks.**
   - **Smooth outlines.** Contour polylines from the subdivided display
     surface have no turning angle above a few degrees except at tagged
     creases.
   - **No seams.** No lighting seams inside a panel; per-panel normals are
     already met (`crane-panel-lighting.md`).
   - **Owner review.** An A/B against the current More-tucked drawing.

## Sources fetched

All on 2026-09-28. Licences are from `gh api repos/OWNER/REPO/license` unless
stated.

- **Bar and hinge.**
  - Liu & Paulino, *MERLIN*, IASS 2016: <http://www2.coe.pku.edu.cn/faculty/liuke/papers/latest/16Liu_merlin.pdf>.
    Code licence not found.
  - Liu & Paulino, *MERLIN2*, Origami 7, 2018: <http://www.liukepku.com/papers/software/18Liu_merlin2.pdf>.
  - Filipov, Liu, Tachi, Schenk & Paulino, *Bar and hinge models for scalable
    analysis of origami*, IJSS 124 (2017): <https://drsl.engin.umich.edu/wp-content/uploads/sites/414/2018/10/2017_Bar_and_Hinge_IJSS.pdf>.
  - Zhu & Filipov, contact in origami assemblages, Proc. R. Soc. A (2019): <https://pmc.ncbi.nlm.nih.gov/articles/PMC6834023/>.
  - `zzhuyii/OrigamiSimulator` (SWOMPS), `zzhuyii/Sim-FAST` and
    `zzhuyii/Sim-FAST-PY`: READMEs via `gh api`. No licence file (404).
  - Khawale, Mehdizadeh, Brigham & Filipov, *Rapid Kirigami Simulation using
    the Bar & Hinge Approach*, arXiv 2608.13770 (abstract).
- **Crease mechanics and paper.**
  - Lechenault, Thiria & Adda-Bedia, PRL 2014: <https://arxiv.org/pdf/1404.1243>.
  - Jules, Lechenault & Adda-Bedia: <https://arxiv.org/abs/1808.04892> and
    <https://arxiv.org/abs/2004.11825> (abstracts).
  - Nayakanti, Tawfick & Hart 2017: <https://arxiv.org/pdf/1707.03673>.
  - Isobe & Okumura 2016: <https://pmc.ncbi.nlm.nih.gov/articles/PMC4846813/>.
  - OrigamiUSA *Paper Review #12: Kami*: <https://origamiusa.org/thefold/article/paper-review-12-kami>.
  - origami.me paper guide: <https://origami.me/paper/>.
  - Wikipedia, *Paper bag problem*: <https://en.wikipedia.org/wiki/Paper_bag_problem>.
- **Shells, bending and locking.**
  - Tamstorf & Grinspun 2013: <https://la.disneyresearch.com/wp-content/uploads/Discrete-Bending-Forces-and-Their-Jacobians-Paper.pdf>.
  - Bergou et al. 2006: <https://cims.nyu.edu/gcl/papers/bergou2006qbm.pdf>.
  - *Better Bending* summary: <https://www.physicsbasedanimation.com/2026/06/13/better-bending-analysis-construction-and-verification-of-discretebending-models-for-kirchhoff-love-shells/>.
    `evouga/better-bending` MIT; `evouga/libshell` MPL-2.0;
    `alecjacobson/bending-active-cosserat` has no licence file.
  - Cirak, Ortiz & Schröder 2000: <https://authors.library.caltech.edu/records/kw8e6-wxc29>.
  - Goldenthal et al. 2007: <http://www.cs.columbia.edu/cg/pdfs/131-ESIC.pdf>.
  - English & Bridson 2008: <https://www.cs.ubc.ca/~rbridson/docs/english-siggraph08-cloth.pdf>.
  - Chen, Kry & Vouga 2019: <https://arxiv.org/abs/1911.05204>.
  - Narain, Pfaff & O'Brien 2013: <http://graphics.berkeley.edu/papers/Narain-FCA-2013-07/Narain-FCA-2013-07.pdf>.
    ARCSim page: <http://graphics.berkeley.edu/resources/ARCSim/>, non-profit
    licence.
- **Developable geometry.**
  - Stein, Grinspun & Crane 2018: <http://www.cs.columbia.edu/cg/developability/developability-of-triangle-meshes.pdf>.
    `odedstein/DevelopabilityOfTriangleMeshes`: GPL-2.0 per its LICENSE text.
  - Rabinovich, Hoffmann & Sorkine-Hornung 2019: <https://igl.ethz.ch/projects/curved-folds/>.
  - Yuan, Cao & Shi, developable-surfaces survey: <https://arxiv.org/pdf/2304.09587>.
  - Kilian et al. 2008 (abstract, via search).
  - Tachi 2010: <https://origami.c.u-tokyo.ac.jp/~tachi/cg/TachiFreeformOrigami2010.pdf>.
- **Solvers.**
  - Gast et al. 2015: <https://www.cs.ucr.edu/~craigs/papers/2015-optimization/paper.pdf>.
  - Bouaziz et al. 2014: <https://www.cs.utah.edu/~ladislav/bouaziz14projective/bouaziz14projective.pdf>.
  - Macklin, Müller & Chentanez 2016: <https://matthias-research.github.io/pages/publications/XPBD.pdf>.
- **Subdivision.**
  - Hoppe et al. 1994: <https://hhoppe.com/psrecon.pdf>.
  - DeRose, Kass & Truong 1998: <https://www.cs.rpi.edu/~cutler/classes/advancedgraphics/S17/papers/derose_subdivision_98.pdf>.
  - OpenSubdiv LICENSE (Tomorrow Open Source Technology License 1.0).
- **Inflation.**
  - Skouras et al. 2014: <https://cgl.ethz.ch/publications/papers/paperSko14a.php>.
- **Scripts.**
  - `scripts/H2-sheet-mechanics/paper_scales.py`: every table in findings 2, 7, 8, 9,
    20 and 21.
  - `scripts/H2-sheet-mechanics/lattice_check.py`: finding 2.

## Open questions

- **Does the owner accept that the physical tucked crane may look different?**
  The More-tucked body is 50% compressed by construction (finding 4). A
  physical version keeps the pocket's paper length and may be wider, or
  wrinkled, or opened differently. R9 measures how far.
- **Inflated bodies: crimps or declared strain?** Should they show crimps and
  ridges, as paper does, or a smooth declared-schematic surface carrying a few
  percent of compression, the tension-field average? That decides whether R5
  needs refinement near rims or a schematic label.
- **Which paper is the default?** Kami at 72 µm, or the repository's 0.1 mm?
  Is `E = 4 GPa` acceptable as an unmeasured assumption, or should the project
  measure one kami sheet? A cantilever droop test needs only a ruler and gives
  `B` directly.
- **Is gravity on by default in a rendered final model?**
- **External oracles.** Is LibShell (MPL-2.0) acceptable to run as an oracle
  under D17? Is ARCSim's non-profit licence acceptable to run at all?
- **Where does the path live?** Is the control schedule `s ↦ (rest angles,
  grips, pressure)` part of the sequence language's material block (PRD 07),
  or study-only until graduation?
- **What wall-clock budget per illustration pose** is acceptable? It decides
  whether 5k-triangle Newton in Haskell needs a faster linear solver.

## Unverified

- **Kami's Young's modulus and Poisson ratio.** No kami measurement was found;
  4 GPa and 0.23 are borrowed from other papers (finding 6). A cantilever
  droop or Taber test on a kami strip would check it.
- **Printer-paper grammage** in finding 20 is assumed at 80 gsm.
- **Paper's tensile failure strain.** Not found in a fetched source, and not
  used in any recommendation.
- **The spring-lattice-to-modulus factor for the study's right-triangle
  meshes.** Only the equilateral case was checked (finding 2). The order of
  magnitude of the stage comparison does not depend on it.
- **MERLIN's code distribution terms.** The software page returned no text and
  GitHub search found nothing.
- ***Better Bending*'s detailed results for the hinge model.** Only the
  abstract and two READMEs were read; the ACM PDF was not fetched.
- **Rabinovich et al.'s isometry constraints and Kilian et al.'s method** are
  from the survey and abstracts, not the papers' full text.
- **Performance of the recommended Newton solver** at about 5k triangles in
  Haskell. Not measured; profile per AGENTS.md.
- **R4's hypothesis** that a thickness-offset start is intersection-free and
  near-isometric at true thickness, including at fold vertices where strips
  cross.
- **Where the pillow target's +152% strain sits.** Whether it concentrates at
  the wing-root collars is inferred from the notes' "distorted wing roots"; no
  per-triangle map was read.
- **Gravity droop of a multi-layer, curved crane wing.** Only the single-layer
  bound (14 mm) was computed.
- **Other cited-but-unread sources.** Lobkovsky 1995, Witten 2007, Martin et
  al. 2011, Riks and Crisfield arc-length, Teran et al. 2005 projected Newton,
  Provot 1995 strain limiting and Rao et al. 2013 were cited through other
  papers or G, not read.
- **Kilian et al. 2008** was read only through search-result abstracts.
