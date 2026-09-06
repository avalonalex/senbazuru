# A tour of what senbazuru does

Every feature, with the command that produces it and the reasoning behind it.
The [README](../README.md) is the short version; this is the long one.

For running any of it, [usage.md](usage.md). For the ideas underneath,
[notes/](notes/). For a word you do not recognise, [glossary.md](glossary.md).

## What it draws

Given a `.fold` file, it draws every edge using the standard
Yoshizawa–Randlett line vocabulary: solid for the edge of the paper, dashed for
valley folds, dash-dot-dot for mountain folds, and a light line for creases that
exist but are not folded. Those dashes are instructions, so they belong to crease
patterns. A folded form is drawn the way a book draws the model itself, with
every edge solid.

```bash
stack run -- render examples/unit-square.fold -o unit-square.svg
```

produces a unit square with a valley fold down the middle, a mountain fold
across it, and a faint diagonal reference crease. That file records no faces, so
what comes out is exactly those lines on a blank page.

A file that *does* record `faces_vertices` gets its faces filled with a paper
tint, so the sheet reads as an object rather than as lines floating on the page:

```bash
stack run -- render examples/quarter-fold.fold -o quarter-fold.svg
```

`--no-fill` turns that off.

A folded form is filled too, but only when the file says which face is in front.
FOLD records that in `faceOrders`, and `examples/simple.fold` carries one:

```bash
stack run -- render examples/simple.fold --view iso -o simple.svg
```

