# Where the crane solve's time goes

Terms are in [the glossary](../glossary.md). The [quick tier](quick-tier.md)
gives one settled crane with its wing spread. It turns the wing's base, the four
layers above the wing's widest point, as one piece, and at each of nine angles
of that turn it *settles* the rest of the wing: it moves the paper until its
lengths, its creases' springs and its layers' contacts balance. Each settle
takes steps. A step writes every one of those requirements as a linear
equation in how the vertices move, solves the equations together (factorising
them, then refining the answer by conjugate gradients), and then tries the move
at its whole length, half of it, a quarter and so on, keeping the first try that
lowers the total penalty. Each try measures again how far apart the paper's
layers are.

On 2026-10-22 the quick tier's settles and checks were profiled, on `main` at
`806e55a`, compiled at `-O1` as `stack run` builds the study, to see where the
time goes. [profiling-study-code](profiling-study-code.md) has the program and
the commands. One profiled run gave this, with each row counting everything
the functions it names call:

| Where the time goes | Time | Allocation |
| --- | ---: | ---: |
| Measuring contact: 1,588 times, clipping 7.6 million pairs of triangles | 65% | 81% |
| …of which arithmetic on the derivative type `D`, with the vector sums inside its maps | 47% | 70% |
| Factorising the linear equations, 263 times | 7.6% | 6.9% |
| Conjugate gradients | 0.9% | 1.5% |
| Checking the final shape's contact, which runs twice | 9.3% | 4.2% |
| Building the creased wing, mostly checking its layer orders | 9.1% | 2.4% |
| Everything else | 8% | 4.5% |

A *cost centre* is a label the profiler charges time and allocation to. The
study's modules had one on each top-level function and the library one on every
binding, and each call into one costs extra, so the profiled run took 134 CPU
seconds against 107 without. The rows that are called most, `D`'s, are
overstated in time. Allocation is not distorted: 628 GB profiled, 616 GB
without.

Without the profiler, three runs took 106.7, 108.2 and 106.8 CPU seconds, 23%
of it collecting garbage, and each allocated 615,832,033,672 bytes, the same to
the byte, at a maximum residency of 152 MB. The whole quick tier, which also
draws its page, took 110.2 to 110.5 CPU seconds and allocated 633.8 GB, the
three runs differing by 10 KB. [quick-tier](quick-tier.md)'s 92.3 seconds times
the nine settles alone.

**Most of the contact measured is never differentiated.** The 263 steps need
contact's derivatives once each, to write their equations. The other 1,325
measurements never read a derivative: they are the line search's tries, its
starting penalty, the stopping test and the setup's checks, and in every step
the starting penalty and the stopping test measure the same positions as the
step's own measurement. A measurement whose derivatives go unread still costs
what a full one does, 0.041% of the run each, because `D` keeps its derivative
in a strict field:

```haskell
data D = D {value :: !Double, derivative :: !(IM.IntMap V3)}
```

Computing a value builds its derivative too. Removing that one `!` and changing
nothing else, the same program allocated 367.9 GB rather than 615.8 and took
86.4 to 86.8 CPU seconds over three runs, with the same base angle to all 17
digits printed and the same verdicts. [strict-fields](strict-fields.md) is the
other side of this trade. [#441](https://github.com/avalonalex/senbazuru/issues/441)
proposes measuring gaps without derivatives in the line search, and reusing a
measurement rather than repeating it.

**The clip measures each corner twice.** Clipping one triangle's shadow by a
side of another asks how far each corner is from the side's line, and each
corner is the end of one edge and the start of the next. Measured once per
corner, the program allocated 486.1 GB and took 96.8 to 97.6 seconds, with the
same results.

**Each derivative is a map.** It maps a vertex id to a vector, so multiplying
two `D`s builds new maps rather than doing arithmetic:

```haskell
D a da * D b db = D (a * b) (IM.unionWith (^+^) (IM.map (b *^) da) (IM.map (a *^) db))
```

A map keyed by vertex lets two triangles that share a vertex add their
contributions to it. [#615](https://github.com/avalonalex/senbazuru/issues/615)
proposes fixed slots instead.

**Two checks repeat work.** `rootAccepted` checks the final shape's contact, and
the quick tier then checks it again for its report, 4.6% and 4.7% of the time.
Building the creased wing checks its layer orders by scanning lists of face ids,
9% of the time, once per run.

[#618](https://github.com/avalonalex/senbazuru/issues/618) removed these three.
The clip now measures each corner once, the accept functions take the contact
report their callers already have, and the layer-order check keeps its faces in
a set. Measured on 2026-10-22, in CPU seconds and bytes allocated, three runs
each, with the same results:

| Program, at `-O1` | `main` at `29170c0` | With #618 |
| --- | --- | --- |
| The settles and checks | 103.7 to 104.3 s, 571.3 GB | 83.7 to 85.8 s, 442.1 GB |
| `craneRootAt` alone, ten times | 72.6 to 73.1 s, 132.2 GB | 26.4 to 27.5 s, 127.4 GB |

`main` had changed since the table above: #614, which set the clip's band as a
distance, took the program from 615.8 GB to 571.3.

None of these is the language. What hid the cost is that a line like
`crossXY (x, y, _) (a, b, _) = x * b - y * a` reads as arithmetic on numbers,
while `D`'s `Num` instance makes each operator build maps; operator overloading
would hide that in any language that has it. Laziness is the one part particular
to Haskell, and here it is the cheapest lever. The profiler is how to see all of
them, and each is a change to this code.

Owner decision 61 ([#606](https://github.com/avalonalex/senbazuru/issues/606))
asks that one model's whole `senbazuru run` finish within ten minutes of wall
clock on this Mac. These are CPU seconds of a single-threaded study program,
while `senbazuru` is built with the threaded runtime, so its clock and its
garbage collection can differ. The quick tier already takes under two minutes.
The costly settles are elsewhere: the finer mesh takes about three minutes for
one ([spreading-connected-wing](spreading-connected-wing.md)), and one
released body control takes 3,902 seconds for its three
([quick-tier](quick-tier.md)). Their shares may differ from these: an earlier
profile of another crane solve put factorising at 31%
([internal-crease-diagnostic](internal-crease-diagnostic.md)).
