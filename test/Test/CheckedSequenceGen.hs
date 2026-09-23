-- |
-- Module      : Test.CheckedSequenceGen
-- Description : Random fold sequences that mean something, and the same with one value only Haskell can make.
--
-- "Test.SequenceGen" makes sequences a source could /spell/, with names drawn
-- from a pool regardless of what defines them. The checker refuses nearly all
-- of those, so a property about checked sequences needs sequences that name
-- only what is already defined. This module makes them.
--
-- == How it keeps to the rules
--
-- It walks the sequence in the order the checker reads it, keeping a record
-- of what has been defined so far, and draws each name from that record:
--
-- * a point's name only where a point may stand, a line's where a line may,
--   and only after the @mark@ or @let@ that gives it;
-- * a step's name only once the step has closed, and only a step of the right
--   kind: one that draws a picture for @unfold@ and @repeat@, one of exactly
--   one macro-move for @continue@, one that turned paper at most once for
--   @hinge of@;
-- * every name new, from a pool of ordinary words with a number added when a
--   word is taken;
-- * a step never made of @let@s alone; numbers inside their ranges.
--
-- Those rules are restated here rather than imported from the checker, on
-- purpose. A property that asks the checker to accept what this generates is
-- then a comparison of two readings of the design, and a disagreement between
-- them fails loudly instead of agreeing with itself.
--
-- == Where it is cautious instead of exact
--
-- A @repeat@ that is mirrored or turned may not carry a @model [...]@ line or
-- a count of layers, and the checker follows that through names and through
-- earlier @repeat@s. Rather than restate all of that, each step is chosen to
-- be /clean/ or not before it is made. A clean step makes no model line and
-- no count of layers, repeats only clean steps, and names only points and
-- lines that cannot hold a model line: those defined in clean steps, marks,
-- which are fixed to the paper when they are made, and points known exactly.
-- Only a range of clean steps is ever mirrored or turned. That rules out some
-- sequences the checker would accept, and never admits one it would refuse.
--
-- == Values only Haskell can make
--
-- 'genPossiblyFaulty' plants one of them, sometimes, in a sequence made as
-- above: a name that is not a word, a reserved word as a name, a count of no
-- layers, a fold's angle with a sign, a macro-move taken backwards, an
-- in-between pose with a sign, a @continue@ taken backwards, an @unfold@ of no
-- steps. It goes on a step's name, or in a move standing alone or inside a
-- @together@ or an @expect refused@. Everything before the planted value is
-- sound, so the checker must refuse the sequence and must refuse it for that
-- value, which is handed back beside it with where it was put.
--
-- Every span is 'NoSpan', as in a sequence built in Haskell.
module Test.CheckedSequenceGen
  ( genChecked,
    genPossiblyFaulty,
    Planted (..),
    Fault (..),
    Placement (..),
  )
where

