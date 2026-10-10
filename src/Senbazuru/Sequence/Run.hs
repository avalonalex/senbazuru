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
-- far it makes @fold@, along creases the paper already has or, on the flat
-- sheet, along a line where none runs yet, its line given by points, by an
-- edge, by laying one line onto another or as @hinge of NAME@; @pre-crease@,
-- the same fold checked and laid flat again, which leaves its crease and one
-- record; @unfold@; @turn over@, which moves no paper and shows the model
-- from its other side; @rotate@ by whole quarter turns, which turns the model
-- on the page, the same side up; @anchor P@, which holds other paper still
-- from then on and moves none; and @expect refused@. Every other move is
-- refused as not run yet, naming itself, rather than skipped.
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
--    alignment fold such as @P to Q@, its first point. Where the line crosses
--    paper with no crease, and the paper is the flat sheet, crease it there
--    first, at rest, and name paper again ('creaseAcross').
-- 2. Take the flap containing the seed, and the creases along the line that
--    border it, as the hinge. If the flap holds the anchor's face, which
--    folding holds still, re-anchor first ('reanchor'), and name paper
--    afresh on the fold held from the new face.
-- 3. Turn @valley@ or @mountain@ into a direction from the reader's side:
--    @valley@ is in front, towards the reader, which is +z on the paper as
--    folded while the model is shown as it lies, and -z once the display
--    turns it over: with the white side up, or held from a face lying face
--    down.
-- 4. Check the turn over its whole path ("Senbazuru.Origami.Flap"), and make
--    the move's record from the checked turn.
-- 5. Hand on: write the accepted angles and layer orders onto the working
--    pattern, never the folded coordinates, fold it afresh, and check that
--    the paper landed where the checked turn left it. A rigid jump between
--    two individually checked moves would otherwise pass unseen.
--
-- An @unfold@ reuses each named move's recorded hinge and seed, last move
-- first, and turns its hinge back by that move's change of angle. A record
-- numbers its edges and faces as the paper was then, and a later move may
-- have creased the paper since, which renumbers them; so the hinge is found
-- again by its vertices, which creasing never renumbers, and the moving side
-- by which way the faces run along it ('piecesNow', 'movingSideNow'), as is
-- the crease @hinge of NAME@ names. A turn back that carries the anchor's
-- face re-anchors as a fold does, which happens when a later move
-- re-anchored onto the paper this one moved. It is
-- refused if a later move changed one of those creases, and skips a move
-- whose creases all lie flat already. One that turns back several moves makes
-- a record for each, all at the unfold's own step and move, in the order it
-- turned them.
--
-- == Not yet
--
-- Refused as not run yet: a new crease on folded paper, which creases
-- through its layers (milestone M4), layer words, a @rotate@ by an odd
-- number of eighths, whose cos 45° no 'Double' holds (owner decision 10),
-- and every move but @fold@, @pre-crease@, @unfold@, @turn over@, @rotate@
-- and @anchor@, @mark@ among them.
--
-- A re-anchoring onto a face that does not lie flat is refused as
-- @ReanchorNotFlat@ (PRDs\/02-language-semantics.md, §2.3), since then no
-- side of the model faces the reader. A fold never meets it, because paper
-- is named only on a flat state; an unfold can, once a later fold has stood
-- up the paper beside the hinge it turns back.
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
-- not survive the cutting a new crease makes. Its face is the working
-- pattern's first, which folding holds where it lay on the sheet. A new
-- crease through the anchor moves it off the crease to a face the move holds
-- still (decisions C19), and a move that turns the anchor's paper moves it
-- to the paper beside the hinge that the move holds still (owner decision
-- 3): both are 'reanchor'. @anchor P@ moves it on demand, to P and the face
-- P lies strictly inside ('reanchorAt').
--
-- And the /placement/: where the model stands, a rigid motion from the paper
-- as folded. Re-anchoring changes which face folding holds still, which
-- moves the whole fold, and the placement takes that up, so the model stays
-- where it stood on the page. It is the identity until a run re-anchors onto
-- paper that had moved.
--
-- And the /presentation/: how the model is shown to the reader, a rigid
-- motion from where the model stands to where the reader sees it. A
-- turn-over or a rotate changes it and nothing else; no paper moves, and
-- every record's surfaces stay as folded. Each turns the model as shown,
-- about its middle as shown, so it is composed after the presentation it
-- changes: after a turn-over, @anticlockwise@ is anticlockwise as the reader
-- now sees the model, which seen from the coloured side is clockwise. The
-- placement and presentation together, the /display/, decide the /reader's
-- side/, which @valley@ and @mountain@ are read from, and the states a run
-- writes are displayed.
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
import Data.List (find, nub, sort, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Set qualified as S
import Data.Text (Text)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Creasing (NewCreaseAngle (..), creaseAllAlongWith)
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Faces (sheetOf, tolerance, toleranceOf)
import Senbazuru.Fold.Query (FrameKind (..), atRest, edgeKey, frameKind, frameVertices, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..), boxFromPoints)
import Senbazuru.Geometry.Polygon (centroid, distanceToSegment, edges, insideRing, signedArea)
import Senbazuru.Geometry.Rigid (Mat3 (..), Rigid (..), applyRigid, identity, isProperRotation, matApply)
import Senbazuru.Geometry.Rigid qualified as Rigid
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, modelSpan, zSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flap (CheckedFlap, FlapError, Toward (..), checkFlap, prepareFlapAlong, prepareFlapToward)
import Senbazuru.Origami.Folding (Folded (..), FoldingError, foldFrameWith)
import Senbazuru.Origami.HingeSweep (SweepSettings, defaultSweepSettings)
import Senbazuru.Origami.Stacking (Budget, defaultBudget)
import Senbazuru.Origami.Surface (Surface, surfaceFrame, surfaceFromFolded)
import Senbazuru.Sequence.Elaborate (Core (..), CoreMove (..), Elaborated (..), ElaboratedStep (..), Origin (..))
import Senbazuru.Sequence.Error (FoldedBy (..), MoveFailure (..), Place (..), ResolveProblem (..), SelectionError (..), SequenceError (..), SheetProblem (..), refusalKindOf)
import Senbazuru.Sequence.Pretty (prettyLine, prettyPoint)
import Senbazuru.Sequence.Record
import Senbazuru.Sequence.Resolve
import Senbazuru.Sequence.Syntax (Amount (..), Header (..), Layers (..), Line (..), Located (..), Name, PageAxis (..), Point, Sense (..), SheetSource (..), Side (..), Start (..), Turning (..))

