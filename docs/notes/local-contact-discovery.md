# Discover nearby parts of bending paper

An uncreased strip can curl until its returning end meets its beginning.
Both ends still belong to one source panel, the region between deliberate
crease lines. `LocalContactDiscovery` distinguishes material triangles within
that panel and finds nearby partners from a separated reference shape. It
consumes a mesh, a model direction and two distances, with no authored pair
list. Panel identities and original-sheet coordinates stay unchanged.

The two distances serve different purposes. A **search distance** gathers
possible partners before they touch. The much smaller **numerical clearance**
is the gap the solver tries to leave, to absorb tolerated numerical error.
Neither distance represents physical paper thickness. Both are measured along
the supplied direction where triangle projections overlap; this is not a
closest-distance calculation in 3D. The direction belongs to the model, so
rotating the camera changes no contacts.

`SurfaceContact.localOverlapCandidates` shares clipping arithmetic with the
existing whole-panel scan, but compares triangles regardless of panel owner.
It excludes triangles sharing material vertices: their connection cannot be
pulled apart. Projected bounding boxes only discard impossible overlaps;
clipping determines the overlap and the range of height differences across it.
Crossed or coplanar references cannot establish order and are refused. When
both triangles stand parallel to the direction, the scan conservatively refuses
an unresolved comparison instead of guessing.

A triangulation diagonal is not a physical boundary. If a discovered overlap
covers only one half of a flat reference patch, a later contact can slide onto
its other triangle. Connected coplanar reference triangles therefore share
their discovered partners. This expands the triangle requirements without
merging vertices or introducing source panels. Their membership stays fixed
with the reference, even if they subsequently bend. Shared-vertex pairs are
still excluded, cycles and incompatible transitive requirements are refused,
and the independent reference check inspects every pair, including neighbors.

Correction keeps these learned orders. It rescans every trial shape, but never
learns a new order from that trial: an intersection could otherwise legitimise
the reversed side. An unknown separated pair needs no contact force. If it
reaches clearance plus the contact tolerance, or crosses, the trial is refused.
The wider reference search distance is a buffer for finding partners ahead of
that event, not another force or a requirement to keep distant shadows ordered.
An insufficient reference can stall a solve; that result remains unconverged.

Run `stack run senbazuru-material-study -- --bending build/fold-material` and
select **Curled panel · discovered contact**. Its eight spans start at 44.5°
per bend, positioned using original span lengths. The reference direction is
`(-3, 0, 1)` and the search distance is `0.03` model units. The scan finds three
nearby overlaps between the strip ends; extending them across the two flat
end patches supplies four triangle relationships. The separate numerical
clearance remains `1e-6`. The passive springs and imposed curl controls are
those of the [original experiment](local-panel-contact.md).

The eight-span correction settles in 38 numerical iterations. Its largest
relative material-edge error is `9.37e-8`, and all 120 independent triangle-pair
checks pass, with no crossing, unresolved overlap or reversed order. The
smallest gap is about `9.999e-7` model units along the contact direction.
Without contact forces, the same controls produce three crossing pairs.
All nine previous gallery runs retain their exact meshes and measurements.

The sixteen-span regression exposes the remaining history limitation. Its
22.25° reference also discovers the end patches, but early correction steps
meet the neighboring spans (including triangle pairs 2/30 and 0/28). Those pairs
are absent from the reference. The ordinary fixed-pair solve reaches a valid
endpoint; the discovery-guarded solve refuses those trial encounters and remains
unconverged. This is an explicit coverage failure, not a successful finer-mesh
correction or evidence that its intervening route is safe.

This is reference-based discovery under specified controls, not automatic
approach selection. A flat starting sheet may provide no partners. New contacts
must be covered by another suitable reference or explicit requirements; the
solver does not yet maintain an evolving bending-contact history. Neither its
numerical iterates nor the pose construction certify collision-free motion.
These boundaries, and a fixed direction's inability to describe all possible
self-contact arrangements, remain part of [#146](https://github.com/avalonalex/senbazuru/issues/146).
This increment is [#164](https://github.com/avalonalex/senbazuru/issues/164).
