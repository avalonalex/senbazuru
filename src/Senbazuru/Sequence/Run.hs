-- |
-- Module      : Senbazuru.Sequence.Run
-- Description : Running a fold sequence: the state it threads from move to move, and where that state starts.
--
-- A run performs a checked sequence one move at a time. Between moves it
-- holds a /fold state/ (see docs/glossary.md, "Fold sequences"): the paper as
-- the next move will find it. A finished run hands back move records
-- ("Senbazuru.Sequence.Record") and never the state itself, so no reader of a
-- run can come to depend on how the runner keeps its paper. 'FoldState' is
-- opaque for the same reason.
--
-- 'sheetState' turns a sheet, a file's key frame, into the state a run begins
-- from, and 'runSequence' runs a checked, elaborated sequence from there. So
-- far it makes the moves the blintz needs: @fold@ along creases the paper
-- already has, its line given by points or as @hinge of NAME@, @unfold@, and
-- @expect refused@. Every other move is refused as not run yet, naming
-- itself, rather than skipped.
--
-- An @expect refused K { move }@ runs its move against the current state and
-- requires a refusal of kind K ('Senbazuru.Sequence.Error.refusalKindOf'). It
-- leaves the state as it was and no record, since it moved no paper; the run
-- keeps the outcome. A move that is made instead, or refused as another kind,
-- refuses the run. A move not run yet says nothing about the paper, so its
-- refusal is passed on as itself.
--
-- == A fold, move by move
--
-- 1. Fold the working pattern from its angles, and name paper on the result
--    ("Senbazuru.Sequence.Resolve"): the fold line where the paper now lies,
--    the creases along it, and the seed, which is @moving P@ or, for an
--    alignment fold such as @P to Q@, its first point.
-- 2. Take the flap containing the seed, and the creases along the line that
--    border it, as the hinge.
-- 3. Turn @valley@ or @mountain@ into a direction from the reader's side:
--    @valley@ is in front, towards the reader, which is +z with the coloured
--    side up and -z with the white side up.
-- 4. Check the turn over its whole path ("Senbazuru.Origami.Flap"), and make
--    the move's record from the checked turn.
-- 5. Hand on: write the accepted angles and layer orders onto the working
--    pattern, never the folded coordinates, fold it afresh, and check that
--    the paper landed where the checked turn left it. A rigid jump between
--    two individually checked moves would otherwise pass unseen.
--
-- An @unfold@ reuses each named move's recorded hinge and seed, last move
-- first, and turns its hinge back by that move's change of angle. It is
-- refused if a later move changed one of those creases, and skips a move
-- whose creases all lie flat already. One that turns back several moves makes
-- a record for each, all at the unfold's own step and move, in the order it
-- turned them.
--
-- == Not yet
--
-- A fold that would carry the anchor's paper re-anchors (owner decision 3);
-- until that is built it is refused as not run yet, as are new creases,
-- layer words and every move but @fold@ and @unfold@.
--
-- == What a fold state holds
--
-- The /working pattern/: the sheet's crease pattern, cut at every crossing,
-- with its vertices in material coordinates, where the paper lay on the flat
-- sheet. Folding never changes those coordinates; a move changes only the
-- crease angles and the layer orders written on the pattern, and the pattern
-- is folded afresh from them. Folded coordinates fed back as material would
-- fold the paper a second time.
--
-- And the /anchor/: the point of paper that stays still while the rest of the
-- paper moves, so that a model does not wander across the page from one
-- picture to the next. It is a material point, not a face id, because ids do
-- not survive the cutting a new crease makes.
--
-- == How a sheet becomes a starting state
--
-- * __The key frame only.__ A sheet is the paper before any folding. A key
--   frame with no vertices belongs to a file of folded states, and one that
--   leaves the plane, or calls itself a folded form, is folded already; both
--   are refused.
-- * __Flat.__ Every crease starts at angle 0, whatever angle the file wrote:
--   @examples\/blintz-base.fold@ records its four corners folded in, and a
--   blintz sequence must not start already folded. (Starting from the file's
--   angles is @start folded@, a later milestone.)
-- * __Intent kept.__ A crease keeps the letter it was drawn with, M or V,
--   though it now lies flat. That departs from "a valley at angle 0 is not a
--   valley", on purpose: the library turns only an M, V or U crease, and a
--   later move needs to know which way a crease was made. It is safe because
--   folding reads angles before letters, and a crease at 0 orders no layers.
--   An F crease the file drew at a nonzero angle contradicts itself, since F
--   means unfolded, so its angle is believed: M below 0, V above. A U crease
--   stays U whatever its angle, since U says only that the direction is
--   undecided, and the runner must not invent a direction nobody gave.
-- * __Clean.__ Layer orders and unknown keys are dropped, since nothing has
--   been stacked yet. Faces are cut at crossings and traced where the file
--   has none, and every face's ring runs anticlockwise on the sheet, so that a
--   face's normal points the way the file's +z does.
-- * __The anchor, by default.__ The vertex mean, the average of the corners,
--   of the largest face, ties to the lowest and then the leftmost vertex mean,
--   a tie being close enough that rounding could have made the difference.
--   That face is put first, because folding holds its first face still. A
--   vertex mean of a face that is not convex can lie outside it, and is
--   refused: the author names the anchor instead.
--
-- == The number that looks arbitrary
--
-- "Flat" for a crease's letter means within 'atRest', 1e-10 degrees, of 0:
-- the same threshold 'Senbazuru.Origami.Surface' uses to decide which creases
-- a bent surface keeps, so the two cannot disagree about a crease.
module Senbazuru.Sequence.Run
  ( -- * The state a run threads
    FoldState,
    workingPattern,
    stateAnchor,

    -- * Starting
    sheetState,
    squareSheet,

    -- * Running
    RunSettings (..),
    defaultRunSettings,
    runSequence,
  )