-- | The paper between two moves of a run: the working pattern and the anchor.
-- Opaque; the header says what each is and why.
data FoldState = FoldState
  { theWorking :: !Frame,
    theAnchor :: !MaterialPoint,
    -- | How the model is shown to the reader: the rigid motion from where the
    -- paper is folded to where the reader sees it, changed by a turn-over or
    -- a rotate and by nothing that folds (decisions D5). The reader's side
    -- follows from it ('frontOf').
    thePresentation :: !Rigid,
    -- | Where the anchor's face is placed: the rigid motion from the paper as
    -- folded, which folding computes with the anchor's face where it lay on
    -- the sheet, to where the model stands before it is presented (decisions
    -- D14). The identity until a move turns the anchor's paper and the run
    -- re-anchors onto paper that had moved ('reanchor').
    thePlacement :: !Rigid,
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

-- | The reader's side: model +z of the model as shown (decisions D5),
-- measured on the paper as folded. It is the coloured side until the display
-- sends +z to -z, as a turn-over does, or a re-anchoring onto paper lying
-- face down; a valley fold sends its paper towards it.
frontOf :: FoldState -> Toward
frontOf state = case matApply (rigidLinear (displayOf state)) (V3 0 0 1) of
  V3 _ _ z | z < 0 -> TowardMinusZ
  _ -> TowardPlusZ

-- | How the paper as folded is shown: placed, then presented.
displayOf :: FoldState -> Rigid
displayOf state = thePresentation state `Rigid.after` thePlacement state

-- | A turn-over about the model's own middle (decisions D5): left-right maps
-- (x, y, z) to (2cx - x, y, 2cz - z), top-bottom to (x, 2cy - y, 2cz - z).
turnOverAbout :: PageAxis -> [V3] -> Rigid
turnOverAbout = \case
  LeftRight -> aboutMiddle (Mat3 (V3 (-1) 0 0) (V3 0 1 0) (V3 0 0 (-1)))
  TopBottom -> aboutMiddle (Mat3 (V3 1 0 0) (V3 0 (-1) 0) (V3 0 0 (-1)))

-- | A turn on the page about the model's own middle (decisions D5), by
-- quarter turns, anticlockwise as the reader sees it when positive: about
-- the line parallel to +z through (cx, cy), so the side shown stays the side
-- shown. One quarter anticlockwise maps (x, y) to (cx + cy - y, cy - cx + x).
quarterTurnsAbout :: Int -> [V3] -> Rigid
quarterTurnsAbout quarters = aboutMiddle $ case quarters `mod` 4 of
  1 -> Mat3 (V3 0 (-1) 0) (V3 1 0 0) (V3 0 0 1)
  2 -> Mat3 (V3 (-1) 0 0) (V3 0 (-1) 0) (V3 0 0 1)
  3 -> Mat3 (V3 0 1 0) (V3 (-1) 0 0) (V3 0 0 1)
  _ -> rigidLinear identity

-- | A turn that keeps the middle of the points where it is: (cx, cy) the
-- centre of their xy box and cz the middle of their z range. About the
-- middle, so the model stays where it is on the page; about the origin it
-- would be carried off it. Every turn made here has entries 0 and 1 and -1,
-- which a 'Double' holds exactly, so applying one multiplies nothing
-- inexactly; only the additions round, as they do anywhere. A turn by an
-- eighth would need cos 45°, which no 'Double' holds, and whose last bits
-- come from the platform's trigonometry (owner decision 10).
aboutMiddle :: Mat3 -> [V3] -> Rigid
aboutMiddle turn points = Rigid turn (middle ^-^ matApply turn middle)
  where
    middle = V3 (mid v3x) (mid v3y) (mid v3z)
    mid along = case map along points of
      [] -> 0
      values -> (minimum values + maximum values) / 2

-- | Where a surface's vertices are, as folded.
surfacePositions :: Surface V2 -> [V3]
surfacePositions surface = [V3 x y (case rest of z : _ -> z; [] -> 0) | x : y : rest <- verticesCoords (surfaceFrame surface)]

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
  let ring = ringOn material
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
        thePresentation = identity,
        thePlacement = identity,
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
    runNearMissBand :: !Double,
    -- | How hard the layer solver may look before giving up, @--layer-budget@.
    -- Every entry point that can reach the solver takes it (AGENTS.md); no
    -- move solves a stacking yet, so it waits here for the first that does,
    -- choosing among layer orders at milestone M4.
    runBudget :: !Budget
  }

