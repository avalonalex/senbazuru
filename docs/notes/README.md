# Notes

Short notes on ideas worth knowing for this project. **One idea per file**, each
a few minutes to read, each with references if you want to go deeper.

These are background and direction, not documentation of the code. For the code,
read the Haddock module headers; for the domain, start with
[../fold-primer.md](../fold-primer.md); for any term you do not recognise, see
[../glossary.md](../glossary.md).

## Origami and geometry

| Note | Idea |
| --- | --- |
| [maekawa.md](maekawa.md) | At a flat-foldable vertex, mountains minus valleys is always ±2 |
| [kawasaki.md](kawasaki.md) | Alternating angles decide single-vertex flat-foldability exactly |
| [kawasaki-without-trig.md](kawasaki-without-trig.md) | The alternating sum is a product of complex numbers, so it can be tested exactly |
| [big-little-big.md](big-little-big.md) | A sector smaller than both its neighbours forces one mountain and one valley |
| [flat-foldability-is-hard.md](flat-foldability-is-hard.md) | One vertex is linear time; the whole sheet is NP-hard |
| [robust-predicates.md](robust-predicates.md) | Why `Double` gets the left-of-line test *wrong*, not just imprecise |
| [convex-hull.md](convex-hull.md) | Andrew's monotone chain, in four steps |
| [half-edge.md](half-edge.md) | The structure FOLD's array format is already shaped for |
| [folding-by-transforms.md](folding-by-transforms.md) | How angles become positions: one rigid matrix per face, over a spanning tree |
| [fold-angles-are-the-state.md](fold-angles-are-the-state.md) | Positions are derived from angles, and neither can be naively interpolated |
| [precreases-and-target-states.md](precreases-and-target-states.md) | Square and waterbomb bases share eight guide segments, but only six bend in each chosen collapsed state |
| [symmetric-base-collapse.md](symmetric-base-collapse.md) | A symmetric square/waterbomb collapse links four valley angles to two mountain angles without stretching the sheet |
| [fish-and-bird-endpoints.md](fish-and-bird-endpoints.md) | A fish's rabbit ears and a bird's lifted petals need explicit endpoint creases; a valid flat packet alone does not identify the intended base |
| [six-more-base-endpoints.md](six-more-base-endpoints.md) | Boat and pig have the same silhouette but different material landmarks; six traditional endpoints exercise folds through layers and four petals |
| [rabbit-ear-motion.md](rabbit-ear-motion.md) | Four linked crease angles gather one fish-base flap; its moving panels need different order requirements from the closed stack |
| [petal-fold-motion.md](petal-fold-motion.md) | A bird-base petal lifts its tip while four side creases close and two old folds open; the flat body retains its layer order |
| [two-petals.md](two-petals.md) | The two bird-base petals move on opposite sides of a stationary packet and close into the verified endpoint |
| [projected-panel-visibility.md](projected-panel-visibility.md) | Compare open panels over their projected overlaps, then reuse flat visible regions to hide paper and creases |
| [two-rabbit-ears.md](two-rabbit-ears.md) | The fish's ears can fold in sequence while staying on opposite sides of the diagonal; each closes into its own layer chain |
| [creasing-through-layers.md](creasing-through-layers.md) | Creasing a packet of layers alternates mountain and valley, because alternate layers are upside down |
| [layer-ordering.md](layer-ordering.md) | Why drawing a folded model is hard and a crease pattern isn't |
| [taco-taco.md](taco-taco.md) | Every constraint on the layer order is one of four local rules |
| [several-stackings.md](several-stackings.md) | A model usually has many valid layer orders, and counting them is a product over independent components |
| [convex-clipping.md](convex-clipping.md) | Test whether two faces overlap by clipping them, not with predicates |
| [visible-regions.md](visible-regions.md) | Draw a folded model by subtracting the layers over each face, not by painting faces in order |
| [layer-numbers.md](layer-numbers.md) | Which sheet of the stack a face is in is the longest chain below it, not a count of what it covers |
| [paper-thickness.md](paper-thickness.md) | Why independent layer lifting opened crease gaps and was replaced |
| [huzita-hatori.md](huzita-hatori.md) | Paper folding is strictly stronger than straightedge and compass |
| [no-sequence-solver.md](no-sequence-solver.md) | Nobody can turn a crease pattern into folding instructions, and why |
| [two-bends-need-more-than-radii.md](two-bends-need-more-than-radii.md) | A single rounded fold preserves material, but composing two perpendicular bends can stretch the outer layer by 200%; an executable counterexample |
| [sharp-creases-and-opening-panels.md](sharp-creases-and-opening-panels.md) | A sharp crease can join nonparallel panels; prescribed openings still need material-length checks |
| [restoring-material-lengths.md](restoring-material-lengths.md) | Correct lengths alone let layers cross; a coupled length and packet-order correction meets both numerical targets |
| [crease-identity-through-refinement.md](crease-identity-through-refinement.md) | Source crease ids survive subdivision; current fold angles and preferred rest angles are separate inputs |
| [first-contact-history.md](first-contact-history.md) | Learn a new panel order during a sampled approach, then retain it through separation and correction |
| [hinge-sweep-contact.md](hinge-sweep-contact.md) | Check a specified rigid flap rotation between poses; valid endpoints can conceal an interior crossing |
| [checked-flap-operation.md](checked-flap-operation.md) | Check a whole turn before a library flap operation supplies angle-derived surfaces to SVG and glTF |
| [flat-flap-endpoints.md](flat-flap-endpoints.md) | A one-sided approach permits endpoint contact and records which layer rests on which |
| [moving-touching-layers.md](moving-touching-layers.md) | Touching layers with the same rigid motion retain their order, while other pairs still need a collision check |
| [checked-petal.md](checked-petal.md) | Exact polynomial signs check seven coordinated crease angles throughout one bird petal |
| [checked-bird-base.md](checked-bird-base.md) | The stationary base plane separates opposite petals; exact checks carry their material and layer order through the final press |
| [checked-square-collapse.md](checked-square-collapse.md) | Exact checks carry the prepared open sheet into the square base and verify its landing order before either petal opens |
| [chaining-checked-folds.md](chaining-checked-folds.md) | Carry angles, orders and a consistent anchor between the five checked turns of a blintz sequence |
| [aligned-crease-hinges.md](aligned-crease-hinges.md) | One physical hinge can join several graph segments or distinct material creases on touching layers; their angle signs follow their stationary faces |
| [turning-towards-a-side.md](turning-towards-a-side.md) | A turn towards +z or −z is read from the moving face beside each hinge crease; the face held still answers the other way on a hinge folded shut, and made a page turn depend on which crease came first |
| [A wing resting on paper](a-wing-resting-on-paper.md) | A crease can keep touching another layer while the wing leaves its plane; departure must still match the starting order. |
| [free-edges-on-a-hinge.md](free-edges-on-a-hinge.md) | A declared stack can support its free edge on a shared hinge without welding the material vertices |
| [endpoints-and-routes.md](endpoints-and-routes.md) | A valid state, a checked route and the existence of some route are different questions |
| [checking-numerical-corrections.md](checking-numerical-corrections.md) | Bound contact throughout numerical vertex corrections, and expose a solver that stalls when unsafe shortcuts are refused |
| [rejected-bending-trials.md](rejected-bending-trials.md) | Distinguish energy, history and motion refusals; stop identical failed searches and expose a discontinuous layer penalty |
| [directional-contact-distance.md](directional-contact-distance.md) | Resist a retained layer reversal before projected overlap, restoring the closing strip's material lengths with every accepted path checked |
| [growing-local-contact-history.md](growing-local-contact-history.md) | Learn new triangle partners at accepted separated poses while retaining earlier contact orders |
| [local-contact-discovery.md](local-contact-discovery.md) | Discover nearby material triangles within bending paper and retain their reference order across flat patches |
| [local-panel-contact.md](local-panel-contact.md) | Keep two regions of one bending panel apart using local triangle requirements and a curled-strip control |
| [reference-contact-discovery.md](reference-contact-discovery.md) | A separated reference pose supplies contact order; later overlaps must respect that fixed history |
| [ordered-flap-contact.md](ordered-flap-contact.md) | Declared panel order stops opposing flaps from crossing; moving overlap corners need derivatives too |
| [crease-and-panel-energy.md](crease-and-panel-energy.md) | Crease preferences and panel bending select among connected shapes; stiffer panels can miss their crease targets by more |
| [two-held-paper-layers.md](two-held-paper-layers.md) | One folded diamond bends as two distinct touching layers, sharing only the real root crease |
| [wing-root-holds.md](wing-root-holds.md) | Separate an exact root hold from a crease preference, and retain contact requirements through held body layers |
| [opening-a-crane.md](opening-a-crane.md) | Real crane finishing couples both wings to the body pocket; crease identities can survive while angles and neck/tail attachments move |
| [crane-pocket-map.md](crane-pocket-map.md) | The central body patch has an internal perimeter, while four separate sheet-edge landmarks meet underneath; a material map is not yet a cavity |
| [body-angle-preferences.md](body-angle-preferences.md) | Matched body-angle controls separate material preferences from endpoint acceptance. |
| [contact-correction-at-a-crease.md](contact-correction-at-a-crease.md) | Contact correction passes numerical checks while an independent exact gap retains penetration |
| [nonnegative-crease-contact.md](nonnegative-crease-contact.md) | Constrained material steps and exact repairs remove the small crease’s penetration without adding thickness |
| [coupled-crease-contact.md](coupled-crease-contact.md) | Both interiors bend beside one held crease; current triangle contacts preserve order, while symmetry and refinement limit the result |
| [fine-crease-solver.md](fine-crease-solver.md) | A stronger length penalty and a stricter near-parallel contact address different fine-mesh failures without relaxing acceptance caps |
| [two-direction-crease-refinement.md](two-direction-crease-refinement.md) | The missing 4×2 mesh retains length sensitivity; separate passive and imposed spring energies expose the competition at the control lines |
| [distributed-bend-preference.md](distributed-bend-preference.md) | A fixed material band preserves desired turn and flat-reference energy under refinement; numerical acceptance still has to be checked |
| [several-contact-exchanges.md](several-contact-exchanges.md) | Several weak contacts can require a sequence of improving replacements while all final residual limits stay unchanged |
| [fine-band-length-enforcement.md](fine-band-length-enforcement.md) | Restarting two stalled band endpoints separates more work from stronger length enforcement; converged crossing remains invalid paper |
| [combined-band-refinement.md](combined-band-refinement.md) | Repeating the full band grid with one stronger length/contact policy separates numerical acceptance from mesh convergence |
| [band-refinement-8x2.md](band-refinement-8x2.md) | Explicit shape, opening and energy targets judge the next length/width comparison separately from valid endpoints |
| [prescribed-bend-energy.md](prescribed-bend-energy.md) | Known shapes separate concentrated bends, clipped band angles and chord-length penalties without running the optimizer |
| [band-boundary-fractions.md](band-boundary-fractions.md) | Attribute the same fraction of actual and preferred turn to partial band intervals, checking both energy and derivatives |
| [fractional-band-solves.md](fractional-band-solves.md) | Compare original and fractional band turns in small coupled solves, keeping holds and numerical policy fixed |
| [fractional-band-length.md](fractional-band-length.md) | Double length subdivisions under each band rule, keeping width and solver policy fixed |
| [bending-energy-locations.md](bending-energy-locations.md) | Locate saved spring costs and the new opposite turn outside the upper bending band |
| [outer-strip-refinement.md](outer-strip-refinement.md) | Refine only the outer strip, or only the rest, to locate the source of the loaded opening |
| [matched-energy-locations.md](matched-energy-locations.md) | Interior refinement adds bending costs that outweigh reductions at shared locations; saved edge accounting separates this from the outer bend |
| [prescribed-uneven-bends.md](prescribed-uneven-bends.md) | Known bends on four uneven meshes isolate missing boundary costs and averaging at the held-strip transition |
| [prescribed-held-bend.md](prescribed-held-bend.md) | A geometric fit preserves both original grip regions and full material lengths, with mesh-dependent curve parameters and costs |
| [smooth-held-bend.md](smooth-held-bend.md) | Zero curvature at both joins still gives a larger refinement gap; compare each approximation with its own continuous cost |
| [fixed-bend-refinement.md](fixed-bend-refinement.md) | Fixed curves approach their analytic costs at different rates; length error and grip drift remain separate |
| [transition-refinement.md](transition-refinement.md) | Equal triangle budgets near curvature joins improve cost accuracy but can increase grip drift |
| [whole-bend-refinement.md](whole-bend-refinement.md) | Resolving the bend interior improves geometry, while the circle retains an angular-cost tradeoff |
| [held-panel-equilibrium.md](held-panel-equilibrium.md) | Letting the same held paper settle on uniform and whole-bend grids at two modest budgets |
| [held-bending-costs.md](held-bending-costs.md) | Refinement lowers the held-boundary cost while free-paper increases dominate the saved endpoint differences |
| [held-endpoint-confirmation.md](held-endpoint-confirmation.md) | Tightening the movement stop barely changes two held-panel endpoints; their refinement cost gaps remain |
| [held-panel-refinement.md](held-panel-refinement.md) | Comparing 256 and 512 triangles at fixed width, with the same material, grips and tighter stopping test |
| [held-layout-costs.md](held-layout-costs.md) | The equal-budget gap lies mostly in free paper; the largest length cost and worst relative error occupy different edges |
| [body-correction-replay.md](body-correction-replay.md) | Replay saved body corrections: 1/64 lowers cost and passes unchanged geometry checks without a new solve |
| [body-contact-direction.md](body-contact-direction.md) | Guard one body contact in the correction calculation; the next larger trial exposes a neighboring pair |
| [body-contact-pairs.md](body-contact-pairs.md) | Guard two contacts from the same saved shape: 1/8 becomes usable, but 1/4 exposes a third pair |
| [body-short-corrections.md](body-short-corrections.md) | Fresh guards retain ten shapes, but later fractions shrink against the same crossing boundary |
| [body-restoration-loop.md](body-restoration-loop.md) | Ten material corrections with one repair per trial, preserved refusals and unchanged geometry checks |
| [body-contact-55-93.md](body-contact-55-93.md) | Saved vertex 30 plane crossing, six overlap gaps and hypothetical guards without a new solve |
| [body-fourth-pair.md](body-fourth-pair.md) | One matched correction with six added 55–93 overlap guards and the unchanged repair policy |
| [body-overlap-restoration.md](body-overlap-restoration.md) | One overlap repair clears 14–55 but fails neighboring 55–93 guards |
| [body-barrier-comparison.md](body-barrier-comparison.md) | Pause pair-by-pair repairs; bound initialization and a matched body barrier/penalty comparison |
| [body-separated-initialization.md](body-separated-initialization.md) | A bounded joint construction tests whether the saved body can enter the contact barrier |
| [body-angle-contact.md](body-angle-contact.md) | Considering inherited layer overlaps and loop closure together during crease-angle construction |
| [body-crease-seed.md](body-crease-seed.md) | Compatible crease angles preserve lengths but can still cross inherited layers |
| [body-feasible-initialization.md](body-feasible-initialization.md) | Keep lengths within bounds while reducing the worst remaining clearance deficit |
| [body-contact-14-55.md](body-contact-14-55.md) | A saved guarded gap loses its starting floor and lengthens a tiny intersection past tolerance |
| [body-fresh-restoration.md](body-fresh-restoration.md) | Repeat one contact repair after refreshing the material direction, retaining all geometry and cost checks |
| [body-fresh-direction.md](body-fresh-direction.md) | One fresh material direction from the repaired trial, with unchanged guards and checks |
| [body-contact-restoration.md](body-contact-restoration.md) | One minimum-movement repair makes the saved 1/128 body trial pass unchanged geometry and cost checks |
| [body-plane-loss.md](body-plane-loss.md) | Relative vertex movement and plane rotation interact: about 98% of the missed distance loss at 1/128 |
| [body-plane-guard.md](body-plane-guard.md) | One moving-plane guard permits 1/256 instead of 1/32768, but finite plane motion still limits the trial |
| [body-final-contact.md](body-final-contact.md) | Vertex 27 crosses a plane threshold outside the overlap while the guarded height gap improves |
| [body-third-contact.md](body-third-contact.md) | A third pair adds no force: the linear gap prediction passes while the finite trial crosses |
| [body-geometry-continuation.md](body-geometry-continuation.md) | Continue the saved body patch with both cost and geometry gates, keeping the full-proposal convergence test |
| [body-contact-diagnosis.md](body-contact-diagnosis.md) | Locate shallow crossings in saved body-patch triangles and distinguish intersection extent from height gaps |
| [recovered-body-subdivision.md](recovered-body-subdivision.md) | Subdivide the recovered current triangles before one final-weight continuation, with full proposal and refusal evidence |
| [body-patch-checkpoints.md](body-patch-checkpoints.md) | Saved corrections expose a misordered starting guess, a coarse near-stall and a refined length/contact failure, without new solves |
| [coupled-body-patch.md](coupled-body-patch.md) | A free-boundary crane body opens with both roots, but coarse solves remain unsettled and the refined control fails geometry |
| [illustration-material-priority.md](illustration-material-priority.md) | Plausible crane illustrations take priority; defer cost convergence while retaining valid-paper checks and explicit visual review |
| [outer-strip-continuation.md](outer-strip-continuation.md) | Two exhausted endpoints settle with unchanged material and length weight; one still crosses |
| [illustration-scale-refinement.md](illustration-scale-refinement.md) | Compare saved paper at its drawing size; stable outlines can still conceal changes in tiny exposed layers |
| [thin-layer-visibility.md](thin-layer-visibility.md) | Real exposed paper and twelve sampling grids keep thin-layer changes distinct from raster artifacts |
| [exposed-layer-distance.md](exposed-layer-distance.md) | Bound filled-region distances before sampling; a tiny distant fragment can dominate the maximum |
| [exposed-area-budget.md](exposed-area-budget.md) | Bound exposed area beyond two pixels without discarding small fragments or waiving distance failures |
| [exposed-area-highlights.md](exposed-area-highlights.md) | Locate the measured contributions with actual-size highlights and unrounded 32× details |
| [band-refinement-8.md](band-refinement-8.md) | One more length doubling tests the band shape while keeping width, loading and numerical policy fixed |
| [combined-crease-refinement.md](combined-crease-refinement.md) | Repeat the length/width grid under one solver policy so numerical changes do not masquerade as mesh convergence |
| [unequal-crease-refinement.md](unequal-crease-refinement.md) | Independent length and width refinement tests contact regions as well as matching vertices; solver convergence remains a separate requirement |
| [unequal-crease-controls.md](unequal-crease-controls.md) | Unequal upper controls separate the layers or change the lower panel through contact; fixed crease-adjacent strips isolate that response |
| [near-closed-crease.md](near-closed-crease.md) | Exact strip profiles separate contact tolerances from a false triangle crossing |
| [internal-crease-diagnostic.md](internal-crease-diagnostic.md) | Holding shared crease lines improves convergence, but equilibrium, contact tolerance and valid paper remain separate checks |
| [spreading-connected-wing.md](spreading-connected-wing.md) | A held curved wing on the existing crane preserves the body, material creases and tail order |
| [coupled-touching-layer-solve.md](coupled-touching-layer-solve.md) | Coupled preconditioning resolves a fine touching-mesh stall; original residuals and refinement still judge the result |
| [held-wing-bending.md](held-wing-bending.md) | Exact root and grip controls bend an uncreased wing; a known strip and three mesh resolutions check the static solve |
| [connected-paper-surface.md](connected-paper-surface.md) | One material surface can support sharp folds and later bending; thickness, display offsets and the controls that open a pocket have separate roles |
| [panel-contact-and-order.md](panel-contact-and-order.md) | Rigid panels need separate crossing and order checks; upright flaps and shared crease contact need both |
| [a-crease-is-a-hinge.md](a-crease-is-a-hinge.md) | A crease is a torsional hinge with a rest angle set by the material and a radius set by what it wraps, and the two numbers a renderer needs are those |
| [the-puff-is-a-drawing.md](the-puff-is-a-drawing.md) | The earlier schematic-puff proposal: a bump can illustrate a body while stretching its material; controlled pocket opening is now a separate future goal |