import Control.Monad (join, replicateM)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.State.Strict (StateT, evalStateT, get, gets, modify', put)
import Data.Ratio ((%))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Sequence.Error (Bound (..), Place (..), StaticProblem (..), refusalKinds)
import Senbazuru.Sequence.Parse (reservedWords)
import Senbazuru.Sequence.Syntax
import Test.QuickCheck
import Test.SequenceGen (genAngle, genCaption, genFraction, genPath, genSigned, namePool)
import Test.SequenceHelpers (built)

-- | A sequence the checker should accept.
genChecked :: Gen Sequence
genChecked = evalStateT sequenceG (Scope [] [] [] Set.empty False)

-- ---------------------------------------------------------------------------
-- What has been defined so far

type G = StateT Scope Gen

data Scope = Scope
  { scopePoints :: [Defined],
    scopeLines :: [Defined],
    -- | Finished steps, oldest first.
    scopeSteps :: [Finished],
    -- | Every name given, so that each new one is new.
    scopeUsed :: Set Text,
    -- | Whether the step being made is clean; see the module header.
    scopeClean :: Bool
  }

-- | A point's or a line's name.
data Defined = Defined
  { definedName :: Name,
    -- | Usable in a clean step.
    definedClean :: Bool,
    -- | A point known exactly without folding: a mirror or a turn may be
    -- about it.
    definedExact :: Bool
  }

-- | What a later move needs to know of a finished step.
data Finished = Finished
  { finishedName :: Maybe Name,
    finishedNumber :: Int,
    finishedFigure :: Bool,
    finishedMacros :: Int,
    finishedTurns :: Int,
    finishedClean :: Bool
  }

-- | One of several choices, each a step of the generator, by weight.
-- 'frequency' picks the step without running it, and 'join' then runs it, in
-- this generator's state.
choice :: [(Int, G a)] -> G a
choice options = join (lift (frequency [(weight, pure option) | (weight, option) <- options]))

maybeOf :: G a -> G (Maybe a)
maybeOf value = choice [(1, pure Nothing), (1, Just <$> value)]

-- | Between one and three.
someOf :: G a -> G [a]
someOf value = do
  count <- lift (choose (1, 3))
  replicateM count value

pick :: [a] -> G a
pick = lift . elements

freshName :: G Name
freshName = do
  used <- gets scopeUsed
  base <- pick namePool
  let taken = (`Set.member` used)
      name = case filter (not . taken) (base : [base <> "-" <> T.pack (show n) | n <- [2 :: Int ..]]) of
        new : _ -> new
        [] -> base
  modify' (\scope -> scope {scopeUsed = Set.insert name (scopeUsed scope)})
  pure (Name name)

-- | Names usable here: in a clean step, only clean ones.
usable :: (Scope -> [Defined]) -> G [Name]
usable field = do
  scope <- get
  pure [definedName d | d <- field scope, definedClean d || not (scopeClean scope)]

namedSteps :: (Finished -> Bool) -> G [Name]
namedSteps wanted = gets (\scope -> [name | step <- scopeSteps scope, wanted step, Just name <- [finishedName step]])

define :: (Scope -> [Defined]) -> (Scope -> [Defined] -> Scope) -> Name -> Bool -> Bool -> G ()
define field store name clean exact =
  modify' (\scope -> store scope (Defined name clean exact : field scope))

definePoint :: Name -> Bool -> Bool -> G ()
definePoint = define scopePoints (\scope points -> scope {scopePoints = points})

defineLine :: Name -> Bool -> G ()
defineLine name clean = define scopeLines (\scope lines' -> scope {scopeLines = lines'}) name clean False

-- ---------------------------------------------------------------------------
-- The sequence, the header and the steps

sequenceG :: G Sequence
sequenceG = do
  header <- headerG
  count <- lift (choose (1, 5))
  steps <- mapM stepG [1 .. count]
  pure (Sequence header (map built steps))

-- | The header is read before any step, so nothing in it has a name to use.
headerG :: G Header
headerG = do
  title <- maybeOf (lift genCaption)
  sheet <- lift (oneof [pure UnitSquare, SheetFile <$> genPath])
  anchor <- maybeOf (pointG 2)
  side <- lift arbitraryBoundedEnum
  start <- choice [(1, pure StartFlat), (1, StartFolded <$> specG)]
  closing <- maybeOf (lift genCaption)
  pure
    Header
      { hTitle = title,
        hSheet = built sheet,
        hAnchor = built <$> anchor,
        hSide = side,
        hStart = built start,
        hClosing = closing
      }

stepG :: Int -> G Step
stepG number = do
  clean <- lift (frequency [(3, pure True), (1, pure False)])
  modify' (\scope -> scope {scopeClean = clean})
  name <- choice [(2, Just <$> freshName), (1, pure Nothing)]
  caption <- maybeOf (lift genCaption)
  -- A step of one macro-move and nothing else is what @continue@ needs, and
  -- among steps of several random moves it would be rare.
  moves <- choice [(1, pure <$> macroG), (4, movesG)]
  let finished =
        Finished
          { finishedName = name,
            finishedNumber = number,
            finishedFigure = any drawsSomething moves,
            finishedMacros = sum (map macrosIn moves),
            finishedTurns = length (filter turnsPaper moves),
            finishedClean = clean
          }
  modify' (\scope -> scope {scopeSteps = scopeSteps scope <> [finished]})
  pure (Step name caption (map built moves))
  where
    -- A step of nothing but @let@s is empty, so one fold is added to such a
    -- step.
    movesG = do
      moves <- someOf (moveG 2)
      if all isLet moves then (moves <>) . pure <$> foldG else pure moves

