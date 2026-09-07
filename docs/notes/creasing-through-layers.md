# Creasing a packet of layers alternates mountain and valley

Terms this assumes — mountain, valley, crease pattern, folded form, flat-folded
— are in [the glossary](../glossary.md).

Fold a square in half. Now, without unfolding it, crease the doubled sheet
somewhere across the middle. Open it out again.

There are two creases, and **they are not the same kind**. One is a mountain and
one is a valley.

That is worth pausing on, because both layers were creased by the same fingers
in the same direction at the same moment. Nothing about the two was different
except which way up the paper was.

## Why

A crease pattern is drawn on one side of the sheet, and mountain and valley are
named from that side: a valley opens towards you when you are looking at that
side, a mountain away from you.

Folding the square in half turns one half of it over. That half is now lying
face down: the side the pattern is drawn on is against the table. So when you
press a fold that opens towards you, you are looking at the *back* of that half
of the paper, and the fold that reads as a valley from where you are sitting is
a mountain on the side the pattern is drawn on.

The other half never turned over, so its crease is a valley on both counts.

## More layers

The rule is per layer, so it follows how each layer got where it is rather than
alternating for its own sake. Fold a unit square into quarters — the four creases
running from the middle to the four edge midpoints — and the paper collapses into
the corner square with `x` between `0.5` and `1` and `y` between `0` and `0.5`.
Crease that four-layer packet with one vertical line at `x = 0.6`. Opening it out
gives four creases, two at `x = 0.6` and two at `x = 0.4`, and their kinds are:

    x = 0.4, y below 0.5   mountain        x = 0.6, y below 0.5   valley
    x = 0.4, y above 0.5   valley          x = 0.6, y above 0.5   mountain

Two of each, and not in a ring: the kind is decided quarter by quarter, by
whether that quarter of the sheet turned over an odd or an even number of times
on its way into the packet. Two of the four are face up when the crease is made
and two are face down, and reading round the middle is the wrong way to look for
the pattern.

## How a program knows

Not from the file. FOLD records a face's corners in order, and the direction
that order runs is the usual way to say which side of a face is its top — but
that is the file's word, and a file that wound every face backwards describes the
same model with no signal to say so. senbazuru treats it as a guess wherever
nothing else cancels against it.

There is a measurement available instead. Folding places each face by one rigid
motion — see [folding-by-transforms.md](folding-by-transforms.md) — and that
motion says where the paper's up direction went. Apply it to the vector pointing
out of the front of the sheet:

- comes back pointing **up**, and the face is still face up;
- comes back pointing **down**, and the face turned over.

For a model folded flat there is nothing in between. Every crease it folds along
is a half turn about a line lying in the plane — and the ones it does not fold
along are no turn at all. A half turn about such a line sends the up direction to
exactly its opposite, so composing any number of them lands on exactly up or
exactly down. So the sign of one number is the whole answer, with no
tolerance to choose and no near-tie to get wrong.

## Why it matters

This is the difference between a program that puts every new crease in the right
*place* and one that also gets it *right*. A file with all the positions correct
and half the assignments inverted looks entirely plausible, passes any test that
compares coordinates, folds without complaint — and folds into a different
model.

## Further reading

- [folding-by-transforms.md](folding-by-transforms.md) — where the per-face
  motions come from.
- [fold-angles-are-the-state.md](fold-angles-are-the-state.md) — why the flat
  pattern stays the authoritative representation, so this move is expressed on
  the sheet and uses the folded model only to say where.
