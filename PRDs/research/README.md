# Research behind the sequence-language and material-rendering PRDs

These notes were written on 2026-09-14 against `568dcb6`. They are **snapshots**:
line numbers, issue states and measurements are as they were that day. They
are the evidence the PRDs one directory up cite; the PRDs, not these notes,
record the decisions. E3 is the exception: it was written on 2026-09-23
against `19de099`, after the first sequence code merged, and revised the same
day after review. The decision it led to is recorded in `decisions.md` like the
rest, and its evidence adds two kinds, sources read in full and a run of the
library in GHCi, whose script is in [`scripts/`](scripts).

The file names are research keys (A1, A2, B, …) because the notes cite each
other by them, for example "A2 F8" means finding 8 of the A2 note.

## How to read them

Every note has the same shape: **Summary**, numbered **Findings** with
citations, **Implications for the design**, **Open questions**, and
**Unverified**. The last section is the important one. Anything a note could
not check is listed there rather than stated as fact.

Evidence comes in five kinds. Each note says which kind backs each claim:

- **Code read at cited lines.** The strongest claim a note makes about
  behaviour, short of running it.
- **`jq` or Python on fixture JSON.** A measurement of a file, not of
  senbazuru.
- **A Python re-implementation**, used in `gap-layer-selective-folds`. It is
  independent of senbazuru and checked against the library at one tip
  position; see its Unverified section.
- **A prebuilt binary from 2026-09-07**, used in
  `gap-assignment-at-rest-convention`. Its strokes matched the current
  quarter-fold goldens; later renderer changes could alter other frames.
- **Fetched web sources.** URLs are given; external licences are stated as
  read, not as legal advice.

Nothing in the repository was modified to produce these notes. Before E3, no
note ran `stack build` or `stack test` in the working checkout; E3's script
loads the library with `stack ghci`, which builds it.
`gap-sequence-cost-and-test-budget` built and ran in separate clones.

## The notes

### The code as it stands

