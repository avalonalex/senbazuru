# A quick tier holds the body

The study's crane galleries settled a spread wing in hours when this note was
written, on 2026-10-03. Each runs several
controls, many with the crane's body free to move, and each released control
searches or checks the angle of the wing's base. A reader who wants to see
one spread crane needs one settled shape. The quick tier gives one in under a
minute ([what it costs](#what-it-costs)), by holding paper that the model leaves
free, and saying so.

```bash
stack run senbazuru-material-study -- --crane-quick build/fold-material
```

## What it holds

The wing turns about its root ([flap-roots.md](flap-roots.md)). The quick
tier holds the crane's body still while the wing spreads, and turns the
wing's base, four layers deep above its widest point, as one piece. The body
is left free in the research galleries; holding it is the owner's choice for a
quick tier (owner decision 39). The output names what it held: its GLB's
*fidelity record* ([glossary](../glossary.md)) gives the geometry as `bent
zero-thickness`, settled by the solver, with a `held` list:

```json
{"geometry": "bent zero-thickness",
 "held": ["the body", "the wing's base, turned as one piece at 28.394°"], ...}
```

So it is a true solve of held paper, and claims nothing about the paper the
model leaves free.

## Why holding the body costs nothing visible here

Measured at the root on 2026-10-03, against the research galleries' accepted
endpoints with the body free. The largest distance between matching vertices
of the quick endpoint and each released one, in pixels at the 692 px per
sheet unit the quick tier draws at:

| Released endpoint | Largest difference |
| --- | ---: |
| crane-body, original springs | 0.0084 px |
| crane-body, selected springs × 0.1 | 0.0084 px |
| crane-body, 170° preference | 0.0084 px |
| crane-internal, original | 0.0084 px |
| crane-internal, continued | 0.0084 px |

crane-internal's crease-lines-held control is left out: at the root it misses
the original-angle limit and is not accepted
([internal-crease-diagnostic.md](internal-crease-diagnostic.md)).

The 1 px a quick result may differ by is more than a hundred times larger.
Little of the difference is the body. Released, the crane's body moves at
most 5.5e-7 sheet units, 0.0004 px here: the body barely moves when the wing
opens, so holding it changes nothing a drawing can show. The base angle is
the other difference, 28.394° here against the galleries' 28.383°. That is one model. A model whose shape comes from its body moving, such
as an inflated water bomb, cannot be made quick this way
([#428](https://github.com/avalonalex/senbazuru/issues/428)).

## How it chooses the base angle

A full search ([wing-hinged-at-the-neck.md](wing-hinged-at-the-neck.md)) tries
16 angles from 15° to 45°, narrowing to 0.05°. The quick tier searches
within 5° of the turn its control's root starts at, 30°, read from the
control, and narrows to 0.5°. If its answer lands at an end of that bracket,
the least may lie beyond it, and the full search runs instead.

Half a degree is enough. Turned away from the least by a measured amount, the
held solve moves by:

| Off by | Largest difference at 692 px per sheet unit |
| --- | ---: |
| 0.5° | 0.38 px |
| +1° | 0.73 px |
| −1° | 0.82 px |
| −2° | 1.76 px |

## What it costs

On 2026-10-25 five runs took 39.17 to 39.38 seconds of wall clock each, on an
Apple M1 Max, and each found 28.394° and was accepted. The study runs on one
core, so its CPU time is its wall clock: user and sys came within 0.03 seconds
of real in every run. Of those 39 seconds, 30.90 to 30.99 were the nine solves,
the only part the run times itself (`solveCpuSeconds` in `checks.json`). The
rest loads the crane and builds its wing, checks contact, screens the result and
writes the three files, none of it timed apart. The runs went one after another
under `/usr/bin/time -p`, with no other build or study running, on a binary
built on 2026-10-23 from #620's code, which `5523e5a`'s equals.

It cost more at first. At `a8d69c7`, on 2026-10-03, three runs took 183.3, 198.2
and 200.1 CPU seconds for the solves, nine each, finding 28.394°; about four
minutes of wall clock with the exports. Searching to 0.05° instead took 14
solves and 218 to 221 CPU seconds, so the last five solves, near the least and
starting from a neighbour already close to it, were cheap. The first ones
carried the cost: one of the first four, at 31.18°, did not converge. The
solves were not timed one by one, so how the time divided among them was not
measured.

On 2026-10-21 all nine solves converged, the one at 31.18° included, and found
the same 28.394°: in 90.8 CPU seconds at `0bdd02f`, and in 92.3 with #566's fix
to the contact clip ([snap-edges-along-a-clip-line](snap-edges-along-a-clip-line.md)),
one run each. So the 31.18° solve converged before that fix. At least four
commits between `a8d69c7` and `0bdd02f` change the code the quick tier runs
(#485, #573, #575 and #539), and which one changed it was not isolated.

From those 92.3 seconds to the 31 of 2026-10-25 is a cut of about two thirds.
Three merged changes touch the code the quick tier runs in between: #614, #619
and #620. #619 and #620 were the speedups, the first removing work the solve
and its checks repeated, the second judging each step the solver tries by its
contact gaps alone. Timed side by side with the code before each, at `-O1`, they
left the quick tier's settles and checks at 0.80 and then 0.46 of what they were
([crane-solve-profile](crane-solve-profile.md)). #614's effect was measured only
on allocation.

Measured before #619 and #620, for scale: one released control in the research
galleries cost 3,902 CPU seconds for its three solves, and the whole
crane-internal gallery 7,965. A single held solve at a known angle took 7.5.

The body galleries keep the comparison that matters most on every run: how
far their own held control's paper lies from each released control's
(`heldComparison` in crane-body's and crane-internal's `checks.json`, and the
last column of each page's comparison table). Where that stays under a pixel,
holding the body is a label and not a change of shape.

Given the research galleries' FOLD endpoints, the quick tier also writes the
comparison above into its `checks.json` (`--crane-quick DIR FOLD...`), so it
can be repeated after the galleries change. Pass only endpoints their gallery
accepted: `selectedAccepted` in a crane-body control's `-check.json`,
`accepted` in a crane-internal one's. A FOLD does not say whether it was
accepted, and a diagnostic endpoint compares as readily as an accepted one.
A reference that cannot be read, or lies on another mesh, is recorded with
the reason and not compared; the quick tier's own files are written first.