where

import Control.Monad (foldM, unless, when)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (find, sort, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Faces (sheetOf, tolerance)
import Senbazuru.Fold.Query (FrameKind (..), atRest, frameKind, frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (centroid, insideRing, signedArea)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, modelSpan, zSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flap (CheckedFlap, FlapError, Toward (..), checkFlap, prepareFlapAlong, prepareFlapToward)
import Senbazuru.Origami.Folding (Folded (..), FoldingError, foldFrameWith)
import Senbazuru.Origami.HingeSweep (SweepSettings, defaultSweepSettings)
import Senbazuru.Origami.Surface (Surface, surfaceFrame, surfaceFromFolded)
import Senbazuru.Sequence.Elaborate (Core (..), CoreMove (..), Elaborated (..), ElaboratedStep (..), Origin (..))
import Senbazuru.Sequence.Error (FoldedBy (..), MoveFailure (..), Place (..), ResolveProblem (..), SelectionError (..), SequenceError (..), SheetProblem (..), refusalKindOf)
import Senbazuru.Sequence.Pretty (prettyLine, prettyPoint)
import Senbazuru.Sequence.Record
import Senbazuru.Sequence.Resolve
import Senbazuru.Sequence.Syntax (Amount (..), Header (..), Layers (..), Line (..), Located (..), Name, Point, Sense (..), SheetSource (..), Side (..), Start (..))

-- | The paper between two moves of a run: the working pattern and the anchor.
-- Opaque; the header says what each is and why.
data FoldState = FoldState
  { theWorking :: !Frame,
    theAnchor :: !MaterialPoint,
    -- | Which way the reader's side faces: in front, where a valley fold
    -- sends its paper.
    theFront :: !Toward,
    -- | The working pattern folded, when the last move's join check has
    -- folded it already: the next move starts from that fold rather than
    -- folding the same pattern again.
    theFold :: !(Maybe Folded),
    -- | The sheet's faces in its own order, wound anticlockwise: the order
    -- an anchor named in the header reorders from, once, so that every face
    -- but the anchor's keeps the sheet's numbering.
    theSheetFaces :: ![[VertexId]]
  }
  deriving stock (Eq, Show)

-- | The working pattern: the sheet's creases cut at every crossing, its
-- vertices in material coordinates, the anchor's face first.
workingPattern :: FoldState -> Frame
workingPattern = theWorking

-- | The anchor: the point of paper that stays still.
stateAnchor :: FoldState -> MaterialPoint
stateAnchor = theAnchor

-- | The state a run starts from, given the file the header's @sheet@ names:
-- its key frame laid flat, with its creases' letters kept, its faces traced
-- and wound anticlockwise, and the largest face's vertex mean as the anchor.
-- The header says why each.
sheetState :: FoldFile -> Either SheetProblem FoldState
sheetState file = do
  let key = keyFrame file
  points <- first SheetNotAPattern (frameVertices key)
  when (null points) (Left (SheetHasNoVertices (length (otherFrames file))))
  case frameKind (frameClasses key) points of
    FoldedForm -> Left (SheetAlreadyFolded (if hasRelief points then ByRelief (zSpan points) else ByClass))
    CreasePattern -> pure ()
  planar <- first SheetNotAPattern (withPlanarFaces key {faceOrders = [], frameExtras = mempty})
  material <- first SheetNotAPattern (IM.fromList . zip [0 ..] . map flat <$> frameVertices planar)
  room <- first SheetNotAPattern (tolerance <$> sheetOf planar)
  let ring face = [p | VertexId i <- face, Just p <- [IM.lookup i material]]
      faces = [if signedArea (ring face) < 0 then reverse face else face | face <- facesVertices planar]
      measured = [(i, face, abs (signedArea (ring face)), centroid (ring face)) | (i, face) <- zip [0 :: Int ..] faces]
  (index, anchor) <- case defaultAnchor room measured of
    Just (i, face, _, mean)
      | insideRing room (ring face) mean -> Right (i, mean)
      | otherwise -> Left (DefaultAnchorOutside mean)
    Nothing -> Left SheetHasNoFaces
  let angles = edgesFoldAngle planar
      letters = zipWith intent (edgesAssignment planar) (angles ++ repeat 0)
  pure
    FoldState
      { theWorking =
          planar
            { edgesAssignment = letters,
              edgesFoldAngle = map (const 0) letters,
              facesVertices = firstOf index faces
            },
        theAnchor = MaterialPoint anchor,
        theFront = TowardPlusZ,
        theFold = Nothing,
        theSheetFaces = faces
      }
  where
    flat (V3 x y _) = V2 x y
    -- An F crease at an angle has its angle believed; every other letter is
    -- kept as drawn, U included.
    intent letter angle = case letter of
      Flat
        | angle < negate atRest -> Mountain
        | angle > atRest -> Valley
      _ -> letter

-- | The face whose vertex mean is the default anchor, numbered, with its area
-- and vertex mean: the largest face, and among faces of one area the lowest
-- vertex mean and then the leftmost. A tie is a billionth of the largest area,
-- or the sheet's own tolerance in a height or a distance across, so that a
-- rounding error in an area or a mean cannot decide one. 'Nothing' for a
-- sheet with no faces.
defaultAnchor :: Double -> [(Int, [VertexId], Double, V2)] -> Maybe (Int, [VertexId], Double, V2)
defaultAnchor room measured = case measured of
  [] -> Nothing
  _ ->
    let biggest = maximum [area | (_, _, area, _) <- measured]
        largest = [m | m@(_, _, area, _) <- measured, area >= biggest - 1e-9 * biggest]
        lowest = minimum [y | (_, _, _, V2 _ y) <- largest]
        low = [m | m@(_, _, _, V2 _ y) <- largest, y <= lowest + room]
        leftmost = minimum [x | (_, _, _, V2 x _) <- low]
     in find (\(_, _, _, V2 x _) -> x <= leftmost + room) low

-- | The list with its @i@th item moved to the front: the anchor's face put
-- first, since folding holds its first face still.
firstOf :: Int -> [a] -> [a]
firstOf i xs = [x | (j, x) <- zip [0 ..] xs, j == i] ++ [x | (j, x) <- zip [0 ..] xs, j /= i]

-- | The sheet @sheet square@ names: the unit square, its four corners
-- anticlockwise from the origin, four border edges and one face.
squareSheet :: FoldFile
squareSheet =
  FoldFile
    { fileSpec = Just 1.2,
      fileCreator = Nothing,
      fileAuthor = Nothing,
      fileTitle = Nothing,
      fileDescription = Nothing,
      fileClasses = [],
      keyFrame =
        emptyFrame
          { frameClasses = ["creasePattern"],
            verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1]],
            edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 0)]],
            edgesAssignment = replicate 4 Border,
            facesVertices = [map VertexId [0, 1, 2, 3]]
          },
      otherFrames = []
    }

