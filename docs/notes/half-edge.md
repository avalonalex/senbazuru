# Half-edge structures, and why FOLD is already halfway there

FOLD stores a planar graph as parallel arrays. That is fine for drawing edges
and useless for the questions algorithms actually ask: what is the next edge
counterclockwise around this face? Which face is on the other side of this edge?

A *half-edge* structure -- also called a doubly-connected edge list -- answers
both in constant time. Each undirected edge becomes two directed half-edges
pointing opposite ways. Each half-edge knows four things: its twin, its origin
vertex, the face on its left, and the next half-edge around that face. Walking a
face is then following `next` until you arrive back where you started.

The pleasant part is that FOLD was designed with this in mind. `vertices_vertices`
is specified as *counterclockwise ordered* around each vertex, and that
rotational order is precisely the ingredient the construction needs -- it is
what lets you identify the next half-edge combinatorially, with no geometry and
no angle computation at all.

## Why it matters here

`Senbazuru.Diagram` currently has one shape constructor, `Polyline`. Drawing
paper as paper rather than as a wireframe needs filled polygons, which needs
face traversal. A folded form needs more still: which face is adjacent to which,
and which is on top -- see [layer-ordering.md](layer-ordering.md).

## References

- de Berg, Cheong, van Kreveld & Overmars, *Computational Geometry*, 3rd ed.,
  Springer, 2008 -- the chapter on the doubly-connected edge list.
- Lutz Kettner, "Using generic programming for designing a data structure for
  polyhedral surfaces", *Computational Geometry* 13(1), 1999.
- The FOLD specification, on the ordering guarantee for `vertices_vertices`.
