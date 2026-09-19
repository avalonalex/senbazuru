# Where length refinement changes bending costs

The [length comparison](fractional-band-length.md) leaves a question: why do
both band rules change shape and energy when the mesh goes from `2×1` to
`4×1`? Read its twelve saved endpoints without solving again:

```bash
stack run senbazuru-material-study -- --bend-locations \
  build/fold-material/boundary-length build/fold-material
```

Open `bend-locations.html` on the local study server. A panel is a region of
paper allowed to bend between its mesh triangles; the [glossary](../glossary.md)
defines the material terms. Material coordinates locate each spring on the
unfolded sheet. Write `d` for distance from the shared crease: the held strip
ends at `1/8`, the imposed upper band runs from `1/8` to `7/16`, and the
outer edge at `1/2` is also held. Passive springs resist panel bending;
imposed springs ask the upper band to curve further. The original closed
crease has its own spring and is accounted for separately.

The gallery assigns each spring's entire cost to its material edge midpoint.
It separates the held strip, its boundary line, band interior, band-end line
and outer region. That is discrete accounting, not an estimate of energy
per paper area: a finer mesh adds edges inside these fixed regions. Maps
colour energy divided by material edge length on a common scale. Cumulative
plots and region tables include every passive or imposed spring, including
lengthwise and diagonal edges. Their totals reproduce the prior report.

For edges parallel to the shared crease, the turn profile divides the signed
angle by the mean distance to the neighboring material columns: `1/16` on
`2×1`, `1/32` on `4×1`. It shows the width-weighted mean and full range.
Without this normalization, sharing a bend among more edges could look like
less bending. This is a discrete angular rate, not a recovered smooth
curvature field. The upper and lower panels use opposite material
orientations, so compare the same panel across meshes. Raw angles and all
1,552 spring records remain available in `bend-locations/checks.json`.

The matched control's passive cost rises from `0.0994134` to `0.108684` on
each panel, or 9.33%. Its region changes are:

| Region | Signed energy change |
| --- | ---: |
| Held strip | 0 |
| Held-strip boundary | −0.00432485 |
| Band interior | +0.0146010 |
| Band end | −0.00118852 |
| Outer region | +0.000182904 |
| Total | +0.00927054 |

Here “band interior” names the same material region even though the matched
control has no band load. Its extra cost is mainly in the interior, offset
by smaller costs on the boundary lines. A growing energy total does not mean
that the existing boundary springs are becoming more costly.

The loaded upper panel adds a more distinctive response:

| Region | Original-rule change | Fractional-rule change |
| --- | ---: | ---: |
| Held-strip boundary | −0.0105568 | −0.00617869 |
| Band interior | +0.0370960 | +0.0317922 |
| Band end | −0.00268077 | −0.00189112 |
| Outer region | +0.0350484 | +0.0320603 |
| Total | +0.0589067 | +0.0557827 |

On `2×1`, the last transverse bend is at `7/16`; there is none inside the
outer strip. `4×1` introduces one at `15/32`, between the band end and the
held outer edge. Both loaded rules turn that new bend in the opposite
direction to the preceding band bends. The following values are signed
turn divided by material spacing, in radians per sheet length:

| Upper panel, 4×1 | At band end, 7/16 | New bend, 15/32 | Energy at new bend |
| --- | ---: | ---: | ---: |
| Matched holds | −0.400178 | −0.175081 | 0.000104444 |
| Band, original | −1.15658 | +3.18534 | 0.0323157 |
| Band, fractional | −1.07692 | +3.04035 | 0.0293897 |

The new bend alone carries about 55% and 53% of the respective net upper
passive-energy increases. These percentages describe the discrete springs;
the coarse mesh has no equivalent edge to subtract. The region table must
not be read as continuous energy appearing from nothing. Lengthwise and
diagonal bends still matter: the fractional upper panel's total on those
edges changes from `0.0000742411` to `0.00363141` and is included throughout.

The imposed band costs decrease by `0.0564951` under the original rule and
`0.112001` under the fractional rule. The original decrease is mostly in
the interior (`−0.0398023`), with a smaller band-end decrease (`−0.0198098`)
and a held-boundary increase (`+0.00311696`). The fractional decrease includes
both boundary lines (`−0.0229548` and `−0.0530986`) and the interior
(`−0.0359474`). These measure different objectives, so their magnitudes
cannot rank the two rules as material models.

Contact-off controls show a similar opposite turn at the new outer bend
(`+3.24170` original, `+2.99717` fractional). Their lower passive-energy
changes reproduce the matched control within `2.9e-9`. Contact therefore
is not necessary for this outer-bend pattern to appear in the saved upper
panel, but these crossing shapes remain invalid. This is an observation
about endpoints, not a causal proof about the optimizer or real paper.

Before measuring, the reader verifies material coordinates, triangulation,
shared vertex identities, holds, source-panel identities and retained layer
orders against the authored fixture. It rechecks lengths, the original
crease, exact directional gaps and independent triangle contact. Historical
convergence remains separate: eight constrained endpoints are eligible and
four contact-off endpoints stay diagnostic. All twelve fresh measurement
reports match the originals; the source report and twelve FOLDs are copied
byte-for-byte. There is no optimizer, contact repair or coordinate edit in
this command. An independent calculation from exported coordinates checks
all spring angles, material stiffnesses, energies, normalized turns and
region sums. Analytic cylinder, accounting, off-axis bend and input-rejection
tests need no equilibrium solve. All 1,502 tests pass in a cold warning-free
build; formatting, HLint 3.10 and JavaScript checks pass. All 24 gallery
selections and 84 SVG assets are checked, including zero-load and diagnostic
views. A modified saved cost is refused before export.

The useful next experiment is to isolate resolution of the short outer strip
from refinement of the rest of the panel, with the same holds, band,
contact-on/off controls and acceptance caps. That can test whether the newly
available reverse bend drives the loaded shape change. The matched-control
interior change remains a separate question. Do not infer convergence from
these maps or promote either rule to the default: tighter-solve confirmation,
`4×2`, physical calibration, the illustration decision and a checked flexible
route remain open under [#195](https://github.com/avalonalex/senbazuru/issues/195).
