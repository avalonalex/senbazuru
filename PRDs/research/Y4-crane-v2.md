# Y4. Opening the crane body with thickness, a body load, a tension-field core and refinement

Experiment Y4, run 2026-09-28 against `main` at `83fc960`, in a scratch
directory; nothing in the repository was changed. It is one of the second-round
experiments the [completeness critique](Z2-critic.md) proposed, and its
evidence feeds [PRD 11](../11-prd-refined-final-forms.md). Its scripts are in
[`scripts/Y4-crane-v2/`](scripts/Y4-crane-v2/); other outputs it names (renders, saved states,
logs) were not kept, except the contact sheet below. Paths it quotes are relative
to its scratch folder.

![Y4 contact sheet](img/Y4-contact-sheet.jpg)

## Question

X3 showed that grips on the wings could spread the stitched closed crane with IPC contact (the barrier method that keeps triangles from passing through each other), but the body opened only 29–40% as far as spread-0's before contact jammed.

This round asks whether any combination of four ingredients opens the body to at least 70% of spread-0, at 1–3% strain or less, with zero crossings. The ingredients are:

1. thickness as a minimum contact distance (dmin), checked with Tight-Inclusion collision detection;
2. a body load: a volume floor, underside mouth grips, and variants of these;
3. a tension-field (compression-free) membrane on the body core;
4. refinement of the core.

It also asks which ingredient mattered, and if nothing works, where and why it jams.

## Setup

**Code.** All code is my own, in `experiments/Y4-crane-v2/src/`.
- It builds on X3's `sim.py`, `torn.py`, `contact.py` and `metrics.py` (copied, then extended).
- New files: `sim2.py`, `metrics2.py`, `run_stitch2.py`, `run_open2.py`, `refine.py`, `refine_state.py`, `diag.py`, `core_shape.py`, `budget.py`, `table.py`, `bench.py`, `plot_runs.py`, `render_views.py`, `sheet.py`.
- The venv is X3's (symlinked): ipctk 1.6.0, scipy 1.17.1, numpy 2.4.6, shapely 2.1.2, matplotlib 3.11.2, Blender's Python 3.11. Renders use Blender 4.4.1 EEVEE.
- Nothing was installed, and the repo was not touched.

**Mesh.** The study's `before.fold`: 448 triangles, 237 vertices.
- It is cut at all 202 folds into 52 flat pieces (490 vertex copies, 418 stitches), as in X3.
- Refined variant: 672 triangles and 349 vertices (638 copies, 454 stitches).
- **Body core:** the 49 study core vertices, which are the eight panels touching the paper's centre. That is 64 triangles with a 32-edge rim.

**Solver.** X3's projected Newton method.
- Energies: edge springs, hinge bending, crease hinges, stitch springs and grips.
- Contact: an ipctk log barrier, filtered by material adjacency.
- New in the solver:
  - collision candidates are built once per iteration over the swept step and reused for the next iteration and the line search;
  - a trust region caps each step at 1e-2 for dmin = 0, and at 5e-3 with thickness;
  - Tight-Inclusion collision detection at tolerance 1e-5 with 1e6 iterations (the defaults took 13–17 s per call);
  - a switch that turns contact off, for control runs.

**Load path.** 10 steps with 40 Newton iterations each.
- **Wing grips:** X3's "root" patches (mid-wing, near the root, radius 0.08 around closed position (1, 0.2)). Each patch moves by a scaled rigid (Kabsch) motion to its spread-0 pose.

**Ingredients.**
1. **Thickness.** dmin with Tight-Inclusion collision detection at dmin. The stitched starts are rebuilt with the pieces lifted to 1.5 × dmin.
2. **Body loads.**
   - Volume floor: an energy k_v/2 · max(0, V* − V)². V is the volume enclosed by the 64 core triangles plus a fan cap over the core rim, measured on the welded sheet (so it does not change under translation). V* ramps up to spread-0's value, 1.17e-3.
   - Mouth grips: all copies of the four boundary midpoints (vertices 20, 1, 55, 28) move toward spread-0.
   - Variants: a "back press" on the paper's centre (vertex 24), neck/tail tip grips (vertices 0, 57), and stiff point grips.
