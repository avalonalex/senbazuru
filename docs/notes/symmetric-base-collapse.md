# Six meeting creases can share one collapse parameter

Choose **Square base** or **Waterbomb base** in the material-study viewer,
then **Collapse · mountains −90°**. The four valleys are at +109.471220634°,
not +90°. Equal angles would leave neighbouring faces disagreeing along shared
edges.
Mountain and valley directions are defined in the [glossary](../glossary.md).

Both patterns have two opposite mountains and four valleys; two additional
guide segments stay flat. Their active crease directions differ by a 45° turn
relative to the square border, so the same angular relationship works for
both, while their final outlines differ. The relationship depends on the angles
between creases, rather than where the border cuts them. See
[pre-creases and target states](precreases-and-target-states.md).

We choose a symmetric motion: the two mountain angles are equal, as are the
four valley angles. This is one path through the possible shapes, not a claim
that the creases can only move this way. The broader use of symmetry to reduce
the number of independent angles is studied by Chen et al. in
[Symmetric Waterbomb Origami](https://researchportal.northumbria.ac.uk/files/30829244/RSPA_R1.pdf)
(2016). The coordinate construction below is ours; it selects the inward
collapse of these two traditional fixtures.

Let `m` be the positive magnitude of the mountain angle, from 0° to 180°.
The mountains use `−m`. Write `t = m/2`, `s = sin t`, and `c = cos t`.
To derive the relation, put the waterbomb's centre at the origin and allow the
whole model to turn, instead of holding the viewer's reference face still.
The four corners can then sit at `(±½, ±c/2, s/2)`. The signs of the first two
coordinates vary independently. Each of the broad north and south panels
stays rigid: its two corner rays still meet at 90° and keep their lengths.

The right edge midpoint has coordinates `(x/2, 0, z/2)`. Its distance from the
centre stays ½, so `x² + z² = 1`. Its ray still meets each neighbouring corner
ray at 45°, so their dot product gives `x + z s = 1`. Solving these two
equations and choosing the solution that moves inwards gives
`x = c²/(1+s²)` and `z = 2s/(1+s²)`. The left midpoint mirrors its x coordinate;
the north and south midpoints lie halfway between their neighbouring corners.
All eight triangles therefore retain their original edge lengths. Measuring
the angle between neighbouring triangle normals gives:

```text
mountain = −m
valley   = 2 atan2(√2 sin(m/2), cos(m/2))
flat guide = 0
```

Trigonometric functions in Haskell use radians. This expression, also used in
`BaseCollapseSpec`, returns degrees and stays well behaved at `m = 180`:

```haskell
let valley m = 360 / pi * atan2 (sqrt 2 * sin (m * pi / 360)) (cos (m * pi / 360))
map valley [0, 30, 60, 90, 120, 150, 175, 180]
```

For those eight magnitudes, the valley angles rounded for reading are 0°, 41.507142°,
78.463041°, 109.471221°, 135.584691°, 158.542834°, 176.463344° and 180°.
The manifest stores the first seven at full precision. It keeps the explicit angle-list
format; it does not add a new motion format. The viewer stops at mountain
−175° so the layers remain visible, while the tests include the closed endpoint.

`BaseCollapseSpec` checks independently predicted distances: the waterbomb's
two right corners approach with separation `c`, and its left and right edge
midpoints with separation `c²/(1+s²)`. It checks both bases at random angles
and every integer mountain magnitude from 0° through 180°. Every sampled state
passes the folding engine's shared-vertex and crease-angle checks and the
28 panel-pair contact checks. Uniformly halving the final angles, or perturbing
just one active crease by 1°, is rejected. Run `stack test --ta='--match BaseCollapse'`.

The panel orders come from each fixture's closed flat stacking. Six declared
neighbour relations form two chains of four triangles; each triangle is named
by a point inside it on the original sheet. Orders are measured along the
fixed face's +z direction, independently of the camera. Sampling a path is
not continuous collision certification, and the selected symmetry does not
predict bending, finite thickness, or how real paper settles when released.
