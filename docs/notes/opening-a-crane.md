# Opening the wings also opens the body

A traditional paper crane can be stored as a flat [packet](../glossary.md)
and then shaped into a three-dimensional bird. The material experiment needs to reproduce that
change, rather than match one attractive silhouette. The references below
were checked on 2026-09-14. Their photographs and diagrams stay on the authors'
sites; no third-party artwork is copied into our fixtures.

[Stacie Tamaki's photographed tutorial](https://tinygami.wordpress.com/2016/02/10/how-to-open-an-origami-crane/)
is particularly useful because it shows the underside as well as the finished
bird. She supports each wing near the body while pulling down and outward.
The central body becomes pillow-shaped. Shaping the underside into an X gives
the opened bird a stable base; the wings can then be smoothed separately.
The photographs show a rounded centre alongside still-visible fold lines.
They do not support making every root line disappear.

[Rachel Katz's crane instructions, diagrammed by Katrin and Yuri Shumakov](https://origamiwithrachelkatz.oriland.com/folding/crane.php)
also connect spreading the wings with rounding the body.
[Bridget Spitznagel's instructions](https://www.cs.cmu.edu/~sprite/Origami/crane_gif.html)
adjust the neck and tail before opening the wings and describe blowing through
the underside as an alternative when pulling alone does not open the body.
These are folding references, not measured force or motion data. They show
that a prescribed air pressure is not required for every opening, but do not
tell us the pressure, strain or contact forces during one.

Our interpretation is that the next crane study must couple wing movement to
body opening. A pocket means a space between separated layers, not an added
solid. Its walls and the bases of the neck and tail belong to the same sheet.
Moving those attachment regions can move a sharply folded neck or tail even
without changing the folds inside it. The references do not establish a
particular automatic head or tail trajectory: direct hand shaping is another
possible cause of the final pose. We should measure that response, not prescribe
it from a photograph. Nor should we infer that pulling the tail must flap this
crane's wings; that would require checking the particular model and movement.

This also changes how to interpret [the held-root study](wing-root-holds.md).
It fixes most body vertices and accepts original mountain/valley angles only
within `1e-5` radians of their previous values. A mountain or valley identifies
the direction of a material fold; it is not a command to remain closed forever
(see the [glossary](../glossary.md)). Releasing four neighbouring body panels
while retaining that angle gate is a constrained control, not a general test
of whether a real crane can open. Keep its failure as evidence about those
constraints. A new experiment must explicitly name which body folds may change
angle, which remain controlled, and which positions are held.

There is a physical reason to retain both crease rotation and bending between
creases. [Lechenault, Thiria and Adda-Bedia (2014)](https://arxiv.org/abs/1404.1243)
study sheets with parallel creases and find that the balance between crease
and panel stiffness determines how much a small imposed opening uses each.
That supports the distinction between our line spring and ordinary uncreased
material; it does not supply calibrated properties for a paper crane.
[Jules, Lechenault and Adda-Bedia (2020)](https://arxiv.org/abs/2004.11825)
also measure changes in crease rest angles and time-dependent relaxation.
A rest angle is the angle a crease prefers without an applied turning force.
Consequently, the folds' previous treatment matters when comparing a simulation
to a real sheet; one photograph cannot identify all the material parameters.

A bounded follow-up under [#195](https://github.com/avalonalex/senbazuru/issues/195)
and [#106](https://github.com/avalonalex/senbazuru/issues/106) should begin by
mapping the body pocket and the material connections to both wings, neck and
tail. Resolve the failed body trial and compare the authored root spring with
ordinary uncreased bending before a larger solve. Then use two small wing grips,
leave the pocket walls and neck/tail attachments free, and constrain only enough
additional motion to keep the whole crane from translating or rotating away.
The grip locations are part of the experiment: the observed near-root hand
support and our existing tip strips are different boundary conditions.

A useful physical reference would record the same crane at several opening
amounts from the top, side and underside, with paper size, grip locations and
any deliberate head/tail adjustments noted. That would separate the response
to wing pulling from subsequent hand shaping. The published photographs guide
this protocol; they are not a three-dimensional reconstruction dataset.

Compare a few increasing grip separations, using each accepted result as the
next initial guess. Measure wing curvature, body height and width, underside
opening, neck/tail directions, original material lengths and shared vertices,
achieved crease angles, contact and retained layer relations. Allow touching
layers to separate while refusing crossings; do not enforce a fixed viewing-axis
height order where the surface has turned away from that direction. Repeat a
successful case at a finer mesh. These are proposed measurements, not results
already obtained, and separate checked endpoints still do not certify the
motion between them.

Start with mechanical pulling. Adding pressure later needs a stated pocket
boundary and load model: this sheet has an opening underneath, so it is not
automatically a sealed balloon with conserved volume. Simply raising body
vertices or smoothing the rendering would bypass the material question.