-- | How a run checks its moves.
data RunSettings = RunSettings
  { -- | How finely a turn's path is checked ("Senbazuru.Origami.HingeSweep").
    runSweep :: !SweepSettings,
    -- | How near a vertex, in sheet lengths, a typed point is refused as a
    -- near miss: 1e-3 by owner decision 2.
    runNearMissBand :: !Double
  }

-- | The settings a run uses unless told otherwise.
defaultRunSettings :: RunSettings
defaultRunSettings = RunSettings defaultSweepSettings 1e-3

-- | Run a checked, elaborated sequence against its sheet, handed over keyed by
-- the path the header writes, and give back a record for each move. Pure:
-- the caller reads the files. The first move refused ends the run, and no
-- part of a refused run comes back.
runSequence :: RunSettings -> Map FilePath FoldFile -> Elaborated -> Either SequenceError Run
runSequence settings sheets elaborated = do
  let header = elaboratedHeader elaborated
  (start, startSurface) <- startOf sheets header
  let go progress = \case
        [] -> Right (progress, Nothing)
        step : rest ->
          runStep settings progress step >>= \case
            Going next -> go next rest
            Stopped at stop -> Right (at, Just stop)
  (Progress _ made _ expected _ outcomes, stop) <- go (Progress start [] M.empty [] startSurface []) (zip [1 ..] (elaboratedSteps elaborated))
  pure
    Run
      { runTitle = hTitle header,
        runStart = startSurface,
        runSteps = reverse outcomes,
        runRecords = reverse made,
        runExpected = reverse expected,
        runClosing = hClosing header,
        runStop = stop
      }

