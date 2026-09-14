# Roadmap, and where we stand

The README's [roadmap](../README.md#roadmap) is the map: one completed
foundation and three open goals, each an issue tagged `roadmap` that holds the
approach and the acceptance criteria. This is the state of play behind it — what is done, what
is open, how hard each open piece is, and an order to take them in. It is a
snapshot and will drift, so it carries a date: **as of 2026-09-14**, through
the contact study in [#173](https://github.com/avalonalex/senbazuru/pull/173)
and the checked flap operation in [#175](https://github.com/avalonalex/senbazuru/issues/175)
with flat endpoints in [#177](https://github.com/avalonalex/senbazuru/issues/177)
and touching stacks in [#179](https://github.com/avalonalex/senbazuru/issues/179),
including free edges on the hinge in [#181](https://github.com/avalonalex/senbazuru/issues/181),
a complete checked blintz sequence in [#183](https://github.com/avalonalex/senbazuru/issues/183),
the continuously checked first bird petal in [#185](https://github.com/avalonalex/senbazuru/issues/185),
the second petal and final press in [#187](https://github.com/avalonalex/senbazuru/issues/187),
the initial square-base collapse in [#189](https://github.com/avalonalex/senbazuru/issues/189),
the checked helmet sequence in [#191](https://github.com/avalonalex/senbazuru/issues/191),
the checked crane wing in [#193](https://github.com/avalonalex/senbazuru/issues/193),
the controlled wing-bending experiment in [#196](https://github.com/avalonalex/senbazuru/issues/196),
the two touching layers in [#198](https://github.com/avalonalex/senbazuru/issues/198),
their refined coupled solves in [#200](https://github.com/avalonalex/senbazuru/issues/200),
the connected wing in [#203](https://github.com/avalonalex/senbazuru/issues/203),
the root/body comparison in [#205](https://github.com/avalonalex/senbazuru/issues/205),
and the pocket material map in [#210](https://github.com/avalonalex/senbazuru/issues/210). The
README and the issues stay the source; update this when a roadmap issue
closes.

## Where the project stands

| | |
| --- | --- |
| Stage | Alpha; obsolete internal paths can be replaced as regression cases pass |
| Material study | Connected meshes, length/contact checks, square/waterbomb collapse, fish ears, bird petals and six more base endpoints |
| Production handoff | Shared surfaces reach SVG and two glTF scenes; complete blintz and helmet routes plus a crane-wing departure use checked flap operations, and the open-sheet-to-bird route has exact ideal-path certificates; frog stages still have sampled checks |
| Contact study | Checks one fixed-hinge rotation or straight numerical correction throughout its interval; learned contact orders and a distance barrier settle the recorded opening/closing strip controls |
| Tests | 1,392 examples pass, including the crane material map, wing-root/body controls, inherited contact orders, exact bending grips and a known strip, a checked crane wing with its tail tucked inside, complete helmet, quarter-fold, blintz and bird routes, aligned stacks, flat landing/reopening and material/contact checks |
| Traditional crane fixture | 72 faces; 76 after adding one wing crease |
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
The study shares its material representation with the renderer interfaces;
glTF keeps crease positions and material identities in two scenes. Production
rendering handles planar panels, including panels lifted into the air. General
bent-panel rendering remains a study-to-production gap. Authoring a folding
sequence, handling larger models and installing without Stack remain separate
pieces of work.

## The four roadmap items

1. **Complete: one connected material surface** ([#146](https://github.com/avalonalex/senbazuru/issues/146)).
   `Origami.Surface` now holds material identity, current geometry, crease
   topology and optional properties. The study uses its mesh/refinement code,
   and both renderer interfaces accept it. glTF now writes visible and complete
   scenes at the same positions, retaining material references instead of
   lifting faces apart. Physical thickness is metadata only. The six acceptance
   criteria are met by [#148](https://github.com/avalonalex/senbazuru/pull/148)
   and [#149](https://github.com/avalonalex/senbazuru/pull/149): shared geometry,
   material connectivity, renderer handoff, optional thickness, regression
   coverage and documentation. Tests cover all thirteen base fixtures plus the
   quarter fold, sixteen bird states and five frog milestones. The duplicate
   study mesh/refinement and glTF face-lifting implementations are removed.
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
   rabbit-ear and bird-petal states. The contact study checks entire intervals
   for fixed-hinge turns, numerical corrections, square-base collapse, both bird petals
   and final pressing.
   Connecting the
   fixed-hinge check to one authored flap rotation is now implemented in
   [#175](https://github.com/avalonalex/senbazuru/issues/175), with a single-fold
   SVG/glTF demo and an opposing-flap collision witness. Flat touching
   endpoints now carry approach/departure order. Touching layers sharing a
   rigid motion retain their supplied order through the turn in #179. A
   declared partner's shared hinge now supports an aligned free layer edge
   in #181, while the plane check still separates the turning interior.
   A complete blintz recipe now chains four corner folds and a reopening in
   #183, carrying accepted angles/orders and checking continuity at every join.
   The first bird petal now has an exact ideal-path contact/length certificate
   and checked flat endpoint orders in #185. The second petal and final pressing
   now continue that checked route in #187, preserving both stage joins.
   The initial square-base collapse now joins that route in #189. General flap/wing
   authoring, an angle solver and checks for arbitrary coupled motions remain open
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
  the crane is rigid-foldable end to end is not known. #61 has three bounded motion
  checks: [fixed-hinge sweeps](notes/hinge-sweep-contact.md) bound a
  rigid rotation over angular intervals using floating-point arithmetic and a
  numerical guard; [correction sweeps](notes/checking-numerical-corrections.md)
  use exact rational bounds for straight numerical vertex paths. Both refuse
  unresolved intervals and check pairs sharing material vertices rather than
  skipping all neighbours. Straight numerical paths can stretch the sheet and
  are not folding instructions. The fixed-hinge check now backs the library's
  [flap operation](notes/checked-flap-operation.md) and the complete
  [blintz route](notes/chaining-checked-folds.md). The
  [first-petal certificate](notes/checked-petal.md) checks the seven coupled
  angles of one known bird petal using exact polynomial signs. The
  [complete bird route](notes/checked-bird-base.md) adds the second petal and
  final pressing with checked joins. The [initial collapse](notes/checked-square-collapse.md)
  now connects the prepared open sheet to that route. The checkers
  report a colliding pose or an unresolved interval, not a guaranteed first
  impact time; #61 remains open.
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
  The [angular-energy study](notes/crease-and-panel-energy.md) adds crease
  preferences and panel bending. [Shared crease identities](notes/crease-identity-through-refinement.md)
  survive refinement, and [contact correction](notes/ordered-flap-contact.md)
  keeps declared lower/upper panels in order. The study can also
  [discover nearby triangle partners](notes/local-contact-discovery.md) within
  one bent panel and [retain newly encountered orders](notes/growing-local-contact-history.md)
  during numerical corrections. Discovery needs an encounter while the
  triangles are still separated.

  The latest [distance barrier](notes/directional-contact-distance.md), a
  penalty that grows as the required layer separation vanishes, acts before
  projected overlap reappears. It settles the recorded closing control after
  99 accepted corrections, with maximum relative material-edge error
  `1.18e-8`, all 496 endpoint triangle-pair checks passing, and every accepted
  straight numerical path checked. The opening control settles in three
  corrections at `6.56e-8`. These are the measured #173 runs, not promised
  iteration counts on every platform. [Rejected-trial diagnostics](notes/rejected-bending-trials.md)
  explain refusals and let the saved energies be replayed.

  These results cover retained directional orders: they can forbid passing
  around a layer even when there is no collision. The path check establishes
  separation, not preservation of directional order throughout the interval.
  Calibrating stiffness, general self-contact discovery/correction, automatic
  route planning and length-preserving folding motions remain open. None is a
  prerequisite for completing the representation milestone #146.
- **[#106](https://github.com/avalonalex/senbazuru/issues/106) body opening.**
  Representing a pocket is only the first step. Its expansion needs a driving
  control, compatible crease motion, possible panel bending and contact checks.
  Start with controlled opening; a pressure/volume model additionally needs a
  defined cavity and treatment of its openings.

### Medium: days, with a picture or a format to design

- **[#50](https://github.com/avalonalex/senbazuru/issues/50) side view** and **[#49](https://github.com/avalonalex/senbazuru/issues/49) cut-away.** The geometry
  exists. What a schematic side view of a 32-layer crane should look like, and
  where the cut-away circle comes from, does not.
- **[#54](https://github.com/avalonalex/senbazuru/issues/54) rotating a flap.**
  The rigid flap operation and complete checked blintz and helmet recipes are implemented.
  Where several moving creases meet at a vertex, their angles
  must change together to keep the paper joined; the four-crease case is
  [#52](https://github.com/avalonalex/senbazuru/issues/52). Production SVG
  handles open planar panels. The reusable operation now handles a fixed
  hinge with explicitly selected aligned segments, including flat endpoints with a checked one-sided
  approach and departure order. Touching stacks with a common rigid motion
  now retain their orders, including aligned free edges supported by a
  declared partner's shared hinge. A separate study recipe now checks
  both bird petals and final pressing continuously, with accepted geometry
  and layer requirements retained at both joins. It uses known compatible angle formulas.
  Sliding contact, unsupported hinge seams
  and the solve for compatible crease angles remain to be built.
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

The shared-surface milestone #146 is complete. The contact study through #173
now supplies one checked library motion in #175, extended with one-sided flat
endpoints in #177 and touching stacks in #179/#181. The first bird petal in
#185, extended through the second petal and final press in #187 and back to
the prepared open sheet in #189, adds a complete known route with continuously
checked coupled angles.

1. **One checked flap rotation**, a bounded part of
   [#54](https://github.com/avalonalex/senbazuru/issues/54) and
   [#61](https://github.com/avalonalex/senbazuru/issues/61). The first operation
   checks lengths, shared vertices and achieved angles, rejects a crossing
   route, and supplies SVG steps and glTF from the accepted surfaces. A complete
   single fold and reopening now preserve the order at flat touching endpoints.
   A small stack can now stay in contact during a move, retaining its order
   without overlooking other crossings, including a free upper edge reaching
   the lifting hinge. The complete blintz sequence now folds all four corners
   and reopens one, retaining endpoint orders and a stable central anchor.
   The first bird petal now checks seven coordinated angles from the square
   base through its flat landing, with an exact certificate for its ideal path.
   The second petal and final pressing now preserve accepted geometry and
   layer order through two checked stage joins. The initial square-base collapse
   adds a third checked join and completes the route from a prepared open sheet.
   The helmet route in #191 now selects several aligned segments for one
   physical hinge, then turns paired material creases on touching layers.
   The crane-wing recipe in #193 adds a crease to the real fixture and checks
   a 90-degree departure while its hinge rests across the other wing. The
   opposite direction is refused by the starting order. Its selected stacking
   keeps the tail between the body layers on both sides.
   The first experiment under [#195](https://github.com/avalonalex/senbazuru/issues/195)
   holds the root and tip of a separate uncreased wing-shaped sheet. [#196](https://github.com/avalonalex/senbazuru/issues/196)
   checks its static solves against a known strip and three mesh resolutions;
   [the measurements](notes/held-wing-bending.md) show remaining mesh sensitivity.
   [#198](https://github.com/avalonalex/senbazuru/issues/198) adds two touching
   layers of one folded diamond, exact grips and a declared initial order.
   Bending, initially penetrating and lifted-grip controls pass; incompatible
   grips remain refused. [#200](https://github.com/avalonalex/senbazuru/issues/200)
   resolves the fine-mesh linear stall with coupled preconditioning and checks
   the original linear residual. [Three resolutions](notes/coupled-touching-layer-solve.md)
   converge with decreasing observed shape/energy changes; this does not prove
   independence from mesh size.
   [#203](https://github.com/avalonalex/senbazuru/issues/203) now spreads that
   existing crane wing with a 30-degree root and 50-degree tip grip. Two local
   refinements pass static length, crease and whole-sheet contact checks;
   the body stays exactly fixed and the tucked tail retains its orders.
   An upper grip pushed through its partner remains a failed diagnostic.
   [The measurements](notes/spreading-connected-wing.md) retain the observed
   mesh dependence and the coplanar seam distance tolerance.
   [#205](https://github.com/avalonalex/senbazuru/issues/205) separates the root
   hold from crease stiffness/rest-angle preferences and tests a small released
   body patch. [Its measurements](notes/wing-root-holds.md) distinguish accepted
   static shapes from failed body attempts, and preserve inherited contact
   orders through held layers.
   **Next: compare the authored root spring with ordinary uncreased panel
   bending, and diagnose body-release failures before extending the free region.**
   [Photographed crane-opening references](notes/opening-a-crane.md) show why
   the larger experiment should use both wings and an opening body pocket.
   [#210](https://github.com/avalonalex/senbazuru/issues/210) now maps five
   connected material regions, including their side connections, and identifies
   22 candidate opening creases. [The map](notes/crane-pocket-map.md) distinguishes
   the core's internal perimeter from four separate underside landmarks; it
   does not yet identify a closed cavity. Next declare which candidate angles
   may change, resolve the earlier body solve, and test paired grips with the
   neck/tail attachments free. Measure their response rather than pinning it away.
   Keep these endpoint experiments distinct from a checked flexible route.
   Returning the rigid wing onto its resting surface and a joined sequence
   lowering both wings remain useful motion extensions.
   Sliding contact and general coupled-angle solving remain later work.
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