The stacking is a fact about the paper rather than about the picture — it says a
face lies on the side another face's *normal* points to — so the drawing order
depends on where you are looking from, and the same model seen from behind
stacks the other way up. A folded form with no `faceOrders` gets one worked out,
if it lies flat; see [What it stacks](#what-it-stacks). One with paper still in
the air stays a wireframe: painting its faces in the order they happen to appear
in the file would be a confident picture of the wrong thing.

Folded forms take a viewing angle:

```bash
stack run -- render examples/squaretwist.fold --view iso -o squaretwist.svg
```

## What it folds

`--fold` computes the folded form rather than reading one. Given a crease
pattern and a fold angle for every crease, paper does not stretch, so each face
moves rigidly and the whole state is one rigid motion per face — walk the faces,
compose one turn per crease, and every vertex is a lookup.

```bash
stack run -- render examples/quarter-fold.fold --fold -o quarter-folded.svg
stack run -- render examples/diagonal-cp.fold --fold -o diagonal-folded.svg
```

The first folds a square into quarters and produces a quadrant with four layers;
the second folds a square along its diagonal and produces a triangle. Neither
needs `--view`: both fold *flat*, and the view is chosen from the coordinates, so
they are drawn from above. Forcing `--view iso` on a flat-folded model shears a
correct picture into a wrong one; leave the camera alone unless the fold really
does leave the plane. Fold angles
come from `edges_foldAngle`, or from the assignments if the file records none —
an assignment names a direction and not an amount, and a flat fold is the only
amount consistent with naming no number.

Not every set of angles describes something a sheet of paper can do. Walk round
an interior vertex and the turns must compose back to nothing, and the obvious
algorithm never checks: it reaches each face by one path and silently *tears* the
model when they disagree. `--fold` compares the places each face puts a shared
vertex and refuses rather than drawing the tear:

```console
$ senbazuru render bent.fold --fold
senbazuru: cannot fold bent.fold: vertex 6 is placed 0.707107 apart by the faces
meeting at it, so these fold angles tear the paper rather than folding it
```

The threshold for "disagree" admits arithmetic noise and nothing more, so angles
that are a fraction of a degree short of closing are refused too — the message
quotes the distance, which is how you tell a tear from a typo in the fourth
decimal place.

## What it stacks

Folding says where every face went and nothing about which is in front, and in
a model folded flat every face lies in the same plane, so the coordinates cannot
say either. FOLD keeps the answer in `faceOrders`, which a computed folded form
does not have. So senbazuru works one out.

Deciding which layer is on top is a constraint problem, and in general a hard
one, but every constraint the paper imposes is local. Two faces joined along an
edge of the folded form are either a *taco* — the paper folded back on itself,
both faces on one side of the edge — or a *tortilla*, paper continuing flat
across the line. A face that runs across a taco's fold line cannot lie between
the taco's two faces; two tacos on one line must nest or stay apart; two
tortillas cannot cross each other; and a valley puts the face that turned over
on top where a mountain puts it underneath. Generate those rules for every pair
of faces that share a patch of paper, satisfy them, and the result is a
`faceOrders` the renderer already knows how to draw. The rules are written up in
[notes/taco-taco.md](notes/taco-taco.md).

```bash
stack run -- render examples/letter-fold.fold --fold -o letter-folded.svg
```

folds a square in three like a letter, with panels of different widths so the
order shows: the long third panel is painted last and covers most of the other
two. Fold a strip of paper the same way and look. The quarter fold above comes
out four layers deep in the one order its three mountains and one valley allow.
The traditional crane works too:

```bash
stack run -- render examples/crane.fold --fold --rotate 180 -o crane.svg
```

`--rotate` because the crane lands upside down. A folded model sits whichever
way up its crease pattern happened to be drawn, and no FOLD file says which way
up it should be read, so turning the drawing is the reader's to do.

That file, and a few others in `examples/`, come from
[Flat-Folder](https://github.com/origamimagiro/flat-folder), an independent
solver for the same problem, whose published counts of constraints per model
senbazuru's test suite checks itself against, kind by kind.

Not every set of creases has a stacking. Make both of the letter fold's creases
valleys and the third panel has to slide between the first two, but it is longer
than the pocket and the pocket is closed at the far end:

```console
$ senbazuru render rolled.fold --fold
senbazuru: cannot render rolled.fold: the layers cannot be stacked without the
paper passing through itself; the constraint between faces 0, 1, 2 is the one
that could not be met
```

Folding cannot see this — the coordinates are identical to the accordion's — and
neither can `check`, whose theorems are about one vertex at a time.
`examples/big-little-big.fold` passes `check` and is refused here, for exactly
the reason [its note](notes/big-little-big.md) gives.

Two limits, both deliberate. The solver covers models folded *flat*; a folded
form with paper in the air and no `faceOrders` is still drawn as a wireframe,
and `info` says so. And every face has to be convex, which the faces of a
flat-foldable pattern are whenever the sheet is.

### Which stacking

There is rarely just one. The crane has five valid layer orders, the kabuto
nine, and one of Flat-Folder's dragons more than 10⁸³ — the counts are products,
because the constraints fall into independent components and the choices in them
multiply. `info --fold` says how the model divides up:

```console
$ senbazuru info examples/crane.fold --fold
...
    layers:   (none in the file; 892 overlapping pairs in 2 components, 5 valid orders)
    stacking: 1 component with a choice; --stacking takes 0-4
```

The two counts differ by one on purpose: the first counts components the way
Flat-Folder does, with the pairs that were settled outright among them, so its
published figures can be compared with these. The second counts what you can
actually choose. `--stacking` takes one index per component with a choice in it:

```bash
stack run -- render examples/crane.fold --fold --stacking 3 -o crane-3.svg
```

which puts a different flap on top of the crane's right wing. Most of the
difference between orders is buried, though: all sixteen of the 2×2 grid's are
the same picture from either side, and all nine of the kabuto's are one picture
from above and four from below. A count of orders is a count of *models*, not of
pictures.

The same split is what keeps the search finishing. Each component is solved on
its own, so the cost adds up over them rather than multiplying, and each is
given a budget of guesses — `--layer-budget`, a thousand by default — so that a
model propagation cannot settle says it gave up instead of running on. The most
any model here needs is eight, and both models that cannot be stacked at all are
refused without a single guess. The reasoning is in
[notes/several-stackings.md](notes/several-stackings.md).

## What it hides

Knowing which layer is on top is not the same as having a picture, for two
reasons that are really one.

A valid layer order can run in a **circle**. The four flaps of a twist lie A
over B over C over D over A, and no paper passes through any other, because no
point of the sheet is under all four at once. There is simply no order to paint
four whole faces in. And painting whole faces hides nothing anyway: every crease
is drawn afterwards, including the ones ten layers down.

So a model folded flat is not drawn face by face. Each face is cut down to what
is left of it once every face nearer the viewer has been taken away, and each
edge is kept only over the stretches where the paper differs across it. The
result has its hidden lines gone, and its **two sides in different colours** —
origami paper is coloured on one side, and a flap folded over shows its back.

```bash
stack run -- render examples/thirds-pinwheel.fold --fold -o pinwheel.svg
stack run -- render examples/thirds-pinwheel.fold --fold --view bottom -o under.svg
```

The first is a twist, which could not be drawn at all until this arrived. The
second is the same model from underneath, which is a different picture and not
the first one upside down: a different set of faces is on top, and they show the
other side of the paper. How it works is in
[notes/visible-regions.md](notes/visible-regions.md).

A folded form that is *not* flat — paper still in the air — is still painted
face by face in the order `faceOrders` gives, with every crease drawn, because
none of the above has a plane to work in. `--no-fill` also draws every crease,
which is what makes it the escape hatch for a file this cannot make sense of.

One caveat on the colours. Which side of the sheet a patch of paper shows is
read from the order its corners are listed in, which FOLD says is
counterclockwise and which real files sometimes get backwards. A file that wound
*every* face backwards is drawn with its layers right and its two colours
swapped, silently — the layer order survives it because its signs were written
against those same windings, and the paper side has nothing to cancel against.

## What it opens out

Hidden-line removal makes the picture honest, and sometimes honest is useless.
Fold a square into quarters and the four quadrants land exactly on top of one
another: the silhouette is one square, the only visible region is one square,
and the reader is told nothing at all about the four layers underneath. There is
nothing partly hidden to reveal.

Books answer this by drawing the stack slightly opened, and so does `--offset`:

```bash
stack run -- render examples/quarter-fold.fold --fold --offset 6 -o stack.svg
stack run -- render examples/letter-fold.fold  --fold --offset 6 -o letter.svg
stack run -- render examples/kabuto.fold       --fold --offset 6 -o kabuto.svg
stack run -- render examples/crane.fold --fold --rotate 180 --offset 1.5 --margin 60 -o crane.svg
```

Every face is drawn whole and each layer sits a few points further up and to the
right than the layer below it, the way an exploded drawing separates the parts
of an assembly. The quarter fold becomes four stepped squares in the order the
solver found, bottom-left quadrant lowest; the letter fold shows its middle
panel, which the ordinary picture buries whole; and the kabuto's twelve layers
open into a band of stepped sheets down its diagonal.

The step is in **page units**, which is the two-unit rule doing real work: six
points is six points whether the sheet is one unit across or four hundred, so
the model's own coordinates are never touched and the page does not rescale
because a stack was opened.

### The stack is drawn finer than the model

The drawing is in two weights, and it has to be. A sheet buried in the stack is
drawn at 0.35pt where the model itself is drawn at 1 to 1.6 — so what the reader
sees is the picture they would have seen without the flag, standing on a fine
hatch of the layers underneath it.

Drawing the stack at the model's own weight is the version that does not work. A
dozen sheet edges within a few points of one another, each as heavy as the
outline of the paper, add up to a black band; the same edges drawn fine read as
the thickness of the sheaf. It also removes the floor on the step, which used to
be the line weight: a step of 1.5pt separates 0.35pt lines perfectly well, and it
did not separate 1.6pt ones at all.

What remains is a ceiling. The step times the number of layers has to fit the
page, because the offset deliberately does not enter the extent — the page is
fitted to the paper, and opening a stack does not shrink the model to make room.
A deep model wants a small step, a wide `--margin`, or both.

### How many layers is too many

Fold a square in half twice and you have four layers; fold anything worth
folding and you have thirty. The crane is **32 layers** deep, and an offset view
of it is dense — not because the drawing is wrong but because the model is like
that, and the picture is telling the truth about it.

Printed books do not answer this by exploding the whole model. Robert Lang's
diagramming conventions give three tools in order of desperation: **x-ray
lines** for a few hidden edges, and only as many as the current step needs;
a **cut-away** when those get cluttered — a heavy circle with the obscuring
layers removed inside it, and edges offset where they cross the boundary; and,
when there are too many layers to draw at all, a schematic **side view** of the
stack with an arrow, which is a different picture rather than a busier one.

`--offset` is the second of those applied to the whole sheet rather than inside
a circle. It is the right tool for a model a handful of layers deep, and for a
deep one it is honest rather than legible. The other two are tracked:
[#48](https://github.com/avalonalex/senbazuru/issues/48) for x-ray lines scoped
to the step, [#49](https://github.com/avalonalex/senbazuru/issues/49) for the
cut-away, and [#50](https://github.com/avalonalex/senbazuru/issues/50) for the
side view, which needs the paper to have a thickness and so belongs with the 3D
export.

[notes/layer-numbers.md](notes/layer-numbers.md) has the measurements, and the
two other things worth knowing: which layer a face is in is the longest chain of
faces below it, not a count of what it covers; and a twist has no offset view at
all, because stepping layers apart needs one order for the entire model and a
twist is exactly the model that has none.

## What it instructs

A picture of paper is not an instruction. The arrow that says *this* piece moves
*there* is what makes a diagram teachable, and FOLD has no key for one — no
arrow, no operation, not even a caption. What a file does have is consecutive
frames, and between two of them the arrow is a subtraction rather than a search:
both ends of the motion are given.

`--arrows` draws it, on the frame *before* the fold, as a book does:

```bash
stack run -- render examples/quarter-fold-steps.fold --frame 0 --arrows -o step-1.svg
stack run -- render examples/quarter-fold-steps.fold --frame 1 --arrows -o step-2.svg
stack run -- render examples/quarter-fold-steps.fold --frame 2 -o step-3.svg
```

Step 1 is the flat sheet with an arrow swinging its left half onto the right;
step 2 is the folded rectangle with an arrow bringing its top half down; step 3
is the finished quarter, and carries no arrow because there is nothing left to
do.

What moves is worked out by comparing where the paper *is* in the two frames,
not by reading fold angles — a frame may record none, or record ones that
disagree with its own coordinates, and turning a model over moves paper without
changing any angle. Paper that moves as one piece gets one arrow; a step that
folds two separate flaps gets two, because a single arrow averaged between them
would point somewhere no paper goes.

`--steps` puts the whole sequence on one page instead:

```bash
stack run -- render examples/quarter-fold-steps.fold --steps --arrows \
  --width 700 --height 300 -o page.svg
```

Every figure is drawn at **one shared scale**, so the model genuinely shrinks as
it is folded — the quarter fold ends up a quarter of the size it started. Giving
each figure its own scale is the tempting mistake: every drawing would then be
blown up to fill its cell, and the page would tell the reader, in the most
convincing way a picture can, that folding a sheet in half does not make it
smaller. `--columns` sets how many figures go across.

## What it checks

`senbazuru check` applies two classical theorems to every *interior* vertex of a
crease pattern — a vertex with paper all the way round it, as opposed to one on
the edge of the sheet, where neither theorem applies.

*Maekawa's theorem* says the number of mountain creases at such a vertex minus
the number of valley creases is always ±2. It follows that the total is even, so
three creases meeting at a point can never fold flat, whatever their angles:

```console
$ senbazuru check examples/three-crease.fold
examples/three-crease.fold, frame 0
  vertex 5: 3 creases meet here, an odd number, which never folds flat (Maekawa)
  checked 1 interior vertex; skipped 5 on the border
  1 violation
```

*Kawasaki's theorem* says that walking round the vertex and adding the angles
between consecutive creases with alternating signs gives zero. A square folded
into quarters satisfies both:

```console
$ senbazuru check examples/quarter-fold.fold
examples/quarter-fold.fold, frame 0
  checked 1 interior vertex; skipped 8 on the border
  no violations found
```

It says *no violations found* rather than *flat-foldable*, and that wording is
load-bearing. Both theorems are necessary, not sufficient: they are local, so a
sheet whose every vertex passes can still be impossible, and even at one vertex
they miss a third condition on which crease is a mountain and which a valley.
`examples/big-little-big.fold` passes this check and cannot be folded — see
[big-little-big.md](notes/big-little-big.md). A violation means the pattern
is definitely wrong; a clean run means nothing was caught.

The command exits non-zero when it finds a violation, so it drops into a build
or a hook without anyone grepping the output.

There is also a summary command for poking at unfamiliar files:

```console
$ stack run -- info examples/unit-square.fold
examples/unit-square.fold
  title:   Unit square with a cross of creases
  creator: senbazuru (hand-written)
  classes: singleModel
  frames:  1
  frame 0: Preliminary creases
    classes:  creasePattern
    vertices: 8
    edges:    11
    faces:    0
    creases:  B=8 M=1 V=1 F=1
    layers:   (none, and a crease pattern needs none)
```

The `layers` line is where to look when a folded form comes out as a wireframe:
it reports the `faceOrders` the file carries, or, for a folded form without any,
whether one could be worked out and if not why.
