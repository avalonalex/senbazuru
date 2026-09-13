# Three moving vertices can describe a whole petal

The [first bird petal](petal-fold-motion.md) starts with the square base and
lifts one tip while folding both sides inward. Seven crease angles change,
but only three of the thirteen material vertices move. That makes this a
small example of checking a motion involving several creases together.
The eleven stationary panels retain their layer order; the five moving
panels must separate from them and from each other throughout the fold.

In the earlier derivation, the tip hinge turns by `t`, while the side folds
turn by `s`, where `tan(s/2) = sin(22.5°)*tan(t/2)`. At `t = 90°`, the tip is
`(0.6464466094067263, 0.3535533905932738, 0.5)` and one shoulder is
`(0.5187070285094433, 0.04516276193919817, 0.12773958089728293)`.
These are values from `PetalCertificate.petalPoints 90`, checked against the
angle-derived folding engine. The shoulder does not turn at the tip's speed.

To bound the whole motion, replace the angle with
`u = tan(t/2)/(1 + tan(t/2))`. It runs from zero to one, including the flat
landing. Put `k² = (2-sqrt(2))/4`. The moving coordinates become ratios of
polynomials in `u`: sums of constant multiples of `1, u, u², ...`.
All coordinates can share the denominator
`D = ((1-u)²+u²) * ((1-u)²+k²*u²)`, which is positive everywhere on `[0,1]`.
For example, the tip's height is `u*(1-u)/((1-u)²+u²)`, and a shoulder's
height is `k²*u*(1-u)/((1-u)²+k²*u²)`.
Multiplying by `D` therefore never changes which side of a plane a point is on.

The coefficients have the form `a + b*sqrt(2)`, with rational `a` and `b`.
The certificate stores those two rational numbers separately. Products stay
in that form because `sqrt(2)² = 2`; comparing signs uses rational squares
when the two terms have opposite signs. This preserves exact zeros at shared
vertices and planes instead of asking a tolerance to distinguish a seam from
a tiny penetration. The source FOLD coordinates remain ordinary rounded numbers.

For each pair involving moving paper, the checker tries separating planes
through either triangle or through one of its edges. Signed distances, after
clearing positive denominators, are polynomials. In the **Bernstein basis**,
a polynomial's value on `[0,1]` is a weighted average of its coefficients.
Nonnegative coefficients establish nonnegative values everywhere; one positive
coefficient establishes strict positivity throughout `(0,1)`. If one triangle
lies on one side and the other's interior lies strictly on the other, their
interiors cannot intersect. Touching edges and corners remain allowed.
Every one of the 65 pairs involving moving panels passes on the whole interval;
the other 55 pairs stay geometrically unchanged. A failed bound is unresolved,
not permission to fall back to samples.

Flat endpoints need another check because strict separation may disappear
there. Exact polygon clipping finds every overlapping pair and a point inside
its overlap. The first nonzero coefficient of the difference between the two
panels' heights near that endpoint determines the approach or departure order.
The required lower/upper relation must agree. This checks 71 pairs across the
two endpoints, including stationary contacts. Reflecting the motion below the
packet preserves all material lengths but fails its departure order.

Squared edge-length identities are checked as polynomials too: all 28 edges
retain their material lengths for every `u`. Each triangle starts with nonzero
area, so its three fixed edge lengths keep it rigid and nondegenerate. One
trajectory per material vertex keeps neighbouring triangles joined.
`CheckedPetal` accepts only the fixture's material coordinates, cut topology,
edge ids and stationary anchor. Every requested pose is rebuilt from crease
angles, so the folding engine still checks shared vertices and achieved angles.
Its coordinates must agree with the certified ideal path within `1e-12` of
the unit sheet, and its contact report must pass. The exact result concerns
the ideal path; that tolerance is a comparison with floating-point output,
not a physical clearance guarantee.

Run `stack run senbazuru-material-study -- --petal build/fold-material` for
eight illustrations and their FOLD/glTF exports. This is one known route for
zero-thickness paper. The square-base collapse, the second petal and general
motion discovery remain separate work. The next useful extension is to check
the second petal and their final pressing, retaining the first petal's accepted
geometry and layer order.
