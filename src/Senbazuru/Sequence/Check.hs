-- |
-- Module      : Senbazuru.Sequence.Check
-- Description : Refuse a fold sequence that cannot mean anything, before any paper is folded.
--
-- A fold sequence can be wrong in ways that need no paper to see. It unfolds a
-- step that was never written, gives one name twice, uses a point's name where
-- a line belongs, or has a step that does nothing. This module finds those,
-- and it is what stands between the two ways of writing a sequence and the
-- code that will fold one. It knows no geometry and opens no file, so checking
-- a whole crane costs nothing and cannot fail for want of its sheet.
--
-- == A checked sequence is a type of its own
--
-- 'checkSequence' hands back a 'Checked', and the constructor is not exported.
-- The only way to hold one is to have passed the check, so the code that
-- expands shorthand and the code that folds can ask for a 'Checked' and never
-- wonder whether names resolve. This is \"parse, don't validate\": the proof
-- that the check was made is the value, not a comment asking callers to
-- remember it.
--
-- == It also finishes a job the parser could not
--
-- A /kind/ is what a name names: a point, a line or a step. In
--
-- > let a = corner south-west
-- > let b = edge north
-- > fold valley a to b
--
-- the parser cannot know that @b@ is a line, because that depends on a @let@
-- it was not asked to understand. It reads every such bare name as a point,
-- giving @'Onto' ('PointNamed' a) ('PointNamed' b)@: the fold that lays one
-- /point/ onto another. This is the pass that knows the kinds, so it puts the
-- right constructor there, @'PointToLine' ('PointNamed' a) ('LineNamed' b)@.
-- The four shapes 'canonical' rewrites one way are the four this module
-- rewrites back, and nothing else in the tree changes:
-- @canonical (checkedSequence c)@ equals @canonical s@.
--
-- == The rules about names
--
-- * __One set of names__ for steps, marked points and @let@s. A name is given
--   once, and there is no shadowing: a second definition is 'DuplicateName'
--   wherever it is.
-- * __A name is used only after it is given__, reading the source top to
--   bottom. The header comes first, so it can use no name at all.
-- * __A step's name is taken when the step opens and usable when it closes.__
--   That looks like two rules and is one, seen from both ends: inside
--   @step a { … }@, @mark a = centre@ is a 'DuplicateName', because the name
--   is taken, and @unfold a@ is an 'UnknownName', because there is no finished
--   step @a@ to unfold yet.
-- * __What @expect refused { … }@ holds defines nothing.__ The author says the
--   move inside will be refused, so a @mark@ in it never happens.
--
-- == Values only Haskell can make
--
-- A 'Name' is text, and "Senbazuru.Sequence.Build" will wrap any text in one:
-- @"two words"@, or @"north-west"@, which is a reserved word. A count of
-- layers can be 0 and a fold's angle negative. No source can spell any of
-- these, so a sequence holding one would print as text that parses to
-- something else, or to nothing. Each is refused here, by the same rule the
-- parser uses ('isNameToken', 'reservedWords'), so that __a checked sequence
-- always prints as text that parses back to it__.
--
-- == What is not checked here
--
-- Anything that needs to know where the paper is: whether a fold line crosses
-- any paper, whether two lines meet, whether a flap is free to move. Those are
-- refused by the code that folds. One bound on a number is left to it as well:
-- @continue NAME until A@ has to go /beyond/ where the named move stopped, and
-- where it stopped is known only by running it.
--
-- Only the first problem is reported, in the order an author reads the
-- source. The second is often a consequence of the first.
module Senbazuru.Sequence.Check
  ( Checked,
    checkedSequence,
    checkSequence,
  )
where

