# Why there is no folding sequence solver

Given a crease pattern, produce the step-by-step instructions for folding it.
It is the natural thing to want from an origami tool, and in general nobody can
do it. Three reasons, and only the last is about complexity.

**A "step" is not a formal object.** Diagrams are written in named macro-moves —
squash fold, petal fold, inside reverse fold — each several creases formed
together with a particular manipulation. A solver would have to emit those, and
there is no agreed formalisation of the vocabulary to emit.

**Many crease patterns are not folded sequentially.** Tessellations and most
Lang-style designs are *collapsed*: precrease everything, then bring it together
at once. Ask a folder for the sequence and often there is not one.

**The formalised restrictions are NP-hard.** *Simple foldability* — can the
sheet be folded by repeatedly folding along one line through all layers? — is
NP-hard, and that is the easy cousin. Plain
[flat-foldability](flat-foldability-is-hard.md) is already NP-hard before anyone
asks for an ordering.

This third reason is the **weakest** of the three, and it is worth saying so.
NP-hardness implies little about real instance sizes: layer ordering is also
NP-hard and is solved *completely*, in a browser, by branch-and-propagate search.
Compute is not the scarce resource here. The barrier is the first reason — you
cannot search a move set nobody has defined, and if you substitute the nearest
well-defined one (all simple folds) the search returns valid sequences that fold
through forty layers and no human could execute.

## The one that works

ReferenceFinder searches combinations of the
[Huzita-Hatori axioms](huzita-hatori.md) for a short fold sequence locating a
target point or line on the square, ranked by accuracy and fold count. It
answers "how do I find the point one third along this edge", not "how do I fold
this crane" — a defined move set and a bounded depth, which is exactly why it
works.

## Why it matters here

Senbazuru renders sequences rather than solving for them, and FOLD is built for
that: a multi-frame file *is* the sequence.

With one catch. FOLD stores the *states*, not the transitions — there is no key
anywhere in the format for an arrow, an operation, or a step caption. So even a
hand-authored sequence needs its arrows inferred by diffing consecutive frames
for creases whose fold angle changed. That is a well-posed problem, unlike the
one this note is about: you have both endpoints, so you are subtracting rather
than searching.

## References

- Arkin, Bender, Demaine, Demaine, Mitchell, Sethia & Skiena, "When can you fold
  a map?", *Computational Geometry* 31(1-2), 2004.
- Bern & Hayes, "The complexity of flat origami", *SODA*, 1996.
- Robert Lang, *ReferenceFinder* and *TreeMaker* — <https://langorigami.com>