-- The rules the checker reads a step by, restated; see the module header.

isLet :: Move -> Bool
isLet = \case
  Let {} -> True
  _ -> False

drawsSomething :: Move -> Bool
drawsSomething = \case
  Let {} -> False
  ExpectRefused {} -> False
  _ -> True

macrosIn :: Move -> Int
macrosIn = \case
  Macro {} -> 1
  Together members -> sum (map (macrosIn . locValue) members)
  _ -> 0

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
  _ -> False

-- ---------------------------------------------------------------------------
-- Moves

-- | A move. The depth bounds how far @together@ and @expect refused@ nest.
moveG :: Int -> G Move
moveG depth = do
  figures <- namedSteps finishedFigure
  singleMacros <- namedSteps ((== 1) . finishedMacros)
  ranges <- repeatRanges
  choice $
    [ (8, foldG),
      (2, FoldAndUnfold <$> lift arbitraryBoundedEnum <*> lineG 2 <*> layersG <*> maybeOf (pointG 1)),
      (1, TurnOver <$> lift arbitraryBoundedEnum),
      (1, Rotate <$> lift (choose (1, 7)) <*> lift arbitraryBoundedEnum),
      (1, Anchor <$> pointG 2),
      (2, markG),
      -- Lines' names are what the checker has most to do with, and a @let@
      -- is the only way to get one.
      (5, letG),
      (2, macroG),
      (1, Pose <$> someOf ((,,) <$> pointG 1 <*> pointG 1 <*> lift genSigned)),
      (1, Checkpoint <$> lift genPath <*> specG),
      (1, NotModelled <$> lift genCaption)
    ]
      <> [(2, Unfold <$> someOf (pick figures)) | not (null figures)]
      <> [(2, Continue <$> pick singleMacros <*> lift untilAngle) | not (null singleMacros)]
      <> [(3, repeatG ranges) | not (null ranges)]
      <> if depth <= 0 then [] else [(2, togetherG depth), (2, expectG depth)]

foldG :: G Move
foldG = Fold <$> lift arbitraryBoundedEnum <*> amountG <*> lineG 2 <*> layersG <*> maybeOf (pointG 1)
  where
    amountG = lift (oneof [pure ToFlat, Degrees <$> genAngle])

-- | A count of layers means different paper once a step is carried
-- elsewhere, so a clean step never says one.
layersG :: G Layers
layersG = do
  clean <- gets scopeClean
  lift . oneof $ [pure FlapOfFirstArgument, pure AllLayers, pure TopFlap] <> [TopLayers <$> choose (1, 4) | not clean]

-- | The point is made before the name is taken, as the checker reads it. A
-- mark is fixed to the paper when it is made, so it is never a model line
-- and is clean wherever it is made.
markG :: G Move
markG = do
  p <- pointG 2
  face <- maybeOf (pointG 1)
  name <- freshName
  definePoint name True False
  pure (Mark name p face)

-- | A @let@ of a point, of a line, or of a line's name spelled as the parser
-- spells it, as a point. The last is a line, and so is the name it gives.
letG :: G Move
letG = do
  lineNames <- usable scopeLines
  clean <- gets scopeClean
  (binding, record) <-
    choice $
      [ (1, (\p -> (BindPoint p, \name -> definePoint name True True)) <$> exactPointLiteralG),
        (1, (\p -> (BindPoint p, \name -> definePoint name clean False)) <$> pointG 2),
        (4, (\l -> (BindLine l, (`defineLine` clean))) <$> lineG 2)
      ]
        <> [(1, (\n -> (BindPoint (PointNamed n), (`defineLine` clean))) <$> pick lineNames) | not (null lineNames)]
        <> [(1, (\n -> (BindLine (LineNamed n), (`defineLine` clean))) <$> pick lineNames) | not (null lineNames)]
  name <- freshName
  record name
  pure (Let name binding)

