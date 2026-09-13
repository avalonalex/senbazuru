# A filled polygon has no first corner

The first bird-petal CI run failed its SVG golden on Linux while passing on
macOS. Its first difference was a four-corner filled region: one output wrote
`A B C D`, the other `B C D A`. Closing either list draws the same polygon.
Small differences in trigonometry had changed which corner the clipping
algorithm returned first, even though all printed coordinates were identical.

`Render.Svg.closedPathData` now chooses the smallest cyclic rotation of the
formatted point strings. **Cyclic rotation** moves a prefix to the end while
keeping the order around the boundary: `A B C D` can become `C D A B`, but not
`A C B D`. Comparing complete rotations also resolves ties when two distinct
corners round to the same printed point.

Formatting must happen before choosing the start. Comparing raw coordinates
would allow a difference too small to print to choose different output bytes.
The text ordering is merely a deterministic choice; it does not claim that the
chosen corner is the geometrically leftmost one.

This changes serialization only. Winding, coordinates, the order of subpaths
within a fill, and the painting order of separate shapes are preserved. Open
strokes and arrow paths keep their meaningful endpoints. Tests exercise every
cyclic start, reversed winding, and corners that round to the same point. The
updated golden files were compared as complete SVG trees after allowing only
cyclic rotation of closed filled subpaths: every other attribute, coordinate,
text node and child order remained identical.
