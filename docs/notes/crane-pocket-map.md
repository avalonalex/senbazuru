# The body patch is not the pocket's mouth

The [crane-opening references](opening-a-crane.md) suggest letting the body,
both wings and their neck/tail attachments move together. Before deciding
which points to hold, map the paper they come from. Run:

```bash
stack run senbazuru-material-study -- --crane-pocket build/fold-material
```

The input is the existing tail-tucked crane, including the earlier four
authored wing-root segments. `CranePocket` changes no positions, material
coordinates or layer orders. It resolves landmarks on the original unit
square, then uses shared edges to check the following partition. A panel is
a region between recorded edges; see the [glossary](../glossary.md).

| Region | Selection in material space | Panels |
| --- | --- | ---: |
| Body core | Panels touching the square's centre | 8 |
| Wing A sector | Remaining upper-left quadrant | 14 |
| Wing B sector | Remaining lower-right quadrant | 10 |
| Tail sector | Remaining lower-left quadrant | 18 |
| Neck and head sector | Remaining upper-right quadrant | 26 |

Every panel belongs to exactly one connected region. The two wing counts
differ because the older one-wing experiment divided only Wing A at its
authored root. A sector includes its base strips; it is not just the freely
moving wing tip. Neither numbering nor screen-space proximity selects a region:
the map survives face renumbering and refuses a panel crossing a material
quadrant boundary.

The eight central panels form a useful candidate body core, but their 16
perimeter edges all have another material panel on the other side. That
perimeter is therefore an internal interface, not an exposed hole. Four
distinct midpoints of the original sheet's boundary also meet underneath in
the flat crane: vertices 1, 20, 55 and 28 in this fixture, all near folded
position `(1, 0.5, 0)`. They remain distinct material vertices. Their separation
could measure later opening; it does not identify a complete mouth boundary
or justify capping that space for a pressure or volume calculation.

The graph has more connections than a body with four independent flaps.
Each wing sector shares four edges with the body core, three with the tail
sector, and three with the neck/head sector. Some are recorded flat edges,
across which the paper is uncreased. `surfaceFeatures` omits those guides for
physical-crease consumers; this map instead reads every recorded edge and its
face incidence, because omitting flat connections would falsely disconnect
the paper. A layer-order relation is different again: it constrains overlapping
layers without joining their material vertices.

The next solve has a concrete candidate angle set: the 22 original mountain
or valley creases that touch the body core or cross between regions. This
is a starting hypothesis, not a claim that all 22 must change or that these
alone allow opening. The proposed split keeps the other 79 mountain/valley creases as fold
preferences, while allowing their regions to move in space. The 21 flat
connections remain continuous uncreased material, and the four authored root
controls still need the comparison with ordinary panel bending.
The 12 paper-boundary segments are the actual outer edge of the sheet.
`crane-pocket/map.json` records every edge's owners, region and proposed role.

The original-sheet SVG colours that material partition. Folded SVG highlights
are explicitly x-ray views: they show a selected region even where other layers
cover it, using the same geometry and scale for every selection. The ordinary
GLB keeps visible and complete-paper scenes. Neither picture is a newly opened
state. The map checks material lengths, coverage, connected regions and shared
interfaces; the existing crane construction supplies the tail-tucked baseline.

Next, distinguish the body folds allowed to open from folds whose preferences
remain controlled, resolve the earlier body-release failure, and choose small
paired wing grips with the neck/tail attachments free. Use the underside
landmarks and body dimensions as measurements before attempting a cavity
volume. The rim, contact changes and compatibility of that coupled opening
remain unresolved under [#195](https://github.com/avalonalex/senbazuru/issues/195)
and [#106](https://github.com/avalonalex/senbazuru/issues/106).
