# Adding the missing overlap guards

Adding the six 55–93 overlap guards lets the new direction accept **1/8**,
compared with **1/128** for the saved control, without repairing either selected
shape. It reduces total cost by **0.390833%**, versus **0.028072%**, while all
selected geometry checks remain unchanged. The larger new **1/4** trial instead
crosses **14–55**, a pair that already has overlap guards. The
[saved 55–93 inspection](body-contact-55-93.md) motivated this comparison.
[#363](https://github.com/avalonalex/senbazuru/issues/363) records this experiment
under [#195](https://github.com/avalonalex/senbazuru/issues/195), track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).

```bash
stack run senbazuru-material-study -- --body-fourth-pair build/fold-material/body-restoration-loop build/fold-material
```

Both directions start at `step-9.fold`: the retained shape just before
correction ten, not the loop's final shape. A direction gives a proposed
movement for every free vertex. The control reuses its saved proposal without
solving again. One new quadratic, a local squared-error approximation to the
material cost, receives nineteen guards: the twelve old overlap constraints,
the vertex 27–plane 70 constraint, then six new overlap constraints. Their
order is retained because changing the numerical solver's input order would
introduce another variable into the comparison.

The inherited material order puts **triangle 93 below triangle 55**. At each
corner of their top-view overlap, the gap is 55's height minus 93's height.
The guard predicts its change as both triangles and the overlap corner move.
A positive gap must stay nonnegative; an already negative gap must get no
worse. This local rule is stricter than the actual geometry check's `1e-7`
contact tolerance. All positions and distances use the original sheet's
coordinate units. No vertex 30 plane guard is added.

The same largest-first search tests fractions `1, 1/2, …, 1/2^30`. Every
refused fraction may receive the existing one vertex 27–plane 70 repair. That
repair restores the starting plane distance with a minimum-movement correction
and refreshes the overlap predictions at the refused shape. It must preserve
all original guards as well as those refreshed guards. Adding the pair means
these repair checks include its six corners too; changing overlap-corner
identities remains a refusal. Raw and repaired coordinates must preserve the
connected sheet, exact holds, relative edge-length error below `1e-5`, inherited
orders and all-pair contact at the unchanged tolerance, and decrease total
cost. The first passing candidate wins.

The material and numerical settings remain fixed: length weight `1e8`,
contact weight `1e10`, damping `1e-3`, 100 quadratic iterations and `1e-12`
guard residual tolerance. Panel cost penalizes bending inside uncreased paper;
crease cost penalizes deviations from preferred fold angles. The gallery
shows these separately from length and contact penalties, with body depth and
movement. No continuation runs from the selected shape, and a small fraction
does not establish equilibrium: the full verified proposal must also move
less than `1e-7` sheet units.

| Measurement | Saved control | Six added guards |
| --- | ---: | ---: |
| Quadratic iterations / active guards | 3 / 2 | 5 / 4 |
| Selected fraction | 1/128 | 1/8 |
| Selected movement | 4.160940e-6 | 6.820255e-5 |
| Movement at 600 pixels per sheet unit | 0.002497 px | 0.040922 px |
| Total cost | 0.012736763811 | 0.012690546844 |
| Panel cost | 0.001061594437 | 0.001057018118 |
| Crease cost | 0.011621582109 | 0.011578787996 |
| Length cost | 0.000047886349 | 0.000049806459 |
| Contact cost | 0.000005700916 | 0.000004934272 |
| Relative length error | 6.380501e-6 | 6.118133e-6 |
| Body depth | 0.036235262957 | 0.036247459875 |
| Full proposal movement | 0.000532600262 | 0.000545620366 |

Starting cost is `0.012740340282`; starting body depth is `0.036234441693`.
The new direction buys more bending and crease-cost reduction with a slightly
higher length penalty. Maximum relative length error still improves: a sum of
squared edge errors and the largest relative edge error measure different
things. Both selected states keep exact holds and pass all 7,140 triangle-pair
checks without reversed inherited orders. The added direction's full movement
remains **5,456 times** above its stopping threshold; neither result is a
settled endpoint. This is useful numerical progress, not a visible body opening.

The new active constraints include overlap corners **4 and 5**, appended rows
17 and 18. Corner 4's actual gap stays positive at `7.409300e-8`, while corner
5 improves from `−7.667635e-9` to `−7.653170e-9`. Vertex 30's distance from
triangle 93's extended plane stays positive at `9.056851e-7`. No visited new
trial crosses 55–93, including the full-size proposal. Its refused 1/4 trial
is cheaper and passes lengths and layer order, but crosses 14–55. The old
vertex 27 repair is inapplicable there because that plane distance did not
worsen. The full-size trial receives a repair in each direction; both repaired
results remain refused. These attempts are retained separately in the gallery.

The comparison shares the loop's acceptance and repair routine. Before the
new solve, the reader authenticates all 137 saved loop states and checks that
the shared routine exactly reproduces all thirty saved repairs. Replaying the
old direction must also preserve its eight visited fractions and every raw
or repaired acceptance decision. Archive reads finish before the next file is
opened, avoiding deferred file handles for thousands of saved SVGs; the broader
archive follow-ups remain in [#360](https://github.com/avalonalex/senbazuru/issues/360).

Independent calculations check all **15 exported shapes**: the start, twelve
raw fractions and two attempted repairs. They recompute separate costs, lengths,
exact holds, all-pair crossings, inherited orders and **18,520 exported face-order
records**, plus the selection decisions. Finite differences verify the eighteen
overlap derivatives and the two repairs' refreshed rows (maximum error
`2.31e-10`); sixty-digit arithmetic checks plane distances and gradients.
Both recorded quadratics independently satisfy force balance below `1e-6`.
All **2,025** source assets retain their bytes. Changing vertex 30 by `1e-10`
in a copy of the final refused input is rejected before any new solve or output.
Generation and the negative check run under a 256-file limit. All **90**
shape/view combinations load without browser warnings or errors. The cold build
is warning-free; all **1,883 tests pass in 168.0 seconds**. Ormolu 0.7.2.0,
HLint 3.10 using the exact CI JSON command, study JavaScript and inline-script
syntax checks pass. This adds no material solve to default CI.

The [saved 14–55 inspection](body-contact-14-55.md) follows this comparison
without new solves. Both triangles already straddle each other's planes; the
finite intersection grows past tolerance as an active overlap guard's local
prediction misses a small actual gap loss. That motivates testing one refreshed
overlap-gap repair, while keeping this specimen distinct from body inflation,
whole-crane response and a continuously checked flexible route.