3. **Tension-field core.** A per-triangle principal Green-strain energy on the core, stiff in tension (k_t = 1e5) and 1e-3 as stiff in compression, in place of the core's edge springs. Gradients match finite differences (3e-6 abs error, largest gradient component 6.8e3). The volume gradient matches to 4e-12.
4. **Refinement.** Core triangles split 1-to-4 and the rim neighbours bisected. Stitched states are carried over exactly by subdivision.

**Stiffnesses.** X3's values: k_m 1e5, k_b 1e-2, k_c 1e-3, k_g 1e3, k_w 1e4. For dmin = 0 the barrier uses dhat 1e-4 and kappa 1e11.

**Measures per step.**
- **Mirror opening:** X3's median separation of 18 mirror pairs.
- **Body depth:** the study's definition, the world-z range of the 49 core vertices.
- Wing-tip separation.
- Max edge error, and max principal stretch and compression, reported separately for the core and the rest.
- Stitch gaps.
- Minimum distance between layers.
- **Crossings on the cut mesh:** pairs of triangles that share no material vertex where an edge of one passes through the other. This is what IPC guarantees.
- Core volume and runtime.
- Added for diagnosis:
  - the core's head-to-tail length (x-range);
  - the fold angles of the 12 crease segments through the paper's centre (8 midline, 4 diagonal);
  - where stitch gaps, stretch and pressed contacts sit.

**Machine.** M1 Max, 10 cores. Load averages of 22–260 came from other agents.

## Results

### 1. Reference poses on the same measures

| pose | opening | depth | tips | edge err | stretch | core length (x-range) | midline / diagonal fold |
|---|---|---|---|---|---|---|---|
| closed (before) | 0 | 0 | 0 | 0 | 0 | 0.235 | 180 / 180 deg |
| after (study) | 0.0564 | 0.0725 | 0.340 | 5.3% | 22% | 0.235 | 166 / 159 |
| **spread-0** | **0.1403** | **0.2071** | 0.774 | 57% | 107% | **0.414** | **14 / 4** |
| X3 best (conv-root10) | 0.0556 (40%) | 0.1077 (52%) | 0.759 | 7.5% | 10.6% | 0.215 | 179 / 143 |

### 2. Thickness: can the closed crane be stitched with dmin?