-- | A macro-move stops somewhere in (0°, 180°], and each in-between pose lies
-- strictly between 0° and there.
macroG :: G Move
macroG = do
  reach <- lift untilAngle
  call <-
    choice
      [ (1, (\p keeping -> Collapse p keeping reach) <$> pointG 1 <*> maybeOf ((,) <$> pointG 1 <*> pointG 1)),
        (1, (`RabbitEar` reach) <$> pointG 1),
        (1, (`Petal` reach) <$> choice [(1, TipAt <$> pointG 1), (1, pure TopFlapTip)])
      ]
  count <- lift (choose (0, 2))
  samples <- replicateM count (lift ((\k -> reach * (k % 8)) <$> choose (1, 7)))
  pure (Macro call samples)

untilAngle :: Gen Rational
untilAngle = (% 2) <$> choose (1, 360)

-- | The @repeat@s possible here: a finished step that draws a picture, or a
-- range of them in order, and whether every step in the range, named or not,
-- is clean. A clean step repeats only clean ranges, and only a clean range
-- may be mirrored or turned.
repeatRanges :: G [(Name, Maybe Name, Bool)]
repeatRanges = do
  scope <- get
  let steps = scopeSteps scope
      figures = [(number, name) | Finished {finishedName = Just name, finishedNumber = number, finishedFigure = True} <- steps]
      cleanBetween first final = and [finishedClean s | s <- steps, finishedNumber s >= first, finishedNumber s <= final]
  pure
    [ (from, to, rangeClean)
      | (first, from) <- figures,
        (to, final) <- (Nothing, first) : [(Just name, number) | (number, name) <- figures, number >= first],
        let rangeClean = cleanBetween first final,
        rangeClean || not (scopeClean scope)
    ]

repeatG :: [(Name, Maybe Name, Bool)] -> G Move
repeatG ranges = do
  (from, to, rangeClean) <- pick ranges
  isometry <- if rangeClean then maybeOf isometryG else pure Nothing
  pure (Repeat from to isometry)
  where
    isometryG =
      choice
        [ (1, MirroredAcross <$> exactPointG <*> exactPointG),
          (1, TurnedQuarters <$> lift (choose (1, 3)) <*> exactPointG)
        ]
    exactPointG = do
      exact <- gets (\scope -> [definedName d | d <- scopePoints scope, definedExact d])
      choice ([(1, PointNamed <$> pick exact) | not (null exact)] <> [(3, exactPointLiteralG)])

togetherG :: Int -> G Move
togetherG depth = do
  count <- lift (choose (0, 2))
  Together . map built <$> replicateM count (moveG (depth - 1))

-- | What an @expect refused@ holds never happens, so whatever it defines is
-- forgotten afterwards. The names it took stay taken, which costs nothing.
expectG :: Int -> G Move
expectG depth = do
  kind <- pick refusalKinds
  before <- get
  inner <- moveG (depth - 1)
  used <- gets scopeUsed
  put before {scopeUsed = used}
  pure (ExpectRefused kind inner)

specG :: G StackingSpec
specG = choice [(1, pure StackingFirst), (2, Relations <$> someOf (LayerAbove <$> pointG 1 <*> pointG 1))]

-- ---------------------------------------------------------------------------
-- Points and lines

-- | A point known exactly without folding.
exactPointLiteralG :: G Point
exactPointLiteralG =
  choice
    [ (2, CornerOf <$> lift arbitraryBoundedEnum),
      (1, pure Centre),
      (1, AtSheet <$> lift genSigned <*> lift genSigned),
      (1, MidpointOfEdge <$> lift arbitraryBoundedEnum)
    ]

-- | A point, nesting other points and lines at most this deep.
pointG :: Int -> G Point
pointG depth = do
  points <- usable scopePoints
  steps <- namedSteps (const True)
  choice $
    [(3, PointNamed <$> pick points) | not (null points)]
      <> [(5, exactPointLiteralG)]
      <> if depth <= 0
        then []
        else
          [ (1, MidpointOf <$> smaller <*> smaller),
            (1, FractionAlong <$> lift genFraction <*> smaller <*> smaller),
            (1, Meet <$> lineG (depth - 1) <*> lineG (depth - 1))
          ]
            <> [(1, EndOfCreaseOf <$> pick steps <*> smaller) | not (null steps)]
  where
    smaller = pointG (depth - 1)

