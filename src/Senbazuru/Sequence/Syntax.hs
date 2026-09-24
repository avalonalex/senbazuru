-- |
-- Module      : Senbazuru.Sequence.Syntax
-- Description : A fold sequence as a plain value: what both ways of writing one produce.
--
-- A /fold sequence/ is the list of instructions that takes a sheet of paper to
-- a model: \"fold the south-east corner to the centre\", \"turn the paper
-- over\". An instruction book draws one picture per instruction, and the two
-- words this module uses come from there. A __step__ is the instruction for
-- one picture. A __move__ is one thing done to the paper, and a step holds one
-- or more of them, because \"fold and unfold both diagonals\" is one picture
-- of two moves.
--
-- There are two ways to write a sequence down: as Haskell, in a @do@ block,
-- and as text in a file. Both produce the 'Sequence' defined here, and
-- everything that reads a sequence — the checker, the runner, the printer —
-- reads this value and never asks which way it was written. That is the whole
-- reason the module exists apart from either front end: the type both of them
-- import cannot live in one of them.
--
-- == Why there is not a single function in it
--
-- 'Sequence' derives 'Eq' and 'Show' and holds no functions, and that is a
-- decision with a cost, not a default. The obvious Haskell encoding of \"a
-- program of moves\" is a monad whose binds hand back results, so that a later
-- step can depend on what an earlier one measured. A file cannot hold that:
-- text has no way to say \"the rest of the program, given the length I just
-- computed\". A value with a function inside also cannot be compared, printed
-- or checked without being run.
--
-- Keeping the tree first-order buys exactly those things. Two sequences are
-- compared with @==@, which is how a test says that a sequence written in
-- Haskell and the same one written as text are the same sequence. A sequence
-- can be printed as text that parses back. And it can be refused for naming a
-- step that does not exist without folding any paper. The Haskell builder
-- still has loops and helper functions; they run while the value is being
-- built, and the value records what they produced.
--
-- == Paper is named by where it lay on the flat sheet
--
-- Nothing in this tree is a vertex, edge or face id. Ids are array positions
-- in a FOLD file, and adding one crease re-traces the faces and renumbers
-- them, so an id written at step 1 means something else by step 3. A 'Point'
-- or a 'Line' instead names paper by its position on the /unfolded/ sheet,
-- which never gains or loses paper however it is folded.
--
-- The names are compass words, fixed on the sheet as the file draws it: north
-- is up the page, @corner south-west@ is the sheet's bottom-left corner, and
-- it is still called that after the model is turned over and the corner is at
-- the reader's top right. Words for what the reader /sees/ — left, right, top,
-- bottom — are deliberately not used for paper, because they would have to be
-- relearnt after every move.
--
-- == The names that look like stuttering
--
-- 'ValleyFold', 'MountainFold' and 'LayerAbove' would read better as @Valley@,
-- @Mountain@ and @Above@. Those constructors already exist in
-- "Senbazuru.Fold.Types", where they say how a /file/ labels a crease and
-- orders two faces. The runner has to import both modules, and GHC does not
-- choose a constructor by the type expected, so the shorter names would force
-- a qualified import on the library's own code at every use. The clash is
-- removed here, once, rather than at every importer.
--
-- The two vocabularies are also not the same idea, which is the better reason.
-- A 'Sense' is read from the /reader's side/: a valley fold brings paper
-- towards whoever is looking at the model. A file's assignment is read from
-- the paper's own top face. After the model is turned over the two disagree,
-- and one @fold valley@ can correctly write a file's valley on one crease and
-- its mountain on another.
--
-- == What is deliberately missing
--
-- The design for this language gives a step an optional @settle { … }@ block
-- and the header an optional @material { … }@ block, both for the material
-- study, which bends the paper of one step as an elastic sheet. Neither has a
-- field here yet. Their types are the interface between this language and the
-- study, that interface is to be agreed when the study starts consuming
-- sequences, and a type sketched here ahead of that would be a second,
-- competing definition. Until then the text parser refuses both blocks as not
-- yet supported, so no tree needs a place to keep one.
--
-- == Two normal forms
--
-- 'stripSpans' and 'canonical' exist so that values written in different ways
-- can be compared. A parsed tree remembers where in the file each piece came
-- from and a built one has nowhere to remember; 'stripSpans' forgets the
-- positions. 'canonical' handles the one place where two different trees
-- print as the same text; its own comment has the example.
--
-- The design this implements, with the alternatives it rejected, is recorded
-- in @PRDs\/decisions.md@ (D1, D2 and D12) in the repository.
module Senbazuru.Sequence.Syntax
  ( -- * The sequence
    Sequence (..),
    Header (..),
    SheetSource (..),
    Side (..),
    Start (..),
    Step (..),

    -- * Moves
    Move (..),
    Sense (..),
    Amount (..),
    Layers (..),
    PageAxis (..),
    Turning (..),
    Binding (..),
    MacroCall (..),
    PetalTip (..),
    Isometry (..),
    StackingSpec (..),
    Relation (..),
    RefusalKind (..),

    -- * Naming paper
    Point (..),
    Line (..),
    Corner (..),
    Compass (..),
    Name (..),

    -- * Where in a source something was written
    Span (..),
    Located (..),

    -- * Normal forms, for comparing
    stripSpans,
    canonical,

    -- * The files a sequence names
    SourceFile (..),
    sourceFiles,

    -- * How a number is spelled
    exactNumber,
  )
