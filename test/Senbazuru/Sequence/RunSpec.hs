-- | Where a run starts: 'sheetState' on the repository's sheets, and on small
-- sheets made here for the cases no fixture has, such as a crease drawn F at
-- an angle or a face wound clockwise.
module Senbazuru.Sequence.RunSpec (spec) where

import Control.Monad (forM_)
import Data.List (sort, sortOn)
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap (FlapError (..), flapCheck)
import Senbazuru.Origami.HingeSweep (SweepCheck (..), SweepOutcome (..), SweepSettings (..))
import Senbazuru.Origami.Surface (surfaceFrame)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (FoldedBy (..), MoveFailure (..), Place (..), ResolveProblem (..), SelectionError (..), SequenceError (..), SheetProblem (..), refusalKindOf)
import Senbazuru.Sequence.Record (ExpectedRefusal (..), MaterialPoint (..), RouteEvidence (..), Run (..), RunStop (..), recordAfter, recordAngles, recordBefore, recordEvidence, recordHinge, recordMoving, recordStationary, recordStep, runRefusal)
import Senbazuru.Sequence.Run
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Corner (..), Header (..), Layers (..), Line (..), Move (..), Name (..), PageAxis (..), Point (..), RefusalKind (..), Sense (..), Sequence (..), Side (..), Span (..))
import Test.Hspec
import Test.SequenceExamples (blintz, quarterFold)

spec :: Spec
spec = do
  starting
  running
  quartered
  stopping
  blocked

