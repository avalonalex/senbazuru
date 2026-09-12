# Remember the side of a first encounter

Start the opposing-flap sheet at 145° / 105°. The middle panel is below each
flap, but the flaps themselves have no overlapping footprints when viewed
along the model's vertical direction. Their geometry supplies two relationships,
not three. Hold the left crease at 145° and close the right through 110°, 115°,
120° and 121°. At the last sample the flap footprints overlap, while the paper
remains separated by at least `0.08464948` sheet units. The left flap is below
the right: we can now record that relationship before correction brings them
into contact. “First encounter” here means the first **sampled projected
overlap**, not the exact instant that paper touches paper.

`ContactDiscovery.observeContactPose` accepts an existing reference history and
one new mesh pose. It first checks that triangle ids and original-sheet
coordinates have not changed, and that the pose respects every earlier order
and its numerical clearance. Only previously unrelated overlapping panels need
a new decision. Their measured height ranges must resolve one above/below side;
crossed, coplanar or uncheckable first encounters are refused. Relationships
already implied through other panels are retained without adding a duplicate.
The combined order must have no cycle, and the independent triangle check must
also pass, including pairs inside one source panel.

Only then does the function return a new history. Each observation records its
number, newly learned relationships and measured triangle overlaps. The opaque
`ReferenceContact` keeps this audit together with its prepared constraints;
accessors cannot update the history. A failure returns `Left` and leaves the
caller's original value available for another attempt. Relationships survive
separation and re-contact. This is deliberately conservative: carrying a flap
around another to reverse its order requires a richer history model.

Numerical solver trials never call the observation operation. They keep using
`discoveredContacts` with the accepted history frozen. Otherwise a trial could
cross the paper and then describe its new side as the intended order. The
approach is supplied by the caller; this increment does not plan a motion or
teach the solver to discover unrelated contacts inside its line search.

Run `stack run senbazuru-material-study -- --bending build/fold-material` and
choose **Opposing flaps · first contact**. **Folding state** selects the five
angle-defined approach poses or the corrected endpoint comparison. Every pose
uses the same connected sheet, camera and scale. The approach has 40 triangle
overlaps until 121°, when it has 46 and learns the third panel relationship.
Its largest relative edge-length error is below `8e-16`; the achieved crease
angles agree with the prescribed angles to `1e-10` degrees in the test. The
JSON records each pose's current orders and the first-encounter measurements.

From 145° / 121°, the correction settles in 140 numerical iterations with
maximum relative edge error `8.80e-8`. All 276 independent triangle-pair checks
pass. The corrected mesh is exactly the same as an authored-order solve from
that pose, which serves as an independent oracle. The seven older gallery runs
retain their geometry and measurements. Tests also cover opposite approaches,
reversed re-contact, invalid material, insufficient clearance and rejected
observations that leave the history unchanged.

These are checks of sampled poses. Paper could cross and separate between two
samples without either endpoint revealing it. We do not interpolate positions
or claim a collision-free path: approach positions come from crease angles,
and numerical correction checkpoints are not folding instructions. Continuous
collision checking, automatic approach selection and correction within a bent
source panel remain open. The existing `1e-6` numerical clearance between
unjoined panels remains separate from physical thickness. This increment is
[#158](https://github.com/avalonalex/senbazuru/issues/158), following
[reference discovery](reference-contact-discovery.md) and
[ordered correction](ordered-flap-contact.md).
