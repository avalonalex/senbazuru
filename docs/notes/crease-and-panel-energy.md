# Choosing a shape with crease and panel energy

Preserving a triangle's three lengths fixes its shape, but its neighbor can
still rotate around their shared edge. Lengths and contact therefore leave
many possible folded sheets. An angular spring supplies a preference: turning
away from its rest angle costs energy. A crease is a deliberately folded line;
its rest angle can be nonzero. The uncreased paper between creases is a panel;
its internal triangle edges prefer zero bend.

`study/fold-material/FoldBending.hs` applies that distinction to the original
single- and double-fold controls. It uses `Origami.Surface`'s material mesh:
shared vertex ids remain shared, and positions move without changing the
original sheet coordinates. Creases are classified at `u = 0.5`, and for the
double fold also `v = 0.5`, on that original unit square. This fixture-specific
classification remains an adapter for those fixtures. The later
[shared-crease adapter](crease-identity-through-refinement.md) instead follows
source edge ids through refinement for diagonal and kite examples.

Each shared edge contributes `E = k (θ − θ₀)² / 2`. Here `θ` is the signed
angle between its triangles, `θ₀` the preferred angle, and `k` its stiffness.
Angles are in radians; zero is unfolded and positive is a valley, following
FOLD's [angle convention](../glossary.md). The error uses the equivalent angle
nearest the target. That avoids a discontinuity at a nearly closed crease,
but does not remember a folding path through ±180°.

We assign a crease segment stiffness `κ l`, where `l` is its material length.
Dividing one straight crease into more segments therefore leaves its total
energy unchanged when their angles agree. Within a panel we use `B l / h`,
where `h` is the mean material height of the two triangles above their common
edge. This weights the change of angle across an area of paper. `κ = 1` and
`B = 0.2` or `5` are illustrative values, not properties measured from paper.
The general separation of stretching, panel bending and crease folding follows
[Filipov et al.'s bar-and-hinge framework](https://paulino.scholar.princeton.edu/document/1561).
Our simple triangle weighting does not implement that paper's calibrated panel
law or establish convergence to a continuum material as the mesh is refined.

`FoldRelaxation.relaxBending` adds these angular residuals to the existing
length and packet-contact solve. Starting with a huge length penalty makes
even one rigid fold crawl: a straight step in the direction of rotation
changes lengths at second order. We first solve with length penalty `10²`,
then `10⁴`, `10⁶`, and `10⁸`, each beginning at the preceding result. Contact
uses 100 times the current length penalty. These weights control numerical
constraint enforcement; they are separate from `B` and `κ`.

Only the final stage can establish success: relative edge-length error must
be at most `10⁻⁵`, reversed packet gaps at most `10⁻⁷` sheet units, and the
largest **full proposed correction** at most `10⁻⁷` sheet units. The inner
linear solve must also finish with a finite residual below the larger of
`10⁻⁶` or `10⁻⁸` times its initial residual. Near equilibrium, large length
forces cancel angular forces; a purely relative test on their tiny remainder
asks for accuracy floating-point subtraction cannot supply. A numerical
movement penalty of `10⁻³` improves conditioning without becoming part of the
paper's energy. A line search
can make a failed step arbitrarily short, so its accepted displacement alone
would be an unreliable stopping test. Each stage has a 100-iteration limit;
exhaustion remains a failed convergence result. Recorded intermediate meshes
are numerical attempts, not a physical motion or folding instructions.

Run the compiled example from the repository root:

```bash
stack run senbazuru-material-study -- --bending build/fold-material
```

On the 81-vertex, 128-triangle unit sheet, the single fold settles at its
requested 150° angle. Maximum relative edge error is about `5.2 × 10⁻⁹`;
panel energy is below `2 × 10⁻¹⁶`. Its positions are solved, not written from
the known rigid answer. Both double-fold runs ask every crease for 170° in
its assigned direction. Their final measurements are:

| Panel stiffness | First crease magnitude | Largest internal-edge bend | Relative edge error | Crease energy | Panel energy |
| --- | --- | --- | --- | --- | --- |
| 0.2 | 173.81–177.16° | 2.017° | `7.47 × 10⁻⁷` | 0.005364 | 0.002750 |
| 5 | 179.30–179.71° | 0.205° | `2.82 × 10⁻⁷` | 0.013712 | 0.000726 |

Both pass the known packet-order check. Stiffer panels bend less but miss the
crease targets by more. The preferred angles are therefore an input, not a
promise that every crease can achieve them independently on connected paper.
The viewer reports achieved ranges, both energies and principal strains
(the most compressed and stretched material directions), alongside the checks.

This is a local equilibrium experiment on nearly flat, zero-thickness packets.
It does not certify general self-contact, contact inside a panel, collision-free
motion, a unique/global energy minimum, or behavior of a specified paper stock.
The shared-crease adapter now supplies explicit rest-angle controls and
independent triangle contact diagnostics. Contact forces that also cover open
panels remain the next extension. Physical
thickness can be added separately; it was not necessary to distinguish these
shapes. Work is tracked in [#150](https://github.com/avalonalex/senbazuru/issues/150),
following [#114](https://github.com/avalonalex/senbazuru/issues/114).