where

import Data.Ratio (denominator, numerator)
import Data.String (IsString)
import Data.Text (Text)
import Data.Text qualified as T
import System.FilePath (replaceFileName)

-- | Where in a sequence source a piece of the tree was written: the file, then
-- the line and column it starts at, then the line and column it ends at. Lines
-- and columns count from 1, and a column counts characters, not bytes.
--
-- The end is the column just /after/ the last character, so the word @left@
-- starting at column 20 runs from 20 to 24, and its length is the difference.
--
-- 'NoSpan' is what every value built in Haskell carries, since it was never
-- text. It is a constructor rather than a @Maybe Span@ at each use so that the
-- tree has one shape whichever front end made it.
data Span
  = Span !FilePath !Int !Int !Int !Int
  | NoSpan
  deriving stock (Eq, Show)

-- | A piece of the tree together with where it was written.
--
-- Only the pieces a run can /refuse/ are wrapped: a step, a move, and the
-- header lines that can turn out wrong once paper is involved. A refusal
-- points a caret at the span, so a piece that cannot be refused has no use for
-- one.
--
-- 'Eq' compares the span too. Two trees that differ only in position are
-- different values until 'stripSpans' has been applied to both.
data Located a = Located
  { locSpan :: !Span,
    locValue :: !a
  }
  deriving stock (Eq, Show, Functor)

-- | A name an author gave to a step, a marked point or a line, so that a later
-- move can refer to it: @unfold c1@.
--
-- 'IsString' lets a Haskell author write @"c1"@ under @OverloadedStrings@. It
-- also means a 'Name' can hold text no source could spell, such as
-- @"two words"@ or a reserved word. Nothing here refuses that; the checker
-- does, in the same place and words as it refuses a bad name in text.
newtype Name = Name Text
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | The name of a way a move can be refused, as written after
-- @expect refused@: @ExistingHingeFlat@.
--
-- It is text and not a sum type because the refusals it can name are
-- constructors of many error types: the folding code's, the layer solver's
-- and the sequence language's own. A sum type here would have to import them
-- all, and this module imports nothing from the project, so that every other
-- part of the language can import it. The checker refuses a kind that names
-- no refusal.
newtype RefusalKind = RefusalKind Text
  deriving stock (Eq, Ord, Show)

