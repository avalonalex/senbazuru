# A crease is a hinge with a rest angle and a radius

Terms used here are defined in [../glossary.md](../glossary.md).

This records an early material-study hypothesis. The later
[double-fold experiment](two-bends-need-more-than-radii.md) showed that radius
and connectivity alone do not preserve material. Current rendering uses the
[shared surface](connected-paper-surface.md) and does not infer a physical
crease radius from a display layer number.

Everything senbazuru draws treats a crease as a line where two flat planes
meet at a fold angle. That is the right model for deciding where the paper
goes. It is the wrong model for drawing what the paper looks like once it is
there, and this note is about what a crease physically is, reduced to the two
numbers a renderer needs: how far open a pressed fold sits, and how tight it
can bend. Three bodies of work each pin one piece, and none of them is origami
literature.

## A crease is a torsional hinge with a rest angle

Lechenault, Thiria and Adda-Bedia creased strips of Mylar by loading a hand
pre-crease with a 10 kg weight for twenty minutes, let them relax for an hour,
and measured what they did. The model that fits is two flat panels joined by a
**torsional hinge**: the moment needed to hold the panels at an angle `φ` is
proportional to `φ − φ₀`, where `φ₀` is the **rest angle** the crease returns
to when nothing is loading it.

Two facts from the measurements matter here.

- **The rest angle is not zero, and it does not depend on thickness.** Across
  sheets from 0.15 to 0.5 mm the panels settled between 30° and 40° apart, with
  no significant dependence on thickness. The rest angle is set by the material's yield
  stress, the load past which it stops springing back, not by how thick it is. Mylar is far springier than
  paper, so the number itself does not transfer; the thickness-independence
  does.
- **There is a length that decides whether a load opens the crease or bends
  the panel.** Bending a panel costs its bending rigidity `B`; opening the
  crease costs the hinge rigidity `κ`. Their ratio `L* = B/κ` is a length, and
  for their sheets it scaled as about **200 thicknesses**. A panel shorter than
  `L*` stays flat and the crease opens; a panel longer than `L*` bends and the
  crease stays put.

That second fact has a consequence for a diagram. Origami paper is about
0.1 mm thick, so `L*` is about 2 cm. The panels of a hand-sized model are
longer than that. So on the models senbazuru draws, **the flanks of a fold are
curved, not flat**, which is why a fillet joined to two flat planes will still
read as slightly stiff, and why the fully faithful shape is an elastica problem, the curve a bent
elastic strip takes — the boundary [#64](https://github.com/avalonalex/senbazuru/issues/64) draws.

Benusiglio, Mansard, Biance and Bocquet add that the rest angle is not even a
constant: a fold left alone opens *logarithmically* with time, which they
attribute to plastic creep under the stored elastic energy, and faster in humid
air. A folded model photographed a day later is more open than the same model
photographed at once.

## A fold has a minimum radius, and it is about a thickness

Rao, Tawfick, Shlian and Hart rolled folds into three papers — abaca, Tyvek and
a metal-fibre laminate — under controlled force and measured the radius. The
radius falls as a power law with the load, with one exponent before a
**plastic hinge** forms and a steeper one after, and then flattens out: past
the plastic hinge more force barely tightens the fold. Their tightest fold,
Tyvek held in a binder clip for an hour, had a radius of 0.14 mm at a surface
strain of 0.4.

For a thin sheet bent to radius `R` the strain at its surface is about
`t / 2R`, so that measurement puts the minimum radius at roughly **1.25
thicknesses**. That derivation is ours, not theirs, and it is the order of
magnitude that matters: a fold pressed as hard as a hand can press still has a
radius, and it is about the thickness of the paper.

## A fold around other layers has a radius set by what it wraps

The third source is not a paper. Bookbinders have compensated for this geometry
for a century under the name **creep** (also *shingling* or *push-out*): fold a
stack of sheets into a signature and the inner sheets stick out past the outer
ones, because each outer fold has to go round every sheet inside it. Prepress
software shifts the page images inward to hide it, and the correction it
applies is the caliper (the printer's word for thickness) times the number of
sheets wrapped — Kodak's Preps
documents it as `4 × t × (S/4 − 1)` for `S` pages in the signature.

That is the packing argument
[#114](https://github.com/avalonalex/senbazuru/issues/114) makes, in
industrial use: a fold wrapping `n` layers has a radius of about `n × t / 2`,
and the layers it joins sit about `n × t` apart.

## What this settles for a renderer

The two numbers separate cleanly, and that is the useful result.

- **The radius is geometry.** It is set by how many layers the fold wraps,
  with a floor of about one thickness for a fold wrapping nothing. Both inputs
  were initially approximated by layer numbers and a display-spacing option.
  That option has been removed: physical thickness is now separate surface
  data, and a display layer number does not determine how much material a
  crease wraps.
- **The rest angle is material.** It is a constant of the paper, independent
  of thickness and of what the fold wraps. For a drawing, a small fixed opening
  is defensible and there is nothing in the file to derive it from.

So when a real folded sheet opens by *different* amounts at different folds —
the thing the fan mock-up for #114 could not reproduce — that comes from the
radius growing with the layers wrapped, not from the hinges resting at
different angles. The outer fold of a quarter fold wraps three thicknesses and
the inner folds wrap one, and that 3:1 is the whole of the difference.

What this does not settle is the shape of the flank between the hinge and the
next crease, which on a hand-sized model is a curve. Drawing it as flat is a
known approximation with a known cause, and it is where the line between
geometry and mechanics runs.

## References

- Lechenault, Thiria, Adda-Bedia, *Mechanical Response of a Creased Sheet*,
  Phys. Rev. Lett. 112, 244301 (2014). The hinge model, the rest angle, and
  `L* ≃ 200h`. https://arxiv.org/abs/1404.1243
- Rao, Tawfick, Shlian, Hart, *Fold Mechanics of Natural and Synthetic Origami
  Papers*, ASME IDETC/CIE 2013, DETC2013-13553. The minimum fold radius and
  the two power laws. https://dspace.mit.edu/handle/1721.1/119371
- Benusiglio, Mansard, Biance, Bocquet, *The anatomy of a crease, from folding
  to ironing*, Soft Matter 8, 3342 (2012). The logarithmic opening with time.
  https://pubs.rsc.org/en/content/articlelanding/2012/sm/c2sm07151g
- Kodak Preps documentation, *Shingling the page images for creep
  compensation*. The bookbinder's formula.
  https://workflowhelp.kodak.com/display/PREPS75/Shingling+the+page+images+for+creep+compensation
- [the-puff-is-a-drawing.md](the-puff-is-a-drawing.md) surveys what the full
  mechanics would cost, and [paper-thickness.md](paper-thickness.md) is where
  the old display-spacing approach was retired.
