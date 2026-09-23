-- |
-- Module      : Senbazuru.Sequence.Elaborate
-- Description : A checked fold sequence with its shorthand expanded, in the moves a run performs.
--
-- Two things an author writes are shorthand, convenient to write and nothing
-- the paper does on its own:
--
-- * @let mid = edge west to edge east@ gives a line a name. Nothing happens to
--   the paper when it is written. Each later use of @mid@ means that line,
--   worked out afresh wherever it is used, so a @let@ pins nothing to the
--   paper; a @mark@ is what does that.
-- * @fold and unfold valley mid@ makes a crease and lays the paper flat
--   again. It is a fold, and then the unfold of that fold.
--
-- This pass writes both out, so the code that folds paper meets only /core
-- moves/: no @let@ anywhere, no name of a line, and no @fold and unfold@. It
-- needs no paper and cannot fail, because 'elaborate' takes only a 'Checked'
-- sequence, whose names all resolve.
--
-- == Core moves are a type of their own
--
-- 'Core' could have been the tree's own 'Move', with a promise that
-- 'Let' and 'FoldAndUnfold' never occur. A separate type makes the promise
-- one the compiler keeps, and it has a move the tree has no way to say:
-- 'CoreUnfoldPrevious', the second half of a @fold and unfold@. The tree's
-- 'Unfold' names /steps/, and the fold it undoes here is a single move, in the
-- middle of a step.
--
-- == Every core move remembers what the author wrote
--
-- A run refuses moves, and its message has to be about the text the author
-- wrote, not the expansion. If @fold valley mid moving centre@ cannot be
-- folded, the message quotes @mid@, and its caret goes under the author's
-- line. So each 'CoreMove' carries an 'Origin': the span and the checked move
-- it came from, and which half of a @fold and unfold@ it is. The two halves
-- share one origin, and that is how a run can count them as one move, as the
-- design asks when it decides whether a step's moves still match its picture.
--
-- == Where the names go
--
-- A @let@ is replaced at each use by what it names, itself expanded, so a
-- @let@ of a @let@ ends as the construction underneath. Nothing can be
-- captured by accident: the checker gives each name once and refuses a use
-- before the definition. A @let@ inside @together { … }@ stays in scope after
-- the block, as the checker reads it, and one inside @expect refused { … }@
-- does not, since what is there never happens. What is left are the names of
-- marks, which name paper, and of steps.
--
-- Nothing else changes. The header holds no names, since it comes before any
-- definition, and a step keeps its name, caption and span.
module Senbazuru.Sequence.Elaborate
  ( -- * The expansion
    elaborate,
    Elaborated (..),
    ElaboratedStep (..),

    -- * Core moves
    CoreMove (..),
    Core (..),
    Origin (..),
    Part (..),
  )
where