-- | A side of the unfolded sheet's bounding box. North is increasing @y@ on
-- the sheet as the file draws it, and stays north however the model is turned.
data Compass = North | East | South | West
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | A corner of the unfolded sheet's bounding box, by the same compass.
data Corner = SouthWest | SouthEast | NorthEast | NorthWest
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Which way a fold sends the paper, as the /reader/ sees it: a valley fold
-- brings the moving paper towards the reader, a mountain fold sends it away
-- behind. The module header says why these are not called @Valley@ and
-- @Mountain@.
data Sense = ValleyFold | MountainFold
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The line on the page a model is turned over about. 'LeftRight' swaps the
-- reader's left and right, like turning the page of a book; 'TopBottom' swaps
-- top and bottom.
data PageAxis = LeftRight | TopBottom
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Which way round the model is spun on the page.
data Turning = Clockwise | Anticlockwise
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Which side of the sheet faces the reader at the start. Origami paper is
-- usually coloured on one side and white on the other.
data Side = ColouredUp | WhiteUp
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | A point of the paper, named on the unfolded sheet.
--
-- Coordinates are in /sheet lengths/: the south-west corner of the sheet's
-- bounding box is @(0, 0)@ and the box's longer side is 1, with one scale on
-- both axes. So @(1\/2, 1\/2)@ is the centre of any square sheet, whatever
-- units its file happens to use. They are 'Rational' because an author writes
-- @1\/3@ and means a third; the conversion to 'Double' happens once, where the
-- point is resolved against real paper.
--
-- Every form except 'Meet' is worked out on the flat sheet. The midpoint of
-- two corners is the same paper after those corners have been folded onto one
-- spot, which is the point of naming paper this way.
data Point
  = -- | @corner south-east@
    CornerOf Corner
  | -- | @centre@, of the sheet's bounding box
    Centre
  | -- | @(u, v)@, in sheet lengths
    AtSheet Rational Rational
  | -- | @midpoint of [P, Q]@
    MidpointOf Point Point
  | -- | @midpoint of edge north@. Separate from 'MidpointOf' because an edge is
    -- not two points. There is no @fraction r along edge north@: nothing would
    -- say which end @r@ counts from.
    MidpointOfEdge Compass
  | -- | @fraction r along [P, Q]@: the point @r@ of the way from P to Q
    FractionAlong Rational Point Point
  | -- | @meet L1 L2@: where two lines cross. The one form measured where the
    -- paper is /now/, since two lines can cross only once they have positions.
    Meet Line Line
  | -- | @end of crease of NAME nearest P@: the end, nearest P, of a crease the
    -- named step made
    EndOfCreaseOf Name Point
  | -- | A name given by @mark@ or @let@
    PointNamed Name
  deriving stock (Eq, Show)

-- | A line on the paper: usually the line to fold along.
--
-- The middle group is the /Huzita–Hatori operations/, the standard list of
-- ways one straight fold can be pinned down by what it brings together. An
-- author rarely knows a fold line's coordinates; they know \"this corner goes
-- to that one\". Several of the operations can have more than one answer, and
-- the optional last 'Point' picks the answer nearest to it.
data Line
  = -- | @edge west@: a side of the sheet
    EdgeOf Compass
  | -- | @[P, Q]@: the line through two points (operation 1)
    Segment Point Point
  | -- | @P to Q@: the fold that lays P onto Q (operation 2)
    Onto Point Point
  | -- | @L1 to L2@: the fold that lays one line onto another (operation 3)
    LineOnto Line Line (Maybe Point)
  | -- | @perpendicular to L through P@ (operation 4)
    PerpendicularThrough Line Point
  | -- | @P to L through Q@: lays P onto L with the fold passing through Q
    -- (operation 5)
    PointToLineThrough Point Line Point (Maybe Point)
  | -- | @P to L1 and Q to L2@: lays two points onto two lines at once
    -- (operation 6)
    TwoToTwo Point Line Point Line (Maybe Point)
  | -- | @P to L1 perpendicular to L2@ (operation 7)
    PointToLinePerpendicular Point Line Line
  | -- | @P to L@: lays P onto L with the fold parallel to L, which is \"fold
    -- the corner to the crease\". Not one of the seven, and common in books.
    PointToLine Point Line
  | -- | @crease [P, Q]@: along creases that already run from P to Q
    ExistingCrease Point Point
  | -- | @hinge of NAME@: the line the named step turned paper about
    HingeOf Name
  | -- | @crease of NAME@: the creases the named step made
    CreaseOf Name
  | -- | @model [(x1, y1), (x2, y2)]@: between two points in the /current
    -- model's/ coordinates, as seen. The escape hatch, and the one form that
    -- is not a name on the sheet.
    ModelSegment (Rational, Rational) (Rational, Rational)
  | -- | A name given by @let@
    LineNamed Name
  deriving stock (Eq, Show)