-- | What stands beside @to@ in the parser's reading: a point, or a line's bare
-- name spelled as a point, which the checker will find is a line.
data Operand = PointOperand Point | LineNameOperand Name

operandG :: Int -> G Operand
operandG depth = do
  lineNames <- usable scopeLines
  choice ([(2, LineNameOperand <$> pick lineNames) | not (null lineNames)] <> [(5, PointOperand <$> pointG depth)])

asPoint :: Operand -> Point
asPoint = \case
  PointOperand p -> p
  LineNameOperand name -> PointNamed name

-- | A line, nesting other lines and points at most this deep.
lineG :: Int -> G Line
lineG depth = do
  lineNames <- usable scopeLines
  hinges <- namedSteps ((<= 1) . finishedTurns)
  steps <- namedSteps (const True)
  clean <- gets scopeClean
  choice $
    [(4, LineNamed <$> pick lineNames) | not (null lineNames)]
      <> [(2, EdgeOf <$> lift arbitraryBoundedEnum)]
      <> [(1, HingeOf <$> pick hinges) | not (null hinges)]
      <> [(1, CreaseOf <$> pick steps) | not (null steps)]
      <> [(1, ModelSegment <$> pair <*> pair) | not clean]
      <> if depth <= 0
        then []
        else
          [ (1, Segment <$> point <*> point),
            (3, onto),
            (2, LineOnto <$> line <*> line <*> maybeOf point),
            (1, PerpendicularThrough <$> line <*> point),
            (1, PointToLineThrough <$> point <*> line <*> point <*> maybeOf point),
            (1, TwoToTwo <$> point <*> line <*> point <*> line <*> maybeOf point),
            (1, PointToLinePerpendicular <$> point <*> line <*> line),
            (2, PointToLine . asPoint <$> operandG (depth - 1) <*> line),
            (1, ExistingCrease <$> point <*> point)
          ]
            -- The shapes a Haskell author writes where the parser would give
            -- 'Onto', which 'canonical' rewrites.
            <> [(2, PointToLine <$> point <*> (LineNamed <$> pick lineNames)) | not (null lineNames)]
            <> [(2, (\a l -> LineOnto (LineNamed a) l Nothing) <$> pick lineNames <*> line) | not (null lineNames)]
  where
    point = pointG (depth - 1)
    line = lineG (depth - 1)
    pair = lift ((,) <$> genSigned <*> genSigned)
    -- @L to P@ lays a line onto a point, which names no fold. So after a
    -- line's name, only another line's name may follow.
    onto = do
      first <- operandG (depth - 1)
      second <- case first of
        LineNameOperand _ -> LineNameOperand <$> (usable scopeLines >>= pick)
        PointOperand _ -> operandG (depth - 1)
      pure (Onto (asPoint first) (asPoint second))

-- ---------------------------------------------------------------------------
-- Values only Haskell can make

-- | Which value 'genPossiblyFaulty' planted.
data Fault
  = NameNotAToken
  | NameReserved
  | NoLayers
  | SignedFold
  | MacroBackwards
  | SampleBackwards
  | ContinueBackwards
  | UnfoldNothing
  deriving stock (Eq, Show, Enum, Bounded)

-- | Where it was planted. A value inside a block has to be found inside the
-- block, so each place is one the checker could miss on its own.
data Placement = AsAStepName | AsAMove | InsideATogether | InsideAnExpectation
  deriving stock (Eq, Show, Enum, Bounded)

-- | What 'genPossiblyFaulty' planted, where, and what the checker must say:
-- the step it must name, counted from 1 with the name it has, and the
-- problem.
data Planted = Planted
  { plantedFault :: Fault,
    plantedWhere :: Placement,
    plantedPlace :: Place,
    plantedProblem :: StaticProblem
  }
  deriving stock (Show)

-- | A planted value: the name of a step or a move, and any steps it needs
-- before it. @continue@ needs a finished step of one macro-move to continue.
data Carrier = StepNamed Name | InMove [Step] Move

