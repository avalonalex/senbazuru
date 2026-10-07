-- |
-- Module      : Senbazuru.Sequence.Record
-- Description : What a run hands back for each move: the paper before and after, and the evidence that the move could be made.
--
-- A run folds a sheet one move at a time, and each move leaves one /move
-- record/ (see docs/glossary.md, "Fold sequences"); only @let@, @not
-- modelled@ and @expect refused@ leave none. So far the only move a record
-- can hold is a turn about a hinge; the header's last sections say what the
-- other moves will bring. Three
-- readers take records rather than the folded frames a run also writes: the
-- page of steps, which draws one arrow for each move; the material study,
-- which settles a move's paper as a sheet that bends; and the animated export.
-- A record is the one value all three read, so its shape is an agreement
-- between them, and this header is where that agreement is kept.
--
-- == What a record holds
--
-- Where the move sits: its step's number, name and caption, its place in the
-- step, and the move as the author wrote it ('recordOrigin'). Then the paper
-- itself: the folded surface just before the move and just after it, the
-- creases it turned about (its /hinge/), the paper that moved, named by the
-- point the author picked it out with (its /seed/) and by the faces that
-- point picked, and the one face beside the hinge that was held still. Last,
-- the evidence that the move was possible: for a turn about a hinge, the
-- library's check that the moving paper passes through no other paper on its
-- way.
--
-- Points and segments a record names on the paper are in /material
-- coordinates/, where the paper lay on the flat sheet before any folding (see
-- docs/glossary.md, "Geometry"). An author names paper by
-- where it was on the sheet, never by an id, and a material point stays the
-- same point of paper however the model is folded.
--
-- == Three rules a reader relies on
--
-- * __Unpresented.__ The surfaces are as folding computed them, with the face
--   the move held still lying where it lay before the move. Nothing about how
--   the model is shown on a page, turned over or spun, is applied to them.
--   This matters most to the material study. It reads which of two touching
--   faces lies on top by whether each face's normal points up, along +z, and
--   it solves for contact along +z; a model turned over for the page flips
--   every normal, so every above-and-below would be read the wrong way round.
-- * __One numbering.__ Both surfaces number faces and edges alike, so the ids
--   in 'recordHinge', 'recordMoving' and 'recordStationary' mean the same
--   paper in either. A turn about a hinge never cuts the paper, so it never
--   renumbers it.
-- * __Nothing stored twice.__ What the surfaces already hold is read from them:
--   the layer orders, and the crease angles ('recordAngles').
--
-- == Made only from a checked turn
--
-- The constructor and its fields are not exported. 'hingeTurn' makes a
-- record from a 'CheckedFlap', the library's proof that one turn about a
-- hinge passes through no paper, and takes both surfaces, the moving faces
-- and the face held still from that one turn. So no record can pair the paper
-- before one fold with the paper after another, and every record's evidence
-- describes the record's own move. The same reasoning made
-- 'Senbazuru.Sequence.Check.Checked' opaque.
--
-- Two parts are the runner's word, not the turn's: the hinge as stretches on
-- the sheet, and the seed. A turn does not say how its hinge edges group into
-- the author's fold line, layer by layer, nor which point the author named
-- the paper by; the runner, which resolved both, does.
--
-- == What is not here yet
--
-- The design sketches more fields than a turn about a hinge fills
-- (@PRDs\/decisions.md@, §5). Each arrives with the first move that fills it,
-- because a field nothing fills is a promise no test can check:
--
-- * the move's kind, once there is a second kind, the pre-crease;
-- * the creases a move adds, with the creasing that adds them;
-- * how the model is presented and where its anchor lies, before and after,
--   with @turn over@, @rotate@ and re-anchoring (owner decision 3);
-- * the stacking chosen, with layer-selective folds; the macro bindings, with
--   macro moves; and the references resolved and the cost, with the report
--   that prints them;
-- * a pose part-way along the move (@recordPoseAt@ in the design), with its
--   first reader, the material study's grips or the animated export;
-- * the evidence for moves that are not turns about a hinge: no motion, a
--   change of presentation, a state with no route, or a sampled macro move.
--
-- Four of the sketch's fields change. Its @recordLabel@, the step's caption
-- (@PRDs\/01-architecture.md@, §5.8), is 'recordCaption', the language's own
-- word for it. Its @recordPath@, the names a move sits under, is
-- 'recordStepName', a single name, since a step's own name is so far the only
-- one a move can sit under. Its @recordSpan@ is 'recordOrigin',
-- which keeps the move as the author wrote it beside the span, so that a
-- reader can quote the move and not only point at it. Its @recordStationary@,
-- a @Maybe@ pairing a face with a material point, is the face alone: every
-- turn about a hinge holds one face still, and the face's material
-- coordinates are in 'recordBefore'. It becomes a @Maybe@ again with the
-- first move that holds nothing still.
--
-- == The mistake to avoid
--
-- 'recordAfter' is the paper at the end of the move, but it is not where a
-- settle starts. The material study starts from 'recordBefore', a flat state
-- whose layer orders hold, and reaches the move's pose by holding and
-- gripping paper; a wing at 90° shares no plane with the body, so the
-- surface after the move has no layer orders between them to start from.
module Senbazuru.Sequence.Record
  ( -- * Paper named on the sheet
    MaterialPoint (..),
    MaterialSegment (..),

    -- * The record
    MoveRecord,
    recordStep,
    recordMoveIndex,
    recordStepName,
    recordCaption,
    recordOrigin,
    recordBefore,
    recordAfter,
    recordEvidence,
    recordHinge,
    recordMoving,
    recordStationary,
    recordAngles,
    RouteEvidence (..),

    -- * Making one
    hingeTurn,

    -- * A run
    Run (..),
    ExpectedRefusal (..),
    RunStop (..),
    runRefusal,
  )