import Control.Monad (unless, when, zipWithM)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Reader (ReaderT, ask, local, runReaderT)
import Control.Monad.Trans.State.Strict (StateT, evalStateT, get, gets, modify', put)
import Data.Foldable (for_, traverse_)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Senbazuru.Sequence.Error
import Senbazuru.Sequence.Parse (isNameToken, reservedWords)
import Senbazuru.Sequence.Syntax

-- | A sequence that passed 'checkSequence'. Opaque: see the module header.
newtype Checked = Checked Sequence
  deriving stock (Eq, Show)

-- | The sequence, with every bare name beside @to@ given its kind. It differs
-- from what was checked in those places only.
checkedSequence :: Checked -> Sequence
checkedSequence (Checked checked) = checked

-- | Check a sequence, built or parsed. A refusal names the step, and for
-- parsed text carries the span of the move as well.
checkSequence :: Sequence -> Either SequenceError Checked
checkSequence (Sequence header steps) =
  Checked <$> evalStateT (runReaderT checked (Here InHeader NoSpan)) (Scope Map.empty Map.empty)
  where
    checked = Sequence <$> checkHeader header <*> zipWithM checkStep [1 ..] steps

-- ---------------------------------------------------------------------------
-- What the check carries

-- | The reader holds where the check has got to, which is what a refusal
-- reports. The state holds what has been defined so far.
type Check = ReaderT Here (StateT Scope (Either SequenceError))

data Here = Here Place Span

data Scope = Scope
  { scopeNames :: Map Name Known,
    -- | Every finished step by its number, named or not: a @repeat a..b@
    -- takes in the unnamed steps between its ends.
    scopeSteps :: Map Int StepFacts
  }

-- | A name that is taken. 'StepOpen' is the step being checked: its name
-- cannot be given again, and cannot be used yet.
data Known = Finished Defined | StepOpen

data Defined
  = DefinedPoint PointFacts
  | -- | A line, and whether it is in the model's coordinates; see 'pointInModel'.
    DefinedLine Bool
  | -- | A step, by its number.
    DefinedStep Int

-- | What later checks need to know of a named point.
data PointFacts = PointFacts
  { -- | It is a place on the sheet known exactly without folding: a corner,
    -- the centre, @(u, v)@ or the midpoint of an edge. A @repeat@ may be
    -- mirrored or turned about such a point and no other.
    pointExact :: Bool,
    -- | Somewhere inside it is a @model [...]@ line, which is measured on the
    -- model as seen and so is no place on the sheet.
    pointInModel :: Bool
  }

-- | What later checks need to know of a finished step.
data StepFacts = StepFacts
  { factName :: Maybe Name,
    -- | It draws a picture of its own: it has a move that is neither a @let@
    -- nor an @expect refused@.
    factFigure :: Bool,
    -- | How many macro-moves it holds. @continue@ needs exactly one.
    factMacros :: Int,
    -- | How many of its moves turn paper. @hinge of@ needs at most one.
    factTurns :: Int,
    factInModel :: Bool,
    factCountsLayers :: Bool
  }

refuse :: StaticProblem -> Check a
refuse problem = do
  Here place sp <- ask
  lift (lift (Left (StaticRefused place sp problem)))

-- | Run a check on a located piece, with refusals pointing at its span.
located :: (a -> Check b) -> Located a -> Check (Located b)
located check (Located sp value) =
  Located sp <$> local (\(Here place _) -> Here place sp) (check value)

-- ---------------------------------------------------------------------------
-- Names

-- | Take a name. The three tests run in this order so that a name no source
-- could spell is refused as that, and not as a duplicate of another like it.
define :: Known -> Name -> Check ()
define known name@(Name text) = do
  unless (isNameToken text) (refuse (NotANameToken name))
  when (T.toLower text `Set.member` reservedWords) (refuse (ReservedWordAsName name))
  taken <- lift (gets (Map.member name . scopeNames))
  when taken (refuse (DuplicateName name))
  bind name known

bind :: Name -> Known -> Check ()
bind name known = lift (modify' (\scope -> scope {scopeNames = Map.insert name known (scopeNames scope)}))

-- | What a name names. The open step's own name is not usable yet.
lookUp :: Name -> Check Defined
lookUp name = do
  known <- lift (gets (Map.lookup name . scopeNames))
  case known of
    Just (Finished defined) -> pure defined
    Just StepOpen -> refuse (UnknownName name)
    Nothing -> refuse (UnknownName name)

kindOf :: Defined -> NameKind
kindOf = \case
  DefinedPoint _ -> PointName
  DefinedLine _ -> LineName
  DefinedStep _ -> StepName

-- | A name where only a step's will do, and that step's facts.
stepNamed :: Name -> Check (Int, StepFacts)
stepNamed name =
  lookUp name >>= \case
    DefinedStep number -> do
      facts <- lift (gets (Map.lookup number . scopeSteps))
      -- A step's name is bound to its number only once its facts are stored,
      -- so the lookup cannot miss. Saying so with a refusal keeps this total.
      maybe (refuse (UnknownName name)) (pure . (number,)) facts
    other -> refuse (WrongKind name StepName (kindOf other))

-- | A step that draws a picture, which is what @unfold@ and @repeat@ need.
figureNamed :: Name -> Check Int
figureNamed name = do
  (number, facts) <- stepNamed name
  unless (factFigure facts) (refuse (NotAFigure name))
  pure number

-- ---------------------------------------------------------------------------
-- The header and the steps

-- | The header is checked before any step, so a name in it is always unknown.
checkHeader :: Header -> Check Header
checkHeader header = do
  anchor <- traverse (located checkPoint) (hAnchor header)
  start <- located checkStart (hStart header)
  pure header {hAnchor = anchor, hStart = start}
  where
    checkStart = \case
      StartFlat -> pure StartFlat
      StartFolded spec -> StartFolded <$> checkSpec spec

checkStep :: Int -> Located Step -> Check (Located Step)
checkStep number (Located sp step) =
  local (const (Here (InStep number (stepName step)) sp)) $ do
    traverse_ (define StepOpen) (stepName step)
    moves <- traverse (located checkMove) (stepMoves step)
    when (all (isLet . locValue) moves) (refuse EmptyStep)
    names <- lift (gets scopeNames)
    let facts =
          StepFacts
            { factName = stepName step,
              factFigure = any (drawsSomething . locValue) moves,
              factMacros = sum (map (macrosIn . locValue) moves),
              factTurns = length (filter (turnsPaper . locValue) moves),
              factInModel = any (moveInModel names . locValue) moves,
              factCountsLayers = any (countsLayers . locValue) moves
            }
    lift (modify' (\scope -> scope {scopeSteps = Map.insert number facts (scopeSteps scope)}))
    for_ (stepName step) (\name -> bind name (Finished (DefinedStep number)))
    pure (Located sp step {stepMoves = moves})

isLet :: Move -> Bool
isLet = \case
  Let {} -> True
  Fold {} -> False
  FoldAndUnfold {} -> False
  Unfold {} -> False
  TurnOver {} -> False
  Rotate {} -> False
  Anchor {} -> False
  Mark {} -> False
  Macro {} -> False
  Continue {} -> False
  Together {} -> False
  Pose {} -> False
  Repeat {} -> False
  Checkpoint {} -> False
  NotModelled {} -> False
  ExpectRefused {} -> False

-- | A step whose moves are all @let@ or @expect refused@ leaves the paper as
-- it found it and draws nothing.
drawsSomething :: Move -> Bool
drawsSomething = \case
  Let {} -> False
  ExpectRefused {} -> False
  Fold {} -> True
  FoldAndUnfold {} -> True
  Unfold {} -> True
  TurnOver {} -> True
  Rotate {} -> True
  Anchor {} -> True
  Mark {} -> True
  Macro {} -> True
  Continue {} -> True
  Together {} -> True
  Pose {} -> True
  Repeat {} -> True
  Checkpoint {} -> True
  NotModelled {} -> True

-- | A @together@ counts for what it holds. An @expect refused@ counts for
-- nothing: its macro-move never runs, so there is nothing to continue.
macrosIn :: Move -> Int
macrosIn = \case
  Macro {} -> 1
  Together members -> sum (map (macrosIn . locValue) members)
  ExpectRefused {} -> 0
  Fold {} -> 0
  FoldAndUnfold {} -> 0
  Unfold {} -> 0
  TurnOver {} -> 0
  Rotate {} -> 0
  Anchor {} -> 0
  Mark {} -> 0
  Let {} -> 0
  Continue {} -> 0
  Pose {} -> 0
  Repeat {} -> 0
  Checkpoint {} -> 0
  NotModelled {} -> 0

-- | Whether a move turns paper about a line. @hinge of NAME@ means the line
-- NAME's one such move turned about, so it counts these. A @together@ is one
-- move here, as it is everywhere else.
turnsPaper :: Move -> Bool
turnsPaper = \case
  Fold {} -> True
  FoldAndUnfold {} -> True
  Unfold {} -> True
  Macro {} -> True
  Continue {} -> True
  Together {} -> True
  Pose {} -> True
  Repeat {} -> True
  TurnOver {} -> False
  Rotate {} -> False
  Anchor {} -> False
  Mark {} -> False
  Let {} -> False
  Checkpoint {} -> False
  NotModelled {} -> False
  ExpectRefused {} -> False

-- ---------------------------------------------------------------------------
-- Moves

checkMove :: Move -> Check Move
checkMove = \case
  Fold sense amount line layers seed -> do
    checkAmount amount
    Fold sense amount <$> checkLine line <*> checkLayers layers <*> traverse checkPoint seed
  FoldAndUnfold sense line layers seed ->
    FoldAndUnfold sense <$> checkLine line <*> checkLayers layers <*> traverse checkPoint seed
  Unfold names -> do
    when (null names) (refuse UnfoldNamesNothing)
    traverse_ figureNamed names
    pure (Unfold names)
  TurnOver axis -> pure (TurnOver axis)
  Rotate eighths turning -> do
    unless (eighths >= 1 && eighths <= 7) (refuse (NotEighths eighths))
    pure (Rotate eighths turning)
  Anchor p -> Anchor <$> checkPoint p
  -- The point is checked before the name is taken, so @mark a = a@ is an
  -- unknown name and not a mark of itself.
  Mark name p face -> do
    checkedPoint <- checkPoint p
    checkedFace <- traverse checkPoint face
    -- A mark is fixed to the paper when it is made. From then on it is a
    -- place on the sheet, though not one known without folding.
    define (Finished (DefinedPoint (PointFacts {pointExact = False, pointInModel = False}))) name
    pure (Mark name checkedPoint checkedFace)
  Let name binding -> do
    checkedBinding <- checkBinding binding
    names <- lift (gets scopeNames)
    let defined = case checkedBinding of
          BindPoint p -> DefinedPoint (PointFacts {pointExact = exactPoint names p, pointInModel = pointInModelNow names p})
          BindLine line -> DefinedLine (lineInModel names line)
    define (Finished defined) name
    pure (Let name checkedBinding)
  Macro call samples -> do
    checkedCall <- checkMacro call
    let reaches = untilOf call
    checkUntil reaches
    for_ samples $ \sample ->
      unless (sample > 0 && sample < reaches) (refuse (ParameterOutOfRange sample (Exclusive 0) (Exclusive reaches)))
    pure (Macro checkedCall samples)
  Continue name angle -> do
    (_, facts) <- stepNamed name
    unless (factMacros facts == 1) (refuse (NotASingleMacro name))
    checkUntil angle
    pure (Continue name angle)
  Together members -> Together <$> traverse (located checkMove) members
  Pose creases -> Pose <$> traverse (\(p, q, angle) -> (,,angle) <$> checkPoint p <*> checkPoint q) creases
  Repeat from to isometry -> do
    firstStep <- figureNamed from
    lastStep <- maybe (pure firstStep) figureNamed to
    when (lastStep < firstStep) (refuse (RangeRunsBackwards from (fromMaybe from to)))
    Repeat from to <$> traverse (checkIsometry from [firstStep .. lastStep]) isometry
  Checkpoint path spec -> Checkpoint path <$> checkSpec spec
  NotModelled what -> pure (NotModelled what)
  ExpectRefused kind inner -> do
    unless (kind `elem` refusalKinds) (refuse (UnknownRefusalKind kind))
    -- The names are put back afterwards: what is in here never happens.
    before <- lift get
    checkedInner <- checkMove inner
    lift (put before)
    pure (ExpectRefused kind checkedInner)

-- | A fold's angle is unsigned. Text cannot spell a negative one.
checkAmount :: Amount -> Check ()
checkAmount = \case
  ToFlat -> pure ()
  Degrees angle -> when (angle < 0) (refuse (SignNotAllowed angle))

checkLayers :: Layers -> Check Layers
checkLayers = \case
  TopLayers count -> do
    when (count < 1) (refuse (LayerCountNotPositive count))
    pure (TopLayers count)
  FlapOfFirstArgument -> pure FlapOfFirstArgument
  AllLayers -> pure AllLayers
  TopFlap -> pure TopFlap

-- | How far a macro-move's driving crease may be taken. Every macro-move the
-- language has closes flat, and flat is 180°.
macroMaximum :: Rational
macroMaximum = 180

-- | An @until@ angle: more than 0, since a move has to go somewhere, and no
-- more than the macro-move allows.
checkUntil :: Rational -> Check ()
checkUntil angle =
  unless (angle > 0 && angle <= macroMaximum) (refuse (ParameterOutOfRange angle (Exclusive 0) (Inclusive macroMaximum)))

untilOf :: MacroCall -> Rational
untilOf = \case
  Collapse _ _ angle -> angle
  RabbitEar _ angle -> angle
  Petal _ angle -> angle

checkMacro :: MacroCall -> Check MacroCall
checkMacro = \case
  Collapse p keeping angle ->
    Collapse <$> checkPoint p <*> traverse (\(q1, q2) -> (,) <$> checkPoint q1 <*> checkPoint q2) keeping <*> pure angle
  RabbitEar p angle -> RabbitEar <$> checkPoint p <*> pure angle
  Petal (TipAt p) angle -> Petal . TipAt <$> checkPoint p <*> pure angle
  Petal TopFlapTip angle -> pure (Petal TopFlapTip angle)

checkSpec :: StackingSpec -> Check StackingSpec
checkSpec = \case
  StackingFirst -> pure StackingFirst
  Relations relations -> Relations <$> traverse (\(LayerAbove a b) -> LayerAbove <$> checkPoint a <*> checkPoint b) relations

-- | A mirror or a turn carries a step to another part of the sheet by moving
-- the names in it, so everything in reach has to /be/ a name on the sheet.
-- The refusal names the step in the way where it has a name, and otherwise
-- the step the @repeat@ named.
checkIsometry :: Name -> [Int] -> Isometry -> Check Isometry
checkIsometry from numbers isometry = do
  checkedIsometry <- case isometry of
    MirroredAcross p q -> MirroredAcross <$> checkPoint p <*> checkPoint q
    TurnedQuarters quarters p -> do
      unless (quarters >= 1 && quarters <= 3) (refuse (NotQuarters quarters))
      TurnedQuarters quarters <$> checkPoint p
  names <- lift (gets scopeNames)
  let fixedPoints = case checkedIsometry of
        MirroredAcross p q -> [p, q]
        TurnedQuarters _ p -> [p]
  unless (all (exactPoint names) fixedPoints) (refuse (RepeatUnmappable from IsometryByConstruction))
  steps <- lift (gets (\scope -> mapMaybe (`Map.lookup` scopeSteps scope) numbers))
  for_ steps $ \facts -> do
    when (factInModel facts) (refuse (RepeatUnmappable (fromMaybe from (factName facts)) UsesModelCoordinates))
    when (factCountsLayers facts) (refuse (RepeatUnmappable (fromMaybe from (factName facts)) CountsLayers))
  pure checkedIsometry

-- ---------------------------------------------------------------------------
-- Points and lines

-- | One side of a @to@: a point, or the bare name of a line.
data Operand = PointOperand Point | LineOperand Name

-- | Read a point that stands beside @to@. The parser wrote a bare name there
-- as a point whatever it names, and this is where a line's name is told from
-- a point's.
operand :: Point -> Check Operand
operand = \case
  PointNamed name ->
    lookUp name >>= \case
      DefinedPoint _ -> pure (PointOperand (PointNamed name))
      DefinedLine _ -> pure (LineOperand name)
      DefinedStep _ -> refuse (WrongKind name PointName StepName)
  other -> PointOperand <$> checkPoint other

-- | The right-hand side of a @let@, which has the same trouble: @let n = b@
-- was read as a point, and @b@ may be a line.
checkBinding :: Binding -> Check Binding
checkBinding = \case
  BindLine line -> BindLine <$> checkLine line
  BindPoint p ->
    operand p >>= \case
      PointOperand q -> pure (BindPoint q)
      LineOperand name -> pure (BindLine (LineNamed name))

checkPoint :: Point -> Check Point
checkPoint = \case
  CornerOf corner -> pure (CornerOf corner)
  Centre -> pure Centre
  AtSheet u v -> pure (AtSheet u v)
  MidpointOf p q -> MidpointOf <$> checkPoint p <*> checkPoint q
  MidpointOfEdge side -> pure (MidpointOfEdge side)
  FractionAlong r p q -> do
    unless (r >= 0 && r <= 1) (refuse (RatioOutOfRange r))
    FractionAlong r <$> checkPoint p <*> checkPoint q
  Meet l1 l2 -> Meet <$> checkLine l1 <*> checkLine l2
  EndOfCreaseOf name p -> do
    _ <- stepNamed name
    EndOfCreaseOf name <$> checkPoint p
  PointNamed name ->
    lookUp name >>= \case
      DefinedPoint _ -> pure (PointNamed name)
      other -> refuse (WrongKind name PointName (kindOf other))

-- | A line, with its bare names given their kinds.
--
-- 'Onto' and 'PointToLine' are the two forms the parser produces for a name
-- whose kind it could not know, so they are the two read with 'operand'. A
-- line laid onto a point names no fold. When that is found, the name blamed
-- is the second one if it is a name, since @L to P@ reads as a wrong @P@, and
-- the first otherwise.
checkLine :: Line -> Check Line
checkLine = \case
  EdgeOf side -> pure (EdgeOf side)
  Segment p q -> Segment <$> checkPoint p <*> checkPoint q
  Onto p q -> do
    from <- operand p
    to <- operand q
    case (from, to) of
      (PointOperand a, PointOperand b) -> pure (Onto a b)
      (PointOperand a, LineOperand l) -> pure (PointToLine a (LineNamed l))
      (LineOperand l1, LineOperand l2) -> pure (LineOnto (LineNamed l1) (LineNamed l2) Nothing)
      (LineOperand _, PointOperand (PointNamed b)) -> refuse (WrongKind b LineName PointName)
      (LineOperand l, PointOperand _) -> refuse (WrongKind l PointName LineName)
  LineOnto l1 l2 nearest -> LineOnto <$> checkLine l1 <*> checkLine l2 <*> traverse checkPoint nearest
  PerpendicularThrough line p -> PerpendicularThrough <$> checkLine line <*> checkPoint p
  PointToLineThrough p line q nearest ->
    PointToLineThrough <$> checkPoint p <*> checkLine line <*> checkPoint q <*> traverse checkPoint nearest
  TwoToTwo p l1 q l2 nearest ->
    TwoToTwo <$> checkPoint p <*> checkLine l1 <*> checkPoint q <*> checkLine l2 <*> traverse checkPoint nearest
  PointToLinePerpendicular p l1 l2 -> PointToLinePerpendicular <$> checkPoint p <*> checkLine l1 <*> checkLine l2
  PointToLine p line -> do
    from <- operand p
    onto <- checkLine line
    pure $ case from of
      PointOperand a -> PointToLine a onto
      LineOperand l -> LineOnto (LineNamed l) onto Nothing
  ExistingCrease p q -> ExistingCrease <$> checkPoint p <*> checkPoint q
  HingeOf name -> do
    (_, facts) <- stepNamed name
    when (factTurns facts > 1) (refuse (HingeOfSeveralMoves name))
    pure (HingeOf name)
  CreaseOf name -> CreaseOf name <$ stepNamed name
  ModelSegment from to -> pure (ModelSegment from to)
  LineNamed name ->
    lookUp name >>= \case
      DefinedLine _ -> pure (LineNamed name)
      other -> refuse (WrongKind name LineName (kindOf other))

-- ---------------------------------------------------------------------------
-- What a repeat can carry

-- | A place on the sheet known exactly without folding. A name counts if the
-- @let@ behind it does.
exactPoint :: Map Name Known -> Point -> Bool
exactPoint names = \case
  CornerOf _ -> True
  Centre -> True
  AtSheet _ _ -> True
  MidpointOfEdge _ -> True
  PointNamed name -> maybe False pointExact (pointFactsOf names name)
  MidpointOf _ _ -> False
  FractionAlong {} -> False
  Meet _ _ -> False
  EndOfCreaseOf _ _ -> False

pointFactsOf :: Map Name Known -> Name -> Maybe PointFacts
pointFactsOf names name = case Map.lookup name names of
  Just (Finished (DefinedPoint facts)) -> Just facts
  _ -> Nothing

-- | Whether a point is measured, anywhere inside it, on the model as seen.
-- Only 'Meet' holds lines, and only a line can be a @model [...]@.
pointInModelNow :: Map Name Known -> Point -> Bool
pointInModelNow names = \case
  CornerOf _ -> False
  Centre -> False
  AtSheet _ _ -> False
  MidpointOfEdge _ -> False
  MidpointOf p q -> pointInModelNow names p || pointInModelNow names q
  FractionAlong _ p q -> pointInModelNow names p || pointInModelNow names q
  Meet l1 l2 -> lineInModel names l1 || lineInModel names l2
  EndOfCreaseOf _ p -> pointInModelNow names p
  PointNamed name -> maybe False pointInModel (pointFactsOf names name)

lineInModel :: Map Name Known -> Line -> Bool
lineInModel names = \case
  ModelSegment _ _ -> True
  EdgeOf _ -> False
  HingeOf _ -> False
  CreaseOf _ -> False
  Segment p q -> point p || point q
  Onto p q -> point p || point q
  ExistingCrease p q -> point p || point q
  LineOnto l1 l2 nearest -> lineInModel names l1 || lineInModel names l2 || any point nearest
  PerpendicularThrough line p -> lineInModel names line || point p
  PointToLineThrough p line q nearest -> point p || lineInModel names line || point q || any point nearest
  TwoToTwo p l1 q l2 nearest -> point p || lineInModel names l1 || point q || lineInModel names l2 || any point nearest
  PointToLinePerpendicular p l1 l2 -> point p || lineInModel names l1 || lineInModel names l2
  PointToLine p line -> point p || lineInModel names line
  LineNamed name -> case Map.lookup name names of
    Just (Finished (DefinedLine inModel)) -> inModel
    _ -> False
  where
    point = pointInModelNow names

moveInModel :: Map Name Known -> Move -> Bool
moveInModel names = \case
  Fold _ _ line _ seed -> lineInModel names line || any point seed
  FoldAndUnfold _ line _ seed -> lineInModel names line || any point seed
  Anchor p -> point p
  Mark _ p face -> point p || any point face
  Let _ (BindPoint p) -> point p
  Let _ (BindLine line) -> lineInModel names line
  Macro (Collapse p keeping _) _ -> point p || any (\(q1, q2) -> point q1 || point q2) keeping
  Macro (RabbitEar p _) _ -> point p
  Macro (Petal (TipAt p) _) _ -> point p
  Macro (Petal TopFlapTip _) _ -> False
  Together members -> any (moveInModel names . locValue) members
  Pose creases -> any (\(p, q, _) -> point p || point q) creases
  Repeat _ _ isometry -> any isometryInModel isometry
  Checkpoint _ spec -> specInModel spec
  ExpectRefused _ inner -> moveInModel names inner
  Unfold _ -> False
  TurnOver _ -> False
  Rotate _ _ -> False
  Continue _ _ -> False
  NotModelled _ -> False
  where
    point = pointInModelNow names
    isometryInModel = \case
      MirroredAcross p q -> point p || point q
      TurnedQuarters _ p -> point p
    specInModel = \case
      StackingFirst -> False
      Relations relations -> any (\(LayerAbove a b) -> point a || point b) relations

-- | Whether a move says @top N layers@. A count from the reader's side means
-- different paper once the step is carried elsewhere.
countsLayers :: Move -> Bool
countsLayers = \case
  Fold _ _ _ layers _ -> isCount layers
  FoldAndUnfold _ _ layers _ -> isCount layers
  Together members -> any (countsLayers . locValue) members
  ExpectRefused _ inner -> countsLayers inner
  Unfold _ -> False
  TurnOver _ -> False
  Rotate _ _ -> False
  Anchor _ -> False
  Mark {} -> False
  Let _ _ -> False
  Macro _ _ -> False
  Continue _ _ -> False
  Pose _ -> False
  Repeat {} -> False
  Checkpoint _ _ -> False
  NotModelled _ -> False
  where
    isCount = \case
      TopLayers _ -> True
      FlapOfFirstArgument -> False
      AllLayers -> False
      TopFlap -> False