| dmin (fraction of the sheet side) | barrier | stitch stiffness reached | edge err | stretch | largest stitch gap | notes |
|---|---|---|---|---|---|---|
| 1e-3 (= t, X3's) | dhat 2.5e-4, kappa 1e8 | — | — | — | — | steps cut to 1e-4 to 1e-5 by collision detection; stopped |
| 1e-3 | dhat 1e-3, kappa 1e7 | 10 / 100 | 8.8% / 7.6% | 12.9% / 9.8% | 18.5 t / 12.7 t | stage 100 limited on 150 of 150 iterations; stage 1e3 jammed (step 0.002–0.004 of full) |
| 5e-4 | dhat 5e-4, kappa 3e7 | 10 / 100 | 2.8% / 2.7% | 3.3% / 3.3% | 18 / 12 dmin | stage 100 limited on 150 of 150 iterations |
| 2.5e-4 | dhat 2.5e-4, kappa 1e8 | 100 (converged, 97 iterations) | 0.78% | 1.4% | 12 dmin (3.0e-3) | stage 1e3 jammed |
| 2.5e-4 | kappa 1e10 | 1e4 (limited on 149 of 150 iterations) | 0.78% | 1.5% | 8.9 dmin (2.2e-3) | min distance 2.56e-4, 0 crossings |

On the 448-triangle mesh, thick paper cannot close its nested creases. Each crease must bridge up to 46 stacked layers × dmin on one coarse edge.

### 3. Opening runs at the end of the path (s = 1 unless noted)

Grips are on the wings in every run. In the table, "tf" is the tension-field core, "vol" the volume floor and "mouth" the mouth grips.

| run | ingredients | opening | depth | edge err | stretch core / rest | core compression | largest stitch gap | cut-mesh crossings |
|---|---|---|---|---|---|---|---|---|
| A R0-d0-ti | dmin 0, Tight-Inclusion | 35% | 42% | 4.8% | 3.0 / 10.6% | 3% | 5.6e-3 | 0 |
| R0-mouth | + mouth | 44% | 49% | 8.2% | 3.8 / 11.7% | 4% | 7.5e-3 | 0 |
| R0-vol | + vol 1e7 | 38% | 45% | 7.1% | 7.5 / 10.6% | 7% | 7.0e-3 | 0 |
| R0-tf | + tf | 45% | 65% | 29% | 5.0 / 5.9% | 36% | 3.5e-3 | 0 |
| B R0-all | + mouth + vol + tf | 51% | 66% | 19% | 5.8 / 10.1% | 38% | 7.5e-3 | 0 |
| R0-voltf8 | + vol 1e8 + tf | 49% | 69% | 34% | 6.6 / 6.6% | 47% | 4.3e-3 | 0 |
| R0-back | + back press | 43% | 51% | 8.4% | 3.5 / 12.1% | 6% | 9.9e-3 | 0 |
| R0ref-tf | refined + tf | 47% | 74% | 58% | 7.9 / 5.4% | 60% | 2.5e-3 | 0 |
| C R0ref-all | refined + mouth + vol + tf | 53% | 73% | 40% | 9.0 / 14.8% | 42% | 7.8e-3 | 0 |
| D R0-all-nt (s=0.9) | B + neck/tail grips | 57% | 70% | 26% | 6.7 / 15.6% | 34% | 6.2e-3 | 0 |
| R0-all-stiff (s=0.4) | D with point grips 1e5 | 60% | 46% | 17% | 17.7 / 19.1% | 41% | **4.0e-2** | 0 |
| E R2-all | thick t/4, kappa 1e10, stitches 1e4, + B | 17% | 24% | 2.6% | 1.3 / 1.4% | 4.5% | 2.2e-3 | 0 (tips only 0.15 of 0.77) |
| F R1-k10-all | thick t/4, kappa 1e10, stitches 1e2, + B | 106% | 89% | 46% | 47 / 50% | 15% | **6.7e-2 (torn)** | 0 |
| R0-nocontact | control, no contact | 60% | 36% | 0.7% | 0.9 / 1.7% | 1% | 6e-4 | **672** |
| G R0-nocontact-mouthstiff | no contact, forced mouth + neck/tail | 72% | 107% | 15% | 3.4 / 19.9% | 3% | 1.7e-2 | **663** |

### 4. The most open state within the budget

The 3% budget below means both stretch and edge error are at or below 3%, with zero crossings.

| run | last s within 3% | opening | depth |
|---|---|---|---|
| wings only | 0.4 | 19% | 23% |
| + mouth | 0.4 | 21% | 23% |
| + vol | 0.5 | 23% | 26% |
| + back press | 0.4 | 22% | **28%** |
| + tf / all / refined | 0.2–0.3 | 10–18% | 17–25% |
| thick t/4, stiff stitches (E) | 1.0, but the grips lag by 0.23 | 16–17% | 23–24% |

**Stretch only** (tension-field slack allowed): the tension-field core at s = 0.7 reaches opening 35% and depth 51%, with stretch 2.9%, core compression 19% and edge error 15%.

### 5. What each ingredient did

Compared with A at s = 1:

| ingredient | effect |
|---|---|
| Tight-Inclusion collision detection (and dmin = 0) | Zero crossings on the cut mesh in every contact run, including the path where X3's Additive run lost the guarantee (3–4 crossings). Opening matched X3's. |
| dmin (thickness) | Hurt on this mesh: jam at kappa 1e8, creep with stiff stitches, tearing with weak ones (sections 2 and 3). |
| Mouth grips (stiffness 1e3) | +9 opening, +7 depth. But the mouth points themselves did not move toward their targets: lag 0.09–0.12 against target moves of 0.09–0.14, the same as A. At stiffness 1e5 they tear the stitches (gap 2.1% of the side at s = 0.2). |
| Volume floor 1e7 | +3 / +3. Reached 65% of spread-0's core volume. |
| Tension-field core | +10 / **+23**. Stretch outside the core halves (5.9% against 10.6%), at the cost of 36% slack in the core. |
| Volume 1e8 + tension-field | +14 / +27. Core volume reached 92% of spread-0's as a pod. |
| Refinement | +2 / +7–9 over the same run without it. |
| Back press | +8 / +9. |
| Neck/tail grips (with B, s = 0.9) | +9 / +8, stretch 15.6%. |

### 6. Where it jams, and why

| state | core length | midline fold (median, min) | diagonal fold (median, min) |
|---|---|---|---|
| spread-0 | 0.414 | 14 (12) | 4 (2) |
| A wings only | 0.222 | 180 (179) | 146 (144) |
| B all | 0.222 | 155 (134) | 116 (94) |
| C refined all | 0.225 | 141 (99) | 92 (56) |
| volume 1e8 + tension-field | 0.219 | 144 (122) | 120 (90) |
| no contact, wings only | 0.234 | 168 (165) | 159 (154) |
| G no contact, forced | 0.266 | 129 (63) | 98 (69) |
| E thick | 0.234 | 174 (171) | 164 (157) |

- **The core never gets longer.** Every run keeps it at 0.20–0.235 (the closed crane has 0.235), and every contact run keeps the midline creases at 140–180 deg. The opening all comes from the core swinging about its spine, as the diagonal creases open to 92–146 deg. That makes a pod; spread-0 instead flattens the paper's centre square into a pillow top.
- **Stretch sits at the neck and tail roots.** The most-stretched triangles are at material (0.457, 0.206), (0.177, 0.468), (0.823, 0.532) and (0.543, 0.794), at 6–15%. These are the roots of the neck and tail flaps, next to the core rim.
- **Pressed contacts sit in the same places.** At s = 1 in A, 208 pressed pairs: neck 32, tail 31, core/wing 27 + 16.
- **Stitches tear at the core's diagonal corners**, (0.354, 0.354) and (0.354, 0.646), with gaps up to 5–7.5 × 1e-3.
- **Contact is not the first limit.** With contact off, wing grips alone still leave the midlines at 168 deg. Forcing the mouth open needs 20% stretch even with no contact.
- **With dmin = 0, layers still pack.** The minimum distance falls to 1.5e-10 at s = 0.5, which is when collision detection starts limiting all 40 of 40 iterations.

### 7. Cost

**Collision-detection benchmark** (`bench.py`, 3 repeats each, load average 230–260):
- Tight-Inclusion at dmin = 0: 3.05–3.54 s per call, step fraction 0.234.
- Additive on the same state: 0.014–0.022 s per call, step fraction 0.37–0.81.
- Tight-Inclusion at dmin = 2.5e-4, kappa 1e10: 0.04–0.12 s per call.
- Rest of an iteration: candidate build and filter 0.03–0.6 s, barrier 0.01–0.07 s, linear solve 0.02–0.6 s.

**Runs** (single runs, under load):
- Contact runs: 1.2–2.6 s per iteration, 490–1170 s per 400-iteration run.
- Thick runs: 0.6–0.7 s per iteration.
- No-contact runs: 0.05–0.19 s per iteration.

## Images

- `contact-sheet.png`: 10 columns × 3 gallery cameras (upright, head, below).
  - Columns: closed start, X3 best, A, B, C, D, E, F, G, spread-0.
  - A–D grow a rounded pod between V-shaped wings, and the underside stays a closed seam.
  - E barely opens.
  - F (torn) and G (crossing) are the only boxy bodies with an open underside, like spread-0.
- `img/curves.png`: opening, depth, edge error, stretch and core compression for each load step, 12 runs, with the 70% and 3% targets and X3's best marked.
- `img/head-zoom.png`: head-on views of A, volume + tension-field, C and spread-0. The pod is visibly rounder with the tension-field core and with refinement, but it is not spread-0's box.
- `img/controls-zoom.png`: G (crumpled), E (a sliver), F (boxy but torn), and spread-0.

## What it shows

- The IPC path cannot open this crane body to a spread-0-like pillow at low strain. The best result within the strict 3% budget is 28% of spread-0's depth. The best allowing core slack is 51%.
- Every run past 70% on both measures is invalid: it either tears or crosses.
- The limit is geometric. Spread-0's body is the paper's centre square unfolded: core length +77%, midline creases at 14 deg. No tested load lengthens the core.
- The wing, mouth, back, volume and neck/tail loads all turn the core about its spine instead, making a pod. The neck and tail flap roots take the stretch.
- The tension-field core is the one ingredient that helps materially, and it is physically required anyway: spread-0's own core needs about 50% compression across the wings.
- Thickness via dmin makes the coarse mesh worse: it jams, creeps or tears.
- Tight-Inclusion collision detection keeps zero crossings, at 150–250× the cost of Additive.

## What it does NOT show

- It does not show converged equilibria. Every step hit its iteration cap.
- It does not show behaviour with calibrated paper stiffness.
- It does not model the true pocket mouth. The volume cap is over the core's rim.
- It does not use a finer mesh with bend strips along the nested creases outside the core.
- It tests thickness only at t/4 in the openings.
- It does not test plastic re-creasing (rest-angle changes) of the neck/tail reverse folds, which is the natural next candidate for lengthening the core.
- The welded sheet still has 600–900 crossing pairs, a stitch artefact as in X3.
- It does not show that spread-0's exact body is reachable at all. The no-contact forced run (G) suggests it needs about 20% stretch even with no contact.

## Recommendation for the PRD

1. **State the no.** Pulling (plus the tested body loads) gives a pod-shaped body at about 50% depth, and only with core slack. Put the owner's choice in the PRD: a valid pod, or a prescribed pillow sketch.
2. **Add measures that separate pod from pillow.** Add core length (head-to-tail) and the centre-crease fold angles to the gallery measures. Depth and core volume cannot tell a pod from a pillow: a pod reaches 92–94% of spread-0's core volume.
3. **Require the tension-field core** in any opening or inflation solve.
4. **Target the core's length next.** The next experiment should aim at lengthening the core: loads at the neck/tail flap roots, or rest-angle changes of their reverse folds (the X-stand's new creases, H4 finding 15). More wing, volume or mouth load will not do it.
5. **Refine before adding thickness.** Refine along the nested creases (bend strips) first, then add dmin. Do not add thickness to the 448-triangle mesh.
6. **Keep Tight-Inclusion collision detection** at tolerance 1e-5 with 1e6 iterations, and plan a compiled or vectorised solver, since collision detection dominates the cost.

