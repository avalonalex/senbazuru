# Where a flap turns from

A flap's *root* is the line it turns from
([glossary](../glossary.md#origami)). The crane studies turn one wing about a
hinge, and the owner placed that hinge by eye at the base of the neck and the
base of the tail. Then they asked that such choices not be made model by model:
there are far too many models (owner decisions 34 and 35,
[#455](https://github.com/avalonalex/senbazuru/issues/455)). This note is the
rule that finds the root instead, and what it does on the crane.

The idea is the owner's: open the wing further in than its root and the body
can no longer hold. Stated for a folded model: a flap's hinge may crease only
the flap's own paper, and the root is the line furthest from the tip where
that is still true. Past it, the hinge would also crease the paper beside the
flap, which would then have to move with it.

**Turning alone does not find it.** Probe lines across the wing, square to
its axis, at increasing distances from its tip at folded (1, 0). Crease each
line through every layer, from the axis out to where it first leaves paper on
each side. Take the paper still joined to the tip once the crease is cut, and
turn it a quarter turn. Measured on 2026-10-02 (`examples/crane.fold`, the
tail tucked):

| Line at folded y | The crease runs across | Paper joined to the tip | Turns 90°? |
| --- | --- | --- | --- |
| 0.05 – 0.30 | the wing, to its edges | 4 faces | yes |
| 0.35 – 0.3758 | the wing, to its edges: x 0.8758–1.1242 at 0.3758 | 8 faces (the 4 triangles folded inside it join) | yes |
| 0.376 – 0.40 | the wing, the neck and the tail: x 0.7998–1.2002 at 0.376 | the same 8 | yes |
| 0.42, 0.45 | the wing, the neck and the tail | the same 8 | no: the layer order contradicts the motion |

The crease stops staying in the wing between 0.3758 and 0.376, but the wing
turns up to 0.40. To a rigid model, a crease through paper that stays put is a
flat crease, and costs nothing. So the rule has to say what "the body can no
longer hold" means: the hinge creases only the flap's own paper.

**The rule as computed.** Take the run of paper across the flap at some
distance from its tip. Each end of the run moves continuously along the
flap's edge until the line passes a corner where that edge meets the paper
beside it. There the end jumps out into that paper: at the wing, from x
1.1242 to 1.2002. So step lines inwards from the tip, square to the line from
the tip to the middle of the model, every 1/400 of the model's span. On each
side, bisect each step down to a hair to see whether the end jumped within it,
and stop at the first that did. A continuous edge changes the end by less and
less as the step narrows, and a jump does not.

The root joins the two points just before the jumps. Its direction comes from
those corners, not from the lines probed. For the wing, the tip-to-middle axis
is about 5° off square to the wing, and both ends still land at y = 0.375849.
The root is kept only if the flap then turns about it: crease it through
every layer, take the paper joined to the tip, and turn it either way.

Each flap is named by the corner of the flat sheet at its tip. The folded tip
alone would not say which flap: both wings end at folded (1, 0).

| Sheet corner | Flap | Root | Turns about it |
| --- | --- | --- | --- |
| (0, 1) and (1, 0) | a wing | (0.87585, 0.375849) to (1.12415, 0.375849), the neck and tail bases | yes, 90°, the wing's 8 faces |
| (0, 0) | the neck | (1.12415, 0.375849) to (0.72284, 0.26152) | no: 64 faces stay joined to the tip, and the sweep refuses |
| (1, 1) | the tail | none: its edge never meets other paper | — |

The wing's root is the line the owner chose by eye, y = 0.376, to three
decimals. An independent union of the faces' shadows finds the same two
reflex corners in the folded outline, to 1e-9. In two runs, searching the
tail's edge in full, which finds nothing, took 0.35 and 0.36 CPU seconds, and
finding a wing's root and checking the turn took 8.2 to 8.4, most of it
folding and solving the layer order again.

**Where it stops.** The neck and the tail are reverse-folded: they leave the
body between its layers. On one side the neck's edge meets the same visible
corner as the wing's. On the other it runs inside the body, where the outline
shows nothing, so the rule's second end lands on the head and the turn check
refuses it. The tail's edge never meets visible paper at all. So the rule finds
roots that show in the outline, and refuses, rather than guesses, roots hidden
between layers. Finding those needs the outline of the flap's own layers
against their neighbours in the stack, not the model's outline.

The rule also reads every jump as the flap's edge meeting other paper. A
flap whose own outline steps outward, or a sideways protrusion ending, makes
the run's end jump too, and the rule would put the root at that step, nearer
the tip than the real one. The turn check would not catch that, since the
crease stays in the flap's own paper. It has been tried on one model.

```bash
stack run senbazuru-material-study -- --flap-root build/fold-material
```

`flap-root/checks.json` holds each corner's root and turn, and the wing scan
above. `CraneWing.wingRoot` gives the crane studies their hinge from this
rule, so no gallery types it in. (Some tests still build wings at an explicit
0.376, to test the wing's construction at a given line.)