-- | A sequence made by 'genChecked', and a third of the time one value only
-- Haskell can make planted in it.
genPossiblyFaulty :: Gen (Sequence, Maybe Planted)
genPossiblyFaulty = do
  s <- genChecked
  frequency
    [ (2, pure (s, Nothing)),
      ( 1,
        do
          fault <- arbitraryBoundedEnum
          (carrier, problem) <- faulty fault
          (planted, placement, place) <- plant carrier s
          pure (planted, Just (Planted fault placement place problem))
      )
    ]

faulty :: Fault -> Gen (Carrier, StaticProblem)
faulty = \case
  NameNotAToken -> do
    name <- Name <$> elements ["two words", "", "1st", "a.b", "-x", "ok?"]
    (,NotANameToken name) <$> nameCarrier name
  NameReserved -> do
    word <- elements (Set.toList reservedWords)
    name <- Name <$> elements [word, T.toUpper word, T.toTitle word]
    (,ReservedWordAsName name) <$> nameCarrier name
  NoLayers -> do
    count <- choose (-3, 0)
    pure (InMove [] (Fold ValleyFold ToFlat (EdgeOf West) (TopLayers count) (Just Centre)), LayerCountNotPositive count)
  SignedFold -> do
    angle <- negate <$> positive
    pure (InMove [] (Fold MountainFold (Degrees angle) (EdgeOf North) AllLayers (Just Centre)), SignNotAllowed angle)
  MacroBackwards -> do
    angle <- negate <$> positive
    pure (InMove [] (Macro (Collapse Centre Nothing angle) []), ParameterOutOfRange angle (Exclusive 0) (Inclusive 180))
  SampleBackwards -> do
    angle <- negate <$> positive
    pure (InMove [] (Macro (Petal TopFlapTip 90) [angle]), ParameterOutOfRange angle (Exclusive 0) (Exclusive 90))
  -- The name is outside 'namePool', so it cannot be taken already.
  ContinueBackwards -> do
    angle <- negate <$> positive
    let macroStep = Step (Just "planted-macro") Nothing [built (Macro (RabbitEar Centre 90) [])]
    pure (InMove [macroStep] (Continue "planted-macro" angle), ParameterOutOfRange angle (Exclusive 0) (Inclusive 180))
  UnfoldNothing -> pure (InMove [] (Unfold []), UnfoldNamesNothing)
  where
    positive = (% 2) <$> choose (1, 720)
    nameCarrier name = elements [StepNamed name, InMove [] (Mark name Centre Nothing), InMove [] (Let name (BindPoint Centre))]

-- | Put the value in a step that exists or in a new one, anywhere. A move may
-- be wrapped in a @together@ or an @expect refused@, where the checker reads
-- it just the same. Steps the value needs go just before the step it is in.
--
-- The step it lands in is the one the refusal must name: the @at@ steps kept
-- before it and any it needs come first, so its number is one more than
-- those.
plant :: Carrier -> Sequence -> Gen (Sequence, Placement, Place)
plant carrier (Sequence header steps) = do
  at <- choose (0, length steps)
  existing <- if null steps then pure False else arbitrary
  let (before, after) = splitAt at steps
      rebuilt middle = Sequence header (before <> middle)
  case (carrier, existing, after) of
    (StepNamed name, True, Located sp step : rest) ->
      pure (rebuilt (Located sp step {stepName = Just name} : rest), AsAStepName, InStep (at + 1) (Just name))
    (StepNamed name, _, _) ->
      pure (rebuilt (built (Step (Just name) Nothing [built (TurnOver LeftRight)]) : after), AsAStepName, InStep (at + 1) (Just name))
    (InMove needed m, _, _) -> do
      (wrapped, placement) <-
        elements
          [ (m, AsAMove),
            (Together [built m], InsideATogether),
            (ExpectRefused (RefusalKind "FlapCovered") m, InsideAnExpectation)
          ]
      let first = map built needed
          number = at + length needed + 1
      case (existing, after) of
        (True, Located sp step : rest) -> do
          j <- choose (0, length (stepMoves step))
          let (early, late) = splitAt j (stepMoves step)
          pure (rebuilt (first <> (Located sp step {stepMoves = early <> (built wrapped : late)} : rest)), placement, InStep number (stepName step))
        _ -> pure (rebuilt (first <> (built (Step Nothing Nothing [built wrapped]) : after)), placement, InStep number Nothing)