-- | The settings a run uses unless told otherwise.
defaultRunSettings :: RunSettings
defaultRunSettings = RunSettings defaultSweepSettings 1e-3 defaultBudget

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
        runStartPresentation = thePresentation start,
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
  -- White side up starts with a turn-over left-right (G3), about the sheet's
  -- own middle as every turn-over is.
  let shown = case hSide header of
        WhiteUp -> turnOverAbout LeftRight (surfacePositions surface)
        ColouredUp -> identity
  Right (anchored {thePresentation = shown, theFold = Just folded}, surface)

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
      [] -> Right (Going (progress st made got (outcome st made : outcomes)))
      (i, CoreMove origin core) : rest -> case runMove settings (Here n (elaboratedName step) (elaboratedCaption step) i origin) named st (after made) core of
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
    outcome st made = StepOutcome n (elaboratedName step) (elaboratedCaption step) (if all expectation (elaboratedMoves step) then Nothing else Just (after made)) (thePresentation st) (thePlacement st)
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

runMove :: RunSettings -> Here -> Map Name [MoveRecord] -> FoldState -> Surface V2 -> Core -> Either SequenceError Made
runMove settings place named state surface = \case
  CoreFold sense amount line layers seed -> moved <$> foldMove settings place named state Turn sense amount line layers seed
  -- A pre-crease is the fold, checked over its whole path, laid flat again:
  -- one move and one record, its crease left without a direction.
  CorePrecrease sense line layers seed -> moved <$> foldMove settings place named state Precrease sense ToFlat line layers seed
  CoreUnfold names -> moved <$> foldM (undoOne settings place) (state, []) (reverse (concat [M.findWithDefault [] name named | name <- names]))
  -- The inner move runs against this state, and must be refused as the kind
  -- given; it leaves the state as it was and no record, since it moved no
  -- paper. A move not run yet says nothing about the paper, so its refusal
  -- is passed on as itself.
  CoreExpectRefused kind inner -> case inner of
    Nothing -> Left (refusedAt place (RefusalNotRaised kind))
    Just (CoreMove origin core) -> case runMove settings place {placeOrigin = origin} named state surface core of
      Right _ -> Left (refusedAt place (RefusalNotRaised kind))
      Left err -> case refusalKindOf err of
        Just raised
          | raised == kind -> Right (Made state [] [ExpectedRefusal (placeStep place) (placeMove place) kind])
          | otherwise -> Left (refusedAt place (RefusedDifferently kind raised))
        Nothing -> Left err
  CoreNotModelled what -> Left (refusedAt place (NotModelledStop what))
  -- A turn-over moves no paper: the model is shown from its other side, its
  -- axis through the middle of the model as shown (decisions D5). The state
  -- keeps its paper and changes its presentation, and with it the reader's
  -- side.
  CoreTurnOver axis -> present (TurnedOver axis) (turnOverAbout axis)
  -- @anchor P@ re-anchors on demand (PRDs\/02-language-semantics.md, §2.3):
  -- the face P lies strictly inside is held still from now on, with the
  -- anchor at P, as the header's anchor is. No paper moves, and the model
  -- stays where it stood on the page.
  CoreAnchor point -> do
    folded <- first (refusedAt place . FoldingRefused) (foldNow state)
    let naming = resolvingAt place (prettyPoint point)
    flat <- first naming (flatState folded)
    m <- first naming (materialPoint flat point)
    FaceId face <- first naming (regionFace flat m)
    (anchored, refolded) <- reanchorAt place state folded face m
    held <- first (refusedAt place . JoinBroken . ("the re-anchored paper makes no surface: " <>) . explain) (surfaceFromFolded refolded)
    Right (Made anchored [anchoring (placeStep place) (placeMove place) (placeName place) (placeCaption place) (placeOrigin place) (theAnchor state, theAnchor anchored) held (thePresentation anchored) (thePlacement anchored)] [])
  -- A rotate turns the model on the page, the same side up, so the reader's
  -- side stays. Only whole quarter turns are made: an odd number of eighths
  -- would need cos 45° (owner decision 10).
  CoreRotate eighths turning
    | odd eighths -> Left (refusedAt place (MoveNotRunYet ("\"rotate " <> tshow eighths <> "/8 turn\", which is not a whole number of quarter turns,")))
    | otherwise -> present (Rotated eighths turning) (quarterTurnsAbout ((case turning of Anticlockwise -> 1; Clockwise -> -1) * (eighths `div` 2)))
  other -> Left (refusedAt place (MoveNotRunYet (moveWords other)))
  where
    moved (st, records) = Made st records []
    -- A change of presentation turns the model as shown, about its middle as
    -- shown, so the turn goes after the presentation it changes.
    present turn about = do
      let shown = thePresentation state
          shown' = about [applyRigid (displayOf state) p | p <- surfacePositions surface] `Rigid.after` shown
      unless (isProperRotation (rigidLinear shown')) (Left (refusedAt place PresentationImproper))
      Right (Made state {thePresentation = shown'} [presented (placeStep place) (placeMove place) (placeName place) (placeCaption place) (placeOrigin place) turn (theAnchor state) surface (shown, shown') (thePlacement state)] [])

-- | A fold along creases the paper has, as the header lays out.
foldMove :: RunSettings -> Here -> Map Name [MoveRecord] -> FoldState -> MoveKind -> Sense -> Amount -> Line -> Layers -> Maybe Point -> Either SequenceError (FoldState, [MoveRecord])
foldMove settings place named given kind sense amount line layers seed = do
  found <- first (refusedAt place . FoldingRefused) (foldNow given)
  seen <- first (resolvingAt place (prettyLine line)) (flatState found)
  -- @hinge of NAME@ is the line the named step's one move turned about: the
  -- recorded crease, where the paper now lies, found on the paper as it is
  -- now, since a later move may have creased it ('piecesNow').
  let lineOn st flat' = first (resolvingAt place (prettyLine line)) $ case line of
        HingeOf name -> case M.findWithDefault [] name named of
          [earlier] -> case concatMap (piecesNow (theWorking st) (surfaceFrame (recordBefore earlier))) (concatMap snd (recordHinge earlier)) of
            e : _ -> lineAlong flat' e
            [] -> Left NoSolution
          records -> Left (HingeOfNotOneMove name (length records))
        _ -> foldLine (runNearMissBand settings) flat' line
      towardIn st = case sense of
        ValleyFold -> frontOf st
        MountainFold -> opposite (frontOf st)
  foldAt <- lineOn given seen
  -- A fold's new crease is lettered by its sense, seen from the coloured
  -- side; a pre-crease's has no direction, since a later move may fold it
  -- either way (owner decision 14). Creasing is on the flat sheet, where
  -- re-anchoring moves nothing, so the side is the same before and after it.
  -- A fold is run as a Turn or a Precrease, never as a Presentation.
  let letter = case kind of
        Precrease -> Unassigned
        _ -> case towardIn given of
          TowardPlusZ -> Valley
          TowardMinusZ -> Mountain
  (creased, foldedCreased, flatCreased, fresh, around) <- creaseAcross place line given found seen foldAt letter
  -- The paper that moves: the seed, which is a moving point or an alignment
  -- fold's first argument, and the flap holding it. For L1 to L2 the seed is
  -- a line, and the side holding it moves, so it must not lie across the
  -- fold. Chosen on a state named afresh, so asked twice when the anchor
  -- moves.
  let choose flat' at = do
        candidates <- first (resolvingAt place (prettyLine line)) (hingeAlong flat' at)
        let pointSeed p = do
              m <- first (resolvingAt place (prettyPoint p)) (materialPoint flat' p)
              picked <- first (resolvingAt place (prettyPoint p)) (seedFaces flat' m)
              pure (m, picked, prettyPoint p)
        (m, picked, seedWords) <- case (layers, seed, line) of
          (FlapOfFirstArgument, Just p, _) -> pointSeed p
          (FlapOfFirstArgument, Nothing, Onto p _) -> pointSeed p
          (FlapOfFirstArgument, Nothing, LineOnto l1 _ _) -> do
            (m, (a, b)) <- first (resolvingAt place (prettyLine l1)) (firstLineSeed flat' l1)
            when (straddles flat' at (a, b)) (Left (refusedAt place (Selecting (SegmentStraddles (toSheetLengths flat' a) (toSheetLengths flat' b)))))
            picked <- first (resolvingAt place (prettyLine l1)) (seedFaces flat' m)
            pure (m, picked, prettyLine l1)
          (FlapOfFirstArgument, Nothing, _) -> Left (refusedAt place (Selecting SeedMissing))
          (_, _, _) -> Left (refusedAt place (MoveNotRunYet "choosing which layers to fold"))
        selection <- first (refusedAt place . Selecting) (flapOf flat' at candidates m picked)
        pure (m, seedWords, selection)
  -- A new crease through the anchor leaves it on a crease, in no one face,
  -- and it moves off it (decisions C19): to a face the move holds still,
  -- which the paper the move turns says. On the flat sheet every face lies
  -- where it lies, whichever is held still, so that paper is chosen on the
  -- creased state as traced, and then again once the anchor's face is first.
  -- If the move turns every face around the anchor, the anchor's paper is
  -- carried, and the move re-anchors below.
  (anchored, foldedAnchored, flatAnchored, carried) <- case around of
    [] -> Right (creased, foldedCreased, flatCreased, False)
    _ -> do
      (_, _, turning) <- choose flatCreased foldAt
      case [FaceId i | i <- around, FaceId i `notElem` selectionMoving turning] of
        [] -> Right (creased, foldedCreased, flatCreased, True)
        still -> do
          (moved, refolded) <- reanchor place creased foldedCreased still
          renamed <- first (resolvingAt place (prettyLine line)) (flatState refolded)
          Right (moved, refolded, renamed, False)
  chosen@(_, _, turning) <- choose flatAnchored foldAt
  -- A move that turns the anchor's face, the working pattern's first, which
  -- folding holds still, re-anchors (owner decision 3): onto the paper beside
  -- its hinge that it holds still, which then stays where it is on the page.
  -- Rooted at another face, the fold is moved as a whole, so the fold line
  -- and the paper it turns are named on it afresh.
  (state, folded, flat, (m, seedWords, selection), lineNow) <-
    if carried || FaceId 0 `elem` selectionMoving turning
      then do
        (moved, refolded) <- reanchor place anchored foldedAnchored (stillBeside (theWorking anchored) (selectionHinge turning) (selectionMoving turning))
        renamed <- first (resolvingAt place (prettyLine line)) (flatState refolded)
        at <- lineOn moved renamed
        picked <- choose renamed at
        Right (moved, refolded, renamed, picked, at)
      else Right (anchored, foldedAnchored, flatAnchored, chosen, foldAt)
  when (FaceId 0 `elem` selectionMoving selection) (Left (refusedAt place (JoinBroken "named afresh after re-anchoring, the fold still turns the anchor's paper")))
  let magnitude = case amount of
        ToFlat -> 180
        Degrees r -> fromRational r
  motion <- first (refusedAt place . FlapRefused) (prepareFlapToward (selectionHinge selection) (selectionSide selection) magnitude (towardIn state) folded)
  turn <- first (refusedAt place . FlapRefused) (checkFlap (runSweep settings) motion)
  let resolved = [uncurry (ResolvedLine (prettyLine line)) (lineAsSeen flat lineNow), ResolvedSeed seedWords (toSheetLengths flat m)]
  turned <- first (refusedAt place . FlapRefused) (recordOf place (hingeStretches flat (selectionHinge selection)) fresh (theAnchor given, theAnchor state) (thePresentation state) (thePlacement state) (MaterialPoint m) resolved turn)
  let record = case kind of
        Precrease -> asPrecrease turned
        _ -> turned
  next <- handOn place state folded record
  pure (next, [record])
  where
    opposite = \case
      TowardPlusZ -> TowardMinusZ
      TowardMinusZ -> TowardPlusZ

-- | Crease the paper where the fold line crosses it with no crease, before
-- the fold turns it: the state, folded and named afresh, and the creases
-- drawn, each with the edges it became and its letter. A line along creases
-- the paper has crosses no face, and changes nothing.
--
-- Only the flat sheet is creased here, every crease at rest: the paper is one
-- layer, and the line crosses each face once. On folded paper the line
-- crosses layers, and creasing through them is milestone M4's.
--
-- The new creases take the letter they are given: a fold's sense seen from
-- the coloured side, the "raw sense" of decisions D5, or U for a
-- pre-crease's.
--
-- Creasing moves no paper. On the flat sheet every face lies where it lies
-- on the sheet, so the fold line found before creasing is still the line
-- after it. The anchor's face, cut in two where the line crosses it, is put
-- first again, the face folding holds still. A line through the anchor
-- itself leaves it in no one face: then the faces are left as traced, and
-- the last of the answer is the faces around the anchor, from which the
-- caller moves it ('reanchor') once it knows which of them the move turns.
creaseAcross :: Here -> Line -> FoldState -> Folded -> FlatState -> FoldLine -> Assignment -> Either SequenceError (FoldState, Folded, FlatState, [(MaterialSegment, [EdgeId], Assignment)], [Int])
creaseAcross place line state folded flat foldAt letter = case crossedFaces flat foldAt of
  [] -> Right (state, folded, flat, [], [])
  crossed -> do
    unless (all ((<= atRest) . abs) (edgesFoldAngle (theWorking state))) $
      Left (resolvingAt place (prettyLine line) (NotRunYet "a fold whose line crosses folded paper where no crease runs, which creases through its layers,"))
    let chords = chordsAcross flat foldAt crossed
    (creased, pieces) <- first (refusedAt place . CreasingRefused) (creaseAllAlongWith AtRest [(a, b, letter) | (a, b) <- chords] (theWorking state))
    room <- first (refusedAt place . CreasingRefused) (tolerance <$> sheetOf creased)
    let material = materialPoints creased
        ring = ringOn material
        faces = facesVertices creased
        -- A face holds a point on its outline too, as a closed polygon does.
        holds face = insideRing room (ring face) anchor || any ((<= room) . (`distanceToSegment` anchor)) (edges (ring face))
    -- Strictly inside one face, the anchor stays, and that face goes first;
    -- on a crease, it is held by the faces around it, and the caller moves
    -- it. On none at all, nothing could say which face to hold still.
    (ordered, around) <- case [i | (i, face) <- zip [0 ..] faces, insideRing room (ring face) anchor] of
      [i] -> Right (firstOf i faces, [])
      _ -> case [i | (i, face) <- zip [0 ..] faces, holds face] of
        [] -> Left (refusedAt place (MoveNotRunYet "a new crease that leaves the anchor on no face,"))
        held -> Right (faces, held)
    let next = state {theWorking = creased {facesVertices = ordered}, theFold = Nothing}
    refolded <- first (refusedAt place . FoldingRefused) (foldNow next)
    named <- first (resolvingAt place (prettyLine line)) (flatState refolded)
    pure (next, refolded, named, [(MaterialSegment (MaterialPoint a) (MaterialPoint b), ids, letter) | ((a, b), ids) <- zip chords pieces], around)
  where
    MaterialPoint anchor = theAnchor state

-- | Move the anchor to one of the faces given, which folding then holds
-- still: the vertex mean of the largest, ties to the lowest vertex mean and
-- then the leftmost, as 'sheetState' picks the default anchor
-- (PRDs\/02-language-semantics.md, §2.3). Two moves ask for it: a new crease
-- through the anchor, from the faces around it that the move does not turn
-- (decisions C19), and a move that turns the anchor's paper, from the faces
-- beside its hinge that it holds still (owner decision 3). 'reanchorAt' does
-- the rest.
reanchor :: Here -> FoldState -> Folded -> [FaceId] -> Either SequenceError (FoldState, Folded)
reanchor place state folded still = do
  let working = theWorking state
      material = materialPoints working
      ring = ringOn material
      measured = [(i, face, abs (signedArea (ring face)), centroid (ring face)) | (i, face) <- zip [0 ..] (facesVertices working), FaceId i `elem` still]
      room = toleranceOf (IM.elems material)
  case defaultAnchor room measured of
    Just (i, face, _, mean)
      | insideRing room (ring face) mean -> reanchorAt place state folded i mean
      | otherwise -> Left (refusedAt place (MoveNotRunYet "an anchor moved to a face that does not hold its own vertex mean,"))
    Nothing -> Left (refusedAt place (JoinBroken "no face was left to hold still"))

-- | Hold face @i@ of the working pattern still from now on, with the anchor
-- at the material point given, which lies in it. The fold handed back is the
-- new one.
--
-- Folding holds the working pattern's first face where it lay on the sheet.
-- Put another face first, and the whole fold moves by the inverse of h,
-- where h is how that face is placed now: it is the face held still that
-- changes, not the paper. The placement takes h on, so the model stands on
-- the page where it stood, and that is checked, refolded, within 1e-12 of
-- the model's size. On the flat sheet every face lies where it lay, h is the
-- identity, and nothing is placed differently.
--
-- Putting a face first renumbers the faces, so the layer orders are
-- renumbered with them. Their signs stand: each is read against its faces'
-- windings, which are not touched.
reanchorAt :: Here -> FoldState -> Folded -> Int -> V2 -> Either SequenceError (FoldState, Folded)
reanchorAt place state folded i anchorAt = do
  let working = theWorking state
      material = materialPoints working
      faces = facesVertices working
      broken = Left . refusedAt place . JoinBroken
  h <- maybe (broken "the new anchor's face has no place in the fold") Right (IM.lookup i (foldedPlacements folded))
  -- The new face is held where it lay on the sheet, so its normal on the page
  -- is where the display sends +z. It must face the reader or away, or no
  -- side of the model faces the reader.
  let shown = thePresentation state `Rigid.after` (thePlacement state `Rigid.after` h)
      V3 _ _ facing = matApply (rigidLinear shown) (V3 0 0 1)
  box <- maybe (broken "the sheet has no extent") Right (boxFromPoints (IM.elems material))
  when (abs facing < 1 - 1e-9) (Left (refusedAt place (ReanchorNotFlat (sheetLengthsIn box anchorAt) (acos (min 1 (abs facing)) * 180 / pi))))
  let renumber (FaceId f)
        | f == i = FaceId 0
        | f < i = FaceId (f + 1)
        | otherwise = FaceId f
      orders = [o {orderFace = renumber (orderFace o), orderRelativeTo = renumber (orderRelativeTo o)} | o <- faceOrders working]
      moved =
        state
          { theWorking = working {facesVertices = firstOf i faces, faceOrders = orders},
            theAnchor = MaterialPoint anchorAt,
            thePlacement = thePlacement state `Rigid.after` h,
            theFold = Nothing
          }
  refolded <- first (refusedAt place . FoldingRefused) (foldNow moved)
  stood <- either (const (broken "the paper's vertices cannot be read")) (Right . map (applyRigid (thePlacement state))) (frameVertices (foldedFrame folded))
  stands <- either (const (broken "the refolded paper's vertices cannot be read")) (Right . map (applyRigid (thePlacement moved))) (frameVertices (foldedFrame refolded))
  let scale = modelSpan stood
  unless (length stood == length stands && and (zipWith (\p q -> norm (p ^-^ q) <= 1e-12 * scale) stood stands)) (broken "re-anchoring moved the model on the page")
  pure (moved {theFold = Just refolded}, refolded)

-- | A record's edge, numbered as the paper was when the move was made, found
-- on the working pattern now: the edge itself, if nothing has cut it since,
-- or the pieces a later crease cut it into, in order from its first end.
--
-- Creasing appends vertices and never renumbers one, so the edge's two ends
-- are the same vertices now; its pieces are the edges lying between them on
-- the sheet. Edges are renumbered, which is why the record's edge id alone
-- would name some other crease.
piecesNow :: Frame -> Frame -> EdgeId -> [EdgeId]
piecesNow now thenFrame (EdgeId e) = case drop e (edgesVertices thenFrame) of
  (a, b) : _
    | e >= 0 -> case drop e (edgesVertices now) of
        (u, v) : _ | (u, v) == (a, b) -> [EdgeId e]
        _ -> between a b
  _ -> []
  where
    material = materialPoints now
    at (VertexId v) = IM.lookup v material
    room = toleranceOf (IM.elems material)
    between a b = case (at a, at b) of
      (Just p, Just q) ->
        let on x = distanceToSegment (p, q) x <= room
         in map snd . sortOn fst $
              [ (dot (0.5 *^ (x ^+^ y) ^-^ p) (q ^-^ p), EdgeId i)
                | (i, (u, v)) <- zip [0 ..] (edgesVertices now),
                  Just x <- [at u],
                  on x,
                  Just y <- [at v],
                  on y
              ]
      _ -> []

-- | The faces a turn about a hinge carries with the given face: every face
-- reached from it without crossing the hinge. Read from the working pattern
-- alone, so it asks nothing of where the paper lies, which a turn back of
-- paper standing in the air needs.
carriedWith :: Frame -> [EdgeId] -> FaceId -> [FaceId]
carriedWith frame hinge (FaceId start) = go [] [start]
  where
    cut = S.fromList [edgeKey u v | (i, (u, v)) <- zip [0 ..] (edgesVertices frame), EdgeId i `elem` hinge]
    rings = IM.fromList (zip [0 ..] (facesVertices frame))
    owners = M.fromListWith (++) [(edgeKey u v, [f]) | (f, ring) <- IM.toList rings, (u, v) <- ringEdges ring]
    beyond f = [g | Just ring <- [IM.lookup f rings], (u, v) <- ringEdges ring, S.notMember (edgeKey u v) cut, g <- M.findWithDefault [] (edgeKey u v) owners, g /= f]
    go seen [] = map FaceId (reverse seen)
    go seen (f : rest)
      | f `elem` seen = go seen rest
      | otherwise = go (f : seen) (beyond f ++ rest)

-- | The faces beside a hinge that a turn of the given faces holds still,
-- each once: any of them can stay put while the rest turns.
stillBeside :: Frame -> [EdgeId] -> [FaceId] -> [FaceId]
stillBeside frame hinge moving =
  nub
    [ FaceId f
      | (f, ring) <- zip [0 ..] (facesVertices frame),
        FaceId f `notElem` moving,
        any (`elem` [edgeKey u v | (u, v) <- ringEdges ring]) hingePairs
    ]
  where
    hingePairs = [edgeKey u v | (i, (u, v)) <- zip [0 ..] (edgesVertices frame), EdgeId i `elem` hinge]

-- | A face's corners on the sheet, from a pattern's points.
ringOn :: IM.IntMap V2 -> [VertexId] -> [V2]
ringOn material face = [p | VertexId v <- face, Just p <- [IM.lookup v material]]

-- | Each vertex of a working pattern where it lies on the sheet: the pattern's
-- own coordinates, since a working pattern is never folded in place.
materialPoints :: Frame -> IM.IntMap V2
materialPoints frame = IM.fromList (zip [0 ..] [V2 x y | x : y : _ <- verticesCoords frame])

-- | Which side of a record's hinge crease its moving paper lay, found on the
-- working pattern now: the face beside a piece of that crease that lies the
-- same way round it as one of the record's moving faces did.
--
-- Face ids do not survive the re-tracing a new crease makes, so the side is
-- read from the rings. Every ring of the working pattern runs anticlockwise
-- on the sheet, as 'sheetState' winds them and as tracing does, so a face
-- lies to the left of an edge it runs along forwards and to the right of one
-- it runs along backwards. A piece runs the way its crease ran, since
-- cutting keeps every crease's direction from its first end, so "left of the
-- piece" and "left of the crease" are one side.
movingSideNow :: Frame -> Frame -> [FaceId] -> EdgeId -> EdgeId -> Maybe FaceId
movingSideNow now thenFrame moving (EdgeId thenEdge) (EdgeId piece) = do
  (a, b) <- listToMaybe (drop thenEdge (edgesVertices thenFrame))
  (u, v) <- listToMaybe (drop piece (edgesVertices now))
  wanted <- listToMaybe [s | FaceId g <- moving, ring <- take 1 (drop g (facesVertices thenFrame)), let s = sideOf ring a b, s /= 0]
  listToMaybe [FaceId f | (f, ring) <- zip [0 ..] (facesVertices now), sideOf ring u v == wanted]
  where
    -- +1 if the face lies left of a -> b, -1 if right, 0 if it does not run
    -- along that edge.
    sideOf ring a b
      | (a, b) `elem` pairs = 1 :: Int
      | (b, a) `elem` pairs = -1
      | otherwise = 0
      where
        pairs = zip ring (drop 1 ring ++ take 1 ring)

-- | Turn one recorded move back: its own hinge and seed, by the change of
-- angle it made. Skipped if its creases all lie flat already; refused if a
-- later move changed one of them.
--
-- The record numbers its edges and faces as the paper was then; a later
-- move may have creased the paper since, so each is found on the paper as it
-- is now ('piecesNow', 'movingSideNow'), and the new record numbers them as
-- now.
undoOne :: RunSettings -> Here -> (FoldState, [MoveRecord]) -> MoveRecord -> Either SequenceError (FoldState, [MoveRecord])
undoOne settings place (state, made) earlier = do
  let working = theWorking state
      thenFrame = surfaceFrame (recordBefore earlier)
      -- Each recorded hinge edge with its pieces now, and then each pair.
      found = [(e, piecesNow working thenFrame e) | e <- concatMap snd (recordHinge earlier)]
      pairs = [(e, p) | (e, ps) <- found, p <- ps]
      hinge = map snd pairs
      (before, after) = recordAngles earlier
      now = edgesFoldAngle working
      angle angles (EdgeId e) = IM.lookup e (IM.fromList (zip [0 ..] angles))
      flat e = maybe True ((<= atRest) . abs) (angle now e)
  -- Creasing only adds, so every recorded crease is on the paper still. One
  -- that is not cannot be judged flat or folded, and is refused rather than
  -- passed over as though it lay flat.
  case [e | (e, []) <- found] of
    e : _ -> Left (refusedAt place (UnfoldChangedSince e))
    [] -> Right ()
  case pairs of
    (firstThen, first') : _
      | not (all flat hinge) -> do
          case [p | (e, p) <- pairs, angle now p /= angle after e] of
            p : _ -> Left (refusedAt place (UnfoldChangedSince p))
            [] -> Right ()
          let travel = fromMaybe 0 ((-) <$> angle before firstThen <*> angle now first')
              (seed, moving) = case recordMoving earlier of
                (m, faces) : _ -> (m, faces)
                [] -> (MaterialPoint (V2 0 0), [])
          foldedNow <- first (refusedAt place . FoldingRefused) (foldNow state)
          let sideIn st = maybe (Left (refusedAt place (Selecting NothingSelected))) Right (movingSideNow (theWorking st) thenFrame moving firstThen first')
          side' <- sideIn state
          -- Turning back paper that holds the anchor's face re-anchors, as a
          -- fold does (owner decision 3): a later move may have re-anchored
          -- onto the paper this one moved.
          let carried = carriedWith working hinge side'
          (turning, folded, side) <-
            if FaceId 0 `elem` carried
              then do
                (moved, refolded) <- reanchor place state foldedNow (stillBeside working hinge carried)
                side <- sideIn moved
                Right (moved, refolded, side)
              else Right (state, foldedNow, side')
          motion <- first (refusedAt place . FlapRefused) (prepareFlapAlong hinge side travel folded)
          turn <- first (refusedAt place . FlapRefused) (checkFlap (runSweep settings) motion)
          let stretches = [(segment, [p | (e, ps) <- found, e `elem` recorded, p <- ps]) | (segment, recorded) <- recordHinge earlier]
          record <- first (refusedAt place . FlapRefused) (recordOf place stretches [] (theAnchor state, theAnchor turning) (thePresentation turning) (thePlacement turning) seed [ResolvedTurnedBack (recordStep earlier) (recordStepName earlier)] turn)
          next <- handOn place turning folded record
          pure (next, made ++ [record])
    _ -> Right (state, made)

-- | The record of a checked turn, at this place.
recordOf :: Here -> [(MaterialSegment, [EdgeId])] -> [(MaterialSegment, [EdgeId], Assignment)] -> (MaterialPoint, MaterialPoint) -> Rigid -> Rigid -> MaterialPoint -> [ResolvedReference] -> CheckedFlap -> Either FlapError MoveRecord
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
  CorePrecrease {} -> "\"pre-crease\""
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