-- | Which of the layers lying under a fold line are folded.
data Layers
  = -- | No layers clause. The fold moves the /flap/ containing the first
    -- thing its line names, which may be a point or a line: for
    -- @corner south-east to centre@, the paper still joined to that corner
    -- once the model is cut along the fold line, and for
    -- @edge west to edge east@ the paper still joined to the west edge.
    FlapOfFirstArgument
  | -- | @all layers@
    AllLayers
  | -- | @top N layers@, counted from the reader's side. @top layer@ is
    -- @TopLayers 1@. The type allows a count below 1, which no source can
    -- spell; the checker refuses it, as it does an out-of-range 'Rotate' or
    -- 'TurnedQuarters'.
    TopLayers Int
  | -- | @top flap@
    TopFlap
  deriving stock (Eq, Show)

-- | How far a fold turns the paper.
--
-- 'ToFlat' is not @'Degrees' 180@, although it turns the paper through 180°.
-- A fold written with no angle parses to 'ToFlat' and prints with no angle; a
-- fold written @180°@ keeps its angle. One constructor for both would make
-- printing a sequence change its text.
data Amount = ToFlat | Degrees Rational
  deriving stock (Eq, Show)

-- | @layers A above B@: where the paper at A and the paper at B overlap, A's
-- is nearer the reader. A folded model often has several valid layer orders,
-- and relations like this one say which is meant.
data Relation = LayerAbove Point Point
  deriving stock (Eq, Show)

-- | How one layer order is chosen among several: by stated relations, or
-- @stacking first@ for whichever the solver finds first. A sum and not a list
-- with a flag, so that no value can ask for both.
data StackingSpec = Relations [Relation] | StackingFirst
  deriving stock (Eq, Show)

-- | The right-hand side of a @let@.
data Binding = BindPoint Point | BindLine Line
  deriving stock (Eq, Show)

-- | A /macro-move/: a named move that turns several creases together at tied
-- rates, as one straight fold cannot. Each runs until its driving crease
-- reaches the given angle, in degrees.
data MacroCall
  = -- | @collapse at P [keeping [Q1, Q2] flat] until A°@
    Collapse Point (Maybe (Point, Point)) Rational
  | -- | @rabbit-ear at P until A°@
    RabbitEar Point Rational
  | -- | @petal tip P until A°@, or @petal top flap until A°@
    Petal PetalTip Rational
  deriving stock (Eq, Show)

-- | Which flap a petal fold lifts: the one whose tip is named, or the top one.
data PetalTip = TipAt Point | TopFlapTip
  deriving stock (Eq, Show)

-- | How a repeated stretch of steps is carried to another part of the sheet:
-- mirrored across the line through two points, or turned about a point by a
-- number of quarter turns.
data Isometry = MirroredAcross Point Point | TurnedQuarters Int Point
  deriving stock (Eq, Show)

