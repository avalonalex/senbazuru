# Critique of research slices H1–H7: what a rendering PRD still lacks

Completeness critic, written 2026-09-28 against `main` at `83fc960`. Nothing
under the repository was modified. I read all seven notes in full: H1 diagnosis,
H2 sheet mechanics, H3 contact, H4 inflation, H5 photoreal, H6 illustration and
H7 tooling. I also read [research G](../../PRDs/research/G-realistic-rendering-and-simulation.md)'s
summary and implications, decisions D14, D15 and D17–D19 and the owner-decision
table in `PRDs/decisions.md`, the non-goals table in `PRDs/00-overview.md`,
`docs/notes/illustration-material-priority.md`, `the-puff-is-a-drawing.md`,
`opening-a-crane.md` and `docs/related-projects.md`. Where two notes disagreed
on a number, I reran their scripts on the same input. My scripts and the one
fetched PDF are in `scripts/Z2-critic/` beside this note.

> **Status, 2026-09-28.** This is the completeness critique of research
> slices [H1](H1-diagnosis.md)–[H7](H7-tooling.md), written before the second
> round of experiments. Its proposed experiments ran as
> [Y1](Y1-valid-curved-looks.md)–[Y6](Y6-fea-oracle.md), and its conflicts are
> resolved in [PRD 11](../11-prd-refined-final-forms.md).
> [V](V-verification.md) corrects its B6: the two doubled-ink metrics overlap
> rather than being disjoint. Its B1 predates [X3](X3-crane-opening.md), which
> demonstrated a fourth start route (cut at the folds, stitch back under
> contact).

**Evidence tags.** `[code]` a file and lines read; `[note]` a repository note
or research slice read at the place cited; `[ran]` a command I ran (given);
`[fetched]` a page or PDF fetched on 2026-09-28 whose text I read;
`[search]` a search-result summary only, not the source itself (treated as
UNVERIFIED for anything load-bearing); `[reasoned]` my own derivation.

**Words used here.** A *start* (or *starting state*) is the mesh a solver
begins from. *Admissible* means every pair of non-neighbouring surface pieces is
already farther apart than the paper's thickness, which barrier contact
requires ([H3](H3-contact.md) finding 4). *Creep* is the outward shift of a fold
that wraps other layers ([H3](H3-contact.md) "Terms"). *Gauss–Newton* is the
study's solver, which minimises a sum of squared residuals; an *energy
minimiser* minimises any energy, including terms that are not squares, such as
a log barrier or `−p·V` for pressure `p` and volume `V`. A *tension-field*
membrane resists stretching but lets paper shorten for free
([H4](H4-inflation.md) "Terms").

## Summary

The seven notes are strong. Most of their numbers were re-measured on this
repository's own meshes, and they agree on the central diagnosis: the preferred
"More tucked" crane is an authored sketch that no paper can take
(H1 findings 4–7, H2 finding 4, H3 finding 3, H7 finding 1). They also agree on
the direction: valid geometry first, reached along a path from a valid state,
and presentation fixes that never hide a defect.

A PRD cannot yet be written from them without six decisions and one kind of
evidence that no note supplies:

1. **No agreed route to a valid, thick starting state.** Three notes propose
   three incompatible routes (B1). None has worked beyond a single fold: H7's
   double fold stalled at 0.77°, and the other two are untested. The industrial
   practice for exactly this problem, folding an airbag mesh with thickness,
   is not cited by any note (E1).
2. **Two model choices are open, and so is the threshold.** Should the solver
   minimise squared residuals or a general energy (B2)? Should the membrane be
   symmetric or tension-field (B3)? Which strain screen applies, the owner's
   0.1% or the notes' 1% (B4)?
3. **Repository constraints are not reconciled** (C). D18 lists *sliding
   contact* as a non-goal, and every IPC recommendation is frictionless sliding
   contact; no note says so. H7's in-library IPC contact contradicts D15 stage
   4. The recommended mesh sizes exceed owner decision 12's settle caps.
4. **Three things the owner named have no evidence behind them.**
   - *Finite-element analysis as such:* no note assesses a general shell FEA
     code, although `docs/related-projects.md` lists four (E2).
   - *The waterbomb:* H4 studied a cube as a stand-in; nobody has the flat
     model (A, gap 3).
   - *Steps:* how an inflate or spread step appears on a page (A, gap 2).
5. **No experiment separates presentation from geometry.** Every look
   experiment used the invalid More-tucked shape. No note rendered the one
   valid non-flat crane result, the wing spread with the body held, through the
   new recipes. That split decides how much of the L–XL mechanics work the
   owner's "refined" actually needs (experiment X1).

Two measurements of my own sharpen this. The baseline for doubled ink is two
different quantities (B6). And H6's restyle, which removes every duplicate, still
leaves 3.6× the production crane's ink (D, weak claim 11). So ink alone will not
reach book density, but that "book density" target was set against a flat
crane, which may be the wrong reference.

## Findings

### A. Coverage against the owner's request

