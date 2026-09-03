# Kawasaki's theorem

Take a single vertex with creases separating angles `t1, t2, ... t2n` in
rotational order. It folds flat **if and only if** the alternating sum is zero:

    t1 - t2 + t3 - ... - t2n = 0

Equivalently: the odd-numbered angles sum to 180 degrees, and so do the even
ones.

What makes this notable is the *if and only if*. [Maekawa's
theorem](maekawa.md) gives a condition that must hold; Kawasaki's settles the
question completely for one vertex. Sum the angles with alternating signs and
compare to zero -- that is the entire algorithm, linear in the number of creases.

It says nothing about *which* creases are mountains and which are valleys. That
is a separate question, constrained by Maekawa on the counts and by the
Big-Little-Big lemma on the arrangement.

## Why it matters here

Same appeal as Maekawa, but it needs angles, so it needs coordinates: take
`atan2` of each incident edge direction, sort, difference. That makes it the
first place in senbazuru where floating-point tolerance is a real design
question rather than a formatting one -- see
[robust-predicates.md](robust-predicates.md).

The "if and only if" applies to a *single vertex*. Whole crease patterns are a
different matter entirely: see
[flat-foldability-is-hard.md](flat-foldability-is-hard.md).

## References

- Toshikazu Kawasaki, "On the relation between mountain-creases and
  valley-creases of a flat origami", in *Origami Science and Technology*
  (H. Huzita, ed.), 1989. Found independently by Jacques Justin.
- Thomas Hull, *Origametry*, Cambridge University Press, 2020.
