# A valid state is not a folding route

The opposing-flap demo rejects a full turn that ends where it started: the
flap hits another panel in between. This rejects that particular route. It
does **not** show the endpoint is unreachable; doing nothing is already a
valid route to this identical endpoint.

More generally, distinguish three questions. Does a state preserve the sheet
and avoid crossings? Does a proposed route satisfy those conditions all the
way through? Does *some* permitted route join the chosen start and end? The
first is a state check, the second is motion checking, and the third requires
finding a route or proving one exists. A state check alone supplies neither.

The permitted moves matter. A route requiring a second crease to move is
unavailable when only the selected hinge can turn. Bending a panel may enable
a route unavailable to rigid panels. If a real sheet was physically folded
from that same start, the observed sequence is evidence of a route—but our
model must permit those moves to reproduce it.

A concrete example is the traditional square twist studied by
[Silverberg and colleagues](https://www.nature.com/articles/nmat4232).
Its panels must bend during folding; treating them as rigid removes that
route even though the folded form exists. This is why adding panel bending
can change what our model can reach, rather than merely how it looks.

In rigid origami, each valid choice of crease angles and contacting layer
order is a point in the **configuration space**, the set of permitted states.
Two states are reachable from one another only when a continuous path in that
set joins them. Membership alone does not establish this connection. He and
Guest formalize this equivalence in Theorem 1 of
[On Rigid Origami I](https://arxiv.org/html/1803.01430v3#S3).

`Origami.Flap` currently checks a supplied single-hinge turn. A refusal means
that route collided, contradicted a starting layer order, or could not be
resolved within the numerical check. It is not a proof that every route to
the requested endpoint fails.