running :: Spec
running = describe "running a sequence" $ do
  blintzFile <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  let sheets = M.singleton "examples/blintz-base.fold" blintzFile
      runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings sheets . elaborate
      oneStep moves = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just centre)) (step_ "s" moves)
  records <- runIO (right (runRecords <$> runOn blintz))

  it "runs the blintz to five records, one a step, its corners about edges 8 to 11" $ do
    map recordStep records `shouldBe` [1 .. 5]
    map (concatMap snd . recordHinge) records `shouldBe` [[EdgeId 8], [EdgeId 9], [EdgeId 10], [EdgeId 11], [EdgeId 8]]

  -- E2: every record's evidence is a turn checked over its whole path, and
  -- the check found it clear.
  it "checks every turn over its whole path, and finds each clear" $
    forM_ records $ \record -> case recordEvidence record of
      SweptHinge turn -> sweepOutcome (flapCheck turn) `shouldBe` SweepClear

  -- Behind is away from the reader: with the coloured side up, -180, the
  -- recipe's travel; the unfold takes edge 8 back to 0. Turns red if the
  -- reader's side were read backwards, or a move changed another crease.
  it "turns each corner behind by 180, and the unfold back to flat" $
    forM_ (zip3 records [8, 9, 10, 11, 8] [-180, -180, -180, -180, 180]) $ \(record, e, travel) -> do
      let (anglesBefore, anglesAfter) = recordAngles record
      [i | (i, a, b) <- zip3 [0 :: Int ..] anglesBefore anglesAfter, a /= b] `shouldBe` [e]
      (anglesAfter !! e) - (anglesBefore !! e) `shouldBe` travel

  -- E3, as the records show it: each move starts where the last one ended,
  -- and the centre square, the anchor's face, never moves.
  it "hands each move's paper to the next, the anchor's face held still" $ do
    forM_ (zip records (drop 1 records)) $ \(record, next) -> do
      endPoints <- right (frameVertices (surfaceFrame (recordAfter record)))
      startPoints <- right (frameVertices (surfaceFrame (recordBefore next)))
      and (zipWith (\p q -> p == q || maximum (map abs (zipWith (-) (coords p) (coords q))) < 1e-12) endPoints startPoints) `shouldBe` True
    map recordStationary records `shouldBe` replicate 5 (FaceId 0)

  -- The white side up puts the reader's side at -z, so behind is +z: the
  -- same mountain turns the crease the other way.
  it "reads valley and mountain from the reader's side" $ do
    let coloured = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just centre)) (step_ "s" (fold mountain (cornerOf SouthEast `onto` centre)))
        whiteUp = coloured {seqHeader = (seqHeader coloured) {hSide = WhiteUp}}
    run <- right (runOn whiteUp)
    case runRecords run of
      [record] -> (snd (recordAngles record) !! 8) `shouldBe` 180
      other -> expectationFailure ("expected one record, got " <> show (length other))

  -- moving P picks the paper for a line that does not say which side moves.
  it "folds the side named by moving P, and refuses a line with none" $ do
    let alongEdge8 = Segment (MidpointOfEdge South) (MidpointOfEdge East)
    run <- right (runOn (oneStep (move (Fold MountainFold ToFlat alongEdge8 FlapOfFirstArgument (Just (CornerOf SouthEast))))))
    map (concatMap snd . recordHinge) (runRecords run) `shouldBe` [[EdgeId 8]]
    refusal (runOn (oneStep (fold mountain alongEdge8))) `shouldBe` Just (Selecting SeedMissing)

  describe "refuses" $ do
    it "a sheet it was not given" $
      case checkSequence blintz >>= runSequence defaultRunSettings M.empty . elaborate of
        Left (SheetRefused _ "examples/blintz-base.fold" SheetNotLoaded) -> pure ()
        other -> expectationFailure ("expected the sheet refused, got " <> show (fmap (length . runRecords) other))

    -- The diagonal crosses the central square, where no crease runs.
    it "a fold that would need a new crease, until creasing is run" $
      case runOn (oneStep (move (Fold ValleyFold ToFlat (Segment (CornerOf SouthWest) (CornerOf NorthEast)) FlapOfFirstArgument (Just (CornerOf SouthEast))))) of
        Left (ResolveRefused (InStep 1 _) _ _ (NotRunYet _)) -> pure ()
        other -> expectationFailure ("expected creasing to be not run yet, got " <> show (fmap (length . runRecords) other))

    -- An anchor inside corner south-east's triangle moves with it.
    it "a fold that would carry the anchor's paper, until re-anchoring is run" $ do
      let carried = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just (at (19 / 20) (1 / 50)))) (step_ "s" (fold mountain (cornerOf SouthEast `onto` centre)))
      case refusal (runOn carried) of
        Just (MoveNotRunYet _) -> pure ()
        other -> expectationFailure ("expected re-anchoring to be not run yet, got " <> show other)

    -- c1 folds the corner behind, is unfolded, and the corner is then folded
    -- in front: edge 8 is no longer where c1 left it, so unfolding c1 again
    -- would undo the later fold. A second unfold of a flat crease is skipped.
    it "an unfold of a crease folded again since, and skips one lying flat" $ do
      let later = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
            c1 <- step "c1" "a" (fold mountain (cornerOf SouthEast `onto` centre))
            step_ "b" (unfold [c1])
            step_ "c" (unfold [c1])
            step_ "d" (fold valley (cornerOf SouthEast `onto` centre))
            step_ "e" (unfold [c1])
      refusal (runOn later) `shouldBe` Just (UnfoldChangedSince (EdgeId 8))
      let twice = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
            c1 <- step "c1" "a" (fold mountain (cornerOf SouthEast `onto` centre))
            step_ "b" (unfold [c1])
            step_ "c" (unfold [c1])
      fmap (length . runRecords) (runOn twice) `shouldBe` Right 2

    -- Edge south onto the line up the middle: the lines cross at (1/2, 0),
    -- the middle of edge south, so whichever crease is chosen, edge south
    -- lies across it and does not say which side moves.
    it "a line laid onto a line, when the first lies across the fold" $
      case refusal (runOn (oneStep (fold behind (LineOnto (edge South) (Segment (MidpointOfEdge South) (MidpointOfEdge North)) (Just (MidpointOfEdge East)))))) of
        Just (Selecting (SegmentStraddles a b)) -> sortOn coords2 [a, b] `shouldSatisfy` (\ends -> and (zipWith close ends [V2 0 0, V2 1 0]) && length ends == 2)
        other -> expectationFailure ("expected edge south refused as lying across the fold, got " <> show other)

    it "a move it does not make yet, by name" $
      refusal (runOn (oneStep (turnOver LeftRight))) `shouldBe` Just (MoveNotRunYet "\"turn over\"")
  where
    coords (V3 x y z) = [x, y, z]
    coords2 (V2 x y) = [x, y]
    close (V2 x y) (V2 x' y') = abs (x - x') < 1e-12 && abs (y - y') < 1e-12
    refusal = \case
      Left (StepRefused _ _ _ failure) -> Just failure
      _ -> Nothing

