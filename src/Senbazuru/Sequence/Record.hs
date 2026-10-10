-- |
-- Module      : Senbazuru.Sequence.Record
-- Description : What a run hands back for each move: the paper before and after, and the evidence that the move could be made.
--
-- A run folds a sheet one move at a time, and each move leaves one /move
-- record/ (see docs/glossary.md, "Fold sequences"); only @let@, @not
-- modelled@ and @expect refused@ leave none. So far a record holds a turn
-- about a hinge, a pre-crease, which is such a turn checked and laid flat
-- again, a change of presentation, which moves no paper, or an @anchor P@,
-- which moves none either and holds other paper still ('MoveKind'); the
-- section \"What is not here yet\" says what the other moves will bring. Three
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
-- * __Unpresented.__ The surfaces are as folding computed them, with the
--   anchor's face lying where it lay on the sheet. Nothing about how the
--   model stands or is shown on a page, re-anchored, turned over or spun, is
--   applied to them; 'recordPlacement' and 'recordPresentation' say that,
--   and 'displayBefore' and 'displayAfter' put the two together.
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
-- 'Senbazuru.Sequence.Check.Checked' opaque. The two other makers,
-- 'presented' and 'anchoring', take a single surface for both, so they pair
-- nothing, and their evidence says that no paper moved.
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
-- * the stacking chosen, with layer-selective folds; the macro bindings, with
--   macro moves; and the cost;
-- * a pose part-way along the move (@recordPoseAt@ in the design), with its
--   first reader, the material study's grips or the animated export;
-- * the evidence for a state with no route, or a sampled macro move.
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
    MoveKind (..),
    Presenting (..),
    recordKind,
    recordStep,
    recordMoveIndex,
    recordStepName,
    recordCaption,
    recordOrigin,
    recordBefore,
    recordAfter,
    recordEvidence,
    recordHinge,
    recordNewCreases,
    recordAnchor,
    recordPresentation,
    recordPlacement,
    displayBefore,
    displayAfter,
    recordMoving,
    recordStationary,
    recordResolved,
    recordAngles,
    ResolvedReference (..),
    RouteEvidence (..),

    -- * Making one
    hingeTurn,
    asPrecrease,
    presented,
    anchoring,

    -- * A run
    Run (..),
    StepOutcome (..),
    ExpectedRefusal (..),
    RunStop (..),
    runRefusal,

    -- * Its states, as written
    WrittenState (..),
    writtenStates,

    -- * Its report
    renderRunReport,
  )
where

