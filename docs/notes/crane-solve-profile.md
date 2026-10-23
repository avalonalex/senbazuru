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
| Checking the final shape's contact, which ran twice | 9.3% | 4.2% |
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
step's own measurement. A measurement whose derivatives went unread still cost
what a full one did, 0.041% of the run each, because `D` kept its derivative in
a strict field:

```haskell
data D = D {value :: !Double, derivative :: !(IM.IntMap V3)}
```

Computing a value built its derivative too. Removing that one `!` and changing
nothing else, the same program allocated 367.9 GB rather than 615.8 and took
86.4 to 86.8 CPU seconds over three runs, with the same base angle to all 17
digits printed and the same verdicts. [strict-fields](strict-fields.md) is the
other side of this trade. [#441](https://github.com/avalonalex/senbazuru/issues/441)
proposed measuring gaps without derivatives in the line search, and reusing a
measurement rather than repeating it; it was done later (below).

**The clip measured each corner twice.** Clipping one triangle's shadow by a
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

**Two checks repeated work.** `rootAccepted` checked the final shape's contact,
and the quick tier then checked it again for its report, 4.6% and 4.7% of the
time. Building the creased wing checked its layer orders once for every order,
scanning all of them each time: 9% of the time, once per run.

None of these is the language. What hid the cost is that a line like
`crossXY (x, y, _) (a, b, _) = x * b - y * a` reads as arithmetic on numbers,
while `D`'s `Num` instance makes each operator build maps; operator overloading
would hide that in any language that has it. Laziness is the one part particular
to Haskell, and here it is the cheapest lever. The profiler is how to see all of
them, and each is a change to this code.

[#618](https://github.com/avalonalex/senbazuru/issues/618) removed the three
repeats. The clip now measures each corner once, every accept function takes the
contact report its caller already has, and the layer-order check runs once per
face rather than once per order, with the faces in a set. `main` had changed
since the profile above: [#614](https://github.com/avalonalex/senbazuru/pull/614),
which set the clip's band as a distance, took the program from 615.8 GB to
571.3. Measured on 2026-10-22 with the programs in
[profiling-study-code](profiling-study-code.md), in CPU seconds and bytes
allocated, three runs of each, interleaved, with the same results:

| Program, at `-O1` | `main` at `29170c0` | With #618 |
| --- | --- | --- |
| The settles and checks | 108.8 to 109.0 s, 571.3 GB | 86.6 to 86.7 s, 431.7 GB |
| Building the creased wing (`craneRootAt`) ten times | 74.0 to 74.2 s, 132.2 GB | 4.88 to 4.90 s, 24.2 GB |

[#441](https://github.com/avalonalex/senbazuru/issues/441) then made the line
search's tries read gaps alone. A contact *row* is one corner's gap with its
derivatives. With `D`'s derivative field lazy, `SurfaceContact.orderedGaps`
computes the gaps without building a single derivative map, and the line search
judges each try by them. The try it keeps is measured in full, so that a
non-finite derivative still refuses it, and those rows are the next step's own:
its starting penalty comes from them, and so does its stopping test when that
test reads the penalty's own rows. A kept try is still measured twice, by its
gaps and then in full; what the gaps save is the full measurement of every try
refused. Every penalty the line search computes is unchanged, bit for bit: a
trace of two settles, 53 steps and 230 refused tries, prints the same before and
after. Measured on 2026-10-23, three runs of each, interleaved, with the same
results:

| Program, at `-O1` | `main` at `8e9850f` | With #441 |
| --- | --- | --- |
| The settles and checks | 80.3 to 81.5 s, 431.7 GB | 36.6 to 37.0 s, 150.6 GB |
| The crane-internal gallery's short trial, #208's profiling driver | 348.0 to 351.6 s, 1,735 GB | 167.6 to 169.5 s, 615 GB |

`main` here is the same code the #618 table above timed at 86.6 to 86.7
seconds the evening before; only figures timed together compare. A heap profile
by type finds the program's largest live heap unchanged, 168 MB in the final
contact check, while during the settles the heap now peaks at 44 MB rather than
90.

Profiled again, the settles and checks spend 33% of their time and 44% of their
allocation measuring contact, 262 times in full and 437 times by gaps alone, and
the largest single function is now the factorising of the linear equations, at
23% of the time. The driver, profiled the same way, spends 43% of its time and
56% of its allocation measuring contact, 668 times in full and 1,535 by gaps
alone, and 30% of its time factorising.

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
