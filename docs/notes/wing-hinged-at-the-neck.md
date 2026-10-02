# The wing hinged at the neck and tail bases

The crane-with-a-wing studies lower one wing of the traditional crane by
turning it about a crease drawn across it, its *hinge*. They have always put
that crease at folded y = 1/4. In a finished crane the wing opens nearer the
body, along the line from the base of the neck to the base of the tail
([#455](https://github.com/avalonalex/senbazuru/issues/455)). The fixture
lands upside down, with the wing's tip at y = 0 and the body's underside at
y = 1/2 ([README](../../README.md#why-the-crane-is-upside-down)), and that
line is y = 0.376: there the wing's outline narrows back to x 0.876–1.124,
and the neck and tail paper begins beside it.

Moving the hinge there changes what it crosses. Below the wing's widest point,
y = 0.324, a crease across the wing meets four faces on two layers. Above it,
the wing's sides are creased to four small triangles folded inside it, and the
crease has to cut those too, through all layers
([glossary](../glossary.md#origami)): a triangle it missed would be joined both
to paper that turns and to paper that stays put. So the crease at 0.376 is
eight segments rather than four, and the paper between the widest point and
the hinge, the wing's *base*, gets panels of its own (`CraneWing`).

Run the comparison from the repository root:

```bash
stack run senbazuru-material-study -- --crane-root build/fold-material
```

The wing-root study (see [wing-root-holds.md](wing-root-holds.md)) now runs two
of its controls at both hinges. The held control fixes the strip beside the
hinge at 30°; at 0.376 that strip is the whole base. The flat-preference
control releases it and gives the hinge's springs a rest angle of zero. Every
control grips the outer eighth of its wing at 50° about its own hinge, so the
two hinges hold their tips in different places: compare the shapes, not where
the tips are.

Released, the base did not settle. Left to bend as a sheet at 0.376, the
flat-preference solve stalled. The base is several layers folded together, and
the study now turns it as one piece instead: every base vertex is held where
the flat crane's base lands turned by an angle θ about the hinge
(`CraneRoot.rigidBase`). That makes θ a choice the study has to make, so it
takes the θ that leaves the paper the least *bending energy*: the sum of
what every crease spring stores away from its rest angle, the hinge's own
included, and every panel stores bent across a triangle edge. It finds that
θ by golden-section search over 15–45°. Keep a bracket and two points inside
it at the golden ratio, and drop the end beside the worse point. The better
point is then already one of the new bracket's two, so each narrowing costs
one solve. Narrowing to 0.05° takes 16 solves, each starting from the mesh
of the bracket point beside it.

Measured on 2026-10-02:

| Control | Hinge | Triangles | Root turn | Max edge error | Max crease error (rad) | Accepted |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Held root | y = 1/4 | 1,176 | 30.00° | 2.9e-7 | 2.4e-7 | yes |
| Flat preference | y = 1/4 | 1,176 | 28.22° | 1.7e-7 | 7.5e-8 | yes |
| Held root | y = 0.376 | 2,196 | 30.00° | 1.8e-7 | 8.3e-7 | yes |
| Flat preference | y = 0.376 | 2,196 | 28.39° | 2.3e-7 | 2.3e-7 | yes |

At 0.376 the flat preference's root turn is θ itself, because the base is held
at θ; at 1/4 it is where a free solve settled. The two dashed curves in the
side profile almost coincide.

The energy fixes θ to about a degree, not to 0.05°, which is only the width
of the search's last bracket. Against the least energy found, at 28.39°:

| θ | 22.08° | 26.46° | 27.49° | 28.39° | 29.16° | 30.84° | 33.54° |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Bending energy | 3.14× | +7.3% | +1.3% | least | +0.8% | +7.1% | +26% |

Fifteen of the 16 solves converged. The one that did not, at 22.08°, is the
one that ruled out the low end: its energy, three times the least, sent the
search towards larger angles. A settled solve there would change the answer
only by coming in below the energy at 26.46°, 7% above the least.

The search assumes one minimum between 15° and 45°. Taken in order of θ, all
16 energies fall and then rise, which is what one minimum looks like, but
nothing was tried below 22° or above 34°, and a second minimum there would go
unseen. The stiffnesses are illustrative, as in the rest of the study, so θ
is the best angle for these springs rather than for paper. The 16 solves make
the flat-preference control about a hundred times slower at 0.376 than at
1/4: 501 and 507 CPU seconds in two runs, against 4.8 and 4.7.

`hinge-held.svg` and `hinge-flat.svg` draw each control at both hinges, from
one camera at one scale. They are for the owner to decide whether the
crane-with-a-wing galleries move to the neck and tail bases. The second
question in [#456](https://github.com/avalonalex/senbazuru/issues/456),
whether the side profile's magnified scale counts towards the page's paper
screen, waits on that decision.