-- | One thing done to the paper, or to how it is shown.
data Move
  = -- | @fold SENSE [A°] LINE [LAYERS] [moving P]@. The last field is the
    -- optional /seed/: a point on the paper that moves, for a line that does
    -- not itself say which side that is.
    Fold Sense Amount Line Layers (Maybe Point)
  | -- | @pre-crease SENSE LINE [LAYERS] [moving P]@, also written
    -- @precrease@ or @fold and unfold@: fold along the line and lay the paper
    -- flat again, one move whose lasting change is the crease it leaves (owner
    -- decision 14). It has no 'Amount' because it has nowhere to stop part-way.
    FoldAndUnfold Sense Line Layers (Maybe Point)
  | -- | @unfold c1 c2@: undo the named steps
    Unfold [Name]
  | -- | @turn over left-right@. Moves no paper; the reader sees the other side.
    TurnOver PageAxis
  | -- | @rotate k\/8 turn clockwise@: spin the model on the page by @k@
    -- eighths of a turn. Eighths because a book's diamond view is one eighth
    -- from its square view. The 'Int' is @k@ as written, so @2\/8@ stays 2.
    Rotate Int Turning
  | -- | @anchor P@: from here on, the paper at P is what stays still
    Anchor Point
  | -- | @mark A = P [in face containing S]@: name a point of the paper. The
    -- optional point picks one layer where P lies on several.
    Mark Name Point (Maybe Point)
  | -- | @let N = …@: shorthand, expanded wherever the name is used
    Let Name Binding
  | -- | A macro-move, with the angles at which to draw an in-between pose
    Macro MacroCall [Rational]
  | -- | @continue NAME until A°@: carry the named step's macro-move further
    Continue Name Rational
  | -- | @together { … }@: moves made at the same time. Each member has its own
    -- span so that a refusal points at its line, not at the whole block.
    Together [Located Move]
  | -- | @pose { crease [P, Q] at A°; … }@: set creases to stated angles, each
    -- crease named by its two ends. The one move whose angles are signed.
    Pose [(Point, Point, Rational)]
  | -- | @repeat N[..M] [mirrored across [P, Q] | turned k\/4 about P]@: do the
    -- named step, or the steps from N to M, again
    Repeat Name (Maybe Name) (Maybe Isometry)
  | -- | @checkpoint \"path\" { … }@: compare the model so far with a file
    Checkpoint FilePath StackingSpec
  | -- | @not modelled \"inside reverse fold\"@: the author says a move happens
    -- here that the language cannot express, and a run stops at it
    NotModelled Text
  | -- | @expect refused KIND { move }@: a move the author expects to be
    -- refused, written so that a test of the language can live in a sequence
    ExpectRefused RefusalKind Move
  deriving stock (Eq, Show)

-- | One picture's worth of instruction. Both the name and the caption are
-- optional in text, so both are 'Maybe'; a caption of @Just ""@ is a different
-- step from one with no caption.
data Step = Step
  { stepName :: Maybe Name,
    stepCaption :: Maybe Text,
    stepMoves :: [Located Move]
  }
  deriving stock (Eq, Show)

-- | How the paper starts: with every crease flat, or folded as the sheet's
-- file says, with its layer order chosen as given.
data Start = StartFlat | StartFolded StackingSpec
  deriving stock (Eq, Show)

-- | Where the starting paper comes from. A path is kept exactly as written;
-- 'sourceFiles' says which file that means.
data SheetSource = UnitSquare | SheetFile FilePath
  deriving stock (Eq, Show)

-- | Everything a sequence says before its first step.
--
-- 'hAnchor' is the /anchor/: the point whose paper stays still while folds
-- move the rest, so that a model does not wander across the page from one
-- picture to the next.
--
-- 'hClosing' looks misplaced and is not. It is the caption under the /last/
-- picture, and text writes it after the last step, in the order a page draws
-- it. It is kept here because it belongs to the sequence and not to any step.
data Header = Header
  { hTitle :: Maybe Text,
    hSheet :: Located SheetSource,
    hAnchor :: Maybe (Located Point),
    hSide :: Side,
    hStart :: Located Start,
    hClosing :: Maybe Text
  }
  deriving stock (Eq, Show)

-- | A whole fold sequence.
data Sequence = Sequence
  { seqHeader :: Header,
    seqSteps :: [Located Step]
  }
  deriving stock (Eq, Show)

