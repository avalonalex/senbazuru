# Gap: exact landmarks, and binding coupled macros on arbitrary patterns

Researched 2026-09-14 against the repository at `568dcb6`
(branch `docs/prds-sequence-language`). Nothing in the repository was modified,
built or tested. Evidence comes from:

- `sed`, `grep` and `jq` on the cited files;
- `git log -S`;
- `gh issue view 60`;
- `python3` on this Mac, for floating-point and field facts. Python is not GHC,
  so every number from it is labelled.

Three external sources were fetched: Foschi–Hull–Ku on arXiv, the Hackage page
of `cyclotomic` with the `base` `Numeric` docs, and the FOLD spec. Akitaya's
2012 seminar paper was read as a PDF.

Terms used without definition are in `docs/glossary.md`: sector, star, Maekawa,
Kawasaki, rabbit ear, petal, collapse, hair. "Moving crease" below means a
crease whose fold angle changes during the step. "Current" means the state
before the step; "target" means the assignment (M/V/F) the pattern says the
step ends at.

## Summary

- **Landmarks.** Author them as constructions, with `Rational` only for typed
  fractions. Evaluate each once to `Double` and resolve it against the drawing
  with creasing's own tolerance. Exact fields belong in study certificates.
  Q(√2) names the bird's petal vertices but is not closed under Huzita–Hatori
  constructions, and cannot hold the fish rabbit ear's rate constant. The
  snapshot's `cyclotomic` is GPL-3.0-only and unordered.
- **Binding.** Each macro binds from a *moving star*: current angles, plus
  target signs. The collapse, rabbit-ear and petal signatures are given below
  and checked on the square, waterbomb, fish and bird fixtures. Roles inside a
  match are unique. Matches are not: the fish has two ears and the bird two
  petals, so a material-point disambiguator is required.
- **Certification.** On an arbitrary pattern a coupled macro can claim only
  sampled poses (`TornAt`, `loopsClose`, static contact). Certificates are
  bound to one fixture. Label assurance per step.
- **Angle tests.** The manifest's rabbit-ear literal is one ulp (unit in the
  last place, the gap to the adjacent `Double`) from the documented `atan2`
  form. A `tan` form reproduces it in Python. Compare formula angles with a
  named tolerance, and keep exact equality for copied values, driving
  parameters and pinned endpoints.

## Findings

### A. How exact a landmark is today

1. **One irrational coordinate already has four `Double` spellings.**
   - Material vertex 9 of `examples/bird-base.fold` has
     y = `0.2071067811865475` (`jq .vertices_coords`). The exact value is
     0.5·(√2 − 1) = 0.20710678118654752440….
   - The nearest `Double` is `0.20710678118654752`, so the file's literal is
     one ulp below it (Python `math.nextafter`).
   - `PetalCertificate` builds the same point as `(h, diagonal - h)` with
     `diagonal = Q 0 (1/2)` (`PetalCertificate.hs:136`, `:145`).
     `approx (Q a b) = fromRational a + fromRational b * sqrt 2`
     (`:68-69`). That expression order evaluates in Python to
     `0.20710678118654757`.
   - On the fish, `1/sqrt 2` is `0.7071067811865475` and `sqrt 2 / 2` is
     `0.7071067811865476` (Python).

   All of these differences are below 1e-16, about seven orders of magnitude
   inside any tolerance in the code (finding 2). Anything that decides
   "same landmark" with `==` on `Double`s is deciding by rounding. A newcomer
   will assume `sqrt 2 / 2 == 1 / sqrt 2`; it is not.

2. **"A hair" is several formulas, and a resolver must name one.**

   | Where | Formula | Used for |
   | --- | --- | --- |
   | `Fold.Faces.tolerance` (`Faces.hs:248-251`) | 1e-9 × bounding-box **diagonal**, no floor | creasing: length, "meets something", interning (`Creasing.hs:150`, `:176-177`, `:186-190`, `:231`, `:243`) |
   | `Import.Segments.mergeTolerance` (`Segments.hs:194-196`) | 1e-9 × diagonal, no floor | merging `.cp`/`.opx` endpoints |
   | `Origami.Flat.sheetHair` (`Flat.hs:193-195`) | 1e-9 × max(1, larger x/y **span**) | the glossary's **Hair** (`docs/glossary.md:46`) |
   | `Origami.Folding.sheetTolerance` (`Folding.hs:847-854`) | 1e-9 × max(1, larger span) | `TornAt`, `loopsClose` (`:368`, `:376-377`, `:810-811`) |
   | `StudyCase` strictly-inside (`StudyCase.hs:141`, `:168`) | absolute 1e-10 | naming panels and the fixed panel by material point |
   | `CheckedPetal`/`CheckedBird` `samePoints` (`CheckedPetal.hs:96`, `CheckedBird.hs:148-149`) | absolute 1e-12 | pose vs certified ideal path |
   | `Contact.panelTolerance` (`Contact.hs:84`) | absolute 1e-7 | planarity and contact |
   | `FlatFold.defaultTolerance` (`FlatFold.hs:142-163`) | 1e-5 radians | Kawasaki sums on rounded files |
   | `HingeSweep` (`HingeSweep.hs:26`, `:49-50`) | 64 machine epsilons coplanar; 1e-10 separation guard | one-hinge interval check |

   On the unit square, creasing's tolerance is 1.41e-9 while the glossary's
   hair is 1e-9. On a sheet 0.01 wide, creasing's is 1.4e-11 while `Flat`'s and
   `Folding`'s floor at 1e-9: about 70 times apart.

