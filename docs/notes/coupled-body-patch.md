# A small body can open before its solve settles

After the [illustration-priority decision](illustration-material-priority.md),
return to the body with both wing roots involved. The earlier root experiment
held the central body and the other wing fixed. This experiment instead extracts
the eight central panels from the [material map](crane-pocket-map.md), plus their
four neighbours in each wing. It keeps their original material coordinates and
shared vertices. Run the four declared controls with:

```bash
stack run senbazuru-material-study -- --body-patch build/fold-material
```

This is a **free-boundary specimen**: its outer edges can move because the rest
of the crane has been removed. It cannot establish that an attached neck, tail
or complete wing would allow the same shape. The two collars are also not
mirror copies: the earlier fixture divided one wing at an authored root line.
No new symmetry, pressure cavity or whole-crane response is assumed here.

Three exact holds control opening. Fix the original sheet's centre and move
the two wing attachments in opposite directions around it, keeping their
distance to the centre. Each attachment moves by 5° or 10°; their separation
angle is twice that value. The two neck/tail attachment landmarks remain free.
The controls were recorded in [#317](https://github.com/avalonalex/senbazuru/issues/317)
before solving. All fourteen internal mountain/valley creases belong to the
mapped candidate opening set. Their original signed angles remain spring
preferences, so opening them does not violate an exact angle requirement.
Panel and crease stiffness stay at the earlier illustrative values, 0.2 and 1.
This uses the existing crane held/contact solver. The later two-panel solver
repairs contact by moving an upper and lower panel apart; applying that policy
to this multi-panel body would require a separate change and validation.

The patch keeps the full crane's inherited layer order before removing outside
panels. Otherwise removing a layer between two retained layers could erase
their relationship. Its distinct touching vertices remain distinct. The
coarse specimen has 29 vertices and 30 triangles; subdividing the same flat
triangles gives 87 vertices and 120 triangles, with the same three holds and
the same starting shape. The initial opening guess is not required to preserve
lengths; the solved endpoint is. Numerical corrections are never an animation.

Measurements on 2026-09-20, with forty iterations per existing length-penalty
stage and the unchanged `1e-5` relative length limit:

| Control | Triangles | Largest relative length error | Contact/order | Settled? |
| --- | ---: | ---: | --- | --- |
| Closed reference | 30 | `2.30e-13` | Pass | Yes |
| Attachments at 5° | 30 | `1.62e-6` | Pass | No |
| Attachments at 10° | 30 | `1.78e-6` | Pass | No |
| Attachments at 5°, refined | 120 | `4.01e-2` | Fail | No |

The coarse opened endpoints preserve the exact holds and pass the independent
length/contact checks, but exhaust the final iteration budget. Neither has
earned the solver's convergence verdict. Their central body depths are
`0.036192` and `0.072102` sheet units. At 5°, the free tail and neck landmarks
move `0.001097` and `0.001048` sheet units; at 10°, they move `0.004042` and
`0.003743`. These are responses of the isolated specimen, not predictions of
the crane's final silhouette. Separate crease/panel costs are
`0.011986 / 0.00060690` and `0.048332 / 0.00239761`.

The refined trial is a stronger failure: 4.01% maximum length error, 124
crossing triangle pairs and 333 reversed-order pairs. It also exhausts its
budget. Its lower crease cost and larger panel cost cannot make this a usable
pose. These are counts of triangle pairs, so refinement alone can change a
count; the important result is that the geometric checks fail. The four solves
took about 52 CPU seconds together. This is a bounded failure to retain, not a
reason to launch a larger crane solve or another cost-convergence sweep.

The gallery separates accepted paper from diagnostic wire views, which show
hidden layers. Only the closed reference gets an accepted GLB/paper preview.
Side, top and underside drawings use fixed cameras and 600 pixels per original
sheet unit, with a 2× inspection option. Every endpoint and initial guess is
saved as FOLD; reports include source identities, exact holds, achieved angles,
separate energies, body bounds and attachment movement. Saved checkpoints let
the next investigation inspect where the refined run deteriorated. The
coarse/fine comparison measures matching vertices only and is explicitly not
an accepted refinement result or a whole-surface distance bound.

An independent measurement script recalculated material connectivity, lengths,
holds, area, angles, both energies, body bounds and landmark movements from the
exports. A separate projected-overlap calculation reproduces all 333 reversed
orders on the refined endpoint and no reversed orders above tolerance on the
coarse endpoints. In particular, the specimen's area is about 0.29566, not one: its area
ratio must divide by its own original material area. Fast regression tests
cover extraction, coincident-but-distinct material, unchanged refined controls
and starting shape, crease provenance, the flat equilibrium and refusal of
unfinished or invalid endpoints. The expensive open controls stay in the
explicit gallery command rather than CI. All 1,779 tests pass after a cold,
warning-free build; formatting, HLint 3.10 and JavaScript checks also pass.

Next, use these saved checkpoints to distinguish slow settling of the coarse
5° case from the refined case's length/contact failure. Start by locating the
first deterioration and checking the proposed correction; do not relax the
geometry checks or assume the controls are impossible. A targeted continuation
or correction experiment can follow that diagnosis. Full wings, neck/tail
loads, pressure and a certified flexible path remain separate work under
[#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).

[The checkpoint audit](body-patch-checkpoints.md) now locates the initial
order defects and first-correction crossings without new solves, and records
one proposed continuation from the recovered coarse shape.
