# Check the numerical correction before accepting it

Fold a square 120 degrees about its diagonal. Its lifted corner is at
`(0.25, 0.25, sqrt(3/8))`; folding to the other side puts it at
`(0.25, 0.25, -sqrt(3/8))`. Both poses preserve the original triangle lengths,
and neither intersects the base. But moving that corner straight between them
puts it at `(0.25, 0.25, 0)` halfway across, inside the base triangle. The
shared diagonal is lawful contact; the overlapping triangle interiors are not.

Run `stack run senbazuru-material-study -- --bending build/fold-material` and
select **Contact between numerical poses**. **Correction case** shows the
clear endpoints or the rejected halfway witness. These are samples of a
numerical shortcut, not instructions for a half-fold. Unfolding and refolding
would follow a different path, determined by crease angles, and would preserve
material lengths. The solver instead proposes a displacement for each vertex;
its line search tries smaller fractions of that displacement. That gives a
specific straight path to check, even though intermediate triangles can stretch.

`CorrectionSweep` asks whether a plane separates each triangle pair throughout
an interval. Projecting the moving vertices onto the plane's normal gives
polynomials in progress. We express these in the **Bernstein basis**, whose
functions are nonnegative and add up to one. The polynomial's value is therefore
a weighted average of its coefficients: if every coefficient is positive, the
value stays positive over the whole interval. This use of Bernstein signs in
collision detection is described by [Tang et al.](https://pmc.ncbi.nlm.nih.gov/articles/PMC4283478/).
Our checker uses sufficient separation certificates and interval subdivision,
not that paper's complete system of feature-level collision queries.

Fixed measuring directions often separate a pair immediately. Otherwise we
try planes attached to either moving triangle. A shared vertex or edge prevents
strict separation, so the plane may contain that shared material, provided the
remaining vertices of at least one triangle stay strictly on its side. Any
intersection is then confined to the shared point or edge. Merely skipping
neighbors would miss the diagonal-fold shortcut. We also bound each triangle's
squared normal length; it must stay positive so a collapsed triangle cannot
slip through the pair tests.

The finite input `Double` coordinates become exact rational numbers before
these bounds are computed. Subdivision restricts the original exact paths;
it never rounds an intermediate pose and treats that rounded pose as new input.
Structural zeros at shared vertices therefore stay zero, and a tiny negative
coefficient never becomes acceptable through a tolerance. This proves separation
for the specified straight paths of those encoded coordinates. It does not
account for uncertainty in measured input or supply physical paper thickness.
Static contact diagnostics still use their existing tolerance when reporting
an approximate witness; they cannot establish a clear interval.

A result is clear, a collision or degeneracy witness, or unresolved. The default
limits are 16 subdivisions per branch and 1,024 visited intervals. Failure to
find a separating plane is not proof of collision: subdivision may find another
plane, a static sample may provide a witness, or the work limit may be reached.
An unresolved result refuses the correction. A witness is not a first impact
time. A collapse at a progress such as `1/3`, which binary subdivision never
samples exactly, must still prevent a clear result.

`relaxSweptLocalHistory` checks the starting pose and every accepted straight
correction before retaining positions or learning new contacts. The returned
audit contains the accepted endpoints, iteration labels and interval reports.
Energy-increasing candidates are discarded before doing the more expensive
motion check. The original endpoint-only modes remain available for comparison.

The **Checked opening** control starts with the same sixteen-span strip as the
[history experiment](growing-local-contact-history.md), at 22.25 degrees per
bend. Its external controls prefer 27 degrees, with four times the stiffness
of the passive springs preferring zero. Their balance opens it to 21.6 degrees.
It settles after three checked corrections, with maximum relative edge-length
error `6.56e-8`. The final shape passes all 496 independent triangle-pair checks.

The original closing controls expose the harder problem. They prefer 30 degrees,
but the strict motion guard stops the solver after 25 accepted corrections;
its 400-iteration budget ends unconverged, with about 1.13% edge-length error.
The accepted paths clear; the resulting stretched sheet is not a finished fold.
Rejecting intersections does not itself provide a direction that can move
along contact while restoring lengths. The guard also refuses unresolved
bounds; this comparison does not classify every rejected trial as a collision.
Diagnosing the limiting trials and finding admissible corrections is the next
solver problem, rather than accepting more iterations as evidence of success. All eleven earlier
gallery runs retain their exact meshes and measurements.

This increment is [#168](https://github.com/avalonalex/senbazuru/issues/168).
Arbitrary physical folding paths, thickness and contact-aware motion planning
remain in [#61](https://github.com/avalonalex/senbazuru/issues/61) and
[#146](https://github.com/avalonalex/senbazuru/issues/146).