3. **Creasing already snaps, and says why snapping cannot be perfect.**
   - An end within tolerance of an existing corner *is* that corner.
   - Ends added in one batch merge to the **nearest** earlier end.
   - The header explains that being within a tolerance is not transitive, so
     merging is order-dependent at the margin (`Creasing.hs:131-137`,
     `:224-245`).
   - But `existingAt` returns the **first** vertex in id order within
     tolerance, not the nearest (`Creasing.hs:323-327`).
   - A landmark resolver built on these functions inherits both behaviours.

4. **The exact arithmetic that exists proves things; it does not name
   points.**
   - `PetalCertificate` defines `data Q = Q !Rational !Rational` for a + b√2.
   - Its `Ord` compares a² with 2b² when the signs differ, never approximating
     √2 (`PetalCertificate.hs:38-59`).
   - Division is safe only where callers establish a nonzero divisor
     (`:61-66`).
   - The stated purpose is to keep shared-plane zeros exact, so that polynomial
     signs bound a whole motion (`:6-11`; `docs/notes/checked-petal.md:27-32`).
   - The file's coordinates stay "ordinary rounded numbers"
     (`checked-petal.md:32`). The fixture is accepted by comparing its
     `Double` vertices with the Q-built material within 1e-12
     (`CheckedPetal.hs:50`, `:96`).

5. **Q(√2) is not closed under the constructions a sequence names.**
   - *Bird P is inside it.* The line bisecting the corner angle between the
     bottom edge and the diagonal has slope tan 22.5° = √2 − 1
     (`docs/notes/fish-and-bird-endpoints.md:11-18`). It meets the midline
     x = ½ at y = ½·(√2 − 1). Python: `tan(22.5°)/2 − y₉ = 5.6e-17`.
   - *One bisector leaves it.* Bisecting the angle between the bottom edge and
     a line of slope 1/3 gives slope √10 − 3, by the half-angle identity
     tan(θ/2) = sin θ/(1 + cos θ). Python residual: −1.7e-16.
   - *Axiom 6 leaves every tower of square roots*, because it solves a cubic
     (`docs/notes/huzita-hatori.md:7-9`).
   - *The rabbit ear's own positions leave it.*
     - The documented landmark formulas use c = cos 22.5° and s = sin 22.5°
       separately (`docs/notes/rabbit-ear-motion.md:62-67`).
     - cos 22.5° = √(2+√2)/2 is not a + b√2 with rational a, b. Squaring gives
       a² + 2b² = 2 and 2ab = 1. That forces 2a⁴ − 4a² + 1 = 0, so
       a² = 1 ± √2/2, which is irrational.
   - *The rabbit ear's rate constant leaves it.*
     - K = sin(π/16)/sin(5π/16) (`rabbit-ear-motion.md:30-31`).
     - Write K = cos(7π/16)/cos(3π/16). The field Q(cos π/16) has an
       automorphism σ₉ taking cos(kπ/16) to cos(9kπ/16). It fixes √2, since
       2cos(36π/16) = 2cos(π/4).
     - σ₉ sends K to cos(π/16)/cos(5π/16) ≈ 1.7654, which is not
       K ≈ 0.2346 (Python). An element of Q(√2) would be fixed.
     - So the `Q` type cannot host a rabbit-ear certificate as written.

