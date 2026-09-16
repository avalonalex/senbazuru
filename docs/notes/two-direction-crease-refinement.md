# Refining the unequal panels in both directions

The [common-policy grid](combined-crease-refinement.md) accepted its five
meshes but left one comparison missing: length × width `4×2`. Adding it gives
256 triangles and tests whether the large `2→4` length change also appears
at the finer width. The same command now generates all six meshes:

```bash
stack run senbazuru-material-study -- --combined-refinement build/fold-material
```

The solver, holds, original crease, three imposed upper bend lines and
acceptance limits are unchanged. Every mesh uses length weights through `1e9`,
contact exchange and forty iterations per stage. The added diagnostics only
measure the existing springs. They separate passive bending, which resists
curvature inside each uncreased panel, from imposed bending, which asks the
upper panel to turn further at three material lines. Both remain illustrative
energies, not calibrated paper properties.

On 2026-09-16 all eighteen solves converge and all twelve contact-enabled
endpoints pass. The new `4×2` measurements are:

| Control | Iterations | Relative edge error | Minimum exact gap | Maximum gap | Accepted |
| --- | ---: | ---: | ---: | ---: | --- |
| Matched holds | 51 | 6.473e-7 | 0 | 1.401e-14 | Yes |
| Upper bend preference | 87 | 2.336e-6 | 0 | 0.005676 | Yes |
| Same preference, contact off | 51 | 6.473e-7 | -0.005112 | 0.005575 | No |

Lengths, original crease angles, shared material identities, exact holds,
independent whole-sheet contact and exact order pass at the constrained
endpoints. Every recorded constrained gap stays nonnegative, and every
accepted update decreases its own stage's energy after repair. All forty-five
previous FOLD states reproduce #232 unchanged. The expanded gallery retains
fifty-four complete states with FOLD/GLB exports, side profiles, gap plots
and the same 40×40 sample map.

The upper-preference comparison is still sensitive to length resolution:

| Refinement | Maximum change at matching material points |
| --- | ---: |
| 1×1 → 2×1 | 0.001298 |
| 2×1 → 4×1 | 0.004552 |
| 1×2 → 2×2 | 0.001211 |
| 2×2 → 4×2 | 0.004398 |
| 4×1 → 4×2 | 0.0003004 |

These distances are fractions of the unit sheet's side. The large second
length change persists at both widths. At length four, doubling width changes
the maximum opening from `0.005510` to `0.005676`, about 3.0%. Both maps retain
400 near-contact and 1080 separated samples, with 120 outside overlap. Those
stable counts do not establish shape convergence. Contact still influences
the lower panel: enabling it changes the `4×2` lower endpoint by `0.001503`,
while contact-off restores the matched reference within `1e-14` and crosses.

The energy breakdown exposes competition at the imposed lines. Each extra
spring is an angular preference on an existing triangle edge, not a new
material crease. Its preferred angle stays fixed under length refinement.
The ordinary passive spring at the same edge remains present and prefers
zero angle. Summed across the width, each line has imposed stiffness `8`,
whereas its passive stiffness is `1.6`, `3.2` and `6.4` at length multipliers
one, two and four, at either width. This increase follows the existing
edge-length/triangle-height weighting: length refinement makes the triangles
narrower beside that edge. It is not a change of material parameters.

For the middle upper line, `0.25` sheet lengths from the shared crease, the
preferred turn is about `-0.3909` radians at every resolution. The achieved
range across its width is `-0.2731` to `-0.2690` on `2×2`, but `-0.2194` to
`-0.2172` on `4×2`. Zero means coplanar triangles; the sign follows material
winding, not the camera. The finer mesh turns less at that particular line.
Its upper passive energy and unmet-control energy both increase:

| Upper-preference mesh | Lower passive energy | Upper passive energy | Imposed control energy |
| --- | ---: | ---: | ---: |
| 2×1 | 0.10556 | 0.35401 | 0.19941 |
| 4×1 | 0.11865 | 0.48050 | 0.36054 |
| 2×2 | 0.10668 | 0.35291 | 0.20096 |
| 4×2 | 0.12000 | 0.48619 | 0.35836 |

These three contributions sum to the previously reported panel/control
energy; the original closed crease is excluded. `checks.json` also retains
each width segment's material location, signed achieved/preferred angles,
stiffnesses and separate energies at all three exported stages. The page
shows ranges rather than hiding widthwise variation in an average.

This identifies a changing competition between the passive material and a
fixed-angle line load. It does not prove that loading is the only source of
length sensitivity, or that the existing passive bending model is calibrated.
The [next experiment](distributed-bend-preference.md) compares these line
loads with a bend preference distributed over a fixed-width material band, keeping the band
width, total desired turn and flat-reference control energy fixed as its
triangles are subdivided. It tests a finite region of curved paper while
retaining this line-load case as the reference, comparing energies, gaps and
matching positions before returning to the crane body. Known z order and
static endpoints remain limitations; no continuous flexible route is
certified here.
