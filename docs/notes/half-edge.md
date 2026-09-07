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

This is the algorithm `Senbazuru.Fold.Faces` runs. `faces_vertices` is optional
in FOLD and absent from most real files -- no `.cp` or `.opx` can express one at
all -- so the faces are traced from the creases, and everything that needs paper
rather than lines waits on that: filling, folding, and the layer order.

Senbazuru does the traversal with angles rather than combinatorially, because
it does not have the ingredient the note above describes. `vertices_vertices` is
specified as counterclockwise ordered, and would give the rotational order for
free -- but it is one of the keys senbazuru does not decode, and a file need not
carry it. Sorting each vertex's creases by `atan2` reconstructs the same order
from the coordinates, which every file does carry.

The rule that comes out of it is worth stating in one line, because it reads as
a mistake: **from the half-edge `u→v`, turn at `v` onto the next crease
clockwise from `v→u`.** Clockwise, to trace a face that comes out
counterclockwise. Turning the way the face winds traces the same rings
backwards.

## References

- de Berg, Cheong, van Kreveld & Overmars, *Computational Geometry*, 3rd ed.,
  Springer, 2008 -- the chapter on the doubly-connected edge list.
- Lutz Kettner, "Using generic programming for designing a data structure for
  polyhedral surfaces", *Computational Geometry* 13(1), 1999.
- The FOLD specification, on the ordering guarantee for `vertices_vertices`.
