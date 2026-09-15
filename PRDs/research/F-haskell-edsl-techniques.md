# F. Haskell techniques for a fold-sequence DSL that is also a text file

Research slice for the PRDs on (1) an embedded Haskell DSL, (2) a CLI-parsed
sequence language, (3) the material study consuming both. No repository file
was modified and nothing was compiled.

## Summary

Recommendation: a **deep embedding** — a first-order syntax tree of steps
whose references to earlier landmarks are explicit *name* nodes — plus a thin
`State` builder that only hands out fresh names and appends steps. Checking,
running, printing, the step page and the material render are all ordinary
functions over that tree or the run's result.
The text form is parsed by megaparsec 9.5.0 (in LTS 22.44, BSD-2-Clause)
into the same tree. Each step keeps a source span, and a QuickCheck property
`parse (pretty s) == Right s` ties the two front ends together. Free and
operational monads and tagless final are rejected. Each puts a Haskell
function where a file needs data, and tagless final also needs a typechecker
to bring text back in. Kind errors (a point where a line is expected) are
caught by one pass over the untyped tree that both front ends share; phantom
types can echo it for Haskell authors but cannot replace it. Geometric
refusals are only found by running, and must come back wrapped with the
step's span. One finding changes #60's shape: the working recipes carry a
folded state and a material pattern from step to step, not a `Frame`.

## Findings

### A. What the repository already commits to

1. **#60 already chose a plain ADT, and its own condition for revisiting that
   is now met — but that condition argues for more functions, not a free
   monad.** Issue #60's Approach says a plain ADT and an interpreter, not a
   free monad, because there is one interpreter and a second would earn it.
   The goal now names at least four consumers (checked run, step page,
   pretty-printer, material render). Gibbons & Wu (finding 11) show that a
   deep ADT gets a second, third, fourth interpretation by writing another
   function over it. So "several interpreters" is an argument for keeping the
   ADT, not for replacing it. A newcomer may read #60 as "free monad once we
   have two interpreters"; the two ideas are independent.

2. **#60's signature `apply :: Move -> Frame -> Either MoveError Frame` is
   out of date relative to the code that actually chains checked folds.**
   `BlintzSequence.buildBlintzSequence` (study/fold-material/BlintzSequence.hs:57-73)
   and the identical loop in HelmetSequence.hs:52-68 thread a `Folded` value.
   Each move runs `prepareFlap`/`prepareFlapAlong` → `checkFlap` → `flapAt 1`.
   The accepted angles *and* `faceOrders` are then copied onto the **original
   material pattern** (BlintzSequence.hs:63), which is refolded, and the
   positions are compared within `1e-12` of the sheet span
   (BlintzSequence.hs:64-70). docs/notes/chaining-checked-folds.md:9-14
   explains why. Copying folded positions into the pattern would describe
   different paper, and re-solving the layer order could pick a different
   stack. Lines 15-23 of that note explain the anchor-face reorder done once
   before any move (BlintzSequence.hs:44-47). The per-move record is a start
   state, a checked motion and an end `Surface V2` (BlintzSequence.hs:32-37),
   not a frame. So an interpreter's state is at least (material pattern,
   `Folded`, anchor). Frames are a *projection* of its output for
   `Render.Steps`.

3. **Raw ids are not stable references; the study already has a
   serialisable replacement.** `Senbazuru.Origami.Flap`'s header
   (src/Senbazuru/Origami/Flap.hs:9-10) says to select ids from
   `foldedPattern`, because cutting crossings can renumber the input. The
   blintz recipe's edge ids refer to the fixture "after cutting and tracing".
   Its face ids refer to the reordered pattern (BlintzSequence.hs:4-8, recipe
   at 51-55). By contrast, `StudyCase.buildCasePose` anchors panel names by a
   material point strictly inside the original sheet. The stated reason is
   that face renumbering during cutting then cannot silently change a name's
   meaning (study/fold-material/StudyCase.hs:117-119). It refuses unless
   exactly one face contains the point (StudyCase.hs:139-143). The JSON
   carrier is `PanelTag {tagName, tagAt}` (study/fold-material/ContactSpec.hs:10-19),
   written as `{"name": "centre", "at": [0.6, 0.6]}` in
   study/fold-material/cases.json. This is the project's own answer to what
   docs/related-projects.md:86-97 calls the topological naming problem, and
   it is plain data. (*Material coordinates*: a point's position on the
   unfolded sheet, docs/glossary.md:81.)