## Files and formats

| Note | Idea |
| --- | --- |
| [cp-and-opx.md](cp-and-opx.md) | The two formats crease patterns are actually shared in are one format twice: a flat list of coloured segments, with the vertices left out |
| [closed-path-starts.md](closed-path-starts.md) | Choose a filled polygon’s first corner after formatting, so cyclic starts cannot make SVG goldens platform-dependent |
| [round-trips.md](round-trips.md) | A decode/encode round trip only tests the parts the decoder kept, so keep the parts you do not understand |

## Haskell

| Note | Idea |
| --- | --- |
| [phantom-units.md](phantom-units.md) | Turning the model-units/page-units rule from a comment into a type error |
| [envelopes.md](envelopes.md) | A support function beats a bounding box for laying out a step sequence |
| [shrinking.md](shrinking.md) | A property test is only as useful as its counterexample is small |
| [folds.md](folds.md) | `foldl` builds a tower, `foldl'` flattens it, `foldr` produces lazily |
| [strict-fields.md](strict-fields.md) | `foldl'` forces only to WHNF, so lazy fields leak anyway — measured |
| [parallel-material-tests.md](parallel-material-tests.md) | Independent solver tests can share CI CPUs while retaining every acceptance check |

## Material mesh

| Note | Idea |
| --- | --- |
| [depth-ties-at-contact.md](depth-ties-at-contact.md) | Touching zero-thickness layers need an explicit display convention when depth precision runs out |
| [visible-paper-mesh.md](visible-paper-mesh.md) | Two glTF scenes share material positions: clip buried coplanar paper for display and retain the complete sheet for inspection |
| [sharing-material-vertices.md](sharing-material-vertices.md) | Shared material vertices keep creases connected; separate panel normals keep them sharp |

## Where to start

[maekawa.md](maekawa.md) and [kawasaki.md](kawasaki.md) are built:
`senbazuru check` applies both. Read those two first, then
[big-little-big.md](big-little-big.md), which is the condition they miss and the
smallest thing left to add to the checker.
