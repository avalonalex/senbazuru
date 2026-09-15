# Gap: how an existing but unbent crease is written in every frame

Slice `assignment-at-rest-convention` from `Z-critic.md` §3.2 (contradiction 3).
Extends D's C3 and A1's "creaseAllAlong is not a precrease"; it does not
repeat them.

## Summary

An interpreter must write every crease in every frame, including ones not
bent: a precrease, a crease a later step folds, a reopened crease. The
repository writes these five ways.

FOLD says a valley's angle is positive, a mountain's negative, and flat,
unassigned and border edges zero; the sign "should match". So M/V at 0, and U
or F at a nonzero angle, depart from it. `Senbazuru.Fold.Types` agrees.

Variants of `quarter-fold-steps.fold`, run through a prebuilt binary whose
strokes match both goldens:
- **F or U at 0:** step 1's dashed creases turn faint, and so does step 2's solid line.
- **M/V at 0 on a precrease that ends flat:** `check` reports a false Maekawa violation.
- **U at 0:** Maekawa is skipped silently.

`Flap` turns only M, V or U. The material study treats F at 0 as uncreased
paper.

**Recommendation.** Write the *state*: M below 0, V above, F at 0, explicit
angles, never U. Keep the *intent* in the sequence definition and the
interpreter's working pattern. The price: two quarter-fold goldens change if the
fixture migrates, and #60's done-when needs amending.

## Findings

### A. What the authorities say

1. **The FOLD spec**, fetched from
   https://raw.githubusercontent.com/edemaine/FOLD/main/doc/spec.md (FOLD 1.2;
   the repository is MIT, per https://raw.githubusercontent.com/edemaine/FOLD/main/LICENSE):
   - `edges_assignment` lists B, M, V, F, U, C and J (spec lines 252-260).
   - F is a crease that is present but not folded (lines 278-280).
   - U is a crease that could be a mountain, a valley or sometimes flat, with
     no knowledge of which (lines 276-277).
   - J is an edge present only for modelling; its two faces count as one
     (lines 281-290).
   - `edges_foldAngle` lies in [−180, 180]. It is positive for valleys,
     negative for mountains, and zero for flat, unassigned and border edges,
     and its sign "should match" the assignment (lines 308-313).
   - The spec calls itself a rough draft (lines 3-5) and uses "should", not
     "must".
   - It says nothing about whether an edge's assignment may change from frame
     to frame. The `diagrams` file class is described only as frames that
     represent folding steps (lines 106-107).

   So **M/V at 0 contradicts the stated sign rule**, and so do **U or F at a
   nonzero angle**. PR #72's word "invalid" is stronger than the text, which
   is a recommendation in a draft.
2. **The library documents the same rule.** The `Assignment` haddock gives M an
   angle in [−180, 0), V one in (0, 180] and F an angle of 0
   (`src/Senbazuru/Fold/Types.hs:298-313`).
3. **PR #72 and `Creasing`.**
   - PR #72 (merged 2026-09-07, `gh pr view 72`) says a `V` at nought "is not a
     valley".
   - Its rationale is consistency between two paths. The same command must not
     mean one thing when the file records angles and another when it does not.
   - `creaseAllAlong` writes ±180 for a new M/V and 0 for anything else
     (`src/Senbazuru/Fold/Creasing.hs:280-292`, `flatAngleFor` at `306-320`).
   - `test/Senbazuru/Fold/CreasingSpec.hs:109-113` pins those values.
4. **The precreases note** writes a guide line that stays flat as `F` at 0°. It
   says F records only that the guide is flat in this state, and not the
   stiffness or memory a precrease leaves
   (`docs/notes/precreases-and-target-states.md:20-26`, `48-50`).

### B. Five conventions actually written in the repository