-- | Forget where everything was written.
--
-- A parsed sequence and the same sequence built in Haskell differ in every
-- span and nothing else, so a comparison between them goes through this.
stripSpans :: Sequence -> Sequence
stripSpans (Sequence header steps) =
  Sequence
    header
      { hSheet = unlocated (hSheet header),
        hAnchor = unlocated <$> hAnchor header,
        hStart = unlocated (hStart header)
      }
    (map (unlocated . fmap stripStep) steps)
  where
    stripStep step = step {stepMoves = map stripLocatedMove (stepMoves step)}
    stripLocatedMove = unlocated . fmap stripMove

    -- Only two moves hold another move, so only they can hide a span. The
    -- rest are listed one by one, with no catch-all, on purpose: a move added
    -- later then stops this compiling until somebody has decided whether it
    -- holds a span, where a catch-all would quietly leave its spans in.
    stripMove = \case
      Together members -> Together (map stripLocatedMove members)
      ExpectRefused kind inner -> ExpectRefused kind (stripMove inner)
      move@Fold {} -> move
      move@FoldAndUnfold {} -> move
      move@Unfold {} -> move
      move@TurnOver {} -> move
      move@Rotate {} -> move
      move@Anchor {} -> move
      move@Mark {} -> move
      move@Let {} -> move
      move@Macro {} -> move
      move@Continue {} -> move
      move@Pose {} -> move
      move@Repeat {} -> move
      move@Checkpoint {} -> move
      move@NotModelled {} -> move

unlocated :: Located a -> Located a
unlocated located = located {locSpan = NoSpan}

-- | Rewrite a sequence to the tree the text parser would give for it.
--
-- Nearly every spelling has one tree. The exception is a bare name beside
-- @to@:
--
-- > let a = corner south-west
-- > let b = edge north
-- > fold valley a to b
--
-- Reading @a to b@, the parser cannot know whether @b@ names a point or a
-- line: that depends on a @let@ it has not been asked to understand. So it
-- always reads such a name as a point, giving
-- @'Onto' ('PointNamed' a) ('PointNamed' b)@, and leaves it to the checker to
-- notice that @b@ is a line. A Haskell author who knows @b@ is a line can
-- build @'PointToLine' ('PointNamed' a) ('LineNamed' b)@ instead, which prints
-- as the same text. Four shapes have this problem, and this function rewrites
-- each to what the parser produces:
--
-- > PointToLine p (LineNamed b)                  ~>  Onto p (PointNamed b)
-- > LineOnto (LineNamed a) (LineNamed b) Nothing ~>  Onto (PointNamed a) (PointNamed b)
-- > LineOnto (LineNamed a) l Nothing             ~>  PointToLine (PointNamed a) l
-- > Let n (BindLine (LineNamed b))               ~>  Let n (BindPoint (PointNamed b))
--
-- A 'LineOnto' with a @nearest@ point is left alone: that word can only end
-- the line-to-line form, so the text has already said both names are lines.
--
-- So \"printing then parsing gives the sequence back\" is true of
-- @canonical s@, not of @s@. Applying it twice changes nothing more, and both
-- front ends produce values it leaves alone.
canonical :: Sequence -> Sequence
canonical (Sequence header steps) =
  Sequence
    header
      { hAnchor = fmap canonicalPoint <$> hAnchor header,
        hStart = canonicalStart <$> hStart header
      }
    (map (fmap canonicalStep) steps)
  where
    canonicalStep step = step {stepMoves = map (fmap canonicalMove) (stepMoves step)}
    canonicalStart = \case
      StartFlat -> StartFlat
      StartFolded spec -> StartFolded (canonicalSpec spec)

canonicalMove :: Move -> Move
canonicalMove = \case
  Fold sense amount line layers seed ->
    Fold sense amount (canonicalLine line) layers (canonicalPoint <$> seed)
  FoldAndUnfold sense line layers seed ->
    FoldAndUnfold sense (canonicalLine line) layers (canonicalPoint <$> seed)
  Unfold names -> Unfold names
  TurnOver axis -> TurnOver axis
  Rotate eighths turning -> Rotate eighths turning
  Anchor p -> Anchor (canonicalPoint p)
  Mark name p face -> Mark name (canonicalPoint p) (canonicalPoint <$> face)
  Let name binding -> Let name (canonicalBinding binding)
  Macro call samples -> Macro (canonicalMacro call) samples
  Continue name angle -> Continue name angle
  Together members -> Together (map (fmap canonicalMove) members)
  Pose creases -> Pose [(canonicalPoint p, canonicalPoint q, angle) | (p, q, angle) <- creases]
  Repeat from to isometry -> Repeat from to (canonicalIsometry <$> isometry)
  Checkpoint path spec -> Checkpoint path (canonicalSpec spec)
  NotModelled what -> NotModelled what
  ExpectRefused kind inner -> ExpectRefused kind (canonicalMove inner)