-- The quarter fold, PRD 09's test 1: each fold lays one side of the sheet
-- onto the opposite side, L1 to L2, about creases the sheet has. The fixture
-- holds the states its author folded by hand, so the run's angles have
-- something independent to equal.
quartered :: Spec
quartered = describe "the quarter fold" $ do
  sheet <- runIO (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  records <- runIO (right (runRecords <$> (checkSequence quarterFold >>= runSequence defaultRunSettings (M.singleton "examples/quarter-fold-steps.fold" sheet) . elaborate)))

  it "folds in half about edges 8 and 10, then in quarters about 9 and 11" $
    map (sort . concatMap snd . recordHinge) records `shouldBe` [[EdgeId 8, EdgeId 10], [EdgeId 9, EdgeId 11]]

  -- The second fold, one valley fold, writes edge 9 at +180 and edge 11 at
  -- -180: both faces beside edge 11 were turned over by the first (PRD
  -- decisions D5, "the line that looks like a typo").
  it "ends each fold at the angles the fixture's author wrote" $
    map (snd . recordAngles) records `shouldBe` map edgesFoldAngle (otherFrames sheet)

  -- PRD 02 §6.3: the seed is the vertex mean of the face beside the first
  -- line's longest piece, ties to the lowest, then the leftmost. Edge west's
  -- lower half for the first fold; edge north's west half, (1/4, 3/4), for
  -- the second, as §6.3 works it.
  it "keeps as each seed the face beside the first side's lowest, then leftmost, piece" $
    map (map fst . recordMoving) records `shouldBe` [[MaterialPoint (V2 0.25 0.25)], [MaterialPoint (V2 0.25 0.75)]]

-- A run that reaches not modelled stops there and still succeeds, keeping
-- every move made before it, so that the states up to the gap can be
-- written and drawn (PRDs/decisions.md, D21; PRD 04's A18).
stopping :: Spec
stopping = describe "a run that reaches not modelled" $ do
  sheet <- runIO (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  let runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings (M.singleton "examples/quarter-fold-steps.fold" sheet) . elaborate
      -- The quarter fold, its second step's moves given, and then its second
      -- fold, which would leave a record of step 3 if a run went on past a
      -- stop at step 2.
      quarterWith second = sequenceOf (header "A square folded into quarters" (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (1 / 4)))) $ do
        _ <- step "half" "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
        _ <- step "quarter" "Fold the top half down in front, onto the bottom." second
        step_ "Fold the top half down in front, onto the bottom." (fold inFront (LineOnto (edge North) (edge South) Nothing))
      quarterStop = RunStop 2 (Just (Name "quarter")) (Just "Fold the top half down in front, onto the bottom.") NoSpan "fold in quarters"

  it "stops at its step, keeping the moves before it and running none after (A18)" $ do
    run <- right (runOn (quarterWith (notModelled "fold in quarters")))
    map recordStep (runRecords run) `shouldBe` [1]
    runStop run `shouldBe` Just quarterStop
    runRefusal run `shouldBe` Just (StepRefused 2 (Just (Name "quarter")) NoSpan (NotModelledStop "fold in quarters"))
    fmap explain (runRefusal run) `shouldSatisfy` maybe False (T.isPrefixOf "step 2 (quarter): \"fold in quarters\" is not modelled")

  -- Stopped before any move, the run has no record, and still succeeds.
  it "stops at the first step with no record made" $ do
    run <- right (runOn (sequenceOf (header "Not yet" (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (1 / 4)))) (step_ "Squash it." (notModelled "squash fold"))))
    runRecords run `shouldBe` []
    runStop run `shouldBe` Just (RunStop 1 Nothing (Just "Squash it.") NoSpan "squash fold")

  it "keeps a move its own step made before the stop" $ do
    run <- right (runOn (quarterWith (fold inFront (LineOnto (edge North) (edge South) Nothing) >> notModelled "squash the corner")))
    map recordStep (runRecords run) `shouldBe` [1, 2]
    fmap stopText (runStop run) `shouldBe` Just "squash the corner"

  -- not modelled names no paper, so no kind matches it, and the expectation
  -- passes it on: the run stops there just the same.
  it "stops inside expect refused too, which cannot name it" $ do
    run <- right (runOn (quarterWith (expectRefused (RefusalKind "FlapCollision") (NotModelled "fold in quarters"))))
    runStop run `shouldBe` Just quarterStop
    runExpected run `shouldBe` []

  it "has no stop and nothing to refuse when it runs to the end" $ do
    run <- right (runOn quarterFold)
    (runStop run, runRefusal run) `shouldBe` (Nothing, Nothing)

-- A turn blocked part-way. Folding needs paper lying flat, so only an
-- unfold can turn paper with something standing in its way. On the
-- accordion, c1 lays the last strip on the third; the left half is then
-- turned 135 degrees in front, so it leans over them in the air; and
-- unfolding c1 lifts the last strip back up into it. The sweep, which checks
-- the whole path before the turn's ends are judged, refuses it, with a
-- witness a quarter of the way along: a point of contact, not the first.
blocked :: Spec
blocked = describe "a turn blocked part-way" $ do
  accordion <- runIO (loadFoldFile "examples/accordion.fold" >>= right)
  let runWith settings sequence' = checkSequence sequence' >>= runSequence settings (M.singleton "examples/accordion.fold" accordion) . elaborate
      along x seed amount = Fold ValleyFold amount (Segment (at x 0) (at x 1)) FlapOfFirstArgument (Just (CornerOf seed))
      unfoldInto wrap = sequenceOf (header "Into a leaning flap" (sheetFile "examples/accordion.fold") (Just (at (5 / 8) (1 / 2)))) $ do
        c1 <- step "c1" "Lay the last strip on the third, in front." (move (along (3 / 4) SouthEast ToFlat))
        step_ "Lean the left half over them." (move (along (1 / 2) SouthWest (Degrees 135)))
        step_ "Open the last strip again." (move (wrap (Unfold [refName c1])))

  it "is refused as FlapCollision part-way through, at step 3" $
    case runWith defaultRunSettings (unfoldInto id) of
      Left err@(StepRefused 3 _ _ (FlapRefused (FlapCollision t _))) -> do
        t `shouldSatisfy` (\progress -> progress > 0 && progress < 1)
        refusalKindOf err `shouldBe` Just (RefusalKind "FlapCollision")
      other -> expectationFailure ("expected a collision at step 3, got " <> either (show . explain) (show . length . runRecords) other)

  it "and runs, with the outcome kept, when the sequence expects it" $ do
    run <- right (runWith defaultRunSettings (unfoldInto (ExpectRefused (RefusalKind "FlapCollision"))))
    length (runRecords run) `shouldBe` 2
    runExpected run `shouldBe` [ExpectedRefusal 3 1 (RefusalKind "FlapCollision")]

  -- With no depth to subdivide, the sweep can neither clear the turn nor find
  -- the flap in the way: it gives up, and that is a refusal of its own.
  it "is unresolved by a sweep with no depth, and that can be expected too" $ do
    let shallow = defaultRunSettings {runSweep = SweepSettings 0 1}
    case runWith shallow (unfoldInto id) of
      Left err@(StepRefused 3 _ _ (FlapRefused FlapUnresolved {})) -> refusalKindOf err `shouldBe` Just (RefusalKind "FlapUnresolved")
      other -> expectationFailure ("expected the unfold at step 3 unresolved, got " <> either (show . explain) (show . length . runRecords) other)
    run <- right (runWith shallow (unfoldInto (ExpectRefused (RefusalKind "FlapUnresolved"))))
    runExpected run `shouldBe` [ExpectedRefusal 3 1 (RefusalKind "FlapUnresolved")]

starting :: Spec
starting = describe "the state a run starts from" $ do
  -- The fixture records its four corners folded in, at -180. Turns red if a
  -- file angle survives, or if a crease lying flat loses the M it was drawn
  -- with.
  it "lays the blintz flat and keeps its creases mountains" $ do
    state <- start "examples/blintz-base.fold"
    let frame = workingPattern state
    edgesFoldAngle frame `shouldBe` replicate (length (edgesVertices frame)) 0
    [edgesAssignment frame !! e | e <- [8 .. 11]] `shouldBe` replicate 4 Mountain
    faceOrders frame `shouldBe` []
    length (facesVertices frame) `shouldBe` 5

  -- The central square is largest, and its vertex mean is the centre, which
  -- is where `anchor centre` puts it too. Turns red if the anchor's face were
  -- not put first: folding holds its first face still.
  it "anchors the blintz at the centre of its central square, put first" $ do
    state <- start "examples/blintz-base.fold"
    stateAnchor state `shouldBe` MaterialPoint (V2 0.5 0.5)
    firstMean <- faceMean (workingPattern state) 0
    firstMean `shouldBe` V2 0.5 0.5

  -- All four faces tie on area; faces 0 and 3 tie on height, and face 3 is
  -- further left. Turns red if ties went by face id or by the highest mean.
  it "breaks a tie on area by the lowest and then the leftmost vertex mean" $ do
    state <- start "examples/quarter-fold-steps.fold"
    stateAnchor state `shouldBe` MaterialPoint (V2 0.25 0.25)
    firstMean <- faceMean (workingPattern state) 0
    firstMean `shouldBe` V2 0.25 0.25

  -- A sheet halved at x = 1/2 - 1e-13: the right half is larger by 2e-13, a
  -- difference rounding could make, so the halves tie on area and on height,
  -- and the left half wins as the leftmost. Turns red if areas were compared
  -- exactly, when the right half would win.
  it "treats areas that differ only by rounding as tied" $ do
    let x = 0.5 - 1e-13
        halves =
          emptyFrame
            { verticesCoords = [[0, 0], [x, 0], [1, 0], [1, 1], [x, 1], [0, 1]],
              edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0), (1, 4)]],
              edgesAssignment = replicate 6 Border ++ [Mountain]
            }
    state <- right (sheetState (withKey (const halves) squareSheet))
    case stateAnchor state of
      MaterialPoint (V2 ax _) -> ax `shouldSatisfy` (< 0.5)

  -- crane.fold writes no angles: 58 M, 41 V, 20 F and 10 B. Turns red if any
  -- letter is rewritten, F at 0 included.
  it "keeps every crease's letter as drawn when nothing contradicts it" $ do
    file <- load "examples/crane.fold"
    state <- right (sheetState file)
    edgesAssignment (workingPattern state) `shouldBe` edgesAssignment (keyFrame file)

  -- F means unfolded, so an F at an angle contradicts itself and the angle
  -- is believed. U says only that the direction is undecided, so it stays U
  -- at any angle. Turns red if the angle were trusted over U, or F kept at an
  -- angle.
  it "believes an F crease's angle, and keeps U at any angle" $
    forM_ [(Flat, -90, Mountain), (Flat, 90, Valley), (Flat, 0, Flat), (Flat, 1e-11, Flat), (Unassigned, 45, Unassigned)] $ \(letter, angle, expected) -> do
      state <- right (sheetState (diagonal letter angle))
      let frame = workingPattern state
      [a | ((VertexId 0, VertexId 2), a) <- zip (edgesVertices frame) (edgesAssignment frame)] `shouldBe` [expected]
      edgesFoldAngle frame `shouldBe` replicate 5 0

  -- A face's normal points the way its ring turns, so a clockwise ring would
  -- face the other way from the file's +z.
  it "winds every face anticlockwise on the sheet" $ do
    state <- right (sheetState (squareWith [3, 2, 1, 0]))
    area <- faceArea (workingPattern state) 0
    area `shouldSatisfy` (> 0)
    forM_ ["examples/blintz-base.fold", "examples/crane.fold", "examples/bird-base.fold"] $ \path -> do
      frame <- workingPattern <$> start path
      areas <- mapM (faceArea frame) [0 .. length (facesVertices frame) - 1]
      areas `shouldSatisfy` all (> 0)

  it "starts sheet square as the unit square, anchored at its centre" $ do
    state <- right (sheetState squareSheet)
    length (facesVertices (workingPattern state)) `shouldBe` 1
    edgesAssignment (workingPattern state) `shouldBe` replicate 4 Border
    stateAnchor state `shouldBe` MaterialPoint (V2 0.5 0.5)

  describe "refuses a sheet that is not paper before folding" $ do
    -- The file keeps its paper in sixteen folded states, not a key frame.
    it "with an empty key frame, naming the file's frames" $ do
      file <- load "examples/bird-base-sequence.fold"
      sheetState file `shouldBe` Left (SheetHasNoVertices 16)
      explain (SheetRefused NoSpan "examples/bird-base-sequence.fold" (SheetHasNoVertices 16))
        `shouldSatisfy` T.isPrefixOf "sheet \"examples/bird-base-sequence.fold\": its key frame has no vertices; the file keeps its paper in 16 file_frames"

    it "already folded, by its relief or by its class" $ do
      file <- load "examples/simple.fold"
      case sheetState file of
        Left (SheetAlreadyFolded (ByRelief z)) -> z `shouldSatisfy` (> 0)
        other -> expectationFailure ("expected a relief refusal, got " <> show other)
      sheetState (withKey (\f -> f {frameClasses = ["foldedForm"]}) squareSheet) `shouldBe` Left (SheetAlreadyFolded ByClass)

    -- An L whose arms are a tenth wide: its corners average to a point in
    -- the empty quarter. Turns red if the anchor were taken without asking
    -- whether it lies on paper.
    it "whose default anchor falls outside its only face" $ do
      let l = [[0, 0], [1, 0], [1, 0.1], [0.1, 0.1], [0.1, 1], [0, 1]]
          frame = emptyFrame {verticesCoords = l, edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 6)) | i <- [0 .. 5]], edgesAssignment = replicate 6 Border, facesVertices = [map VertexId [0 .. 5]]}
      case sheetState (withKey (const frame) squareSheet) of
        Left (DefaultAnchorOutside (V2 x y)) -> (x, y) `shouldSatisfy` (\(a, b) -> abs (a - 2.2 / 6) < 1e-12 && abs (b - 2.2 / 6) < 1e-12)
        other -> expectationFailure ("expected the anchor refused, got " <> show other)

    -- The same question on a face that is not convex but whose mean is on
    -- paper: a thick arm three long and a short one, the mean (7/6, 2/5) in
    -- the long arm. Turns red if a convex-only test were used, which calls the
    -- mean outside because it lies beyond the line of the short arm's inner
    -- side.
    it "but not a mean that lies on paper in a face that is not convex" $ do
      let l = [[0, 0], [3, 0], [3, 0.5], [0.5, 0.5], [0.5, 0.7], [0, 0.7]]
          frame = emptyFrame {verticesCoords = l, edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 6)) | i <- [0 .. 5]], edgesAssignment = replicate 6 Border, facesVertices = [map VertexId [0 .. 5]]}
      state <- right (sheetState (withKey (const frame) squareSheet))
      case stateAnchor state of
        MaterialPoint (V2 x y) -> (x, y) `shouldSatisfy` (\(a, b) -> abs (a - 7 / 6) < 1e-12 && abs (b - 0.4) < 1e-12)
  where
    load path = loadFoldFile path >>= right
    start path = load path >>= right . sheetState
    -- The unit square cut by one crease from corner 0 to corner 2.
    diagonal letter angle =
      withKey
        ( \f ->
            f
              { edgesVertices = edgesVertices f ++ [(VertexId 0, VertexId 2)],
                edgesAssignment = edgesAssignment f ++ [letter],
                edgesFoldAngle = replicate 4 0 ++ [angle],
                facesVertices = []
              }
        )
        squareSheet
    squareWith ring = withKey (\f -> f {facesVertices = [map VertexId ring]}) squareSheet
    withKey change file = file {keyFrame = change (keyFrame file)}

-- | A face's ring on the sheet, from the frame's own vertices.
ringOf :: Frame -> Int -> IO [V2]
ringOf frame face = do
  points <- right (frameVertices frame)
  pure [V2 x y | VertexId i <- facesVertices frame !! face, let V3 x y _ = points !! i]

faceArea :: Frame -> Int -> IO Double
faceArea frame face = signedArea <$> ringOf frame face

faceMean :: Frame -> Int -> IO V2
faceMean frame face = do
  ring <- ringOf frame face
  let n = fromIntegral (length ring)
  pure (V2 (sum [x | V2 x _ <- ring] / n) (sum [y | V2 _ y <- ring] / n))

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
