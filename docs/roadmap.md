# Roadmap, and where we stand

The README's [roadmap](../README.md#roadmap) is the map: one completed
foundation and three open goals, each an issue tagged `roadmap` that holds the
approach and the acceptance criteria. This is the state of play behind it — what is done, what
is open, how hard each open piece is, and an order to take them in. It is a
snapshot and will drift, so it carries a date: **as of 2026-09-20**, with
**Track A's material priority refreshed on 2026-09-26** below. The historical
milestones include
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
the pocket material map in [#210](https://github.com/avalonalex/senbazuru/issues/210),
selected body-angle controls in [#212](https://github.com/avalonalex/senbazuru/issues/212),
internal crease diagnostics in [#214](https://github.com/avalonalex/senbazuru/issues/214),
the small closed-crease reference in [#216](https://github.com/avalonalex/senbazuru/issues/216),
its contact-correction controls in [#218](https://github.com/avalonalex/senbazuru/issues/218),
nonnegative-gap constraints in [#220](https://github.com/avalonalex/senbazuru/issues/220),
both bending crease panels in [#222](https://github.com/avalonalex/senbazuru/issues/222),
unequal controls in [#224](https://github.com/avalonalex/senbazuru/issues/224),
independent mesh refinement in [#227](https://github.com/avalonalex/senbazuru/issues/227),
the fine-mesh solver comparison in [#229](https://github.com/avalonalex/senbazuru/issues/229),
the common-policy grid in [#231](https://github.com/avalonalex/senbazuru/issues/231),
its `4×2` completion in [#233](https://github.com/avalonalex/senbazuru/issues/233),
distributed bend preferences in [#235](https://github.com/avalonalex/senbazuru/issues/235),
the common band policy in [#241](https://github.com/avalonalex/senbazuru/issues/241),
its `8×1` follow-up in [#243](https://github.com/avalonalex/senbazuru/issues/243),
and the `8×2` decision study in [#245](https://github.com/avalonalex/senbazuru/issues/245). The
README and the issues stay the source; update this when a roadmap issue
closes.

## Where the project stands

**Material priority, 2026-09-26:** [#315](https://github.com/avalonalex/senbazuru/issues/315)
[sets an illustration milestone](notes/illustration-material-priority.md).
Energy/opening refinement percentages and strict numerical residuals remain
research diagnostics. Connected paper and explicit drawing-scale review gate
approximate illustrations; convergence is required only for a claim of a solved
material equilibrium. The owner permits looser accuracy when the drawing supports it.
The body-contact work through [#375](https://github.com/avalonalex/senbazuru/pull/375)
meets the first deliverable's **reproducible geometry/solver blocker** option.
There is still no accepted opened body; #195 and track A of #269 remain open.

**Both bounded initializations stopped at blockers.**
[#379](https://github.com/avalonalex/senbazuru/issues/379)
[lowers a weighted construction cost](notes/body-separated-initialization.md),
but four retained corrections leave negative gaps and excess length error.
The owner-selected [constraint-first attempt](notes/body-feasible-initialization.md)
in [#381](https://github.com/avalonalex/senbazuru/issues/381) instead bounds
lengths and reduces the largest clearance deficit. Its first direction fails
original-row verification after 115 iterations: no geometry trial or correction
is retained. The unverified proposal still has negative gaps, edge error just
above `1e-5`, and no change in body depth; maximum movement is 0.00350 drawing
pixels. No candidate is barrier-ready and no body barrier solve has run.

**A new angle-derived pose closes but intersects.** The owner approved
[#383](https://github.com/avalonalex/senbazuru/issues/383)'s
[crease-based construction](notes/body-crease-seed.md) and new grip positions.
Two angle corrections satisfy shared vertices and achieved angles; lengths
stay within `2.2e-11`. The same shape has four coarse or eighteen refined
crossing pairs, with a reversed-order height near 4.71 drawing pixels. It is
not barrier-ready. Subdivision changes counts, not the intersecting shape.

**Contact-aware angle construction stops at numerical verification.**
[#385](https://github.com/avalonalex/senbazuru/issues/385)
[includes all inherited overlap corners and loop bounds together](notes/body-angle-contact.md).
Its first constrained direction fails original-row checks after 34 inner
iterations, so no angle changes or geometry trials occur. The starting
crossings remain. This is a solver blocker, not proof that no valid arrangement
exists. [#387](https://github.com/avalonalex/senbazuru/issues/387)
[audits that saved problem](notes/body-angle-audit.md): exact arithmetic on
the same twelve selected equalities satisfies all 1,204 inequalities, as does
rounding the result once to Double. The maximum angle-direction change is
`1.35e-7°`; no body pose changes. The owner’s 2026-09-26 guidance prioritizes plausible illustrations.
[#389](https://github.com/avalonalex/senbazuru/issues/389)
[assesses saved poses at drawing scale](notes/body-illustration-tolerances.md):
the second correction's longest refused crossing is 0.0059 px, versus 62 px
in the strained control and a 4.71 px reversed-order depth in the angle seed.
Provisional 0.1 px distance and 0.1% local-strain screens separate these cases;
they are review aids, not solver defaults. All four views currently fall back
from projected visibility, so next compare visible layers on the recovered seed
and second correction under a declared depth-tie allowance. Keep their geometry
and strict verdicts. More solver precision is deferred until it benefits the
picture or a useful opening; do not resume individual-pair repairs. The matched barrier/penalty comparison remains blocked;
physical thickness, pressure and full-crane response remain later studies.

The following evidence explains that decision. [The first bounded body-patch
comparison](notes/coupled-body-patch.md)
retains unsettled coarse poses and a failed refined control.
[The saved-checkpoint audit](notes/body-patch-checkpoints.md) finds pre-existing
order defects and first-correction crossings. [Subdivision of its recovered
coarse endpoint](notes/recovered-body-subdivision.md) now supplies a valid
120-triangle start, but a forty-step continuation remains unsettled and develops
three crossings. [Inspection of correction 1→2](notes/body-contact-diagnosis.md)
finds complete contact coverage but shallow negative gaps: a finite penalty and
whole-triangle crossing test enforce different conditions.
[Replaying the saved proposal](notes/body-correction-replay.md) finds that 1/64
lowers cost by 0.177505% while passing unchanged geometry checks; 1/32 still
crosses. The [bounded continuation](notes/body-geometry-continuation.md) now
retains passing geometry for seven tiny moves, then stalls on correction 8.
Cost falls 0.226368%, but full movement remains 11,392 times above convergence;
total displacement is below 0.014 drawing pixels. The
[contact-aware direction](notes/body-contact-direction.md) now passes at 1/128,
lowering cost 0.085385%; both ordinary controls remain blocked. At 1/64,
neighboring pair 14–55 crosses. [Guarding both pairs](notes/body-contact-pairs.md)
now permits 1/8 with cost down 1.256878%; 1/4 crosses pair 46–70. The selected
move is below 0.086 drawing pixels and full movement remains 11,438 times above
equilibrium. [Adding 46–70](notes/body-third-contact.md) leaves the direction unchanged: its
guards are inactive, while the actual gap worsens beyond the linear prediction.
[Ten refreshed corrections](notes/body-short-corrections.md) now pass, but move
only 0.112 drawing pixels and lower cost 1.604856%. The last fraction is
1/32,768; full movement remains 9,036 times above equilibrium.
[Inspecting the saved final refusal](notes/body-final-contact.md) locates it at
vertex 27: it crosses the negative plane threshold outside triangle 70's
projected outline while the actual overlap gap improves.
[Adding that local plane guard](notes/body-plane-guard.md) increases the usable
fraction from 1/32768 to 1/256, but moves only 0.00216 drawing pixels. Finite
plane motion still makes 1/128 fail at 46–70.
[Saved distance accounting](notes/body-plane-loss.md) attributes about 98% of
that missed loss to the interaction of relative vertex movement and plane
rotation under a centroid convention. A second-order estimate closely matches
the saved result. [One local restoration](notes/body-contact-restoration.md)
now makes 1/128 pass: at most `3.07e-12` sheet lengths of repair, positive overlap
guard margins and a further `3.54e-10` cost decrease.
[One fresh direction](notes/body-fresh-direction.md) then selects 1/256 and
lowers cost another 0.029073%, but moves only 0.00213 drawing pixels. The new
1/128 trial again crosses at 46–70.
[Repeating one repair](notes/body-fresh-restoration.md) makes that fresh 1/128
pass: maximum movement `2.97e-12` sheet lengths, with all guards and actual
geometry/cost checks unchanged.
[The bounded repair loop](notes/body-restoration-loop.md) now retains ten
corrections, three using repair. Cost falls 1.720266% and net movement is
0.165283 drawing pixels; the last full proposal remains 5,326 times above
equilibrium. [Inspecting 55–93](notes/body-contact-55-93.md) locates the last
refusal at vertex 30 against plane 93; overlap derivatives accurately predict
worsening gaps too. [Adding those six guards](notes/body-fourth-pair.md) accepts
1/8 without repair, versus the saved 1/128, reducing starting cost by 0.390833%
with all geometry checks kept. The larger 1/4 trial now crosses already-guarded 14–55.
[The saved inspection](notes/body-contact-14-55.md) finds that both triangles
already straddle: the intersection length crosses tolerance as corner 0's actual
gap loss exceeds its linear prediction. Doubling the correction quadruples
that discrepancy. [One overlap repair](notes/body-overlap-restoration.md)
clears the crossing and passes actual geometry/cost, but fails two original
55–93 guards and one refreshed guard. The proposed joint repair protecting
all nineteen original and eighteen refreshed guards is now deferred by the
bounded barrier comparison above. No accepted body-opening endpoint yet.
Earlier failures and unmet research targets below
remain evidence, not current prerequisites for starting that study.

| | |
| --- | --- |
| Stage | Alpha; obsolete internal paths can be replaced as regression cases pass |
| Material study | Connected meshes, length/contact checks, square/waterbomb collapse, fish ears, bird petals and six more base endpoints |
| Production handoff | Shared surfaces reach SVG and two glTF scenes; complete blintz and helmet routes plus a crane-wing departure use checked flap operations, and the open-sheet-to-bird route has exact ideal-path certificates; frog stages still have sampled checks |
| Contact study | Checks one fixed-hinge rotation or straight numerical correction throughout its interval; learned contact orders and a distance barrier settle the recorded opening/closing strip controls |
| Tests | 1,926 examples pass for #389, including drawing-scale contact-region clipping and broad/shallow overlap counterexamples; exact audits of saved constrained equations and refusal of invalid working sets; contact-aware angle derivatives, material adjacency, valid layer order and refused-direction preservation; bounded crease-angle construction, independent loop closure and unchanged material identities; constraint-first initialization with simultaneous layers, hard length/movement limits and exact holds; bounded separated initialization with shared vertices and fixed work limits; overlap-gap restoration above held paper and invalid/repeated-gradient handling, the bounded one-repair search policy, one minimum-movement plane restoration, finite plane-distance accounting and the moving-plane derivative and saved six-vertex plane-threshold transition, incremental contact guards, geometry-gated continuation, saved body-correction replay and archive diagnostics, isolated fractional-band solve fixtures through `4×1`, fractional band-boundary energies and derivatives, prescribed-bend angular/length formulas, exposed-region distance and area bounds, several bounded contact replacements and refusal of a partial repair, fixed-band turn/energy normalization and exact boundary clipping, passive/control energy accounting and 4×2 material identities, a stricter near-parallel contact exchange and stronger fine-mesh length enforcement, independent width refinement and fixed-location gap sampling, unequal panel controls and contact-off comparisons, both moving crease panels, nonnegative-gap constraints, small-crease correction/contact references, internal-crease diagnostic controls, body-angle policies and the crane material map, wing-root/body controls, inherited contact orders, exact bending grips and a known strip, a checked crane wing with its tail tucked inside, complete helmet, quarter-fold, blintz and bird routes, aligned stacks, flat landing/reopening and material/contact checks |
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
   The earlier plan was to compare the authored root spring with ordinary
   uncreased panel bending and diagnose body-release failures. The current
   priority is the bounded illustration study recorded at the end of this item.
   [Photographed crane-opening references](notes/opening-a-crane.md) show why
   the larger experiment should use both wings and an opening body pocket.
   [#210](https://github.com/avalonalex/senbazuru/issues/210) now maps five
   connected material regions, including their side connections, and identifies
   22 candidate opening creases. [The map](notes/crane-pocket-map.md) distinguishes
   the core's internal perimeter from four separate underside landmarks; it
   does not yet identify a closed cavity. [#212](https://github.com/avalonalex/senbazuru/issues/212)
   [compares preferences](notes/body-angle-preferences.md) at two candidates
   without changing the earlier free patch or grips. Weaker springs and a 170°
   preference leave essentially the same failed shape; the selected-angle gate
   was not the blocker. [#214](https://github.com/avalonalex/senbazuru/issues/214)
   [isolates folds 26/51](notes/internal-crease-diagnostic.md): holding their
   shared lines reaches numerical equilibrium but still fails angle/contact
   checks, and omitting surrounding forces makes the whole-sheet result worse.
   The original reaches its iteration budget without exhausting a line search;
   eighty more final-stage iterations reduce length error and crossing reports
   but do not produce an accepted endpoint. [#216](https://github.com/avalonalex/senbazuru/issues/216)
   now [extracts one closed crease](notes/near-closed-crease.md) with exact
   length-preserving profiles. The controls expose a real microscopic crossing
   inside the tolerance and a separate false report from an overextended plane
   cut; the latter is corrected without changing tolerances.
   [#218](https://github.com/avalonalex/senbazuru/issues/218) now
   [tests contact correction](notes/contact-correction-at-a-crease.md) on that
   fixture. Holding the lower panel and outer upper strip, three contact-enabled
   starts converge and pass numerical length/angle/contact checks at both
   resolutions. Exact gap checks still find penetration around `6e-11` and
   `8e-11` sheet lengths, even from perfect touching. No-contact and impossible
   hold controls fail independently. The solver and tolerances are unchanged.
   [#220](https://github.com/avalonalex/senbazuru/issues/220) now
   [requires nonnegative gaps](notes/nonnegative-crease-contact.md) on the same
   fixed lower panel. All six compatible constrained endpoints have exact
   minimum gap zero, comparable length error and passing angle/contact checks;
   incompatible holds are refused. Initial repairs and accepted-step lifts
   remain explicit numerical corrections, without adding thickness.
   [#222](https://github.com/avalonalex/senbazuru/issues/222) now
   [releases both interiors](notes/coupled-crease-contact.md) with the shared
   crease and both outer strips held. Current-triangle contacts and opposite
   repairs preserve exact order; six symmetric endpoints pass and incompatible
   holds are refused. Both panels move, but matching material positions change
   by up to `0.001558` sheet lengths under refinement.
   [#224](https://github.com/avalonalex/senbazuru/issues/224) now
   [compares unequal upper controls](notes/unequal-crease-controls.md), holding
   narrow crease-adjacent strips and both outer edges. An opened upper grip
   separates the paper; an upper bend preference changes the lower through
   contact. The identical contact-off control crosses. All six constrained
   endpoints pass, but the preferred-bend maximum gap changes from `7.271e-7`
   to `0.007009` with refinement despite unchanged control strength.
   [#227](https://github.com/avalonalex/senbazuru/issues/227)
   [refines length and width independently](notes/unequal-crease-refinement.md).
   Doubling width retains the fine-length opening (maximum gap `0.006907`),
   but the next length refinement fails: matched/contact-off length errors
   exceed the cap and the upper-preference constrained step does not converge.
   Eight constrained endpoints pass; the two finer-length failures remain
   diagnostics, so shape convergence is not established.
   [#229](https://github.com/avalonalex/senbazuru/issues/229) now
   [separates the two numerical failures](notes/fine-crease-solver.md) on that
   same fine mesh. An extra length-penalty stage fixes the matched/contact-off
   length failure. Exchanging one selected contact equality for a stricter,
   nearly parallel inequality resolves the upper-preference inner step.
   Both changes together yield a passing upper-preference endpoint, with
   relative length error `3.961e-6`; neither physical nor numerical acceptance
   caps change. Four combinations retain the original policies as controls,
   and the contact-off result still crosses.
   [#231](https://github.com/avalonalex/senbazuru/issues/231) now
   [reruns all five meshes with that policy](notes/combined-crease-refinement.md).
   All fifteen solves converge; all ten constrained endpoints pass, while all
   five contact-off controls still cross. Width refinement retains the opening,
   but the upper-preference matching-position change grows from `0.001298`
   to `0.004552` across the two length doublings. The fine endpoint is accepted;
   shape convergence remains unestablished.
   [#233](https://github.com/avalonalex/senbazuru/issues/233) adds the missing
   [`4×2` comparison](notes/two-direction-crease-refinement.md): all eighteen
   solves converge and all twelve constrained endpoints pass. The second
   length change remains large at width two (`0.004398`), while the `4×1→4×2`
   width change is `0.0003004`. Passive stiffness beneath each imposed line
   doubles with length refinement while control stiffness stays fixed;
   achieved turns shrink and the separate passive/control energies rise.
   [#235](https://github.com/avalonalex/senbazuru/issues/235) compares a
   [fixed-width bend preference](notes/distributed-bend-preference.md), keeping
   total desired turn and flat-paper control energy fixed under refinement.
   Four of six constrained band endpoints pass; both middle meshes fail the
   inner contact residual checks, while retaining exact nonnegative gaps.
   All fifty-four old reference states are unchanged. The accepted fine-width
   comparison still changes matching positions by `0.0005894` and near-contact
   samples from 894 to 630, so the shape is not established as mesh independent.
   [#237](https://github.com/avalonalex/senbazuru/issues/237)
   [replays those two failures](notes/several-contact-exchanges.md): more than
   one contact equality must be replaced. An opt-in sequence of improving
   replacements passes every unchanged inner residual cap. Complete `2×1`
   and `2×2` band endpoints now pass, with relative edge errors `1.483e-6`
   and `6.541e-7` and exact minimum gap zero. The matched, original line-load
   and contact-off endpoints are unchanged; the original failures remain
   reproducible controls.
   [#239](https://github.com/avalonalex/senbazuru/issues/239)
   [isolates the fine contact-off length failures](notes/fine-band-length-enforcement.md).
   Restarting either endpoint at `1e9` makes no movement; raising the weight
   to `1e10` brings relative edge error below `2.3e-6` at both widths, with
   the same `1e-5` cap. Both still cross and remain invalid paper.
   [#241](https://github.com/avalonalex/senbazuru/issues/241)
   [repeats the full band grid](notes/combined-band-refinement.md) with weights
   through `1e10` and progressive contact exchange on every run. All thirty
   solves converge and all eighteen constrained endpoints pass; all twelve
   contact-off controls still cross. Fine band openings are `0.003760` and
   `0.003287`, while middle-mesh gaps shrink roughly tenfold with the stronger
   penalty. The second length doubling changes matching positions by
   `0.003290` / `0.002800`, more than the first at either width.
   [#243](https://github.com/avalonalex/senbazuru/issues/243)
   [adds the next length doubling](notes/band-refinement-8.md): `8×1` matched
   and band endpoints pass, while contact-off still crosses. The band change
   from `4×1→8×1` shrinks to `0.001233`, with maximum opening `0.004151` and
   relative edge error `3.570e-6`. Energies still shift, so this encouraging
   result does not establish mesh convergence. The agreed study exit targets
   are less than 0.1% sheet-length movement and less than 5% changes in opening
   and each nonzero bending-energy component under both length and width
   refinement, with stable contact regions and all existing endpoint checks.
   A tighter-solve confirmation must also stay within those budgets. These
   are engineering targets, not calibrated real-paper standards.
   [#245](https://github.com/avalonalex/senbazuru/issues/245)
   [completes the `8×2` comparison](notes/band-refinement-8x2.md). All nine
   solves converge and all six constrained endpoints pass; contact-off still
   crosses. The band misses the shape target along length (`0.001770`) and
   meets it across width (`0.0004075`), but opening changes 37.74% / 9.07%
   and upper/imposed energies miss the 5% target in both directions. Matched
   passive energies also change 6.47% along length. The accepted band solve
   costs 2491.6 local CPU seconds; this work stays outside default CI.
   [#247](https://github.com/avalonalex/senbazuru/issues/247)
   [compares the saved paper at illustration scale](notes/illustration-scale-refinement.md),
   without another solve. All accepted position changes stay below 1.08 pixels
   at 600 pixels per sheet unit; silhouettes and visible creases meet the
   provisional two-pixel budget. Matched controls and the top-view band meet
   every sampled check. Six oblique band comparisons still flag thin exposed
   layer slivers and do not get an automatic all-checks pass. The original
   material targets remain open; illustration readiness is a separate milestone.
   [#249](https://github.com/avalonalex/senbazuru/issues/249)
   [measures real polygon exposure and isolates each layer](notes/thin-layer-visibility.md).
   All six oblique comparisons still flag the minority layer on all twelve
   density/offset grids. Counts are sampling-sensitive; the underlying exposure
   is real. No small-area waiver or all-camera acceptance is established.
   [#251](https://github.com/avalonalex/senbazuru/issues/251)
   [bounds distances over the filled exposed regions](notes/exposed-layer-distance.md).
   The 45°-below length pair passes geometry despite its pixel failure; both
   top-view pairs fail geometry despite passing pixels. Several large maxima
   come from exposed fragments smaller than 0.001 px², so maximum distance alone
   does not express their visual importance. All eight band pairs remain in
   review; matched controls pass and contact-off remains diagnostic.
   [#253](https://github.com/avalonalex/senbazuru/issues/253)
   [bounds area beyond two pixels](notes/exposed-area-budget.md) in both
   directions. All 64 measurements reach 0.00001 px² precision; the low-angle
   length pair reaches 0.6165 px² outside in one direction, while several
   distant-fragment comparisons stay below 0.002 px². No area waiver is adopted;
   all existing verdicts and material/contact limits remain unchanged.
   [#255](https://github.com/avalonalex/senbazuru/issues/255)
   [locates these contributions at 1× and 32×](notes/exposed-area-highlights.md),
   retaining unclassified regions and unrounded geometry. Two adjacent
   16-pixel tiles hold 97.9% / 96.7% of the above/low-angle length mismatch:
   a thin strip along the lower outline. Distant fragments contribute much less
   area; no region is dropped and no review verdict changes.
   **Illustration next: review these concrete strips at the intended drawing
   size before deciding a feature-specific illustration rule.
   Material accuracy: [#257](https://github.com/avalonalex/senbazuru/issues/257)
   [measures prescribed bends](notes/prescribed-bend-energy.md) on all eight
   existing meshes without optimization or contact repair. Fixed-corner energy
   doubles with length refinement; the smooth cylinder's passive/control
   costs approach explicit limits. Its sampled chords still miss the length
   cap at `8×2`, while a full-length polygon has the same angular energy and
   negligible length cost. Width leaves angular energies unchanged but adds
   length-residual terms. These diagnose representation effects, not the cause
   of every optimized shape change.
   [#259](https://github.com/avalonalex/senbazuru/issues/259)
   [compares fractional band turns](notes/band-boundary-fractions.md): the
   cylinder's imposed energy is now 0.8343544 on every existing mesh, with
   matching analytic/spatial derivatives. Flat normalization and full intervals
   are unchanged; fixed-corner costs still grow. The original measurements
   and SVG/FOLD geometry remain intact, and the candidate is not a default.
   [#261](https://github.com/avalonalex/senbazuru/issues/261)
   [tests both rules in small solves](notes/fractional-band-solves.md): all
   twelve converge, eight constrained endpoints pass and four contact-off
   endpoints cross. Original references and matched controls reproduce exactly.
   The candidate moves both panels by about 0.00065 sheet lengths; width
   sensitivity does not improve; tiny openings remain dependent on numerical policy.
   [#263](https://github.com/avalonalex/senbazuru/issues/263)
   [doubles length at fixed width](notes/fractional-band-length.md): all twelve
   solves converge and eight constrained endpoints pass, but the fractional
   rule only reduces the shape change from 0.003290 to 0.003016 sheet lengths.
   Both miss the 0.001 target; opening and all nonzero energy components miss
   5%. Even matched passive energies change by 9.33%, without a band.
   [#265](https://github.com/avalonalex/senbazuru/issues/265)
   [maps the saved spring costs](notes/bending-energy-locations.md) without new
   solves. Matched energy grows mainly in the interior while boundary-line
   costs fall. At `4×1`, both loaded upper panels turn back at a newly available
   bend between the band end and held outer edge; it accounts for
   about 53–55% of the net upper passive-energy increase. Crossing controls
   show it too. These are discrete contributions, not continuous area densities.
   [#267](https://github.com/avalonalex/senbazuru/issues/267)
   [refines that outer strip separately](notes/outer-strip-refinement.md),
   comparing 64/72/120/128-triangle meshes under the same policy. Outer-only
   opens by 0.002808 / 0.002710 sheet lengths under the original/fractional
   rules, while its matched passive-energy change is only 0.32%; refining the
   rest changes matched energy by 8.99%. The extra outer bend matters, but
   does not explain every refinement effect. Nonuniform spring supports are
   explicit. Of 24 solves, 22 converge and 15 constrained endpoints pass;
   fractional rest-only and original contact-off outer-only exhaust the final
   iteration budget. All contact-off endpoints cross.
   [#270](https://github.com/avalonalex/senbazuru/issues/270)
   [continues those saved endpoints](notes/outer-strip-continuation.md) at the
   same final weight. They converge in 2 / 15 additional iterations, moving
   at most 1.04e-7 / 2.77e-7 sheet lengths. Rest-only now passes; contact-off
   still crosses. Original budgets and reports remain intact.
   [#272](https://github.com/avalonalex/senbazuru/issues/272)
   [locates the saved matched-energy difference](notes/matched-energy-locations.md)
   without new solves: interior costs rise by 0.014127 per panel while costs
   on the held boundary and 7/16 line fall by 0.005207. Their net, with the
   outer strip, is 0.008933 (8.9857%). Shared, added and removed material edges
   reconcile every contribution; both rule-labelled archives agree exactly.
   [#284](https://github.com/avalonalex/senbazuru/issues/284)
   [prescribes bends on those same meshes](notes/prescribed-uneven-bends.md)
   without optimization. Interior refinement raises cylinder cost by 3.57%
   and the held-start bend by 2.38%; uncovered boundary intervals and transition
   averaging account for their full differences. Full-length segments retain
   those angular costs while removing chord shortening. The old outer grips
   are not imposed, so this does not explain all the solved 8.99% change.
   [#288](https://github.com/avalonalex/senbazuru/issues/288)
   [retains both original grip regions](notes/prescribed-held-bend.md).
   Four geometrically fitted full-length polygons pass the unchanged material,
   grip, original-crease and known-order checks. Their passive costs change by
   11.98% under interior refinement, with matching vertices moving 0.0009846
   sheet lengths. The common smooth reference already changes discrete cost
   by 10.74%; fitted curve parameters also change. Sampled length failures and
   unfitted grip drift remain diagnostic. No material-equilibrium solve runs.
   [#291](https://github.com/avalonalex/senbazuru/issues/291)
   [smooths those curvature transitions](notes/smooth-held-bend.md) with the
   same grips. The common-reference gap grows to 17.16%, and the fitted gap
   to 17.50% with 0.0010468 matching-vertex movement. Geometry still passes;
   the smoother family concentrates bending into a shorter region. Its fine
   common-curve cost is closer to its own analytic value (6.41% low, versus
   9.21% for the circle), so successive-mesh gaps alone do not grade accuracy.
   [#295](https://github.com/avalonalex/senbazuru/issues/295)
   [keeps both curves fixed through five nested meshes](notes/fixed-bend-refinement.md).
   At 1,024 triangles, circular/smooth analytic-cost errors fall to 1.19% / 0.12%.
   Full-length grip drifts remain 9.65e-7 / 1.24e-6 sheet lengths; sampled
   relative edge errors are 5.95e-6 / 1.63e-5. These are diagnostic references,
   not equilibria or completion of the solved-material refinement criteria.
   [#298](https://github.com/avalonalex/senbazuru/issues/298)
   [compares fixed local and uniform placement at equal budgets](notes/transition-refinement.md).
   At 1,024 triangles, local circular/smooth cost errors are 0.59% / 0.096%,
   versus uniform 1.19% / 0.12%. Local full-length grip drifts increase to
   2.36e-6 / 4.22e-6 sheet lengths; whole-material uniform/local differences
   are 2.33e-5 / 3.85e-5. No fit or material solve runs; acceptance criteria stay fixed.
   [#301](https://github.com/avalonalex/senbazuru/issues/301)
   [resolves the whole curved interval at equal budgets](notes/whole-bend-refinement.md).
   At 1,024 triangles, circular/smooth cost errors are 0.89% / 0.031%.
   Full-length grip drift falls to 2.41e-7 / 3.10e-7 sheet lengths, and both
   sampled references meet the unchanged length cap. Whole-bend geometry is
   better on these controls, but the join windows still estimate circular
   cost more accurately. No fit or equilibrium solve runs.
   [#303](https://github.com/avalonalex/senbazuru/issues/303)
   [tests held-panel equilibrium at 128 and 256 triangles](notes/held-panel-equilibrium.md).
   All four uniform/whole-bend solves converge and pass the unchanged paper
   checks. Maximum opening stays below 7.44e-14 sheet lengths. Uniform refinement
   changes shape by 0.000704 and passive costs by 6.49%; whole-bend refinement
   changes them by 0.001170 and 8.31%. Both miss the 5% cost target; whole-bend
   also misses the 0.001 shape target. Lower cost does not select the better mesh.
   [#306](https://github.com/avalonalex/senbazuru/issues/306)
   [locates those costs on the saved meshes](notes/held-bending-costs.md), without
   solving again. Held-boundary costs fall by 0.006870 / 0.003739, while the first
   free interval rises by 0.007203 / 0.006998 and remaining free paper rises by
   0.006724 / 0.004702 (uniform / whole bend, per panel). Raw boundary angles
   shrink, but angle divided by material spacing increases. Differences are
   distributed, not confined to the boundary spring.
   [#308](https://github.com/avalonalex/senbazuru/issues/308)
   [confirms both 256-triangle endpoints at a tighter stop](notes/held-endpoint-confirmation.md).
   They settle at `1e-8` in four / three extra iterations, with movement below
   `8.1e-8` and passive-cost changes below `0.00001%`. All paper checks pass;
   the original 6.49% / 8.31% refinement gaps remain.
   [#311](https://github.com/avalonalex/senbazuru/issues/311)
   [compares 256 → 512 triangles at fixed width](notes/held-panel-refinement.md).
   Both finer endpoints converge at `1e-8` and pass paper checks. Shape changes
   are 0.000587 / 0.000501 and passive changes shrink to 3.75% / 3.78%, meeting
   those targets. Equal-budget layouts still differ by 10.36%; length-penalty
   costs rise 348% / 489% despite passing edge errors. No overall material
   convergence is claimed.
   [#313](https://github.com/avalonalex/senbazuru/issues/313)
   [locates that layout gap beside length penalties](notes/held-layout-costs.md)
   on four unchanged endpoints, without solves or repairs. At 512 triangles,
   98.32% of the passive gap lies in free paper; lower transverse costs are
   partly offset by higher diagonal costs. The largest length penalty lies
   farther out than the worst relative error, which sits just outside the grip.
   **Owner priority: [#315](https://github.com/avalonalex/senbazuru/issues/315)
   [prioritizes plausible crane illustrations](notes/illustration-material-priority.md).
   Defer shape-preserving width subdivision and further cost-refinement studies
   until a visible artifact, meaningful layer change or unreliable authored
   control makes them relevant. Return to a small body patch connected to both
   wing roots, with declared spread/opening controls and free neck/tail
   attachment response. Preserve endpoint material/contact and solver checks;
   earlier body-release failures still need a compatible geometry.
   Review a few static poses at declared drawing sizes and cameras, with
   refinement evidence and separate diagnostics. Energy and relative-opening
   convergence are deferred research, not illustration gates. Keep calibrated
   physics, pressure loads and default-policy changes separate.
   Profile the expensive accepted case under #208 before another large solve.**
   [#317](https://github.com/avalonalex/senbazuru/issues/317) now implements
   [that first isolated specimen](notes/coupled-body-patch.md): sixteen panels,
   three exact holds and free neck/tail attachment landmarks. The closed
   reference passes. Coarse 5°/10° endpoints pass lengths and contact but exhaust
   the solve budget; the refined 5° case fails lengths/contact as well.
   [#319](https://github.com/avalonalex/senbazuru/issues/319)
   [remeasures fifty saved checkpoints](notes/body-patch-checkpoints.md), with
   no new solves. Both guesses already reverse layers; crossings appear in
   correction 0→1. The coarse case pauses near 121–130 before recovering by
   160; the refined case retains large length/contact penalties. Its initial
   contact cost is 6.538× larger on the same subdivided shape, a candidate
   contributor rather than an isolated cause.
   [#321](https://github.com/avalonalex/senbazuru/issues/321) verifies
   [subdivision of that recovered shape](notes/recovered-body-subdivision.md):
   the inherited 120-triangle seed passes geometry. Forty corrections at the
   same final penalty reduce cost but leave three crossings and a full proposal
   357 times above the movement limit. All 456 refusals and full proposals are
   saved. The original failed refined control remains unchanged.
   [#323](https://github.com/avalonalex/senbazuru/issues/323) locates those
   [shallow intersections](notes/body-contact-diagnosis.md) with four contact
   samples per pair. Negative height gaps (2.70e-9–1.72e-8) are penalized but
   below the order-reporting tolerance; whole-triangle straddling and section
   overlap still fail the crossing check. Bending savings outweigh increased
   length/contact penalties. No sampling partner is missing in these pairs.
   [#325](https://github.com/avalonalex/senbazuru/issues/325)
   [replays all 31 fractions](notes/body-correction-replay.md) without new solves.
   The first passing choice, 1/64, lowers cost 0.177505%; 1/32 still reports
   pair 22–63 crossing. Smaller tolerated intersections remain diagnostic.
   [#327](https://github.com/avalonalex/senbazuru/issues/327)
   [continues with both gates](notes/body-geometry-continuation.md). Seven tiny
   accepted corrections lower cost 0.226368%; search 8 blocks on pair 22–63.
   All returned geometry passes, but the full proposal remains far above
   convergence. All 134 refusals are saved: 16 cost and 118 geometry failures.
   [#329](https://github.com/avalonalex/senbazuru/issues/329)
   [guards pair 22–63 in the direction](notes/body-contact-direction.md). A
   verified quadratic selects 1/128, lowering cost 0.085385% with all geometry
   gates passing; both ordinary controls remain blocked. At 1/64, pair 14–55
   crosses. The selected move is only 0.00533 drawing pixels and remains
   unsettled. [#333](https://github.com/avalonalex/senbazuru/issues/333)
   [guards both pairs](notes/body-contact-pairs.md): 1/8 lowers cost 1.256878%
   with all unchanged gates passing; 1/4 instead crosses 46–70. Full movement
   stays 11,438× above equilibrium, and the selected movement is below 0.086
   drawing pixels. Both old controls and the one-pair result are unchanged.
   [#336](https://github.com/avalonalex/senbazuru/issues/336)
   [adds 46–70](notes/body-third-contact.md), but its four guards are inactive:
   the direction and selected 1/8 are unchanged. The actual gap at 1/4 worsens
   despite a locally predicted improvement. All four earlier controls remain
   unchanged. [#339](https://github.com/avalonalex/senbazuru/issues/339)
   [refreshes those guards for ten corrections](notes/body-short-corrections.md).
   All ten retain passing shapes, with cost down 1.604856% and total movement
   0.112 drawing pixels. Late fractions shrink to 1/32,768 against 46–70, while
   full movement remains 9,036× above equilibrium. The almost-motionless second
   correction and temporary other crossing pairs remain diagnostics.
   [#342](https://github.com/avalonalex/senbazuru/issues/342)
   [inspects that refusal without solving](notes/body-final-contact.md): vertex
   27 crosses the negative plane threshold outside triangle 70's projected
   outline, while the overlap gap improves.
   [#345](https://github.com/avalonalex/senbazuru/issues/345)
   [adds that local plane guard](notes/body-plane-guard.md): one matched quadratic
   selects 1/256 instead of 1/32768, with all unchanged gates passing. The
   selected movement is only 0.00216 drawing pixels and the next larger 1/128
   still crosses 46–70 despite a nearly unchanged linear distance prediction.
   [#347](https://github.com/avalonalex/senbazuru/issues/347)
   [accounts for that loss without solving](notes/body-plane-loss.md): about 98%
   comes from relative movement interacting with the rotated normal under the
   centroid convention. The second-order estimate closely matches 1/128 and
   1/256; every saved acceptance decision remains unchanged.
   [#349](https://github.com/avalonalex/senbazuru/issues/349)
   [restores that one trial](notes/body-contact-restoration.md): a maximum repair
   of `3.07e-12` sheet lengths makes 1/128 pass the same all-pair geometry,
   original/refreshed guards and cost checks. No further main direction runs.
   [#351](https://github.com/avalonalex/senbazuru/issues/351)
   [rebuilds one direction at that repair](notes/body-fresh-direction.md): the
   quadratic verifies and selects 1/256, lowering cost 0.029073%; movement is
   only 0.00213 drawing pixels and 1/128 again crosses at 46–70.
   [#354](https://github.com/avalonalex/senbazuru/issues/354)
   [repairs that fresh 1/128](notes/body-fresh-restoration.md): `2.97e-12` sheet
   lengths of movement restore passing geometry and guards, with cost falling
   a further `3.41e-10`. No additional main direction or loop runs.
   [#356](https://github.com/avalonalex/senbazuru/issues/356)
   [runs that bounded loop](notes/body-restoration-loop.md): all ten corrections
   pass, three needing repair, with 1.720266% less cost and 0.165283 drawing pixels
   of net movement. The ten-correction budget stops an unsettled run; the last
   full proposal remains 5,326 times above its movement limit.
   [#358](https://github.com/avalonalex/senbazuru/issues/358)
   [inspects that saved refusal](notes/body-contact-55-93.md): vertex 30 crosses
   plane 93's threshold while the six overlap gaps remain within tolerance.
   Their derivatives accurately predict the worsening gaps; hypothetical
   guards would constrain both 1/64 and the currently passing 1/128 direction.
   [#363](https://github.com/avalonalex/senbazuru/issues/363)
   [adds those guards in one matched direction](notes/body-fourth-pair.md):
   1/8 passes without repair, versus 1/128 in the saved control. Cost falls
   0.390833% and movement is 0.040922 drawing pixels; the full proposal remains
   5,456 times above equilibrium. Its larger 1/4 is cheaper and passes lengths
   and layer order, but crosses already-guarded 14–55.
   [#366](https://github.com/avalonalex/senbazuru/issues/366)
   [inspects those three saved shapes](notes/body-contact-14-55.md) without
   new solves. Both triangles already straddle; their intersection length grows
   from `2.75e-8` through `5.76e-8` to `1.47e-7`, crossing the `1e-7` threshold.
   Corner 0's active guard predicts no loss, but the actual gap error quadruples
   as the correction doubles. Independent derivatives agree.
   [#373](https://github.com/avalonalex/senbazuru/issues/373)
   [repairs that one gap](notes/body-overlap-restoration.md): 14–55's intersection
   falls to `2.67e-8`; actual geometry, lengths, holds and starting-cost descent
   pass. Two original 55–93 guards and one refreshed guard fail, so the repair
   stays diagnostic. Maximum movement is `1.59e-8` drawing pixels.
   **Owner direction, 2026-09-24: this is the reproducible blocker permitted
   by the first illustration deliverable. Pause the proposed joint repair and
   further pair-by-pair corrections. Next attempt the
   [bounded body barrier comparison](notes/body-barrier-comparison.md), with a
   separately bounded initialization and matching penalty control. Retain the
   original refusals, existing acceptance checks and a firm stop at a useful
   accepted pose or a documented blocker.**
   [#379](https://github.com/avalonalex/senbazuru/issues/379)
   [reaches that initialization stop](notes/body-separated-initialization.md):
   four joint corrections lower construction cost but fail separation and
   length/contact checks. The fifth direction exhausts its thirteen fractions.
   The owner-selected [#381](https://github.com/avalonalex/senbazuru/issues/381)
   [constraint-first construction](notes/body-feasible-initialization.md) stops
   at its first unverified direction after 115 iterations, retaining no new
   state. Its diagnostic proposal still lacks positive clearance and exceeds
   the length limit. [#383](https://github.com/avalonalex/senbazuru/issues/383)
   [constructs a new pose from crease angles](notes/body-crease-seed.md), with
   owner-approved new grip positions. Two angle corrections close its loops
   and preserve lengths, but contact fails at both resolutions. No body
   barrier solve has run. [#385](https://github.com/avalonalex/senbazuru/issues/385)
   [includes contact during angle construction](notes/body-angle-contact.md),
   but its first direction fails numerical verification, retaining no change.
   [#387](https://github.com/avalonalex/senbazuru/issues/387)
   [audits its saved linear equations](notes/body-angle-audit.md): the same
   selected set passes every inequality in exact arithmetic and after one
   rounding to Double. No body trial runs. The owner subsequently prioritized illustration accuracy.
   [#389's saved-pose assessment](notes/body-illustration-tolerances.md) proposes
   drawing-scale review screens while preserving strict diagnostics. Next
   compare visible layers on the recovered seed and second correction, resolving
   small depth ties under a declared allowance without moving vertices. Defer
   greater solver precision and do not repair another limiting pair.
   The existing vertex 27–plane 70 guard remains a conservative fixture policy;
   it is not automatic contact discovery.
   No opened endpoint is accepted yet, and removing the surrounding crane's
   loads makes this a specimen rather than a whole-crane deformation.
   The short compiled profile points to contact derivatives and sparse
   factorization; measure a value-only line-search evaluation under #208.
   The full coupled crane follows the small patch only after its geometry
   and visible result are accepted; measure attachment response rather than
   prescribing a photographed head/tail trajectory.
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
