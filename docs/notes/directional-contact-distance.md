# Resist a layer reversal before its shadows overlap

Two triangles can remain separated in 3D while violating a retained above/below
relationship. Take a lower triangle at `(0,0,0)`, `(1,0,0)`, `(0,1,0)` and an
upper triangle at `(x,0,-0.05)`, `(x+1,0,-0.05)`, `(x,1,-0.05)`. The second is
actually below the first, but for `x > 1` their shadows on the xy plane do not
overlap. The old contact term has no samples there. As `x` falls below 1, new
samples suddenly carry the full reversed-height penalty. Shortening the move
does not remove that jump; see [the rejected-trial diagnosis](rejected-bending-trials.md).

Instead, imagine extending the upper triangle indefinitely upward. To preserve
the required order, the lower triangle must stay outside that volume. Its
distance from this forbidden volume is `x - 1` in the example, approaching zero
continuously before overlap. If the upper triangle instead has height `+0.05`,
the distance is `sqrt((x-1)^2 + 0.05^2)` for `x > 1`, then stays at `0.05` when
the shadows overlap. `DirectionalDistanceSpec` checks these coordinates.

For arbitrary triangles, choose points `a` on the lower and `b` on the upper.
Split their difference into a component along the unit contact direction and
one perpendicular to it. Minimize

```
|perpendicular(b-a)|² + max(0, along(b-a))²
```

over both triangles, then take the square root. `DirectionalDistance` enumerates
closest vertex, edge and face candidates using both 3D and projected distances.
The two expressions have the same derivative where the along-direction gap is
zero, so their closest candidates cover that boundary too. Each closest point
is a weighted average of its triangle's vertices; these **barycentric weights**
distribute the force back to the existing material ids. Parallel features may
tie, so continuity of distance does not promise a unique derivative everywhere.
A randomized test independently checks a supporting plane: every vertex pair
lies at least as far along the computed normal as the reported closest distance.

Let `d` be this distance minus numerical clearance. The new contact energy uses
a **barrier**, a penalty that grows without bound as `d` approaches zero:

```
b(d,h) = -(h-d)² log(d/h)    for 0 < d < h
         0                 for d >= h
```

Its value and first derivative vanish at the activation range `h`. This scalar
barrier is from [Li et al., Incremental Potential Contact, equation 6](https://ipc-sim.github.io/file/IPC-paper-350ppi.pdf).
Our directional distance and existing least-squares solver are a separate,
narrower experiment, not an implementation of that paper's full method. `h`
is an extra numerical force range, not physical paper thickness. Trials outside
the barrier's domain are refused. Finite-difference tests check both the closest
distance derivative and the resulting barrier residual derivative.

Run `stack run senbazuru-material-study -- --bending build/fold-material` and
open **Contact between numerical poses → Distance barrier · closing**. Both
sides check every accepted straight vertex path; only the right uses the new
contact energy. On macOS on 12 September 2026, the old term stalls at 1.13%
maximum relative material-edge error. With `h = 0.001`, the new mode settles
after 99 accepted corrections at `1.18e-8` relative error, with all 496 endpoint
triangle-pair checks passing. It retains seven learned orders. The same compiled
fixture settles at `h = 0.0005` and `0.002`, with errors `5.90e-9` and `2.37e-8`.
The opening control still settles in three accepted corrections at `6.56e-8`.
Iteration counts describe these runs, not cross-platform constants.

`relaxBarrierLocalHistory` keeps the earlier unknown-contact guard, transactional
history updates, exact motion check and final material/contact tolerances.
Its convergence test still examines the full proposed correction, before line
search shortening; a tiny accepted fraction alone cannot establish equilibrium.
Regression tests replay every accepted path and retained rejected-trial energy.
JSON records which contact energy and activation range produced the audit.
It also marks candidate energies evaluated with **proposed** contact history:
newly discovered pairs can add barrier energy before the move is accepted.
The saved orders describe retained history; replay extends it at the trial pose
when that flag is set. A wider-range regression rejects such a proposal and
replays its added energy without retaining its new pairs.

The remaining scope matters: this preserves retained directional orders, which
can forbid passing around another layer even without physical collision. New
partners still need a separated reference encounter; arbitrary self-contact
and automatic route planning remain open. Intermediate numerical shapes can
stretch. The strict motion check proves separation, not a physical folding
instruction or preservation of directional order throughout an interval.
This increment is [#172](https://github.com/avalonalex/senbazuru/issues/172).