4. **The per-edge angle lists in `cases.json` are the opposite of
   "writable without a calculator".** `CaseSpec` supplies a complete angle
   list per state in the source file's edge order (StudyCase.hs:5-7), and
   `buildPoseAt` refuses a list of the wrong length (StudyCase.hs:152-153).
   You can only write one with the edge numbering in front of you. This is
   fine for a study manifest and is not a model for the authoring language.

5. **Arrows are inferred, so the language does not have to author them.**
   `Senbazuru.Origami.Step` works out motion by subtracting two frames
   (src/Senbazuru/Origami/Step.hs:10-15). The arrow belongs on the frame
   *before* the fold (Step.hs:17-21, `motionsBetween` at :88).
   `Render.Steps.stepPage` takes `[Frame]` (src/Senbazuru/Render/Steps.hs:90-99).
   The language needs to produce frames and captions (`frameTitle`,
   src/Senbazuru/Fold/Types.hs:143; issue #94), not arrow geometry. The "step
   page interpreter" is then *run, project to frames, `stepPage`* — a
   composition, not a second walk over the syntax tree.

6. **`quarter-fold-steps.fold` exercises folding, not authoring.** Checked
   with `jq`: a key frame plus two `file_frames`, each with 9 vertices and 12
   edges, differing only in `edges_foldAngle`. That confirms the owner's #60
   comment, and it means the fixture cannot test references or crease-adding.
   The PRD needs a second acceptance sequence that adds creases.

7. **Error conventions the language must meet, and one place they currently
   use CLI vocabulary.**
   - Errors are values with an `Explain` instance (AGENTS.md:160-171). A
     message is a lower-case sentence fragment meant to follow a colon
     (src/Senbazuru/Explain.hs:62-72).
   - `StepError` carries the frame index. Someone holding a twenty-step file
     should not have to bisect it (Render/Steps.hs:54-61). The CLI takes it
     apart to put the file name in the middle (Steps.hs:70-77).
   - `ImportError` already carries line numbers
     (src/Senbazuru/Import/Segments.hs:148-153). `LoadError` notes that aeson
     returns a message about JSON while the segment readers can name a line
     (src/Senbazuru/Fold/Load.hs:71-75).
   - **Library errors leak CLI words.** `CreaseEnd` exists because the user
     "typed the two ends as separate flags" (src/Senbazuru/Fold/Query.hs:57-64).
     `creaseEndFlag` renders it as `--from`/`--to` (Query.hs:68-71), and
     `Origami.ThroughLayers` puts that into a message
     (src/Senbazuru/Origami/ThroughLayers.hs:195).
   - `FlapError` names `EdgeId`s and `FaceId`s of the *cut* pattern
     (Flap.hs:103-111). A file's author never wrote those ids.

   A sequence layer must therefore translate: a step span, the author's
   reference name, and the file's own spelling of an argument.

8. **Existing text-input decisions worth inheriting.** The CLI's `point`
   reader (app/Senbazuru/Cli.hs:298-310) refuses NaN and Infinity, because
   `reads` accepts them and they reach the geometry silently (Cli.hs:303-306).
   It uses `x,y` so that one end is one value (Cli.hs:287-289). Assignment
   is spelled as a book says it, `--valley` rather than `V`
   (Cli.hs:312-320).

9. **Batching is a performance contract the syntax tree must allow.**
   `creaseAllAlong` exists because re-deriving faces per crease is cubic
   (src/Senbazuru/Fold/Creasing.hs:93-105). Its refusals are decided against
   the frame as it was, so they do not depend on order (Creasing.hs:116-120).
   AGENTS.md:206-212 requires batches. A step must be able to hold several
   creases, interpreted with one call.

10. **Purity boundary and test infrastructure.**
    - `Fold.Load` is the only I/O module (Load.hs:5-9), so a parser should
      take `Text`, not a path.
    - The project already depends on aeson (senbazuru.cabal:153),
      optparse-applicative in the executable only (:170), and QuickCheck 2.14
      (:321), on snapshot `lts-22.44` (stack.yaml:4).
    - Hand-written `Arbitrary` instances already exist
      (test/Senbazuru/Geometry/PolygonSpec.hs:40,46;
      test/Senbazuru/Fold/FacesSpec.hs:98).
    - The golden helper writes `.actual` beside the golden
      (test/Test/Golden.hs:38-60).
    - The shared-extension set is GHC2021 plus four extensions in the cabal
      `common warnings` stanza. Per the GHC user's guide
      (https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/control.html),
      `DataKinds` and `GADTs` are **not** in GHC2021; both arrived in
      GHC2024. A kind-indexed `Ref (k :: RefKind)` therefore needs a cabal
      change, or empty phantom types instead.

### B. Embedding styles

11. **Gibbons & Wu, "Folding Domain-Specific Languages: Deep and Shallow
    Embeddings", ICFP 2014**
    (https://www.cs.ox.ac.uk/jeremy.gibbons/publications/embedding.pdf, read
    pp. 1-8). Their argument, in order:
    - A deep embedding is a data type plus functions that observe it; a
      shallow one defines each construct directly as its meaning (§2).
    - Adding an observer is easy deep and awkward shallow; adding a construct
      is the reverse — the expression problem (§2).
    - A shallow embedding is exactly the algebra of a fold over the deep
      syntax (§4). Several interpretations therefore need tupling (§4.1), and
      an interpretation that depends on another needs tupling too (§4.2).
    - A context-sensitive interpretation needs an accumulating parameter
      (§4.3). A fully parametrised shallow embedding can recover the deep one
      (§4.4), and its type-class form relates to finally tagless (§4.5, §5).
    - A small *core* language can carry an everyday language whose extra
      constructs are translated away (§4.6).

    **Why it matters here:** running a sequence is context-sensitive in the
    extreme. Every step's meaning depends on the paper left by all earlier
    steps. A shallow encoding would therefore be a state-passing function,
    which cannot be printed or saved. §4.6 is the model for macro-moves
    (petal, squash): a core vocabulary plus translations. This is #60's stage
    4 ("each a composition of the above").

12. **Svenningsson & Axelsson, "Combining deep and shallow embedding of
    domain-specific languages", Computer Languages, Systems & Structures 44,
    2015** (https://research.chalmers.se/en/publication/227061). They keep the
    deep part small and put user-facing constructs in shallow functions that
    translate into it. **Caveat for this project:** a construct that exists
    only as a Haskell function cannot be *named in a text file*. So any macro
    the text language offers must be a syntax-tree node, or a closed table
    the parser knows, expanded by a separate pass. A Haskell-only helper is
    fine, but it prints as its expansion.

13. **Tagless final: Carette, Kiselyov & Shan, "Finally Tagless, Partially
    Evaluated"**, J. Functional Programming
    (https://okmij.org/ftp/tagless-final/JFP.pdf, read pp. 1-4). Object terms
    are written as ordinary functions (or class methods) over an abstract
    representation. The host type checker rejects ill-typed terms, and
    evaluators need no tags. Kiselyov's course page
    (https://okmij.org/ftp/tagless-final/course/index.html) says that terms
    arriving from a file must be **typechecked during deserialisation**, by
    building type representations and safe casts. **Cost here:**
    - Programs become `forall repr. Sequence repr => repr ()`.
    - Reading a file means writing a typechecker into that existential.
    - The extensibility it buys (new constructs without touching old
      interpreters) is not this project's axis: the vocabulary grows
      deliberately, one reviewed move at a time (#60 stages 1-4).

14. **Free and operational monads hide the rest of the program inside a
    function.** In `operational` (0.2.4.2 in LTS 22.44, BSD-3-Clause,
    https://hackage.haskell.org/package/operational-0.2.4.2), `view` exposes
    a program as its first instruction plus a continuation *function* to the
    rest
    (https://hackage.haskell.org/package/operational-0.2.4.2/docs/Control-Monad-Operational.html).
    `free` (5.2, BSD-style,
    https://hackage.haskell.org/package/free-5.2/docs/Control-Monad-Free.html)
    has the same shape, `Free (f (Free f a))`, interpreted with `foldFree`.
    Past the first bind that uses a result, a printer or a dry run has to
    invent that result, and a file cannot hold the function. What these
    monads add over an ADT is that later steps can depend on the *results* of
    earlier ones. That is exactly what a saved file cannot express.
    - Build Systems à la Carte (Mokhov, Mitchell & Peyton Jones, ICFP 2018,
      https://www.microsoft.com/en-us/research/uploads/prod/2018/03/build-systems.pdf,
      pp. 79:2-3) makes the same distinction for builds. Make's dependency
      graph is complete before anything runs; an Excel `INDIRECT` cell's
      dependencies appear only while computing.
    - optparse-applicative (0.18.1.0 in LTS, BSD-3-Clause,
      https://hackage.haskell.org/package/optparse-applicative-0.18.1.0)
      deliberately has no `Monad` instance, so the parser can be traversed to
      produce usage text without running it.

### C. Builder ergonomics and prior art

15. **Named parts in diagrams are values looked up later, not variables.**
    `IsName` requires `Typeable`, `Ord` and `Show`. A `Name` is a sequence of
    atomic names, and `(.>)` qualifies one inside another
    (https://hackage.haskell.org/package/diagrams-core-1.5.1.1/docs/Diagrams-Core-Names.html,
    BSD-style). The manual's named-subdiagrams section uses `named` and
    `withName`, for example to draw arrows between named parts
    (https://diagrams.github.io/doc/manual.html). The qualification operator
    is the relevant idea for macros: two expansions of one petal fold must
    not collide on the names they create.

16. **Accumulating a description in do-notation is established practice.**
    - Hakyll's `Rules` monad collects `match`/`route`/`compile` declarations;
      the docs note that rule order does not matter, because nothing runs
      while rules are being defined
      (https://hackage-content.haskell.org/package/hakyll-4.16.6.0/docs/Hakyll-Core-Rules.html).
    - Shake separates `Rules` (declarations) from `Action` (execution, which
      may call `need` after reading a file, so dependencies appear while
      running)
      (https://hackage.haskell.org/package/shake-0.19.8/docs/Development-Shake.html).
    - reanimate (1.1.6.0, public domain,
      https://hackage.haskell.org/package/reanimate) models an animation as a
      duration plus a function from time to SVG. That is a shallow embedding,
      and it suits a library whose programs live only in Haskell.

17. **The label technique: `c <- crease …` can be serialisable.** In a
    `State` builder, a bind hands back a *fresh name* that the builder has
    also written into the syntax tree. The Haskell variable `c` merely holds
    that name. The pretty-printer prints the name, and a file can bind the
    same name, so both front ends produce equal trees. This remains true
    while the builder never exposes **geometry**. Once `c` carries a line's
    length or a flap's faces, a later step can branch on it; the dependency
    becomes dynamic (finding 14) and the program cannot be printed. Two
    things a newcomer gets wrong:
    - `Build` *is* a monad, and that is harmless, because only names flow
      through its binds. Names are known without folding anything.
    - Haskell loops and helpers (`forM_ corners …`) run at build time, so the
      tree records the unrolled steps. Printing gives four steps, not the
      loop. Round-trips hold on the tree, not on Haskell source.

### D. Parsing the text syntax

18. **megaparsec is available, with the error machinery the repo rule
    needs.**
    - LTS 22.44 pins `megaparsec ==9.5.0` and `parser-combinators ==1.3.0`
      (checked in https://www.stackage.org/lts-22.44/cabal.config and
      https://www.stackage.org/lts-22.44/package/megaparsec).
    - Licences: megaparsec BSD-2-Clause; parser-combinators BSD-3-Clause
      (https://www.stackage.org/lts-22.44/package/parser-combinators).
    - Library dependencies: base, bytestring, case-insensitive, containers,
      deepseq, mtl, parser-combinators, scientific, text, transformers
      (https://hackage.haskell.org/package/megaparsec-9.5.0).
    - A `ParseErrorBundle` stores errors as offsets plus the state needed to
      compute line and column. `errorBundlePretty` prints them with source
      context. Custom error payloads go through `ShowErrorComponent` and
      `customFailure`
      (https://hackage-content.haskell.org/package/megaparsec-9.5.0/docs/Text-Megaparsec-Error.html).
    - `registerParseError` records an error without stopping, so one run can
      report several
      (https://hackage-content.haskell.org/package/megaparsec-9.5.0/docs/Text-Megaparsec.html).
    - Indentation-sensitive parsing is supported via `indentBlock`,
      `nonIndented` and `lineFold`, and attoparsec is described as fast with
      poor error messages (https://markkarpov.com/tutorial/megaparsec.html).
    - attoparsec 0.14.4 is already a transitive dependency, because aeson
      2.1.2.1 requires it
      (https://hackage.haskell.org/package/aeson-2.1.2.1).
    - prettyprinter 1.7.1 (BSD-2-Clause) is in the snapshot if a layout
      engine is wanted (https://hackage.haskell.org/package/prettyprinter-1.7.1).

19. **JSON or YAML via aeson would add no parser, but loses line numbers for
    exactly the errors that matter.** aeson reports a failure location as a
    JSON path such as `$.steps[3]`. Its documentation mentions no line or
    column
    (https://hackage.haskell.org/package/aeson-2.1.2.1/docs/Data-Aeson-Types.html).
    The study reads `cases.json` with `eitherDecode` and passes the message
    straight to `die` (study/fold-material/Main.hs:94). `yaml` 0.11.11.2
    gives line and column for *syntax* errors, but `FromJSON` failures come
    back as aeson errors with a path
    (https://hackage.haskell.org/package/yaml-0.11.11.2/docs/Data-Yaml.html).
    The errors that matter most here — "`c3` is not defined", "step 14's line
    misses the paper" — are found *after* decoding. With aeson they can name
    a path but not a line. With megaparsec the tree keeps its spans, so they
    can.

20. **Syntax shapes.** `.cp` is already one crease per line
    (src/Senbazuru/Import/Cp.hs:5), and its reader reports line numbers.
    - A line-oriented command language matches that precedent and the way a
      book lists its steps.
    - S-expressions are the cheapest to parse, but look unfamiliar to folders.
    - Indentation-sensitive syntax is supported by megaparsec, but its errors
      are about whitespace, which is hard to explain.

    Doodle, the older origami diagram language (docs/related-projects.md:38),
    is listed as one of #97's three shapes; details are under Unverified. The
    technique recommended here is independent of this choice: the syntax tree
    is the contract, and #97 owns the concrete syntax.

### E. Round-trips

21. **A round-trip only tests what the tree kept.**
    docs/notes/round-trips.md:17-40 shows that a decode/encode property
    passes trivially when the decoder has already dropped the interesting
    part. For this language, that means:
    - `parse (pretty s) == Right s` says nothing about comments, captions or
      spans the tree does not hold. Compare trees with spans stripped. Do not
      claim `pretty . parse` is the identity on *text* unless the tree keeps
      comments and layout.
    - Numbers are the trap. `Explain.hs:93-96` notes that user-typed
      coordinates print shortest-round-trip, so `0.01` reads back as `0.01`.
      A generator of arbitrary `Double`s makes the property depend on
      `show`/`read`. NaN also makes `==` fail spuriously, and the parser must
      refuse it anyway (finding 8).
    - Authored fractions as `Rational` (`1/3`) round-trip exactly and are
      what a person can write without a calculator.
    - Complement the property with goldens of printed schemes, the quarter
      fold and bird base, and goldens of *error output* for representative
      mistakes. Per the owner's rule on tests that cannot fail, name for each
      test the change that would turn it red. A printer that drops captions
      should fail the property, which requires the generator to produce
      captions.

### F. Static versus dynamic checking

22. **What can be checked before any geometry, by one pass shared by both
    front ends:**
    - every name is defined before use, and defined once;
    - each reference's kind (point, line, flap) matches its slot;
    - macro arity;
    - numbers are finite, and fractions lie in [0, 1].

    Haskell's types can repeat the kind check for builder users, via a
    phantom `Ref k` (docs/notes/phantom-units.md:11-17 shows the pattern and
    asks at 24-28 whether the cost is worth it). The parser, though, produces
    untyped names. Turning them into `Ref 'LineRef` at the type level needs
    an existential plus a runtime kind test — Kiselyov's
    typecheck-on-deserialisation (finding 13) — which repeats the untyped
    pass. So the untyped pass is the source of truth, and the phantom index
    is optional.

23. **What only running can decide** (these are existing library refusals):
    - A crease end must meet an edge or corner the drawing already has, not
      merely lie "on the paper" (Creasing.hs:38-55; `CreaseEndMeetsNothing`,
      Query.hs:173, explained by coordinates at Query.hs:312-318).
    - A flap must be a complete cut; an incomplete one is refused
      (Flap.hs:1-6).
    - The turn must be collision-free over its interval (`FlapCollision`,
      `FlapUnresolved`, Flap.hs:118-119).
    - A material-point reference must land strictly inside exactly one face
      (StudyCase.hs:139-143).
    - The refolded join must agree with the accepted endpoint
      (BlintzSequence.hs:69-70).
    - Sign conventions depend on the current fold: a stationary face on an
      upside-down layer needs the opposite FOLD-angle sign for the same
      physical rotation (Flap.hs:14-17).

    A "dry run" is therefore either the static pass (cheap, no promise of
    foldability) or the full geometric run. Nothing sits between them.

## Implications for the design

### Recommended design (one)

- **Syntax tree `Scheme`**: first-order, `Eq`/`Show`, no functions inside. It
  is a list of located steps, each carrying a source span (`NoSpan` for
  Haskell-built steps) and an optional caption that becomes `frame_title`.
- **References are data.**
  - Sheet landmarks: corners of the original sheet, a `Rational` fraction
    along a named line, the meeting point of two named lines.
  - Lines built from points, the natural home for Huzita–Hatori-style
    constructors (docs/notes/huzita-hatori.md:3-5, 21-25).
  - Flaps named by a material point plus a hinge, inheriting `PanelTag`'s
    anchoring (finding 3).
  - `Define name expr` nodes bind names.
  - Never raw `EdgeId`/`FaceId` in the language.
- **Core plus macros** (Gibbons & Wu §4.6): a small core (crease batch, turn
  a flap about a line, turn over), and macro nodes from a closed table
  expanded by an `elaborate` pass. The printer prints the macro, not its
  expansion.
- **Builder** `Build a`: a `State` over (fresh-name counter, steps so far).
  `define*` functions return `Ref`s; step functions return `()`. It never
  sees a `Frame`. Finish with `scheme :: Build () -> Scheme`.
- **Interpreters as functions:**
  - `checkScheme` — static, finding 22;
  - `runScheme` — geometric; threads (material pattern, `Folded`, anchor) as
    the recipes do (finding 2); returns one result per step holding the
    checked motion and end surface;
  - `stepFrames` — projects results to `[Frame]` for `stepPage`;
  - `prettyScheme` — to text;
  - the material study consumes the per-step `Surface V2` values, which
    `Origami.Surface` already shares (docs/architecture.md:115).
- **Parser**: megaparsec, `FilePath -> Text -> Either … Scheme`, pure. File
  reading stays at the I/O boundary (finding 10).
- **Errors**: `SchemeError` with an `Explain` instance. Every run-time
  refusal wraps the library error with the step index, span and the author's
  reference name.
  - Do not surface `--from` (finding 7). `CreaseEnd` needs a spelling that
    fits a file.
  - Expect a clash of formats: `errorBundlePretty` gives a multi-line caret
    excerpt, while `Explain` promises a one-line fragment (Explain.hs:62-68).
    Plan a one-line `explain` plus a separate excerpt function.
- **Batching**: a step's crease list maps to one `creaseAllAlong` or
  through-layers call (finding 9).
- **Tests**: the `parse . pretty` property with a generator covering every
  constructor (captions and macros included), `Rational` numbers and no NaN;
  goldens of pretty output and of error messages; and a crease-adding
  acceptance sequence in addition to `quarter-fold-steps.fold` (finding 6).

### Rejected alternatives

- **Shallow embedding** (a sequence *is* a state-passing function): cannot
  print, save, statically check or dry-run. Each new interpretation must be
  tupled in (finding 11).
- **Free or operational monad**: the continuation is a function, so a file
  cannot hold it and a printer cannot see past a bind. Its extra power —
  steps that depend on results — is what must be forbidden (finding 14).
  #60 already rejected it.
- **Tagless final**: reading a file needs a typechecker into an existential;
  readers face higher-kinded class constraints; its extensibility is on the
  wrong axis (finding 13).
- **GADT-indexed syntax tree** (`Step k`, `Expr a`): the parser would have to
  typecheck into it. Kind-index only the builder's `Ref`, if anything.
- **JSON or YAML as the authoring syntax**: semantic errors cannot name a
  line (finding 19), and per-edge arrays need a calculator (finding 4). JSON
  may still be worth offering later as a *machine* encoding of the same
  tree, as `cases.json` is for the study.
- **References by id** (as the study recipes do): ids change under cutting
  (finding 3).

### Types-only sketch (SKETCH — placeholder names, no implementation)

```haskell
-- SKETCH: illustrates the shape only. Needs DataKinds for Ref's index,
-- or replace RefKind's promoted constructors with empty phantom types.
data Span = Span !FilePath !Int !Int !Int !Int | NoSpan      -- file, line/col from, to
data Located a = Located {locSpan :: !Span, locValue :: !a}
newtype Name = Name Text deriving stock (Eq, Ord, Show)
data RefKind = PointRef | LineRef | FlapRef deriving stock (Eq, Show)

data Corner = BottomLeft | BottomRight | TopRight | TopLeft
data Sense = Valley | Mountain                               -- book words, not M/V

data PointExpr                                               -- all on the unfolded sheet
  = CornerOf Corner
  | Along Name Rational                                      -- 1/2 = midpoint of a named line
  | Meet Name Name                                           -- where two named lines cross
  | PointRef' Name
data LineExpr
  = Through PointExpr PointExpr                              -- the line through two points
  | Onto PointExpr PointExpr                                 -- the fold that lays one on the other
  | LineRef' Name
data FlapExpr = FlapAt Rational Rational | FlapRef' Name      -- material point inside

data Def = DefPoint PointExpr | DefLine LineExpr | DefFlap FlapExpr
data Step
  = Define Name Def                                          -- binds; moves no paper
  | CreaseAll [(LineExpr, Sense)]                            -- one batch, one re-trace
  | TurnFlap FlapExpr LineExpr Sense Rational                -- degrees
  | TurnOver
  | Macro Name [Arg]                                         -- closed table; elaborated
data Arg = ArgPoint PointExpr | ArgLine LineExpr | ArgFlap FlapExpr | ArgNumber Rational
data Scheme = Scheme {schemeSteps :: ![Located (Maybe Text, Step)]}  -- caption, step

data SchemeError
  = Unbound !Span !Name
  | Redefined !Span !Name
  | WrongKind !Span !Name !RefKind !RefKind                  -- wanted, found
  | StepRefused !Span !Int !StepFailure                      -- step index, library reason
data StepFailure = CreaseFailed FoldError | FlapFailed FlapError | JoinMoved
instance Explain SchemeError

-- Front ends: both produce Scheme
parseScheme  :: FilePath -> Text -> Either (ParseErrorBundle Text Void) Scheme
prettyScheme :: Scheme -> Text
newtype Build a = Build (State BuildState a)                 -- Functor, Applicative, Monad
newtype Ref (k :: RefKind) = Ref Name                        -- holds a name, never geometry
defineLine :: LineExpr -> Build (Ref 'LineRef)
creaseAll  :: [(LineExpr, Sense)] -> Build ()
scheme     :: Build () -> Scheme

-- Interpreters: ordinary functions
checkScheme :: Scheme -> Either SchemeError Checked          -- no geometry
runScheme   :: Frame -> Checked -> Either SchemeError [StepResult]
data StepResult = StepResult {resultMotion :: CheckedFlap, resultEnd :: Surface V2}
stepFrames  :: [StepResult] -> [Frame]                        -- feeds Render.Steps.stepPage
```

(`StepResult` is simplified: a crease-only step has no `CheckedFlap`, so the
real type needs a sum. The sketch keeps the shape visible.)

## Open questions

1. **Sheet space or folded space?** A line "drawn on the folded model"
   (`creaseThroughLayers`) and a line drawn on the sheet (`creaseAlong`) are
   different operations (architecture.md; Creasing.hs:84-89). Every point
   and line expression must say which space it lives in. This probably needs
   a step-level form rather than a flag.
2. **Where does the parser live?** In the library, megaparsec and
   parser-combinators (plus case-insensitive) become dependencies for every
   library user. In the executable, library users cannot read scheme files.
   A separate internal library is a third option.
3. **Should comments and layout survive** `parse` then `pretty`? If so, the
   tree must carry trivia, or a separate concrete syntax tree is needed.
4. **Macros in text**: can a file *define* one? That brings parameters, and
   so variable binding, into the language. The recommendation assumes a
   closed table in v1.
5. **Who turns book "valley" into a FOLD sign** when layers are upside down
   (Flap.hs:14-17)? Presumably the run, per step, but the PRD should say so.
6. **Intermediate poses**: are they part of the language or renderer policy?
   HelmetSequence.hs:70-84 shows a camera-driven choice of 120° instead of
   90°.
7. Does a flap named by one material point plus a hinge always identify the
   intended flap? A flap may span several faces and layers
   (docs/glossary.md:29), and `Flap` defines it as what is reached after
   removing the hinge creases (Flap.hs:1-3). This suggests yes, but it
   should be tested on the bird base.
8. Should the builder's `Ref` be kind-indexed (adds `DataKinds`), use empty
   phantom types, or not be indexed at all? The note on phantom units poses
   the same "whether" question.

## Unverified

- **Doodle's syntax and licence.** The WebFetch summary of
  https://doodle.sourceforge.net/ described backslash-prefixed commands,
  step blocks and named vertex assignments, with no licence shown. I did not
  read the raw page or an example file. docs/related-projects.md:38 also
  says "not checked" for its licence.
- **JSON has no comment syntax.** Believed, not fetched (RFC 8259 was not
  opened). It bears on JSON as authoring syntax.
- **`withName` when the name is absent** (diagrams): not checked.
- **Parsec's status in LTS 22.44**: it did not appear in my grep of the
  snapshot constraints, possibly because it is a GHC boot package. Not
  checked.
- **Shake's classification in Build Systems à la Carte.** I read pp. 79:1-3,
  which classify Make as static and Excel as dynamic. That Shake is monadic
  came from the tool's summary of the same PDF; Shake's own docs (finding 16)
  independently show `need` called after reading a file.
- **reanimate's combinator names** and whether its scenes are data: the
  fetched summary did not show them.
- **Whether yaml bundles libyaml's C sources**: the docs reference
  `Text.Libyaml`; bundling not checked.
- **Whether case-insensitive** (a megaparsec dependency) is already in
  senbazuru's transitive closure: not checked without running Stack.
- **Learn2Fold's and OrigamiBench's action spaces** (#96) were not read.
  They may argue for particular reference constructors; that is another
  slice.
