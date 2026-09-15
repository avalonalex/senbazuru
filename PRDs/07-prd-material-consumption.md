# 07 — Material consumption: move records in, settled illustrations out

Feature 3a. Written 2026-09-14 against `568dcb6`, and brought into line on
2026-09-15 with [decisions.md](decisions.md), the design's decision record, which
wins wherever the two disagree. Requirements only: nothing is implemented, and
every type and syntax fragment is a **SKETCH**. This file holds the detail behind
[D14](decisions.md#d14-material-consumption),
[D15](decisions.md#d15-graduation-from-study-to-library) and
[D17](decisions.md#d17-third-party-and-external-tools). Owned elsewhere: the
module graph and recorded-text table ([01](01-architecture.md)), move records and
evidence ([02](02-language-semantics.md); fields in
[decisions §5](decisions.md#5-type-sketch)), grammar and flags
([04](04-prd-sequence-source-and-cli.md)), solver additions
([05](05-prd-library-additions.md)), renderers ([08](08-prd-realistic-rendering.md)),
CI placement ([09](09-testing-and-acceptance.md)). Milestones M0–M8 are
[decisions §8](decisions.md#8-milestones)'s, summarised in
[00](00-overview.md#what-you-can-see-at-each-milestone).

## Summary

The material study bends folded paper, which the rigid solver cannot. Its static
solve holds part of the model exactly, turns a held strip, and lets the rest move
to lower an energy with four terms: stretched edges, crease springs turned away
from their rest angle, bent panels, and layers pressing into each other
([glossary-additions](glossary-additions.md#material), *held boundary* and
*penalty contact*). That solve is a *settle* (same glossary). Today one
hand-built move feeds it. This feature makes it read *move records*, the
per-move results of a sequence run
([glossary-additions](glossary-additions.md#running-a-sequence)). An author
writes `settle { … }` inside the step whose move it illustrates, names holds and
grips against that move ("the stationary side", "a band next to the hinge"), and
gets a settled surface in its own GLB and SVG files. Rigid outputs keep their
bytes.

Four constraints, each backed below:

1. **A settle must name a difference.** A checked rigid state is already an
   *equilibrium* (a state in which nothing would move), so a settle resting at its
   start with no moved grip is refused as `NoDifference`.
2. **Settled geometry is an illustration, never state.** It feeds no later step,
   page or animation; a failure refuses only its own files.
3. **The solver is mature for one case family.** A crane wing bends with the body
   held, accepted at 392 and 1,192 triangles; releasing body paper fails.
4. **The consumer lives in the study until graduation.** M6 delivers
   `senbazuru-material-study --sequence SOURCE DIR`; M8 delivers `run --settle`,
   after [#208](https://github.com/avalonalex/senbazuru/issues/208) and behind a
   triangle budget.

*Certificates*, the study's exact proofs that one fixture's route never crosses
paper ([glossary-additions](glossary-additions.md#assurance)), attach after a run
through a study registry and never enter the library.

## Problem and evidence

### One move, fed by hand

`examples/crane.fold` is a traditional crane stored as a *crease pattern*, the
unfolded sheet with its creases marked ([glossary](../docs/glossary.md#origami)):

```bash
jq -c '{vertices: (.vertices_coords|length), edges: (.edges_vertices|length), faces: (.faces_vertices|length), angles: has("edges_foldAngle"), orders: has("faceOrders"), assignments: (.edges_assignment|group_by(.)|map({(.[0]): length})|add)}' examples/crane.fold
```

prints `{"vertices":58,"edges":129,"faces":72,"angles":false,"orders":false,"assignments":{"B":10,"F":20,"M":58,"V":41}}` (`B` border and `F` flat edges, [glossary](../docs/glossary.md#the-fold-format);
`M` mountain and `V` valley creases, [glossary](../docs/glossary.md#origami)).
`python3 -c 'import json;d=json.load(open("examples/crane.fold"));xs=[v[0] for v in d["vertices_coords"]];ys=[v[1] for v in d["vertices_coords"]];print(min(xs),max(xs),min(ys),max(ys), len(d["vertices_coords"][0]))'`
prints `5.773159728050814e-15 0.9999999999999942 5.551115123125783e-17 1 2`: the
sheet is the unit square to within 6e-15, its corners 5.8e-15 off. One *sheet
length* ([glossary-additions](glossary-additions.md#references)) is s, the larger
side of that box ([02](02-language-semantics.md) records it at resolution). In
`Double` the width is 0.9999999999999885 and the height 1 − 5.55e-17 rounds to
1.0, so s is exactly 1 and one sheet length is one model unit here. Taken as exact
fractions of the stored coordinates, s would be 1 − 5.55e-17.

The recipe `CraneWing` folds the file holding face 0 still
([`CraneWing.hs:54-57`](../study/fold-material/CraneWing.hs#L54-L57)), creases
across the wing along folded y = 1/4 ([`:98`](../study/fold-material/CraneWing.hs#L98)),
turning 72 faces (flat regions between creases) into 76 ([`:60-66`](../study/fold-material/CraneWing.hs#L60-L66)),
picks the [stacking](glossary-additions.md#running-a-sequence) with the tail
tucked between the body layers, index 2 of five
([`:75-78`](../study/fold-material/CraneWing.hs#L75-L78)), takes "every
`Unassigned` edge" as the [*hinge*](glossary-additions.md#origami) ([`:65`](../study/fold-material/CraneWing.hs#L65)),
and checks a +90° turn of the side holding vertex 2
([`:72`](../study/fold-material/CraneWing.hs#L72), [`:80`](../study/fold-material/CraneWing.hs#L80)).
The −90° turn is refused as `FlapEndpointOrder`, because the wing would pass
through the layer it rests against
([`:81-84`](../study/fold-material/CraneWing.hs#L81-L84)).

`craneSpreadWith` bends that wing and takes the *move*, not a surface
([`CraneSpread.hs:80-115`](../study/fold-material/CraneSpread.hs#L80-L115)): the
start state (`:85`), the rigid pose one third of the way through the 90° turn
(`:86`, written `30 / 90`), the moving faces
(`:88`), the hinge ids (`:91`, `:97`) and the start's [face orders](../docs/glossary.md#the-fold-format) turned into
lower/upper pairs by each face normal's sign (`:108-114`). It picks holds by
testing its own coordinates ([`:101-106`](../study/fold-material/CraneSpread.hs#L101-L106)).

**The `fraction` line below looks like a mistake and is not.** Its `y` is the
*folded* start position, not a material coordinate: the wing lies in two layers
and its hinge is "a bent chain on the OPEN sheet"
([`CraneWing.hs:8-10`](../study/fold-material/CraneWing.hs#L8-L10)), so a
straight strip beside the hinge is several unrelated regions of the sheet. Its
two 0.25s mean different things: the first is the hinge's folded y, the second
the wing's length beyond the hinge. Both happen to be 1/4 on this fixture.

```haskell
fraction p = let V3 _ y _ = position p in (0.25 - y) / 0.25
held i p = S.member i body || (S.member i selected && fraction p <= 0.125 + 1e-8) || S.member i grip
```

A Python flat fold from face 0, reflecting across every mountain or valley
crease, checks both numbers:

```bash
python3 - <<'EOF'
import json
d=json.load(open("examples/crane.fold"));V=d["vertices_coords"];A=d["edges_assignment"];F=d["faces_vertices"]
E={frozenset(e):i for i,e in enumerate(d["edges_vertices"])}
def R(p,q):  # reflection across the line through p and q, as a 2x3 affine map
  dx,dy=q[0]-p[0],q[1]-p[1];n=dx*dx+dy*dy;a,b=(dx*dx-dy*dy)/n,2*dx*dy/n
  return [a,b,p[0]-a*p[0]-b*p[1],b,-a,p[1]-b*p[0]+a*p[1]]
def M(s,t):return [s[0]*t[0]+s[1]*t[3],s[0]*t[1]+s[1]*t[4],s[0]*t[2]+s[1]*t[5]+s[2],s[3]*t[0]+s[4]*t[3],s[3]*t[1]+s[4]*t[4],s[3]*t[2]+s[4]*t[5]+s[5]]
T={0:[1,0,0,0,1,0]};todo=[0]   # face 0 stays still; crossing an M or V crease reflects
while todo:
  f=todo.pop()
  for g,r in enumerate(F):
    s=set(F[f])&set(r)
    if g in T or len(s)!=2:continue
    a,b=s;T[g]=M(T[f],R(V[a],V[b])) if A[E[frozenset(s)]] in "MV" else T[f];todo.append(g)
P=lambda f,i:tuple(round(T[f][k]*V[i][0]+T[f][k+1]*V[i][1]+T[f][k+2],9) for k in (0,3))
inside=lambda x,y,r:sum((r[k][1]>y)!=(r[k-1][1]>y) and x<r[k-1][0]+(y-r[k-1][1])*(r[k][0]-r[k-1][0])/(r[k][1]-r[k-1][1]) for k in range(len(r)))%2==1
print([[round(c,9) for c in V[i]] for i in (2,28)])
print({i:{P(f,i) for f in T if i in F[f]} for i in (2,28)})
print([(f,min(P(f,i)[1] for i in F[f]),max(P(f,i)[1] for i in F[f])) for f in (2,3,6,7)])
print([f for f,r in enumerate(F) if inside(19/20,1/3,[V[i] for i in r])])
EOF
```

```text
[[0.0, 1.0], [0.5, 1]]
{2: {(1.0, -0.0)}, 28: {(1.0, 0.5)}}
[(2, -0.0, 0.5), (3, -0.0, 0.5), (6, -0.0, 0.5), (7, -0.0, 0.5)]
[0]
```

Vertex 2 is material corner (0, 1), the tip, and folds to (1, 0), where
[`CraneWingSpec.hs:98-99`](../test/CraneWingSpec.hs#L98-L99) expects it at
progress 0 (`-0.0` is a signed zero, equal to 0). Vertex 28, material (1/2, 1),
folds to (1, 1/2). The wing faces span folded y from 0 to 1/2, so the tip side of
y = 1/4 is exactly 1/4 long. Only face 0 contains (19/20, 1/3). The check assumes
Haskell keeps the file's face numbering; face 0's guard
([`CraneWing.hs:57`](../study/fold-material/CraneWing.hs#L57)) agrees but does
not prove it for faces 2, 3, 6, 7.

So `fraction ≤ 0.125` means "within 1/32 of the hinge" and `≥ 0.875` means "at
least 7/32 from it". `bentPoint` ([`:117-134`](../study/fold-material/CraneSpread.hs#L117-L134))
holds the first strip rigidly at 30°, puts the grip on a circular arc a further
angle on, and starts every free wing vertex on that arc (`:105`). One run on
2026-09-13 ([spreading-connected-wing.md:35-39](../docs/notes/spreading-connected-wing.md)):

| Control | Triangles | Max edge error | Panel bending energy | Solve CPU s |
| --- | ---: | ---: | ---: | ---: |
| Rigid 30° grip | 392 | 1.39e-11 | 1.44e-27 | 0.47 |
| Curved 50° grip | 392 | 2.92e-7 | 0.0121775 | 5.76 |
| Curved, finer mesh | 1,192 | 3.48e-7 | 0.0126582 | 64.30 |

### What that interface cannot survive

- **A surface has lost the move**: no hinge, sides or route
  ([gap-study-consumption-contract](research/gap-study-consumption-contract.md)
  "(a) What the study takes from a move today").
- **Ids hold in one numbering**: the hinge ids exist in the 76-face crane, not the
  72-face one.
- **The hinge is found by `Unassigned`** ([`CraneWing.hs:65`](../study/fold-material/CraneWing.hs#L65),
  [`CraneRoot.hs:60`](../study/fold-material/CraneRoot.hs#L60)); sequences write
  new creases M or V ([02](02-language-semantics.md)).
- **Rest angles come from assignments**: −π if `Mountain`, else +π
  ([`CraneSpread.hs:90-94`](../study/fold-material/CraneSpread.hs#L90-L94)). Every
  active crease needs one ([`FoldBending.hs:177-182`](../study/fold-material/FoldBending.hs#L177-L182)),
  and M/V at angle 0 is active ([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278)),
  so a precrease would get a spring pulling flat paper shut.
- **The stationary side is not exported**: `stationaryFace` is a field
  ([`Flap.hs:85`](../src/Senbazuru/Origami/Flap.hs#L85)), not an export
  ([`:49-59`](../src/Senbazuru/Origami/Flap.hs#L49-L59)).
- **Pins are keyed by mesh vertex id.** A *pin* is one mesh vertex together with
  the exact position a hold or grip fixes it at; `spreadPins` is `CraneSpread`'s
  map from mesh vertex id to that position
  ([`CraneSpread.hs:107`](../study/fold-material/CraneSpread.hs#L107)). The ids are
  made by refinement
  ([`FoldRelaxation.hs:244-247`](../study/fold-material/FoldRelaxation.hs#L244-L247)).

### A rigid state is already settled

The table's first row: with rest angles at the state's own angles and holds where
the rigid solver put them, the solve returns edge error 1.39e-11 and panel energy
1.44e-27. Bending appeared only when the grip turned 20° further
([B](research/B-material-study-mechanics.md) "Summary", finding 6).

### How far the solver reaches

Single recorded runs on one machine, not re-measured here
([B](research/B-material-study-mechanics.md) "Capability table (question a)",
"Unverified").

| Case | Result | Cost | Source |
| --- | --- | --- | --- |
| Crane wing, body held | accepted at 392 and 1,192 triangles | 5.76, 64.30 CPU s | [spreading-connected-wing.md:35-39](../docs/notes/spreading-connected-wing.md) |
| Four body panels released | unconverged after 118 iterations; 49 crossing triangle pairs; edge error 3.75e-5 | about nine CPU minutes each | [body-angle-preferences.md:66-77](../docs/notes/body-angle-preferences.md) |
| Same, 80 more iterations | edge error → 2.07e-5, angle error 0.0187 → 0.0194 rad; still invalid | +452 CPU s | B finding 1 (note) |
| Exact nonnegative contact | gap 0 on 32- and 64-triangle meshes where penalty leaves −5.9e-11 and −8.4e-11; fixture only | — | B finding 1 (note) |
| Mesh dependence | energy changes 3.95% between the accepted crane meshes | — | [spreading-connected-wing.md:47-48](../docs/notes/spreading-connected-wing.md) |
| Tolerance-sized wrongness | a −6.21e-9 crossing passes the 1e-7 check | — | B finding 15 (note) |
| Rendering vs acceptance | an accepted 4,312-triangle crane-root mesh fails the visible glTF scene; complete-sheet GLB works | — | [#206](https://github.com/avalonalex/senbazuru/issues/206) |

*(note)*: B's evidence for that row is a repository note in `docs/notes/`, not a
run made for this PRD.

### What the tests already pay

[#208](https://github.com/avalonalex/senbazuru/issues/208): hspec 626.2452 s for
1,387 examples; `CraneRoot` about 164.87 s and `CraneSpread` 97.48 s (53.21 s one
merged run earlier), from log timestamps; an 8-iteration profile spent about 68%
evaluating contact rows (the energy terms for layers pressing together) and 31%
factorising (rewriting each iteration's sparse linear system so it can be solved).
Each iteration ends in a *line search*
([glossary-additions](glossary-additions.md#material)), which tries step lengths
and needs only the energy at each try; contact evaluation computes derivatives
there too. #208's next optimisation is value-only evaluation, which skips them.
Solving old and new crane side by side would
double the costliest groups (gap-study finding 20).

## Goals

| # | Goal | M |
| --- | --- | --- |
| G-07-1 | Settle a step from its move record, never from a file or ids | M6 |
| G-07-2 | Name every expressible crane-spreading hold, proven to resolve to the same pins | M6 |
| G-07-3 | A settle states its difference, or is refused | M6 |
| G-07-4 | Settles never change rigid output bytes | M6, M8 |
| G-07-5 | Failures scoped to their step; no rigid substitution | M6, M8 |
| G-07-6 | Certificates attach after a run, never downgraded | M5, M6 |
| G-07-7 | Staged, measured graduation | M8 |
| G-07-8 | External solvers as *oracles* (programs whose output we compare ours against, never use) under a licence rule | M0 |

## Non-goals

| Out of scope | Why |
| --- | --- |
| Automatic hold selection; a default settle | No rule exists; a rigid state is already settled ([B](research/B-material-study-mechanics.md) "Implications for the design") |
| Settled geometry feeding later steps | Only independent settles are supported (same) |
| Settling from a non-flat state | One fixed contact direction and coplanar orders ([Where a settle starts](#where-a-settle-starts)) |
| Thickness as geometry, fillets, *springback* | Research ([glossary-additions](glossary-additions.md#material)); a rounded double fold stretches 200% ([two-bends-need-more-than-radii.md](../docs/notes/two-bends-need-more-than-radii.md)) |
| Calibrated stiffness; unheld equilibrium; inflation | "not a calibrated paper constitutive law" ([`FoldBending.hs:18-23`](../study/fold-material/FoldBending.hs#L18-L23)); [#106](https://github.com/avalonalex/senbazuru/issues/106) |
| Certificates in library or CLI; external solvers in CI | [Certificates attach after the run](#certificates-attach-after-the-run); [External tools](#external-tools) |

## Users and scenarios

1. **Study researcher (M6)** re-expresses crane spreading from a sequence; the
   first PR proves named holds resolve to `spreadPins`, solving nothing.
2. **Author (M6)** puts `settle` under "Fold the wing down"; the study writes
   `crane.settled-wing.glb` and `.svg` beside unchanged rigid outputs.
3. **Author with a failed settle** gets the step, its reasons in numbers, rigid
   outputs and a nonzero exit; `--allow-unsettled` exits 0 and records it.
4. **Researcher (M5 + M6)** gets `Certified` on the bird's four stages and
   `NoCertificateFor` on other patterns.
5. **CLI user (M8)** runs `senbazuru run crane.foldseq -o crane.glb --settle`.

## Requirements

M6 unless marked. R-07-10, -13, -16, -17, -19, -22 and -29 were first proposed
here, where the draft record said nothing; [D14](decisions.md#d14-material-consumption)
now decides them as written ([C42](decisions.md#changes-since-draft-v2)).

**Records** (defined in [02](02-language-semantics.md)).

| ID | Requirement |
| --- | --- |
| R-07-1 | The consumer reads only `MoveRecord`s and their `Sequence`, never a written FOLD or GLB. |
| R-07-2 | Record surfaces are unpresented: no [presentation](glossary-additions.md#running-a-sequence) turn, and the root face (the anchor's face, first in the working pattern, which folding holds still) at identity; `displayBefore` and `displayAfter`, computed from `recordPresentation` and `recordPlacement` ([D14](decisions.md#d14-material-consumption)), are applied only by writers and renderers. |
| R-07-3 | One record per move; every id is in `recordBefore`'s numbering, shared by `recordAfter`; for a creasing fold, `recordBefore` is the creased, unturned state. |
| R-07-4 | The solver's surface keeps the working pattern's intent assignments. |
| R-07-5 | Flap records carry `recordStationary`, via a `Flap` accessor or the runner's resolution ([05](05-prd-library-additions.md)). |

**Settle blocks.**

| ID | Requirement |
| --- | --- |
| R-07-6 | `settle { … }` binds to its step's last moving record; none → `SettleOnNoMove`. |
| R-07-7 | A settle starts from `recordBefore`, every vertex within `Fold.Faces.tolerance` (1e-9 × the diagonal of the sheet's bounding box, [`Faces.hs:248-251`](../src/Senbazuru/Fold/Faces.hs#L248-L251); 1.41e-9 on `crane.fold`) of the root face's plane; else `SettleStartNotFlat`. |
| R-07-8 | Contact pairs are `recordBefore`'s `faceOrders` between faces in one plane, each written (lower, upper) by the z sign of the normal of the face the order is read against. Every consequence is added first (A below B and B below C gives A below C); only then are pairs dropped in which neither face has a vertex left free. Dropping first loses A below C whenever B and C are fully held. |
| R-07-9 | Only steps with a `settle` block are settled. |
| R-07-10 | Before M6 the parser refuses settle and material blocks as not yet supported. From M6 until M8, `run --check` checks them, `run` skips them, `--report` counts them, and only `senbazuru-material-study --sequence SOURCE DIR` settles them. |

**Regions.**

| ID | Requirement |
| --- | --- |
| R-07-11 | Holds, grips and refinement use [the vocabulary](#naming-holds-and-grips), resolved against one record; no `FaceId`, `EdgeId` or mesh id in a source. |
| R-07-12 | A region with no mesh vertex → `EmptyRegion`, naming it as written. |
| R-07-13 | `band S d0..d1` (S is `moving` or `stationary`) takes the vertices on side S whose distance from the hinge line in `recordBefore`, in sheet lengths, lies in [d0 − t, d1 + t], with t = `Fold.Faces.tolerance` (R-07-7). |
| R-07-14 | `layer upper\|lower of R` splits R by `recordBefore`'s orders; unordered coincident samples → `AmbiguousLayer`. |
| R-07-15 | Targets: `rigid-pose p`, the rigid state a fraction p of the way through the move's turn, via `recordPoseAt` (`SettleNoPose` for `StateOnly`, `NoMotion`, `Presented`), or a registered generator; v1 `arc-grip` accepts 30° then 0°–20°, else `GripOutOfRange`. |
| R-07-16 | A generator also sets the start positions of free vertices on its side; otherwise they start at their side's rigid-pose target, else `recordBefore`. |
| R-07-17 | A vertex whose targets differ by more than `1e-12 × modelSpan` → `ConflictingTargets`, naming both regions. |

**Rest, stiffness, difference.**

| ID | Requirement |
| --- | --- |
| R-07-18 | Rest angles only from `RestAngles`; never from an assignment. |
| R-07-19 | Rest comes from the settle, else the material block; neither → `SettleNoRest`. |
| R-07-20 | `NoDifference` when rest is `RestAtPose PoseBefore` without exceptions and every target is within `1e-12 × modelSpan` of `recordBefore`. |
| R-07-21 | Stiffness is a named preset; v1's `illustrative` = `Bending 1 0.2` (crease stiffness 1, panel stiffness 0.2), labelled so in outputs. |
| R-07-22 | The solver budget comes from consumer settings, never the source. |
| R-07-23 | `settleStep :: SettleSpec -> MoveRecord -> …` resolves; from M8 `Material.Settle.settle` takes a resolved `SettleInput` and a `Surface V2`, importing no `Sequence` module. |

**Material block.**

| ID | Requirement |
| --- | --- |
| R-07-24 | Physical lengths only in `material { … }`, with unit suffixes; model value = physical ÷ sheet size × s, as a `Rational`, where s is the larger side of the sheet's box as the resolver records it in `Double`, converted with `toRational`. |
| R-07-25 | A physical `frame_unit` (any FOLD value but `unit`, [fold-reference.md:58](../docs/fold-reference.md)) disagreeing with `sheet` → `UnitMismatch`. |
| R-07-26 | Thickness is stored, not interpreted; `--report` says so. |
| R-07-27 | Display parameters (fidelity modes, exaggeration, colours, camera, textures) are render options, never sequence data: [04](04-prd-sequence-source-and-cli.md)'s `materialitem` has no production for them, so writing one is 04's parse error. |

**Illustrations and failure.**

| ID | Requirement |
| --- | --- |
| R-07-28 | Settled geometry never replaces a rigid figure, glTF scene or animation keyframe, and never enters `motionsBetween`/`motionsAcross`, a page basis or extent, or a later step. |
| R-07-29 | Rigid outputs are byte-identical with and without settle blocks whenever all settles are accepted or `--allow-unsettled` is absent. |
| R-07-30 | Each accepted settle writes `STEM.settled-NAME.glb` and `.svg` (NAME: step name or 1-based index). |
| R-07-31 | Settled GLB: complete-sheet scene first, visible scene only if it exports; `extras.senbazuru` has step, spec, verdict, fidelity. |
| R-07-32 | Settled SVG: the rigid page's camera, its own extent, never a grid cell. |
| R-07-33 | Failures scoped per [the failure table](#settled-output-is-an-illustration). |
| R-07-34 | `--allow-unsettled` (study at M6, `run` at M8): exit 0, nothing substituted, unsettled steps and reasons in rigid metadata. |
| R-07-35 | Unaccepted meshes only under a labelled flag, to FOLD or complete-scene GLB, never SVG. |

**Certificates.**

| ID | Requirement |
| --- | --- |
| R-07-36 | A study-only registry keyed by macro name and *fixture fingerprint* ([glossary-additions](glossary-additions.md#assurance)) attaches `Certified \| NoCertificateFor \| Refused` after the run. |
| R-07-37 | Unmatched patterns get `NoCertificateFor`, never `Refused`; `Refused` is never shown as `Sampled`; library and CLI say "sampled, not certified". |
| R-07-38 | A registry entry states its sample poses as `Rational`s of the macro's own driving parameter (`175 * fraction`), never as absolute angles, which give different `Double`s; checked by AC-12. |

**Graduation (M8), tools, errors.**

| ID | Requirement |
| --- | --- |
| R-07-39 | Seven stages in order, one PR each; 33 goldens and the study's accepted/rejected controls unchanged. |
| R-07-40 | #208's value-only line search before M6's crane equivalence PR (or that PR compares resolved sets without solving) and before M8. |
| R-07-41 | `run --settle` refuses more than 1,192 refined triangles, counted before solving, until 3–5 compiled runs after #208; default CI settles ≤ 392. |
| R-07-42 | Modules listed as staying in the study do not graduate. |
| R-07-43 | No CI job or test runs an external solver, simulator or other program whose output it reads (the build, format and lint tools excepted); each program used gets a `docs/related-projects.md` row with its licence *as built*; kept outputs get provenance in `examples/README.md`. |
| R-07-44 | External solvers are oracles only; IPC-family tools apply to open states until a thickness offset exists ([External tools](#external-tools)). A policy recorded in `docs/related-projects.md`, not a tested requirement, since R-07-43 keeps the tools out of CI. |
| R-07-45 | `SettleStepError`, `SettleError`, `Reason` and registry `Refused` each have an `Explain` instance in their own module; no locations in messages; ids as "(internal edge 37)". |

## Design

### The record, as the consumer reads it

| Field ([02](02-language-semantics.md); [decisions §5](decisions.md#5-type-sketch)) | Consumer's use |
| --- | --- |
| `recordStep`, `recordMoveIndex`, `recordLabel`, `recordSpan` | file names and the message prefix; `recordStep` and `recordMoveIndex` also bind a settle to its step's last moving record ([D14](decisions.md#d14-material-consumption)) |
| `recordKind`, `recordEvidence` | refusing non-moving kinds; `recordPoseAt`; settled extras |
| `recordBefore`, `recordAfter` | the start; contact orders; `rigid-pose before/after` |
| `recordHinge` (segments, ids) | `hinge of`, `across-hinge`, the line `band` measures from |
| `recordMoving`, `recordStationary` | `side moving`, `side stationary` |
| `recordNewCreases` | `crease-line` on newly creased paper |
| `recordAngles` | rest poses |
| `recordStacking`, `recordResolved`, `recordMacros`, `recordCost` | report; certificate binding |
| `recordAnchor`, `recordPresentation`, `recordPlacement` | display only, never before settling |

**On the crane wing**, `fold behind 90° corner north-west to midpoint of edge
north` has `recordBefore` = the creased, unturned crane: 76 faces
([`CraneWing.hs:66`](../study/fold-material/CraneWing.hs#L66)), 138 edges and 902
orders ([spreading-connected-wing.md:41-42](../docs/notes/spreading-connected-wing.md)).
`recordHinge` has four segments with `craneHinge`'s ids; `recordMoving` has seed
`corner north-west` and four faces ([`CraneSpreadSpec.hs:31`](../test/CraneSpreadSpec.hs#L31));
`recordAfter` keeps those 76 faces, since a flap turn never re-cuts
([`CraneWingSpec.hs:92`](../test/CraneWingSpec.hs#L92)). The 72-face crane is the
fold state the move receives, before the move adds its hinge crease;
`recordBefore` is taken after creasing so that its ids match `recordAfter`'s.

**Why unpresented.** `CraneSpread` converts orders by each face normal's z sign
([`CraneSpread.hs:108-114`](../study/fold-material/CraneSpread.hs#L108-L114)) and
solves along `V3 0 0 1` (`:138`); a turned-over surface would invert every pair.
`transformSurface` also empties frame extras
([`Surface.hs:292`](../src/Senbazuru/Origami/Surface.hs#L292)), including the
source-panel keys a settled GLB keeps ([`Gltf.hs:241`](../src/Senbazuru/Render/Gltf.hs#L241)).

**Why intent.** The hinge lies at 0 in `recordBefore`. The *state rule*
([glossary-additions](glossary-additions.md#the-fold-format)) would write it `F`;
`surfaceFeatures` would skip it ([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278))
and its segments would become [panel](../docs/glossary.md#geometry) bends
([`FoldBending.hs:169-171`](../study/fold-material/FoldBending.hs#L169-L171)). As
its [intent assignment](glossary-additions.md#the-fold-format) it stays an active crease whose rest must pass the M/V
sign check ([`:181`](../study/fold-material/FoldBending.hs#L181)). The four
segments alternate intent layer by layer ([02](02-language-semantics.md)), as their
signed angles do: "the two touching layers have opposite material normals"
([`CraneRoot.hs:80-82`](../study/fold-material/CraneRoot.hs#L80-L82)).

### Where a settle starts

From `recordBefore`, a *flat state*
([glossary-additions](glossary-additions.md#words-the-prds-narrow)), never
`recordAfter`:

1. `CraneSpread` refines the flat start (`:85`) and reads its orders; the rigid
   pose enters only as the hinge's rest angles (`:86`, `:89-91`). Grip and
   root-strip targets come from the `bentPoint` formula (`:105-107`, `:120-134`),
   which reproduces a rigid 30° turn without reading the pose.
2. `faceOrders` hold coplanar orders only
   ([`Surface.hs:257-263`](../src/Senbazuru/Origami/Surface.hs#L257-L263)); a wing
   at 90° shares no plane with the body.
3. A pair standing parallel to the contact direction is `UncheckableContactPair`
   ([`SurfaceContact.hs:189-191`](../study/fold-material/SurfaceContact.hs#L189-L191)).

The settled surface depicts rigid pose p with the named grips, not the move's end
state. Orders learned from a separated reference (`relaxDiscoveredContact`,
[`FoldRelaxation.hs:286-289`](../study/fold-material/FoldRelaxation.hs#L286-L289))
are a later registered option, never a fallback. Closure before filtering
([`CraneSpread.hs:141-150`](../study/fold-material/CraneSpread.hs#L141-L150)) is
pinned by [`CraneRootSpec.hs:59-61`](../test/CraneRootSpec.hs#L59-L61).

### Naming holds and grips

A *hold* fixes mesh vertices; a *grip* is a hold with a target
([glossary-additions](glossary-additions.md#material)). Each names a *region*, a
set of paper. The mesh does not exist until the settle refines, so a region is
resolved in two stages:

1. **Against the record.** A region is a set of *source panels*, the faces of
   `recordBefore` before refinement splits them into triangles, plus a test on
   each mesh point (a *sample*) that reads the sample's material coordinates or
   its position in `recordBefore`. The test is stored as data, not as a Haskell
   function, so regions can be compared and printed.
2. **Against the refinement.** Refinement records which panel each triangle came
   from and which source edge each split segment came from
   ([`Surface.hs:101-105`](../src/Senbazuru/Origami/Surface.hs#L101-L105),
   [`:398`](../src/Senbazuru/Origami/Surface.hs#L398)), and gives each inserted
   midpoint the average of its ends' material coordinates
   ([`:380`](../src/Senbazuru/Origami/Surface.hs#L380)). Only here does a region
   become mesh vertex ids.

In the table, S is `moving` or `stationary`, and R is any region, such as
`side moving` or `band moving 0..1/32`.

| Name | Resolves to |
| --- | --- |
| `side stationary`, `side moving` | panels outside or inside the record's moving faces |
| `across-hinge S` | panels on side S owning a hinge segment |
| `closed R` | every vertex of every triangle of R, shared boundary vertices included ([`CraneRoot.hs:52-55`](../study/fold-material/CraneRoot.hs#L52-L55)) |
| `band S d0..d1` | vertices on side S at distance d0–d1 sheet lengths from the hinge line in `recordBefore`; `d1` optional |
| `material-band u0..u1` | vertices by material u ([`WingBending.hs:62-63`](../study/fold-material/WingBending.hs#L62-L63)) |
| `crease-line [P, Q]` | refined vertices on creases along material segment [P, Q] |
| `hinge of NAME` | refined vertices on that move's hinge |
| `layer upper\|lower of R` | the part of R on one side of an order |
| `R union R'`, `R minus R'` | set operations |

`hold R` keeps R where `recordBefore` has it. `hold R at rigid-pose p` and
`grip R GENERATOR` both become grips `(SettleRegion, GripTarget)`. The type is
`SettleRegion`, not `Region`, because `Origami.Visible` already exports a `Region`
([`Visible.hs:103`](../src/Senbazuru/Origami/Visible.hs#L103);
[D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders)).
`rigid-pose p` is the rigid state a fraction p of the way through the move's
turn: `rigid-pose 1/3` of this 90° fold is the wing at 30°, `CraneSpread`'s
`flapAt … (30 / 90)`. The canonical spelling is
[04](04-prd-sequence-source-and-cli.md)'s.

The whole crane-wing source (header, `anchor`, `start folded`, the
`expect refused` line) is the "Crane wing" example of
[decisions §7](decisions.md#7-examples), the version
[04](04-prd-sequence-source-and-cli.md#example-sources-checked-against-their-fixtures)
carries, and why its fold line, flap and direction are right is
[02 §6.3's crane example](02-language-semantics.md#63-which-layers). Its
`expect refused` line names `FlapCovered`, **UNVERIFIED**
([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)), not the
`FlapEndpointOrder` that the recipe gets in
[One move, fed by hand](#one-move-fed-by-hand). The sequence's layer selection refuses a covered flap
before `Flap`'s sweep runs ([D8](decisions.md#d8-folding-some-layers)), while
`CraneWing` calls `prepareFlapAlong` with no selection step
([`CraneWing.hs:80-84`](../study/fold-material/CraneWing.hs#L80-L84)), so only
the recipe reaches `Flap`'s refusal. This file adds the `material` line and the
`settle` block. Below they are shown in the step they belong to, copied exactly
from §7 with the `expect refused` line left in, so what you copy is §7's step.
`stiffness illustrative` means `Bending 1 0.2`, the value
[`CraneSpread.hs:98`](../study/fold-material/CraneSpread.hs#L98) passes
(**Stiffness**, below).

```text
material { stiffness illustrative }

step wing "Fold the underneath wing away from you until it stands straight out." {
  expect refused FlapCovered { fold in front 90° corner north-west to midpoint of edge north }   # UNVERIFIED kind
  fold behind 90° corner north-west to midpoint of edge north
  settle {
    refine side moving 3
    rest at rigid-pose 1/3
    hold closed side stationary
    hold band moving 0..1/32 at rigid-pose 1/3    # UNVERIFIED: equals CraneSpread's root-strip pins
    grip band moving 7/32.. arc-grip 30° 20°      # UNVERIFIED: equals CraneSpread's grip pins
  }
}
```

Two lines of the `settle` block are decided, not incidental
([D14](decisions.md#d14-material-consumption), [C41](decisions.md#changes-since-draft-v2)).
`refine` takes a region, `refine REGION INTEGER`, because control 2 below
refines `side moving union across-hinge stationary`, which a side word alone
cannot say; [decisions §6](decisions.md#6-grammar) lists the change to 04's
`settleitem` production. And the `rest` line is required: with no rest in the
settle or the material block, R-07-19 refuses the settle as `SettleNoRest`.

- **Band ends.** The tip side is 1/4 long and s = 1, so 1/32 and 7/32 are
  `fraction` 0.125 and 0.875. **The slacks differ.** `CraneSpread` adds `1e-8`
  in fraction units, 2.5e-9 sheet lengths; R-07-13 adds `Fold.Faces.tolerance`,
  1.41e-9 on `crane.fold`. AC-1 fails if any refined vertex lies in the gap
  between them: more than 1.41e-9 but no more than 2.5e-9 beyond 1/32, or the
  same distance short of 7/32.
- **Root-strip target.** Within 1/32 of the hinge, `bentPoint` is a rigid 30°
  turn about y = 1/4, z = 0 for any extra angle (`middle` and `after` vanish,
  `:128-134`). At the tip with extra 0 it gives (x, 1/4 − 1/4 cos 30°,
  −1/4 sin 30°), the formula `CraneWingSpec.hs:98-99` checks `flapAt` against
  within 1e-12, but only at progress 0, 0.17, 0.51, 0.83, 1
  ([`:89`](../test/CraneWingSpec.hs#L89)). Equality at 1/3 is **UNVERIFIED**.
- **Grip.** `bentPoint` hard-codes hinge y = 0.25, length 0.25 and root 30°
  (`:122-125`); the registered `arc-grip` must read them from the record and
  bands. **UNVERIFIED** until AC-1.

### Every existing crane control, re-expressed

From [gap-study-consumption-contract](research/gap-study-consumption-contract.md)
"(b) Hold, grip and contact names that survive refinement and re-cutting", every
line re-read; rows 15–21 correct or extend it.

| # | Control | Code | Against the wing record | Status |
| --- | --- | --- | --- | --- |
| 1 | refine wing | [`CraneSpread.hs:95-96`](../study/fold-material/CraneSpread.hs#L95-L96) | `refine side moving 3` | yes |
| 2 | + root neighbours | `:97` | `refine side moving union across-hinge stationary 3` | yes |
| 3 | body | `:101` | `hold closed side stationary` (hinge vertices included, unmoved at `:105`) | yes |
| 4 | selected | `:102` | `closed side moving` | yes |
| 5 | root strip at 30° | `:103`, `:106` | `hold band moving 0..1/32 at rigid-pose 1/3` | UNVERIFIED |
| 6 | tip grip | `:104-105` | `grip band moving 7/32.. arc-grip 30° EXTRA°` | UNVERIFIED |
| 7 | contact pairs | `:108-114`, `:141-150` | derived (R-07-8) | yes |
| 8 | root edges | [`CraneRoot.hs:60`](../study/fold-material/CraneRoot.hs#L60) | `hinge of wing` | yes |
| 9 | root neighbours `[7, 8, 27, 43]` | `:60-63`; [`CraneRootSpec.hs:34`](../test/CraneRootSpec.hs#L34) | `across-hinge stationary` | yes |
| 10 | distant | `:67` | `closed (side stationary minus across-hinge stationary)` | yes |
| 11 | `HeldRoot` | `:58`, `:69` | rows 3 + 5 + 6, refined as row 2, extra 20° | yes |
| 12 | `ReleasedRoot` | `:68-69` | rows 3 + 6 | yes |
| 13 | `FlatRoot` | `:73` | row 12 + `rest at rigid-pose 1/3 except { hinge of wing at 0° }` | yes |
| 14 | `FreeBody` | `:67-68`, `:74` | rows 10 + 6 + row 13's rest | yes |
| 15 | `WeakerRoot` (stiffness × 0.1 on root) | `:72` | none: one global `stiffness` | **fixture** |
| 16 | `CraneBody` `OpenBody` (±170° on `EdgeId` 21, 46) | [`CraneBody.hs:66`](../study/fold-material/CraneBody.hs#L66), `:71`; [`CraneBodySpec.hs:28`](../test/CraneBodySpec.hs#L28) | row 14 + `rest … except { crease [P, Q] at ±170°; … }`. The research row *held* these creases; the code changes their springs | yes once segments are read (UNVERIFIED); pocket roles stay fixture data ([`CranePocket.hs:46-50`](../study/fold-material/CranePocket.hs#L46-L50)) |
| 17 | `CraneBody` `WeakerBody` | `:70` | none, as row 15 | **fixture** |
| 18 | `CraneInternal` `HeldLines` (creases 26, 51; 9 vertices per line; 16 added) | [`CraneInternal.hs:55`](../study/fold-material/CraneInternal.hs#L55), `:62-64`; [`CraneInternalSpec.hs:30`](../test/CraneInternalSpec.hs#L30), `:50` | `hold crease-line [P, Q] union crease-line [R, S]` | yes once segments are read (UNVERIFIED) |
| 19 | `InternalForces`, `FixedPatch`, `ContinuedPatch` | `:8-11`, `:52`, `:60-61`, `:79-82` | none: force restriction, borrowed orders, budget continuation; "always a diagnostic" | **fixture** |
| 20 | `crossedGrip` | [`CraneSpread.hs:155-163`](../study/fold-material/CraneSpread.hs#L155-L163) | `layer upper of band moving 7/32..` (`:161`); the −0.005 offset (`:162`) has no target | **fixture** |
| 21 | `WingBending` root, grip | [`WingBending.hs:62-63`](../study/fold-material/WingBending.hs#L62-L63) | `material-band 0..1/8`, `7/8..1` | own mesh, no record: **fixture** |

Cautions kept from the note. A hold is not the
[anchor](glossary-additions.md#running-a-sequence): a hold pins vertices for one
solve, while the anchor is the face folding keeps still. Two layers at the same
folded position are different paper, so a band picks both, and
`layer upper|lower` chooses one. Tests that pin ids today
([`CraneRootSpec.hs:34`](../test/CraneRootSpec.hs#L34)'s root-neighbour faces,
[`CraneInternalSpec.hs:27`](../test/CraneInternalSpec.hs#L27)'s face pairs) will
instead assert the material point each of those faces contains. Their counts stay:
902 orders ([`CraneRootSpec.hs:40`](../test/CraneRootSpec.hs#L40)) and 16 added
hold vertices ([`CraneInternalSpec.hs:50`](../test/CraneInternalSpec.hs#L50)).
Each is a reviewed test change.

### Rest angles, stiffness and NoDifference

```haskell
-- SKETCH: Sequence.Material
data RestAngles = RestAtPose PoseRef | RestAtPoseExcept PoseRef [(CreaseLine, Rational)]  -- degrees, FOLD sign, as seen
data PoseRef = PoseBefore | PoseAfter | PoseOnRoute Rational                              -- 02's type
```

**Equivalence.** `RestAtPose (PoseOnRoute (1/3))` rests each hinge segment at its
angle one third of the way through the turn (as `:89-91`) and every other active crease at its
unchanged angle. `crane.fold` has no `edges_foldAngle` and its active non-border
creases are its 58 M and 41 V (jq above), at ±180°.
`python3 -c 'import math; print(-180*math.pi/180 == -math.pi, 180*math.pi/180 == math.pi)'`
prints `True True`, and GHC's `Double` shares IEEE semantics (not run in GHC), so
the targets map can equal [`CraneSpread.hs:94`](../study/fold-material/CraneSpread.hs#L94)
exactly.

**`NoDifference`** (R-07-20): springs resting at the start and targets in it
leave nothing to move ([B](research/B-material-study-mechanics.md) finding 6).
The rule reads only the rest pose and the targets, so it is computed before any
solve ([D14](decisions.md#d14-material-consumption),
[C39](decisions.md#changes-since-draft-v2)). Releasing a hold is not a condition:
from an equilibrium start it cannot move anything, and it matters only with a
moved grip or another rest pose, as in `ReleasedRoot`.

`NoDifference` catches only a settle whose answer is its own start: it would
write a copy of `recordBefore`, which the rigid outputs already draw. The rigid
baseline (`craneSpread source 3 0`) also shows no bending (panel energy
1.44e-27), yet it is allowed: it rests and grips at the rigid pose 1/3 of the way
through the turn, a state no rigid figure of this step draws, and it is the
control showing that the solver reproduces a rigid pose within 1e-8
([`CraneSpreadSpec.hs:59-64`](../test/CraneSpreadSpec.hs#L59-L64)).

**Stiffness.** `illustrative` = `Bending 1 0.2`, crease stiffness 1 and panel
stiffness 0.2 ([`FoldBending.hs:59-62`](../study/fold-material/FoldBending.hs#L59-L62)), as every crane and wing fixture
([`CraneSpread.hs:98`](../study/fold-material/CraneSpread.hs#L98),
[`WingBending.hs:65`](../study/fold-material/WingBending.hs#L65)).

**Precrease stiffness (owner decision 4).** A *precrease*
([glossary-additions](glossary-additions.md#origami)) keeps M/V intent at 0, so
it settles as an active crease resting at 0 with *crease* stiffness; an `F` edge
from the sheet file stays a panel bend with *panel* stiffness
([`FoldBending.hs:169-171`](../study/fold-material/FoldBending.hs#L169-L171)).
The two resist differently. A crease spring is weighted by its material length
alone, while a panel bend is also weighted by the areas of the two triangles
beside it, so a line settled as a crease can concentrate the turn at that line
where panel paper would spread it through the paper nearby
([wing-root-holds.md:87-92](../docs/notes/wing-root-holds.md)).

### SettleSpec and SettleInput: two contracts

**Two error types** ([D14](decisions.md#d14-material-consumption),
[C6](decisions.md#changes-since-draft-v2)). Constructors that name a move
(`SettleOnNoMove`, `SettleNoPose`, `SettleNoRest`, `NoDifference`) cannot live in
`Material.*`, which knows no moves ([decisions §2](decisions.md#2-shape), row 5).
So `Sequence.Material`'s `SettleStepError` holds them and wraps
`Material.Settle`'s `SettleError` as `SettleFailed`.

```haskell
-- SKETCH. Sequence.Syntax (library; grammar is 04's): what the text says
data SettleRequest = SettleRequest { reqRefine :: (RegionExpr, Int), reqRest :: Maybe RestExpr
                                   , reqHolds :: [RegionExpr], reqGrips :: [(RegionExpr, TargetExpr)] }
-- SKETCH. Sequence.Material (study M6, library M8): names bound
data SettleSpec = SettleSpec { refinement :: (SettleRegion, Int), stiffness :: Bending, rest :: RestAngles
                             , holds :: [SettleRegion], grips :: [(SettleRegion, GripTarget)], budget :: Settings }
settleStep :: SettleSpec -> MoveRecord -> Either SettleStepError Settled
data SettleStepError = SettleOnNoMove | SettleStartNotFlat VertexId Double | SettleNoPose PoseRef | SettleNoRest
                     | NoDifference | EmptyRegion Text | AmbiguousLayer | ConflictingTargets | GripOutOfRange
                     | UnitMismatch | TriangleBudget Int | SettleFailed SettleError
-- SKETCH. Material.Settle (library M8): resolved against one record; knows no moves
data SettleInput = SettleInput { refinement :: (Int, Set FaceId), stiffness :: Bending, rest :: Map EdgeId Double
                               , holds :: [Resolved], grips :: [(Resolved, SampleTarget)], contact :: [(FaceId, FaceId)] }
settle :: SettleInput -> Surface V2 -> Either SettleError Settled
data Settled = Settled { settledSurface :: Surface V2, settledReport :: SettleReport, settledVerdict :: Verdict }
data Verdict = Accepted | Diagnostic [Reason]
```

**`SettleInput`'s ids look like the ids R-07-11 bans, and are not.** `SettleInput`
is resolved against one record's surface for one call, so its `FaceId`s and
`EdgeId`s are that surface's and never outlive the call. The ban is on ids in a
*source*, where creasing would renumber them. A `Resolved` is a region after stage
1 of [Naming holds and grips](#naming-holds-and-grips): source panels plus a sample
test. A `SampleTarget` is likewise a rule, evaluated at each refined sample (a
rigid motion per source panel, or a generator's numbers read from the record),
because the samples do not exist until `settle` refines. So mesh ids exist only
inside `settle`. Both ends of `settleStep` are contracts:
[01 §2.2](01-architecture.md#22-contract-1-moverecord) and
[§2.3](01-architecture.md#23-contract-2-the-settle-input).

### The material block and physical units

```text
material { size 15cm; thickness 0.1mm; stiffness illustrative }
```

The items are spelled as in 04's `materialitem` production. On `crane.fold`, s is
exactly 1 (the box check under [One move, fed by hand](#one-move-fed-by-hand)), so
thickness = 0.1 mm ÷ 150 mm × 1 = 1/1500 model units,
stored by `withPhysicalThickness`, whose header says no renderer or contact check
interprets it ([`Surface.hs:298-304`](../src/Senbazuru/Origami/Surface.hs#L298-L304)),
and copied to GLB `physicalThickness` ([`Gltf.hs:243`](../src/Senbazuru/Render/Gltf.hs#L243)).
`thickness 0.1` is a parse error ([04](04-prd-sequence-source-and-cli.md)).
Row 11 of [01 §4](01-architecture.md#4-recorded-text-this-design-changes) appends
to AGENTS.md "Two unit systems" that physical lengths "become model units in
exactly one place", when `Sequence.Material` resolves a settle. 01 lands that row
with M2, before the block exists at M6.

`frame_unit` is decoded ([`Types.hs:148-149`](../src/Senbazuru/Fold/Types.hs#L148-L149)).
`for f in examples/*.fold; do jq -r '.frame_unit // empty' "$f"; done | sort | uniq -c`
prints `20 unit`, so `UnitMismatch` is tested on a frame built in Haskell (for
example `mm`, s = 100, `size 15cm`), comparing sizes within the relative `1e-9`
of `Fold.Faces.tolerance`.

### Settled output is an illustration

Accepted settles write `crane.settled-wing.glb` and `.svg`. The GLB puts the
complete sheet first and adds the visible scene only if it exports, because the
two fail independently ([#206](https://github.com/avalonalex/senbazuru/issues/206);
the study already falls back, [`CraneRootGallery.hs:76-87`](../study/fold-material/CraneRootGallery.hs#L76-L87)).
Today ([`Gltf.hs:147`](../src/Senbazuru/Render/Gltf.hs#L147),
[`:231-235`](../src/Senbazuru/Render/Gltf.hs#L231-L235)) `VisiblePaper` writes
the visible scene then the complete one, and fails outright if the visible scene
fails; `CompletePaper` writes only the complete scene. A writer that puts the
complete sheet first and drops a failed visible scene is
[08](08-prd-realistic-rendering.md)'s. Until M7b's line
drawing, the SVG uses today's path, which "retains some buried crease lines" on
these meshes ([`docs/usage.md:464-465`](../docs/usage.md)); the study writes SVG
only when accepted ([`CraneRootGallery.hs:81-90`](../study/fold-material/CraneRootGallery.hs#L81-L90)).

| Step k's settle | k's settled files | Other settles | Rigid outputs | Exit |
| --- | --- | --- | --- | --- |
| `Accepted` | written | run | written, unchanged | 0 if all accepted |
| `Left SettleStepError` | none | run | written, unchanged | nonzero, names k |
| `Diagnostic reasons` | none | run | written, unchanged | nonzero, names k and reasons |
| either failure, `--allow-unsettled` | none | run | written + unsettled record | 0 |
| rigid run fails | none | not run | refused | nonzero |

A nonzero exit after writing matches `check` ([`Cli.hs:956`](../app/Senbazuru/Cli.hs#L956)).
The unsettled record goes in the file's key frame under a new key,
`senbazuru:unsettled` (**SKETCH**; not vertex-indexed, so
[D4](decisions.md#d4-written-frames-follow-the-state-rule)'s key-frame rule
allows it until [#73](https://github.com/avalonalex/senbazuru/issues/73)), GLB
`extras.senbazuru`, and SVG `<desc>` (08). Unaccepted meshes never go to SVG,
whose painter assumes the layer order they can violate
([`docs/architecture.md:402-404`](../docs/architecture.md)); the study keeps
a failed endpoint as a diagnostic that "never appears as an accepted model"
([spreading-connected-wing.md:64-69](../docs/notes/spreading-connected-wing.md)).

### Certificates attach after the run

```haskell
-- SKETCH. study/fold-material only; never graduates
data CertificateEntry = CertificateEntry
  { entryMacro   :: MacroName
  , entryBind    :: MoveRecord -> Either Unbound Binding          -- the fingerprint as data
  , entryCertify :: Binding -> [(Int, Int)] -> Either Text PetalCertificate }
attachCertificates :: [MoveRecord] -> [(MoveRecord, CertificateOutcome)]
data CertificateOutcome = Certified PetalCertificate | NoCertificateFor Unbound | Refused Text
```

Certificates are bound to one fixture: all four are `Bool -> [(Int, Int)] ->
Either Text PetalCertificate` ([`PetalCertificate.hs:262`](../study/fold-material/PetalCertificate.hs#L262),
[`:281`](../study/fold-material/PetalCertificate.hs#L281), [`:286`](../study/fold-material/PetalCertificate.hs#L286),
[`:290`](../study/fold-material/PetalCertificate.hs#L290)), hard-coding 16 panels
([`:295`](../study/fold-material/PetalCertificate.hs#L295)) and vertices 0–12
([`:315`](../study/fold-material/PetalCertificate.hs#L315)). The `[(Int, Int)]`
is the accepted face orders as (lower, upper) pairs. The `Bool` picks one of two
length-preserving routes that mirror each other (the parameter is named `above`
in `certifyPetal` and `below` in the other three), and only one lands in the
bird's layer order: the recipes pass `True` to all four
([`CheckedBird.hs:64-66`](../study/fold-material/CheckedBird.hs#L64-L66),
[`CheckedPetal.hs:57`](../study/fold-material/CheckedPetal.hs#L57)), and
[`CheckedPetalSpec.hs:51`](../test/CheckedPetalSpec.hs#L51) expects
`certifyPetal False` to be refused. `entryBind` is
`preparePetal`'s guards as data ([`CheckedPetal.hs:47-60`](../study/fold-material/CheckedPetal.hs#L47-L60)):
material vertices (`:50`), cut faces and the 28-pair edge list (`:52`, `:62`), and
the stationary panel (0.58, 0.4) (`:53`), the bird sequence's `anchor (29/50, 2/5)`.
`jq -c '{nv:(.vertices_coords|length), ne:(.edges_vertices|length), nf:((.faces_vertices // [])|length), unit:.frame_unit}' examples/bird-base.fold`
prints `{"nv":13,"ne":28,"nf":0,"unit":"unit"}`.

| Bird stage ([02](02-language-semantics.md)) | Entry | Run input |
| --- | --- | --- |
| `collapse at centre until 180°` | `certifyCollapse True` | orders accepted by the first petal at 175° ([`CheckedBird.hs:61-64`](../study/fold-material/CheckedBird.hs#L61-L64)); landing orders withheld until landing ([`:131-137`](../study/fold-material/CheckedBird.hs#L131-L137)) |
| first `petal tip … until 175°` | `certifyPetal True` | same orders |
| second `petal tip … until 175°` | `certifySecondPetal True` | same; first petal held at 175° |
| `together { continue …; continue … }` | `certifyPress True` | the 175°→180° suffix ([`:87`](../study/fold-material/CheckedBird.hs#L87)) |

The press step is one move and one record. `together` gives a single record whose
`recordMacros` holds one `MacroBinding` per member, each naming the line it
continues (`bindLine` `first-petal` or `second-petal`)
([D9](decisions.md#d9-macro-moves-as-named-angle-relations),
[C12](decisions.md#changes-since-draft-v2)). So `certifyPress`'s entry binds
against the two bindings of that one record, not against two records.

Which corner the certificates' first petal lifts is **UNVERIFIED**; M5 derives it.
Why this shape ([gap-study-consumption-contract](research/gap-study-consumption-contract.md)
"(c) Certificates attach after the run, in the study"): indices belong to one
pattern, so the key includes the fingerprint; later certificates need accepted
orders, available only after the run; runner hooks would make CLI and study
records differ unexplained; samples use the macro's parameter (`175 * fraction`,
[`:85`](../study/fold-material/CheckedBird.hs#L85)); `Refused` is never rendered
as `Sampled` (same section), following the study's rule that failures are
labelled, never replaced (B finding 16).

### Graduation, staged and gated

| Stage | From (study) | To | What it fixes |
| --- | --- | --- | --- |
| 1 | `ContactRow` ([`FoldContact.hs:37`](../study/fold-material/FoldContact.hs#L37)); `meshEdges`, `edgeStrains`, `componentCount` ([`FoldMaterial.hs:181`](../study/fold-material/FoldMaterial.hs#L181), `:187`, `:207`) | split within study | the solver imports fixtures ([`FoldRelaxation.hs:102-104`](../study/fold-material/FoldRelaxation.hs#L102-L104)); delete `PacketContact` ([`:297`](../study/fold-material/FoldRelaxation.hs#L297)) |
| 2 | `SparseSolve`, `DirectionalDistance` | `Numeric.*` | graduates stating it is "not a bounded-memory solver for arbitrary meshes" ([`SparseSolve.hs:16-17`](../study/fold-material/SparseSolve.hs#L16-L17)) |
| 3 | surface hinges ([`FoldBending.hs:146-156`](../study/fold-material/FoldBending.hs#L146-L156)) | `Material.Bending` | drops fixture `buildHinges` ([`:124-136`](../study/fold-material/FoldBending.hs#L124-L136)), `PacketRestAngles` |
| 4 | penalty rows, `prepareContact` ([`SurfaceContact.hs:131-144`](../study/fold-material/SurfaceContact.hs#L131-L144)) | `Material.Contact` | barrier rows stay: only `relaxBarrierLocalHistory` uses them ([`FoldRelaxation.hs:416-417`](../study/fold-material/FoldRelaxation.hs#L416-L417)); `relaxPinnedContact` uses penalty ([`:256-261`](../study/fold-material/FoldRelaxation.hs#L256-L261)) |
| 5 | `relaxPinnedHinges`, `relaxPinnedContact`, `diagnosePinnedContact` ([`:248-269`](../study/fold-material/FoldRelaxation.hs#L248-L269)) | `Material.Relax` | structured errors; `SpreadError` wraps `Text` ([`CraneSpread.hs:70`](../study/fold-material/CraneSpread.hs#L70)) |
| 6 | `spreadSurface` ([`:189-232`](../study/fold-material/CraneSpread.hs#L189-L232)) replacing [`UncreasedSurface.hs:30`](../study/fold-material/UncreasedSurface.hs#L30), [`WingLayers.hs:108`](../study/fold-material/WingLayers.hs#L108), [`ClosedCrease.hs:116`](../study/fold-material/ClosedCrease.hs#L116); `spreadAccepted` ([`:179-183`](../study/fold-material/CraneSpread.hs#L179-L183)) | `Material.Export`, `Material.Verdict` | `Reason`s = today's gates: converged, edge error ≤ 1e-5, held error 0, crease error < 1e-5, contact passed (`:183`) |
| 7 | `Sequence.Material`; `settle` | `Sequence.Material`, `Material.Settle` | `run --settle`, `--allow-unsettled` |

**Stays in the study:** `ContactQuadratic`, `CreasePairContact`, `CoupledCrease`,
`UnequalCrease`, `CreaseInequality`; discovery, history and correction-sweep
modes; barrier rows; `ClosedCrease`; `FoldMaterial`'s rounded bends; `Crane*` and
`Wing*` recipes and galleries; `PetalCertificate` and the registry.

**Gates.** #208 first: contact rows take about 68% of profiled time. 1,192
triangles is the largest accepted crane-wing mesh with a recorded solve time
(64.30 CPU s, one run). The 4,312-triangle flat-preference crane-root mesh also
passed its checks ([wing-root-holds.md:18-20](../docs/notes/wing-root-holds.md),
`:32`, `:40`) but has no recorded solve time. The crane-wing note calls
two resolutions "a useful comparison, not evidence that the answer has stopped
depending on the mesh" ([spreading-connected-wing.md:47-48](../docs/notes/spreading-connected-wing.md)).
392 (5.76 CPU s) is the default-CI ceiling; larger settles run in the slow job
with fixtures in `beforeAll` ([glossary-additions](glossary-additions.md#code-and-tests)).
Budgets count refined triangles before solving, never seconds.

### External tools

| Tool | Licence as built | What it is | Allowed use |
| --- | --- | --- | --- |
| Origami Simulator | MIT ([`docs/related-projects.md:22`](../docs/related-projects.md)) | WebGL browser app; FOLD in and out; its README shows no headless mode | [#53](https://github.com/avalonalex/senbazuru/issues/53)'s manual or browser-automated export; oracle |
| ipc-toolkit | MIT | C++ library adding contact to an existing simulation, not a simulator itself; authors ask for citation | a driver is new non-Haskell code: a toolchain decision |
| Codim-IPC | Apache-2.0 source; default build links GPL CHOLMOD Supernodal (`LINEAR_SOLVER=CHOLMOD`, `WITH_GPL` on) | IPC shells, rods, particles | user-installed, `WITH_GPL=OFF` or Eigen; copying brings Apache-2.0 §4 obligations |
| Doodle (GPLv2), Rabbit Ear (GPL-3.0), ReferenceFinder (GPL-2.0), Creasy (GPL-3.0), ORIPA (GPL-3.0) | GPL | reference implementations | ideas only ([`AGENTS.md:132-138`](../AGENTS.md)) |

Licence rows are from [gap-study-consumption-contract](research/gap-study-consumption-contract.md)
"(e) Licences for driving external solvers" (fetched pages, `gh api`); a reading,
not legal advice. IPC (Incremental Potential Contact) keeps surfaces apart with a
*barrier* energy ([glossary-additions](glossary-additions.md#material), *penalty
contact / barrier contact*) that grows without bound as two surfaces approach. So
layers stacked at zero distance, as in a flat fold, cannot be its starting state:
they need a *thickness offset*, the layers first moved apart by a small distance
([G](research/G-realistic-rendering-and-simulation.md) "B. Geometry models, and
whether a sequence could feed them", finding 13, derived). IPC-family tools
therefore apply to open states only.

**The rule goes into AGENTS.md.** [D17](decisions.md#d17-third-party-and-external-tools)
decides that running an external program and reading its output is not
vendoring. The program still needs a `docs/related-projects.md` row with its
licence *as built*, and any output kept needs provenance in `examples/README.md`.
No CI job or test may depend on it, and an external solver is a comparison
oracle, never ahead of the in-repo path. The wording lands at M0 as
[decisions §3](decisions.md#3-recorded-text-this-design-changes) row 8;
[01 §4.8](01-architecture.md#48-agentsmd-third-party-material) holds the exact
text, so this file does not repeat it.

### Errors

Messages are **SKETCH**es, prefixed "step N (name): settle: " without rewording
nested `explain`; `num` for measured values, `tshow` for ids and counts.

| Constructor | Example message |
| --- | --- |
| `SettleOnNoMove` | "this step turns no paper; put the settle block in the step that folds" |
| `SettleStartNotFlat` | "the paper before the move is not flat: (internal vertex 2) lies 0.25 off its plane" (vertex 2 is the tip in the record's numbering, [`CraneWing.hs:72`](../study/fold-material/CraneWing.hs#L72); 0.25 is its depth after the wing's 90° turn, `CraneWingSpec.hs:99`) |
| `SettleNoPose`, `SettleNoRest` | "rigid-pose 1/3 needs a checked route; this checkpoint records none" · "no rest pose in the settle or material block" |
| `NoDifference` | "the paper rests where it starts and no grip moves it, so the solve would return it unchanged" |
| `EmptyRegion` | "`band moving 3/10..` has no mesh vertex at refinement 3" (the moving side is 1/4 long) |
| `AmbiguousLayer` | "`layer upper of band moving 7/32..`: (internal vertex 212) and (internal vertex 305) lie at one place with no order between their faces" |
| `ConflictingTargets` | "`hold side moving` and `grip band moving 7/32.. arc-grip 30° 20°` both fix (internal vertex 118), at places 0.012 apart" |
| `GripOutOfRange` | "`arc-grip 30° 25°`: this generator takes a 30° root and a further 0°–20°" |
| `UnitMismatch` | "the sheet file is 100 mm across (frame_unit mm) but the material block says `size 15cm`" |
| `TriangleBudget` | "4,312 triangles; settles accept at most 1,192 until measured otherwise" |
| `RefineRefused` etc. | nested `explain` unchanged, e.g. a non-convex panel ([`Surface.hs:343`](../src/Senbazuru/Origami/Surface.hs#L343)) |
| `Reason` | "not converged after 118 iterations; relative edge error 3.75e-5; 49 crossing triangle pairs" ([body-angle-preferences.md:72-77](../docs/notes/body-angle-preferences.md)) |
| `Refused` | "petal certificate refused: bird path contact unresolved for panels …" ([`PetalCertificate.hs:301`](../study/fold-material/PetalCertificate.hs#L301)) |

Apart from vertex 2 in `SettleStartNotFlat`, the ids and the distance in these
messages show format only; they were not taken from a run.

### Rejected alternatives

| Alternative | Why not |
| --- | --- |
| `settle :: SettleSpec -> Surface V2` as the whole interface | a surface has lost hinge, sides and route |
| two records per crease-then-turn move | one record whose before is creased and unturned keeps one numbering |
| state-rule record surfaces with a separate intent field | the solver drops the hinge at 0 |
| settling from `recordAfter`; a default settle | no coplanar orders; a rigid state is already settled |
| settled frames replacing rigid figures or keys | the next figure snaps back; pages and animations mix topologies |
| rest from assignments, by `EdgeId` in a source or `SettleSpec`, or at achieved angles | springs shut precreases; creasing renumbers ids; a no-op |
| holds by `FaceId` or mesh id; `band` as a fraction of extent | ids renumber; sheet lengths are the one unit |
| certificate hooks in the runner | the CLI passes none |
| graduating barrier rows; wall-clock settle limits | unused by graduated solves; counts behave alike everywhere |
| substituting rigid meshes, or an external solver, on failure | hides failure (B finding 16); licence, toolchain, IPC cannot start flat |

## Acceptance criteria

| # | Check | Turns red when |
| --- | --- | --- |
| AC-1 | Wing record's resolved pins equal `spreadPins` of `craneSpread source 3 20` ([`CraneSpreadSpec.hs:26`](../test/CraneSpreadSpec.hs#L26)): same ids, positions within 1e-12, without solving; M6's first test (R-07-11–16) | band in material coordinates; `closed` dropping shared hinge vertices; `rigid-pose` read at 30 instead of 1/3 |
| AC-2 | Refined surface equals `spreadRefined` | `refine side moving` also refining across the hinge |
| AC-3 | `RestAtPose (PoseOnRoute (1/3))` gives exactly `CraneSpread.hs:94`'s targets (R-07-18) | Mountain → +π slip; resting at `PoseAfter` |
| AC-4 | Contact pairs equal `spreadContactOrders`; `CraneRootSpec.hs:59-61`'s case holds (R-07-8) | filtering before closing |
| AC-5 | Hinge ids equal `craneHinge`; `recordBefore` has 76 faces (R-07-3) | recording before creasing |
| AC-6 | `turn over left-right` before the step, with `fold behind` rewritten `fold in front`, leaves pins and contact pairs unchanged (R-07-2). The word must change because `in front`/`behind` is read from the reader's side, which a turn-over flips ([02 §5.1](02-language-semantics.md#51-the-readers-side)); the record is not presented, so its pins must not move | presenting inside the record |
| AC-7 | The wing settle builds hinges without `MissingRestAngle`/`InvalidRestAngle` (R-07-4) | solver surface from a written frame; one intent on all four segments |
| AC-8 | `rest at before` with no grips → `NoDifference`; `rest at rigid-pose 1/3` → not (R-07-20) | deleting the check |
| AC-9 | A settle on `unfold wing` after the wing step, a move starting at 90° and ending flat → `SettleStartNotFlat` (R-07-7) | settling from `recordAfter` |
| AC-10 | Rigid outputs byte-identical with settle blocks deleted (R-07-28, 29) | a settled surface reaching a page basis or later step |
| AC-11 | One `GripOutOfRange` and one accepted settle: accepted files exist, refused absent, rigid written, exit nonzero naming the step; `--allow-unsettled` exits 0 and records it (R-07-33, 34) | aborting all settles at the first failure; writing rigid geometry in its place |
| AC-12 | Bird records → `Certified` ×4; the same macros on `square-base.fold` → `NoCertificateFor`; a wrong-branch (`False`) call → `Refused`, never `Sampled`; each entry's sample poses equal `175 * fraction` exactly (R-07-36–38) | keying by macro name only; mapping `Refused` to `Sampled`; a pose written as an absolute angle |
| AC-13 | More than 1,192 refined triangles → `TriangleBudget` before any `relax*` call (R-07-41) | counting after solving |
| AC-14 | `material { size 15cm; thickness 0.1mm }` stores exactly 1/1500 on `crane.fold` (s = 1 in `Double`, R-07-24); a built `mm` frame with s = 100 → `UnitMismatch` (R-07-24–26) | using the refined mesh's extent; ignoring `frame_unit` |
| AC-15 | Each graduation PR: `git diff --name-only --diff-filter=MD origin/main...HEAD -- test/golden/` prints nothing, the check of [D16](decisions.md#d16-testing-and-acceptance) (it printed nothing on 2026-09-15 at `568dcb6`, where `git ls-files test/golden \| wc -l` printed 33); the gallery's `[True, True, True, False]` ([`CraneSpreadGallery.hs:108`](../study/fold-material/CraneSpreadGallery.hs#L108)) unchanged (R-07-39) | a stage altering an energy or tolerance |
| AC-16 | No workflow in `.github/workflows` or spec in `test/` runs an external solver or simulator or reads such a program's output; `stack`, ormolu and hlint are excepted (R-07-43) | a test shelling out to a simulator |
| AC-17 | One example value per constructor of `SettleStepError`, `SettleError`, `Reason` and `Refused`, produced by a function that matches each type with no wildcard, and an `explain` golden for each; a property over the examples checks that no message contains a Haskell constructor name or record syntax (R-07-45) | a constructor added without an example (an incomplete-pattern warning, which the cold `stack clean && stack build --test` shows; there is no `-Werror`); a message built with `show` |

## Dependencies

| On | For |
| --- | --- |
| M4 (layer selection, relations, `start folded`); [02](02-language-semantics.md), [05](05-prd-library-additions.md) | the crane-wing sequence |
| `recordPoseAt`, `flapPoseAt`, stationary face, per-layer intent from `creaseLayersThrough AtRest` ([05](05-prd-library-additions.md)) | grips, rest, `side stationary`, AC-7 |
| M5 `CheckedMacro`, `macroPoseAt`, bird route | registry; `rigid-pose` on macros |
| [04](04-prd-sequence-source-and-cli.md) grammar and flags; [08](08-prd-realistic-rendering.md) two-scene GLB, fidelity extras, `<desc>`, [W1](glossary-additions.md#realistic-rendering) (exact line drawing); [09](09-testing-and-acceptance.md) slow job | text, output, CI |
| [#208](https://github.com/avalonalex/senbazuru/issues/208) | gate before M6 equivalence and M8 |
| [#195](https://github.com/avalonalex/senbazuru/issues/195), [#114](https://github.com/avalonalex/senbazuru/issues/114) (rewritten at M6, [10](10-roadmap-risks-questions.md)), [#206](https://github.com/avalonalex/senbazuru/issues/206), [#53](https://github.com/avalonalex/senbazuru/issues/53), [#73](https://github.com/avalonalex/senbazuru/issues/73) | follow-ups, fallback, oracle, file keys |

Order: M4 → M6 → M8; M5 before the bird registry entries ([10](10-roadmap-risks-questions.md)).

## Risks

| Risk | Evidence | Mitigation |
| --- | --- | --- |
| Named holds miss `spreadPins` | bands, `rigid-pose 1/3`, `arc-grip` UNVERIFIED; slacks differ | AC-1 first, without solving; fixtures keep their code until it passes |
| M6 doubles costly CI groups | 164.87 s, 97.48 s (#208) | #208 first, or compare resolved sets; solve once in the slow job |
| Authors expect settle to beautify any step | a rigid state is already settled | `NoDifference`; [00](00-overview.md) |
| Tolerance-sized crossings hide in accepted meshes | −6.21e-9 passes 1e-7; GLB packs at 1e-6 of span (B finding 15) | residuals reported as numbers |
| Settled SVG shows buried creases | `docs/usage.md:464-465` | accepted only; W1 at M7b |
| Results depend on the mesh | 3.95%; a qualitative change at 64 triangles (B finding 9) | report refinement level; `illustrative` |
| Few settles start flat; non-convex panels | the wing's next move starts at 90°; [`Surface.hs:343`](../src/Senbazuru/Origami/Surface.hs#L343) | named refusals; discovery later |
| Per-spring controls cannot be named | mapping rows 15, 17, 19 | they stay fixtures |

## Open questions for the owner

Owner decisions, numbered as in [decisions §9](decisions.md#9-owner-decisions)
and [10](10-roadmap-risks-questions.md#6-owner-decisions), each with the default
§9 recommends:

1. **(4)** Should a precreased M/V crease at 0 settle as a crease spring at rest 0
   or as uncreased panel, and should the sheet file's `F` edges stay panel bends
   ([wing-root-holds.md:87-92](../docs/notes/wing-root-holds.md))? Default: a
   crease spring at rest 0, and `F` edges stay panel bends.
2. **(11)** Should the external-tools rule go into AGENTS.md or only
   `docs/related-projects.md`? Default: AGENTS.md, as
   [decisions §3](decisions.md#3-recorded-text-this-design-changes) row 8 at M0.
3. **(12)** Are 392 triangles in default CI and 1,192 behind `run --settle`
   right, and which crane-sized sequences move to the slow job? Default: both
   numbers, until 3–5 compiled runs after #208; crane-sized sequences in a slow
   job that is a required check.

## Research links

- [gap-study-consumption-contract](research/gap-study-consumption-contract.md):
  "(a) What the study takes from a move today", "(b) How holds, grips and contact
  panels are chosen today", "(c) Certificates", "(d) What guards each recipe",
  "(e) Licences for driving external solvers", "Implications for the design".
- [B](research/B-material-study-mechanics.md): "Capability table (question a)",
  "The implicit material API (question b)", "Realism (question c)", "Risks
  (question d)", "Graduation (question e)".
- [G](research/G-realistic-rendering-and-simulation.md): "B. Geometry models, and
  whether a sequence could feed them", finding 13.
- [gap-layer-selective-folds](research/gap-layer-selective-folds.md): "Re-deriving
  CraneWing by rule (script)".
- [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md):
  "Implications for the design"; "Addendum — runs that finished after this note
  was written".