canonicalBinding :: Binding -> Binding
canonicalBinding = \case
  BindPoint p -> BindPoint (canonicalPoint p)
  BindLine line -> case canonicalLine line of
    LineNamed name -> BindPoint (PointNamed name)
    other -> BindLine other

canonicalMacro :: MacroCall -> MacroCall
canonicalMacro = \case
  Collapse p keeping angle -> Collapse (canonicalPoint p) (both canonicalPoint <$> keeping) angle
  RabbitEar p angle -> RabbitEar (canonicalPoint p) angle
  Petal (TipAt p) angle -> Petal (TipAt (canonicalPoint p)) angle
  Petal TopFlapTip angle -> Petal TopFlapTip angle
  where
    both f (a, b) = (f a, f b)

canonicalIsometry :: Isometry -> Isometry
canonicalIsometry = \case
  MirroredAcross p q -> MirroredAcross (canonicalPoint p) (canonicalPoint q)
  TurnedQuarters quarters p -> TurnedQuarters quarters (canonicalPoint p)

canonicalSpec :: StackingSpec -> StackingSpec
canonicalSpec = \case
  Relations relations -> Relations [LayerAbove (canonicalPoint a) (canonicalPoint b) | LayerAbove a b <- relations]
  StackingFirst -> StackingFirst

-- A point is never itself rewritten, but 'Meet' holds lines that may be.
canonicalPoint :: Point -> Point
canonicalPoint = \case
  CornerOf corner -> CornerOf corner
  Centre -> Centre
  AtSheet u v -> AtSheet u v
  MidpointOf p q -> MidpointOf (canonicalPoint p) (canonicalPoint q)
  MidpointOfEdge side -> MidpointOfEdge side
  FractionAlong r p q -> FractionAlong r (canonicalPoint p) (canonicalPoint q)
  Meet l1 l2 -> Meet (canonicalLine l1) (canonicalLine l2)
  EndOfCreaseOf name p -> EndOfCreaseOf name (canonicalPoint p)
  PointNamed name -> PointNamed name

-- The parts are rewritten first and the line itself second. One pass is
-- enough, and that is why 'canonical' is idempotent, for two reasons. No rule
-- produces a 'LineNamed', and every rule fires only on a 'LineNamed', so
-- rewriting the parts can never turn a line the rules skipped into one they
-- would take. And what a rule produces is itself finished: an 'Onto', which
-- no rule touches, or a 'PointToLine' whose line is not a bare name.
--
-- That last clause depends on the order of the two 'LineOnto' arms. The arm
-- for two bare names has to come first; tried second, its case would fall to
-- the arm below it and leave a 'PointToLine' onto a bare name, which a second
-- pass would rewrite again.
canonicalLine :: Line -> Line
canonicalLine = \case
  EdgeOf side -> EdgeOf side
  Segment p q -> Segment (canonicalPoint p) (canonicalPoint q)
  Onto p q -> Onto (canonicalPoint p) (canonicalPoint q)
  LineOnto l1 l2 nearest ->
    case (canonicalLine l1, canonicalLine l2, canonicalPoint <$> nearest) of
      (LineNamed a, LineNamed b, Nothing) -> Onto (PointNamed a) (PointNamed b)
      (LineNamed a, second, Nothing) -> PointToLine (PointNamed a) second
      (first, second, chosen) -> LineOnto first second chosen
  PerpendicularThrough line p -> PerpendicularThrough (canonicalLine line) (canonicalPoint p)
  PointToLineThrough p line q nearest ->
    PointToLineThrough (canonicalPoint p) (canonicalLine line) (canonicalPoint q) (canonicalPoint <$> nearest)
  TwoToTwo p l1 q l2 nearest ->
    TwoToTwo (canonicalPoint p) (canonicalLine l1) (canonicalPoint q) (canonicalLine l2) (canonicalPoint <$> nearest)
  PointToLinePerpendicular p l1 l2 ->
    PointToLinePerpendicular (canonicalPoint p) (canonicalLine l1) (canonicalLine l2)
  PointToLine p line -> case canonicalLine line of
    LineNamed b -> Onto (canonicalPoint p) (PointNamed b)
    other -> PointToLine (canonicalPoint p) other
  ExistingCrease p q -> ExistingCrease (canonicalPoint p) (canonicalPoint q)
  HingeOf name -> HingeOf name
  CreaseOf name -> CreaseOf name
  ModelSegment from to -> ModelSegment from to
  LineNamed name -> LineNamed name

