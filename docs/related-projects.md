# Related projects

The other software in this space, what each one does, and what senbazuru has
taken or could take from it, together with every external program whose answer
the repository relies on. Kept as one list so that "has anyone done this?" has
a place to look before an issue is written.

**The licence column comes first for a reason.** The rule in
[AGENTS.md](../AGENTS.md#third-party-material) is that ideas travel and
expression does not: a published algorithm can be reimplemented from
understanding, and a GPL implementation can be read to understand the domain
and never copied, fixtures included. MIT projects can be vendored with
attribution, but a repository licence is not a design licence, so another
designer's crease pattern in an MIT repo is still theirs. Running someone else's
program and reading its output is not vendoring, but
[AGENTS.md](../AGENTS.md#third-party-material) asks that each one whose answer we
rely on have a row here giving its licence as built. When a licence below says
*not checked*, check it before reading the code.

## Tools that read or write FOLD

| Project | What it is | Licence | Why it matters here |
| --- | --- | --- | --- |
| [FOLD](https://github.com/edemaine/FOLD) — Demaine, Ku, Lang | The format: spec, a JavaScript library, a browser viewer, and the example files three of ours come from | MIT | The spec is the contract `Senbazuru.Fold.Types` mirrors; [docs/fold-reference.md](fold-reference.md) tracks every key. The viewer is the reference picture of a file. |
| [Flat-Folder](https://github.com/origamimagiro/flat-folder) — Jason Ku | Browser crease-pattern solver: reads FOLD, SVG, `.opx`, `.cp`; traces faces; solves the layer order by the taco-taco rules, splits it into components, counts the states; x-ray and flip views; exports the pattern and the folded state as FOLD | MIT | The layer solver `Senbazuru.Origami.Stacking` is validated against its published table, and five of our examples are its files. It solves *unassigned* creases, which is [#38](https://github.com/avalonalex/senbazuru/issues/38); its 755 patterns are the corpus [#93](https://github.com/avalonalex/senbazuru/issues/93) will run. |
| [Origami Simulator](https://github.com/amandaghassaei/OrigamiSimulator) — Amanda Ghassaei | Browser physics simulation: every crease folds at once, a slider from 0 to 100%, strain shown in colour; reads SVG and FOLD, writes FOLD, OBJ, STL and GIF | MIT | The *compliant* model senbazuru deliberately is not ([#64](https://github.com/avalonalex/senbazuru/issues/64)). Its folded states are what [#53](https://github.com/avalonalex/senbazuru/issues/53) will read to see what real angles look like. |
| [Rabbit Ear](https://github.com/robbykraft/Origami) — Robby Kraft | JavaScript library: planar-graph repair, the Huzita–Hatori axioms, single-vertex checks, flat folding, a layer solver on Ku's rules, SVG and WebGL rendering | GPL-3.0 | The closest thing to senbazuru as a *library*. Read it for the shape of the problems; reimplement, never copy. |
| [origami-diagrams](https://github.com/amkraft/origami-diagrams) — Robby Kraft | Diagrams from a FOLD file's frames, with arrows, multilingual captions and step numbers stored under vendor keys | MIT, stated only in `package.json`; no licence file | The one other project aiming at printed diagrams from FOLD. It *stores* arrows; senbazuru *infers* them from consecutive frames, and would read captions off the standard `frame_title` ([#94](https://github.com/avalonalex/senbazuru/issues/94)). |
| [ORIPA](https://github.com/oripa/oripa) — Jun Mitani and contributors | The original crease-pattern editor, in Java: draws, estimates the folded form, enumerates layer orders, writes `.opx`, FOLD, SVG and images | GPL-3.0 | `.opx` is its format, read by `Senbazuru.Import.Opx` from the format alone. Its folded-form export is what the `fold` verb gives senbazuru. Its own `turkey2015.opx` has 71 creases stopping on another, which is why `Fold.Crossings` exists. |
| [Oriedita](https://github.com/oriedita/oriedita) | A crease-pattern editor forked from Orihime: draws, checks flat-foldability by the extended Fushimi theorem, folds very complex patterns, writes `.cp`, `.ori`, FOLD, SVG, PNG | MIT | `.cp` is its format and Orihime's; `examples/bird-base.cp` is its test fixture. Its source is readable for the format, and the rule is still to reimplement. Its y-down export mirrors our y-up reading, deliberately. |
| [Orihime](https://oriedita.github.io/) — Toshiyuki Meguro | The editor Oriedita was forked from, and the origin of the `.cp` format and its type codes | see Oriedita | Historical. Everything worth knowing about it is in [notes/cp-and-opx.md](notes/cp-and-opx.md). |
| [Rhino Grasshopper FOLD plugin](https://github.com/edemaine/FOLD#software) | Converts between Rhino meshes and FOLD | — | Not relevant yet; listed because the FOLD README does. |

## Tools that do not speak FOLD

| Project | What it is | Licence | Why it matters here |
| --- | --- | --- | --- |
| [Freeform Origami, Rigid Origami Simulator, Origamizer](https://tsg.ne.jp/TT/software/) — Tomohiro Tachi | Rigid-origami kinematics, interactive design under rigid constraints, and crease patterns for any polyhedron | Binaries only, non-commercial | Tachi's *papers* are the method [#55](https://github.com/avalonalex/senbazuru/issues/55) follows; the binaries are what to compare against once it exists. |
| [TreeMaker](https://langorigami.com/article/treemaker/) — Robert J. Lang | Turns a stick figure into a crease pattern for a base | GPL | The design end of the pipeline, which senbazuru does not do. Read for the vocabulary of bases and flaps. |
| [ReferenceFinder](https://langorigami.com/article/referencefinder/) — Robert J. Lang | Finds a short folding sequence that lands a reference point or line, by searching the Huzita–Hatori axioms | GPL-2.0 | Exactly the *reference* vocabulary a written folding scheme needs ([#97](https://github.com/avalonalex/senbazuru/issues/97)); see [notes/huzita-hatori.md](notes/huzita-hatori.md). |
| [Eos](https://www.semanticscholar.org/paper/Computational-Origami-System-Eos-Ida-Takahashi/b7ae46f4f3b074d336af2802ac0a8337a39c1ba0) — Tetsuo Ida and others | The E-origami system: Mathematica programs that fold as a person would, implement Huzita's axioms with a logical specification in first-order predicate logic, solve the constraints symbolically, and prove geometric properties of the result | Closed source: Mathematica packages sent on request to project members; the tutorial is CC BY-NC-ND 4.0 | The rigorous answer to the half of [#97](https://github.com/avalonalex/senbazuru/issues/97) that is hard — how a fold names the line it folds on. Read it for the reference vocabulary, and for its formal model of folded paper: faces with adjacency and a superposition relation, a fold as a graph rewrite. It is not a diagram tool, but it does fold whole models: it can fold a chosen set of faces, say where in the stack they go, and has folded a crane. See [E3](../PRDs/research/E3-formal-fold-semantics.md). |
| [Doodle](https://doodle.sourceforge.net/) — Jérôme Gout and others | A text language for origami diagrams, compiled to PostScript. 2000–2001 | GPL-2.0 | A whole diagramming language with no geometry in it: the arrows and captions were typed, not computed. One of the three shapes [#97](https://github.com/avalonalex/senbazuru/issues/97) weighs. |
| [Foldinator](https://zingman.com/origami/foldinator3OSMEpaper.php) — John Szinger, 2001 | A modeller that folds a sheet step by step in 3D and generates annotated diagrams. Valley, mountain and reverse folds; never released | paper only | The closest ancestor of [#60](https://github.com/avalonalex/senbazuru/issues/60), and a record of how far a fold vocabulary got twenty-five years ago. |
| [rigid-origami](https://github.com/belalugaX/rigid-origami) — Geiger, Martinkus, Richter, Wattenhofer | Python: rigid-origami crease-pattern generation and folding simulation, framed as a game environment | Its own: non-commercial research and education only, with a required citation | Another rigid-origami simulator to compare angle solutions against. Not compatible with MIT, so ideas only. |
| [OrigamiSimulator (MATLAB)](https://github.com/zzhuyii/OrigamiSimulator) — Yi Zhu | Bar-and-hinge simulation of active origami: compliant creases, panel contact, thermal actuation. Its README points to a successor, [Sim-FAST](https://github.com/zzhuyii/Sim-FAST) | None: no licence file. Sim-FAST's README declares CC BY 4.0, with no licence file | What keeping paper out of paper ([#61](https://github.com/avalonalex/senbazuru/issues/61)) looks like in a compliant model. Unlicensed code is ideas only; CC BY is not a software licence, so reusing Sim-FAST is an owner decision. |

## Simulators that could inflate a crane

The crane's last step — blow into the body so it rounds out — is the airbag
problem, and the simulators below could compute it. None is needed:
[notes/the-puff-is-a-drawing.md](notes/the-puff-is-a-drawing.md) argues that a
diagram wants a convincing bulge rather than a correct one, and
[#106](https://github.com/avalonalex/senbazuru/issues/106) generates that from
a bump function. This is the list of what accuracy would have cost, kept so the
question is not reopened from scratch.
[PRD 11](../PRDs/11-prd-refined-final-forms.md) ran several of them for its
research, and the rows say what it found. The IPC Toolkit is listed with them
although it is a contact library, not a simulator, because PRD 11's prototype
used it.

| Project | What it is | Licence | Why it matters here |
| --- | --- | --- | --- |
| [LS-DYNA](https://lsdyna.ansys.com/) | Explicit finite element analysis. Simulates folded airbags inflating as a matter of routine, and lets the flat sheet be the stress-free state with the folded one as the start | Commercial | The reference answer, and out of reach. A week to set up the first model. |
| [Abaqus](https://www.3ds.com/products/simulia/) | Implicit and explicit finite element analysis, with shells, pressure loads and contact | Commercial | Same as LS-DYNA. |
| [CalculiX](http://www.calculix.de/) | Open-source nonlinear shells with pressure loads and contact | GPL-2.0: nearly all its source files grant version 2 only, though conda-forge's metadata says or-later. The conda-forge 2.23 build that ran links SPOOLES (public domain), ARPACK-ng and OpenBLAS (BSD-3-Clause), LLVM's OpenMP runtime and the GCC runtime | Free, and it does not know what a crease is: every hinge is a thin strip or a connector you build by hand. It installs on this Mac from conda-forge and agreed with our own solver on an inflated pillow; a fold built from shared nodes came out rigid ([Y6](../PRDs/research/Y6-fea-oracle.md)). |
| [Code_Aster](https://code-aster.org/), [Kratos](https://github.com/KratosMultiphysics/Kratos) | Open-source nonlinear shells with pressure loads and contact | Code_Aster GPL-3.0; Kratos a four-clause BSD licence, with an advertising clause | Free, and neither knows what a crease is, as for CalculiX. Code_Aster's conda-forge package and Kratos's PyPI wheels have no macOS arm64 build. |
| [MERLIN, MERLIN2](http://www.liukepku.com/downloads.html) — Liu and Paulino | The bar-and-hinge reduced-order model for origami: bars along edges, torsional springs at creases and across faces | None stated on the download page, which carries only a site copyright; the archives were not opened | Orders of magnitude cheaper than shells, and its nodes are a FOLD file's vertices. The closest thing to a drop-in. |
| [Blender](https://www.blender.org/) | A cloth simulator with a pressure setting that inflates a closed mesh, and the Cycles path tracer | Source GPL-2.0-or-later; binaries GPL-3.0-or-later. Its FAQ adds that published Python scripts using its API must be licensed GPL as well | For a picture only, which is all a diagram needs. An afternoon rather than a week. Running it is not vendoring, but a published script that uses its Python API is GPL, so none lives in this MIT tree; the shell scripts here only start it from the command line. |
| [ArcSim](http://graphics.berkeley.edu/resources/ARCSim/) | Adaptive cloth simulation written for folding and crumpling paper, with plastic creases | Non-profit use only, citing two papers | Same again: no number anyone would publish, and a puffed crane by the end of the day. |
| [IPC Toolkit](https://github.com/ipc-sim/ipc-toolkit), Python binding [`ipctk`](https://ipctk.xyz/) | Contact for simulation, not a simulator: barrier potentials, continuous collision detection and a thickness offset, which keep surfaces from ever passing through each other | Source MIT. The PyPI wheel statically links filib, which is LGPL-2.1, as the toolkit's own documentation warns; checked in the 1.6.0 macOS wheel | PRD 11's prototype opened the crane with it ([X3](../PRDs/research/X3-crane-opening.md), [Y4](../PRDs/research/Y4-crane-v2.md)). Install and run it; never vendor the wheel. |

SWOMPS, the bar-and-hinge simulator with panel contact and compliant crease
regions, is the OrigamiSimulator (MATLAB) row in the table above.

## Renderers

| Project | What it is | Licence | Why it matters here |
| --- | --- | --- | --- |
| [Mitsuba 3](https://github.com/mitsuba-renderer/mitsuba3) — Wenzel Jakob and others | A research path tracer, scriptable from Python, with two-sided materials | Three-clause BSD text plus a clause granting the author a licence to any improvements you share; GitHub cannot classify it. The 3.9.1 macOS arm64 wheel that ran bundles Embree 3, OpenEXR 2, libpng, libjpeg-turbo and pugixml, all permissive, and links nothing else but its BSD-3-Clause Dr.Jit 1.5.0 wheel and macOS's own libraries | The permissive alternative to Blender for offline stills of paper ([H7](../PRDs/research/H7-tooling.md) finding 15). It reads OBJ and PLY, not glTF. |

## Checkers run by hand

Programs run by hand to check senbazuru's own output. None is run by CI or a
test, as [AGENTS.md](../AGENTS.md#third-party-material) requires. Two programs
listed with the simulators above have been run this way too: Blender, to import a
`.glb` without its window and render it, and the IPC Toolkit, to count crossings
on the study's saved crane body
([notes/crossing-counts-on-touching-paper.md](notes/crossing-counts-on-touching-paper.md)).

| Project | What it is | Licence | Why it matters here |
| --- | --- | --- | --- |
| [glTF Validator](https://github.com/KhronosGroup/glTF-Validator) — Khronos Group | The reference validator for glTF 2.0 and `.glb` files, published to npm as `gltf-validator` | Apache-2.0, as is the npm package that was run | Run by hand on `.glb` output since the export was built ([#51](https://github.com/avalonalex/senbazuru/pull/51)), by `study/gltf/validate.cjs` through its JavaScript API, since the npm package has no command-line program; [study/gltf/README.md](../study/gltf/README.md) pins the version |
| [rsvg-convert](https://gitlab.gnome.org/GNOME/librsvg) (librsvg) — GNOME | Renders SVG to PNG from the command line | LGPL-2.1-or-later, as is the Homebrew 2.62.3 build that was run; it loads GLib, Pango, cairo, FriBiDi, libthai, libdatrie and libintl under the LGPL, and nothing GPL | Rasterises senbazuru's SVG so a drawing can be checked by eye ([H1](../PRDs/research/H1-diagnosis.md)), and SVG for the research's contact sheets ([X1](../PRDs/research/X1-paper-look-renders.md), [Y1](../PRDs/research/Y1-valid-curved-looks.md), [Y5](../PRDs/research/Y5-waterbomb.md)); measured stroke ink for [H6](../PRDs/research/H6-illustration.md), which PRD 11 cites, and caption ink for [PRD 06](../PRDs/06-prd-step-diagrams.md) |
| [three.js](https://github.com/mrdoob/three.js) — Ricardo Cabello and others | A WebGL library for 3D scenes in the browser | MIT, as is the npm package `three@0.186.0` that the study's pages pin, which has no dependencies. [X1](../PRDs/research/X1-paper-look-renders.md) records only release r186, which is 0.186.0 or 0.186.1, both MIT with no dependencies | The viewer [usage.md](usage.md) installs to look at senbazuru's `.glb` output, imported by the study's 3D pages and X1's render comparison |

## Libraries and tools the research relied on

Libraries and programs whose answers the research notes and the study's notes
cite, or whose pictures they keep. The research's own scripts call them; none is
run by CI or a test. Blender, CalculiX and the IPC Toolkit, listed with the
simulators above, and Mitsuba 3, with the renderers, were run for the research
too. Versions are those the notes record unless a row says otherwise. The
Python environments the research ran in are gone, but the wheels it downloaded
were still cached: what each ships and links was read from those files, and
what it compiles in from the scripts that built it
([C100](../PRDs/decisions.md#changes-since-draft-v2)).

| Project | What it is | Licence | Why it matters here |
| --- | --- | --- | --- |
| [ImageMagick](https://imagemagick.org) | Command-line image processing | The ImageMagick licence, an Apache-2.0-style one, for the Homebrew 7.1.2-30 build that was run and is still installed; the notes record 7.1.2. Every run loads LGPL libltdl. Only its HEIC coder links LGPL libheif and libde265 and GPL-2.0-or-later x265, which no recorded use loaded; PostScript and PDF go to AGPL Ghostscript as a separate program | Assembled the full-size contact sheets of [X1](../PRDs/research/X1-paper-look-renders.md), [Y1](../PRDs/research/Y1-valid-curved-looks.md), [Y5](../PRDs/research/Y5-waterbomb.md) and [Y6](../PRDs/research/Y6-fea-oracle.md), which `PRDs/research/img/` keeps downscaled, and measured ink and seam pixels for [H6](../PRDs/research/H6-illustration.md) (findings 2, 20 and 25), which PRD 11 cites |
| [ImageIO](https://developer.apple.com/documentation/imageio) — Apple | The image reading and writing built into macOS, behind `sips` and Preview | Proprietary, part of macOS | Wrote the nine downscaled JPEG contact sheets in `PRDs/research/img/`. No note records the step, but the files' JPEG segments come in the order ImageIO writes them, which `sips` reproduces and ImageMagick does not |
| [SciPy](https://scipy.org) | Scientific computing for Python: sparse solvers, optimisation, interpolation | Source BSD-3-Clause. The macOS 14 arm64 wheels that ran, 1.17.1 and 1.18.1, use Apple's Accelerate but bundle the GCC runtime: libgfortran and libgcc_s, GPL-3.0-or-later with the GCC runtime exception, and LGPL-2.1-or-later libquadmath | The research's solvers and fits ([H7](../PRDs/research/H7-tooling.md), [X2](../PRDs/research/X2-inflating-paper.md), [X3](../PRDs/research/X3-crane-opening.md), [Y2](../PRDs/research/Y2-reachability.md) to [Y4](../PRDs/research/Y4-crane-v2.md)), and the KD-tree in [Y1](../PRDs/research/Y1-valid-curved-looks.md)'s crossing counter |
| [scikit-sparse](https://github.com/scikit-sparse/scikit-sparse) | A Python wrapper for SuiteSparse's sparse Cholesky factorisation, CHOLMOD | Wrapper BSD-2-Clause. Built from the 0.5.0 sdist against Homebrew SuiteSparse 7.14.0, it links CHOLMOD with its GPL-2.0-or-later Supernodal, Modify and MatrixOps modules, and Supernodal ran ([H7](../PRDs/research/H7-tooling.md) finding 17). SuiteSparse's AMD loads the GCC runtime with LGPL libquadmath, and CHOLMOD loads LLVM's OpenMP runtime. The same build made GPL-2.0-or-later UMFPACK and SPQR wrappers, never imported. No note gives the version: 0.5.0 is the first release with the `cho_factor` the scripts call | H7's sparse-solver comparison and IPC prototype (`PRDs/research/scripts/H7-tooling/`). The scripts call the wrapper's BSD API, and the GPL code stays in the user-installed build, as [AGENTS.md](../AGENTS.md#third-party-material) allows |
| [Eigen](https://eigen.tuxfamily.org) | A C++ template library for linear algebra, sparse factorisations included | Homebrew's header-only 5.0.1, declared `MPL-2.0 AND Apache-2.0 AND BSD-3-Clause AND Minpack`; nothing the benchmark included is GPL or LGPL. `SimplicialLDLT` and its AMD ordering, the code that ran, are MPL-2.0: they adapt Davis's LDL and CSparse, which SuiteSparse ships under the LGPL and which their author licensed for Eigen under MPL-2.0 | The third solver in H7's sparse-solver comparison ([H7](../PRDs/research/H7-tooling.md) finding 7, `eigen_ldlt.cpp`), whose time PRD 11 cites |
| [`ad`](https://hackage.haskell.org/package/ad) | Automatic differentiation for Haskell | BSD-3-Clause, as is the 4.5.6 build from Stackage `lts-22.44` that ran; everything it pulls in is BSD-2-Clause, BSD-3-Clause, MIT or ISC, and its optional C tape was off | The correctness reference and speed baseline for H7's hand-written Hessian ([H7](../PRDs/research/H7-tooling.md) finding 8, `hsbench`), which PRD 11 cites |
| [`hmatrix`](https://hackage.haskell.org/package/hmatrix) | Dense linear algebra for Haskell, over BLAS and LAPACK | BSD-3-Clause. The 0.20.2 build from `lts-22.44` that ran links BLAS and LAPACK from Apple's Accelerate, and its dependencies are BSD-3-Clause and MIT; its GSL bindings, `hmatrix-gsl`, are GPL-3.0 and were not used | H7's dense Cholesky timings ([H7](../PRDs/research/H7-tooling.md) finding 9, `hsbench`) |
| [NumPy](https://numpy.org) | Arrays and linear algebra for Python | BSD-3-Clause, and the code its source vendors is permissive. Blender's own 1.26.4 build and the 2.4.6 and 2.5.3 macOS 14 wheels that ran link only Apple's Accelerate and ship no other library. The X2 environment's 1.26.4 was Blender's build or, more likely, PyPI's macOS 11 wheel, which ships OpenBLAS, the GCC runtime and LGPL libquadmath and which pip's cache holds from the day X2 ran; the environment is gone, so which one ran is not known | Independent checks of the study's output in the notes ([crane-pillow-target.md](notes/crane-pillow-target.md), [whole-crane-candidate.md](notes/whole-crane-candidate.md) and others, which record no version), and the research's scripts |
| [Shapely](https://github.com/shapely/shapely) | Planar geometry for Python, over the GEOS library | BSD-3-Clause. The 2.1.2 wheel recorded for X3's environment ([Y4](../PRDs/research/Y4-crane-v2.md)) bundles GEOS 3.13.1 as shared libraries, LGPL-2.1 | The independent polygon engine behind the study's visible-region and coverage checks ([body-visible-layers.md](notes/body-visible-layers.md) and others, which record no version), and [X3](../PRDs/research/X3-crane-opening.md)'s and [Y4](../PRDs/research/Y4-crane-v2.md)'s scripts |
| [matplotlib](https://matplotlib.org) | Plots for Python | Its own licence, modelled on the PSF's. The 3.11.2 wheel statically links FreeType under the FTL, HarfBuzz and libraqm (MIT), SheenBidi (Apache-2.0) and Qhull (its own permissive licence), and ships permissive fonts: nothing GPL or LGPL | The research's plots and several of its contact sheets |
| [Pillow](https://python-pillow.org) | Image reading, writing and drawing for Python | MIT-CMU. The 12.3.0 macOS arm64 wheel recorded for X2's environment ([Y3](../PRDs/research/Y3-locking.md)) bundles only permissive libraries, leaves out GPL libimagequant, and loads LGPL FriBiDi only if it finds one installed | Assembled several research contact sheets |

## Two halves that never met

Three of the entries above are attempts at the thing
[#60](https://github.com/avalonalex/senbazuru/issues/60) wants, and they fall
either side of one line.

**Eos has the geometry and no diagrams.** It is rigorous to the point of proving
theorems about a folded point, and it has folded whole models, a crane among
them, but it is a system for constructing and proving, not for drawing
instructions.

**Doodle has the diagrams and no geometry.** It printed book-quality pages from
typed input in 2000, and it could not tell you whether what you typed was
foldable, because nothing in it knew what paper was.

**Foldinator tried to join them** — fold a sheet step by step in 3D, emit
annotated diagrams — and was never released, so only the paper survives.

That is the gap senbazuru would be filling, and it is worth knowing that the
one previous attempt to fill it did not ship.

## The same problem, outside origami

Naming a flap is the hard part of a written scheme, and it is not an origami
problem. Parametric CAD has fought it for thirty years under the name **the
topological naming problem**: you select a face, the system records an
identifier for it, you change an earlier feature, and the identifier now names a
different face or none. FreeCAD and the commercial packages have all bled on it.

A written fold hits it the moment it says something like *petal fold the front
flap*. That flap is not a corner or an edge of the square; it exists only
because of the folds made before it, so a step inserted earlier can leave the
name pointing at different paper, or at none — and the scheme still parses.
Nobody has a clean answer, but there is a great deal of evidence about which
approaches fail, and it is cheaper to read than to rediscover.

Machine knitting has been through a version of the same exercise from the other
direction, turning a traditional written craft vocabulary into something a
machine can execute.

This belongs here rather than in a note because the useful part is the pointer
to other people's software. If a decision comes out of it, that is
[#97](https://github.com/avalonalex/senbazuru/issues/97).

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

Two more formalise constructions, compared in
[E3](../PRDs/research/E3-formal-fold-semantics.md):

- **Beloch** — [github.com/tophcodes/beloch](https://github.com/tophcodes/beloch),
  MIT, OCaml, with history from April 2026. A declarative fold language on the
  Huzita–Justin axioms whose construction rules are close to ours: candidates
  computed on the current flat state, lines that miss the paper dropped, the
  moving side named in the text, and exactly one answer required. Its decision
  records are worth reading before settling what `nearest P` measures.
- **A Lean Paper About Paper** — [arXiv 2609.14912](https://arxiv.org/abs/2609.14912),
  September 2026. Proves in Lean that each Huzita fold exists, and for some
  that it is unique, but enumerates none, so it cannot confirm that a solver
  found every answer. Its authors' code,
  [celioboulay/origami-formalization](https://github.com/celioboulay/origami-formalization),
  which the paper does not link, has no licence.

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