import Control.Monad (join, unless)
import Data.Aeson (Value, object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KM
import Data.IntMap.Strict qualified as IM
import Data.List (sort, sortOn)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showFFloat)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Query (assignmentAtRest)
import Senbazuru.Fold.Types (Assignment (..), EdgeId (..), FaceId (..), FaceOrder (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (Box (..), V2 (..), boxFromPoints, boxSize)
import Senbazuru.Geometry.Polygon (distanceToSegment, signedArea)
import Senbazuru.Geometry.Rigid (Rigid, applyRigid, identity)
import Senbazuru.Geometry.Rigid qualified as Rigid
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap (CheckedFlap, FlapError, flapAt, flapMovingFaces, flapStationaryFace)
import Senbazuru.Origami.Surface (Surface, materialFrame, materialU, materialV, surfaceFrame, surfaceSamples)
import Senbazuru.Sequence.Elaborate (Origin (..))
import Senbazuru.Sequence.Error (MoveFailure (..), SequenceError (..), WriteProblem (..))
import Senbazuru.Sequence.Pretty (prettyMove)
import Senbazuru.Sequence.Syntax (Name (..), PageAxis, RefusalKind (..), Span, Turning)

-- | A point of paper, where it lay on the flat sheet before any folding.
newtype MaterialPoint = MaterialPoint V2
  deriving stock (Eq, Show)

-- | A straight stretch of paper between two material points, such as one
-- layer's part of a fold line.
data MaterialSegment = MaterialSegment !MaterialPoint !MaterialPoint
  deriving stock (Eq, Show)

-- | How a move is known to be possible. A value rather than a flag, because a
-- reader can do things with it: the page draws a turn part-way through from
-- the checked turn. The evidence for the moves still to come joins these as
-- constructors (see the header).
data RouteEvidence
  = -- | A turn about a hinge, checked over its whole path: the moving paper
    -- passes through no other paper from start to end.
    SweptHinge CheckedFlap
  | -- | A change of how the model is shown, a turn-over or a rotate: no
    -- paper moved, so there was no path to check.
    Presented
  | -- | No paper moved and nothing was shown differently: @anchor P@, which
    -- changes only which paper is held still. There was no path to check.
    NoMotion
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
    theNewCreases :: ![(MaterialSegment, [EdgeId], Assignment)],
    theAnchor :: !(MaterialPoint, MaterialPoint),
    thePresentation :: !(Rigid, Rigid),
    thePlacement :: !(Rigid, Rigid),
    theKind :: !MoveKind,
    theMoving :: ![(MaterialPoint, [FaceId])],
    theStationary :: !FaceId,
    theResolved :: ![ResolvedReference]
  }
  deriving stock (Eq, Show)

-- | What kind of move a record is of: what a reader may take from its two
-- surfaces.
data MoveKind
  = -- | A turn about a hinge, a fold or the unfold of one: the paper ends
    -- where the turn left it.
    Turn
  | -- | A pre-crease (owner decision 14): the paper is folded along a line
    -- and laid flat again, so it ends where it began, creased along the
    -- line. Its record keeps the fold's evidence, which was checked over its
    -- whole path, and carries no sense, since a crease it draws has none.
    Precrease
  | -- | A change of presentation (decisions D5): the whole model is shown
    -- turned, and no paper moves. Its two surfaces are one; its presentation
    -- changes, and 'Presenting' says which turn the author wrote.
    Presentation Presenting
  | -- | @anchor P@ (PRDs\/02-language-semantics.md, §2.3): from now on the
    -- paper at P is held still, and no paper moves. Its two surfaces are
    -- one, held from the new anchor's face as a re-anchoring move's are
    -- ('recordPlacement').
    Anchoring
  deriving stock (Eq, Show)

-- | Which turn a change of presentation was, as written. Kept because the
-- two presentations a record holds cannot always say it: @k/8 turn
-- clockwise@ is the same motion as @(8 - k)/8 turn anticlockwise@, and a
-- half turn has no direction at all, yet a page draws the turn the author
-- wrote (PRDs\/06-prd-step-diagrams.md, \"Which turn a turn over or rotate
-- record was\").
data Presenting
  = -- | @turn over left-right@ or @top-bottom@: shown from the other side.
    TurnedOver PageAxis
  | -- | @rotate k/8 turn@: turned on the page by k eighths, the same side
    -- up.
    Rotated Int Turning
  deriving stock (Eq, Show)

-- | A reference as the run resolved it, for the report: the words the author
-- wrote, and what they named, in sheet lengths. A fold resolves two: its
-- line, and the point that names the paper it moves.
data ResolvedReference
  = -- | The fold line as written, where the paper lay when the move was
    -- made: through its point nearest the middle of the paper, pointing east,
    -- or north for a line running north-south, as a refusal shows a line.
    ResolvedLine Text V2 V2
  | -- | The words naming the moving paper, and the point of paper they named:
    -- a @moving@ point, an alignment fold's first argument, or for
    -- @L1 to L2@, the first line, which names its paper by a face beside it.
    ResolvedSeed Text V2
  | -- | For an @unfold@, the step whose move it turns back, and the step's
    -- name: an unfold of several steps makes a record for each.
    ResolvedTurnedBack Int (Maybe Name)
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

-- | What kind of move this is: a turn, or a pre-crease that ends where it
-- began.
recordKind :: MoveRecord -> MoveKind
recordKind = theKind

-- | The move as the author wrote it, and where.
recordOrigin :: MoveRecord -> Origin
recordOrigin = theOrigin

-- | The folded surface just before the move. Unpresented; the material study
-- starts here.
recordBefore :: MoveRecord -> Surface V2
recordBefore = theBefore

-- | The folded surface just after the move, numbered as 'recordBefore'. The
-- next record's 'recordBefore' is this surface again, unless the next move
-- creased the paper before it turned it: then its 'recordBefore' is this
-- paper with the new creases, lying at rest, and numbered afresh.
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

-- | The creases the move drew before it turned, where its line crossed paper
-- with no crease: each as a stretch on the sheet, the edges of 'recordBefore'
-- it became, and its letter, the move's sense from the coloured side. They
-- are already in 'recordBefore', at rest; the hinge lists them again with
-- any creases the line found already there.
recordNewCreases :: MoveRecord -> [(MaterialSegment, [EdgeId], Assignment)]
recordNewCreases = theNewCreases

-- | The anchor, the point of paper held still, before the move and after
-- it. The two differ when the move's new crease ran through the anchor,
-- which moved it off the crease to a face the move held still (decisions
-- C19), or when the move turned the anchor's paper, which moved it to the
-- paper the move holds still (owner decision 3). Neither moves any paper on
-- the page.
recordAnchor :: MoveRecord -> (MaterialPoint, MaterialPoint)
recordAnchor = theAnchor

-- | How the model was shown before the move and after it: the rigid motion
-- taking where the paper is folded to where the reader sees it (decisions
-- D5). The surfaces are never presented; a turn-over or a rotate changes
-- this and nothing else.
recordPresentation :: MoveRecord -> (Rigid, Rigid)
recordPresentation = thePresentation

-- | Where the anchor's face is placed for each surface, before and after:
-- the rigid motion from the surface, which folding computed with the
-- anchor's face lying where it lay on the sheet, to the model as it stands
-- before it is presented (decisions D14). It is the identity until a move
-- turns the anchor's paper. That move re-anchors before it turns, so both
-- its surfaces are computed from the new anchor's face and both halves are
-- the new placement; the change shows between the record before it and this
-- one, as the anchor's own change does ('recordAnchor').
recordPlacement :: MoveRecord -> (Rigid, Rigid)
recordPlacement = thePlacement

-- | How 'recordBefore' is shown: its placement, then its presentation. In
-- that order, because the presentation turns the model as it stands, and
-- the placement is what makes it stand there.
displayBefore :: MoveRecord -> Rigid
displayBefore r = fst (thePresentation r) `Rigid.after` fst (thePlacement r)

-- | How 'recordAfter' is shown, as 'displayBefore' is for 'recordBefore'.
displayAfter :: MoveRecord -> Rigid
displayAfter r = snd (thePresentation r) `Rigid.after` snd (thePlacement r)

-- | The paper that moved: each seed the author named it by, with the faces
-- that seed picked out. The faces are the turn's; the seed is the runner's.
recordMoving :: MoveRecord -> [(MaterialPoint, [FaceId])]
recordMoving = theMoving

-- | The face beside the hinge that was held still, which lies where it lay in
-- both surfaces.
recordStationary :: MoveRecord -> FaceId
recordStationary = theStationary

-- | The references the move resolved, in the order it resolved them: a
-- fold's line and moving paper, or the step an @unfold@ turns back.
recordResolved :: MoveRecord -> [ResolvedReference]
recordResolved = theResolved

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
  -- | The creases the move drew before it turned, with their edges and
  -- letters; none for a fold along creases the paper had.
  [(MaterialSegment, [EdgeId], Assignment)] ->
  -- | The anchor before the move and after it, the same unless the move's
  -- new crease ran through it.
  (MaterialPoint, MaterialPoint) ->
  -- | How the model is shown, which a turn about a hinge does not change.
  Rigid ->
  -- | Where the anchor's face is placed, which the turn does not change
  -- either: a move that turns the anchor's paper re-anchors before it turns.
  Rigid ->
  -- | The seed the moving paper was picked out by.
  MaterialPoint ->
  -- | The references the move resolved, for the report.
  [ResolvedReference] ->
  CheckedFlap ->
  Either FlapError MoveRecord
hingeTurn step move name caption origin hinge newCreases anchor shown placed seed resolved turn = do
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
        theNewCreases = newCreases,
        theAnchor = anchor,
        thePresentation = (shown, shown),
        thePlacement = (placed, placed),
        theKind = Turn,
        theMoving = [(seed, flapMovingFaces turn)],
        theStationary = flapStationaryFace turn,
        theResolved = resolved
      }

-- | A pre-crease's record from its fold's (owner decision 14): the fold was
-- checked over its whole path, and the paper is laid flat again, so the
-- record ends where it began and keeps the fold's evidence. Its new creases
-- were drawn without a direction, as the runner draws a pre-crease's.
asPrecrease :: MoveRecord -> MoveRecord
asPrecrease record = record {theKind = Precrease, theAfter = theBefore record}

-- | The record of a change of presentation, a turn-over or a rotate: the
-- paper as it lies, held still in both surfaces, shown one way before and
-- another after. No paper moved, so its evidence is that it was
-- 'Presented', it has no hinge and no moving paper, and the face it holds
-- still is the anchor's.
presented ::
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
  -- | Which turn it was.
  Presenting ->
  -- | The anchor, which a change of presentation does not move.
  MaterialPoint ->
  -- | The paper as it lies.
  Surface V2 ->
  -- | How it was shown before, and after.
  (Rigid, Rigid) ->
  -- | Where the anchor's face is placed, which a change of presentation does
  -- not change.
  Rigid ->
  MoveRecord
presented step move name caption origin turn anchor surface shown placed =
  MoveRecord
    { theStep = step,
      theMoveIndex = move,
      theStepName = name,
      theCaption = caption,
      theOrigin = origin,
      theBefore = surface,
      theAfter = surface,
      theEvidence = Presented,
      theHinge = [],
      theNewCreases = [],
      theAnchor = (anchor, anchor),
      thePresentation = shown,
      thePlacement = (placed, placed),
      theKind = Presentation turn,
      theMoving = [],
      theStationary = FaceId 0,
      theResolved = []
    }

-- | The record of @anchor P@: the paper as it lies, held from the new
-- anchor's face in both surfaces, as a re-anchoring move's are, so its
-- placement is the new one on both sides and the change shows against the
-- record before it, as the anchor's does. No paper moved, so its evidence is
-- 'NoMotion', it has no hinge and no moving paper, and the face it holds
-- still is the anchor's.
anchoring ::
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
  -- | The anchor before the move, and the point it names.
  (MaterialPoint, MaterialPoint) ->
  -- | The paper as it lies, held from the new anchor's face.
  Surface V2 ->
  -- | How it is shown.
  Rigid ->
  -- | Where the new anchor's face is placed.
  Rigid ->
  MoveRecord
anchoring step move name caption origin anchor surface shown placed =
  MoveRecord
    { theStep = step,
      theMoveIndex = move,
      theStepName = name,
      theCaption = caption,
      theOrigin = origin,
      theBefore = surface,
      theAfter = surface,
      theEvidence = NoMotion,
      theHinge = [],
      theNewCreases = [],
      theAnchor = anchor,
      thePresentation = (shown, shown),
      thePlacement = (placed, placed),
      theKind = Anchoring,
      theMoving = [],
      theStationary = FaceId 0,
      theResolved = []
    }

-- | What a run hands back: the state it started from, what each step did,
-- one record for each move it made, in order, each refusal a sequence
-- expected and got, and where a @not modelled@ move stopped it. With the
-- sequence's title and closing caption, this is all a written file needs.
data Run = Run
  { runTitle :: Maybe Text,
    -- | The sheet laid flat, before any move: state 0.
    runStart :: Surface V2,
    -- | How state 0 is shown: as it lies, or turned over for a sequence
    -- that starts white side up.
    runStartPresentation :: Rigid,
    -- | Each step the run finished, in order.
    runSteps :: [StepOutcome],
    runRecords :: [MoveRecord],
    -- | Each @expect refused@ whose move was refused as expected. It leaves
    -- no record, because it moved no paper, and this is where a reader such
    -- as @run --report@ finds it.
    runExpected :: [ExpectedRefusal],
    -- | The caption after the last step, for the state it ends at.
    runClosing :: Maybe Text,
    -- | Where the run stopped at @not modelled@, if it did. The records
    -- above are every move made before it.
    runStop :: Maybe RunStop
  }
  deriving stock (Eq, Show)

-- | What one step did: its number, counted from 1, its name and caption, and
-- the state it ends at, which it writes. A step whose moves were all
-- @expect refused@ moved no paper and writes no state, so it has none
-- (PRDs\/decisions.md, D24). Every other step writes one, even a step that
-- made no record, such as an @unfold@ of paper already flat: its state is
-- the one before it.
data StepOutcome = StepOutcome
  { outcomeStep :: !Int,
    outcomeName :: !(Maybe Name),
    outcomeCaption :: !(Maybe Text),
    outcomeEnd :: !(Maybe (Surface V2)),
    -- | How the state it ends at is shown.
    outcomePresentation :: !Rigid,
    -- | Where the anchor's face of the state it ends at is placed.
    outcomePlacement :: !Rigid
  }
  deriving stock (Eq, Show)

-- | A @not modelled@ move: its step, counted from 1, and the step's name, the
-- move's span, and its text. A run stops there and still succeeds, since a
-- failure could carry none of the states the author folded up to the gap
-- (PRDs\/decisions.md, D21).
data RunStop = RunStop
  { stopStep :: !Int,
    stopName :: !(Maybe Name),
    -- | The step's caption, which the last state written carries: it names
    -- the step that would have left that state.
    stopCaption :: !(Maybe Text),
    stopSpan :: !Span,
    stopText :: !Text
  }
  deriving stock (Eq, Show)

-- | What a run that stopped says on stopping, as a refusal: the message and
-- the place a caller prints, and the reason it exits nonzero, after writing
-- the states the run did make. 'Nothing' for a run that went to the end.
runRefusal :: Run -> Maybe SequenceError
runRefusal = fmap (\(RunStop n name _ at what) -> StepRefused n name at (NotModelledStop what)) . runStop

-- | An @expect refused@ that was refused as expected: its step and move,
-- counted from 1, and the kind.
data ExpectedRefusal = ExpectedRefusal
  { expectedStep :: !Int,
    expectedMove :: !Int,
    expectedKind :: !RefusalKind
  }
  deriving stock (Eq, Show)

-- | One state as a fold sequence's file writes it, and the step that
-- produced it: 'Nothing' for state 0, the sheet laid flat.
data WrittenState = WrittenState
  { stateStep :: !(Maybe Int),
    stateFrame :: !Frame
  }
  deriving stock (Eq, Show)

-- | Every state a run reached, as written frames, in order: state 0, the
-- start, then the end of each step that writes one. The writer writes these
-- and the page of steps will draw them, so the page shows exactly what the
-- file holds (PRDs\/02-language-semantics.md, §11).
--
-- Each frame follows the /state rule/ ('assignmentAtRest'): its creases are
-- lettered by the angle they are at, and an @F@ crease's angle is written as
-- exactly 0, so a reader testing for folded by @angle /= 0@ agrees with the
-- letter. It is @creasePattern@ only when every angle is 0 and every face
-- shows its top: its ring, in the sheet's winding, turning anticlockwise
-- where the face now lies. Any face turned over, or any fold, makes it a
-- @foldedForm@.
--
-- A state's @frame_title@ is the caption of the step that /leaves/ it, which
-- is where a book prints an instruction: next to the picture it starts from.
-- The last state's is the closing caption, or, for a run that stopped at
-- @not modelled@, the caption of the step it stopped at. Its
-- @senbazuru:assurance@ looks the other way, at the step that /produced/
-- it: each of that step's moves, and what checked it. State 0 has none,
-- which is not the same as having an empty one.
--
-- Positions are displayed, each state's by the placement and presentation
-- it ended with ('writtenFrame'). A state with the same faces as the state
-- before it numbers them as that state did ('numberedAsBefore').
writtenStates :: Run -> Either SequenceError [WrittenState]
writtenStates run = alike <$> sequence (zipWith3 write [0 ..] produced titles)
  where
    alike = \case
      [] -> []
      start : rest -> scanl (\previous st -> st {stateFrame = numberedAsBefore (stateFrame previous) (stateFrame st)}) start rest
    writing = [(outcome, end) | outcome <- runSteps run, Just end <- [outcomeEnd outcome]]
    -- State 0's anchor's face lies where it lay on the sheet: placed by the
    -- identity.
    produced = (Nothing, runStart run, runStartPresentation run) : [(Just outcome, end, outcomePresentation outcome `Rigid.after` outcomePlacement outcome) | (outcome, end) <- writing]
    titles = map (outcomeCaption . fst) writing ++ [maybe (runClosing run) stopCaption (runStop run)]
    write k (producer, surface, shown) title = case writtenFrame surface shown title (fmap (assurance . outcomeStep) producer) of
      Left problem -> Left (WriteRefused k problem)
      Right frame -> Right (WrittenState (fmap outcomeStep producer) frame)
    assurance n = toJSON [object ["move" .= recordMoveIndex record, "evidence" .= evidenceName (recordEvidence record)] | record <- runRecords run, recordStep record == n]
    evidenceName = \case
      SweptHinge _ -> "SweptHinge" :: Text
      Presented -> "Presented"
      NoMotion -> "NoMotion"

-- | A frame's faces numbered as the frame before it numbered them, when the
-- two have the same faces, each the same ring; otherwise the frame as it is.
-- Its layer orders are renumbered with them.
--
-- Re-anchoring puts the new anchor's face first, because folding holds the
-- first face still (owner decision 3), and so renumbers faces the paper did
-- not change. A reader pairing two states, as the page of steps does to find
-- what moved, needs one face to keep one number, as a vertex does
-- (PRDs\/decisions.md, D6). Creasing changes the faces themselves, and
-- leaves the frame as it is. A frame numbered as before already is left
-- exactly as it is, so a run that never re-anchors writes what it wrote.
numberedAsBefore :: Frame -> Frame -> Frame
numberedAsBefore previous frame
  | sort now == sort before, M.size there == length before = frame {facesVertices = before, faceOrders = map renumbered (faceOrders frame)}
  | otherwise = frame
  where
    now = facesVertices frame
    before = facesVertices previous
    there = M.fromList (zip before [0 :: Int ..])
    moved = IM.fromList [(i, j) | (i, ring) <- zip [0 ..] now, Just j <- [M.lookup ring there]]
    renumbered o = o {orderFace = to (orderFace o), orderRelativeTo = to (orderRelativeTo o)}
    to (FaceId f) = FaceId (IM.findWithDefault f f moved)

-- | One surface as a written frame, shown as the reader sees it: the state
-- rule, the class, the caption and the two vendor keys. Nothing of the
-- sheet's own frame is kept but its unit: its extras, attributes, author and
-- description described the sheet, and would be stale on a state folded from
-- it.
--
-- Written frames are displayed (decisions D5, D14): each vertex placed, then
-- presented, so a state after a turn-over is written turned over, its faces
-- showing their backs, and one after a re-anchoring stands where the model
-- stood before it. A display that is the identity leaves the coordinates
-- exactly as folded, so a run with no turn-over, rotate or re-anchoring
-- onto moved paper writes what it always wrote.
writtenFrame :: Surface V2 -> Rigid -> Maybe Text -> Maybe Value -> Either WriteProblem Frame
writtenFrame surface shown title assurance = do
  let folded = materialFrame surface
      base
        | shown == identity = folded
        | otherwise = folded {verticesCoords = [let V3 x y z = applyRigid shown (V3 a b c) in [x, y, z] | a : b : rest <- verticesCoords folded, let c = case rest of z : _ -> z; [] -> 0]}
      angles = edgesFoldAngle base
      edgeCount = length (edgesVertices base)
      letters = case edgesAssignment base of
        [] -> replicate edgeCount Unassigned
        given -> given
      written = zipWith assignmentAtRest letters angles
      writtenAngles = zipWith (\letter angle -> if letter == Flat then 0 else angle) written angles
      placed = IM.fromList (zip [0 ..] [V2 x y | x : y : _ <- verticesCoords base])
      showsTop ring = signedArea [p | VertexId v <- ring, Just p <- [IM.lookup v placed]] > 0
      flat = all (== 0) writtenAngles && all showsTop (facesVertices base)
  unless (length angles == edgeCount) (Left (WriteMissingAngles edgeCount (length angles)))
  -- The material coordinates go into a vendor key through toJSON, where a
  -- NaN would become null before the encoder could refuse it.
  case [(v, x) | (v, sample) <- zip [0 :: Int ..] (surfaceSamples surface), x <- [materialU sample, materialV sample], isNaN x || isInfinite x] of
    (v, x) : _ -> Left (WriteNonFinite ("senbazuru:material_coords[" <> tshow v <> "]") x)
    [] -> Right ()
  pure
    base
      { frameTitle = title,
        frameAuthor = Nothing,
        frameDescription = Nothing,
        frameAttributes = [],
        frameParent = Nothing,
        frameInherit = False,
        frameClasses = [if flat then "creasePattern" else "foldedForm"],
        edgesAssignment = written,
        edgesFoldAngle = writtenAngles,
        frameExtras = KM.fromList ([(key, value) | key <- ["senbazuru:material_coords"], Just value <- [KM.lookup key (frameExtras base)]] ++ [("senbazuru:assurance", value) | Just value <- [assurance]])
      }

-- | What a run did, one fact to a line, for a person to read: each move
-- under a heading of where it is and the move as the printer spells it,
-- canonical words and all, then what checked it, what its references named,
-- the paper it moved, its hinge and the face it held still; each refusal a
-- sequence expected, which has no record and is found only here; and where
-- the run stopped, if it did. In step order, a step's moves in theirs.
--
-- Ids are the run's own, written @(internal edge 8)@, so an author knows they
-- did not write them (PRDs\/decisions.md, D20). They number the paper as the
-- run held it for that move; after a re-anchoring that is not how the
-- written states number their faces ('numberedAsBefore'). Numbers are
-- rounded to six places, which rounds away the last bits in which platforms
-- differ; only a value lying on a rounding boundary could still print
-- differently.
renderRunReport :: Run -> [Text]
renderRunReport run = concatMap entry (sortOn place entries) ++ stopped
  where
    entries = [(recordStep r, recordMoveIndex r, Left r) | r <- runRecords run] ++ [(expectedStep e, expectedMove e, Right e) | e <- runExpected run]
    place (n, i, _) = (n, i)
    names = [(outcomeStep o, outcomeName o) | o <- runSteps run] ++ [(stopStep s, stopName s) | Just s <- [runStop run]]
    heading n name i written = "step " <> tshow n <> maybe "" (\(Name x) -> " (" <> x <> ")") name <> ", move " <> tshow i <> ": " <> written
    entry (_, _, Left r) = heading (recordStep r) (recordStepName r) (recordMoveIndex r) (prettyMove (originWritten (recordOrigin r))) : map ("  " <>) (facts r)
    entry (n, i, Right e) =
      let RefusalKind kind = expectedKind e
       in [heading n (join (lookup n names)) i ("expect refused " <> kind), "  refused as " <> kind <> ", as expected; nothing moved"]
    facts r =
      [checked r]
        ++ map resolvedFact (recordResolved r)
        ++ map newCrease (recordNewCreases r)
        ++ ["laid flat again: the paper ends where it began" | recordKind r == Precrease]
        ++ [ "anchor moved: " <> point (sheetLengths a) <> " to " <> point (sheetLengths b) <> why
             | let (MaterialPoint a, MaterialPoint b) = recordAnchor r,
               a /= b,
               let why
                     | recordKind r == Anchoring = ", where the move names it"
                     | any (\(MaterialSegment (MaterialPoint p) (MaterialPoint q), _, _) -> distanceToSegment (sheetLengths p, sheetLengths q) (sheetLengths a) <= 1e-9) (recordNewCreases r) = ", off the new crease"
                     | otherwise = ", off the paper the move turns"
           ]
        ++ [ line
             | turned (recordEvidence r),
               line <- ["moving: " <> internal "face" [f | (_, faces) <- recordMoving r, FaceId f <- faces], "hinge: " <> internal "edge" [e | (_, edges) <- recordHinge r, EdgeId e <- edges], "held still: " <> internal "face" [let FaceId f = recordStationary r in f]]
           ]
    checked r = case (recordEvidence r, recordKind r) of
      (SweptHinge _, _) -> "checked: the whole turn, swept, with no paper in its way"
      (Presented, Presentation (Rotated _ _)) -> "presented: the whole model turned on the page, the same side up; no paper moved"
      (Presented, _) -> "presented: the whole model shown from its other side; no paper moved"
      (NoMotion, _) -> "nothing turned: no paper moved"
    turned = \case
      SweptHinge _ -> True
      _ -> False
    resolvedFact = \case
      ResolvedLine written p d -> "line " <> written <> ": through " <> point p <> ", along " <> point d
      ResolvedSeed written p -> "named by " <> written <> ": the paper at " <> point p
      ResolvedTurnedBack n name -> "turns back: step " <> tshow n <> maybe "" (\(Name x) -> " (" <> x <> ")") name
    -- A new crease is kept on the sheet in the file's own coordinates, as
    -- the hinge is; the report gives every point in sheet lengths, the
    -- author's units, as the line and the seed already are.
    newCrease (MaterialSegment (MaterialPoint a) (MaterialPoint b), edges, letter) =
      "new crease: " <> point (sheetLengths a) <> " to " <> point (sheetLengths b) <> ", " <> letterWord letter <> " " <> internal "edge" [e | EdgeId e <- edges]
    -- Measured on the sheet the run started from: from its box's lower
    -- corner, in its longer side, as "Senbazuru.Sequence.Resolve" measures.
    sheetLengths p = case boxFromPoints [V2 (materialU s) (materialV s) | s <- surfaceSamples (runStart run)] of
      Just box ->
        let V2 w h = boxSize box
            V2 x0 y0 = boxMin box
            V2 x y = p
            side = max w h
         in if side > 0 then V2 ((x - x0) / side) ((y - y0) / side) else p
      Nothing -> p
    letterWord = \case
      Mountain -> "mountain"
      Valley -> "valley"
      Unassigned -> "unassigned"
      other -> tshow other
    internal noun ids = "(internal " <> noun <> (if length ids == 1 then "" else "s") <> " " <> T.intercalate ", " (map tshow ids) <> ")"
    point (V2 x y) = "(" <> decimal x <> ", " <> decimal y <> ")"
    stopped = ["stopped: " <> explain refusal | Just refusal <- [runRefusal run]]

-- | A number rounded to six places, with no trailing zeros and no negative
-- zero: the same text on every platform.
decimal :: Double -> Text
decimal x =
  let rounded = fromIntegral (round (x * 1e6) :: Integer) / 1e6 :: Double
      shown = T.pack (showFFloat Nothing (if rounded == 0 then 0 else rounded) "")
   in fromMaybe shown (T.stripSuffix ".0" shown)
