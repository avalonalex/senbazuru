# Folding: one rigid transform per face

Given a crease pattern and a fold angle for every crease, where do the vertices
end up in space?

Terms used here are defined in [../glossary.md](../glossary.md); the ideas
behind them are in [../fold-primer.md](../fold-primer.md).

Paper does not stretch, so **every face moves rigidly** — it may rotate and
translate, never bend or scale. The whole folded state is therefore captured by
one rigid transform per face. Get those and vertex positions are a lookup:
apply the matrix of any face containing the vertex.

```
foldedPositions(creasePattern, foldAngles, rootFace):
    M[rootFace] = identity

    for (parent, child, crease) in bfsSpanningTree(faceAdjacency, rootFace):
        p, q  = endpoints of crease          -- in FLAT coordinates
        axis  = normalize(q - p)
        R     = translate(p) · rotate(axis, foldAngle[crease]) · translate(-p)
        M[child] = M[parent] · R

    for each vertex v:
        folded[v] = M[any face containing v] · flat[v]
```

The **spanning tree** walks the face-adjacency graph, reaching every face
without revisiting one; the **root face** is held still at the identity, and
everything else is placed relative to it — a choice that moves the model in
space but never changes its shape. *Flat coordinates* means positions as the
crease pattern gives them, before folding.

One pass over the faces and one over the vertices. Rotation about an arbitrary line is the usual
translate-to-origin / rotate / translate-back sandwich, with Rodrigues' formula
for the rotation about a unit axis:

```
R(n, θ) v  =  v cos θ  +  (n × v) sin θ  +  n (n · v)(1 − cos θ)
```

## The line that looks wrong

`M[child] = M[parent] · R`, with `R` built from the crease **as it sits in the
flat pattern**. But in folded space the child rotates about the crease where it
has *ended up*, which depends on `M[parent]`. Surely you need the folded line?

You do not, and the reason is worth keeping. Sandwiching a rotation between a
rigid motion and its inverse — written `M R M⁻¹`, and called *conjugation* —
gives the same rotation about a moved axis: if `R` turns about line `L`, then
`M R M⁻¹` turns through the same angle about `M(L)`. So

```
M[child] = R_folded · M[parent]
         = (M[parent] · R_flat · M[parent]⁻¹) · M[parent]
         = M[parent] · R_flat
```

The inverse cancels: every rotation is computed from the original flat
coordinates, with no inversions and no axes re-derived from accumulated results.

## Two things to watch

**Sign.** Reversing the axis (`q - p` versus `p - q`) negates the angle, and
FOLD's convention — negative for mountain, positive for valley — is relative to
the direction a face's vertices are listed in, its *winding*. Orient creases
consistently or half the model folds backwards.

**The tree cuts loops.** Around an interior vertex the faces form a cycle, which
a tree cannot. So a vertex shared by several faces gets a position from each of
them, and they agree only under a condition the tree never checks. See
[fold-angles-are-the-state.md](fold-angles-are-the-state.md).

## The flat case is much easier

When every angle is exactly ±180°, rotating about a line *in the plane* by 180°
**is reflection in that line**. The matrices collapse to 2D reflections, the
result never leaves the plane, and no 3D rotation appears at all. That is why a
traditional crane — which folds flat — is reachable long before a shaped one
with its wings spread.

## References

- Belcastro & Hull, "Modelling the folding of paper into three dimensions using
  affine transformations", *Linear Algebra and its Applications*, 2002.
- Tachi, "Simulation of Rigid Origami", *4OSME*, 2009.
