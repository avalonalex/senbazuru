# Resolve the middle of the bend

The [transition-window study](transition-refinement.md) improved bending-cost
accuracy by placing more triangles near the flat-to-curved joins. But its
full-length polygons usually missed the outer grip by more, and its sampled
edges shortened more. This comparison gives the middle of the bend priority
too, keeping the same triangle counts and two fixed reference curves.

All three layouts begin with material columns `0, 1/16, …, 1/2`: lines across
the original unfolded paper, giving 64 triangles over two touching panels.
Uniform refinement halves every interval. Join-window refinement uses density
four within `1/32` sheet length of each join and one elsewhere. The new
whole-bend rule uses density four from `1/8` to `1/8 + A`, where `A` is the
fixed curved length, and one elsewhere. Both concentrated rules bisect the
interval with the largest integrated density and break ties toward the shared
crease. The whole bend and the windows have different widths; equal triangle
counts, not equal integrated density, set the comparison budget.

The new rule was recorded in
[#301](https://github.com/avalonalex/senbazuru/issues/301) before evaluation.
No cost measurement tunes the density or its extent. Every grid retains its
preceding level and the original coarse columns. The two width strips,
material coefficient `0.2`, shared crease, inner holds and outer-grip targets
are unchanged. The reference curves are those of the
[fixed refinement ladder](fixed-bend-refinement.md), without another fit.

Run from the repository root:

```bash
stack run senbazuru-material-study -- --whole-bend build/fold-material
```

Open `build/fold-material/whole-bend.html`. It compares all three layouts at
five budgets, for each curve and each construction. **Samples** place vertices
on the curve but shorten straight edges. **Full-length segments** restore the
sampled chord lengths to the material lengths while retaining their directions;
the outer grip can then drift. Their angular costs agree within roundoff,
although their geometry errors differ. Every result remains a prescribed
diagnostic, not an equilibrium found by the material solver.

Cost errors below are `100 * abs(measured - analytic) / analytic`, per panel.
The analytic cost integrates squared curvature, meaning squared turning per
material length, with the same material coefficient. Its values remain
`0.153247166460` for the circle and `0.196258506440` for the smooth reference.
These model costs are not calibrated joules.

| Triangles | Circle uniform | Circle joins | Circle whole | Smooth uniform | Smooth joins | Smooth whole |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 18.0139% | 18.0139% | 18.0139% | 20.1163% | 20.1163% | 20.1163% |
| 128 | 9.2110% | 4.4699% | 7.7434% | 6.4071% | 3.0689% | 1.8399% |
| 256 | 4.4699% | 2.3824% | 3.9384% | 1.7817% | 0.9581% | 0.4995% |
| 512 | 2.3824% | 1.1892% | 1.7088% | 0.4724% | 0.3431% | 0.1289% |
| 1,024 | 1.1892% | 0.5912% | 0.8875% | 0.1213% | 0.0960% | 0.0308% |

Whole-bend placement improves cost accuracy over uniform spacing at every
refined budget. It also beats the join windows for the smooth curve, but not
for the circle. The circle's curvature changes abruptly at its joins, whereas
the smooth curve has zero curvature there. The result supports retaining
different geometric and angular error measures; it does not select a
universally best placement rule.

The geometric tradeoff improves. At every refined budget, whole-bend grip drift
and sampled edge shortening are smaller than with either earlier rule. At
1,024 triangles:

| Measurement | Circle uniform / joins / whole | Smooth uniform / joins / whole |
| --- | --- | --- |
| Full-length outer-grip drift, sheet lengths | `9.64967e-7 / 2.35878e-6 / 2.41173e-7` | `1.23817e-6 / 4.21517e-6 / 3.09602e-7` |
| Largest sampled relative edge error | `5.94574e-6 / 2.37828e-5 / 1.48644e-6` | `1.63495e-5 / 6.51659e-5 / 4.08914e-6` |

Both finest whole-bend sampled meshes now meet the unchanged `1e-5` length
cap; the smooth 512-triangle mesh still fails it. Full-length whole-bend edges
stay within `1.2e-14` relative error, but their missed grips are not copied back.
Passing a length cap alone does not make these shapes equilibria.

All three pairwise comparisons cover the whole sheet at the same material
locations, using the union of their columns. Between consecutive columns the
profiles are straight and repeat unchanged across width, so the largest
positional difference occurs at a column in that union. At 1,024 triangles,
full-length uniform/whole differences are `5.83282e-6` / `9.63400e-6` sheet
lengths for the circle/smooth references. Joins/whole differences are
`2.33312e-5` / `3.84849e-5`. These are comparisons between layouts, not an
error bound against arbitrary real paper or a continuous folding path.

Independent reconstruction checks all 60 FOLDs, 41,784 material edges, 29,640
springs and 60 pairwise comparisons. It regenerates the exact density grids,
integrates the smooth curve separately with Simpson's rule, and recomputes
spring costs from triangle normals and original material heights. The two
layers retain identical triangulated positions with opposite winding,
establishing exact zero touching gaps everywhere while sharing only crease
vertices 0/1/2. Inner holds do not move; original crease error stays below
`2.45e-16` radians. All 74 SVGs parse, all 40 browser selections work, and regenerating the previous gallery
leaves 945 archived assets byte-for-byte unchanged.

This completes the prescribed comparison, not #195's solved-response criteria
or the old solved 8.99% difference. A useful next step is one small held-panel
equilibrium comparison using whole-bend placement at two modest budgets, with
the uniform controls, holds, contact policy and material weights fixed. Check
solver convergence, geometry and separate energies before adopting a default
mesh policy. The reference curves can inform that experiment; their present
cost agreement cannot establish how the paper will settle.

Tracked in [#301](https://github.com/avalonalex/senbazuru/issues/301), continuing
[#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).
