# H1. Why the material study's crane does not look refined

Research slice H1, written 2026-09-28 against `main` at `83fc960` (clean tree
apart from an untracked `.claude/`). Nothing under the repository was modified.
Pictures were rasterised and measured in a scratch directory; the one program
run from the repository was the already-built study executable, writing its
output outside the checkout (finding 4 gives the command).

> **Verification, 2026-09-28.** [V](V-verification.md) re-checked this note.
> Its load-bearing geometry figures reproduce exactly. Corrections: the share
> of area above 50% strain is "about 13%" (two triangles sit exactly at the
> bin edge); the 99 vertices of finding 6 *changed* angle sum (54 down,
> 45 up), not "lost" it; finding 15's 22–28% measures *near-parallel* contour
> ink and is a different defect from [H6](H6-illustration.md)'s exactly
> duplicated ink; finding 15's explanation of strokes stopping in mid-paper is
> **refuted**: they are single boundaries that end where layers cross
> (H6 finding 4); finding 16's material previews hold 2,048 triangles in
> 188 fill paths, not 381 separate triangles; the commit counts of finding 3
> are 119 and 35 by whole days; "31 body PRDs" are PRs. Finding 10's
> attribution of the false creases to locking is **refuted** by
> [Y3](Y3-locking.md): the pose's construction makes them (they carry the same
> total turning at every mesh resolution; **corrected 2026-09-29:** at the
> three Y3 measured, and not at two finer ones, #438); locking is real but
> secondary.
> Scripts named
> `scripts/H1-diagnosis/…` are kept; the PNG crops it names are not.

**Evidence tags.** `[code]` file and lines read; `[note]` a repository note
read at the cited lines (a note's numbers were not re-run unless also tagged
`[ran]`); `[issue]` read with `gh issue view`; `[ran]` a command I ran, given in
full or named by its script; `[fetched]` a web page fetched on 2026-09-28;
`[paper]` a paper whose text I read; `[reasoned]` my own derivation. Anything I
could not check is in **Unverified**.