5. **`examples/quarter-fold-steps.fold` writes M/V at 0.**
   - With jq: the key frame has `M,V,M,M` on edges 8-11, all at angle 0.
   - Step 2 has angles `[-180, 0, -180, 0]`: V on edge 9 and M on edge 11 are
     still at 0.
   - Step 3 has `[-180, 180, -180, -180]`.
   - Classes are `creasePattern`, then `foldedForm` twice.
   - The file came from #26 (2026-09-05), two days before #72.
   - `test/fixtures/quarter-fold-steps.fold` is byte-identical (`cmp`).
   - In this fixture the assignment is also each crease's final direction, so
     candidates (1) and (4) below write it identically.
6. **`examples/bird-base-sequence.fold` writes the target state.**
   - With jq: frames 1-8 carry M/V at angle 0 (10 edges in frame 1, then 5).
   - Frame 16 writes edges 11, 15, 19 and 23 as `F` at 0. Frames 1-15 write
     those same edges as `M` at negative angles (−180 … −5).
   - The source `examples/bird-base.fold` has F on exactly those four edges.
   - The rewrite comes from `StudyCase.buildCaseFrame`, which turns an `F` with
     |angle| > 1e-10 into M or V by sign and leaves M/V at 0 alone
     (`study/fold-material/StudyCase.hs:207-210`). `CheckedBird.hs:154`
     calls it.
   - So the bird file's rule is: the assignment of the finished base, with a
     bent F written by the sign of its angle.
7. **The checked recipes start from M/V at 0.**
   - Each takes an M/V fixture and zeroes every angle:
     `test/Senbazuru/Origami/FlapSpec.hs:37-39`,
     `study/fold-material/BlintzSequence.hs:42`,
     `study/fold-material/HelmetSequence.hs:39`,
     `study/fold-material/CheckedPetal.hs:51`.
   - The blintz step "Reopen the first corner" (`BlintzSequence.hs:55`) brings
     edge 8 back to 0.
   - `surfaceAt` changes only the angles and keeps the pattern's assignments
     (`src/Senbazuru/Origami/Flap.hs:343-344`), and `materialFrame` copies the
     topology (`src/Senbazuru/Origami/Surface.hs:248-252`). So the reopened
     corner is written **M at 0**. Code reading; not run.
8. **`CraneWing` writes U, first at 0 and then at nonzero angles.**
   - The wing crease is created as `Unassigned` (`CraneWing.hs:101`, `60`).
   - The hinge is then found as "every U edge" (`CraneWing.hs:65`). Here U is
     doing a second job: recovering ids, because `creaseAllAlong` does not
     return the new edge ids.
   - After the turn, `craneFile` writes `materialFrame` of poses at 30°, 60°
     and 90° (`CraneWing.hs:104-120`), keeping U (`Flap.hs:343-344`). The output
     therefore holds **U at nonzero angles**, contrary to the spec's "zero for
     unassigned". Code reading; not run.
9. **The precreases note writes F at 0** (finding 4).

### C. What each consumer reads

10. **Folding reads the angle and ignores the assignment whenever angles are
    present.**
    - `foldAnglesOf` uses `edges_foldAngle` when it has the right length. Only
      when it is absent does it derive M → −180, V → +180 and everything else
      → 0 (`src/Senbazuru/Origami/Folding.hs:507-532`).
    - `creaseIndex` sees only angles (`547-561`).
    - `foldFrameWith` copies `edgesAssignment` unchanged and writes the angles
      it used (`379-391`).
    - Trap: **M/V at 0 survives only while the angle array survives**. Drop the
      array anywhere and every such crease folds flat.
    - F and U fold to 0 on both paths.
11. **Flap accepts only M, V or U as a hinge** (`Flap.hs:187`).
    - That is the only place it reads an assignment (grep).
    - The sign of travel comes from the stationary face's winding
      (`Flap.hs:208-216`), not from the assignment. So by code reading a V can
      be driven to a negative angle without refusal.
    - It requires explicit angles (`Flap.hs:172-173`).
