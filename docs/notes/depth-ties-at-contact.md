# When touching layers share a depth value

The corrected double-fold mesh can meet its contact tolerance and still show
orange triangles through the cream underside. The geometry check uses double
precision; the viewer sends single-precision coordinates to a finite depth
buffer, which decides which triangle is nearest at each pixel. Layers separated
by less than that precision can trade places on screen as the camera turns.

The underside view at yaw −3 radians and pitch −1.3 radians reproduced patches
at both crease ends. Changing the triangle depth offset from `(1,1)` to `(0,0)`
did not remove them. The tested browser reported a 24-bit depth buffer. A tiny
depth adjustment using the already checked packet order removed the patches
without changing any mesh coordinates.

A second underside view (yaw −0.785, pitch −1.15) exposed a residual patch
with an eight-increment guard. Double-precision projection through that corner
found overlapping triangle depths differing by less than 1e-11 model units.
Removing the slope-dependent polygon offset did not fix it; a 64-increment guard
did. This distinguishes a numerical tie from a sizeable geometric intersection.

Short lines remained after that fix. They survived disabling crease strokes,
and a magnified view with flat red/white face colours isolated them from lighting.
The slope-dependent outline offset was pushing steep triangles farther back
than their neighbours, exposing thin strips of the other side. Replacing
`polygonOffset(1,1)` with `(0,1)` removed those strips: surfaces still leave a small
constant depth allowance for ink, but the offset no longer changes their relative
depths. Both corrections are needed in the reproduced corner view.

The study now breaks these near-equal depth ties by 64 depth-buffer increments
per layer, projected along the packet's vertical axis. Looking underneath reverses
which layer wins. Boundary and crease strokes receive their incident panel's
adjustment too, otherwise strokes can show through a surface that has moved in
depth. Screen coordinates, exports and material measurements remain unchanged.

This is a display convention for these zero-thickness packets, not extra paper
thickness or a better contact solver. It is enabled only when all triangles were
checkable and the maximum ordering violation is below the declared contact
tolerance. Failed checkpoints and the untested kite/blintz cases receive no
adjustment. Their intersections must remain available for inspection.

The contact checker and display data share `FoldContact.packetLayer`; duplicating
that order in the viewer would let a drawing hide a disagreement with the solver.
See [the study](../../study/fold-material/README.md) for its geometric limits.

This guard was checked on the four-layer control, not on arbitrary stacks. More
layers need explicit contact/visibility tests; growing the bias is not a substitute
for modelling their contact. At iteration 5, the unadjusted viewer still exposes
the crossings reported by its 44 violating triangle pairs.
