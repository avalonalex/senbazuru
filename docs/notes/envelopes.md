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

Roadmap item 3 is laying out a multi-frame FOLD file as a numbered grid of
steps. That is precisely the problem envelopes solve, and `diagramExtent` is the
crude fixed-box version of the same idea.

## References

- Brent Yorgey, "Monoids: Theme and Variations (Functional Pearl)", *Haskell
  Symposium*, 2012.
- The `diagrams` documentation on envelopes and traces:
  <https://diagrams.github.io>
