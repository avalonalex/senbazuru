# Learn contact partners before they meet

Run `stack run senbazuru-material-study -- --bending build/fold-material` and
select **Curled panel · growing contact history**. Both pictures start with the
same uncreased strip: sixteen spans (successive rectangular pieces along the
strip), each bent 22.25°. The left solve keeps its
initial four triangle relationships and stalls when neighboring spans approach.
The right solve records six additional relationships at numerical iteration 5
and settles after 11 iterations. **Contact history** shows the reference,
the learning pose and the settled endpoint with one camera and scale.

A relationship says that one material triangle is below another along the
supplied model direction `(-3, 0, 1)`. These are identities on the original
sheet, not temporary pieces of the drawing. The strip keeps one source-panel
id, 34 shared material vertices and 32 triangles. The [discovery note](local-contact-discovery.md)
explains the projected-overlap scan and its `0.03`-unit search distance.

`extendLocalReference` returns a proposed replacement for the private contact
history. First it checks the earlier relationships and refuses any *unknown*
pair already within numerical clearance or crossing. A new nearby pair can
supply its order only while its entire overlapping projection is separated
by more than clearance plus tolerance. The six witnesses in this example have
minimum gaps between `0.00112` and `0.00477` model units, well above the `1e-6`
clearance. The clearance is a numerical margin, not physical paper thickness.

Connected flat triangles share newly discovered partners so contact can slide
across a triangulation diagonal. Each observation finds those flat patches
again in its own pose: treating an originally flat sheet as one permanent patch
would miss its later self-contact. Existing relationships remain unchanged.
If A is below B and a new encounter puts B below C, the history also requires
A below C. Every newly implied relationship must have positive clearance
where its projections overlap, even outside the search distance. Cycles and
requirements that would separate shared material vertices are refused.

The solver's line search tries progressively smaller corrections. A proposed
history accompanies each trial, and only the accepted trial's history survives.
A rejected trial contributes no orders or audit event. The same history passes
through all four increasing penalty weights. Known negative gaps can still be
corrected during the early stages; requiring *all* old gaps to be positive
before learning a separated new neighbor would block that correction. The
established direction is never inferred again from a penetrated pose.

In the recorded result the largest relative edge-length error is `5.50e-8`.
The independent check inspects all 496 triangle pairs, including neighbors
excluded from separating forces: no crossings, unresolved overlaps, reversed
orders or uncheckable orders remain. The contact residual also meets tolerance.
All ten earlier gallery runs keep their exact meshes and measurements. Tests
replay the growth audit, check the original material and triangle connections,
retain order after separation, and refuse crossed first encounters, changed
material, contradictory implied orders and cycles.

These observations are numerical iterations, not a folding instruction sequence
or a continuous motion check. A pair could pass through another between sampled
poses; this increment does not bound that motion. The final all-pair check stays
necessary, especially for joined neighbors that cannot receive separating
forces. A fixed direction also cannot express every possible arrangement of
curved paper. This closes the finer strip's reference-coverage gap in
[#166](https://github.com/avalonalex/senbazuru/issues/166), while arbitrary
bending motion and general self-contact remain in
[#146](https://github.com/avalonalex/senbazuru/issues/146).