| Element of the request | Where covered | Status |
| --- | --- | --- |
| Why the material study does not look refined | H1 (whole note), H6 findings 2–6 | **Covered well**, with measurements |
| Mesh modelling of the paper | H2 findings 12–17 and R7, R10; H6 I6 | Covered; display subdivision is unsafe on stacks (D, weak claim 13) |
| Finite element analysis | H2 (discrete shells, bar-and-hinge, StVK); H1 finding 22 | **Partly.** "FEA" is reframed as specific missing pieces (H1 finding 22), which is right, but general shell FEA is never evaluated, even as an oracle (E2) |
| Inflation of the crane body | H4 findings 10–17, implication 6; H2 R5 | Model and load designed; **nothing run on a crane**; the mouth loop is unnamed (H4 open questions) |
| Inflation of the waterbomb | H4 finding 7 (a cube stand-in), implication 7 | **Gap.** No flat-folded waterbomb fixture exists (H1 finding 27), and no note checked whether senbazuru can produce one today |
| Wing spread | H1 finding 1 (accepted, body held); H4 finding 16 | The one **valid** non-flat result, yet no note renders it through the new looks (gap 4) |
| Rendering of the final origami, photoreal | H5 | Covered; recipe run on the invalid shape only |
| Rendering of the final origami, book style | H6 | Covered; prototype exists; the "book" reference class is two Wikimedia SVGs (weak claim 12) |
| "Steps" that involve inflation or spreading | H6 finding 19 (one line on the inflate symbol) | **Gap.** See gap 2 |
| What "refined" means, measurably | Every note's acceptance section | Six overlapping metric sets with different definitions (B6, B7) |

**Gaps a PRD must close.**

1. **The start is the blocker, and the notes disagree on the route.** See B1
   and E1.
2. **How a non-flat step appears in a step sequence.** The owner wrote "steps
   involve inflation … or spread the wing". Three things follow, and no note
   designs any of them.
   - *The camera.* A step page has one camera and one scale (`AGENTS.md:370`
     [code]). A finished puffed figure is drawn from three-quarters
     (`the-puff-is-a-drawing.md:39-45` [note]), so something has to give.
   - *The symbols.* The inflate and pull arrows that PRD 06 would carry are
     mentioned once (H6 finding 19).
   - *The motion.* The opening could be shown as an animation. D19's motion
     axis lists "animated flexible" as research, and G implication 5 allows
     morph targets only for dense, checked keys [note]. A path-following
     solver (H2 R3, H7 Stage 5) produces exactly such keys, and no note
     connects the two.
3. **The waterbomb has no fixture.** H4 inflated a closed cube instead.
   Checking whether a flat-folded waterbomb balloon can be produced now is
   cheap, either from a generated crease pattern through `senbazuru fold` or
   through a `.foldseq`. It is the prerequisite for the second named case
   (experiment X5).
4. **Valid shape against invalid shape, through the same look.** All
   presentation experiments used More tucked: H5 findings 2–4 and 22, H6 all,
   H7 finding 14. The accepted wing spread with the body held (392 and 1,192
   triangles, `spreading-connected-wing.md:35-39` [note]) and the #394 body
   specimen (strain 0.0018%, H1 finding 5) are the only near-paper non-flat
   shapes. No note shows what H5's recipe or H6's restyle make of them.
5. **No physical ground truth.** Every note that asks whether More tucked is
   reachable (H1 open questions; H2 R9; H4 open questions) ends with "a
   photograph would settle it". Nobody proposes measuring a real crane in 3D.
   Photogrammetry runs on the owner's Mac: Apple's Object Capture API
   (`PhotogrammetrySession`) is available on macOS 12 and later [search]
   (experiment X9).
6. **Inverse design.** The owner chose a pose by eye; a physical solve will
   land elsewhere. Only H3's handle pulling in the IDP style (finding 6) and
   H2's isometric projection (R9) address the gap, and neither was run. No note
   proposes adjusting the *controls* (grips, rest angles, target volume) to
   match an owner-chosen silhouette, or estimates how far physics will land
   from More tucked (experiment X2).
7. **The renderer's own scaling.** The mechanics notes want 2,190–5,475
   triangles (H3 finding 18), about 5,000 (H2 finding 19) or about 13,000 (H7
   finding 7). The drawing's visibility step clips every triangle pair:
   about 200k pairs per view at 448 triangles and about 51M at 16×
   (H6 "Two notes on cost", reasoned). D19's residue already says W1's cost at
   4,312 triangles is unmeasured (`PRDs/decisions.md:1565-1568` [code]). The
   drawing, not the solve, may become the bottleneck, and no note measured it
   (experiment X7).
8. **One plan.** The notes propose about 40 work items with two effort scales:
   H2 counts M as 1–2 weeks, H7 as about a week. They also propose three
   orders:
   - H7 Stage 5: waterbomb base, then wing, then body, then inflation;
   - H4: pillow benchmarks, then crane grips, then waterbomb;
   - H3: the crane thick start first.

   A PRD needs one dependency graph with an explicit go/no-go gate. The cheap
   visible items should come first: H1's paper screen, H6 I1–I3 and H5's viewer
   pass, each S.
9. **Machine learning is neither used nor excluded.** No note mentions image
   generation or neural rendering. The PRD should exclude them in one line,
   for determinism, provenance and licence, so the question is not reopened.
   [reasoned]

