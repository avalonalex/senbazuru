# Related projects

The other software in this space, what each one does, and what senbazuru has
taken or could take from it. Kept as one list so that "has anyone done this?"
has a place to look before an issue is written.

**The licence column comes first for a reason.** The rule in
[CLAUDE.md](../CLAUDE.md#third-party-material) is that ideas travel and
expression does not: a published algorithm can be reimplemented from
understanding, and a GPL implementation can be read to understand the domain
and never copied, fixtures included. MIT projects can be vendored with
attribution, but a repository licence is not a design licence, so another
designer's crease pattern in an MIT repo is still theirs. When a licence below
says *not checked*, check it before reading the code.

## Tools that read or write FOLD

| Project | What it is | Licence | Why it matters here |
| --- | --- | --- | --- |
| [FOLD](https://github.com/edemaine/FOLD) — Demaine, Ku, Lang | The format: spec, a JavaScript library, a browser viewer, and the example files three of ours come from | MIT | The spec is the contract `Senbazuru.Fold.Types` mirrors; [docs/fold-reference.md](fold-reference.md) tracks every key. The viewer is the reference picture of a file. |
| [Flat-Folder](https://github.com/origamimagiro/flat-folder) — Jason Ku | Browser crease-pattern solver: reads FOLD, SVG, `.opx`, `.cp`; traces faces; solves the layer order by the taco-taco rules, splits it into components, counts the states; x-ray and flip views; exports the pattern and the folded state as FOLD | MIT | The layer solver `Senbazuru.Origami.Stacking` is validated against its published table, and five of our examples are its files. It solves *unassigned* creases, which is [#38](https://github.com/avalonalex/senbazuru/issues/38); its 755 patterns are the corpus [#93](https://github.com/avalonalex/senbazuru/issues/93) will run. |
| [Origami Simulator](https://github.com/amandaghassaei/OrigamiSimulator) — Amanda Ghassaei | Browser physics simulation: every crease folds at once, a slider from 0 to 100%, strain shown in colour; reads SVG and FOLD, writes FOLD, OBJ, STL and GIF | MIT | The *compliant* model senbazuru deliberately is not ([#64](https://github.com/avalonalex/senbazuru/issues/64)). Its folded states are what [#53](https://github.com/avalonalex/senbazuru/issues/53) will read to see what real angles look like. |
| [Rabbit Ear](https://github.com/robbykraft/Origami) — Robby Kraft | JavaScript library: planar-graph repair, the Huzita–Hatori axioms, single-vertex checks, flat folding, a layer solver on Ku's rules, SVG and WebGL rendering | GPL-3.0 | The closest thing to senbazuru as a *library*. Read it for the shape of the problems; reimplement, never copy. |
| [origami-diagrams](https://github.com/mayakraft/origami-diagrams) — Robby Kraft | Diagrams from a FOLD file's frames, with arrows, multilingual captions and step numbers stored under vendor keys | MIT | The one other project aiming at printed diagrams from FOLD. It *stores* arrows; senbazuru *infers* them from consecutive frames, and would read captions off the standard `frame_title` ([#94](https://github.com/avalonalex/senbazuru/issues/94)). |
| [ORIPA](https://github.com/oripa/oripa) — Jun Mitani and contributors | The original crease-pattern editor, in Java: draws, estimates the folded form, enumerates layer orders, writes `.opx`, FOLD, SVG and images | GPL-3.0 | `.opx` is its format, read by `Senbazuru.Import.Opx` from the format alone. Its folded-form export is what [#91](https://github.com/avalonalex/senbazuru/issues/91) gives senbazuru. Its own `turkey2015.opx` has 71 creases stopping on another, which is why `Fold.Crossings` exists. |
| [Oriedita](https://github.com/oriedita/oriedita) | A crease-pattern editor forked from Orihime: draws, checks flat-foldability by the extended Fushimi theorem, folds very complex patterns, writes `.cp`, `.ori`, FOLD, SVG, PNG | MIT | `.cp` is its format and Orihime's; `examples/bird-base.cp` is its test fixture. Its source is readable for the format, and the rule is still to reimplement. Its y-down export mirrors our y-up reading, deliberately. |
| [Orihime](https://oriedita.github.io/) — Toshiyuki Meguro | The editor Oriedita was forked from, and the origin of the `.cp` format and its type codes | see Oriedita | Historical. Everything worth knowing about it is in [notes/cp-and-opx.md](notes/cp-and-opx.md). |
| [Rhino Grasshopper FOLD plugin](https://github.com/edemaine/FOLD#software) | Converts between Rhino meshes and FOLD | — | Not relevant yet; listed because the FOLD README does. |

## Tools that do not speak FOLD

| Project | What it is | Licence | Why it matters here |
| --- | --- | --- | --- |
| [Freeform Origami, Rigid Origami Simulator, Origamizer](https://tsg.ne.jp/TT/software/) — Tomohiro Tachi | Rigid-origami kinematics, interactive design under rigid constraints, and crease patterns for any polyhedron | Binaries only, non-commercial | Tachi's *papers* are the method [#55](https://github.com/avalonalex/senbazuru/issues/55) follows; the binaries are what to compare against once it exists. |
| [TreeMaker](https://langorigami.com/article/treemaker/) — Robert J. Lang | Turns a stick figure into a crease pattern for a base | GPL | The design end of the pipeline, which senbazuru does not do. Read for the vocabulary of bases and flaps. |
| [ReferenceFinder](https://langorigami.com/article/referencefinder/) — Robert J. Lang | Finds a short folding sequence that lands a reference point or line, by searching the Huzita–Hatori axioms | GPL (not checked) | Exactly the *reference* vocabulary a written folding scheme needs ([#97](https://github.com/avalonalex/senbazuru/issues/97)); see [notes/huzita-hatori.md](notes/huzita-hatori.md). |
| [Doodle](https://doodle.sourceforge.net/) — Jérôme Gout and others | A text language for origami diagrams, compiled to PostScript. 2000–2001 | not checked | A whole diagramming language with no geometry in it: the arrows and captions were typed, not computed. One of the three shapes [#97](https://github.com/avalonalex/senbazuru/issues/97) weighs. |
| [Foldinator](https://zingman.com/origami/foldinator3OSMEpaper.php) — John Szinger, 2001 | A modeller that folds a sheet step by step in 3D and generates annotated diagrams. Valley, mountain and reverse folds; never released | paper only | The closest ancestor of [#60](https://github.com/avalonalex/senbazuru/issues/60), and a record of how far a fold vocabulary got twenty-five years ago. |
| [rigid-origami](https://github.com/belalugaX/rigid-origami) | Python: rigid-origami crease-pattern generation and folding simulation, framed as a game environment | not checked | Another rigid-origami simulator to compare angle solutions against. |
| [OrigamiSimulator (MATLAB)](https://github.com/zzhuyii/OrigamiSimulator) — Yuyuan Zhu | Bar-and-hinge simulation of active origami: compliant creases, panel contact, thermal actuation | not checked | What keeping paper out of paper ([#61](https://github.com/avalonalex/senbazuru/issues/61)) looks like in a compliant model. |

## Research, 2026

Four papers that build a formal move vocabulary, which
[notes/no-sequence-solver.md](notes/no-sequence-solver.md) was written before.
[#96](https://github.com/avalonalex/senbazuru/issues/96) is the note that
reconciles them.

- **OrigamiBench** — [arXiv 2603.13856](https://arxiv.org/abs/2603.13856). An
  environment where a model proposes one fold at a time against a target and
  gets validity and similarity back.
- **Learn2Fold** — [arXiv 2603.29585](https://arxiv.org/abs/2603.29585). An LLM
  emits a folding program over a crease-pattern graph; a learned world model
  predicts whether each step is feasible.
- **COrigami** — [arXiv 2606.26299](https://arxiv.org/abs/2606.26299). Text to
  crease pattern, by way of a stick figure and a base packing.
- **FoldingAgent** — [arXiv 2609.00377](https://arxiv.org/abs/2609.00377).
  Parametric folding procedures inferred from demonstration videos.

## Reading

The theorems and algorithms senbazuru leans on are cited note by note in
[notes/](notes/README.md). Three sources come up often enough to name here:

- Robert J. Lang, *Origami Diagramming Conventions* — [via
  zenorig](https://zenorig.blogspot.com/2012/09/origami-diagramming-conventions-robert.html).
  The x-ray line, the cut-away and the side view, which are
  [#48](https://github.com/avalonalex/senbazuru/issues/48),
  [#49](https://github.com/avalonalex/senbazuru/issues/49) and
  [#50](https://github.com/avalonalex/senbazuru/issues/50).
- Erik Demaine and Joseph O'Rourke, *Geometric Folding Algorithms* (2007). The
  theorems in [notes/maekawa.md](notes/maekawa.md),
  [notes/kawasaki.md](notes/kawasaki.md) and
  [notes/flat-foldability-is-hard.md](notes/flat-foldability-is-hard.md).
- Tomohiro Tachi, *Simulation of Rigid Origami* (2009). The angle solve
  [#55](https://github.com/avalonalex/senbazuru/issues/55) follows.
