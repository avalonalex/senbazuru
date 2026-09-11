# A petal lifts its tip while two old folds open

A **petal fold** lifts a flap of the square base and folds its sides inward,
making a longer, narrower flap. Two petal folds form the bird base. This study
moves only the first, leaving the second and the underlying packet still.
The [endpoint construction](fish-and-bird-endpoints.md) explains the original
material coordinates; the [glossary](../glossary.md) covers the fold vocabulary.

Start with `bird-base.fold`, but set its angles to a collapsed square base.
Its signs put the south-east (SE) flap on top of the packet. Its four original
corners then meet at `(1,0,0)` in our chosen reference plane.
The sheet's centre is `(0.5,0.5,0)`. The first petal hinge joins
`P = (0.5,0.2071067811865475,0)` and
`Q = (0.7928932188134525,0.5,0)`; these points stay still throughout.
The corner originally at SE is the moving tip B. These are model coordinates,
not coordinates fitted to a picture.

Let `t` be the hinge angle in degrees, from 0 to 180. With `d = 1/sqrt(2)`,
the hinge midpoint is `H = (1-d/2,d/2,0)`. B describes a circle of radius 1/2
around PQ:

```
B(t) = H + (d*cos(t)/2, -d*cos(t)/2, sin(t)/2)
B(0)   = (1,                  0,                  0)
B(90)  = (0.6464466094067263, 0.3535533905932737, 0.5)
B(180) = (0.2928932188134525, 0.7071067811865475, 0)
```

`PetalFoldSpec` checks these positions against the folding engine. They are
independent of the angle relationship used to close the side folds.

The side folds cannot simply turn by t. Look at the original bottom-edge
midpoint W. In the square base it is `(0.5,0,0)`. It rotates around the fixed
line from A = `(1,0,0)` to P, while both boundary edges AW and WB must retain
length 1/2. If s is that side rotation, put `c = cos(22.5°)` and
`k = sin(22.5°)`. Rotation around AP gives:

```
W(s) = (1 - c*c/2 - k*k*cos(s)/2,
        c*k*(1-cos(s))/2,
        k*sin(s)/2)
```

Substituting B and W into `|W-B|² = 1/4` reduces to
`sin(t)*sin(s) = k*(1-cos(t))*(1+cos(s))`.
The branch that starts with W still at `(0.5,0,0)` therefore satisfies
`tan(s/2) = sin(22.5°)*tan(t/2)`. The implementation uses `atan2` so it is
also defined at t = 180. At t = 90, s is about 41.882°: uniformly interpolating
all final angles would instead ask for 90° and tear the sheet.

In the source's edge order, the four side creases 12, 13, 16 and 17 have angle
`-s`; hinge 26 has `+t`. The two outer midline segments 11 and 15 have angle
`t-180`: they **open from -180 to zero**. The remaining entries stay at their
square-base values, including eight segments at signed 180° angles. The second petal hinge stays at zero.
All sixteen triangular panels keep their edge lengths, and neighbouring panels
agree on their shared vertices and crease angles. At 180°, only SE has reached
the opposite tip; the other three original corners still meet at `(1,0,0)`.

The moving tip triangle is the largest panel, so the gallery's usual choice
of holding the largest panel still would move the base around it. The optional
`fixedPanel: [0.58,0.4]` instead selects a point strictly inside the stationary
triangle beside the hinge. It identifies original material, surviving face
renumbering. It changes only the reference frame, not the fold.

The flat body retains overlapping panels throughout. Nineteen declared
lower/upper relations cover the union of the square and one-petal endpoint
orders, with redundant relations removed. Each endpoint agrees with the unique
stacking found by the production solver. All 120 panel pairs also pass contact
and order checks at every half degree from 0 through 180, and at random angles
and mesh refinements. Removing orders exposes unresolved overlaps; folding the
petal below the packet fails its required order. Geometry alone cannot choose
which of two coincident zero-thickness panels is on top.

For display, validated orders break depth ties along the declared direction.
The exactly coincident packet needs a wider numerical guard than the relaxed
double fold: the old 128 depth-units factor still left patches at the default
90° petal view; 1024 removed them in the inspected views. Feature lines carry
their incident panels' levels too, so buried creases do not shine through. Looking underneath reverses those depth ties. Positions in the
OBJ/FOLD exports and material measurements are unchanged; failing contact
reports disable the adjustment. The eight gallery states end at 175° for
inspection. These are sampled rigid states, not a continuous collision proof,
a thickness model, or the second petal's motion.