-- | A run so far: the state, the records made (latest first), each named
-- step's records for a later @unfold@ or @hinge of@, the refusals expected
-- and got (latest first), the surface the paper is at, and each finished
-- step's outcome (latest first).
data Progress = Progress !FoldState ![MoveRecord] !(Map Name [MoveRecord]) ![ExpectedRefusal] !(Surface V2) ![StepOutcome]

-- | The state the header describes: its sheet, laid flat, anchored at its
-- @anchor@ point or by default, with its side up; and that state as a
-- surface, state 0 of what the run writes.
startOf :: Map FilePath FoldFile -> Header -> Either SequenceError (FoldState, Surface V2)
startOf sheets header = do
  let Located at source = hSheet header
      path = case source of
        UnitSquare -> "square"
        SheetFile written -> written
      refuse = Left . SheetRefused at path
  file <- case source of
    UnitSquare -> Right squareSheet
    SheetFile written -> maybe (refuse SheetNotLoaded) Right (M.lookup written sheets)
  case locValue (hStart header) of
    StartFolded _ -> refuse StartFoldedNotRunYet
    StartFlat -> Right ()
  laid <- first (SheetRefused at path) (sheetState file)
  anchored <- case hAnchor header of
    Nothing -> Right laid
    Just (Located anchorAt point) -> do
      folded <- first (SheetRefused at path . SheetDoesNotFold) (foldFrameWith (theWorking laid))
      let refuseAnchor = ResolveRefused InHeader anchorAt (prettyPoint point)
      flat <- first refuseAnchor (flatState folded)
      m <- first refuseAnchor (materialPoint flat point)
      FaceId face <- first refuseAnchor (regionFace flat m)
      -- The face is found in the default anchor's order; it goes first, and
      -- the rest follow in the sheet's own order, so that the default's
      -- reordering does not linger in them.
      let chosen = take 1 (drop face (facesVertices (theWorking laid)))
      Right laid {theWorking = (theWorking laid) {facesVertices = chosen ++ filter (`notElem` chosen) (theSheetFaces laid)}, theAnchor = MaterialPoint m, theFold = Nothing}
  folded <- first (SheetRefused at path . SheetDoesNotFold) (foldNow anchored)
  surface <- first (SheetRefused at path . SheetNoSurface) (surfaceFromFolded folded)
  Right (anchored {theFront = if hSide header == WhiteUp then TowardMinusZ else TowardPlusZ, theFold = Just folded}, surface)

-- | Where a step leaves a run: going on, or stopped at a @not modelled@
-- move with everything made before it, the step's own earlier moves included.
data Outcome = Going Progress | Stopped Progress RunStop