12. **Stacking** takes the direction from a nonzero angle first and only then
    from the assignment (`src/Senbazuru/Origami/Stacking.hs:705-727`). The
    direction is used only for a taco hinge (`creaseRule`, `636-639`). A crease
    at angle 0 in a consistent frame is a tortilla, so its assignment orders
    nothing.
13. **Drawing depends on the assignment.**
    - `strokeFor` (`src/Senbazuru/Diagram/Style.hs:267-289`):
      - Crease-pattern notation: V dashed, M dash-dot-dot.
      - Folded-form notation: M and V solid ink.
      - F and U: faint `themeGhost` lines in both notations.
      - J: not drawn.
    - The line-vocabulary table in `Style.hs:12-23` reserves the "thin light
      line" for an existing flat crease. Dashes mean a fold still to be made
      (`35-39`).
    - Painting order puts F/U lines under M/V (`creaseOrder`,
      `src/Senbazuru/Render/CreasePattern.hs:565-573`).
    - The notation comes from `frame_classes` for flat frames (`546-549`,
      `src/Senbazuru/Fold/Query.hs:459-463`).
    - Where lines coincide in a visible-region drawing, M/V (weight 2) beat F/U
      (weight 1), which beat J (weight 0)
      (`src/Senbazuru/Origami/Visible.hs:531-541`).
    - Newcomer trap, from `Style.hs:54-62`: mountain and valley flip when a
      layer faces away from the viewer, so marking the *next* fold on a folded
      form must handle that. F has no side, so it cannot be drawn backwards.
14. **`check` works only on crease patterns.**
    - M, V and U divide the paper at a vertex. F and J are dissolved. B and C
      mark the paper's edge, so that vertex is skipped
      (`src/Senbazuru/Origami/FlatFold.hs:66-86`, `436-448`).
    - Maekawa is skipped whenever any U meets the vertex (`503-506`).
      `renderReport` has no line saying so (`559-585`).
    - `check` refuses any `foldedForm` frame (`365-370`), and `foldFrameWith`
      tags every output `foldedForm` (`Folding.hs:386`). So **only the first
      frame of a sequence is ever checkable**.
15. **The material study splits on the assignment.**
    - `surfaceFeatures` treats B, M, V, U and C as feature edges always, and F
      only when its angle is nonzero (`Surface.hs:272-278`).
    - `hingesForSurface` builds a crease hinge for every feature except B and C:
      - It refuses a feature crease with no rest-angle control
        (`MissingRestAngle`, `study/fold-material/FoldBending.hs:180`).
      - It refuses a control on a non-feature edge (`UnexpectedRestAngle`,
        `166`).
      - It constrains the control's sign only for M and V (`181`).
    - Non-feature edges stay zero-bend panel springs
      (`docs/notes/crease-identity-through-refinement.md:23-29`).
    - So **F at 0 is uncreased paper and cannot be given a crease control**;
      M, V or U at 0 is a hinge that needs one.
    - This bites goal (3): the glossary's rest angle for a creased sheet is not
      zero (`docs/glossary.md:19`).
16. **Arrows ignore assignments.** `motionsBetween` compares positions, and
    lists as its creases only those whose recorded angle changed
    (`src/Senbazuru/Origami/Step.hs:88-165`, `150-158`). Every candidate leaves
    arrows and `StepSpec`'s "sees the left half swing onto the right" (line 64)
    alone.

### D. Measurements

