# Envelopes: how to place two drawings side by side

`Senbazuru.Diagram` stores `diagramExtent` as a bounding box, so that every step
of a sequence can be drawn at one shared scale and the model does not appear to
grow and shrink between figures.

A bounding box is a blunt instrument for this. Placing two shapes adjacent so
they touch but do not overlap requires knowing their extent *in the direction of
placement*, not their axis-aligned box. For anything rotated or diagonal, a box
wastes space and the layout looks loose.

The `diagrams` library answers this with an *envelope*: not a rectangle, but a
function from a direction to how far the diagram extends that way. Once you have
that, composition becomes a genuine `Monoid` -- overlay is `<>` -- and
operations like `hcat` and `vcat` place things by querying envelopes rather than
by arithmetic on boxes.

It is worth reading even if you never use the library. It is a clean case of
choosing an abstraction -- a support function -- that makes a fiddly layout
problem fall out as algebra.

## Why it matters here

Laying a multi-frame FOLD file out as a numbered grid of steps is precisely the
problem envelopes solve. `Senbazuru.Diagram.Layout` does it the crude way — one
shared bounding box per figure, arranged on a fixed pitch — and that is enough
for a folding sequence, because every figure is a sheet of paper seen from the
same angle and the boxes are all much the same shape.

Where it will start to cost is the case a book actually uses: figures at
different angles, or a step turned on its side to show a flap, laid out so they
touch without overlapping. A bounding box wastes space on anything diagonal and
there is no way to ask it for the extent *in the direction of placement*. That
is the question an envelope answers, and the point at which this note stops
being background reading.

Worth noting that `diagramExtent` is not simply the crude version of an
envelope: it is deliberately *not* the drawing's own bounds. It is pinned to the
sheet of paper so that a sequence keeps one scale, and an envelope derived from
each figure's contents would lose exactly that.

## References

- Brent Yorgey, "Monoids: Theme and Variations (Functional Pearl)", *Haskell
  Symposium*, 2012.
- The `diagrams` documentation on envelopes and traces:
  <https://diagrams.github.io>
