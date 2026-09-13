# A flat landing order starts with the approach

Open `petal.html` after generating the study with `--petal`. Figure 1 is the
prepared flat sheet; figure 8 is the square base, a smaller square of touching
layers. The same thirteen material vertices and sixteen triangular panels
continue into both petals and the final press. No sheet is replaced at the
join, and every intermediate shape comes from crease angles.

The [symmetric collapse construction](symmetric-base-collapse.md) supplies the
angle relationship. On the bird fixture its signs are reversed: the two
south-west/north-east diagonal segments are valleys at `m`, and the four
midline rays are mountains at `-v`. Here a ray can contain two collinear crease
segments; the petal-only creases remain flat. For `0 <= m <= 180` degrees:

```text
v = 2 atan2(sqrt(2) sin(m/2), cos(m/2))
```

The south-east quarter stays in its original plane. Its material corner 1
remains at `(1, 0, 0)`, while the opposite corner 3 follows
`((1-cos(m))/2, (1+cos(m))/2, -sin(m)/sqrt(2))`. At `m = 90`, figure 4 of
`checked-petal/sequence.fold` places corner 3 at approximately
`(0.5, 0.5, -0.7071067812)` and corner 0 at
`(0.6666666667, 0, -0.4714045208)`. Both are below the stationary quarter;
an underside view reveals their motion. These are model coordinates, before
any camera projection.

The exact certificate uses `u = tan(m/4)`, which runs from 0 to 1.
Then `sin(m/2) = 2u/(1+u²)` and `cos(m/2) = (1-u²)/(1+u²)`.
Both full angles' sine and cosine become rational functions, so every material
point has a polynomial numerator over the common denominator
`D = (1+u²)² (1+6u²+u⁴)`. Its positive coefficients and constant term prove
`D > 0` throughout the closed interval. The coefficients use the same exact
`a + b*sqrt(2)` arithmetic as the [petal certificate](checked-petal.md).

For every one of the 28 material edges, the squared distance numerator equals
its original squared length times `D²`, coefficient by coefficient. Three
fixed side lengths preserve each triangle's shape and nonzero area. One path
per material vertex keeps adjacent panels joined. Polynomial sign bounds
then separate every pair of panel interiors over the whole open interval:
all 120 pairs, including neighbors. Shared edges and point contacts are
allowed. A bound that cannot establish separation refuses the route.

At the open endpoint, the panels cover the original square with no area
overlap. At the closed endpoint, 32 panel pairs overlap over an area. Each
needs an order consistent with its approach: the first nonzero coefficient
of its signed plane-height difference just before landing must point to the
specified side. Reflecting the entire collapse through the stationary plane
preserves all lengths and reaches exactly the same flat coordinates, but
fails this check. Its layers approach in the opposite order.

That landing order does not constrain the shadows of panels still in the air.
Tilted panels can overlap in projection in a different order while remaining
separated in space. During the open collapse, the static pose checker therefore
checks intersections without applying the future stack's directional orders.
The exact interval check independently proves that there is no panel-interior
contact. At landing, the certified orders become active and are retained by
the first petal. The join checks positions, angles, topology, material
coordinates and these requirements; the exported coplanar orders also agree.

Requested poses are rebuilt through `Origami.Folding`, which checks shared
vertices and achieved crease angles. Their coordinates must agree with the
ideal path within `1e-12` of the unit sheet's side, and static contact is checked
again. This closes the initial-motion gap in one known zero-thickness bird
recipe. It does not certify how the pre-creases were made, introduce physical
thickness, or discover a motion for an arbitrary pattern.
