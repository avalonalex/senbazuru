# Refining unequal panels under one solver policy

The [original refinement grid](unequal-crease-refinement.md) stopped at a
numerical failure on its finest length mesh. The [solver comparison](fine-crease-solver.md)
resolved that case with an extra length-penalty stage and an exchange of two
nearly parallel contact constraints. Comparing that result directly with the
older coarse endpoints would change both the mesh and the solver policy.
Repeat every mesh with both numerical changes before judging its shape.
The measurements below record the five-mesh run; the command now also
includes `4×2`, documented in [the follow-up](two-direction-crease-refinement.md).

```bash
stack run senbazuru-material-study -- --combined-refinement build/fold-material
```

Use the same five meshes: length × width `1×1`, `2×1`, `4×1`, `1×2` and
`2×2`. These multipliers divide the four original crease-to-edge segments
and two width intervals independently. Each mesh has matched holds, an extra
upper bend preference, and that same preference with contact disabled. Held
material strips and outer edges, the three upper control lines and their
total stiffness 24 are unchanged. The shared crease keeps one set of material
vertices; touching points elsewhere remain distinct parts of the sheet.

Every run uses length weights `1e2`, `1e4`, `1e6`, `1e8`, `1e9`, the contact
exchange method and at most 40 iterations per stage. Contact-off omits the
inequalities and repairs but keeps the material objective and holds. The
relative edge-error cap remains `1e-5`; original crease error must be at most
`1e-5` radians. Exact stored-coordinate gaps must be nonnegative, alongside
the independent whole-sheet contact check with its existing `1e-7` distance
tolerance. A failed solve remains diagnostic even if its geometry passes.

The command saves these settings with each result in `checks.json`. Earlier
commands keep their original numerical policies and output directories. The
new page shows material error and numerical convergence separately from the
endpoint checks, with complete FOLD/GLB exports and the same profile, gap and
40×40 fixed-location maps as the earlier grid. Distances below are fractions
of the unit sheet's side; near-contact counts use the unchanged `1e-7` gap
threshold and describe samples, not exact contact areas.

On 2026-09-16 all fifteen solves converge. All ten contact-enabled endpoints
pass material identity, exact holds, lengths, original crease angles and
both contact checks. Every recorded constrained iterate has a nonnegative
exact gap; every accepted update decreases its stage's energy after repair.
The three `4×1` endpoints reproduce #230's combined-policy coordinates
exactly. The upper-preference measurements are:

| Length × width | Triangles | Maximum gap | Near-contact / overlap samples | Relative edge error | Accepted |
| --- | ---: | ---: | ---: | ---: | --- |
| 1×1 | 32 | 7.358e-8 | 1480 / 1480 | 8.682e-8 | Yes |
| 2×1 | 64 | 0.006989 | 400 / 1480 | 7.689e-7 | Yes |
| 4×1 | 128 | 0.005510 | 400 / 1480 | 3.961e-6 | Yes |
| 1×2 | 64 | 3.417e-8 | 1480 / 1480 | 4.471e-8 | Yes |
| 2×2 | 128 | 0.006868 | 400 / 1480 | 5.713e-7 | Yes |

Width refinement retains the opening at length multiplier two: the maximum
gap changes by `0.000121`, about 1.7%. At length multiplier one, the whole
sampled overlap remains near contact. The larger length meshes have only the
400 samples in the held root strip near contact; all 1080 overlapping free
samples are separated. All meshes have the same 120 samples outside overlap,
which are never counted as touching. Compared with the original weaker
penalty, the coarse gaps have moved below the plotting threshold; that change
in sample classification is not evidence of a new macroscopic contact region.

The maximum gap alone can hide a changing shape. Comparing the same material
vertices in each adjacent pair gives:

| Refinement | Maximum matching-position change |
| --- | ---: |
| 1×1 → 2×1 | 0.001298 |
| 2×1 → 4×1 | 0.004552 |
| 1×1 → 1×2 | 1.351e-6 |
| 2×1 → 2×2 | 0.0002124 |
| 1×2 → 2×2 | 0.001211 |

The second length doubling moves matching points more than the first, even
though its maximum gap decreases. The unchanged near-contact counts at
`2×1` and `4×1` do not establish shape convergence either. These comparisons
are now between accepted numerical endpoints; they no longer include the
earlier failed fine-length result.

The controls still isolate the effect of contact. All matched endpoints have
maximum gaps below `3e-14`. All contact-off endpoints converge but cross by
`0.002775` to `0.005095` sheet lengths. Their lower panels match the
corresponding matched-holds reference within `1.7e-14`, while enabling contact
changes the lower panel by `0.001482` to `0.002573`. This is evidence that
contact transmits the upper preference, without asserting a unique physical
shape. The reported panel-bending energy includes the imposed bend controls;
its change across meshes is a diagnostic, not an acceptance criterion.

The [follow-up comparison](two-direction-crease-refinement.md) fills the
missing `4×2` mesh under this same policy. The large `2→4` length change
persists at both widths.
Its achieved-turn and passive/control energy diagnostics expose a changing
competition at the three control lines. Holding their total stiffness fixed
does not by itself establish a mesh-independent loading model; the follow-up
records a bounded loading comparison before returning to the crane body.
Known order along z, retained triangle facing directions and static endpoints
remain limitations; no continuous flexible route is certified here.
