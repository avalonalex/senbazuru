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

## The one that works

ReferenceFinder solves a deliberately narrow version well: given a target point
or line on the square, it searches combinations of the
[Huzita-Hatori axioms](huzita-hatori.md) for a short fold sequence locating it,
ranked by accuracy and fold count. It answers "how do I find the point one third
along this edge", not "how do I fold this crane". TreeMaker, by the same author,
goes stick-figure-to-crease-pattern and likewise does not say how to fold it.

## Why it matters here

Senbazuru renders sequences rather than solving for them, and FOLD is built for
that: a multi-frame file *is* the sequence. Knowing no general solver exists is
what makes consuming `file_frames` the right target rather than a stopgap.

A ReferenceFinder-style search would be in scope, though: a bounded search over
seven axioms to a depth of four or five folds is tractable and self-contained.

## References

- Arkin, Bender, Demaine, Demaine, Mitchell, Sethia & Skiena, "When can you fold
  a map?", *Computational Geometry* 31(1-2), 2004.
- Bern & Hayes, "The complexity of flat origami", *SODA*, 1996.
- Robert Lang, *ReferenceFinder* and *TreeMaker* — <https://langorigami.com>