6. **The only exact-field package in the snapshot is not usable.**
   - `cyclotomic ==1.1.2` is pinned (`lts-22.44.cabal.config:835`).
   - Its Hackage page gives the licence as GPL-3.0-only
     (https://hackage.haskell.org/package/cyclotomic-1.1.2).
   - Its module docs
     (https://hackage.haskell.org/package/cyclotomic-1.1.2/docs/Data-Complex-Cyclotomic.html)
     say it represents rationals, square roots of rationals, and sines and
     cosines of rational multiples of π. It does contain cos 22.5° and K.
   - It has no `Ord` instance. Real values convert to `Double` only
     approximately (`toReal`). It cannot represent nested radicals in general,
     or cube roots.
   - AGENTS.md's third-party table limits GPL code to research use. A
     certificate needs exact signs, which this type does not give.

7. **The round trip of numbers is partly evidenced, partly asserted.**
   - `Fold.Query.coord` prints with `showFFloat Nothing`
     (`Query.hs:429-430`). The `Explain` header calls that shortest
     round-tripping (`Explain.hs:93-95`).
   - The `base` docs (https://hackage.haskell.org/package/base-4.18.2.1/docs/Numeric.html)
     describe `showFFloat Nothing` only as full precision. They state no
     minimality for `floatToDigits` and no read-back guarantee.
   - For FOLD output, one test checks `eitherDecode (encode file) == Right file`
     on the bird sequence (`test/BirdSequenceSpec.hs:51`). That is evidence for
     those `Double`s, not a proof for all.
   - SVG rounds to three decimals (`Render/Svg.hs:332-337`).
   - F's syntax-tree sketch types fractions as `Rational` (`Along Name Rational`,
     `ArgNumber Rational`, F lines 473-489). E2 proposes refusing a point near
     but not within a hair of a vertex (E2 lines 431-437).

### B. Signatures, checked by hand

8. **What each documented formula needs.**
   - **Collapse.**
     - Mountains −m. Valleys 2·atan2(√2 sin(m/2), cos(m/2)). Flat guides 0
       (`docs/notes/symmetric-base-collapse.md:41-45`).
     - On the bird fixture the signs are reversed: the diagonal takes +m, and
       four midline rays take −v.
     - On the bird, a ray can be two collinear segments
       (`docs/notes/checked-square-collapse.md:10-13`;
       `CheckedBird.hs:110-114`).
   - **Rabbit ear.**
     - Foschi, Hull and Ku, Theorem 1, equation (2)
       (https://arxiv.org/html/2206.12691, CC BY 4.0). For a flat-foldable
       degree-4 vertex, one folding mode has ρ₁ = −ρ₃ and ρ₂ = ρ₄.
     - In that mode, tan(ρ₁/2) is tan(ρ₂/2) scaled by
       sin((α₁−α₂)/2)/sin((α₁+α₂)/2), where α₁ and α₂ are adjacent sector
       angles.
     - The note maps (PB, PE, PC, PA) = (−m, v, m, v), with α₁ = 45° and
       α₂ = 67.5° (`rabbit-ear-motion.md:16-32`).
   - **Petal.**
     - tan(s/2) = sin 22.5° · tan(t/2).
     - The hinge takes +t, four side creases −s, and two outer midline segments
       t − 180. Everything else keeps its current angle
       (`docs/notes/petal-fold-motion.md:45-55`; `CheckedPetal.hs:103-110`).

9. **The stars, measured.**

   *Method.* Python read each fixture's JSON. For every vertex off the border
   it took the bearing of each crease (`atan2`), sorted counterclockwise, and
   measured sectors between the creases that fold. This is the same shape as
   the library's `FlatFold.Star` (`FlatFold.hs:218-240`, `:415-426`,
   `:452-466`), which dissolves F/J and drops B/C.

   *The trap.* `Star` reads **target assignments**. A macro needs the
   **moving** set, which also depends on current angles (findings 12 and 16).

   | Fixture | Vertex | Folding rays, CCW bearing → target | Sectors between them |
   | --- | --- | --- | --- |
   | `square-base.fold` | v8 (centre) | 0° V, 45° M, 90° V, 180° V, 225° M, 270° V; F at 135°, 315° | 45, 45, 90, 45, 45, 90 |
   | `waterbomb-base.fold` | v8 | 0° M, 45° V, 135° V, 180° M, 225° V, 315° V; F at 90°, 270° | 45, 90, 45, 45, 90, 45 (the same cycle, rotated) |
   | `bird-base.fold` | v8 | 0° M, 45° V, 90° M, 180° M, 225° V, 270° M | 45, 45, 90, 45, 45, 90 |
   | `fish-base.fold` | v4 = P | 0° V (→E), 67.5° V (→C), 202.5° V (→A), 315° M (→B) | 67.5, 135, 112.5, 45 |
   | `fish-base.fold` | v5 = Q | 22.5° V (→C), 90° V (→v7), 135° M (→D), 247.5° V (→A) | 67.5, 45, 112.5, 135 |
   | `bird-base.fold` | v9 | 45° V (→v10), 90° M (→v8), 202.5° M (→v0), 337.5° M (→v1); F at 270° (→v4) | 45, 112.5, 135, 67.5 |

   Vertices v10, v11 and v12 give the same cyclic sectors as v9, rotated.

10. **Collapse signature, and its check.**

    *Signature.*
    - One interior vertex c has exactly **six moving rays**. Each goes from
      current 0 to target ±180, after merging collinear continuations.
    - Their cyclic sectors are (45, 45, 90, 45, 45, 90), up to rotation and
      reflection.
    - Every other crease at c is 0 in both states.
    - Each ray runs straight to the paper's edge. Where it passes through a
      vertex, every other crease there stays at 0.
    - **Roles.** The *pair* is the two rays flanked by two 45° sectors; they are
      opposite and collinear. The *four* are the rest.
    - **Signs.** The pair takes σ·m and the four take −σ·v, with σ = +1 when
      the pair's target is V.

    *Check.*
    - **Square.** The pair is at 45° and 225° (edges 12 and 8, both M): −m.
      The four are V: +v. This matches `symmetric-base-collapse.md:24-45`.
    - **Waterbomb.** The pair is at 0° and 180° (edges 11 and 15, both M).
    - **Bird.** The pair is at 45° and 225° (edges 9 and 8, both V): +m. The
      four take −v on both segments of each midline: 10 & 11, 14 & 15,
      18 & 19, 22 & 23. Hinges 26 and 27 and the side creases stay 0.
      `collapseAngles` writes exactly this (`CheckedBird.hs:114`).

    *Newcomer trap.* The pair is found from sectors, not from "rays to
    corners". The square's pair ends at corners; the waterbomb's ends at edge
    midpoints (`jq .edges_vertices`).

    *Where binding fails without help.* An eight-ray star at 45° whose rays
    are all marked M/V matches four ways, one for each opposite pair left out.
    The square base and waterbomb base *are* that star. They differ only in
    which opposite pair is F (`docs/notes/precreases-and-target-states.md:11-15`).
    So the F guides are the disambiguator.

11. **Rabbit-ear signature, and its check.**

    *Signature.*
    - An interior vertex has exactly **four moving rays**, all currently 0.
    - The target passes Maekawa (3–1) and Kawasaki.
    - **Roles.**
      - e₁ is the *lone* crease: the one whose assignment differs from the
        other three.
      - e₃ is the ray opposite it: two steps round.
      - e₂ and e₄ are the other two.
    - **Signs.** V is positive and M negative.
    - **Direction does not matter.** Walking clockwise from e₁ meets sectors
      180°−α₂, then 180°−α₁. Those give the same
      sin((α₁−α₂)/2)/sin((α₁+α₂)/2), so no orientation choice is needed. This
      follows from equation (2) and Kawasaki; I derived it, not the note.
    - Each ray reaches the paper's edge, or passes straight through a vertex
      where nothing else moves.
    - No crease that is folded, or that moves, lies inside a sector at the
      vertex. The panels at the vertex must be rigid for the step.

    *Check on the fish.*
    - **P.** The lone crease is edge 9 (M, toward B): −m. Opposite it is
      edge 8 (toward C): +m. Edges 10 (toward E) and 7 (toward A) take v.
      α₁ = 45° and α₂ = 67.5°, as documented. The manifest writes
      `[e7, e8, e9, e10] = [v, m, −m, v]` in every first-ear state
      (`cases.json`, `rabbit-ear` steps; `test/RabbitEarSpec.hs:232-234`).
    - **Q.** Going CCW from the lone crease, edge 13 (toward D), the sectors are
      112.5° then 135°. The ratio is sin(−11.25°)/sin(123.75°), identical to
      P's, because sin 123.75° = sin 56.25°. Edge 12 takes +m; edges 11 and
      14 take v. The manifest writes `[e11..e14] = [v, m, −m, v]`.
    - So signs taken from assignments reproduce both ears with no reflection
      special case. `docs/notes/two-rabbit-ears.md:20-25` explains the same
      result through traversal order.

    *Refusals that must happen.*
    - **Square and waterbomb.** The centre has six moving rays.
    - **Bird, from the flat sheet.** v9 has four folding rays in its target, but
      they run to interior vertices v8 and v10 whose other creases also move.
    - **Bird, from the square-base state.** Edge 10 is held at −180 inside a
      sector of v9.
    - **Same sectors are not the same vertex.**
      - The fish's P and the bird's v9 both have sectors {45, 67.5, 112.5, 135}.
      - The fish's lone crease sits between the 112.5° and 45° sectors. The
        bird's lone crease (toward v10) sits between 67.5° and 45°.
      - So the two ratios are sin(−11.25°)/sin(56.25°) ≈ −0.235 and
        sin(−33.75°)/sin(78.75°) ≈ −0.566: different vertices.
    - **Degenerate.** If α₁ = α₂, the ratio is 0. Equation (2) then holds the
      lone crease flat until the others close. That is derived, not tested;
      refuse it.

12. **Petal signature, and its check.**

    *The current state.* `birdAngles 0 0` (`CheckedPetal.hs:103-110`) gives, at
    v9:
    - edge 10 (toward v8) at −180, and edge 11 (toward v4) at −180. These are
      collinear: one straight folded line through v9;
    - edges 26 (toward v10), 12 (toward v0) and 13 (toward v1) at 0.

    The target (`bird-base.fold`) at v9 is: edge 10 M, edge 11 F, edge 12 M,
    edge 13 M, edge 26 V.

    *Signature.*
    - A crease h = PQ joins two interior vertices and is currently 0: the hinge.
    - Through each of P and Q runs exactly one straight line currently folded
      at ±180.
      - Its segment from P to a point W on the paper's edge is the *opening*
        crease.
      - Its inner segment stays where it is.
    - Two side creases, currently 0, run from P to edge vertices A and B, and
      from Q to B and C. B, the shared end, is the *tip*.
    - **Geometry the documented constant needs.** ∠PAW = ∠PBW = 22.5°, and
      PW ⟂ AB.
    - **Roles.** The hinge takes +t, the four sides −s, the two opening creases
      t − 180.
    - **Signs.** The hinge's target is V, the sides' M, and the opening creases'
      current angle is −180.

    *Check.* Python on `bird-base.fold`:
    - The angle at v1 from v4 to v9 is −22.5°, and at v0 it is +22.5°.
    - At v1 from v10 to v5 it is −22.5°, and at v2 +22.5°.
    - The dot product of v9→v4 with v0→v1 is exactly 0.0.
    - The moving set is edges {11, 12, 13, 15, 16, 17, 26}. That is seven
      creases, matching "Seven crease angles change" (`checked-petal.md:4`).
    - The back petal has hinge 27 (V), sides 20, 21, 24 and 25 (M), and opening
      creases 19 and 23, with the same signs. `birdAngles` applies the same
      signed formula to it (`CheckedPetal.hs:110`; `docs/notes/two-petals.md:16-23`).

    *What reverses.* No crease changes sign in any of the three macros. The
    petal's distinguishing creases **open** from −180 to 0. In
    `bird-base.fold` they are `F` at 0, like any guide. Only the current angle
    marks them, so petal binding cannot work from the target pattern alone.

    *Newcomer trap.* The 22.5° constant is geometry, not a property of petals.
    The note derives it from rotating W about AP with c = cos 22.5° and
    k = sin 22.5° (`petal-fold-motion.md:33-49`). A petal on a flap with other
    corner angles fails this signature and needs a formula nobody has derived
    here.

    *Refusals that must happen.*
    - **Bird, flat sheet.** No folded line runs through v9.
    - **Square and waterbomb fixtures.** They have no P or Q vertex. A petal
      there first needs creases drawn at constructed landmarks, which is part
      (a).

13. **Matches, counted.**

    | State | collapse | rabbit ear | petal |
    | --- | --- | --- | --- |
    | `square-base.fold`, flat | 1 (v8) | 0 | 0 |
    | `waterbomb-base.fold`, flat | 1 (v8) | 0 | 0 |
    | `fish-base.fold`, flat | 0 | 2 (v4, v5) | 0 |
    | `bird-base.fold`, flat | 1 (v8) | 0 | 0 |
    | `bird-base.fold` at `birdAngles 0 0` | 0 | 0 | 2 (hinge 26, tip v1; hinge 27, tip v3) |

    Within one match the roles are unique:
    - the collapse star's half-turn symmetry maps the pair to itself and the
      four to themselves;
    - a rabbit ear's e₂ and e₄ share one angle;
    - swapping a petal's P and Q maps each role set to itself.

    So only the *choice of match* needs a disambiguator. The existing code
    avoids that choice by hard-coding it:
    - stage names (`CheckedBird.hs:48`, `:83-87`);
    - an expected edge list (`CheckedPetal.hs:62`);
    - positional edge ids in prose (`two-petals.md:19-20`).

14. **Akitaya 2012: rewriting ideas, no numerics.**

    *What it is.* Read from the fetched PDF
    (https://www.cgg.cs.tsukuba.ac.jp/~akitaya/CSSeminarAkitaya.pdf): a
    University of Tsukuba seminar paper dated 2012-11-06. No licence is
    stated, so ideas only.

    *What it does.*
    - The crease pattern is an embedded graph. Each vertex keeps a cyclic,
      angle-sorted list of its edges; each edge has a mountain or valley type.
    - A maneuver is a rewrite rule. The system works backwards from the
      finished pattern, matching each rule's result subgraph by brute-force
      subgraph isomorphism.
    - A match is valid only if every affected node is locally flat-foldable,
      or lies on the paper's edge or on a "semi-complete reflection path".
    - All matches are kept as a step-sequence graph rather than chosen.
    - Timings: a crane took 451 ms (41 graph nodes). A frog base took about
      1.78 million ms (22,665 nodes).
    - Global self-intersection is left unsolved.

    *What is missing.* The text does not say whether matching compares sector
    angles, and says nothing about tolerance.

    *Ideas that transfer.*
    - Enumerate every match and make the choice explicit.
    - Validate a rewrite by local flat-foldability.
    - Searching all matches explodes on real bases, so an author-supplied
      disambiguator is the cheap alternative.

15. **#60's premise that macros are compositions does not hold for these
    three.**
    - Issue #60 item 4 calls reverse, squash and petal "a composition of the
      above", meaning turn-over, flap rotation and fold-along-a-line
      (`gh issue view 60`).
    - `Origami.Flap` turns one connected flap about one line and "does not
      discover coupled motions" (`Flap.hs:1-6`). `HingeSweep` checks one
      fixed-axis rotation (`HingeSweep.hs:49-50`).
    - A petal's seven creases turn at three rates: t, s and t − 180. The
      shoulder "does not turn at the tip's speed" (`checked-petal.md:10-15`).
    - A rabbit ear's valleys likewise outrun its mountain
      (`rabbit-ear-motion.md:55-58`).
    - Each coupled macro therefore needs its own angle relation. Composing flap
      turns cannot produce it.

### C. What can be certified, and how angles should be compared

16. **What any sampled pose gets on any pattern.**
    - `foldFrameWith` refuses torn vertices (`TornAt`) and unachieved crease
      angles (`loopsClose`) at `sheetTolerance` (`Folding.hs:368-377`,
      `:783-811`, `:847-854`).
    - The study adds static contact.
      - Every panel must be named exactly once (`StudyCase.hs:130-138`).
      - `checkPanelContact` reports crossings, unordered contacts, reversed
        orders and unchecked orders. `contactPassed` requires all four to be
        empty (`Contact.hs:56-61`, `:86-91`).
      - It is labelled diagnostics, not certification between saved states
        (`Contact.hs:93-97`).
    - Orders for paper in the air cannot come from the landing stack.
      Imposing the final stack mid-turn reports false reversals
      (`rabbit-ear-motion.md:75-83`; `checked-square-collapse.md:52-56`).
    - So a macro on an arbitrary pattern can check crossings at sample times.
      Orders apply only at flat endpoints, where the stacking solver may offer
      several (AGENTS.md, "A model usually has several valid layer orders").
    - The existing tests call half-degree sweeps "sampled geometry and
      contact, not continuous collision freedom" (`rabbit-ear-motion.md:85-89`).
    - The model depends on the file's own convention: **assignment is the
      target, angle is the current state.** `buildPoseAt` keeps the file's
      assignments and overwrites only `edgesFoldAngle` (`StudyCase.hs:154`).
      Binding (findings 10-12) relies on exactly that.

17. **What a certificate adds, and why it stays with its fixture.**
    - `PetalCertificate` builds exact polynomial paths and Bernstein sign
      bounds over the whole interval. A failed bound refuses; it never falls
      back to sampling (`PetalCertificate.hs:6-11`; `checked-petal.md:34-44`).
    - `preparePetal` accepts only a fixed fixture: the fixture's material
      vertices, cut faces and edge ids, the anchor `(0.58, 0.4)`, and orders
      along +z (`CheckedPetal.hs:47-60`).
    - Every pose is re-folded from angles and compared within 1e-12
      (`CheckedPetal.hs:67-74`).
    - Stage joins compare positions, angles, topology, orders and material
      coordinates (`CheckedBird.hs:139-146`).
    - Certificates exist for the collapse, the two petals and the press
      (`PetalCertificate.hs:17-27`). There is none for the rabbit ear, and
      finding 5 shows the `Q` field cannot reach one.
    - The library imports no study code (`docs/architecture.md:201`).

18. **Formula angles differ from stored literals in the last bit.**
    - At rabbit ear m = 30 the manifest stores `97.58514830800293`. The
      documented `atan2` form gives `97.58514830800294` in Python: one ulp,
      1.42e-14°.
    - The note chose `atan2` so the expression stays defined at the closed
      endpoint (`rabbit-ear-motion.md:35-37`). Python evaluation of the
      algebraically equal `2·atan(K·tan(m/2))` returns `…293`.
    - The same `tan` form reproduces the petal's t = 175 literal
      `-166.98236060695527`, where `atan2` gives `…518`.
    - Commit `0f94aa4` adds both the literal and the `atan2` note, and contains
      no generator (`git log -S`, `git show`).
    - **How the tests cope.**
      - Manifest-versus-formula comparisons use 1e-12 (`RabbitEarSpec.hs:49`,
        `:56`; `close` in `CheckedPetalSpec.hs`).
      - Copied literals are compared exactly (`BirdSequenceSpec.hs:41`, `:59`).
      - Coordinates use 1e-12, because "the same trigonometry on macOS and
        Linux differs in the last few bits" (`BirdSequenceSpec.hs:43-50`).
      - CI runs on `ubuntu-latest` (`.github/workflows/ci.yml:13`, `:38`, `:73`).
    - **Endpoints are pinned.** The code writes `if degrees == 180 then 180`
      (`CheckedPetal.hs:107`; `CheckedBird.hs:113`). In Python on this Mac, all
      three unguarded formulas already return exactly `180.0` there, so the
      guard's need was not observed on this platform.

## Implications for the design

1. **Landmarks are syntax; values are never stored in the tree.**
   - A point is a construction: a corner, a `Rational` fraction along a named
     line, the meeting of two lines, an O1–O7 result with its disambiguator,
     or a named vertex from an earlier step.
   - Evaluate it once per step to `V2 Double`. Resolve it with the tolerance
     creasing uses, `Faces.tolerance`, and say so in the PRD, because four
     "hairs" exist (finding 2).
   - Do not add a second near-miss threshold. When a point meets nothing,
     `Creasing` already refuses. The message should add the nearest vertex,
     its distance (via `num`), and its construction name if it has one.
   - Decide `existingAt`'s first-versus-nearest behaviour (finding 3) before a
     resolver depends on it. Refusing when two distinct vertices are within
     tolerance is the honest option.

2. **Round trip by printing the tree.**
   - Print `Rational`s as `n/d`, or keep the authored spelling in the located
     node if textual identity matters. `0.50` and `1/2` normalise to the same
     value.
   - Decimals parse to `Rational` exactly. They are never silently promoted to
     a construction: `0.2071067811865475` stays that rational, and resolution
     then decides.
   - If a DSL value carrying a `Double` is ever printed, add a property test
     for `read . show` on `Double`. The `base` docs do not promise it
     (finding 7).

3. **Keep exact fields in the study.**
   - Do not give the library a Q(√2) landmark type. It names the bird's
     vertices, but neither general constructions nor the fish (finding 5).
   - Do not depend on `cyclotomic` (finding 6).
   - PRD 3 should list a rabbit-ear certificate as research that needs a
     larger ordered field, not as a port of `PetalCertificate`.

4. **Bind from moving stars.**
   - Input: the current frame's angles and the target signs, following the
     convention in finding 16.
   - For each vertex: take the moving creases, merge collinear continuations
     through vertices whose other creases stay at 0, and measure the sectors
     between moving rays. Reuse `FlatFold.Star`'s shape, not its filter.
   - Each macro is a predicate on moving stars plus a role extraction
     (findings 10-12).
   - A refusal names the vertex, the measured sectors and the failed clause.
   - Compare sectors with `FlatFold`'s `Tolerance` (1e-5 rad by default,
     justified for files rounded to six decimals, `FlatFold.hs:142-156`), so
     that `check` and a macro agree about one file.

5. **Require a disambiguator whenever matches exceed one.**
   - Name it by material point: the tip corner, the centre vertex, or the
     hinge segment. Never by id, and never by "front/back": the back petal
     uses the same signs and moves *below* (`two-petals.md:21-23`).
   - Refuse 0 or ≥2 matches, listing the candidates. That is E2's rule, and
     finding 13 shows it is needed on the first real fixtures.

6. **Take signs from assignments; leave viewer words to presentation.**
   Assignment-derived signs reproduce both fish ears and both bird petals with
   no special case (findings 11-12). A caption such as "valley toward you" is
   a presentation fact, and belongs with the turn-over discussion
   (Z-critic contradiction 2).

7. **The macros depend on the at-rest convention (Z-critic gap 3.2).**
   - The collapse needs its guides marked F (finding 10).
   - The petal needs its opening creases' current ±180 (finding 12).
   - The rabbit ear needs target M/V on creases that are currently 0.
   - Under an "F at 0 for unbent" convention the target sign is lost, so the
     scheme would have to carry the target pattern separately. The PRD should
     pick the convention knowing that this binding depends on it.

8. **Label assurance per step, in the run result.**
   - Suggested sum type:
     - `EndpointOnly`;
     - `Sampled {parameters, checks}`, where checks name shared vertices,
       achieved angles, static crossings, and orders at flat endpoints;
     - `SweptHinge`, for `Flap`/`HingeSweep`;
     - `CertifiedPath name`, study only, attached only when the fixture guards
       of finding 17 pass.
   - A coupled macro on an arbitrary pattern reaches `Sampled` at most.
   - The CLI prints the label in its report.
   - Do not write FOLD's `nonSelfIntersecting` attribute to represent a
     motion. The spec defines it for faces in one frame
     (https://raw.githubusercontent.com/edemaine/fold/main/doc/spec.md).
   - A vendor key such as `senbazuru:assurance` must be written after the
     last transform, because transforms drop extras (AGENTS.md). GLB extras
     keep only a whitelist (Z-critic spot check 8).

9. **Angle equality policy.**
   - One Haskell function per formula, called by both interpreter and tests.
   - Schemes and manifests store the driving parameter (m, t) as `Rational`,
     never derived angles.
   - Exact equality is right only for:
     - driving parameters;
     - literals copied through the pipeline;
     - endpoints pinned by an explicit guard to 0 or ±180;
     - two outputs of the same binary on one platform.
   - Everything else uses one named tolerance with its reason. Today's 1e-12°
     works: it is about 70 ulps wide at 97°. Alternatively, derive it from the
     hair: 1e-9 rad per unit crease length.
   - Regenerating the rabbit-ear and bird manifests from formulas changes at
     least two stored values by one ulp. That is a reviewed fixture change,
     and it breaks exact comparisons of regenerated FOLD fixtures (A2 F31).
     Decide before writing acceptance tests.

10. **Correct #60's premise in the PRD** (finding 15). Coupled macros are
    library-defined angle relations with signatures, not compositions of flap
    turns.

## Open questions

1. Which hair should be canonical: creasing's diagonal with no floor, or
   `Flat`/`Folding`'s larger span with a floor of 1? Should they be unified
   before landmark resolution is specified?
2. Should a resolver refuse a point within tolerance of two existing vertices,
   or take the nearest? `existingAt` takes the first.
3. Should the petal refuse any geometry other than 22.5°, or should its
   constant be derived from measured corner angles? The first frog-base petal
   would decide this.
4. The rabbit-ear condition "rays reach the paper's edge, or pass through
   still vertices" may be too strict for a pattern built from several
   molecules. Can it be relaxed to "every other crease at those vertices is
   unchanged and the loop still closes", leaving the proof to `loopsClose`?
5. Which anchor should a macro choose? The petal needed an explicit stationary
   point because the moving tip triangle is the largest panel
   (`petal-fold-motion.md:60-64`). Should the signature pick a face beside the
   hinge on the side that does not move?
6. For DSL authoring from a flat sheet with no final pattern file, where do
   target signs come from: the macro's intrinsic relation (lone crease
   opposite, pair opposite four, hinge opposite sides) plus one author word?
7. Should `Sampled` assurance require a sample spacing, such as the tests'
   half degree, or only report the spacing?

## Unverified

- That GHC's `showFFloat Nothing` prints shortest round-tripping digits, and
  that `fromRational :: Rational -> Double` rounds correctly. The `base` docs
  fetched state neither; `Explain.hs:93-95` asserts the first.
- That GHC on this Mac gives the same bits as Python for the expressions in
  findings 1 and 18. GHC was not run. Also unverified: whether Linux libm
  changes these particular angles, and whether the 180 guard matters there.
- How the manifest literals were produced. The `tan` form reproducing both
  mismatches is suggestive, not established.
- Whether an ulp-level angle change can move an SVG golden at a three-decimal
  rounding boundary.
- The rule that the ratio is independent of direction, and the degenerate
  α₁ = α₂ case (finding 11), are my derivations from equation (2). They were
  not run through `foldFrameWith`.
- The sign agreement for the fish's second ear was checked against manifest
  literals by edge index, not by folding; `RabbitEarSpec` folds them, but I did
  not run it.
- That the collapse signature holds for any pattern whose rays pass straight
  through intermediate vertices. It is shown for the bird fixture only, by its
  certificate.
- That "hinge sign opposite side creases" holds for every petal. It is checked
  on the two bird petals only.
- Whether Akitaya's implementation compares sector angles during matching.
  The paper does not say.
