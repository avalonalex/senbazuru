# A model usually has many layer orders, and they multiply

Fold a crane and press it flat. There is not *one* way its seventy-two faces can
be stacked — there are five. All five fold from the same creases without the
paper passing through itself, and two of them are different pictures: a flap on
the right wing is on top in one and buried in the other.

That is the ordinary case, not a curiosity. Of the models senbazuru has been run
against, the kabuto has nine orders, Ku's pinwheel pockets has forty-seven, and
one of Flat-Folder's dragons has more than 10⁸³ — more than there are atoms in
the observable universe. So "how many orders does this model have" cannot be
answered by listing them.

## Why the number is so large, and why that is good news

The constraints are local. Every rule the paper imposes
([taco-taco.md](taco-taco.md)) is about a handful of faces that share an edge or
a patch of paper, and most pairs of faces share neither. So the constraint graph
— pairs of faces as nodes, rules as the edges joining them — usually falls apart
into pieces that share nothing.

Two consequences, and they are the same fact read twice.

**The count multiplies.** If one piece admits three orders and another admits
three, the model admits nine, because the choices are independent. That is why
the totals get astronomical: they are products of small numbers, not one big
number.

**The cost adds up.** Searching each piece separately costs the *sum* of the
pieces' costs rather than the product. The crane has 892 pairs of overlapping
faces; propagation settles 805 of them outright, and the 87 left form a single
piece that eight guesses exhaust. Searching all 87 as one problem would be a
search of 2⁸⁷ in the worst case. Splitting first is the difference between a
solver that finishes and one that might not.

## Counting them without listing them

Describe the answer as a product rather than as a list:

- the pairs propagation settled, which every valid order agrees about;
- and, for each remaining piece, the orders *it* admits.

The model's orders are every combination. A count is the product; a particular
one is an index per piece. `senbazuru info --fold` prints the shape and
`--stacking` takes the indices.

Flat-Folder records the same shape for each of its 755 examples, as
`component_assignments`. The crane is `|1|5|` — one settled piece admitting a
single answer, one open piece admitting five. Its count of *components* always
includes that settled piece, even when there is nothing in it, which is worth
knowing when comparing figures: what senbazuru calls one component of the crane
it calls two.

## The counts agree

`Senbazuru.Origami.Stacking` splits the graph the same way, and its numbers
match Flat-Folder's model for model — not only the totals but the shape:

| model | components | orders | per component |
| --- | --- | --- | --- |
| traditional crane | 2 | 5 | `\|1\|5\|` |
| traditional kabuto | 3 | 9 | `\|1\|3\|3\|` |
| Brown's 2×2 D1 grid | 5 | 16 | `\|1\|2\|2\|2\|2\|` |
| Ku's thirds pinwheel | 1 | 1 | `\|1\|` |

Most of the difference between orders is buried. All sixteen of the grid's are
the same picture from either side; all nine of the kabuto's are one picture from
above and four from below. The crane's five make two pictures. A count of orders
is a count of *models*, and how many of them a reader could tell apart is a
different and smaller number.

## Why the search still needs a budget

Splitting bounds the work by the size of the largest piece, which is a real
bound and not a guarantee. Nothing stops a model from having one large piece
whose contradiction propagation cannot reach, and the search there is
exponential. Counting guesses and stopping is what turns that from a tool that
hangs into a tool that says it gave up — and a count of guesses, rather than a
stopwatch, is what makes the same file behave the same way on every machine.

## References

- Jason Ku, [Flat-Folder](https://github.com/origamimagiro/flat-folder) — splits
  the constraint graph the same way and publishes the counts its solver found,
  which is what the table above is checked against.
- Erik Demaine & Joseph O'Rourke, *Geometric Folding Algorithms*, Cambridge
  University Press, 2007 — the layer-order problem and its complexity.
- [layer-ordering.md](layer-ordering.md) on why finding even one order is hard,
  and [taco-taco.md](taco-taco.md) on the rules being searched over.