17. **The binary, and how far it can be trusted.**
    - `stack run` would compile, so I ran the prebuilt
      `.stack-work/install/aarch64-osx/6ae009cc…/9.6.7/bin/senbazuru`, built
      2026-09-07 13:24 when HEAD was at `857fd4c` (#88).
    - Since then `FlatFold.hs` has changed only by the `Explain` refactor
      (`git diff 857fd4c HEAD`); the counting logic in the diff is unchanged.
    - Run with `--margin 10` (matching `testPage`,
      `test/Senbazuru/Render/SvgSpec.hs:140-147`) on the unmodified fixture, it
      reproduces **every stroke** of `test/golden/quarter-fold-steps.svg` and
      `quarter-fold-step-1.svg`.
    - The only differences are the cyclic start points of two fill paths. That
      is exactly what 59ec327 (#186, "Canonicalize closed SVG fill paths")
      changed after the build.
    - The ignored `test/golden/*.actual.svg` files date from Sep 6
      (`.gitignore:10`) and are not evidence.
18. **Variants of `quarter-fold-steps.fold`** (copies in scratch; M/V at 0
    rewritten with jq):

    | Variant | `check` frame 0 | Step-1 strokes vs golden | Step-2 horizontal crease | Step 3, arrows |
    | --- | --- | --- | --- | --- |
    | A: as the file (M/V at 0) | 1 interior vertex checked, no violations | identical | ink `#1a1a1a`, width 1 | identical |
    | B: F at 0 | 0 checked; 1 skipped "with no creases" | 4 dashed ink paths → `#bdbdbd` width 0.6, solid | → `#bdbdbd` 0.6, painted before the border | unchanged |
    | C: U at 0 | 1 checked, no violations (Maekawa silently not tested) | byte-identical to B | as B | unchanged |
    | D: J for not-yet-made creases (frame 0 all J; frame 1 edges 9, 11 J) | 0 checked; 1 "with no creases" | the 4 crease paths disappear | disappears | unchanged |

    `check --frame 1` refuses every variant as `foldedForm`.
19. **A precrease that ends flat, as `check` sees it.**
    - The source files: `examples/square-base.fold` and
      `examples/waterbomb-base.fold` each have two `F` guide segments at the
      centre.
    - Writing those guides as M gives:
      "vertex 8: 4 mountains and 4 valleys, which must differ by 2 (Maekawa)",
      exit 1.
    - Writing them as V gives "2 mountains and 6 valleys", exit 1.
    - Writing them as U gives "no violations found", exit 0.
    - The originals pass.
    - So writing a precrease that ends flat as its precrease direction at 0
      makes `check` reject a correct flat sheet.
20. **#60 treats this golden as the test.**
    - #60's done-when asks a scheme to reproduce `quarter-fold-steps.fold`
      (`gh issue view 60`; `docs/roadmap.md:82-86`).
    - The owner's comment there says the exact-coordinates bullet cannot hold,
      and that the second bullet (the `render --steps` page) is the achievable
      one, "so the golden really is the test".

## Candidate table

Measured rows cite finding 18 or 19. "From the frame" means: can a program turn
the crease after reading only the written frame back?

| Candidate | FOLD sign rule | `Flap` can turn it later | Step-1 SVG | quarter-fold-steps golden | `check` (Maekawa) | `foldFrameWith` round trip | `materialFrame` / material study |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **1. M/V at 0** (the direction it was made or last bent in) | Departs: 0 is neither positive nor negative; contradicts `Types.hs:301-304` | Yes, from the frame (`Flap.hs:187`) | Dashed/chain *instruction* on every crease, including step-3 creases on step 1; solid ink across flat paper on step 2 | None; the fixture is this | Passes the fixture; **false violation** when a precrease ends flat or reverses (finding 19) | Only with explicit angles; absent angles fold it to ±180 (`Folding.hs:511-512`) | Copied verbatim; a hinge needing a control, sign-checked (`FoldBending.hs:180-181`) |
| **2. F at 0, reassigned by sign when bent** (the frame's state) | Consistent in every frame, *if* the rewrite runs at every write; F left at a nonzero angle is the failure mode (`StudyCase.hs:207-210` rewrites only in `buildCaseFrame`) | **No**, from the frame (`FlapNotHinge`); needs a working pattern with M/V | Faint `#bdbdbd` 0.6 lines, no instruction (measured) | Changes: 4 paths in `quarter-fold-step-1.svg`, 5 in `quarter-fold-steps.svg` (measured) | Dissolved; a sheet with no bent creases checks nothing; flat guides pass (finding 19) | Folds as 0 whether angles are present or absent; the most robust | Copied verbatim; **uncreased paper**, a control is refused (`FoldBending.hs:166`) |
| **3. U at 0** | Consistent at 0; U then written at a nonzero angle after a turn (CraneWing) is not; and U claims ignorance the interpreter does not have (spec 276-277) | Yes, from the frame | Byte-identical to 2 (measured) | Same changes as 2 | **Maekawa silently skipped** at every vertex touching a U (`FlatFold.hs:503-506`, `559-585`) | Folds as 0 either way | Copied verbatim; a hinge needing a control, sign unconstrained (`FoldBending.hs:181`) |
| **4. Eventual (target-state) direction + explicit angles + sign rewrite while bent** (the bird file's rule) | Departs for M/V at rest; F-in-target is consistent | Yes for creases bent at the end; **no** for creases flat at the end (F) | Same as 1 for target-M/V creases; faint for target-flat guides | None for quarter-fold-steps (its target has no F); none for `bird-base-sequence.fold` (already this) | Frame 1 is checked against the finished pattern: meaningful, no false violation | As 1 (explicit angles mandatory) | As 1 for M/V, as 2 for target-F. **Needs the whole sequence evaluated before frame 1 is written** |
| 5. *(supplementary)* J at 0 for a crease **not yet made** | The spec allows J for modelling and recommends the `joins` attribute (lines 281-290) | No | Nothing drawn (measured) | Step-1 crease paths and the step-2 line removed (measured) | Dissolved (`FlatFold.hs:444-448`); 0 checked | J folds as 0 when absent (`Folding.hs:529-532`); tracing unchecked | Not a feature; the spec says treat its faces as one face, which senbazuru's face-based code does not do (unverified) |

On round trips: a `materialFrame` export carries `foldedForm`
(`Folding.hs:386`), so `foldFrameWith` refuses it (`Folding.hs:338-339`). A
pipeline resuming from a written frame must rebuild the flat pattern from
`senbazuru:material_coords` (`Surface.hs:179-190`). Every candidate's
assignments survive that verbatim. What differs is whether `Flap` can then
continue: candidates 1, 3 and 4 can, candidates 2 and 5 cannot.

## Recommendation

**Adopt candidate 2 as the written convention, and keep the intent out of the
file.** Exactly:

- Every written frame has `edges_foldAngle`, one entry per edge. Refuse to write
  a frame without it: finding 10 shows an absent array changes meaning.
- For every edge that is not B, C or J, the written assignment is:
  - `M` when the angle is below zero;
  - `V` when it is above zero;
  - `F` when it is zero.

  One threshold, defined once. Today `1e-10` appears separately at
  `StudyCase.hs:208` and `Surface.hs:278`.
- The interpreter never writes `U` and never writes M or V at 0.
- The intent is held in the sequence definition (DSL value or parsed file) and
  in the interpreter's in-memory working pattern, not in the output:
  - which way a crease will fold;
  - that it was precreased;
  - which segments form one hinge.

  The working pattern gives `Flap` the M or V it requires (`Flap.hs:187`).
  Resuming a sequence therefore needs its source, not its output.

Why this and not candidate 4, which changes no golden:
- **Authority.** It is the only candidate consistent with all three written
  authorities: the FOLD sign rule, the `Assignment` haddock, and #72 with
  `flatAngleFor`. `Creasing` already writes new creases this way.
- **`check`.** It gives the right answer on precreases that end flat
  (finding 19).
- **No look-ahead.** Frame *n* depends only on steps 1…*n*. Candidate 4 must
  run the whole sequence before writing frame 1, which a CLI reporting the
  first failing step, or a REPL building a sequence incrementally, cannot do.
- **Neither avoids a working pattern.** Candidate 4 still cannot turn a crease
  that is flat in the target from its own output. Its one real advantage is
  golden stability.
- **Book notation.** It draws an existing unbent crease as the book's thin light
  line (`Style.hs:20`), rather than as an instruction to fold now.

What it costs, stated plainly:
- Step pages lose their fold-here dashes until the step renderer draws the
  instruction from the step itself (`motionCreases`, finding 16), which must
  deal with the side-of-paper problem in `Style.hs:54-62`.
- The material study must take crease identity and rest-angle controls from the
  definition, because `FoldBending` refuses a control on an F-at-0 edge.

### Tests and goldens it would change

**(a) Adopted for interpreter output only; existing fixtures kept as they are.**
No existing test or golden changes. #60's done-when, whose operative check is
the steps golden (finding 20), then cannot be met by assignment equality. Amend
it to: coordinates and angles within a tolerance, assignments by the state rule.

**(b) Migrating `quarter-fold-steps.fold` to the rule** (only edges 8-11 of the
key frame and 9 and 11 of step 2 change, to `F`).

| Artifact | Change | Evidence |
| --- | --- | --- |
| `examples/quarter-fold-steps.fold` and `test/fixtures/quarter-fold-steps.fold` | new assignments | — |
| `test/golden/quarter-fold-step-1.svg` (`SvgSpec.hs:371-373`) | 4 crease paths become `stroke="#bdbdbd" stroke-width="0.6"` with no dash array | measured |
| `test/golden/quarter-fold-steps.svg` (`SvgSpec.hs:378-380`) | the same 4 paths; the step-2 path `M 170.312 100 L 229.688 100` becomes faint and moves ahead of the border strokes | measured |
| `docs/img/steps.svg` (`docs/img/README.md:15-16`; no test) | same change expected | not measured |
| `StepSpec` (motions), `StackingSpec.hs:232-245` (two orders), `Fold/FacesSpec` (faces) | none expected | code reading: angles only (finding 16); tortillas (finding 12); faces only |

**(c) Generalising the study's export rule** (`StudyCase.hs:207-210` also
demoting M/V at 0 to F, and every `materialFrame` export in a sequence recipe
going through it). All expected to change and **not measured**, because the
binary predates #141's projected visibility:

- `examples/bird-base-sequence.fold`, frames 1-8, through
  `BirdSequenceSpec.hs:39-40`, and the goldens
  `test/golden/bird-sequence-{bottom,iso}.svg` (`BirdSequenceSpec.hs:84`).
- `checked-bird-{above,below}.svg` (`CheckedBirdSpec.hs:173`).
- `checked-blintz.svg` (`BlintzSequenceSpec.hs:127`): the start frame and the
  reopened corner.
- `checked-helmet.svg` (`HelmetSequenceSpec.hs:187`).
- `checked-crane.svg` (`CraneWingSpec.hs:145`): U at 0/30/60/90 becomes F/V.
  `CraneWing.hs:65` must keep finding U in the working frame.
- `checked-petal.svg` (`CheckedPetalSpec.hs:138`).
- `docs/img/bird-sequence-preview.svg`, `frog-sequence.svg` and `bird-open.svg`.
- The blintz, crane and helmet galleries render through `stepPage`
  (`BlintzGallery.hs:39`, `CraneGallery.hs:38`), so their strokes read the
  assignments.

**(d) Unchanged:** `CreasingSpec.hs:109-113`, since `flatAngleFor` already
follows the rule, and `FlapSpec.hs:37-39`, since it uses an in-memory working
pattern.

## Implications for the design

1. **PRD (1) and (2), the sequence language.**
   - A crease declaration carries its kind (M or V, as seen from the sheet's
     front) separately from any angle.
   - "Precrease" means fold and unfold, leaving `F` at 0 in the written frames.
   - Do not offer `U` to authors as a way to say "not bent yet". `U` means
     unknown, and it silences `check`.
2. **One export function, not one per backend.** Define the state rule once and
   call it at every boundary where a frame leaves the interpreter: FOLD output,
   `stepPage` input and `materialFrame`. AGENTS.md's argument for
   `withPlanarFaces` ("a policy spelled out per backend is a policy the next
   backend forgets") applies unchanged. `StudyCase`'s partial rewrite is the
   existing half-copy.
3. **Refuse absent angles at write time.** M/V at 0 exists today only because
   every writer happened to keep the array (finding 10).
4. **Separate working and written patterns in the interpreter's types.**
   `Flap` needs M, V or U; the written frame has F. A newtype for each (for
   example `WorkingPattern` against `WrittenFrame`) would turn the mix-up into a
   type error, not a `FlapNotHinge` at step 7.
5. **Creases not yet made are a separate decision.** The state rule says what an
   existing crease is. It does not say how to write one that will only be made
   later but must already be in the graph because `motionsBetween` demands equal
   graphs (`Step.hs:88-96`). Measured J-at-0 behaviour is recorded above; its
   tracing, folding and glTF behaviour is not.
6. **PRD (3), the material study, reads intent, not F.** Crease hinges and rest
   angles for a precreased-but-flat line must come from the definition.
   `FoldBending` refuses a control on an F edge (finding 15), and the
   precreases note already says F does not carry stiffness.
7. **Step-page instruction lines belong to the step-annotation PRD** (critic
   §3.3). Draw dashes for the creases a step changes, with the direction of
   change, and resolve the upside-down-layer case in `Style.hs:54-62`. Name
   which goldens that feature moves.
8. **`check` on a sequence.** Only the first frame is checkable (finding 14).
   Under the state rule it checks only creases that are bent at step 1. A
   sequence verb that wants a flat-foldability verdict should check the
   finished crease pattern, meaning the final angles mapped back onto the flat
   pattern with a crease-pattern class, not frame 0.
9. **Amend #60's done-when** (finding 20) in the same PR that adopts the rule,
   or migrate the fixture per (b).

## Open questions

- Should frame 0 of an interpreter's output be the uncreased sheet (all F, or
  J for creases to come) or the target crease pattern? `check` and step 1's
  picture pull opposite ways.
- Is J a sound way to write a not-yet-made crease? The spec says to treat its
  two faces as one. `Flap`, `Stacking` and `Visible` treat them as two.
- Where should the single "is zero" threshold live? And should `check`'s
  report say when Maekawa was skipped because a U is present
  (`FlatFold.hs:503-506`, `559-585`)? That silence is a separate bug-shaped
  finding.
- Should `Flap` refuse travel whose sign contradicts the working assignment
  (finding 11), or is the working assignment advisory?
- Should `Creasing` return the new edge ids, so recipes stop using U as a
  marker (`CraneWing.hs:65`)?

## Unverified

- **HEAD source was not run.** The rendering and `check` results come from a
  binary built 2026-09-07 13:24, not from HEAD. Its strokes matched both
  quarter-fold goldens, and `FlatFold`'s diff since is a refactor of the error
  messages. Later commits to `CreasePattern` (#141, #148) could still alter
  other frames.
- **Not measured:** the bird, blintz, helmet, crane and petal golden changes in
  (c).
- **Not run:** that the blintz reopen writes M at 0 and that `CraneWing` writes
  U at 30/60/90 (findings 7-8). Both are code reading.
- **Code reading only:** that `StackingSpec`'s two orders and `StepSpec` stay
  unchanged under (b); that `Flap` does not relate travel sign to assignment.
- **Other FOLD consumers** (Origami Simulator, Oriedita, others) were not
  checked for how they read M/V at angle 0, or U at a nonzero angle.
- **J edges** through `withPlanarFaces`, `foldFrameWith`, `Flap` and
  `Render.Gltf` were not exercised.
- **The spec's intent.** Whether the FOLD authors mean "should match" to be
  binding for `diagrams` files: the spec text is all I read.