| Note | What it establishes |
| --- | --- |
| [A1 — the library's rigid fold solver](A1-library-fold-solver.md) | The library's state is fold angles on a *cut* crease pattern, and positions are derived. There are exactly three moves: crease a flat sheet, crease through layers, and one checked hinge turn. Edge and face ids do not survive creasing; vertex ids and material coordinates do. |
| [A2 — the study's recipes as a proto-language](A2-study-recipes-as-proto-dsl.md) | Four ways the study writes sequences today: angle tables, flap recipes, certified coupled routes, flat checkpoints. The handoff policy they all repeat. The `cases.json` schema and what it cannot say. Which existing goldens could be acceptance tests. **Erratum** at the top. |
| [B — the material study's mechanics](B-material-study-mechanics.md) | What the bending, contact and relaxation solvers need and return, how mature each is, and what they cost. A checked rigid state is *already* an equilibrium, so "settle" must be told what differs. The order in which study code could move into the library. |
| [C — renderers, CLI and formats](C-renderers-cli-formats.md) | What each backend consumes. What "wireframe" means today (`--no-fill`, buried edges included). What glTF writes and lacks. The CLI's verb structure. Why a sequence file is a program rather than an input format. megaparsec 9.5.0 is in the pinned snapshot. **Erratum** at the top. |
| [D — decisions already on record](D-docs-issues-constraints.md) | Thirty recorded rules and decisions, each marked as reinforced, strained or overturned by the request. The dependency graph of the open issues. Acceptance criteria checked against fixtures. Glossary gaps. |

### Prior art

| Note | What it establishes |
| --- | --- |
| [E1 — sequence languages and programs](E1-prior-art-sequence-languages.md) | Doodle, Eos, Foldinator, origami-diagrams, Rabbit Ear, Akitaya et al., and the four 2026 papers (all four arXiv ids resolve), with each one's move and reference vocabulary and licence. A table of book moves, each classed as a hinge, a coupled motion, or needing bending. |
| [E2 — references and persistent naming](E2-references-and-persistent-naming.md) | The Huzita–Justin–Hatori operations and how many answers each can have. How books name paper. CAD's topological naming problem and what maps onto senbazuru: the sheet is a fixed parameter domain. Machine knitting as the analogous craft language. A proposed reference vocabulary. |
| [E3 — sequences with formal semantics](E3-formal-fold-semantics.md) | Five families that define what a fold is: abstract origami and Eos, folded states and simple folds, formalised construction axioms and Beloch, simulators and robot folds, and the notation's own semantics. No source gives reopening a folded hinge a sense read from the viewer, and where a viewer's sense word is used it names where the moving paper goes; senbazuru's first rule, reading the held face, made a page turn depend on which crease is listed first. Corrections to E1 and E2. |
| [F — Haskell embedding techniques](F-haskell-edsl-techniques.md) | Deep and shallow embeddings, free monads and tagless final, each judged against a language that must round-trip through a file. Builder ergonomics. megaparsec versus JSON. Round-trip properties. What is checked statically and what only running decides. |
| [G — realistic rendering and simulation](G-realistic-rendering-and-simulation.md) | Geometry models from rigid panels to IPC-style contact. glTF material and animation options with viewer support. Classifying SVG lines by provenance rather than dihedral angle. A fidelity ladder, G0–G4, with an appearance axis and a line-drawing axis. |

### Critic and follow-ups

| Note | What it establishes |
| --- | --- |
| [Z — critic](Z-critic.md) | 32 spot checks of load-bearing claims: 30 hold, and 2 are wrong, noted as errata in A2 and C. Ten contradictions between notes. Six gaps, each answered by a `gap-*` note below. |
| [Layer-selective folds](gap-layer-selective-folds.md) | How "fold the top flap along this line" selects faces: a material seed point and "top *n* layers", with a refusal table. On `crane.fold` the rule reproduces the crane-wing recipe's hand-picked faces (Python evidence). Twelve of a traditional crane's 28 steps fold only some layers. |
| [How an unbent crease is written](gap-assignment-at-rest-convention.md) | Five conventions coexist in the repository, measured against `check`, the renderers and the material study. The note recommends writing the state (M < 0, V > 0, F at 0) and keeping intent in the source. |
| [The step annotation channel](gap-step-annotation-channel.md) | What the step page cannot infer: caption, arrow kind, turn-over, precrease. The design is a typed note beside each frame, drawn with defaults that leave output byte-identical. Turn-over axes pass through the extent centre. Crease graphs that grow between steps are matched by material identity rather than backfilled. |
| [Exact landmarks and macro binding](gap-exact-landmarks-and-macro-binding.md) | Why exact algebraic landmark types do not fit the library. The collapse, rabbit-ear and petal signatures, checked by hand on the fixtures. Why a material-point disambiguator is required. The angle-equality policy. |
| [Cost and test budget](gap-sequence-cost-and-test-budget.md) | Measured over 3 runs: any filtered test run pays about 19–21 s of wall time in shared fixture setup. Per-step work counted from the code. Byte sensitivity by platform. An end-to-end acceptance table. The addendum records runs that finished later. |
| [The study's consumption contract](gap-study-consumption-contract.md) | What the material study takes from a move today. A per-move record (the note's heading says per-step). Hold and grip names that survive refinement. A certificate registry. The migration table for every existing recipe. Licence positions for external solvers. |

### Design reviews and drafts

[`spine-reviews/`](spine-reviews) keeps the review that turned these notes into
the decisions in [../decisions.md](../decisions.md). A first draft of the
decisions was attacked through five lenses, and every serious objection was
checked by an independent skeptic, who could confirm it, partly confirm it,
refute it, or find it unclear. A second draft adopted the verified
corrections. The PRD writers then recorded where that draft was still wrong,
and those corrections produced `decisions.md`.

| File | What it is |
| --- | --- |
| [decisions-draft-v1.md](spine-reviews/decisions-draft-v1.md) | The first draft, as reviewed. The reviews cite its line numbers. |
| [review-L1-code-feasibility.md](spine-reviews/review-L1-code-feasibility.md) | Can the code support each decision as described? |
| [review-L2-fixture-truth.md](spine-reviews/review-L2-fixture-truth.md) | Do the example sequences match the fixtures? |
| [review-L3-author-ergonomics.md](spine-reviews/review-L3-author-ergonomics.md) | Can a folder write real book steps in the language? |
| [review-L4-conventions-consistency.md](spine-reviews/review-L4-conventions-consistency.md) | Does the draft follow the repository's conventions, and is it consistent with itself? |
| [review-L5-material-rendering-honesty.md](spine-reviews/review-L5-material-rendering-honesty.md) | Are the material and rendering claims true? |
| [decisions-draft-v2.md](spine-reviews/decisions-draft-v2.md) | The second draft, which adopts the verified objections. The PRD files were written from it. |

The reviews record each objection. The skeptics' verdicts are summarised where
a later draft adopts or rejects the objection, in the drafts' "(L2-4)"-style
references and in the changelog of `decisions.md`.

### Scripts

[`scripts/`](scripts) holds the research code the notes cite, so their
measurements can be rerun. None of it is part of the package, and none of it
is built by `stack` or checked by `make`.

- `layer-selection-analyse.py`: the Python re-implementation behind
  `gap-layer-selective-folds`.
- `time-specs.sh`: the spec-timing loop behind
  `gap-sequence-cost-and-test-budget`.
- `SequenceBench.hs`: the per-stage timing driver that note describes. It was
  **never built or run**; its header gives the cabal stanza it would need.
- `fixture-checks/`: the Python probes the fixture-truth review
  (`review-L2-fixture-truth.md`) ran on the quarter-fold, blintz, bird and
  crane fixtures. They fold flat patterns independently of senbazuru.
- `E3-square-base-listing.ghci`: the run behind E3 section G, which asks
  `prepareFlapToward` for one page turn on `square-base.fold` with its hinge
  creases listed both ways, and asks the layer solver how the page's side
  stacks. Unlike the rest it needs the library; its header gives the command.

## Refined final forms (2026-09-28)

The evidence behind [PRD 11](../11-prd-refined-final-forms.md), written on
2026-09-28 against `83fc960`, after the material study's whole-crane sketches
(#398–#404). It answers why those results do not look refined and how finished
models that open, spread or inflate should be made and drawn. The notes follow
the shape above, with one more evidence kind: **experiments**, bounded runs of
new code (Python, Blender, `ipctk`, CalculiX) in a scratch directory. Nothing in
the repository was changed to produce them.

The research ran in three rounds. Seven slices surveyed the problem and a
critic listed what they missed. Nine experiments then turned open questions into
measurements. An independent verification pass re-ran or re-fetched every
load-bearing claim of H1–H7 and X1–X3, and those notes carry an erratum block
pointing to it where it corrected them. Y1–Y6 ran at the same time and are
single runs.

### Research slices

| Note | What it establishes |
| --- | --- |
| [H1 — diagnosis](H1-diagnosis.md) | The reviewed crane is a shape sketch, not paper: 74.2% of its area strained more than 10%, 345 crossing pairs. The chronology of every approach the study tried, and the pattern that separates what worked. What the drawing adds. What the owner decided, dated. |
| [H2 — sheet mechanics](H2-sheet-mechanics.md) | The study is already a discrete-shell model; what it lacks. Measured paper numbers for a 15 cm kami crane: creases sharp at any diagram scale, panels bending over 11–16 mm beside a crease. Bar-and-hinge, shells, developable geometry and solvers compared. |
| [H3 — contact](H3-contact.md) | Every robust contact method needs a start with no crossings and does not make one. The folded crane's nested creases cannot be thickened by heights alone. IPC, C-IPC, IDP and OGC compared; a Haskell broad phase timed. |
| [H4 — inflation](H4-inflation.md) | Inflated paper is a sheet that cannot stretch but shortens for free. The Mylar balloon and tea bag as benchmarks; pressure versus a volume target; the virtual cap; the puff amount. |
| [H5 — photoreal rendering](H5-photoreal.md) | What makes paper look like paper, in order of payoff. The GLB's two-copy sheet confuses path tracers. glTF extension support as of September 2026. A paper-look recipe for the viewer and for offline stills. |
| [H6 — book illustration](H6-illustration.md) | The book drawing emits each boundary twice and ends lines at crossings. Line roles, chaining, gaps, gradients, and how diagrammers draw. A design for a book renderer of curved paper. |
| [H7 — tooling](H7-tooling.md) | Hackage has no suitable sparse Cholesky, but a readable Haskell LDLᵀ is 200× faster than the study's. Hand-written hyper-duals beat `ad`. `ipctk`, Blender and Mitsuba on this Mac. Where each piece may live. |
| [Z2 — critique](Z2-critic.md) | What the seven slices missed; its experiments became Y1–Y6. |
| [V — verification](V-verification.md) | Every load-bearing claim re-checked: what held, the corrections, one refutation. |

### Experiments

| Note | Question | Answer |
| --- | --- | --- |
| [X1 — paper-look renders](X1-paper-look-renders.md) | Is the problem presentation or geometry? | Valid geometry looks refined under a paper recipe; the sketch does not |
| [X2 — inflating paper](X2-inflating-paper.md) | Can a small model inflate paper correctly? | Yes, with a tension-field membrane: Mylar within 0.44%, tea bag 0.20 |
| [X3 — crane opening](X3-crane-opening.md) | Does a valid start plus IPC open the crane? | Wings spread at 3.1–5.5% edge error; the body opens only 29–40%; the 5.5% run crossed under Additive CCD (V) |
| [Y1 — valid curved looks](Y1-valid-curved-looks.md) | Do valid bent shapes look refined? Is display smoothing safe? | Yes; no, not before thickness |
| [Y2 — reachability](Y2-reachability.md) | Can More tucked be paper? | No: some point must move at least 17 px, proved |
| [Y3 — locking](Y3-locking.md) | Does locking cause the false creases? | No: the construction does |
| [Y4 — crane v2](Y4-crane-v2.md) | With thickness, a body load, a tension-field core and refinement? | A pod, not a pillow; no load lengthened the body |
| [Y5 — water bomb](Y5-waterbomb.md) | Can senbazuru make the water bomb and inflate it? | The flat state folds now; inflation needs crease rest angles |
| [Y6 — FEA oracle](Y6-fea-oracle.md) | Is general shell FEA the answer? | An oracle for inflation (CalculiX agrees to 1.4%), not a route: it has no crease |

### Scripts and images

Each note's own code is in `scripts/<key>/`: Python, shell and Haskell
benchmarks written for the research, no third-party code. They ran
from a scratch directory, and some hold its paths; change them before
rerunning. `scripts/Y5-waterbomb/waterbomb-balloon.fold` is the generated flat
water bomb, a candidate fixture. Large outputs (renders, saved states, logs)
were not kept.

**The 24 scripts that drive Blender through its Python API (`bpy`) are not
here.** Blender's FAQ says published scripts that use that API must be licensed
GPL, and this repository is MIT. Where they belong is owner decision 20 of
[PRD 11](../11-prd-refined-final-forms.md#open-questions-for-the-owner); until it
is decided, each note's reproduce section names the Blender script it ran, and
the shell wrappers that call those scripts will not run as kept.

[`img/`](img) holds one downscaled contact sheet per experiment, the evidence
the notes and PRD 11 show. Commands to regenerate each are in its note.
