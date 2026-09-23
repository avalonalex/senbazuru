# One small repair keeps the larger body trial

[The distance diagnosis](body-plane-loss.md) found a finite loss that the
moving-plane guard's linear prediction missed. Here we keep the saved **1/128**
trial and apply **one** correction to its positions. The result passes the
original all-pair geometry and actual-cost checks. The largest repair is only
**3.066757e-12 sheet lengths**, compared with **7.192170e-6** for the main trial.
[#349](https://github.com/avalonalex/senbazuru/issues/349) tracks this experiment;
[the glossary](../glossary.md) defines material coordinates, panels and contact.

```bash
stack run senbazuru-material-study -- --body-restoration build/fold-material/body-plane build/fold-material
```

The target is vertex 27's original signed distance to triangle 70 at the start
of attempt ten, approximately `-9.99988368057328e-8` sheet lengths. We restore
that distance, not zero separation, and keep the existing `1e-7` contact
tolerance. The plane extends beyond the triangle; this remains an explicit
local guard selected from the earlier crossing diagnosis, not newly discovered
physical contact.

At the refused trial, recompute the distance gradient: how each coordinate
changes the distance for a small move. Remove held vertices from that gradient.
If `g` is the remaining gradient and `loss` is the distance to recover, use:

```text
correction = loss * g / (g dot g)
```

This is the smallest sum of squared vertex movements that satisfies the one
linearized distance equation. Adding movement perpendicular to `g` would
increase movement without recovering more distance. All four relevant vertices
are free here: vertex 27 and triangle 70's corners 81, 71 and 20. The exact
holds elsewhere stay unchanged. There is no new material equilibrium solve,
iterative repair, line search or continuation.

The correction is only a proposal. Check the original twelve overlap guards
against the total movement, then their refreshed derivatives against the repair.
Both versions keep the previous `min(0,gap)` floor rule and `1e-12` linear
residual cap. Also check the original plane guard and the restoration equation.
Remeasure all triangle pairs, material edge lengths, shared identities, exact
holds and actual final-weight cost. A failed check would leave the candidate
diagnostic; this experiment does not retry.

| State | Plane margin above −1e-7, ×1e-12 | Geometry | Actual total cost |
| --- | ---: | --- | ---: |
| Saved start | +1.163192 | Pass | 0.012974870841259303 |
| Saved 1/256 | +0.010253 | Pass | 0.012971035753612711 |
| Saved 1/128 | −3.448565 | Fail: 46–70 | 0.012967223468417423 |
| One restoration at 1/128 | +1.163196 | Pass | 0.012967223114007682 |

The margins above use independent 60-digit arithmetic on the exported
coordinates. Rounding the positions after repair leaves a distance about
`3.5e-18` above the target in the executable's arithmetic. All twelve original
and refreshed overlap margins are positive: the smallest are approximately
`6.03e-12` and `4.62e-12`, respectively. The largest relative length error stays
`2.247410e-6`, below `1e-5`; hold error is exactly zero.

Actual cost falls a further **3.544097e-10** relative to the refused trial.
Separate contributions remain visible: crease energy is unchanged, panel
bending rises about `4.10e-13`, the length penalty falls about `6.49e-13`, and
the contact penalty falls about `3.54e-10`. Body depth is unchanged at the
exported precision. This repairs numerical feasibility; it does not produce
a visible new opening. A geometric intersection segment still exists within
the original tolerance, so neither the red segment nor a passing report means
exact mathematical separation.

The shared archive reader validates both saved proposals, their 62 fractions
and the preceding 310 trials. Source files are copied unchanged; the passing
1/256 and refused 1/128 retain their positions. The four-state gallery uses
shared cameras and scales, with six views and full FOLD/JSON evidence. Five
fast coordinate tests cover minimum movement, a tiny repair against a held
plane, an already-satisfied target, an impossible held repair and invalid input.
Independent calculations recheck the plane gradient, correction, every material
cost, every triangle pair and both sets of overlap guards. All 1,874 tests pass
after a warning-free cold build, with clean formatting, HLint 3.10 and JavaScript
checks. The new tests take about 0.0005 seconds and add no material solve to CI.
The previous gallery's 813 assets and HTML regenerate byte-for-byte unchanged;
5,143 earlier source assets remain unchanged. All six new views load correctly.
An altered saved fraction is refused before any output is written.

[The follow-up](body-fresh-direction.md) now evaluates **one fresh material
direction from this corrected 1/128 candidate**, refreshing the same three-pair
and plane guards. It retains the original trial fractions and geometry/cost
checks. It selects 1/256 but again refuses 1/128 at 46–70: repair permits another
tiny correction without removing the finite-motion limit. The body remains
unsettled, the movement between these numerical states is not certified, and
no whole-crane opening has been established.
