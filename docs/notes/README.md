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
| [paper-thickness.md](paper-thickness.md) | A depth buffer cannot draw coincident layers; lift each by its layer number, and give every face its own corners |
| [huzita-hatori.md](huzita-hatori.md) | Paper folding is strictly stronger than straightedge and compass |
| [no-sequence-solver.md](no-sequence-solver.md) | Nobody can turn a crease pattern into folding instructions, and why |
| [two-bends-need-more-than-radii.md](two-bends-need-more-than-radii.md) | A single rounded fold preserves material, but composing two perpendicular bends can stretch the outer layer by 200%; an executable counterexample |
| [sharp-creases-and-opening-panels.md](sharp-creases-and-opening-panels.md) | A sharp crease can join nonparallel panels; prescribed openings still need material-length checks |
| [restoring-material-lengths.md](restoring-material-lengths.md) | Correct lengths alone let layers cross; a coupled length and packet-order correction meets both numerical targets |
| [connected-paper-surface.md](connected-paper-surface.md) | One material surface can support sharp folds and later bending; thickness, display offsets and the controls that open a pocket have separate roles |
| [panel-contact-and-order.md](panel-contact-and-order.md) | Rigid panels need separate crossing and order checks; upright flaps and shared crease contact need both |
| [a-crease-is-a-hinge.md](a-crease-is-a-hinge.md) | A crease is a torsional hinge with a rest angle set by the material and a radius set by what it wraps, and the two numbers a renderer needs are those |
| [the-puff-is-a-drawing.md](the-puff-is-a-drawing.md) | The earlier schematic-puff proposal: a bump can illustrate a body while stretching its material; controlled pocket opening is now a separate future goal |

## Files and formats

| Note | Idea |
| --- | --- |
| [cp-and-opx.md](cp-and-opx.md) | The two formats crease patterns are actually shared in are one format twice: a flat list of coloured segments, with the vertices left out |
| [round-trips.md](round-trips.md) | A decode/encode round trip only tests the parts the decoder kept, so keep the parts you do not understand |

## Haskell

| Note | Idea |
| --- | --- |
| [phantom-units.md](phantom-units.md) | Turning the model-units/page-units rule from a comment into a type error |
| [envelopes.md](envelopes.md) | A support function beats a bounding box for laying out a step sequence |
| [shrinking.md](shrinking.md) | A property test is only as useful as its counterexample is small |
| [folds.md](folds.md) | `foldl` builds a tower, `foldl'` flattens it, `foldr` produces lazily |
| [strict-fields.md](strict-fields.md) | `foldl'` forces only to WHNF, so lazy fields leak anyway — measured |

## Material mesh

| Note | Idea |
| --- | --- |
| [depth-ties-at-contact.md](depth-ties-at-contact.md) | Touching zero-thickness layers need an explicit display convention when depth precision runs out |
| [sharing-material-vertices.md](sharing-material-vertices.md) | Shared material vertices keep creases connected; separate panel normals keep them sharp |

## Where to start

[maekawa.md](maekawa.md) and [kawasaki.md](kawasaki.md) are built:
`senbazuru check` applies both. Read those two first, then
[big-little-big.md](big-little-big.md), which is the condition they miss and the
smallest thing left to add to the checker.
