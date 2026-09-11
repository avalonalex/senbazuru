# Roadmap, and where we stand

The README's [roadmap](../README.md#roadmap) is the map: four items, in
order, each an issue tagged `roadmap` that holds the approach and the
acceptance criteria. This is the state of play behind it — what is done, what
is open, how hard each open piece is, and an order to take them in. It is a
snapshot and will drift, so it carries a date: **as of 2026-09-11**. The
README and the issues stay the source; update this when a roadmap issue
closes.

## Where the project stands

| | |
| --- | --- |
| Stage | Alpha; obsolete internal paths can be replaced as regression cases pass |
| Material study | Connected meshes, length/contact checks, square/waterbomb collapse, fish ears, bird petals and six more base endpoints |
| Production handoff | Checked bird and frog states rendered as SVG sequences |
| Tests | 1,084 examples, including material and contact checks |
| Traditional crane fixture | 72 faces |
| Releases | none |

The first roadmap is done: fold arrows, the flat-foldability checker, filled
paper, step pages, folding, layer-correct drawing, FOLD output, the layer
solver and the 3D export
([#6](https://github.com/avalonalex/senbazuru/issues/6), [#14](https://github.com/avalonalex/senbazuru/issues/14), [#15](https://github.com/avalonalex/senbazuru/issues/15), [#16](https://github.com/avalonalex/senbazuru/issues/16), [#17](https://github.com/avalonalex/senbazuru/issues/17),
[#18](https://github.com/avalonalex/senbazuru/issues/18), [#19](https://github.com/avalonalex/senbazuru/issues/19), [#25](https://github.com/avalonalex/senbazuru/issues/25), [#27](https://github.com/avalonalex/senbazuru/issues/27)). What is open is the
second generation.

### Against the field

[related-projects.md](related-projects.md) has the tools and their licences.
Senbazuru's focus is book-style diagrams from checked folding states: hidden
lines, two paper colours and visible regions even when flaps stack in a circle.
The study now shares its material representation with the renderer interfaces;
glTF now keeps crease positions and material identities in two scenes. Authoring a folding sequence,
handling larger models and installing without Stack remain separate pieces of
work.

## The four roadmap items

1. **One connected material surface** ([#146](https://github.com/avalonalex/senbazuru/issues/146)).
   `Origami.Surface` now holds material identity, current geometry, crease
   topology and optional properties. The study uses its mesh/refinement code,
   and both renderer interfaces accept it. glTF now writes visible and complete
   scenes at the same positions, retaining material references instead of
   lifting faces apart. Physical thickness is metadata only. Replace
   obsolete internal paths rather than maintaining them for alpha compatibility.
   [The design note](notes/connected-paper-surface.md) separates this
   representation change from the bending and opening controls that follow.
2. **A vocabulary of folds** ([#60](https://github.com/avalonalex/senbazuru/issues/60)). The first move exists, `crease`
   and `crease --folded`, with the mountain/valley alternation through the
   layers right. The done-when — reproduce `examples/quarter-fold-steps.fold`
   from a written scheme — is not met. What stands in the way is a decision,
   [#97](https://github.com/avalonalex/senbazuru/issues/97), on how a scheme is written down, before the second move
   [#95](https://github.com/avalonalex/senbazuru/issues/95) and the flap rotation [#54](https://github.com/avalonalex/senbazuru/issues/54).
3. **Folding in three dimensions** ([#55](https://github.com/avalonalex/senbazuru/issues/55)).
   The studies now have verified intermediate square/waterbomb collapse,
   rabbit-ear and bird-petal states. General flap/wing authoring, a general
   angle solver and continuous collision certification remain open
   ([#54](https://github.com/avalonalex/senbazuru/issues/54),
   [#55](https://github.com/avalonalex/senbazuru/issues/55),
   [#61](https://github.com/avalonalex/senbazuru/issues/61)).
   Controlled pocket opening and body inflation are future goals in
   [#106](https://github.com/avalonalex/senbazuru/issues/106), with bending where
   rigid panels cannot reach the target. A pressure model comes after defining
   a cavity and its openings. The earlier schematic-puff note is historical
   context, not the current limit on what the project intends to compute.
4. **A schematic side view** ([#50](https://github.com/avalonalex/senbazuru/issues/50)).
   Not started. It should use shared material/layer relationships, keeping any
   display separation distinct from physical paper thickness.

## The open issues, by how hard they are

### Hard: weeks, with a research question inside

- **[#55](https://github.com/avalonalex/senbazuru/issues/55) solving fold angles**, and **[#61](https://github.com/avalonalex/senbazuru/issues/61) keeping paper out
  of paper along the way.** Nonlinear loop closure at every interior vertex, a
  Jacobian of rotation products, Newton steps in pure Haskell, and a singular
  starting point because the flat-folded state is where branches meet. Whether
  the crane is rigid-foldable end to end is not known. #61 is continuous
  collision detection between moving panels on top of that. These are general
  motion problems beyond the authored study paths.
- **[#60](https://github.com/avalonalex/senbazuru/issues/60) the vocabulary, and [#97](https://github.com/avalonalex/senbazuru/issues/97) the scheme format.** Hard as
  design rather than code: no reference implementation to lean on, a reference
  vocabulary (corner to corner, edge to crease) that matters as much as the
  moves, and named moves — squash, petal, sink — that need to know which flap
  and which layer, which the code has deliberately never asked. Get the format
  wrong and every move after it is built on it.
- **[#93](https://github.com/avalonalex/senbazuru/issues/93) the corpus sweep, with [#87](https://github.com/avalonalex/senbazuru/issues/87) behind it.** The script
  is a morning; what it finds is the unknown. Expect tolerance failures in
  cutting and tracing, non-convex faces, and models the solver cannot settle
  in a minute. A real fix for the solver's propagation may be Flat-Folder's
  cell and overlap-graph formulation rather than a faster map.
- **[#114](https://github.com/avalonalex/senbazuru/issues/114) the material around a fold.**
  The study now has connected surfaces and a corrected sharp double fold that
  meets length/contact tolerances. The production glTF path now preserves
  shared crease positions through the surface introduced by
  [#146](https://github.com/avalonalex/senbazuru/issues/146), with thickness optional. The original
  rounded double-fold experiment showed that a 3:1 radius ratio can still
  stretch the paper; radius and connectivity alone do not settle its shape.
  Later work needs bending, crease preferences and compatible contact.
- **[#106](https://github.com/avalonalex/senbazuru/issues/106) body opening.**
  Representing a pocket is only the first step. Its expansion needs a driving
  control, compatible crease motion, possible panel bending and contact checks.
  Start with controlled opening; a pressure/volume model additionally needs a
  defined cavity and treatment of its openings.

### Medium: days, with a picture or a format to design

- **[#50](https://github.com/avalonalex/senbazuru/issues/50) side view** and **[#49](https://github.com/avalonalex/senbazuru/issues/49) cut-away.** The geometry
  exists. What a schematic side view of a 32-layer crane should look like, and
  where the cut-away circle comes from, does not.
- **[#54](https://github.com/avalonalex/senbazuru/issues/54) rotating a flap.** Easy until the rotation reaches a vertex,
  then it is the degree-4 closed form of [#52](https://github.com/avalonalex/senbazuru/issues/52), and the result has paper
  in the air. Production SVG now handles the study's open panels; the general
  authoring operation and compatible-angle solve remain to be built.
- **[#36](https://github.com/avalonalex/senbazuru/issues/36) the arrow vocabulary**, **[#48](https://github.com/avalonalex/senbazuru/issues/48) x-ray lines**,
  **[#94](https://github.com/avalonalex/senbazuru/issues/94) captions.** The drawing is easy; classifying a motion in
  `Origami.Step` and scoping to the step are the work. Captions have no font
  metrics to measure against, so truncation is by character count.
- **[#99](https://github.com/avalonalex/senbazuru/issues/99) SVG import.** Path parsing, transforms, and the colour
  conventions of two web tools to read before fixing ours.
- **[#38](https://github.com/avalonalex/senbazuru/issues/38) assignment from a stacking**, **[#53](https://github.com/avalonalex/senbazuru/issues/53) reading a
  simulator's angles**, **[#56](https://github.com/avalonalex/senbazuru/issues/56) glTF animation.** Each is composition
  now that the `fold` verb writes a folded form out; #56 also waits on #55.
- **[#104](https://github.com/avalonalex/senbazuru/issues/104) the silhouette.**
  The rule for #104 is one sign test per shared edge; the care is that it
  changes what every existing folded form draws, so each golden's diff has to
  be read edge by edge. The earlier
  [schematic-puff note](notes/the-puff-is-a-drawing.md) explains why a body
  needs its silhouette even when triangulation edges are hidden.
- **[#111](https://github.com/avalonalex/senbazuru/issues/111) one answer about fold angles.** Moving `foldAnglesOf` into
  `Fold.Query` is the easy half. The judgement is which of the other three
  callers can share it, since how far a crease turns and which way it turns are
  not the same question.
- **[#62](https://github.com/avalonalex/senbazuru/issues/62) polymorphic scalar**, **[#63](https://github.com/avalonalex/senbazuru/issues/63) phantom units**,
  **[#73](https://github.com/avalonalex/senbazuru/issues/73) vendor keys**, **[#102](https://github.com/avalonalex/senbazuru/issues/102) frame inheritance.** Refactors
  of the data model, each with one design choice in it.

### Small: an afternoon of composing what exists

- **[#110](https://github.com/avalonalex/senbazuru/issues/110) a folded frame with its layer order in it.** One function
  beside `layerOrderFor`, and #38, #53 and #56 each stop needing the command
  line to build the value they want.
- **[#109](https://github.com/avalonalex/senbazuru/issues/109) a length `zip3` cannot truncate.** One comparison and an
  error that already exists.
- [#92](https://github.com/avalonalex/senbazuru/issues/92) `convert`, [#100](https://github.com/avalonalex/senbazuru/issues/100) big-little-big, [#101](https://github.com/avalonalex/senbazuru/issues/101) the
  whole-sheet verdict, [#95](https://github.com/avalonalex/senbazuru/issues/95) turn over, [#96](https://github.com/avalonalex/senbazuru/issues/96) the papers note,
  [#98](https://github.com/avalonalex/senbazuru/issues/98) the release, [#58](https://github.com/avalonalex/senbazuru/issues/58), [#11](https://github.com/avalonalex/senbazuru/issues/11), [#64](https://github.com/avalonalex/senbazuru/issues/64).

One is easier than its own text says. [#38](https://github.com/avalonalex/senbazuru/issues/38) claims an unassigned
pattern cannot be folded, so its input must already be a folded form. But at
±180° a mountain and a valley are the same rigid motion. Fold every unassigned
crease at 180 either way, the positions come out identical, then solve the
stacking and read the assignment off it. That drops the hardest precondition.

## An order

1. [#146](https://github.com/avalonalex/senbazuru/issues/146), the shared connected
   surface, following the findings of [#114](https://github.com/avalonalex/senbazuru/issues/114).
   The shared core and glTF replacement are in place, with material references
   on graphics copies and refreshed README examples. Next add bending resistance
   and crease preferences; physical thickness is not a prerequisite for that
   first mechanics model.
2. [#93](https://github.com/avalonalex/senbazuru/issues/93), the sweep, to learn what actually breaks before deciding what
   the next roadmap edit says. File the fixes it finds as small fixtures.
3. [#96](https://github.com/avalonalex/senbazuru/issues/96) then [#97](https://github.com/avalonalex/senbazuru/issues/97): read what the 2026 papers use as their
   vocabulary, then decide the scheme format. Only then [#95](https://github.com/avalonalex/senbazuru/issues/95),
   [#94](https://github.com/avalonalex/senbazuru/issues/94) and [#36](https://github.com/avalonalex/senbazuru/issues/36), which give a written scheme its arrows and
   captions.
4. [#98](https://github.com/avalonalex/senbazuru/issues/98), a release, once the sweep says the tool survives real files.
5. General fold-angle work, starting with [#52](https://github.com/avalonalex/senbazuru/issues/52) and [#53](https://github.com/avalonalex/senbazuru/issues/53), which
   produce the numbers [#55](https://github.com/avalonalex/senbazuru/issues/55) will be tested against.
6. [#110](https://github.com/avalonalex/senbazuru/issues/110) and [#109](https://github.com/avalonalex/senbazuru/issues/109), the two follow-ups the `fold`
   verb left behind. #110 first, and before #38 or #53 rather than after them,
   because it is the value both of them will otherwise rebuild by hand.
7. [#104](https://github.com/avalonalex/senbazuru/issues/104) and
   [#106](https://github.com/avalonalex/senbazuru/issues/106), readable silhouettes
   and controlled pocket opening. The existing schematic puff tests drawing;
   a new expanded body must additionally pass material/contact checks. These
   are future work, not requirements for finishing the representation change.