-- | A file a sequence names, and where that file actually is.
data SourceFile = SourceFile
  { -- | The path exactly as the author wrote it. Sheets are handed to the
    -- runner keyed by this, so that messages use the author's spelling and a
    -- test can supply a sheet without a filesystem.
    sourceWritten :: FilePath,
    -- | The path to open.
    sourceToOpen :: FilePath,
    -- | Where the path was written, for a file that turns out not to load.
    sourceSpan :: Span
  }
  deriving stock (Eq, Show)

-- | Every file a sequence asks for: its sheet, if that is a file, and then
-- each @checkpoint@ in the order written. The first argument is the path of
-- the sequence source itself.
--
-- A relative path is relative to the /source's own directory/, never to the
-- directory the command was run from, so a sequence reads the same sheet from
-- a Makefile, a test and a shell. An absolute path is kept as it is.
--
-- A file named twice is listed twice, each with its own span; whoever loads
-- them decides to read it once. This function only names files and opens
-- none. Opening them is left to "Senbazuru.Fold.Load", the library's only
-- I\/O, which is what lets the rule be tested without a disk.
sourceFiles :: FilePath -> Sequence -> [SourceFile]
sourceFiles source (Sequence header steps) =
  sheetFile <> concatMap checkpointsOfStep steps
  where
    sheetFile = case hSheet header of
      Located sp (SheetFile written) -> [named sp written]
      Located _ UnitSquare -> []

    checkpointsOfStep (Located _ step) = concatMap checkpointsOfLocated (stepMoves step)
    checkpointsOfLocated (Located sp move) = checkpointsOf sp move

    -- A checkpoint inside @expect refused@ has no span of its own, so it is
    -- located at the move around it. No catch-all here either, for the reason
    -- given in 'stripSpans': a move added later that names a file has to be
    -- listed, or whoever loads the files never hears of it.
    checkpointsOf sp = \case
      Checkpoint written _ -> [named sp written]
      Together members -> concatMap checkpointsOfLocated members
      ExpectRefused _ inner -> checkpointsOf sp inner
      Fold {} -> []
      FoldAndUnfold {} -> []
      Unfold {} -> []
      TurnOver {} -> []
      Rotate {} -> []
      Anchor {} -> []
      Mark {} -> []
      Let {} -> []
      Macro {} -> []
      Continue {} -> []
      Pose {} -> []
      Repeat {} -> []
      NotModelled {} -> []

    -- This keeps an absolute path although it never asks whether the path is
    -- absolute, which looks like an oversight and is not: 'replaceFileName'
    -- joins with @<\/>@, and @<\/>@ hands back its right-hand side whole when
    -- that side is absolute.
    named sp written = SourceFile written (replaceFileName source written) sp

-- | A number of the language as text: a whole number, or @n\/d@ in lowest
-- terms, never a decimal. 'Rational' keeps itself reduced with a positive
-- denominator, so @58\/100@ arrives here as @29\/50@ and the sign is always
-- the numerator's.
--
-- It lives beside the tree, and not in the printer, because two modules need
-- it and one of them sits below the printer: a refusal that quotes a number
-- has to spell it the way printed text does, or an author is told about a
-- @0.58@ they can find nowhere in the printed sequence.
exactNumber :: Rational -> Text
exactNumber r
  | denominator r == 1 = T.pack (show (numerator r))
  | otherwise = T.pack (show (numerator r)) <> "/" <> T.pack (show (denominator r))