where

import Data.Text (Text)
import Senbazuru.Fold.Types (EdgeId, FaceId, Frame (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Origami.Flap (CheckedFlap, FlapError, flapAt, flapMovingFaces, flapStationaryFace)
import Senbazuru.Origami.Surface (Surface, surfaceFrame)
import Senbazuru.Sequence.Elaborate (Origin)
import Senbazuru.Sequence.Error (MoveFailure (..), SequenceError (..))
import Senbazuru.Sequence.Syntax (Name, RefusalKind, Span)

-- | A point of paper, where it lay on the flat sheet before any folding.
newtype MaterialPoint = MaterialPoint V2
  deriving stock (Eq, Show)

-- | A straight stretch of paper between two material points, such as one
-- layer's part of a fold line.
data MaterialSegment = MaterialSegment !MaterialPoint !MaterialPoint
  deriving stock (Eq, Show)

-- | How a move is known to be possible. A value rather than a flag, because a
-- reader can do things with it: the page draws a turn part-way through from
-- the checked turn. A @newtype@ while a turn about a hinge is the only move;
-- the evidence for the others joins it as constructors (see the header).
newtype RouteEvidence
  = -- | A turn about a hinge, checked over its whole path: the moving paper
    -- passes through no other paper from start to end.
    SweptHinge CheckedFlap
  deriving stock (Eq, Show)

-- | One move of a run, as its readers take it. Made by 'hingeTurn'; the
-- header says what each part is for and what is still to come.
--
-- Its parts are read through the functions below, not through exported field
-- names: an exported field can be set by record update outside this module,
-- which would let anyone pair one turn's paper with another's.
data MoveRecord = MoveRecord
  { theStep :: !Int,
    theMoveIndex :: !Int,
    theStepName :: !(Maybe Name),
    theCaption :: !(Maybe Text),
    theOrigin :: !Origin,
    theBefore :: !(Surface V2),
    theAfter :: !(Surface V2),
    theEvidence :: !RouteEvidence,
    theHinge :: ![(MaterialSegment, [EdgeId])],
    theMoving :: ![(MaterialPoint, [FaceId])],
    theStationary :: !FaceId
  }
  deriving stock (Eq, Show)

-- | The step's number, counted from 1, as a refusal names it.
recordStep :: MoveRecord -> Int
recordStep = theStep

-- | The move's place in its step, counted from 1. A step such as \"fold and
-- unfold both diagonals\" holds more than one move.
recordMoveIndex :: MoveRecord -> Int
recordMoveIndex = theMoveIndex

-- | The step's name, if the author gave it one: what @unfold c1@ refers to.
recordStepName :: MoveRecord -> Maybe Name
recordStepName = theStepName

-- | The step's caption, if the author gave it one: what a page prints under
-- the step's picture.
recordCaption :: MoveRecord -> Maybe Text
recordCaption = theCaption

-- | The move as the author wrote it, and where.
recordOrigin :: MoveRecord -> Origin
recordOrigin = theOrigin

-- | The folded surface just before the move. Unpresented; the material study
-- starts here.
recordBefore :: MoveRecord -> Surface V2
recordBefore = theBefore

-- | The folded surface just after the move, numbered as 'recordBefore'. The
-- next record's 'recordBefore' is this surface again.
recordAfter :: MoveRecord -> Surface V2
recordAfter = theAfter

-- | How the move is known to be possible.
recordEvidence :: MoveRecord -> RouteEvidence
recordEvidence = theEvidence

-- | The hinge: each stretch of fold line on the sheet, with the edges of
-- 'recordBefore' that lie along it. A fold through several layers has one
-- stretch for each layer it creases. The runner's word: see 'hingeTurn'.
recordHinge :: MoveRecord -> [(MaterialSegment, [EdgeId])]
recordHinge = theHinge

-- | The paper that moved: each seed the author named it by, with the faces
-- that seed picked out. The faces are the turn's; the seed is the runner's.
recordMoving :: MoveRecord -> [(MaterialPoint, [FaceId])]
recordMoving = theMoving

-- | The face beside the hinge that was held still, which lies where it lay in
-- both surfaces.
recordStationary :: MoveRecord -> FaceId
recordStationary = theStationary

-- | Every crease's angle before the move and after it, in degrees as FOLD
-- writes them, one for each edge of 'recordBefore'. Read from the two
-- surfaces, which hold them already.
recordAngles :: MoveRecord -> ([Double], [Double])
recordAngles record = (angles (recordBefore record), angles (recordAfter record))
  where
    angles = edgesFoldAngle . surfaceFrame

-- | The record of a turn about a hinge, made from the checked turn itself.
--
-- The arguments are what only the runner knows: which move this is, its
-- step's name and caption, the move as written, the hinge the author's line
-- resolved to, and the seed the moving paper was picked out by. The paper
-- comes from the turn: the surfaces at its start and end, the faces it moves,
-- and the face it holds still.
--
-- A runner takes its next state from 'recordAfter' rather than asking the
-- turn for its end again: each surface costs one refold of the whole
-- pattern.
--
-- Fails only as 'flapAt' does, building one of the two surfaces.
hingeTurn ::
  -- | The step's number, from 1.
  Int ->
  -- | The move's place in its step, from 1.
  Int ->
  -- | The step's name, if it has one.
  Maybe Name ->
  -- | The step's caption, if it has one.
  Maybe Text ->
  -- | The move as written.
  Origin ->
  -- | The hinge, as stretches on the sheet with the edges along each.
  [(MaterialSegment, [EdgeId])] ->
  -- | The seed the moving paper was picked out by.
  MaterialPoint ->
  CheckedFlap ->
  Either FlapError MoveRecord
hingeTurn step move name caption origin hinge seed turn = do
  before <- flapAt turn 0
  after <- flapAt turn 1
  pure
    MoveRecord
      { theStep = step,
        theMoveIndex = move,
        theStepName = name,
        theCaption = caption,
        theOrigin = origin,
        theBefore = before,
        theAfter = after,
        theEvidence = SweptHinge turn,
        theHinge = hinge,
        theMoving = [(seed, flapMovingFaces turn)],
        theStationary = flapStationaryFace turn
      }

-- | What a run hands back: one record for each move it made, in order, and
-- each refusal a sequence expected and got. More arrives with the moves that
-- need it: the run's start and closing caption, and where a @not modelled@
-- move stopped it.
data Run = Run
  { runRecords :: [MoveRecord],
    -- | Each @expect refused@ whose move was refused as expected. It leaves
    -- no record, because it moved no paper, and this is where a reader such
    -- as @run --report@ finds it.
    runExpected :: [ExpectedRefusal],
    -- | Where the run stopped at @not modelled@, if it did. The records
    -- above are every move made before it.
    runStop :: Maybe RunStop
  }
  deriving stock (Eq, Show)

-- | A @not modelled@ move: its step, counted from 1, and the step's name, the
-- move's span, and its text. A run stops there and still succeeds, since a
-- failure could carry none of the states the author folded up to the gap
-- (PRDs\/decisions.md, D21).
data RunStop = RunStop
  { stopStep :: !Int,
    stopName :: !(Maybe Name),
    stopSpan :: !Span,
    stopText :: !Text
  }
  deriving stock (Eq, Show)

-- | What a run that stopped says on stopping, as a refusal: the message and
-- the place a caller prints, and the reason it exits nonzero, after writing
-- the states the run did make. 'Nothing' for a run that went to the end.
runRefusal :: Run -> Maybe SequenceError
runRefusal = fmap (\(RunStop n name at what) -> StepRefused n name at (NotModelledStop what)) . runStop

-- | An @expect refused@ that was refused as expected: its step and move,
-- counted from 1, and the kind.
data ExpectedRefusal = ExpectedRefusal
  { expectedStep :: !Int,
    expectedMove :: !Int,
    expectedKind :: !RefusalKind
  }
  deriving stock (Eq, Show)