**Relation to research G** (`PRDs/research/G-realistic-rendering-and-simulation.md`,
2026-09-14). G surveyed rendering levels and external simulators before most of
the crane work happened. This note does not repeat that survey. It diagnoses
the 31 body PRDs and 4 whole-crane PRDs that came after it (#318 to #404). Where
it agrees with G it cites G's finding numbers. Where it goes further or
disagrees, it says so.

## Summary

The whole-crane pictures look unrefined mainly because **the shape being drawn
is not paper**. Better ink or lighting cannot fix that.

**Geometry.** The preferred "More tucked" pose (`spread-0`) is authored, not
solved. I regenerated it from the committed fixture and measured it:

- 74% of the sheet's area is stretched or squashed by more than 10%. Real paper
  tears at roughly 1–6%.
- 99 of 237 vertices have lost the flat sheet's angle sum by more than 5°.
- 15 joins inside panels bend by more than 45°. These are folds the crease
  pattern does not have.
- 345 pairs of triangles cross through each other.

The distortion comes from how the shape was built. The body specimen solved in
#394 stretches by only 0.0018%. The whole-crane construction smears that
opening into the rest of the sheet with a formula that ignores paper lengths,
and the pillow targets then replace the solved body with a dome. A dome is
curved in two directions at once, and paper cannot take that shape without
stretching.

**Solver.** The solver never produced these shapes, for four reasons:

1. Crane-scale solves are static. Each starts from a prescribed guess that
   often already intersects, not from a valid state moved in small steps.
2. Contact is a zero-thickness penalty ordered along one fixed axis. It cannot
   order walls that stand upright, and a barrier cannot start from layers that
   touch.
3. Nearly unstretchable edges on a few hundred flat triangles *lock*: the mesh
   can bend only along its triangle edges.
4. It is slow at the sizes a smooth crane needs: one 512-triangle solve took
   195 to 2,492 CPU seconds.

About 15 PRDs of single-pair contact repairs each moved the paper by less than
0.2 drawing pixels.

**Presentation.** The drawings add their own defects:

- The plain previews ink only crease and boundary lines, so parts of the
  outline have no line at all. Every stroke in them has the same weight.
- The book drawing puts 23.6 drawing diagonals of ink on the page, against 4.8
  for the production flat crane. 22–28% of its outline ink is doubled within
  1 px.
- The plain previews use one flat tone and the book drawing three quantised
  tones.
- Same-colour fills in separate paths leave hairline seams.
- Nothing suggests thickness or shadow.

The production flat drawings of the same model are clean. The problem is
specific to the curved pipeline.

## Findings

Some words first. **Strain** is the fractional change of a length: +10% means
a stretch of 10%. A triangle's **principal strains** are its largest stretch
and largest squash in any direction, not only along its edges (`FoldRelaxation.hs:195-221`,
`principalStrains`). A surface is **developable** if it can be flattened
without stretching (cylinders, cones); a dome is not [fetched: Wikipedia].
**Gaussian curvature** measures that, and for a triangle mesh it shows up as a
change in the sum of corner angles around a vertex: paper that only bends keeps
its flat angle sum exactly. A **J edge** (join) is a numerical triangle edge
inside one [panel](../../docs/glossary.md), not a crease (`docs/glossary.md:64`).
A **contour** is a visible edge of paper against background or against paper
at another depth. A **silhouette** is the part of the contour where a smooth
surface turns away from the viewer. **Penalty** contact charges energy for
penetration that has already happened. A **barrier** charges energy that grows
without bound as two surfaces approach, and needs a positive gap to start
(`directional-contact-distance.md:36-50` [note]).

### A. What the study tried for non-flat shapes, in order

**1. The chronology.** Dates are merge dates from `git log --format='%h %ad %s'
--date=short` [ran]; outcomes are from the notes and issues cited.

| Dates (2026-09) | PRs | Approach | What it did | Outcome | Record |
| --- | --- | --- | --- | --- | --- |
| 10 | #121 (issue #114) | Rounded crease fillets | Replace a crease by a half-cylinder band of width πr, with r = 0.015 | One fold is isometric (no stretch). A second perpendicular fold stretches the upper band by **200%** and adds **4.71%** area; making r smaller does not help | `two-bends-need-more-than-radii.md:44-57` [note] |
| 10 | #122 | Gauss–Newton length restoration | Linearise every edge-length error, solve for all vertex moves together, then line-search | Lengths alone let a layer rise through another by 2.9e-4. Adding a packet-order penalty meets both targets | `restoring-material-lengths.md:15-23` [note] |
| 12 | #151, #153 | Bending and hinge springs | k(θ−θ₀)²/2 on every shared edge: crease weight κl, panel weight Bl/h | Double fold settles at 173.8–177.2°, with interior bends up to 2.017° | `crease-and-panel-energy.md:19-31`, `:73` [note] |
| 12 | #155–#167 | Penalty contact on declared, discovered or learned layer orders | Charge negative gaps along one fixed direction; orders come from a separated reference pose or are learned while approaching | Flap and curled-strip controls settle; a different starting order can stall | `ordered-flap-contact.md`, `reference-contact-discovery.md`, `growing-local-contact-history.md` [note] |
| 12 | #161, #169, #171 | Swept-interval certificates | Bernstein-basis sign bounds prove two triangles stay apart through a rigid hinge turn or a straight numerical step | Rigid routes are certified. The closing strip stalls at **1.13%** length error, because the penalty jumps when shadows begin to overlap | `hinge-sweep-contact.md`, `checking-numerical-corrections.md`, `rejected-bending-trials.md` [note]; `directional-contact-distance.md:55` |
| 13 | #173 | Directional barrier | IPC's scalar barrier applied to the distance to *violating a retained order* | Closing strip settles at 1.18e-8 after 99 checked corrections. It is wired only into the local-history strip mode, and its API takes no holds, so it never ran on a crane | `directional-contact-distance.md:52-61`; `body-barrier-comparison.md:45-47` [note]; `BendingGallery.hs:273` [code] |
| 13 | #176–#192 | Checked **rigid** flap routes | Exact polynomial sign checks of rigid rotations: blintz, both bird petals, square-base collapse, helmet | **Worked.** 23 bird states exported | `study/fold-material/README.md` §"Crease preferences" [note] |
| 13–14 | #197–#207 | Pinned holds; wing bending | Exact grips removed from the unknowns; coupled sparse factor; one crane wing spread with the **body held** | **Accepted** at 392 and 1,192 triangles in 5.76 and 64.30 CPU s. Freeing four body panels fails | `spreading-connected-wing.md:35-39`; `wing-root-holds.md` [note] |
| 14 | #209–#215 | Body release with angle preferences; internal crease holds | Free four body panels; vary preferences at creases 21/46 and 26/51 | All unconverged after 118 iterations: 49 crossing triangle pairs, about nine CPU minutes each | `body-angle-preferences.md:72-77`; `internal-crease-diagnostic.md` [note] |
| 14 | #217–#225 | Exact nonnegative contact at one crease | Constrained gaps instead of penalties | The penalty leaves −6e-11; the constraints give exact zero, but only on 32- and 64-triangle fixtures | `nonnegative-crease-contact.md` [note]; #195 items 9–13 [issue] |
| 15–20 | #228–#314, about 40 PRs | Mesh-refinement and cost-convergence studies: bands, prescribed bends, held panels, illustration-scale overlays | Refine bands from 2×1 to 8×2; compare energies and openings | Targets missed (opening changes 37.74%). One 512-triangle solve takes **2491.6 CPU s**. The owner deprioritised this on 09-20 | #195 items 14–47 [issue]; `illustration-material-priority.md:3-9` [note] |
| 20 | #318 | Body patch | 16 panels joining both wing roots, free outer boundary; 30 and 120 triangles; 5° and 10° grips | Coarse runs pass geometry but never settle. The refined run fails: 4.01% length error, 124 crossing pairs | `coupled-body-patch.md:44-65` [note] |
| 20–21 | #320–#328 | Checkpoint audit, subdivision of the recovered shape, crossing diagnosis, replay, geometry-gated continuation | Mostly no new solves | "Seven tiny moves, followed by a blocked search"; the full proposed move stays about 11,670× above the stopping limit | `body-geometry-continuation.md:4-8`; `body-correction-replay.md` [note] |
| 22–24 | #330–#375, 15 PRs | **One contact pair at a time** | Add linear guard rows for the limiting triangle pair; minimum-movement repairs | Each accepted move shifts the paper by 0.005–0.17 drawing px. Every larger trial exposes a neighbouring pair. Owner paused this on 09-24 | `body-contact-direction.md`, `body-contact-pairs.md`, `body-restoration-loop.md`, `body-fourth-pair.md`, `body-overlap-restoration.md`; `body-barrier-comparison.md:3-21` [note] |
| 24 | #378–#386 | Separated, constraint-first, crease-based and contact-aware **initialisations** | Four ways to build a start with positive gaps, so the barrier can begin | None gives an intersection-free separated start, so the barrier-versus-penalty comparison never ran | `body-barrier-comparison.md:84-116` [note] |
| 26 | #388 | Exact audit of the saved equations | All 1,204 inequalities pass exactly | So the failure was numerical accuracy of the saved direction | `body-angle-audit.md:7` [note] |
| 26 | #390–#396 | Drawing-scale screens, visible layers, one larger 10° opening, intersection in context | One 40-correction continuation from the recovered seed | Body depth 21.7 → **43.5 px**, strain **0.0018%**, one intersection of 0.232 px. Unsettled: the proposal is 5,138× above the stop | `body-larger-opening.md:40-62` [note] |
| 26 | #398 | **Prescribed whole-crane sketch** | Copy the 49 body vertices; rigid-fit the wings; spread the rest by a graph continuation; circular wing bend | 5.26% edge error, +22.3% stretch, 683 crossing pairs. The bounded correction diverges to 745% edge error | `whole-crane-candidate.md:16-57` [note] |
| 26 | #400 | **Pillow targets** and wing-spread slider | Release the body; authored dome cushion; wing arches; continuation weighted by 1/length | 57–104% edge error; 217–345 crossing pairs | `crane-pillow-target.md:31-84` [note] |
| 27 | #402 | Interactive GLB viewer | Browser selection of the nine GLBs | Presentation only | `crane-pillow-target.md:133-145` [note] |
| 27 | #404 | Panel lighting; book drawing | Normals averaged per panel; three tones; contour ink; optional short-crease omission | Lighting seams reduced; the shape defects are unchanged | `crane-panel-lighting.md`, `crane-book-drawing.md` [note] |

**2. A pattern separates what worked from what did not** [reasoned from finding 1].

Every accepted non-flat result shares three things:

- it started from a valid state;
- it moved a small region a small step;
- it held nearly everything else.

The rigid routes, the wing with the body held (392 and 1,192 triangles) and the
coarse and 10° body specimens all fit this.

Every failure did one of these instead:

- released many touching layers at once (four body panels; the refined patch);
- started from a guess that already crossed (the 10° guess has layers reversed
  by 9.32 px, `body-larger-opening.md:40-58` [note]);
- was not solved at all (whole crane and pillow).

**3. Where the effort went** [ran]. `git log --oneline --since=2026-09-10 --
study/fold-material | wc -l` gives 111 study commits since 09-10, and 31 since
09-20. Between 09-20 and 09-26 there are 31 body PRDs (#318–#396). Of those, 15
are single-pair guards and repairs. They changed the drawing by amounts like
**0.00533**, **0.0858**, **0.01398** and **0.165** px, while each full proposal
stayed **9,036–11,670×** above equilibrium:

- `body-contact-direction.md` 0.00533 px, 11,376×;
- `body-contact-pairs.md` 0.0858 px, 11,438×;
- `body-geometry-continuation.md` 0.01398 px;
- `body-restoration-loop.md` 0.165 px, 5,326×;
- `body-short-corrections.md` 9,036× [note].

Nothing a reader can see changed. That series was the solver's fight with
contact, not illustration work.

### B. Root causes: geometry

**4. The pictures the owner reviews are authored sketches, and I measured them
as far from paper** [ran]. I regenerated the gallery with no solve, writing
outside the repository:

```bash
.stack-work/install/aarch64-osx/6ae0…/9.6.7/bin/senbazuru-material-study \
  --whole-crane-start study/fold-material/fixtures/whole-crane-body.fold <scratch>/gen
# 121.85 s user, 3:57.84 wall; git status unchanged
```

Its `checks.json` reproduces the notes' figures, and adds figures for the
preferred pose:

| State | Max relative edge error | Max stretch / squash | Crossing triangle pairs | Reversed orders | Unchecked orders |
| --- | ---: | ---: | ---: | ---: | ---: |
| Closed crane | 1.4e-11 | ≈0 | 0 | 0 | 0 |
| First candidate (#398) | 5.26% | +22.3% / −5.7% | 683 | 3,060 | 0 |
| Narrower body (#400) | 58.04% | +152.2% / −82.1% | 266 | 1,927 | 32 |
| **More tucked (`spread-0`)** | **57.29%** | **+106.8% / −83.6%** | **345** | **1,982** | **32** |

An independent script, `scripts/H1-diagnosis/strain_stats.py`, recomputes the principal
strains from `spread-0.fold`'s material coordinates. It reproduces +1.0680 and
−0.8363 exactly and gives the spread over area:

| Strain magnitude above | 1% | 5% | 10% | 25% | 50% |
| --- | ---: | ---: | ---: | ---: | ---: |
| Share of sheet area, More tucked | 89.7% | 83.6% | **74.2%** | 39.0% | 13.0% |
| Share of sheet area, first candidate | 52.1% | 7.0% | 1.7% | 0% | 0% |

For scale:

- Quasi-static tests on kraft handsheets break at roughly **6%** strain
  [fetched: Baumann et al. 2024].
- A paper-properties table lists stretch of **1.1–4.7%**, depending on grade
  and direction [fetched: paperonweb].
- The owner's provisional illustration screen is **0.1%**
  (`illustration-material-priority.md:11-17` [note]).

So three quarters of the preferred crane is stretched past the point where real
paper would tear. What *looks* wrong follows from this: pinched wing roots,
splayed neck and tail layers, an umbrella-like body top.

This agrees with G finding 5 that study shapes can stretch. It goes further:
the pictures the owner is judging sit on G's geometry axis at "as prescribed",
not at G3's "bent panels with contact". G3's own level is unmet for the whole
crane.

**5. The distortion comes from the construction, not from a solve**
[code, note].

- **The body specimen was nearly paper.** #394's 10° body keeps strain at
  0.0018% (`body-larger-opening.md:40-58`).
- **The first whole-crane candidate copies that body and adds 5% error.** It
  copies those 49 vertices exactly, but carries the body's movement into the
  remaining paper by `continueDisplacements`. That is a linear graph
  calculation in which neighbouring vertices prefer equal displacement
  (`WholeCrane.hs:232-250`). The module's own comment calls it an "INITIAL
  GUESS" that "can strain paper" (`WholeCrane.hs:7-9`). The result is 5.26%
  edge error.
- **The pillow targets abandon the solved body altogether.** They prescribe a
  cushion and wing arches, then continue displacements with weight
  1/restDistance (`WholeCrane.hs:171-201`). The comment says this "still cannot
  enforce paper lengths or contact" (`:198-200`).
- **The notes say the same.** The linear graph calculation "does not preserve"
  edge length (`crane-pillow-target.md:58-63`).

Each step that made the silhouette more crane-like made the paper less like
paper. Measured over the #400 series, edge error falls from 104% to 57% only
because the body was narrowed.

**6. The pillow cushion is curved in two directions, so paper cannot take its
shape** [code, ran, fetched].

The cushion height is a product of two parabolas,
`max 0 (1-(x/r)^2) * max 0 (1-(z/r)^2)` (`WholeCrane.hs:171-177`). That is a
dome: curved along both x and z. A developable surface has zero Gaussian
curvature; a dome's is positive [fetched: Wikipedia, "Developable surface"].

`scripts/H1-diagnosis/angle_defect.py` compares each vertex's sum of corner angles in
3D with the same sum on the flat sheet; bending without stretching keeps them
equal.

| State | Vertices changed by more than 5° | … more than 20° | Largest change |
| --- | ---: | ---: | ---: |
| Closed crane | 0 | 0 | 0° |
| First candidate | 3 | 0 | 9.7° |
| More tucked | **99** of 237 | **42** | 164.9° |

A real opened crane gets its fuller body from curved panels that stay
developable, plus creases and small wrinkles. It cannot get it from a smooth
dome [reasoned]. Any target drawn as a dome will stay invalid however it is
relaxed.

**7. False creases: joins bent where the paper has no fold** [ran].

Bend angles come from `checks.json` `angles`. Each hinge is classified by its
FOLD `edges_assignment` in `spread-0.fold`.

| Edge kind | Count | Bent over 20° | Bent over 45° | Largest | Mean |
| --- | ---: | ---: | ---: | ---: | ---: |
| J (join inside a panel), More tucked | 408 | 48 | **15** | **172.6°** | 10.1° |
| F (flat crease), More tucked | 42 | 14 | 8 | 95.2° | 24.6° |
| J, first candidate | 408 | 17 | 4 | 62.5° | 3.2° |

The crane has 76 source panels, each cut into only 4–12 triangles. A
median-area triangle is about 34 drawing px on a side at the study's 600 px per
sheet unit [ran].

The authored curves turn much less than these joins do [reasoned]:

- The wing arch has radius 0.5/(π/6) ≈ 0.955 sheet units, 573 px
  (`WholeCrane.hs:184-190`). A 34 px chord turns about 3.4° and bulges
  0.25 px.
- The cushion across its narrowed axis turns at most about 27° per edge.

So joins bent past 45° are not how a coarse mesh samples a designed curve. They
are kinks: folds with no crease in the pattern, which the book note calls
"pointed joins at the wing roots" (`crane-book-drawing.md:57-58` [note]). The
mean 10° join bend is what the panel-lighting pass (#404) hides in the 3D
preview.

**8. Layers pass through each other, and a fixed contact axis cannot even
check some pairs** [code, ran].

More tucked has 345 crossing pairs and 1,982 reversed orders (finding 4).

- **The contact check depends on a height direction.** It needs at least one
  triangle of each pair to be a height function along a fixed direction; two
  upright triangles are an error (`SurfaceContact.hs:1-11`). Every pillow
  state reports **32 unchecked orders**.
- **Crane-scale solves take that direction from the world axis.** `CraneSpread`
  turns face orders into lower/upper pairs by the z-sign of each face normal
  and solves contact along +z (`PRDs/decisions.md` D14, "Records are
  unpresented"). `solveSpread` calls `relaxPinnedContact`
  (`CraneSpread.hs:169-172`).
- **The whole-crane correction reuses that policy,** and the note already
  doubts it (`whole-crane-candidate.md:53-55` [note]).
- **An opened body turns its walls upright**, where a z-order means nothing.
  The crane-opening note warns against exactly this (`opening-a-crane.md:78-79`
  [note]).

**9. Releasing a closed, zero-thickness stack needs a separated start the study
cannot make** [note].

- **Touching layers are at zero distance.** In the flat crane every touching
  layer pair sits at distance 0. A barrier "needs a positive gap"
  (`body-separated-initialization.md:21`).
- **All four initialisations failed:**
  - separated: four corrections, then negative gaps;
  - constraint-first: the first direction fails verification after 115
    iterations, 487.93 CPU s;
  - crease-based: the loops close, but 4 or 18 pairs cross;
  - contact-aware: fails after 34 inner iterations

  (`body-barrier-comparison.md:84-116`; `body-feasible-initialization.md:76-80`;
  `body-crease-seed.md:64`; `body-angle-contact.md:65`).

This agrees with G finding 13 and G implication 6: thickness has to come before
general contact. Here it is confirmed by failure, not just predicted.

**10. Nearly unstretchable flat triangles lock, and that is why the study's
curves come out as folds along mesh edges** [paper, code, reasoned].

English and Bridson show the mechanism. On a mesh of flat linear triangles,
requiring no stretch keeps each triangle rigid, so the mesh can bend only along
its existing edges. With stiff but not rigid edges, the same effect appears as
"a spurious increased resistance to bending" set by in-plane stiffness. They
cite Liu et al.'s result that an n-triangle conforming mesh has only O(√n) free
degrees of freedom [paper: English & Bridson 2008, §1].

The study is in exactly this regime:

- the final length penalty weight is 1e8 (`FoldRelaxation.hs:543`);
- contact is 100× that (`:638`);
- panel bending weights are Bl/h with B = 0.2 in every crane fixture
  (`WholeCrane.hs:60`; `FoldBending.hs:218`);
- acceptance needs 1e-5 relative length error
  (`FoldRelaxation.hs:125-126`).

The consequence for pictures is finding 7. Smooth bending costs as much as
stretching, so a solver or a sketch expresses curvature as a few sharp folds at
triangle joins.

This goes beyond G finding 11, which says the study "lacks a membrane energy".
The study does penalise all in-plane strain, since three edge lengths fix a
triangle's shape (`FoldRelaxation.hs:11-12`). The harm comes from using that
penalty as a near-hard constraint on coarse linear triangles, not from its
absence.

**11. The crane-scale solver stalls rather than converges** [note, code].

- **Tiny accepted steps.** The 10° body's last accepted step is **1/65,536** of
  its proposal, and the full proposal is 5,138× above the stop
  (`body-larger-opening.md:60-62`).
- **Weighted cost is not geometry.** The whole-crane correction lowers its
  weighted cost for 19 moves, reaching **745%** edge error, then finds no
  descent (`whole-crane-candidate.md:50-53`).
- **Why, in the code.** The line search halves a Gauss–Newton step up to 30
  times and accepts any energy decrease (`FoldRelaxation.hs:680-697`).
  Energy mixes lengths weighted up to 1e8, contact at 1e10 and bending at order
  1 (`:674-676`).

A decrease in that sum can trade huge stretching for a small contact gain
[reasoned]. Conditioning of order 1e8–1e10 [reasoned from the weights] explains
steps too small to see.

### C. Root causes: presentation

**12. The plain previews ink only creases and boundaries, so outlines break
where the outline runs along a join** [code, ran].

`WholeCraneDrawing` clips "real crease/boundary edges" and states "triangle
joins are not ink" (`WholeCraneDrawing.hs:10-11`). On a bent panel the visible
outline often runs along a J edge. In `docs/img/crane-pillow-preview.svg`,
cropped at 3000 px, a stretch of the lower wing's paper edge has fill and no
contour line (`scripts/H1-diagnosis/pale-strip-x3.png`). That is #104's missing
silhouette. It agrees with G findings 20–21 (provenance lines need a
silhouette pass).

The book drawing (#404) derives contours from visible-region boundaries
(`CraneBookDrawing.hs:97-116`), which closes the outline. The docs previews
and the default gallery drawings do not.

**13. One line weight in the previews** [ran].

`grep -o 'stroke-width="[^"]*"'` gives:

| Drawing | Stroke widths |
| --- | --- |
| `whole-crane-preview.svg` | 22 × 0.8 |
| `crane-pillow-preview.svg` | 24 × 0.8 |
| generated `spread-0-upright.svg` | 14 × 0.8 |
| production `crane-folded.svg` | 18 × 1.0, 4 × 1.6 |
| production `bird-open.svg` | 10 × 1.0, 6 × 1.6 |

In the previews outline and crease ink are indistinguishable. The book drawing
fixes this: contours 1.15, creases 0.65 (`CraneBookDrawing.hs:129-130`).

**14. Tone: one flat colour, or three quantised tones with no modelling inside
a panel** [code, ran].

- **The plain previews** fill everything in one colour (`#eee6cf`), so the body
  cannot be read as a volume.
- **The book drawing** gives each original panel one of three tones by its
  area-averaged normal, with thresholds at 0.35 and 0.75
  (`CraneBookDrawing.hs:57-60`, `:84`). Its note says this deliberately drops
  shading inside a curved panel (`crane-book-drawing.md:19-25`).
- **The result.** The body top reads as alternating light and dark radial
  sectors, an umbrella, and the lower body as a jumble of mid and dark slivers
  (`scripts/H1-diagnosis/spread-0-upright-book-full.png`, `up-left-zoom.png`).
- **Thin highlights.** The near-white strips at the wing roots are the lightest
  tone `#f7f2e7` on thin, steeply lit strips, not holes (pixel sample
  `srgb(247,242,231)`).

**15. The book drawing is dense and doubled** [ran].

`scripts/H1-diagnosis/contour_stats.py`, `doubled_contours.py` and `ink.py` measure
the saved `book-checks.json` and the SVGs:

| View (More tucked, book) | Contour segments | Under 2 px | Crease fragments | Contour ink within 1 px of a parallel contour |
| --- | ---: | ---: | ---: | ---: |
| Upright | 447 | 114 | 167 | 22.2% |
| Opposite | 471 | 125 | 166 | 21.9% |
| Low | 340 | 109 | 122 | 27.7% |
| Top | 411 | 109 | 192 | 27.4% |

**Ink density.** Ink length divided by the drawing's bounding-box diagonal is
**23.6** for the upright book drawing. It is **4.8** for the production flat
`crane-folded.svg` and **5.5** for `bird-open.svg`.

**Strokes that seem to stop in mid-paper.** No contour segment has a free end:
every endpoint is shared, checked at 1e-6. So these strokes are the doubled
outlines of hair-thin exposed strips, the visual cost of finding 8's crossings
and of layers splayed by under a pixel [reasoned attribution; see
Unverified].

**16. Seams from splitting one colour across paths** [ran, code].

The "after" figure of `docs/img/whole-crane-preview.svg` fills paper with two
`#eee6cf` paths of 163 and 145 subpaths. Where they abut, the rendering shows
light hairlines (`scripts/H1-diagnosis/whole-seam-zoom.png`, 12× zoom). This breaks the
Fill contract ("abutting fills of one colour are one `Fill`", AGENTS.md
Gotchas).

The older `material-*.svg` previews fill each of 381 triangles separately and
show a faint triangulation hatch (`sharp-zoom.png`).

**17. Missing cues a reader uses to see paper** [ran, reasoned].

No drawing shows any of these:

- **thickness**: no spine at a fold (#114), no edge thickness;
- **occlusion darkening** inside the body pocket;
- **a ground shadow**.

**Tone gradients** (varying brightness) inside curved panels are missing too:
the plain previews use one flat tone, and the book drawing a single tone per
panel. Layers that coincide in the closed crane separate by a few pixels at the
neck and tail. They are drawn as 3–5 parallel outlines, which read as feathers
rather than as one folded point (`whole-after-crop.png`,
`pillow-narrow-crop.png`).

**18. The 3D preview's facets are hidden, not removed** [note].

Averaging normals per panel changes 1,125 of 1,344 triangle corners in More
tucked. Eight corners keep flat normals because their average points behind
the triangle, a sign of reversed patches. Downloads keep flat lighting
(`crane-panel-lighting.md:39-41`, `:31-36`).

**19. The production flat drawings are clean, which locates the problem**
[ran]. `crane-folded.png` and `bird-open.png` show exact planar panels, two
line weights, 16–22 strokes and two tones. The unrefined look belongs to
non-flat geometry and the study's drawing path, not to the renderer's basic
style.

### D. Visible defects, picture by picture

**20.** I rasterised with `rsvg-convert -w 1400 -b white`, with crops at 3000,
4200 and 12× zoom, and read the PNGs [ran]. All images are in
`scripts/H1-diagnosis/`.

| Picture | Visible defects | Cause (finding) |
| --- | --- | --- |
| `docs/img/whole-crane-preview.svg` (after) | Near wing a flattened kite with a notched root; neck and tail tips fanned into 4–5 parallel edges; hairline light seams inside the body; one line weight; one flat tone; short crease lines that stop in mid-panel near the tail base | 5, 7, 16, 13, 14, 17 |
| `docs/img/crane-pillow-preview.svg` | Radial "pinwheel" of creases at the body centre (a flat star, not a puffed body); T-ended crease stubs at the wing roots; **a stretch of the lower wing edge with no outline**; fanned neck and tail | 6, 7, 12, 17 |
| generated `spread-0-upright-book-full.svg` | Umbrella tone sectors on the body; heavy strokes that seem to end in mid-paper (doubled strip outlines); ticks under 2 px at junctions; angular kinks where wings meet the body; lightest-tone slivers at the roots; dense ink | 14, 15, 7 |
| generated `spread-0-low-book-full.svg` | Big dark near wing crossed by heavy interior strokes; small bright wedges between flaps | 8, 15 |
| generated `spread-0-top-book-full.svg` | Neck and tail as bundles of splayed layer outlines; many ticks and stubs; the body a flat four-pointed star | 7, 15, 6 |
| `docs/img/puffed-square.svg` | Dome visible only through its mesh lines; uniform white; no silhouette (#104) | 12, 14 |
| `docs/img/material-*.svg` | Faint triangulation hatch across fills; rounded double fold reads well but is known to stretch | 16; G finding 7 |
| `docs/img/crane-folded.svg`, `bird-open.svg` (production, flat) | None of the above: clean two-weight lines and planar panels | 19 |

### E. Solver architecture, against standard thin-shell simulation

**21. The energy terms the study has** [code].

| Term | Form | Where |
| --- | --- | --- |
| Length | lengthWeight · Σ(|pⱼ−pᵢ| − L)², absolute error, staged 1e2 → 1e8 | `FoldRelaxation.hs:674`, `:543` |
| Bending | Σ k(θ−θ₀)²; crease k = κl, panel k = Bl/h (Discrete-Shells form, G finding 11) | `FoldBending.hs:18-23`, `:218`, `:261-270` |
| Contact | 100 · lengthWeight · Σ min(0, gap)², along a fixed axis; or, on strips only, a directional barrier | `FoldRelaxation.hs:638`, `:668`, `:675`; `SurfaceContact.hs:28-38` |
| Holds | Vertices removed from the unknowns (exact) | `FoldRelaxation.hs:47-53` (header), `:631-634` |

The solver has these parts:

- Gauss–Newton normal equations with damping 1e-3 (`:636`);
- preconditioned conjugate gradients (at most 3000 iterations, tolerance 1e-6,
  `:663`), with a sparse LDLᵀ preconditioner described as "a small-study
  implementation" (`SparseSolve.hs:16-17`);
- a halving line search (`:697`);
- convergence when the full proposal moves under 1e-7 (`:702`).

**22. What a standard thin-shell or origami simulator has that the study does
not.**

| Ingredient | Standard practice (source) | Study |
| --- | --- | --- |
| Constitutive membrane (a finite stiffness with a physical modulus), or elements that avoid locking | Nonconforming or edge-midpoint elements to escape locking [paper: English & Bridson 2008]; adaptive remeshing aligned with folds [fetched: ARCSim page] | Edge penalty used as a near-hard constraint on 4–12 linear triangles per panel (findings 7, 10) |
| Newton with a consistent or positive-definite-projected Hessian | IPC uses projected Newton with per-element positive-definite (PSD) projection [paper: IPC §4, Alg. 1]; MERLIN uses a consistent tangent stiffness [fetched: PMC5666233] | Gauss–Newton JᵀJ, which drops the residuals' second derivatives (large when creases are far from rest, mean 38.6° here) [reasoned; ran on `checks.json`] |
| Continuous collision detection that **bounds** the step | IPC computes a largest feasible step by CCD, then backtracks [paper: IPC §4.4] | Yes/no certificate on a proposed step, on strips only (`CorrectionSweep.hs:1-21`); no crane-scale step bound |
| Contact that begins from a valid state | IPC trajectories start "in an intersection-free state" [paper: IPC §3] | Starts from guesses that already cross (findings 2, 9) |
| Thickness or distance offsets | C-IPC offsets (G finding 13) | None; clearance 1e-6 is numerical (`SurfaceContact.hs:19-22`) |
| Path following | MERLIN's modified generalised displacement control, "a variant of arc-length methods", loads incrementally [fetched] | Static solves from prescribed guesses; one bounded continuation (#394) |
| Time stepping as incremental energy minimisation | IPC [fetched: ipc-sim.github.io] | None (static) |
| Calibrated material | MERLIN's bar and spring stiffnesses from modulus and thickness [fetched] | Illustrative constants (`crease-and-panel-energy.md:30-31`) |

In short, the study already *is* a discrete energy model, a small finite-element
cousin of MERLIN and Discrete Shells. "Adding FEA" does not name the gap; the
specific missing pieces above do.

**23. Mesh sizes and measured costs** [note unless tagged].

| Run | Triangles | Cost | Outcome | Source |
| --- | ---: | --- | --- | --- |
| Wing spread, body held | 392 / 1,192 | 5.76 / 64.30 CPU s | accepted | `spreading-connected-wing.md:35-39` |
| Four body panels released | 1,176 (609 vertices) | about 9 CPU min each | unconverged | `body-angle-preferences.md:30`, `:77` |
| Body patch, four controls | 30 / 120 | about 52 CPU s total | coarse unsettled; refined fails | `coupled-body-patch.md:64-65` |
| Constraint-first initialisation | 120 | 487.93 CPU s | fails | `body-feasible-initialization.md:80` |
| Held panel | 512 | 184.70 + 10.15 CPU s | accepted | `held-panel-refinement.md:54` |
| Band 8×2 | 512 | 2,491.6 CPU s | accepted, targets missed | #195 item 23 [issue] |
| Whole crane | 448 | 40-correction cap | diverged (745%) | `whole-crane-candidate.md:50-53` |
| Whole-crane gallery, no solve (9 shapes, about 200 SVGs) | 448 | 121.85 s user, 3:57.84 wall | — | [ran] |
| Profile (#208) | — | 68% contact rows, 31% factorisation | — | `PRDs/07-prd-material-consumption.md:217-226` |

A crane whose curves read smoothly at 600 px per unit would need joins well
under the 34 px median of finding 7, and so thousands of triangles. The
measured costs put that out of reach of this solver [reasoned].

**24. What the study does well, which a redesign should keep** [note, code].

- Material identity survives refinement.
- Independent checks re-measure every claim: NumPy and GEOS reproduce
  `checks.json`, and so did my scripts.
- Rigid routes are checked exactly.
- Failures are kept as evidence.
- Every result carries an honest label ("not valid paper geometry").

These are why this diagnosis could be made from files alone.

### F. What the owner has asked for and decided

**25. Dated requests and decisions** [note, issue].

| Date | Decision or request | Record |
| --- | --- | --- |
| 09-11 | The schematic puff is a drawing, not a folding state; material-constrained opening is future work (#106) | `the-puff-is-a-drawing.md:3-7` |
| 09-20 | Prioritise a plausible spread wing and opened body; defer work whose only benefit is closer agreement between costs (#315, #316) | `illustration-material-priority.md:3-9` |
| 09-24 | Pause pair-by-pair repairs; compare barrier and penalty from a separated start (#377, #378) | `body-barrier-comparison.md:3-12` |
| 09-24 | Chose #381 constraint-first; approved a new pose and grips for #383 | `body-barrier-comparison.md:93-104` |
| 09-26 | Numerical accuracy may be loosened for plausible illustrations; keep strict diagnostics and connected paper; provisional 0.1 px and 0.1% screens | `illustration-material-priority.md:11-17` |
| 09-26 | Accept the tiny buried body crossing as intermediate evidence; asked for **one complete static candidate** with before/after drawings (#397) | `illustration-material-priority.md:34-39`; #397 [issue] |
| 09-26 | Found the first whole-crane drawing **broken**: viewing angle and unfinished body opening | `crane-pillow-target.md:3-5`; `whole-crane-candidate.md:84-86` |
| 09-26 | Liked the slimmer pillow; wanted more cameras and wing-spread control; later found the opening too wide | #399 [issue]; `crane-pillow-target.md:36` |
| 09-27 | Wanted to inspect the GLB in the browser with spread control (#401) | #401 [issue] |
| 09-27 | **Selected "More tucked"** and asked for further visual refinement; asked how to balance faithfulness with an attractive **instruction-book** drawing (#403) | `crane-panel-lighting.md:3-7`; `crane-book-drawing.md:3-8`; #403 [issue] |
| 09-28 | "Still not 'refined'"; wants a PRD covering non-flat finishes (crane and waterbomb inflation, wing spreading), naming mesh modelling and finite-element analysis | this task |

**26. Standing constraints a PRD must respect or explicitly amend** [code,
note].

- **D18 non-goals** of the sequence PRDs list "calibrated paper; pressure or
  inflation (#106) … thickness as geometry" (`PRDs/decisions.md:1444-1447`). A
  realism PRD that needs these amends D18, which is an owner decision.
- **D17**: external solvers are "comparison oracles, never ahead of the in-repo
  path", with no CI dependence (`decisions.md:1423-1430`).
- **Owner decision 12**: default CI settles at most 392 triangles, and
  `run --settle` refuses above 1,192 until #208 measures (`decisions.md` §9,
  row 12).
- **PRD 07's boundary**: a flexible illustration never feeds later rigid steps
  (`illustration-material-priority.md:88-93`).
- **Keep the default output unchanged**: new looks are opt-in modes (#56,
  D19; G implication 5).
- **Controlled opening before pressure**: the body is not a sealed cavity
  (`opening-a-crane.md:84-87`; `illustration-material-priority.md:88-90`).

**27. Coverage of the owner's three named cases** [ran, note].

- **Wing spread**: static, body held, accepted (finding 1).
- **Crane body opening**: no accepted whole-crane state; only a 16-panel
  specimen is near-valid.
- **Waterbomb inflation**: nothing. `ls examples | grep -i water` finds only
  `waterbomb-base.fold`, and no study module mentions a balloon (`grep -l -i
  balloon study/fold-material/*.hs` is empty).

## Implications for senbazuru

Remedies belong to the sibling slices (H2 sheet mechanics, H3 contact, H4
inflation, H5 photoreal, H6 illustration, H7 tooling). This list says what the
diagnosis requires of them.

1. **Gate every candidate on paper validity before the owner sees it (S).** A
   `paperScreen` pass reports per-triangle principal strain (it already exists,
   `FoldRelaxation.hs:195-221`), the vertex angle-sum change, J-edge bends and
   crossing pairs at drawing scale. It prints them beside the drawing, and the
   drawing carries D19's fidelity label ("geometry: as prescribed"). The
   Python in `scripts/H1-diagnosis/` shows each metric is under 50 lines. It looks like:
   `strain>10%: 74.2% of sheet · false creases: 15 · crossings: 345 ·
   SHAPE SKETCH`. It worked if a sketch can no longer be reviewed as if it were
   paper.
2. **Stop reaching targets by displacement continuation (M).** Build targets
   only from moves that preserve length:
   - crease angles through `foldFrameWith`;
   - developable panel bends (cylinders or cones on ruling lines);
   - grips that a solver then reaches.

   If the owner wants a "pillow", express it as developable panels plus creases
   (H2), never as a dome (finding 6). It worked if a new target starts under 1%
   strain.
3. **Path-follow from the valid closed crane instead of solving from a guess
   (L).**
   - Move the grips (wing pull, body-opening distance) in small increments.
   - Warm-start each increment from the last accepted state.
   - Accept only steps whose CCD-bounded line search keeps the mesh
     intersection-free, as IPC does.

   This is the #394 recipe made systematic, and it matches finding 2's pattern
   of success. It depends on item 5. It worked if each increment ends
   intersection-free under 1% strain, and the sequence reaches the tucked
   silhouette or names the grip value where it cannot.
4. **Remove locking (L).** Choose one:
   - refine bending regions to thousands of triangles, with a finite membrane
     stiffness and a strain cap instead of a 1e8 penalty;
   - use nonconforming or edge-midpoint elements [paper: English & Bridson];
   - use a ruling-based developable panel model (H2).

   It worked if J-edge bends over 45° drop to 0 and joins bend no more than the
   designed curvature needs (finding 7).
5. **Contact without a world axis, with a thickness offset (M to L).** Use
   unsigned distance plus a thickness offset (the C-IPC family, G finding 13)
   where paper turns upright. Keep directional orders only where layers lie
   flat together. The 32 unchecked orders then become checked, and touching
   layers can start a barrier (H3).
6. **Throughput (L to XL).** Crane-scale meshes with contact need about
   10–100× today's rate [reasoned from finding 23]. Two routes:
   - in-repo: value-only line search (#208), spatial hashing for contact rows,
     projected Newton;
   - external: IPC (MIT), ipc-toolkit (MIT) or Codim-IPC (Apache-2.0) [ran:
     `gh api`], as a D17 oracle producing reference shapes. D17 forbids
     putting it ahead of the in-repo path.

   H7 owns the choice.
7. **Presentation fixes that pay off now, provided they never mask a defect
   (M).**
   - Take contours from visible-region boundaries in every drawing, as the book
     drawing already does (finding 12).
   - Keep one path per colour (finding 16).
   - Keep a two-weight line hierarchy (finding 13).
   - Let tone vary within a panel along its real curvature, and darken the
     pocket interior (findings 14, 17).
   - Suppress sub-pixel doubled strips only after the strict checks pass, so
     that crossings are never hidden (finding 15).

   H5 and H6 own the look.
8. **A visible-change rule for the illustration track (S).** A PRD in this
   track states the drawing-scale change it expects, for example at least 1 px
   somewhere at 600 px per unit, or it says why it is diagnostic only. That
   would have stopped the 15-PRD repair series after one or two PRDs
   (finding 3).
9. **Add the waterbomb (M).** The owner names it, and the repository has no
   balloon fixture (finding 27). The traditional waterbomb has no single
   author, so a generated crease pattern plus its flat state is licence-clean.
   It is the whole-sheet inflation case and needs no crane-specific holds.
10. **Amend the non-goals explicitly (S).** Record that the rendering PRD
    reopens D18's "pressure or inflation" and "thickness as geometry" for
    illustrations only, by owner decision (finding 26).

## Acceptance ideas

What "refined" means on the diagnosis axis, at the study's 600 px per sheet
unit and its fixed cameras. Numbers in brackets are today's values for More
tucked.

**Geometry (is it paper?)**

- **G1.** Maximum principal strain at most 1%, and share of area above 0.5%
  reported [today: 106.8%; 74.2% of area above 10%]. The owner's provisional
  0.1% is the stricter option.
- **G2.** Angle-sum change at most 1° at every vertex [99 vertices above 5°].
- **G3.** False creases: no J edge bent more than 15° beyond what the declared
  curvature needs at that triangle size [15 above 45°].
- **G4.** Zero strict crossing pairs; or, under the owner's illustration
  exception, every intersection at most 0.1 px and hidden in all review views
  [345 pairs].
- **G5.** Every ordered pair checkable: zero unchecked orders [32].

**Drawing (does it read like a book figure?)**

- **D1.** Closed outline: 100% of paper-to-background boundary inked [pillow
  preview: gaps].
- **D2.** Doubled contour ink at most 2% [22–28%].
- **D3.** Ink density within 1.5× of the production flat drawing of the same
  model at the same scale [23.6 against 4.8].
- **D4.** No ink segment under 2 px except at a real corner [114 of 447].
- **D5.** No seams: same-colour fills in one path, checked by rasterising at 4×
  and finding no interior pixel lighter than the fill [fails].
- **D6.** Silhouette kinks: no outline vertex turning more than 30° unless it
  lies on a source crease or boundary corner. This is a proposed metric, not
  yet measured.
- **D7.** The owner's review at actual size on the fixed camera set; the
  metrics support that verdict and never replace it.

**Process**

- **P1.** Each illustration PRD reports G1–G5 and D1–D5 before and after, in
  the same table.

## Sources fetched

All on 2026-09-28.

- Liu & Paulino, "Nonlinear mechanics of non-rigid origami: an efficient
  computational approach", Proc. R. Soc. A 2017 (MERLIN):
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC5666233/>. Method (MGDCM, an
  arc-length variant), energy terms, consistent tangent stiffness, runtimes of
  4–11 s. Code licence not stated (G finding 9).
- IPC project page: <https://ipc-sim.github.io/>. Intersection- and
  inversion-free trajectories; time steps solved by energy minimisation. Code:
  `ipc-sim/IPC` **MIT**, `ipc-sim/ipc-toolkit` **MIT** [ran: `gh api …/license`].
- Li, Ferguson, Schneider, Langlois, Zorin, Panozzo, Jiang, Kaufman,
  "Incremental Potential Contact", SIGGRAPH 2020:
  <https://ipc-sim.github.io/file/IPC-paper-350ppi.pdf> (PDF, text extracted).
  An intersection-free start (§3), a CCD step bound then backtracking (§4.4),
  barrier-aware projected Newton (Alg. 1).
- "Convergent Incremental Potential Contact", arXiv 2307.15908 (abstract only):
  <https://arxiv.org/abs/2307.15908>.
- Codim-IPC: `ipc-sim/Codim-IPC` **Apache-2.0** [ran: `gh api`]; the GPL
  CHOLMOD caveat is in D17.
- Origami Simulator: `amandaghassaei/OrigamiSimulator` **MIT** [ran: `gh api`].
- Narain, Pfaff, O'Brien, "Folding and Crumpling Adaptive Sheets", SIGGRAPH
  2013 (ARCSim): <https://objf.ai/papers/Narain-FCA-2013-07/> (redirected from
  graphics.eecs.berkeley.edu). Adaptive remeshing aligned with folds; a plastic
  embedding for persistent creases. Licence not stated on the page.
- English & Bridson, "Animating Developable Surfaces using Nonconforming
  Elements", SIGGRAPH 2008:
  <https://www.cs.ubc.ca/~rbridson/docs/english-siggraph08-cloth.pdf> (PDF,
  §1 read). Locking of conforming triangle meshes under inextensibility.
- Wikipedia, "Developable surface":
  <https://en.wikipedia.org/wiki/Developable_surface>.
- Baumann, Czibula, Hirn, Feist, "The tensile behaviour of paper under high
  loading rates", 2024: <https://pmc.ncbi.nlm.nih.gov/articles/PMC11775012/>.
  Fracture strain about 6% for quasi-static tests on kraft handsheets.
- "Properties of Paper", paperonweb: <https://www.paperonweb.com/paperpro.htm>.
  A stretch table of 1.1–4.7% by grade and direction.

## Open questions

- Can the owner's **More tucked** silhouette be reached by paper at all? The
  body is 124 px across the wings at a 27 px rise, with raised arches. No test
  here answers that. Finding 6 says a dome-shaped route cannot.
- Which strain screen should illustrations use: 1%, from the paper sources, or
  the owner's provisional 0.1%? The difference decides whether a finite
  membrane stiffness (implication 4) is acceptable.
- Will the owner accept a D17 oracle's shape as the *source* of a published
  illustration, or only as a reference to compare against?
- Should a book-style drawing show every source crease? Real crane diagrams
  show few, and the current drawings are 5× denser in ink than the production
  flat crane.
- Is a photographed physical crane, at several opening amounts, available to
  set targets? `opening-a-crane.md:68-72` proposes this protocol; no data exists.

## Unverified

- **Paper failure strain.** The figures (about 6%; 1.1–4.7%) are for kraft
  handsheets and the listed grades, not for origami paper. They set an order of
  magnitude only.
- **Locking, applied to this study.** Finding 10 is reasoned from English &
  Bridson and from the study's weights. No experiment here reran a crane solve
  with a softer membrane or finer mesh to show the false creases disappear.
- **The Liu et al. O(√n) result** is cited through English & Bridson, not read.
- **Curve-sampling estimates** (0.25 px wing bulge, about 27° per edge on the
  cushion) are derived from the construction's parameters, not measured on the
  mesh.
- **Doubled contours.** Attributing them to crossings and sub-pixel layer
  splay is reasoned. I measured parallel contour pairs within 1 px, not the
  cause of each one.
- **Gauss–Newton against Newton.** That the dropped second-derivative terms
  slow crane solves is reasoned, not measured.
- **Conditioning of order 1e8–1e10** is inferred from the weights, not
  computed.
- **The #208 profile** (68% and 31%) and every note-reported runtime were not
  re-run. Only the gallery generation time is mine.
- **Owner decisions** are from the notes and issues; I did not see the owner's
  own messages.
- **The ink-density metric** sums stroked path lengths. On SVGs that put many
  strokes in one path, or set stroke on a group, it misreads, which is why the
  plain previews' values are not reported.
- **Physical plausibility of a "pillow" body.** No reference crane was
  measured, and whether the tucked proportions are reachable is unknown.
