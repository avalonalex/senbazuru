# The same bend on successively finer meshes

The [smooth-transition comparison](smooth-held-bend.md) left an apparent
contradiction: smoothing curvature increased the gap between two meshes, yet
the finer mesh was closer to its analytic cost. A reference with a known
answer lets us measure approximation error directly, before asking an
optimizer to choose a shape.

Keep the two common curves from that comparison fixed. The circular reference
has curvature `3.058080151255` and bend length `0.163868215857`; the smooth
reference has mean curvature `3.381591624734` and bend length `0.143022684385`.
Both reach the original grips using the same continuous paper length. Curvature
means how quickly the direction along the paper turns per unit length; the
smooth reference starts and ends with zero curvature.

The new ladder halves every material interval along the bend, starting with
columns `0, 1/16, 2/16, …, 1/2`. Five meshes have 64, 128, 256, 512 and 1,024
triangles across both panels. Their two width strips stay unchanged. The
previous uneven 120-triangle mesh is a separate reference point, not an extra
step in the ladder. No reference parameter is fitted per mesh, no grip is
copied back, and no material-equilibrium solve runs.

Each mesh has two constructions. **Samples** put vertices on the common curve;
straight triangle edges are shorter than the paper arcs they replace.
**Full-length segments** retain the sampled chord directions but restore each
segment's material length, allowing the outer grip to drift. Their angular
costs agree within roundoff, despite different geometry. Every spring still
uses the existing material coefficient `0.2` and the original triangle sizes
on the unfolded sheet. Increasing the number of springs does not increase the
material coefficient.

Run from the repository root:

```bash
stack run senbazuru-material-study -- --bend-refinement build/fold-material
```

Open `build/fold-material/bend-refinement.html`. Percentage errors below use
`100 * abs(measured - analytic) / analytic`, per unit-width panel. The fixed
analytic costs are `0.153247166460` for the circle and `0.196258506440` for the
smooth reference. They integrate squared curvature with the same material
coefficient; they are model costs, not physically calibrated joules.

| Triangles | Circular cost | Circular error | Smooth cost | Smooth error |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.125641304 | 18.0139% | 0.156778511 | 20.1163% |
| 128 | 0.139131537 | 9.2110% | 0.183683999 | 6.4071% |
| 256 | 0.146397130 | 4.4699% | 0.192761807 | 1.7817% |
| 512 | 0.149596247 | 2.3824% | 0.195331372 | 0.4724% |
| 1,024 | 0.151424713 | 1.1892% | 0.196020527 | 0.1213% |
| 120, uneven | 0.139131537 | 9.2110% | 0.183683999 | 6.4071% |

All costs approach from below. On these levels, halving spacing roughly halves
the circular error; at finer levels it roughly quarters the smooth error.
That is an observed trend, not a convergence theorem or a claim about arbitrary
triangulations. The 120- and 128-triangle meshes agree because their only
extra column lies in the straight outer section. Agreement there alone does
not demonstrate an accurate bend.

Full-length meshes preserve every material edge to relative error at most
`6.22e-15`. At 1,024 triangles their circular/smooth outer-grip drifts are
`9.64967e-7` / `1.23817e-6` sheet lengths, down from
`0.000236690` / `0.000308144` on the coarse meshes. Matching vertices move
`2.89555e-6` / `3.71111e-6` between the last two levels. This does not bound
surface movement between vertices. Sampled vertices do not move at all under
refinement, while their chords and spring costs do change.

The finest sampled circle has relative edge error `5.94574e-6`, inside the
existing `1e-5` numerical cap; the sampled smooth reference remains outside
at `1.63495e-5`. Both remain diagnostic approximations. Every reference retains
one connected sheet, only crease vertices 0/1/2 shared between layers, exactly
zero inner-grip movement and exact zero touching gaps over all triangles.
Original crease error stays below `2.45e-16` radians. Length, passive, original
crease and imposed costs stay separate; no acceptance threshold changes.

This supports the bending rule on these two fixed, width-independent profiles.
It does not settle the old solved 8.99% difference, equilibrium force response,
separation, real-paper stiffness or a flexible folding path. A useful next
control would compare local refinement near curvature transitions with uniform
refinement at equal triangle counts, keeping these curves and diagnostic
errors fixed. That tests where extra triangles help before a larger solve.

Independent reconstruction from the exports checks 24 FOLDs, 14,776 edges,
10,472 springs and 20 comparisons. Simpson integration separately checks the
smooth positions; normals and material triangle heights reproduce spring costs.
The two layers' matching triangulations and monotone profiles independently
establish zero contact gaps everywhere. The earlier coarse, uneven and fully
refined controls reproduce within `1e-14` sheet lengths. All 28 SVGs parse;
all 48 browser selections work; 733 archived assets remain unchanged.

Tracked in [#295](https://github.com/avalonalex/senbazuru/issues/295), continuing
[#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).