## Reproduce

Run everything from `experiments/Y4-crane-v2/src` with `../venv/bin/python`, which is X3's venv.

- **Regions:** the snippet in the transcript writes `out/regions.json`, taking the core from `checks.json` pins minus 2 and 54.
- **Cut starts:** `torn.py 1.5e-3 torn15`, `torn.py 3.75e-4 torn0375`, `torn.py 7.5e-4 torn075`.
- **Refined mesh:** `refine.py`, then `torn.py 1e-3 torn-ref-x3 ../out/refined.json`.
- **X3's start:** `ln -s ../X3-crane-opening/torn.npz torn-x3.npz` and copy `stitch.npy` to `out/x3-stitch.npy`.
- **Stitches:**
  - `run_stitch2.py torn15 stitch-d1b '{"dhat":1e-3,"kappa":1e7,"gtol":5e-3}'`
  - `run_stitch2.py torn0375 stitch-d025 '{"dmin":2.5e-4,"dhat":2.5e-4,"kappa":1e8,"gtol":5e-3}'`
  - `run_stitch2.py torn0375 stitch-d025k10 '{"dmin":2.5e-4,"dhat":2.5e-4,"kappa":1e10,"gtol":5e-3,"kw_schedule":[1e3,1e4],"start":"../out/stitch-d025-kw100.npy"}'`