-- | One step: its moves in order, each from the state the last one left. The
-- records it made are kept under its name, for a later @unfold@.
--
-- A @not modelled@ move comes back from 'runMove' as the refusal it will be
-- printed as, and is the one refusal that ends a run without failing it: an
-- @expect refused@ around it passes it on, since it names no paper.
runStep :: RunSettings -> Progress -> (Int, ElaboratedStep) -> Either SequenceError Outcome
runStep settings (Progress state done named expected surface outcomes) (n, step) = go state [] [] (zip [1 ..] (elaboratedMoves step))
  where
    go st made got = \case
      [] -> Right (Going (progress st made got (outcome made : outcomes)))
      (i, CoreMove origin core) : rest -> case runMove settings (Here n (elaboratedName step) (elaboratedCaption step) i origin) named st core of
        Left (StepRefused _ _ at (NotModelledStop what)) -> Right (Stopped (progress st made got outcomes) (RunStop n (elaboratedName step) (elaboratedCaption step) at what))
        Left err -> Left err
        Right (Made st' records refused) -> go st' (made ++ records) (got ++ refused) rest
    progress st made got = Progress st (reverse made ++ done) (maybe named (\name -> M.insert name made named) (elaboratedName step)) (reverse got ++ expected) (after made)
    -- Where the paper is once the step is done: its last record's end, or
    -- where it was, for a step that made none.
    after made = case reverse made of
      record : _ -> recordAfter record
      [] -> surface
    -- A step of nothing but expect refused moved no paper, and writes no
    -- state (PRDs/decisions.md, D24).
    outcome made = StepOutcome n (elaboratedName step) (elaboratedCaption step) (if all expectation (elaboratedMoves step) then Nothing else Just (after made))
    expectation (CoreMove _ core) = case core of
      CoreExpectRefused {} -> True
      _ -> False

-- | What one move made: the state after it, its records, and the refusal it
-- expected and got, for an @expect refused@.
data Made = Made !FoldState ![MoveRecord] ![ExpectedRefusal]

-- | Where a move is, for its records and its refusals.
data Here = Here
  { placeStep :: !Int,
    placeName :: !(Maybe Name),
    placeCaption :: !(Maybe Text),
    placeMove :: !Int,
    placeOrigin :: !Origin
  }

runMove :: RunSettings -> Here -> Map Name [MoveRecord] -> FoldState -> Core -> Either SequenceError Made
runMove settings place named state = \case
  CoreFold sense amount line layers seed -> moved <$> foldMove settings place named state sense amount line layers seed
  CoreUnfold names -> moved <$> foldM (undoOne settings place) (state, []) (reverse (concat [M.findWithDefault [] name named | name <- names]))
  -- The inner move runs against this state, and must be refused as the kind
  -- given; it leaves the state as it was and no record, since it moved no
  -- paper. A move not run yet says nothing about the paper, so its refusal
  -- is passed on as itself.
  CoreExpectRefused kind inner -> case inner of
    Nothing -> Left (refusedAt place (RefusalNotRaised kind))
    Just (CoreMove origin core) -> case runMove settings place {placeOrigin = origin} named state core of
      Right _ -> Left (refusedAt place (RefusalNotRaised kind))
      Left err -> case refusalKindOf err of
        Just raised
          | raised == kind -> Right (Made state [] [ExpectedRefusal (placeStep place) (placeMove place) kind])
          | otherwise -> Left (refusedAt place (RefusedDifferently kind raised))
        Nothing -> Left err
  CoreNotModelled what -> Left (refusedAt place (NotModelledStop what))
  other -> Left (refusedAt place (MoveNotRunYet (moveWords other)))
  where
    moved (st, records) = Made st records []

-- | A fold along creases the paper has, as the header lays out.
foldMove :: RunSettings -> Here -> Map Name [MoveRecord] -> FoldState -> Sense -> Amount -> Line -> Layers -> Maybe Point -> Either SequenceError (FoldState, [MoveRecord])
foldMove settings place named state sense amount line layers seed = do
  folded <- first (refusedAt place . FoldingRefused) (foldNow state)
  flat <- first (resolvingAt place (prettyLine line)) (flatState folded)
  -- @hinge of NAME@ is the line the named step's one move turned about: the
  -- recorded crease, where the paper now lies, numbered as now since no move
  -- yet cuts the paper.
  foldAt <- first (resolvingAt place (prettyLine line)) $ case line of
    HingeOf name -> case M.findWithDefault [] name named of
      [earlier] -> case concatMap snd (recordHinge earlier) of
        e : _ -> lineAlong flat e
        [] -> Left NoSolution
      records -> Left (HingeOfNotOneMove name (length records))
    _ -> foldLine (runNearMissBand settings) flat line
  candidates <- first (resolvingAt place (prettyLine line)) (hingeAlong flat foldAt)
  -- The seed names the paper that moves: a moving point, or an alignment
  -- fold's first argument. For L1 to L2 that is a line, and the side holding
  -- it moves, so it must not lie across the fold.
  let pointSeed p = do
        m <- first (resolvingAt place (prettyPoint p)) (materialPoint flat p)
        picked <- first (resolvingAt place (prettyPoint p)) (seedFaces flat m)
        pure (m, picked)
  (m, picked) <- case (layers, seed, line) of
    (FlapOfFirstArgument, Just p, _) -> pointSeed p
    (FlapOfFirstArgument, Nothing, Onto p _) -> pointSeed p
    (FlapOfFirstArgument, Nothing, LineOnto l1 _ _) -> do
      (m, (a, b)) <- first (resolvingAt place (prettyLine l1)) (firstLineSeed flat l1)
      when (straddles flat foldAt (a, b)) (Left (refusedAt place (Selecting (SegmentStraddles (toSheetLengths flat a) (toSheetLengths flat b)))))
      picked <- first (resolvingAt place (prettyLine l1)) (seedFaces flat m)
      pure (m, picked)
    (FlapOfFirstArgument, Nothing, _) -> Left (refusedAt place (Selecting SeedMissing))
    (_, _, _) -> Left (refusedAt place (MoveNotRunYet "choosing which layers to fold"))
  selection <- first (refusedAt place . Selecting) (flapOf flat foldAt candidates m picked)
  -- The anchor's face is the working pattern's first, which folding holds
  -- still: asking where the anchor point lies could fail once a crease runs
  -- through it, and must not let such a fold through.
  when (FaceId 0 `elem` selectionMoving selection) (Left (refusedAt place (MoveNotRunYet "a fold that moves the anchor's paper, which re-anchors,")))
  let toward = case sense of
        ValleyFold -> theFront state
        MountainFold -> opposite (theFront state)
      magnitude = case amount of
        ToFlat -> 180
        Degrees r -> fromRational r
  motion <- first (refusedAt place . FlapRefused) (prepareFlapToward (selectionHinge selection) (selectionSide selection) magnitude toward folded)
  turn <- first (refusedAt place . FlapRefused) (checkFlap (runSweep settings) motion)
  record <- first (refusedAt place . FlapRefused) (recordOf place (hingeStretches flat (selectionHinge selection)) (MaterialPoint m) turn)
  next <- handOn place state folded record
  pure (next, [record])
  where
    opposite = \case
      TowardPlusZ -> TowardMinusZ
      TowardMinusZ -> TowardPlusZ

-- | Turn one recorded move back: its own hinge and seed, by the change of
-- angle it made. Skipped if its creases all lie flat already; refused if a
-- later move changed one of them.
undoOne :: RunSettings -> Here -> (FoldState, [MoveRecord]) -> MoveRecord -> Either SequenceError (FoldState, [MoveRecord])
undoOne settings place (state, made) earlier = do
  let hinge = concatMap snd (recordHinge earlier)
      (before, after) = recordAngles earlier
      now = edgesFoldAngle (theWorking state)
      angle angles (EdgeId e) = IM.lookup e (IM.fromList (zip [0 ..] angles))
      flat e = maybe True ((<= atRest) . abs) (angle now e)
  case hinge of
    first' : _
      | not (all flat hinge) -> do
          case [e | e <- hinge, angle now e /= angle after e] of
            e : _ -> Left (refusedAt place (UnfoldChangedSince e))
            [] -> Right ()
          let travel = fromMaybe 0 ((-) <$> angle before first' <*> angle now first')
              (seed, moving) = case recordMoving earlier of
                (p, faces) : _ -> (p, faces)
                [] -> (MaterialPoint (V2 0 0), [])
          folded <- first (refusedAt place . FoldingRefused) (foldNow state)
          side <- case [f | f <- moving, f `elem` besideEdge (theWorking state) first'] of
            f : _ -> Right f
            [] -> Left (refusedAt place (Selecting NothingSelected))
          motion <- first (refusedAt place . FlapRefused) (prepareFlapAlong hinge side travel folded)
          turn <- first (refusedAt place . FlapRefused) (checkFlap (runSweep settings) motion)
          record <- first (refusedAt place . FlapRefused) (recordOf place (recordHinge earlier) seed turn)
          next <- handOn place state folded record
          pure (next, made ++ [record])
    _ -> Right (state, made)

-- | The faces of the pattern either side of an edge.
besideEdge :: Frame -> EdgeId -> [FaceId]
besideEdge frame (EdgeId e) = case drop e (edgesVertices frame) of
  (VertexId a, VertexId b) : _ | e >= 0 -> [FaceId f | (f, ring) <- zip [0 ..] (facesVertices frame), (x, y) <- zip ring (drop 1 ring ++ take 1 ring), (unVertexId x, unVertexId y) `elem` [(a, b), (b, a)]]
  _ -> []

-- | The record of a checked turn, at this place.
recordOf :: Here -> [(MaterialSegment, [EdgeId])] -> MaterialPoint -> CheckedFlap -> Either FlapError MoveRecord
recordOf place = hingeTurn (placeStep place) (placeMove place) (placeName place) (placeCaption place) (placeOrigin place)

-- | Hand the state on: write the accepted angles and orders onto the working
-- pattern, fold it afresh, and check the paper landed where the turn left it,
-- positions within 1e-12 of the model's size and everything else exactly.
handOn :: Here -> FoldState -> Folded -> MoveRecord -> Either SequenceError FoldState
handOn place state folded record = do
  let accepted = surfaceFrame (recordAfter record)
      next = (foldedPattern folded) {edgesFoldAngle = edgesFoldAngle accepted, faceOrders = faceOrders accepted, frameExtras = mempty}
      broken = Left . refusedAt place . JoinBroken
  refolded <- first (refusedAt place . FoldingRefused) (foldFrameWith next)
  let landed = foldedFrame refolded
  expected <- either (const (broken "the accepted surface's vertices cannot be read")) Right (frameVertices accepted)
  actual <- either (const (broken "the refolded paper's vertices cannot be read")) Right (frameVertices landed)
  let scale = modelSpan expected
  unless (length expected == length actual && and (zipWith (\p q -> norm (p ^-^ q) <= 1e-12 * scale) expected actual)) (broken "its vertices are not where the checked turn left them")
  unless (edgesFoldAngle landed == edgesFoldAngle accepted) (broken "its crease angles differ")
  unless (edgesVertices landed == edgesVertices accepted) (broken "its creases differ")
  unless (map sort (facesVertices landed) == map sort (facesVertices accepted)) (broken "its faces differ")
  unless (sortOn orderKey (faceOrders landed) == sortOn orderKey (faceOrders accepted)) (broken "its layer orders differ")
  unless (verticesCoords (foldedPattern refolded) == verticesCoords (foldedPattern folded)) (broken "its material coordinates differ")
  pure state {theWorking = next, theFold = Just refolded}
  where
    orderKey o = (orderFace o, orderRelativeTo o)

-- | The working pattern folded: the last join check's fold if there is one.
foldNow :: FoldState -> Either FoldingError Folded
foldNow state = maybe (foldFrameWith (theWorking state)) Right (theFold state)

refusedAt :: Here -> MoveFailure -> SequenceError
refusedAt place = StepRefused (placeStep place) (placeName place) (originSpan (placeOrigin place))

resolvingAt :: Here -> Text -> ResolveProblem -> SequenceError
resolvingAt place = ResolveRefused (InStep (placeStep place) (placeName place)) (originSpan (placeOrigin place))

-- | A move this runner does not make yet, in the words an author writes it.
moveWords :: Core -> Text
moveWords = \case
  CoreFold {} -> "\"fold\""
  CorePrecrease {} -> "\"pre-crease\", which makes a new crease,"
  CoreUnfold {} -> "\"unfold\""
  CoreTurnOver {} -> "\"turn over\""
  CoreRotate {} -> "\"rotate\""
  CoreAnchor {} -> "\"anchor\""
  CoreMark {} -> "\"mark\""
  CoreMacro {} -> "a macro move"
  CoreContinue {} -> "\"continue\""
  CoreTogether {} -> "\"together\""
  CorePose {} -> "\"pose\""
  CoreRepeat {} -> "\"repeat\""
  CoreCheckpoint {} -> "\"checkpoint\""
  CoreNotModelled {} -> "\"not modelled\""
  CoreExpectRefused {} -> "\"expect refused\""
