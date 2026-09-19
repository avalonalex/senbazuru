-- |
-- Module      : Senbazuru.Sequence.Build
-- Description : Writing a fold sequence in Haskell, as a @do@ block.
--
-- "Senbazuru.Sequence.Syntax" says what a fold sequence /is/: a header and a
-- list of steps, each holding moves. This module is the first of the two ways
-- to write one down. The other is text in a file, and both produce the same
-- value, so that a sequence can be compared with @==@ whichever way it was
-- written.
--
-- A sequence here reads like the instructions it stands for. This one is a
-- /blintz/, which folds the four corners of a square to its centre, and then
-- reopens the first corner:
--
-- > blintz :: Sequence
-- > blintz = sequenceOf (header "Blintz base" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
-- >   c1 <- step "c1" "Fold the south-east corner behind, to the centre." $
-- >     fold mountain (cornerOf SouthEast `onto` centre)
-- >   forM_ [NorthEast, NorthWest, SouthWest] $ \corner ->
-- >     step_ "Fold the next corner behind, to the centre." $
-- >       fold mountain (cornerOf corner `onto` centre)
-- >   step_ "Reopen the first corner." $ unfold [c1]
--
-- == A bind hands back a name, never geometry
--
-- @c1@ above is a 'Ref': the name @"c1"@, and nothing else. It is not the
-- folded paper, not the crease the step made, not a length. That is the one
-- decision in this module, and everything else follows from it.
--
-- Suppose 'step' also handed back the length of the line it folded along, and
-- a later line said @if len > 0.7 then … else …@. Then building a sequence
-- would have to fold paper to learn @len@, so it would need the sheet's file
-- and could fail for geometric reasons. A sequence could no longer be checked
-- without being run. And it could not be printed: text has no @if@, so the
-- printer could write only the branch taken against one particular sheet,
-- which is the wrong branch for another.
--
-- A name has none of those problems. It is known before anything folds, so
-- building is pure, cannot fail, and does no I\/O; 'Build' holds no paper at
-- all.
--
-- == Loops run now, and print unrolled
--
-- @forM_@ above is ordinary Haskell. It runs while the value is being built,
-- and the 'Sequence' that comes out holds three ordinary steps where the loop
-- was. Printed as text, those are three steps written out. Nothing turns them
-- back into a @forM_@, and nothing needs to: the two ways of writing agree on
-- the /value/, not on how it was typed. A helper function disappears the same
-- way, which is why a move that a file must be able to name is a constructor
-- of the tree and never only a function here.
--
-- == What the types check, and what they do not
--
-- Two mistakes are compile errors, and neither needed a language extension.
--
-- A move outside any step, or a step inside a step, does not typecheck,
-- because a step's body has its own type, 'Moves', separate from 'Build'. With
-- one type for both, either would compile, and this module would have to drop
-- or reorder something silently to make a 'Sequence' of it.
--
-- A point's name where a step's name belongs does not typecheck either: a
-- 'Ref' remembers which kind of thing it names. Its constructor is hidden, so
-- a 'Ref' can only come from the builder that defined the name, and a sequence
-- written with 'Ref's cannot mention a step that does not exist. It can still
-- define one name twice; the checker refuses that, as it does in text.
--
-- That is all the compiler checks. __It does not check that a fold is
-- possible.__ Whether paper can make a move is decided by running the
-- sequence, never by building it. And the tree stores plain names, so anything
-- built with 'move' and the constructors of "Senbazuru.Sequence.Syntax"
-- bypasses 'Ref' entirely; the checker refuses an unknown name there, exactly
-- as it does in text.
--
-- == Built values are canonical
--
-- 'sequenceOf' finishes with 'Senbazuru.Sequence.Syntax.canonical'. One text
-- can have two trees where a bare name stands beside @to@, and the parser
-- always produces one of them. So __@letLine "m" (namedLine l)@ stores a
-- /point/ binding, which looks like a bug and is the parser's tree__ for
-- @let m = l@: the parser cannot know @l@ names a line. Doing this once, at
-- the end, rather than in each builder, means a value assembled from raw
-- constructors comes out the same way.
--
-- == Names chosen to stay out of the way
--
-- 'sequenceOf' and 'repeatSteps' are not @sequence@ and @repeat@, and
-- 'allLayers' is not @all@, because those are Prelude's. A /macro-move/ is a
-- named move that turns several creases together, such as 'collapse'; it
-- takes the angle it runs to as an argument because the text's word for that,
-- @until@, is Prelude's too. 'valley' and 'mountain' are lower case because
-- the tree's constructors had to be 'ValleyFold' and 'MountainFold'; that
-- module's header says why.
--
-- Staying clear of Prelude is as far as that goes. __'fold' is also
-- @Data.Foldable@'s, and 'rotate' is @Data.Bits@'s.__ Prelude exports neither,
-- so a module that imports only what it uses, @Data.Foldable (for_)@ say,
-- never notices. One that imports either module whole gets \"Ambiguous
-- occurrence\" at every 'fold', and has to hide theirs. The text says @fold@,
-- and a builder that said something else to dodge a library would be the
-- wrong trade.
module Senbazuru.Sequence.Build
  ( -- * A sequence
    Build,
    sequenceOf,
    header,
    sheetFile,
    sheetSquare,

    -- * Steps
    Moves,
    step,
    step_,
    stepReturning,
    stepUncaptioned,
    stepUncaptioned_,

    -- * Names
    Ref,
    StepK,
    PointK,
    LineK,
    refName,
    point,
    namedLine,
    hingeOf,
    creaseOf,
    endOfCreaseOf,

    -- * Moves
    move,
    fold,
    foldAndUnfold,
    unfold,
    turnOver,
    rotate,
    anchor,
    mark,
    letPoint,
    letLine,
    collapse,
    rabbitEar,
    petal,
    continue,
    together,
    pose,
    repeatSteps,
    checkpoint,
    notModelled,
    expectRefused,

    -- * Senses, layers and layer relations
    valley,
    mountain,
    inFront,
    behind,
    allLayers,
    topLayers,
    topFlap,
    above,

    -- * Points and lines
    cornerOf,
    centre,
    at,
    onto,
    edge,
  )
where

import Control.Monad.Trans.State.Strict (State, modify', runState)
import Data.Kind (Type)
import Data.Text (Text)
import Senbazuru.Sequence.Syntax

-- | A sequence being written: the steps so far.
--
-- Only 'Functor', 'Applicative' and 'Monad', on purpose. 'State' could also
-- give a @MonadFix@ instance, and with it @mdo@ would let a step refer to a
-- name defined further down. A sequence is read top to bottom, by people and
-- by the runner, so that is left out.
newtype Build a = Build (State [Located Step] a)
  deriving newtype (Functor, Applicative, Monad)

-- | The body of one step being written: its moves so far.
newtype Moves a = Moves (State [Located Move] a)
  deriving newtype (Functor, Applicative, Monad)

-- | A name that is known to be defined, and what kind of thing it names.
--
-- The kind signature is not decoration. GHC2021 turns on @PolyKinds@, under
-- which a bare @newtype Ref k@ would accept @Ref Maybe@; the signature says
-- the index is an ordinary type. The three index types below have no values.
-- They exist only to be written in signatures.
type Ref :: Type -> Type
newtype Ref k = Ref Name
  deriving stock (Eq, Show)

-- | Indexes a 'Ref' to a step.
data StepK

-- | Indexes a 'Ref' to a marked or @let@-bound point.
data PointK

-- | Indexes a 'Ref' to a @let@-bound line.
data LineK

-- | The name a 'Ref' holds, for use with 'move' and the tree's constructors.
-- Reading a name out is harmless; it is /making/ a 'Ref' that is reserved to
-- the builders that define one.
refName :: Ref k -> Name
refName (Ref name) = name

-- | Finish a sequence. The steps come out in the order they were written.
sequenceOf :: Header -> Build () -> Sequence
sequenceOf top (Build body) =
  -- Each step was put on the front of the list, so the list is newest first.
  let ((), newestFirst) = runState body []
   in canonical (Sequence top (reverse newestFirst))

-- | A header with a title, the starting paper and the anchor, which is the
-- point whose paper stays still. Everything else is what a source gets by not
-- mentioning it: coloured side up, every crease flat, no closing caption.
-- Change those by record update:
--
-- > (header "A square, white side up" sheetSquare Nothing) {hSide = WhiteUp}
header :: Text -> SheetSource -> Maybe Point -> Header
header title sheet anchorPoint =
  Header
    { hTitle = Just title,
      hSheet = unlocated sheet,
      hAnchor = unlocated <$> anchorPoint,
      hSide = ColouredUp,
      hStart = unlocated StartFlat,
      hClosing = Nothing
    }

-- | The paper is the key frame of this file. The path is kept as written;
-- whoever runs the sequence supplies the sheet under that same text.
sheetFile :: FilePath -> SheetSource
sheetFile = SheetFile

-- | The paper is a plain unit square with no creases.
sheetSquare :: SheetSource
sheetSquare = UnitSquare

-- | A named, captioned step. The 'Ref' it returns is how a later move refers
-- back to it: @unfold [c1]@.
step :: Name -> Text -> Moves () -> Build (Ref StepK)
step name caption body = fst <$> stepReturning name caption body

-- | A captioned step nothing will refer to, so it needs no name. The
-- underscore is @forM_@'s: the same thing, returning nothing.
step_ :: Text -> Moves () -> Build ()
step_ caption = appendStep Nothing (Just caption)

-- | A named step that also hands back what its body returned, which is how a
-- point marked in one step reaches the steps after it:
--
-- > (_, tip) <- stepReturning "open" "Mark the tip." $ mark "tip" (cornerOf NorthEast) Nothing
stepReturning :: Name -> Text -> Moves a -> Build (Ref StepK, a)
stepReturning name caption body = do
  result <- appendStep (Just name) (Just caption) body
  pure (Ref name, result)

-- | A named step with no caption. Not the same step as one captioned @""@:
-- text may leave a caption out, and the tree records that it did.
stepUncaptioned :: Name -> Moves () -> Build (Ref StepK)
stepUncaptioned name body = Ref name <$ appendStep (Just name) Nothing body

-- | A step with neither a name nor a caption.
stepUncaptioned_ :: Moves () -> Build ()
stepUncaptioned_ = appendStep Nothing Nothing

appendStep :: Maybe Name -> Maybe Text -> Moves a -> Build a
appendStep name caption body = Build $ do
  let (result, moves) = movesOf body
  modify' (unlocated (Step name caption moves) :)
  pure result

-- | A body's result, and its moves in the order they were written.
movesOf :: Moves a -> (a, [Located Move])
movesOf (Moves body) =
  let (result, newestFirst) = runState body []
   in (result, reverse newestFirst)

-- | Every built value carries 'NoSpan': it was never text, so it has no
-- position to remember.
unlocated :: a -> Located a
unlocated = Located NoSpan

-- | Add any move, built from the tree's own constructors. This is how a fold
-- with every clause is written, since 'fold' takes only the two a fold must
-- have:
--
-- > move (Fold mountain (Degrees 90) (hingeOf c1) TopFlap (Just (cornerOf SouthEast)))
move :: Move -> Moves ()
move m = Moves (modify' (unlocated m :))

-- | @fold SENSE LINE@, with what the text means when it says no more. The
-- paper is folded flat. What moves is the /flap/ holding the first thing the
-- line names: the paper still joined to it once the model is cut along the
-- fold line ('FlapOfFirstArgument'). And there is no /seed/, the optional
-- point that says which side moves when the line alone does not.
--
-- 'ToFlat' here is not @'Degrees' 180@. A bare @fold@ parses to 'ToFlat' and
-- prints with no angle, so a builder writing 180 would print @180°@ and no
-- longer equal the text it came from.
fold :: Sense -> Line -> Moves ()
fold sense line = move (Fold sense ToFlat line FlapOfFirstArgument Nothing)

-- | @fold and unfold SENSE LINE@: make the crease and lay the paper flat again.
foldAndUnfold :: Sense -> Line -> Moves ()
foldAndUnfold sense line = move (FoldAndUnfold sense line FlapOfFirstArgument Nothing)

-- | @unfold c1 c2@. A list, because the text may name several steps.
--
-- The text needs at least one name, and a list does not: @unfold []@ builds a
-- value no source can spell, so its printed form would not parse. Like every
-- such value it is the checker's to refuse, not this function's, because
-- building cannot fail.
unfold :: [Ref StepK] -> Moves ()
unfold steps = move (Unfold (map refName steps))

-- | @turn over left-right@
turnOver :: PageAxis -> Moves ()
turnOver axis = move (TurnOver axis)

-- | @rotate k\/8 turn clockwise@. The number counts /eighths/ of a turn, so
-- @rotate 1@ is 45° and @rotate 2@ a quarter turn. Only 1 to 7 can be
-- written as text; the checker refuses anything else.
rotate :: Int -> Turning -> Moves ()
rotate eighths turning = move (Rotate eighths turning)

-- | @anchor P@, inside a step. The starting anchor goes in the 'header'.
anchor :: Point -> Moves ()
anchor p = move (Anchor p)

-- | @mark A = P [in face containing S]@. The last argument is that optional
-- clause, which picks one layer where P lies on several.
mark :: Name -> Point -> Maybe Point -> Moves (Ref PointK)
mark name p face = Ref name <$ move (Mark name p face)

-- | @let N = POINT@. Named 'letPoint' because @let@ is Haskell's.
letPoint :: Name -> Point -> Moves (Ref PointK)
letPoint name p = Ref name <$ move (Let name (BindPoint p))

-- | @let N = LINE@
letLine :: Name -> Line -> Moves (Ref LineK)
letLine name line = Ref name <$ move (Let name (BindLine line))

-- | @collapse at P [keeping [Q1, Q2] flat] until A°@, drawing no in-between
-- poses. For some, use 'move' with 'Macro', whose list holds their angles.
collapse :: Point -> Maybe (Point, Point) -> Rational -> Moves ()
collapse p keeping angle = move (Macro (Collapse p keeping angle) [])

-- | @rabbit-ear at P until A°@
rabbitEar :: Point -> Rational -> Moves ()
rabbitEar p angle = move (Macro (RabbitEar p angle) [])

-- | @petal tip P until A°@, or @petal top flap until A°@
petal :: PetalTip -> Rational -> Moves ()
petal tip angle = move (Macro (Petal tip angle) [])

-- | @continue NAME until A°@: carry the named step's macro-move further.
continue :: Ref StepK -> Rational -> Moves ()
continue name angle = move (Continue (refName name) angle)

-- | @together { … }@: the moves of the inner body, made at the same time.
together :: Moves a -> Moves a
together body = do
  let (result, members) = movesOf body
  move (Together members)
  pure result

-- | @pose { crease [P, Q] at A°; … }@. The one place an angle may be negative.
pose :: [(Point, Point, Rational)] -> Moves ()
pose creases = move (Pose creases)

-- | @repeat a[..b] [mirrored across [P, Q] | turned k\/4 about P]@. The two
-- 'Maybe's are the two optional clauses. 'TurnedQuarters' counts quarter
-- turns, and the checker refuses any count but 1, 2 or 3.
repeatSteps :: Ref StepK -> Maybe (Ref StepK) -> Maybe Isometry -> Moves ()
repeatSteps from to isometry = move (Repeat (refName from) (refName <$> to) isometry)

-- | @checkpoint \"path\" { … }@
checkpoint :: FilePath -> StackingSpec -> Moves ()
checkpoint path spec = move (Checkpoint path spec)

-- | @not modelled \"inside reverse fold\"@
notModelled :: Text -> Moves ()
notModelled what = move (NotModelled what)

-- | @expect refused KIND { move }@. It takes a 'Move' and not a body, because
-- the text allows exactly one move there, and a body could hold none or two.
expectRefused :: RefusalKind -> Move -> Moves ()
expectRefused kind inner = move (ExpectRefused kind inner)

-- | A fold that brings paper towards the reader.
valley :: Sense
valley = ValleyFold

-- | A fold that sends paper away, behind the model.
mountain :: Sense
mountain = MountainFold

-- | The text's other word for 'valley'. The tree stores only the sense, so a
-- sequence built with 'inFront' prints as @valley@.
inFront :: Sense
inFront = ValleyFold

-- | The text's other word for 'mountain'.
behind :: Sense
behind = MountainFold

-- | @all layers@
allLayers :: Layers
allLayers = AllLayers

-- | @top N layers@, counted from the side of the model the reader is looking
-- at. The checker refuses a count below 1.
topLayers :: Int -> Layers
topLayers = TopLayers

-- | @top flap@
topFlap :: Layers
topFlap = TopFlap

-- | @layers A above B@, for 'StartFolded' and 'checkpoint'
above :: Point -> Point -> Relation
above = LayerAbove

-- | @corner south-east@
cornerOf :: Corner -> Point
cornerOf = CornerOf

-- | @centre@
centre :: Point
centre = Centre

-- | @(u, v)@, in /sheet lengths/: the unfolded sheet's south-west corner is
-- @(0, 0)@ and its longer side is 1, so @at (1\/2) (1\/2)@ is the centre of
-- any square sheet. The numbers are exact, like the parser's:
-- @at (3\/4) (1\/4)@.
--
-- @at (1\/0) 0@ throws when forced, inside the author's own code, because
-- 'Rational' cannot hold it. No function here can turn that into a refusal,
-- and it is the one way building a sequence can go wrong.
at :: Rational -> Rational -> Point
at = AtSheet

-- | @P to Q@: the fold that lays P onto Q. Meant to be written infix,
-- @cornerOf SouthEast \`onto\` centre@.
onto :: Point -> Point -> Line
onto = Onto

-- | @edge west@
edge :: Compass -> Line
edge = EdgeOf

-- | A point named by 'mark' or 'letPoint'.
point :: Ref PointK -> Point
point (Ref name) = PointNamed name

-- | A line named by 'letLine'.
namedLine :: Ref LineK -> Line
namedLine (Ref name) = LineNamed name

-- | @hinge of NAME@: the line the named step turned paper about.
hingeOf :: Ref StepK -> Line
hingeOf (Ref name) = HingeOf name

-- | @crease of NAME@: the creases the named step made.
creaseOf :: Ref StepK -> Line
creaseOf (Ref name) = CreaseOf name

-- | @end of crease of NAME nearest P@
endOfCreaseOf :: Ref StepK -> Point -> Point
endOfCreaseOf (Ref name) = EndOfCreaseOf name