import Control.Monad.Trans.State.Strict (State, evalState, get, modify', put)
import Data.Bifunctor (bimap)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Senbazuru.Sequence.Check (Checked, checkedSequence)
import Senbazuru.Sequence.Syntax

-- | A checked sequence with every @let@ and @fold and unfold@ written out.
data Elaborated = Elaborated
  { elaboratedHeader :: Header,
    elaboratedSteps :: [ElaboratedStep]
  }
  deriving stock (Eq, Show)

-- | A step as written, but for its moves. A step's number is its place in
-- the list, counted from 1, as a refusal names it.
data ElaboratedStep = ElaboratedStep
  { elaboratedName :: Maybe Name,
    elaboratedCaption :: Maybe Text,
    elaboratedSpan :: Span,
    elaboratedMoves :: [CoreMove]
  }
  deriving stock (Eq, Show)

-- | A move the run performs, and where it came from.
data CoreMove = CoreMove
  { coreOrigin :: Origin,
    coreMove :: Core
  }
  deriving stock (Eq, Show)

-- | What the author wrote that a core move came from.
data Origin = Origin
  { -- | The span of the move written: of the whole @fold and unfold@ for
    -- both its halves, and of the whole @expect refused@ for the move inside
    -- it, which has no span of its own.
    originSpan :: Span,
    -- | The move as written and checked, @let@ names and all, for a message
    -- to quote.
    originWritten :: Move,
    originPart :: Part
  }
  deriving stock (Eq, Show)

-- | Which of the core moves a written move became this one is.
data Part
  = -- | The only one: anything but a @fold and unfold@.
    WholeMove
  | -- | The fold of a @fold and unfold@.
    FoldHalf
  | -- | The unfold of a @fold and unfold@.
    UnfoldHalf
  deriving stock (Eq, Show, Enum, Bounded)

-- | A move of the paper or of how it is shown, with nothing left to expand.
--
-- Each is the tree's move of the same name but for three things. There is no
-- @let@ and no @fold and unfold@. A 'Line' in it is never a bare name, and a
-- point's name is always a mark's. And there is 'CoreUnfoldPrevious'.
data Core
  = CoreFold Sense Amount Line Layers (Maybe Point)
  | -- | Turn back the fold just before this move in the same list of moves.
    -- Only a @fold and unfold@ makes one, as its second half.
    CoreUnfoldPrevious
  | -- | @unfold c1 c2@: undo the named steps.
    CoreUnfold [Name]
  | CoreTurnOver PageAxis
  | CoreRotate Int Turning
  | CoreAnchor Point
  | CoreMark Name Point (Maybe Point)
  | CoreMacro MacroCall [Rational]
  | CoreContinue Name Rational
  | CoreTogether [CoreMove]
  | CorePose [(Point, Point, Rational)]
  | CoreRepeat Name (Maybe Name) (Maybe Isometry)
  | CoreCheckpoint FilePath StackingSpec
  | CoreNotModelled Text
  | -- | The moves the expected move became: none for a @let@, which can
    -- never be refused, and two for a @fold and unfold@, either of which may
    -- be the one refused.
    CoreExpectRefused RefusalKind [CoreMove]
  deriving stock (Eq, Show)

-- | Expand a checked sequence. Total: every name a checked sequence uses is
-- defined before it.
elaborate :: Checked -> Elaborated
elaborate checked =
  Elaborated header (evalState (mapM elaborateStep steps) Map.empty)
  where
    Sequence header steps = checkedSequence checked

-- | What each @let@ seen so far names, already expanded.
type Expand = State (Map Name Binding)

elaborateStep :: Located Step -> Expand ElaboratedStep
elaborateStep (Located sp (Step name caption moves)) =
  ElaboratedStep name caption sp . concat <$> mapM (\(Located at written) -> expand at written) moves

-- | The core moves one written move becomes: none for a @let@, two for a
-- @fold and unfold@, and one for anything else.
expand :: Span -> Move -> Expand [CoreMove]
expand sp written = do
  lets <- get
  let point = pointWith lets
      line = lineWith lets
      whole core = [CoreMove (Origin sp written WholeMove) core]
  case written of
    Let name binding -> do
      modify' (Map.insert name (bindingWith lets binding))
      pure []
    FoldAndUnfold sense l layers seed ->
      pure
        [ CoreMove (Origin sp written FoldHalf) (CoreFold sense ToFlat (line l) layers (point <$> seed)),
          CoreMove (Origin sp written UnfoldHalf) CoreUnfoldPrevious
        ]
    Fold sense amount l layers seed -> pure (whole (CoreFold sense amount (line l) layers (point <$> seed)))
    Unfold names -> pure (whole (CoreUnfold names))
    TurnOver axis -> pure (whole (CoreTurnOver axis))
    Rotate eighths turning -> pure (whole (CoreRotate eighths turning))
    Anchor p -> pure (whole (CoreAnchor (point p)))
    Mark name p face -> pure (whole (CoreMark name (point p) (point <$> face)))
    Macro call samples -> pure (whole (CoreMacro (macroWith lets call) samples))
    Continue name angle -> pure (whole (CoreContinue name angle))
    -- Each member is expanded in turn, so a @let@ among them is in scope for
    -- the members after it, and stays in scope after the block.
    Together members -> whole . CoreTogether . concat <$> mapM (\(Located at member) -> expand at member) members
    Pose creases -> pure (whole (CorePose [(point p, point q, angle) | (p, q, angle) <- creases]))
    Repeat from to isometry -> pure (whole (CoreRepeat from to (isometryWith lets <$> isometry)))
    Checkpoint path spec -> pure (whole (CoreCheckpoint path (specWith lets spec)))
    NotModelled what -> pure (whole (CoreNotModelled what))
    -- What is inside never happens, so any @let@ there is forgotten after it.
    ExpectRefused kind inner -> do
      inside <- expand sp inner
      put lets
      pure (whole (CoreExpectRefused kind inside))

-- ---------------------------------------------------------------------------
-- Replacing names

-- | A binding with the @let@s before it written out.
bindingWith :: Map Name Binding -> Binding -> Binding
bindingWith lets = \case
  BindPoint p -> BindPoint (pointWith lets p)
  BindLine l -> BindLine (lineWith lets l)

-- | A point with every @let@ name in it replaced. A name the map does not
-- hold as a point is a mark's, and stays.
pointWith :: Map Name Binding -> Point -> Point
pointWith lets = \case
  PointNamed name -> case Map.lookup name lets of
    Just (BindPoint p) -> p
    _ -> PointNamed name
  CornerOf corner -> CornerOf corner
  Centre -> Centre
  AtSheet u v -> AtSheet u v
  MidpointOf p q -> MidpointOf (point p) (point q)
  MidpointOfEdge side -> MidpointOfEdge side
  FractionAlong r p q -> FractionAlong r (point p) (point q)
  Meet l1 l2 -> Meet (lineWith lets l1) (lineWith lets l2)
  EndOfCreaseOf step p -> EndOfCreaseOf step (point p)
  where
    point = pointWith lets

-- | A line with every @let@ name in it replaced. After checking, every bare
-- line name is a @let@'s, so none is left; the last case keeps the function
-- total for a sequence no check has seen.
lineWith :: Map Name Binding -> Line -> Line
lineWith lets = \case
  LineNamed name -> case Map.lookup name lets of
    Just (BindLine l) -> l
    _ -> LineNamed name
  EdgeOf side -> EdgeOf side
  Segment p q -> Segment (point p) (point q)
  Onto p q -> Onto (point p) (point q)
  LineOnto l1 l2 nearest -> LineOnto (line l1) (line l2) (point <$> nearest)
  PerpendicularThrough l p -> PerpendicularThrough (line l) (point p)
  PointToLineThrough p l q nearest -> PointToLineThrough (point p) (line l) (point q) (point <$> nearest)
  TwoToTwo p l1 q l2 nearest -> TwoToTwo (point p) (line l1) (point q) (line l2) (point <$> nearest)
  PointToLinePerpendicular p l1 l2 -> PointToLinePerpendicular (point p) (line l1) (line l2)
  PointToLine p l -> PointToLine (point p) (line l)
  ExistingCrease p q -> ExistingCrease (point p) (point q)
  HingeOf step -> HingeOf step
  CreaseOf step -> CreaseOf step
  ModelSegment from to -> ModelSegment from to
  where
    point = pointWith lets
    line = lineWith lets

macroWith :: Map Name Binding -> MacroCall -> MacroCall
macroWith lets = \case
  Collapse p keeping angle -> Collapse (point p) (bimap point point <$> keeping) angle
  RabbitEar p angle -> RabbitEar (point p) angle
  Petal (TipAt p) angle -> Petal (TipAt (point p)) angle
  Petal TopFlapTip angle -> Petal TopFlapTip angle
  where
    point = pointWith lets

isometryWith :: Map Name Binding -> Isometry -> Isometry
isometryWith lets = \case
  MirroredAcross p q -> MirroredAcross (pointWith lets p) (pointWith lets q)
  TurnedQuarters quarters p -> TurnedQuarters quarters (pointWith lets p)

specWith :: Map Name Binding -> StackingSpec -> StackingSpec
specWith lets = \case
  StackingFirst -> StackingFirst
  Relations relations -> Relations [LayerAbove (pointWith lets a) (pointWith lets b) | LayerAbove a b <- relations]