- **Openings.** Let B0 be `"dmin":0,"dhat":1e-4,"kappa":1e11,"step_cap":1e-2`.
  - Base form: `run_open2.py torn-x3 ../out/x3-stitch.npy NAME '{B0,...}'`.
  - Flags: `"mouth":true`, `"k_v":1e7`, `"tf_core":true`, `"back":true`, `"necktail":true`, `"k_p":1e5`, `"contact":false`.
  - Refined runs: `run_open2.py torn-ref-x3 ../out/ref-x3-stitch.npy NAME '{B0,"regions":"regions-refined",...}'`, after `refine_state.py torn-x3 torn-ref-x3 ../out/x3-stitch.npy ../out/ref-x3-stitch.npy`.
  - Thick runs: `run_open2.py torn0375 ../out/stitch-d025k10.npy R2-all '{"dmin":2.5e-4,"dhat":2.5e-4,"kappa":1e10,"k_w":1e4,"mouth":true,"k_v":1e7,"tf_core":true}'`.
  - Convergence checks: `"resume":STATE,"resume_step":k,"rounds":5`.
- **Measures and figures:**
  - `remeasure2.py` (baselines)
  - `table.py -1 RUNS...`
  - `budget.py 0.03 {both|tension} RUNS...`
  - `core_shape.py TORN states...`
  - `diag.py TORN state '{params}'`
  - `bench.py TORN state '{params}' LABEL`
  - `plot_runs.py`
  - `Blender -b --factory-startup --python render_views.py -- ../render upright,head,below OBJ...`
  - `sheet.py`
- **Where things are:** logs, JSON and npy per step are in `out/`; renders in `render/`; figures in `img/`.

