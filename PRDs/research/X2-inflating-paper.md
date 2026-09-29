# X2. Inflating a paper pillow two ways

Experiment X2, run 2026-09-28 against `main` at `83fc960`, in a scratch
directory; nothing in the repository was changed. Scripts are in
[`scripts/X2-inflation/`](scripts/X2-inflation/). The verification pass
([V](V-verification.md), clusters V2, V3 and V5) re-ran the cheaper cases; its
corrections are applied and marked **(V)**. Research slice
[H4](H4-inflation.md) ran independent pillow and cube solves the same day and
agrees.

## Question

Can a small, standard model make inflated paper look right, and what does it
cost? The owner names a crane whose body fills out and a water bomb that is
blown up. Both are paper that is pushed from inside.

## Setup

Three shapes, each with an answer to compare against:

- **The tea bag**: two unit squares joined along their edges and inflated. Its
  largest possible volume is not known exactly. Kepert's construction reaches
  0.2055 × side³, and his upper bound of 0.2176 holds only under two unproved
  assumptions **(V)**; the only rigorous ceiling is 0.266, the sphere of the
  same area. Robin's approximate formula gives 0.2017
  ([Paper bag problem](https://en.wikipedia.org/wiki/Paper_bag_problem);
  Kepert's own page, archived).
- **The Mylar balloon**: two discs of radius 1 sealed at the rim. The answer is
  exact (Paulsen 1994): volume 1.2185, rim radius 0.7628, thickness 0.599 of
  the inflated diameter **(V: 1.2185, not 1.2186)**.
- **The puffed square** of [#104](https://github.com/avalonalex/senbazuru/issues/104):
  one square with its rim clamped and pressure on one side.

Two routes on identical meshes:

1. **Blender cloth** with its Pressure option and self-collision, run headless.
2. **Our own quasi-static solver** in NumPy/SciPy: a St Venant–Kirchhoff
   membrane, hinge bending, and pressure as the energy `−p·V`, where the volume
   of a closed mesh is `V = (1/6) Σ x₀ · (x₁ × x₂)` over its triangles.
   Minimised by L-BFGS; its gradients agree with finite differences to 1e-8.

Each route was run two ways. A **full membrane** resists stretching and
shortening alike. A **tension-field membrane** resists stretching only:
shortening is free, the way paper gathers slack into crimps and wrinkles.

## Results

![Contact sheet: tea bag by both routes and both membrane models, crimp look tests, Mylar balloon, drawn and solved puffed square, section profiles and compression maps](img/X2-contact-sheet.jpg)

**A full membrane at paper stiffness is the wrong model.** It either barely
inflates or buckles at the scale of the mesh, and its answer changes with mesh
and pressure:

| Case | Full membrane | Tension field | Reference |
| --- | ---: | ---: | ---: |
| Tea bag, own solver, 2,304 triangles | 0.092 | 0.1995 | 0.2055 (construction) |
| Tea bag, Blender, 2,304 triangles | 0.1738 | 0.2027 | same |
| Mylar, own solver, 3,072 triangles | 0.5734 | 1.2132 (−0.44%) | 1.2185 |
| Mylar, Blender, 1,200 / 3,072 triangles | 1.1694 / 0.8005 | — | same |

With the tension field, halving the element size changes the volume by at most
1%, and the two independent routes agree. The Mylar section lies on Paulsen's
exact profile. No solved tea bag reaches Kepert's 0.2055, so none has found the
true maximum.

**Paper must gather material to inflate, locally a lot of it.** In the solved
tea bag the edge midpoints move 0.134 of the side towards the centre, and the
corners reach the 50% compression cap. **(V)** Averaged over the sheet the
compression is 5.9%, and 40% of the area is compressed by more than 5%; the
"15–25%" first reported is local to the edge midpoints.

**Bending against pressure is a first-order control.** In the solver's units
the tea bag's volume falls from 0.20 to 0.10 as the bending weight `kb` rises
from 1e-4 to 1e-2. **(V5)** The hinge coefficient is not the plate's bending
stiffness `D`: on these meshes `D` ≈ 2.9–4.5 × `kb`, so real kami at breath
pressure sits at `kb` ≈ 1.1e-3 to 1.8e-2 in these units, and the membrane
factor at 8e3 to 8e4. The conclusion holds: at origami scale, how hard the
paper is blown changes its volume by about a factor of two, so an author should
control the amount of puff directly (a volume, or pressure measured in units of
bending, [H4](H4-inflation.md) finding 9), not a pressure in pascals.

**The correct shape renders as a cushion, not as paper.** The tension-field
answer is the smooth *average* shape. Where the membrane is slack it says how
much paper has gathered and in which direction, but not where the crimps are.
Two look tests added crimps from the compression map: smooth sine crimps read
as quilted fabric; zigzag ridges only where compression exceeds 5% read closer
to paper but show hard patch edges. Placing crimps well is open work (compare
wrinkle augmentation for cloth, Rohmer et al. 2010).

**A clamped rim barely rises.** With the rim clamped, the solved puffed square
rises 3.1% of its side at membrane factor 1e3, against 25% for the drawn bump in
`examples/puffed-square.fold`, which needs up to 26.4% stretch. **(V2)** The
rise falls as the membrane stiffens, about as its −1/3 power: 1.45% at 1e4 and
0.67% at 1e5, the range estimated for kami. So 3% is an upper bound, and the
conclusion is stronger than first stated: never solve a body panel with a
clamped boundary. Inflation works because paper flows in from free edges and
flaps.

**Cost.**

| Route | Case | Time |
| --- | --- | --- |
| Blender cloth, 100 frames | tea bag, 576 triangles | 3.5, 3.7, 4.1 s |
| Blender cloth, 100 frames | tea bag, 2,304 triangles | 11.1, 19.7, 19.9 s |
| Own solver, L-BFGS | tea bag, 576 triangles | 12,068 iterations (deterministic) |
| Own solver, L-BFGS | tea bag, 2,304 triangles | 32k–37k iterations, 446–506 s |

Blender's volume settles within 0.5% by frame 5–10. The machine was heavily
loaded during these runs (load average about 210), so iteration counts, not
seconds, are the reliable measure of the own solver.

## What it shows

- Inflated paper needs a membrane that can shorten for free. With one, about
  600–1,200 triangles per pouch give the right mean shape, validated to 0.4%
  on an exact answer.
- The author's control should be the amount of puff, not physical pressure.
- The refined *look* of inflated paper needs a separate layer of crimps driven
  by the solver's compression field.
- Blender cloth (GPL; run, not vendored) is a fast research tool with pressure,
  target volume, pins and self-collision. Its units are not physical.

## What it does not show

- No creased or layered rest states, no contact between layers, and no water
  bomb. [Y5](Y5-waterbomb.md) attempts the water bomb.
- No wrinkles resolved physically in either route.
- The tension-field energy clamps principal strains; it is not Pipkin's exact
  relaxed energy, and where the slack goes is not unique (the Mylar solution
  gathers it into mesh-symmetric wedges).
- Blender's pillow outputs were not checked for crossing triangles.

## Reproduce

A virtual environment made from Blender's bundled Python 3.11 with `numpy`,
`scipy` and `matplotlib`. `python shell.py` runs the gradient test;
`run.py {teabag|mylar|puff} RES {tension|full} KS KB` runs one solve;
`batch.sh` and `batch2.sh` run the matrix; `bl_cloth.py` runs Blender cloth
headless; `bl_render.py`, `plots.py`, `crimp.py` and `contact.py` make the
figures.
