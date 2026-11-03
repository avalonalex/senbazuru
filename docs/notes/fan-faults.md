# What fanning gets wrong, and where a guard belongs

Terms used here are defined in [../glossary.md](../glossary.md).

A fanned figure moves each vertex toward the page's lower left by 1.5 page units
for every sheet over it, counting at most 6 (its [fan count](fan-counts.md)), so
the stack shows its layers as a fan of edges. The move is a fixed length *on the
page*, while the figure is drawn at whatever scale its page gives it. So every
fault fanning makes depends on the scale: 9 page units, the largest move, is
nothing beside a face 100 units across and can turn a face 5 units across inside
out. Nothing draws a fanned figure yet; this note measures the rule before
[#639](https://github.com/avalonalex/senbazuru/issues/639) and
[#644](https://github.com/avalonalex/senbazuru/issues/644) build it.

## What is measured

- **Inside out.** A face whose fanned outline is simple but winds the other way:
  the paper is drawn from its back. Every move points the same way, so the
  fanned area is exactly *s*² *A*₀ + *s* *B* at *s* page units per sheet length,
  and a face whose corners move by different amounts turns inside out, if at
  all, below one scale, −*B* / *A*₀, which the last section lists. "Inside out" rather than "turned over", which names a move of
  the whole model.
- **Crossing itself.** Two sides of the fanned outline cross, or one folds back
  along its neighbour. Counted instead of inside out, since a crossed outline's
  winding means nothing.
- **A line that stops short.** Where a [stretch](../glossary.md#origami)'s edge
  runs on under a nearer face, the stretch ends at that face's edge. Fanned, the
  two move by different amounts. An end that moves *into* the nearer face is
  covered, because the painter fanning shares with the offset view (06 R-06-27)
  paints a layer's faces after the layers below it. An end that moves *out* of
  it leaves a gap, where the edge's faint continuation shows.
- **Visible paper moved.** How far the corners of a face's visible paper that
  lie on its own edges move. A fold-here line drawn on true positions sits that
  far from the paper it marks, and the face *leans* where the moves differ.
- **Folds drawn as a border.** A stretch takes the strongest line under it, so a
  fold lying along a buried sheet's border is drawn as that border. Fanned, the
  border moves with its own sheet; the mismatch is how far apart the two move.
- **Hinge moves.** How far the paper under a fold's hinge, the line the fold
  turns paper about, moves on the figure before the fold. That is where owner
  decision 74 draws the fold-here line, the line a book draws to say "fold
  here". The largest move of an end, and in brackets its part square to the
  hinge, which is how far the line sits from the moved edge.

The fixtures are the folded crane (the first layer order the solver finds), the
runs of `helmet.foldseq` and `blintz.foldseq`, and the two flat states of
`examples/bird-base-sequence.fold`. A run's first state is a crease pattern,
drawn unfanned, so it is left out, and so are the bird's states with paper in
the air. The crane is also measured turned 180°, as `render --rotate 180` draws
it, because the fan runs the same way on the page whichever way the model is
turned.

## Faults by fixture and figure size

Each cell is faces drawn inside out · faces crossing themselves · stretch ends that come apart from the paper they met, summed over the fixture's fanned figures. The sizes are page units per sheet length, on `render --steps`' uncaptioned page of three columns, by its rows: 115.00 (1–3 rows); 85.58 (4 rows); 68.15 (5 rows); 56.62 (6 rows); 48.42 (7 rows); 42.30 (8 rows); 37.55 (9 rows); 33.76 (10 rows). A captioned `run` page at its default height draws at 115.00 whatever its rows.

| Fixture | Seen | 115.00 | 85.58 | 68.15 | 56.62 | 48.42 | 42.30 | 37.55 | 33.76 | Inside out below |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| crane | from above | 0 · 0 · 2 | 1 · 0 · 2 | 1 · 0 · 2 | 1 · 0 · 2 | 1 · 0 · 2 | 1 · 0 · 2 | 1 · 0 · 2 | 3 · 1 · 2 | 92.98 |
| crane | from below | 0 · 1 · 0 | 0 · 1 · 0 | 0 · 1 · 0 | 0 · 1 · 0 | 0 · 1 · 0 | 0 · 2 · 0 | 0 · 2 · 0 | 1 · 3 · 0 | 63.44 |
| crane | from above, turned 180° | 1 · 0 · 1 | 4 · 0 · 1 | 5 · 1 · 1 | 8 · 1 · 1 | 9 · 1 · 1 | 11 · 1 · 1 | 12 · 1 · 1 | 13 · 1 · 1 | 222.94 |
| helmet | from above | — | — | — | — | — | — | — | — | 4.24 |
| helmet | from below | — | — | — | — | — | — | — | — | — |
| blintz | from above | — | — | — | — | — | — | — | — | 4.24 |
| blintz | from below | — | — | — | — | — | — | — | — | — |
| bird base | from above | — | — | — | — | — | — | — | — | 12.36 |
| bird base | from below | — | — | — | — | — | — | — | — | 14.49 |
| bird base | isometric, as its page | — | — | — | — | — | — | — | — | 17.74 |

## Faults by fixture

Visible paper moved is the faces whose visible boundary moves, how many of them lean, and the largest move. Folds drawn as a border are stretches drawn at border weight whose named edge is a fold, and the largest gap between the fold's move and its border's. Folds along a border are folds lying wholly along a border edge, drawn or not, out of all mountain and valley folds, in the state with most. A hinge move is the largest move of an end of a fold's hinge edges on the figure before the fold, drawn and buried, and in brackets its part square to the hinge. All in page units.

| Fixture | Seen | Visible paper moved | Folds drawn as a border | Folds along a border | Hinge moves |
| --- | --- | --- | --- | --- | --- |
| crane | from above | 7 faces, 7 leaning, up to 2.92 | 4 stretches of 4 folds, up to 9.00 | 15 of 99 | — |
| crane | from below | 8 faces, 8 leaning, up to 2.75 | 4 stretches of 4 folds, up to 9.00 | 15 of 99 | — |
| crane | from above, turned 180° | 7 faces, 7 leaning, up to 2.92 | 4 stretches of 4 folds, up to 9.00 | 15 of 99 | — |
| helmet | from above | — | — | 0 of 6 | step 1: drawn unfanned; step 2: drawn 0, buried 1.50 (1.06); step 3: drawn 0, buried 1.50 (1.06) |
| helmet | from below | — | — | 0 of 6 | step 1: drawn unfanned; step 2: drawn 0, buried 1.50 (1.06); step 3: drawn 0, buried 1.50 (1.06) |
| blintz | from above | — | — | 0 of 4 | step 1: drawn unfanned; step 2: drawn 0; step 3: drawn 0; step 4: drawn 0 |
| blintz | from below | — | — | 0 of 4 | step 1: drawn unfanned; step 2: drawn 0; step 3: drawn 0; step 4: drawn 0 |
| bird base | from above | — | — | 0 of 20 | — |
| bird base | from below | — | — | 0 of 20 | — |
| bird base | isometric, as its page | — | — | 0 of 20 | — |

## Scales below which each face is drawn inside out

- crane, from above: folded face 61 below 92.98; folded face 56 below 37.24; folded face 24 below 36.75; folded face 34 below 31.57; folded face 35 below 31.57; folded face 31 below 28.48; folded face 6 below 27.98; folded face 2 below 27.98; folded face 28 below 27.60; folded face 27 below 26.44; folded face 70 below 25.63; folded face 4 below 22.02; folded face 41 below 18.21; folded face 9 below 16.32; folded face 39 below 15.08; folded face 37 below 15.08; folded face 0 below 14.51; folded face 32 below 13.08; folded face 38 below 13.08; folded face 51 below 11.68
- crane, from below: folded face 20 below 63.44; folded face 28 below 36.75; folded face 37 below 31.57; folded face 39 below 31.57; folded face 5 below 27.98; folded face 31 below 26.44; folded face 7 below 20.47; folded face 24 below 20.45; folded face 43 below 18.21; folded face 65 below 17.09; folded face 35 below 15.08; folded face 34 below 15.08; folded face 15 below 15.00; folded face 10 below 15.00; folded face 36 below 13.08; folded face 33 below 13.08; folded face 3 below 12.96; folded face 49 below 11.68
- crane, from above, turned 180°: folded face 63 below 222.94; folded face 68 below 111.47; folded face 65 below 100.98; folded face 58 below 92.72; folded face 67 below 81.37; folded face 52 below 68.61; folded face 14 below 59.09; folded face 12 below 57.84; folded face 48 below 55.23; folded face 10 below 45.25; folded face 8 below 42.76; folded face 71 below 38.36; folded face 57 below 36.99; folded face 15 below 28.92; folded face 69 below 27.87; folded face 53 below 26.77; folded face 25 below 25.84; folded face 29 below 23.53; folded face 26 below 16.92; folded face 13 below 13.84; folded face 49 below 13.38; folded face 66 below 12.79; folded face 5 below 11.17
- bird base, from above: state 0 face 10 below 12.36; state 15 face 9 below 10.24
- bird base, from below: state 15 face 14 below 14.49
- bird base, isometric, as its page: state 15 face 12 below 17.74; state 15 face 7 below 16.14; state 15 face 9 below 12.44

## What the numbers say

- **The models that run today fan cleanly.** No face of the helmet, the
  blintz or the bird base's flat states turns inside out or crosses itself at
  any size measured, down to ten rows, and no line stops short. The one change
  is under the helmet's folds: on steps 2 and 3 a buried hinge edge moves 1.5
  page units, 1.06 of them square to the hinge. A drawn hinge edge never moves,
  so decision 74's fold-here line stays on the paper it marks.
- **The crane is where the faults are.** Seen from above, face 61 turns inside
  out below 92.98 page units per sheet length, so on every uncaptioned page of
  four rows or more; at ten rows three faces are inside out and one crosses
  itself, the prototype's numbers in 06 Risks. Seen from below, face 20 crosses
  itself at every size, 115 included. Turned 180°, face 63 turns inside out
  below 222.94, so at 115, the largest size a page of three columns draws, and
  at ten rows thirteen faces do.
- **Lines stop short; they do not run over paper.** On the crane from above, two
  stretch ends leave the paper they met, by 0.18 at every size and by 1.02 to
  1.19 as the figure shrinks; turned 180°, face 10's mountain edge leaves face 1
  by 1.98. The same end from above moves *into* face 1, which paints over it.
- **Visible paper moves a little, borders a lot.** Seven of the crane's faces
  have visible paper that moves, all leaning, by up to 2.92 page units (eight
  from below, 2.75). Four stretches are drawn as a border while the fold lies
  over it, and the border moves up to 9 page units, the fan's largest move, away
  from the fold. Of the crane's 99 folds, 15 lie along a border edge.

So the numbers do not put fanning by default in doubt for the models that run
today, which it leaves as they are but for the buried hinge edges. On the crane,
the guard below would draw most figures unfanned: every one from below or turned
round, and every one from above on a page of four rows or more.

## Where the guard belongs

Draw a whole figure unfanned when any of its faces would be inside out or
crossed at the page's scale, and decide it once that scale is known.

- **Not a minimum figure size.** The crane turned round is inside out at 115,
  the largest size a page of three columns gives, and from below a face crosses
  itself at every size. No floor that leaves a page of steps usable stops
  either.
- **Not per shape in `Render.Svg`.** A face drawn unfanned among fanned
  neighbours parts from them at every corner it shares, by that corner's move,
  up to 9 page units: the guard would tear the drawing it was meant to tidy.
- **Per figure, where the scale is known.** A guarded figure falls back to the
  drawing every page makes today, which is right, only less clear.
  `Render.Steps.stepFigures` builds the figures before any scale exists, so the
  test sits after `Diagram.Page.fitPage` in `Render.Sequence.runPage`, and after
  `gridOf` in `Render.Steps.stepPage`, where `pageTransform` gives the scale
  before anything is written. Inside out is cheap to ask: a figure is safe at
  scale *s* when *s* is above every face's threshold. Crossing needs each
  fanned outline checked at *s*.

The lines that stop short, the visible paper that moves and the borders drawn
over folds do not grow as the figure shrinks, and no guard removes them: they
are limitations for #644 to state.

## What the plan had wrong

- **The sizes are not `run`'s.** The plan took 115, 56.6 and 33.8 for `run`'s
  pages of 1 to 10 rows. A captioned `run` page at its default height draws at
  115 whatever its rows and grows taller instead (owner decision 7); the
  shrinking sizes belong to `render --steps`' uncaptioned page, which the S39
  `--fan` flag will draw, and to `run --columns`. The plan's 33.1 at ten rows
  assumed a gutter decision 7 replaced. 06 Risks' "the traditional crane's 29
  figures" cannot be drawn yet: that source's run is refused at step 4, a macro
  move not yet run.
- **Leaning is about visible paper.** "A face with sheets over some of its
  vertices but not others" counts many hidden faces of the crane; the seven are
  the faces whose *visible* paper moves.
- **The hidden line is covered.** 06 Risks had face 10's mountain edge running
  3.4 page units into face 1. On the painter fanning shares with the offset
  view, face 1 is painted after it and covers it; the fault that shows is the
  other way round, a line stopping short.
- **Fifteen and four.** Fifteen of the crane's folds lie along a border; four
  stretches are drawn as one, from either side.

Every number above comes from `stack run senbazuru-material-study --
--fan-faults build/fold-material/fan-faults`, which writes these tables to
`fan-faults.md` and every face, end and hinge to `fan-faults.json`; the move's
step and cap are a copy of 06 R-06-25 in `study/fold-material/FanFaults.hs`,
which S38 re-runs on the shipped rule.