### B. Conflicts between notes

**B1. Three routes to a thick, admissible start, and none demonstrated
beyond one fold.**
- **H2 R4.** Offset each layer by its stacking rank × `t` from `faceOrders`,
  rejoin the creases with strips about `n·t` wide, and accept strain in those
  strips "over a width proportional to `t`" [note].
- **H3, implication 3 and Phase A.** Thicken the valid *closed* crane in its
  flat state with a directional solve, with crease vertices free in the plane
  so that creep can happen. H3 finding 18 proves that heights alone cannot
  separate nested creases, and the folded crane has 206 such pairs [note, ran
  by H3].
- **H7 findings 3, 13 and 22.** Naive rank offsets leave 2,125–2,309 pairs
  closer than the thickness. Folding from the flat sheet with the barrier on
  works for one fold (179.24°–179.39°, no intersection), but the double fold
  stalled at 0.77° after 622 s [note, ran by H7].

H7's measurement refutes the naive form of H2 R4, and H3 finding 18 explains
why. H3's creep solve is untested, and H3 itself ties it to the same kind of
separation that failed four times (#379–#385). None of the notes considers a
fourth route, the airbag industry's (E1). **Consequence:** the PRD's first gate
must compare these routes on the same small fixtures with the same checker
(experiment X4).

**B2. What kind of solver: least squares or energy.**
- H4 designs everything as least-squares rows in the study's Gauss–Newton
  solver: one-sided principal-stretch rows, and a volume row whose multiplier is
  the pressure. It shows that `−p·V` cannot be a row (finding 12), and falls
  back to L-BFGS when pressure must be a force (implication 10) [note].
- H2 (R8, the solver row of finding 19) and H7 (Stage 3) move to Newton on the
  total energy with element Hessians and PSD projection [note].
- H3 and H7 Stage 4 want IPC's log barrier with a CCD-limited line search.
  That is an energy method [note].

These are one architectural decision, not four independent items. The PRD
must choose it once, because it decides whether H4's rows, H2's Hessians and
H3's barrier can live in one solver.

**B3. Membrane: symmetric or tension-field.**
- H2 R2 recommends a per-triangle StVK membrane at paper's physical stiffness.
  StVK charges shortening as well as stretching.
- H4 finding 4 shows that symmetric charging produces the wrong pillow: 0.172
  instead of about 0.20 side³, folded along mesh lines. It recommends
  one-sided tension-field rows instead (implication 1).
- H4 finding 2 also shows that tension-field rows without bending crumple
  through themselves on a fine mesh: 30 crossing pairs at the disc rim.
- H2 finding 9 says real paper answers compression with a few sharp crimps.

A symmetric membrane would need a mesh fine enough to form those crimps; a
tension-field membrane gives the smooth average and needs bending plus contact
where the paper is slack. The PRD must choose per region and say what the
drawing shows (H2 open question "crimps or declared strain", H4 implication 9).

**B4. Strain threshold.**
- The owner's provisional screen is 0.1% local strain
  (`illustration-material-priority.md:11-17` [code]).
- H1 G1 proposes at most 1%, with 0.1% as "the stricter option".
- H2 finding 21 argues that 1% is roughly the visibility threshold.
- H4 finding 8 says 0.1% is "already generous" for paper.
- H7's ipctk envelope "works" at about ±1% edge strain (finding 12), ten
  times the screen.
- H2 R4's crease strips would exceed either threshold locally.

The PRD must pick one number and say whether crease strips, virtual caps and
declared schematic regions are exempt.

**B5. Paper parameters.**

| Note | Thickness | Young's modulus `E` | Poisson ratio `ν` | Bending stiffness `B` |
| --- | --- | --- | --- | --- |
| H2 findings 5–8 | kami, 72 µm | 4 GPa (assumed) | 0.23 | 1.31e-4 N·m |
| H4 finding 8 | 0.1 mm | 3 GPa (Kent paper) | 0.3 (assumed) | 2.7e-4 N·m |
| H3, H7, PRD 07's material block | 1/1500 of the sheet, which is 0.1 mm on 15 cm | — | — | — |

The two bending stiffnesses differ by 2×, which moves H4's pressure scale
`p̂ = pL³/B`. The PRD needs one default paper, stated once.

**B6. The doubled-ink baseline is two different measurements.**
- H1 finding 15 reports that 22–28% of contour ink lies within 1 px of a
  parallel contour.
- H6 finding 2 reports that 74–78% is drawn twice.

I ran both scripts on the same `book-checks.json` [ran]:

```bash
python3 scripts/H1-diagnosis/doubled_contours.py scripts/H1-diagnosis/gen/whole-crane/book-checks.json
#  upright 1724 of 7775 px (22.2%) … top 27.4%
python3 scripts/H6-illustration/duplicates.py   scripts/H1-diagnosis/gen/whole-crane/book-checks.json
#  upright 6064 of 7775 px (78%) overlapped by an opposite-direction contour … top 74%
```

H1's script counts only neighbours at distances between 0.02 and 1.0 px
(`doubled_contours.py`, the test `0.02<dd<1.0` [code]), so it excludes exact
duplicates by construction. The two figures are complementary, not rival.
H1's ink-density baseline (23.6) therefore counts H6's duplicates twice
(weak claim 11).

**B7. The metric sets overlap but disagree.**
- **Short ink.** H1 D4 allows no ink segment under 2 px; H6 allows no
  *dangling* stroke under 5 px.
- **Doubled ink.** H1 D2 allows at most 2% within 1 px; H6 targets 0% exact
  duplicates.
- **Crossings** have three counts on one pose:
  - 345 by the study's checker (H1, H3, H7);
  - 289 by H5's BVH test (finding 4);
  - 512 by H3's own test (finding 16).
- **Close pairs on the closed crane**, near the thickness `1/1500`, have three
  counts that measure different things:
  - 27,596 vertex–triangle and edge–edge pairs within `6.7e-4` (H3 finding
    16);
  - 17,335 ipctk stencils, meaning point–triangle and edge–edge pairs as
    ipctk builds them (H7 finding 2);
  - 16,693 triangle pairs (H5 finding 14).

The PRD must name one reference checker per gate and report the others only
as oracles.

**B8. Display subdivision against "the same geometry for SVG and GLB".**
- H2 R10 proposes Loop subdivision with crease tags as a display-only second
  view.
- H5 finding 16 notes that the owner's milestone rule is to keep SVG and GLB
  on the same geometry (`illustration-material-priority.md:56` [code]), so any
  smoothing must reach both, or be labelled display-only.
- H6 I6 prefers densifying in 3D, or Phong tessellation.

Subdivision that approximates rather than interpolates moves vertices. A gap
of one thickness between layers is 0.3–0.4 px at 600 px per sheet (H2 finding
8; H5 finding 8), so the smoothing can create crossings. No note tested this
(weak claim 13, experiment X8).

**B9. Line weights disagree with PRD 08.** H6 finding 8 shows that PRD 08 W1
styles a silhouette at crease weight 1.0 (`PRDs/08-prd-realistic-rendering.md:690`
[code]). The book convention the notes found says the outline is heaviest (H6
findings 17–18). This amends a merged PRD, so it must be listed as such.

**B10. Two different disagreements with G implication 6.**
- G ordered the work "thickness, then contact".
- H3 finding 5 says the thickness offset in C-IPC is a *stricter requirement*
  on the start, not a way to build one.
- H7 finding 22 says "thickness *is* contact": a barrier with a thickness
  floor produces the offset as the paper folds.

Both go beyond G in different directions. H7's version held for one fold only.

**B11. Smaller discrepancies.**
- **Failure strain.** H1 fetched a paper failure strain of about 6% for kraft
  handsheets, while H2's Unverified list says no failure strain was found in a
  fetched source.
- **Wrap radius.** H3 notes that the repository's `n·t/2` and its own
  `(n+1)·t/2` differ in what `n` counts.

Both are minor, but the glossary should hold one definition of the wrap count.

### C. Repository constraints the recommendations ignore or misread

1. **D18's "sliding contact" non-goal.** `PRDs/00-overview.md:376` explains it
   as "touching layers sliding along each other" [code]. H3's unsigned barrier
   is frictionless ("Friction. None at first", implication 4) and lets a flap
   go around another (finding 20). H2's contact row and H7 Stage 4 are the same
   kind. Every one of them is sliding contact. H1 and H7 list the D18 items
   *pressure or inflation* and *thickness as geometry* for amendment. **No note
   lists sliding contact,** and nothing lists *calibrated paper*, which H2 R1
   approaches; H2 does propose the label "illustrative, kami-like".
2. **D15 stage 4.** Only penalty contact rows graduate to `Material.Contact`,
   barrier rows stay in the study, and "graduating barrier rows no graduated
   solve uses" is rejected (`PRDs/decisions.md:1303-1325` [code]). H7 Stage 4
   proposes an IPC-style `Material.Contact` in the library without flagging
   the conflict. H7 does flag the separate D15 stage 2 problem, that
   `SparseSolve` should not graduate as written.
3. **Owner decision 12.** Default CI settles at most 392 triangles, and
   `run --settle` refuses more than 1,192 until #208 is measured
   (`PRDs/decisions.md:2196` [code]). H2, H3 and H7 recommend 2k–13k-triangle
   meshes. Only H1 cites the cap. The recommendations must either stay
   study-only or amend the decision.
4. **D14 depends on which start is chosen, and H7 overstates it.** D14
   requires a settle to start from `recordBefore`, which must be flat, and
   forbids settled geometry from entering a later step
   (`PRDs/decisions.md:1183-1186`, `:1247-1250` [code]). The flat folded crane
   *is* flat. So H3's route, thickening it inside one settle, needs no D14
   amendment, only a clarification that a continuation of static solves inside
   one settle is allowed [reasoned]. H7's route, carrying a thick material
   state from the flat square through every step, does need the "material
   track" amendment H7 finding 22 proposes. H7 presents the amendment as
   required in general.
5. **D19's geometry axis** offers rigid panels, bent zero-thickness, thickness
   offsets, and "as read" (`PRDs/decisions.md:1463-1467` [code]). H1
   implication 1's label "geometry: as prescribed" is not a value on it, so a
   sketch label needs a D19 amendment.
6. **D17 and D14 against H4's Blender prototype.** H4 implication 8 offers
   Blender cloth for "a picture of the target within a day". D17 makes
   external solvers comparison oracles, never ahead of the in-repo path. D14
   rejects "substituting … an external solver on failure"
   (`PRDs/decisions.md:1287-1288`, `:1427-1429` [code]). H4 implication 8 also
   puts a `bpy` script under `study/` without the licence question that H5 and
   H7 raise (a script using Blender's API must be "GPL compliant" if
   published).
7. **"Measure, do not reason about, performance."**
   - *Single runs.* H7's `SparseSolve` and `hmatrix` timings are single runs
     (H7's own Unverified list).
   - *Possible load.* The slices appear to have run concurrently. The same
     gallery command took about 122 s user time in H1, H3 and H7 but
     3 min 49 s to 5 min 18 s of wall time across slices (H1 finding 4;
     H3 finding 3; H6 "Cost"; H7 finding 1) [note]. Timings in H3 finding 19
     and H7 findings 5–13 may carry that contention. UNVERIFIED; rerunning
     them alone, 3–5 times, would check it.

### D. Load-bearing claims with thin evidence

1. **Locking causes the false creases** (H1 finding 10; H2 finding 13). It is
   reasoned from English & Bridson and the study's weights. Nothing reran a
   bend with a softer membrane or a finer, flipped mesh. H2 R2 and R7 and H1
   implication 4 rest on it (experiment X3).
2. **H2 R4's offset start is near-isometric with length error about `t`.**
   This is reasoned, and it is contradicted by H3 finding 18 and H7 finding 3
   (B1).
3. **H3 Phase A will converge.** It is untested. Its support, that creep
   explains #379's `3.18e-5` error, is an arithmetic hypothesis (H3's own
   Unverified list).
4. **H7's double-fold stall as the go/no-go for the whole barrier route.**
   The evidence is one prototype: 8×8 mesh, finite-difference hinge gradients,
   a fixed barrier stiffness of 1 and a 60-iteration cap. Its cause is
   UNVERIFIED (H7 finding 13). That is weak evidence in either direction for a
   decision this large.
5. **H7's ipctk envelope "works".** It ran at about ±1% edge strain; the 48×48
   run hit its iteration cap with CHOLMOD warning of non-positive-definite
   matrices (finding 12).
6. **H4's benchmark thresholds.** The volume of 0.2006 side³ and the ±2%
   tolerance come from runs that stopped at their iteration limits. The upper
   bound of 0.217 is marked "citation needed" on Wikipedia (H4 finding 2 and
   Unverified). They are proposed as test thresholds (H4 implication 3).
7. **Paper constants.** Kami's `E` = 4 GPa is assumed (H2 finding 6), and
   `L*/t` comes from pre-folded paper and Mylar (H2 finding 7). H4 uses Kent
   paper at 0.1 mm with ν = 0.3 assumed. H4 also applies the wrinkle-wavelength
   law outside its stretched-sheet setting (its own Unverified list).
8. **"1% strain is roughly the visibility threshold"** (H2 finding 21). It is
   reasoned from one panel length of 0.2 sheet, yet it drives a proposed
   acceptance number ten times looser than the owner's screen.
9. **"The GLB's two-copy sheet breaks every path tracer"** (H5 summary). Only
   Cycles was measured. Mitsuba and three-gpu-pathtracer are UNVERIFIED, as H5
   itself notes in finding 2.
10. **The H5 viewer pass (S) will look refined.** The recipe constants were
    chosen by eye on the invalid shape. Transmittance comes from a search
    snippet, and shadow acne and frame rate on zero-thickness sheets were not
    tried (H5 Unverified).
11. **H1's ink-density target D3** asks for at most 1.5× the flat crane's
    density, and its baseline counts duplicates twice (B6). I measured the ink
    per stroke width with subpaths split at each moveto [ran]:

    ```bash
    python3 scripts/Z2-critic/ink_subpaths.py <gallery>/spread-0-upright-book-full.svg \
      scripts/H6-illustration/proto-upright.svg docs/img/crane-folded.svg docs/img/bird-open.svg
    ```

    | Drawing | Ink / bounding-box diagonal | By stroke width |
    | --- | ---: | --- |
    | Current book drawing, upright | 23.6 | contour 14.5, crease 9.1 |
    | H6 prototype restyle, upright | 17.5 | outline 3.3, interior 5.5, crease 8.7 |
    | Production flat crane (`crane-folded.svg`) | 4.8 | 1.6 px: 1.3, 1.0 px: 3.6 |
    | Production open bird (`bird-open.svg`) | 5.5 | — |

    Removing duplicates cuts contour ink by 39%, from 14.5 to 8.8. Even with
    every crease mark omitted, the contours alone are 1.8× the flat crane's
    *total* ink. So either the remaining interior contours (crumpled panels and
    splayed layers, H6 findings 5–6; H1 finding 17) must go through geometry
    work, or the flat crane is the wrong reference for an opened 3D bird.
    Neither note says which.
12. **What an instruction-book finished crane looks like.** The reference
    class is two Wikimedia SVGs plus two conventions pages. The published book
    figures by Lang, Montroll and Kasahara are UNVERIFIED (H6 finding 22). The
    owner asked for "instruction-book quality".
13. **Display subdivision is safe as a second view** (H2 R10). It is untested
    on stacked layers 0.3–0.4 px apart (B8). H6's Phong-tessellation crack risk
    is UNVERIFIED as well.
14. **The linear-solve cost of contact in Haskell** at about 50k active pairs
    is UNVERIFIED (H3 finding 19). Only the broad phase was timed, on a
    fixture that tears the creases. It is load-bearing for whether contact can
    be written in Haskell at all.
15. **Pressure separates the cavity walls** (H4 finding 17). It was tested on a
    pillow and a cube, not on interleaved flaps.

### E. Literature and tools missed

1. **Airbag folding, the closest industrial analogue.**
   - *The paper I read.* Sharma, Mukherjee and Chawla, "A Mechanism of Meshing
     a Folded Airbag" (IIT Delhi) [fetched]. It builds the folded mesh
     geometrically, one fold at a time, as stacks of connected planar layers
     with a declared *fold thickness*, the distance between the innermost
     layers after a fold. Outer layers take a larger circumference than inner
     ones, which is creep by construction. Inner-layer penetration must be
     avoided because it is "catastrophic" in the later unfolding simulation.
     The flat, unfolded surface is what matters, and the folded mesh is only
     the start.
   - *Commercial practice* [search]. LS-DYNA and Abaqus inflate such meshes
     with self-contact from a separately declared stress-free reference
     geometry, the "initial metric" method (SAE 950875; `*AIRBAG_REFERENCE_GEOMETRY`;
     Abaqus `*INITIAL CONDITIONS, TYPE=REF COORDINATE`).
   - *Why it matters.* This is a fourth start route. Build the thick state
     geometrically, move by move, alongside the rigid sequence records, rather
     than solving for separation afterwards (H3) or folding under a barrier
     (H7). It maps onto senbazuru's runner, since a move is a fold about a line
     through known layers, and onto H3's wrap counts.
   - *Its limit, as the paper states it.* The tools restrict fold lines to
     parallel or orthogonal folds of the whole stack. A crane's reverse and
     petal folds are harder. This limit is from the paper.
2. **General shell FEA.** `docs/related-projects.md:43-60` lists LS-DYNA,
   Abaqus, CalculiX, Code_Aster, Kratos, MERLIN, Blender and ArcSim for exactly
   this problem [code]. `the-puff-is-a-drawing.md:162` cites Melancon et al.,
   Nature 592 (2021), whose inflatable origami used shell elements, pressure
   and self-contact [code; search]. No note assesses the open-source codes even
   as oracles, and H2 dismisses commercial FEA in one line. Since the owner
   named FEA, the PRD should say why the discrete-shell route is chosen over
   shell FEA: crease modelling, licence, determinism and the learning goal. It
   should cite evidence rather than silence.
3. **Paper-specific developable modelling.** Three papers are not cited.
   - Solomon, Vouga, Wardetzky & Grinspun, *Flexible Developable Surfaces*
     (CGF 2012). It enforces exact developability at every step and gives a
     subdivision that keeps bent regions developable [search]. That is the
     smoothing-without-stretching tool that H2 R10, H6 I6 and H1 implication 4
     ("a ruling-based developable panel model") are reaching for.
   - Schreck et al., *Nonsmooth Developable Geometry for Interactively
     Animating Paper Crumpling* (TOG 2015). It interleaves physical steps with
     procedural developable surfaces and sharp features [search].
   - Burgoon, Wood & Grinspun, *Discrete Shells Origami* (CATA 2006). It is the
     direct precedent: discrete shells fold simple origami, and more advanced
     models need collision handling [search]. The fetch failed on a TLS
     certificate, so the text is unread.
4. **Physical measurement tools.** Photogrammetry, through Apple Object Capture
   on macOS 12 and later [search], and H2's cantilever droop test for the
   bending stiffness `B` (open question) would turn "a photograph would settle
   it" into a number.

### F. What the set does well, and a PRD should keep

- Most figures were re-measured, not copied. H1, H3, H6 and H7 each
  regenerated the gallery and reproduced the committed notes' numbers.
- The notes correct the brief where it was wrong. H3 and H7 note that
  "≈58% / 152% / 266" describes the `narrow` pose, not More tucked; More tucked
  has 345 crossing pairs.
- I confirmed H2's central claim in the code. More tucked is
  `pillowCraneAtSpread 0`, which calls `pillowCraneWith 0.5`; the body map is
  the flat material rotated, plus a dome, with one axis scaled by 0.5
  (`WholeCrane.hs:157-160`, `:177` [code]). That is a 50% compression written
  into the target.
- Licences were checked with `gh api` throughout. GPL material was read for
  ideas only; H7 declined to read SuiteSparse's LGPL `LDL` code.

## Implications for the PRD

1. **Put the decisions first (S).** The owner has to rule on all of these
   before any L-sized work:
   - amending D18 for pressure or inflation, thickness as geometry, **sliding
     contact** and calibrated paper, or labelling;
   - D15 stage 4, if contact is to reach the library;
   - owner decision 12's triangle caps, or study-only status for large meshes;
   - the strain screen (B4);
   - the default paper (B5);
   - a D19 value for "sketch";
   - whether Blender or ipctk scripts may live under `study/`;
   - whether an oracle's shape may ever be shown to reviewers as the picture.
2. **Ship the cheap, honest wins before the mechanics (S each).**
   - H1 implication 1's paper screen printed beside every drawing;
   - H6 I1–I4 (single ink, role weights, chaining, defect report);
   - H5's viewer pass and its R-08-6 amendment.
   - H1 implication 8's visible-change rule would have stopped the
     15-PRD repair series.
3. **Gate the mechanics on experiments X1, X2 and X4 (below).** X1 says how
   much of the owner's "refined" needs valid geometry at all. X2 says whether
   More tucked is reachable. X4 picks the start route or ends the barrier
   branch.
4. **Choose the solver form once** (B2), then the membrane per region (B3).
   Everything H4 designed as rows must be re-expressed if the answer is
   "energy".
5. **Unify the metrics** (B6, B7) into one scorecard with one reference
   checker, and state the step-page design (gap 2) and the waterbomb fixture
   (gap 3) as their own requirements.

## Experiments, smallest and most decisive first

| # | Goal | Method | What it tells us | Effort |
| --- | --- | --- | --- | --- |
| X1 | Split "not refined" into its presentation part and its geometry part | Take three shapes: More tucked (`spread-0`, invalid), the accepted wing spread with body held (1,192 triangles, valid) and the #394 body specimen. Render each three ways: the current book drawing, H6's `book_v2_prototype.py` restyle, and H5's Cycles recipe with the sheet rebuilt as one two-sided surface. Show the owner blind pairs at fixed cameras | If the valid shapes read as refined under restyle or recipe, the look is mostly presentation plus shape validity, and the L–XL work is justified. If even valid shapes look unrefined, the missing ingredient is elsewhere: tone, line roles, thickness cues or pose | S: 1–2 days; scripts exist |
| X2 | Can the More-tucked silhouette be paper at all? | H2 R9 in Python: a local/global isometry projection of `spread-0` toward its own positions, with anchors on wing tips and body top, and membrane plus bending terms; no contact. Report silhouette displacement at 600 px, strain, false creases and crossings | Under about 5 px of movement, More tucked is a legitimate target for a path solve. Tens of pixels means the owner must accept a different look or a declared schematic. Answers H1 and H2's first open question | S–M |
| X3 | Is locking the cause of the false creases? | On one held strip, or the 392-triangle wing fixture: the length weight at `1e8` against the physical `≈4.3e6` (H2 finding 2), and the triangle diagonals flipped or refined. Count joins bent over 45° and measure the silhouette change | If joins bent over 45° vanish and the silhouette is stable, R2 and R7 are the fix. If not, the kinks come from the construction, not the membrane | S |
| X4 | Which start route works on stacked layers? | Run the double fold and the quarter fold four ways: (a) H7's fold-from-flat under ipctk, with analytic gradients, adaptive barrier stiffness, a graded crease-strip mesh and additive CCD; (b) H3's creep solve on the folded state; (c) H2 R4's offsets plus strips; (d) airbag-style geometric thick folding, one fold at a time with the outer radius `(n+1)t/2`, then relaxed. Use one checker: ipctk `has_intersections` false, smallest gap at least 0.99 `t`, strain within the chosen screen outside crease strips, second fold at least 175° | Picks the route, or ends the barrier branch (H7's no-go). Settles B1 and weak claims 2–4 | M |
| X5 | Does the second named case have a model? | Generate the traditional waterbomb balloon's crease pattern (licence-clean). Try `senbazuru fold` and `check`, or a `.foldseq`, to get the flat state with `faceOrders`. If it exists, inflate it with H4's `pillow.py` rows plus a virtual cap over the blow hole | Whether the waterbomb is blocked on the sequence runner (M4/M5) or ready now. Whether the tucked flaps need contact (H4 open question) | S for the flat state; M for inflation |
| X6 | Can the study's least-squares solver host inflation? | In a scratch copy of the study: one-sided principal-stretch rows plus the volume row (H4 implications 1–2) on the 8- and 16-cell pillow. Compare with H4's 0.1953 / 0.2006 side³ and the Mylar disc | If it matches within 2%, inflation needs no new solver and B2 can stay least squares for loads. If not, the energy solver becomes a prerequisite | S–M |
| X7 | Can the drawing consume the recommended meshes? | Time `depthDrawing` plus `CraneBookDrawing` at 448, 1,792 and 7,168 triangles: compiled, 3–5 runs each, machine otherwise idle | If time grows faster than the solve, a broad phase for the drawing (H6 I6) is a prerequisite of any refinement. Fills D19's residue | S |
| X8 | Is display smoothing safe on stacks? | Loop subdivision with sharp tags on M/V/B edges (Blender's Subdivision Surface modifier with crease weight 1) and Phong tessellation, applied to `before.fold` and the valid wing spread. Count new crossings and pairs closer than `t`, and the contour turning angles | Whether H2 R10 and H6 I6 can ship before thickness exists. Settles B8 and weak claim 13 | S |
| X9 | Ground truth for "refined" and "reachable" | The owner folds a 15 cm kami crane, opens it to a More-tucked-like pose and takes about 40–60 photos. Apple Object Capture on the M1 Max produces a mesh. Measure body height and width, wing droop, tip separation and underside opening, and compare silhouettes with `spread-0` at the gallery cameras. Optionally, a cantilever droop test of one strip gives `B` | A physical reference for X2's target, H4's photo protocol and H5's cue list. The owner's own data, so provenance is clean | S: half a day |
| X10 | Is an external shell FEA oracle worth having? | The square pillow, and optionally the double fold, in CalculiX or Code_Aster: shell elements, pressure, self-contact. Run, not vendored (D17). Compare with H4's tension-field numbers | Answers the owner's "finite element analysis" directly, and says whether a general FEA code adds anything over ipctk or Blender as an oracle | M |

## Acceptance ideas for the PRD as a whole

One scorecard, each row with a single definition and its source. Values are
today's for More tucked, upright view.

| Axis | Metric (single definition) | Today | Source |
| --- | --- | ---: | --- |
| Paper | Largest principal strain per triangle; screen chosen once (B4) | +106.8% / −83.6% | H1 finding 4 |
| Paper | Angle-sum change per vertex, at most 1° | 99 vertices over 5° | H1 finding 6 |
| Paper | Panels whose triangle normals spread more than 90° | 5 | H6 finding 6 |
| Contact | Strict crossings by the study checker; ipctk as oracle | 345 | H1, H3, H7 |
| Contact | Smallest non-incident gap at least 0.99 `t` | 0 | H3 finding 16, H7 finding 2 |
| Ink | Exact duplicate contour ink (H6 definition) | 78% | B6 |
| Ink | Near-parallel ink within 0.02–1 px (H1 definition) | 22% | B6 |
| Ink | Ink density after de-duplication, against a *3D* book reference (to be chosen, gap 12) | 17.5 after restyle | weak claim 11 |
| Ink | Loose contour ends not at a cusp | 7 | H6 finding 4 |
| Look | H5 A1 wrong-side pixels, at most 1% | 44.5% (Cycles GLB import) | H5 finding 2 |
| Look | Owner blind A/B plus H5 A7 cue checklist | — | H5, H6 |
| Process | A visible change of at least 1 px at 600 px per sheet, stated per PRD | — | H1 implication 8 |

## Sources fetched

All on 2026-09-28.

- Sharma, Mukherjee, Chawla, *A Mechanism of Meshing a Folded Airbag*, IIT
  Delhi PDF: <https://web.iitd.ac.in/~achawla/PDF%20Files/A%20Mechanism%20Of%20Meshing%20A%20Folded%20Airbag.pdf>.
  Text extracted with `pdftotext` (`scripts/Z2-critic/airbag.txt`); abstract, §1–2 and
  the layer-folding section read. Undated; its references include the same
  authors' Int. J. Crashworthiness 10(3) 2005 paper.
- Search summaries only, not read in full, and marked `[search]` above:
  - airbag initial-metric and reference-geometry practice (SAE 950875;
    LS-DYNA FAQ slides; an Abaqus example page that returned 403 when
    fetched);
  - Burgoon, Wood, Grinspun, *Discrete Shells Origami*, CATA 2006
    (<https://digitalcommons.calpoly.edu/csse_fac/204/>; the PDF fetch failed
    on a TLS certificate);
  - Melancon et al., Nature 592 (2021) 545–550;
  - Schreck et al., TOG 35(1) 2015
    (<https://dl.acm.org/doi/10.1145/2829948>);
  - Solomon, Vouga, Wardetzky, Grinspun, CGF 31(5) 2012 (the Wiley page
    returned 403);
  - Apple `PhotogrammetrySession`
    (<https://developer.apple.com/documentation/realitykit/photogrammetrysession>).

## Open questions for the owner

- Is the goal a picture that *looks* like a book's finished crane, which X1
  may show needs little mechanics, or a shape that *is* paper? The answer
  decides whether gates X2 and X4 are worth L–XL work.
- If physics moves the crane away from More tucked, which wins: the look, as a
  declared schematic, or the paper?
- Should the PRD adopt airbag-style geometric thick folding as the start
  route to test first, since it needs no contact solver?
- Is an external FEA or IPC oracle's shape ever acceptable as the reviewed
  picture, given D14 and D17?

## Unverified

- Everything tagged `[search]` in E1–E4, in particular that LS-DYNA and Abaqus
  use a separate stress-free reference geometry for folded airbags. Reading
  the SAE paper or the LS-DYNA manual would check it.
- Whether the airbag paper's method extends to reverse and petal folds. It
  restricts fold lines to parallel or orthogonal folds of the whole stack.
- That the slices' timings were contended (C7). It is inferred from differing
  wall times for similar user times; rerunning alone would check it.
- My ink densities include H1's convention of normalising by the bounding-box
  diagonal of all path points. A different page extent would change the
  ratios, not the ordering.
- I did not rerun any mechanics experiment. Every number in B1–B5 and D1–D10
  is from the notes' own runs.
