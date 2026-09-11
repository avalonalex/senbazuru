# Four linked creases gather one rabbit ear

Choose **Rabbit-ear fold** in the material-study viewer, then **Gather the
flap · mountain −30°**. The south-east corner rises and turns towards the
north-east corner while the opposite half stays flat. A rabbit ear gathers
a triangular region into a pointed flap; two of them make our fish base.
Mountain and valley directions are defined in the [glossary](../glossary.md).

The [fish fixture](../../examples/fish-base.fold) is a unit square. Label its
corners `A = (0,0)`, `B = (1,0)`, `C = (1,1)` and `D = (0,1)`, in that order.
The first ear's four creases meet at `P = (d,r)`, where `d = 1/√2` and
`r = 1−d`. They run to A, B, C and the east-edge point `E = (1,r)`.
The diagonal AC and everything on D's side remain flat. See the
[endpoint construction](fish-and-bird-endpoints.md) for where P comes from.

Walking counterclockwise around P, the rays PB, PE, PC and PA enclose angles
45°, 67.5°, 135° and 112.5°. These are angles **on the original sheet**,
distinct from the angles through which the creases fold. Their alternating sums are
180°, which permits the four panels to fold flat locally. Our selected
motion bends PB as a mountain and the other three as valleys.

Let `m` be the mountain's positive magnitude. PB takes angle `−m` and PC
takes `+m`; PA and PE share another angle `v`. The relation is a special
case of Theorem 1, equation (2), in Foschi, Hull and Ku's
[Explicit kinematic equations for degree-4 rigid origami vertices](https://arxiv.org/html/2206.12691)
(2022). Their four fold angles map to `(PB, PE, PC, PA) = (−m, v, m, v)`;
their first two angles on the sheet are 45° and 67.5°. Substitution gives:

```text
tan(−m/2) = sin((45°−67.5°)/2) / sin((45°+67.5°)/2) · tan(v/2)
tan(m/2)  = sin(11.25°) / sin(56.25°) · tan(v/2)
```

The minus signs cancel; dropping only one would turn the wrong crease into
a mountain. Solving for v using `atan2` avoids dividing by a value that
vanishes at the closed endpoint. This Haskell expression takes and returns
degrees; the trigonometric functions themselves take radians:

```haskell
let valley m = 360 / pi * atan2 (sin (5*pi/16) * sin (m*pi/360)) (sin (pi/16) * cos (m*pi/360))
map valley [0, 15, 30, 60, 90, 120, 150, 175, 180]
```

The manifest records the first eight results. Some representative values,
rounded here, are:

| Mountain PB | Valley PC | Valleys PA and PE |
| --- | --- | --- |
| −15° | +15° | +58.593508° |
| −30° | +30° | +97.585148° |
| −90° | +90° | +153.590740° |
| −175° | +175° | +178.826130° |
| −180° | +180° | +180° |

The faster valleys lay the ear over while it rises. There is no separate
rigid phase in which this ear is first lifted straight up and only then
turned. Uniformly scaling all four final angles does not give this motion;
the folding engine rejects that shortcut. Positions come from the production
folding code, which checks shared vertices and achieved crease angles.

Two material points provide an independent check on the shape. Holding APC
still, E rotates around PC through m, while B rotates around AP through v.
With `c = cos 22.5°` and `s = sin 22.5°`, those rotations give:

```text
B = (c² + s² cos v, c s (1−cos v), s sin v)
E = (¾ + ¼ cos m, r + (√2−1)/4 · (1−cos m), r c sin m)
```

At `m = 90°`, E is `(0.75, 0.396447, 0.270598)` and B is
`(0.722390, 0.670210, 0.170210)`. At closure, E reaches `(½,½,0)` and B
reaches `(d,d,0)`. `RabbitEarSpec` checks these rotations against the computed
mesh, including the stationary half's subdivision vertices.

Layer order needs more care than the angle formula. During the turn, all
three moving panels remain above the fixed APC panel along +z, but their
order relative to **each other** changes wherever their vertical projections
overlap. Imposing the final stack during this motion reports reversed orders
even when no panels cross. The case therefore declares only those three
stable relations. At exact closure they leave three overlapping pairs
unresolved. The endpoint test supplies the full chain
`centre-south < south-panel < ear-tip < east-panel` and checks it against the
unique flat stacking; it also verifies that leaving those orders out fails.

Run `stack test --ta='--match rabbit-ear'`. Besides the eight displayed states,
tests cover random angles and mesh refinements, a half-degree sweep, both
upright-panel configurations, and the exact closed endpoint. All 28 panel
pairs are checked in each sampled pose. This establishes sampled geometry
and contact, not continuous collision freedom or finite paper thickness.
The gallery stops at mountain −175° to leave its layers visibly separated;
the second ear and the bird's petal-fold motion remain future work.
