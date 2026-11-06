-- | A move record's rules, checked on real turns: the five a run of the
-- language's blintz makes, each made into a record again here by 'hingeTurn'
-- and paired by hand with the move that asks for it (south-east, north-east,
-- north-west, south-west, then south-east again to reopen it). Where a turn
-- came from does not matter to these rules; what 'hingeTurn' makes of it
-- does, and so the records here are made by this test, not taken from the
-- run.
--
-- The sense a page reads ('recordSense', 'recordUnfolds') is the other way
-- round: it comes from the move a run made the record for, so those tests
-- take the run's own records, and hold each sense to the way its own checked
-- turn moved the paper. So do the tests of a surface as the reader sees it
-- ('displayedFrame'), which hold each record's surfaces, under the record's
-- own displays, to the states the run writes on either side of its step,
-- the tests of the line a turn-over or a rotate turned about
-- ('presentationAxis'), which hold it to the presentations the run recorded,
-- and the tests of a pre-crease's folded pose ('recordFoldedPose'), which
-- hold it to the end of the pre-crease's own checked turn.
module Senbazuru.Sequence.RecordSpec (spec) where

import Control.Monad (forM_)
import Data.List (nub, sort, sortOn, zip5)
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Rigid (Rigid, applyRigid, identity, rotationAboutDegrees)
import Senbazuru.Geometry.Rigid qualified as Rigid
import Senbazuru.Geometry.V3 (V3 (..), modelSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flap (CheckedFlap, flapAt)
import Senbazuru.Origami.Surface
import Senbazuru.Sequence.Build (Build, anchor, at, behind, fold, header, inFront, move, rotate, sequenceOf, sheetFile, sheetSquare, step_, turnOver)
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate
import Senbazuru.Sequence.Error (SequenceError)
import Senbazuru.Sequence.Record
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import Senbazuru.Sequence.Syntax (Compass (..), Corner (..), Layers (..), Line (..), Move (..), Name (..), Point (..), Sequence)
import Test.Hspec
import Test.SequenceExamples (blintz, blintzCaptions, quarterFold)

spec :: Spec
spec = describe "a move record" $ do
  source <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  quarterSheet <- runIO (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  elaborated <- runIO (right (elaborate <$> checkSequence blintz))
  turns <- runIO (right (runSequence defaultRunSettings (M.singleton "examples/blintz-base.fold" source) elaborated) >>= mapM turnOf . runRecords)
  let places = [(step, elaboratedName s, elaboratedCaption s, coreOrigin m) | (step, s) <- zip [1 ..] (elaboratedSteps elaborated), m <- elaboratedMoves s]
  records <- runIO . right $ sequence [hingeTurn step 1 name caption origin [(hinge, [EdgeId e])] [] (MaterialPoint (V2 0.5 0.5), MaterialPoint (V2 0.5 0.5)) identity identity (MaterialPoint corner) [] turn | ((step, name, caption, origin), turn, corner, hinge, e) <- zip5 places turns corners hinges edges]

  -- If the language's blintz changed order, every test below would be about
  -- the wrong pairs.
  it "pairs each of the run's five turns with the move that asks for it" $ do
    length records `shouldBe` 5
    [isFold (originWritten (recordOrigin r)) | r <- records] `shouldBe` [True, True, True, True, False]
    map (originWritten . recordOrigin) (drop 4 records) `shouldBe` [Unfold [Name "c1"]]

  -- Turns red if 'hingeTurn' swapped the step and the move, or dropped a
  -- step's name or caption.
  it "says which step and move it is" $ do
    map recordStep records `shouldBe` [1 .. 5]
    map recordMoveIndex records `shouldBe` replicate 5 1
    map recordStepName records `shouldBe` Just (Name "c1") : replicate 4 Nothing
    map recordCaption records `shouldBe` map Just blintzCaptions

  -- Turns red if a surface came from anywhere but the record's own turn,
  -- or the two were swapped.
  it "takes both surfaces and its evidence from the turn it records" $
    forM_ (zip records turns) $ \(record, turn) -> do
      Right (recordBefore record) `shouldBe` flapAt turn 0
      Right (recordAfter record) `shouldBe` flapAt turn 1
      recordEvidence record `shouldBe` SweptHinge turn

  -- One numbering: a turn that cut the paper would renumber it, and the ids
  -- in the record would then mean different paper in the two surfaces.
  it "numbers both of its surfaces alike" $
    forM_ records $ \record -> do
      let startFrame = surfaceFrame (recordBefore record)
          endFrame = surfaceFrame (recordAfter record)
      map sort (facesVertices endFrame) `shouldBe` map sort (facesVertices startFrame)
      edgesVertices endFrame `shouldBe` edgesVertices startFrame

  -- Unpresented: the face held still lies exactly where it lay. Turns red if
  -- the surface after were turned over or spun for a page, or if the face
  -- returned were one that moves. On every blintz turn it is the central
  -- square, face 0, which the recipe puts first.
  it "holds the face beside the hinge where it lay, the centre each time" $
    forM_ records $ \record -> do
      recordStationary record `shouldBe` FaceId 0
      let centre surface = do
            points <- frameVertices (surfaceFrame surface)
            pure [points !! i | ring <- take 1 (facesVertices (surfaceFrame surface)), VertexId i <- ring]
      startCentre <- right (centre (recordBefore record))
      endCentre <- right (centre (recordAfter record))
      length startCentre `shouldBe` 4
      let scale = modelSpan startCentre
      zipWith (\p q -> norm (p ^-^ q) <= 1e-12 * scale) startCentre endCentre `shouldBe` replicate (length startCentre) True

  -- Turns red if the angles were read from one surface twice, kept in
  -- radians, or stored once and left stale: each move changes exactly its
  -- own hinge, by exactly its turn.
  it "reads every crease's angle before and after from its two surfaces" $
    forM_ (zip3 records edges travels) $ \(record, e, travel) -> do
      let (anglesBefore, anglesAfter) = recordAngles record
          changed = [i | (i, a, b) <- zip3 [0 :: Int ..] anglesBefore anglesAfter, a /= b]
      changed `shouldBe` [e]
      (anglesAfter !! e) - (anglesBefore !! e) `shouldSatisfy` (\d -> abs (d - travel) < 1e-9)

  -- The paper a move ends with is the paper the next move starts from:
  -- layer orders and angles exactly, positions within the recipe's join
  -- bound. The material study reads its contact pairs from a record's
  -- before, and a turn works out the orders across its hinge afresh from
  -- where its paper touches, so an order lost at a join would be a contact
  -- missing from a settle.
  it "hands its after to the next record as that record's before" $
    forM_ (zip records (drop 1 records)) $ \(record, next) -> do
      let ends = surfaceFrame (recordAfter record)
          starts = surfaceFrame (recordBefore next)
          key o = (orderFace o, orderRelativeTo o)
      sortOn key (faceOrders starts) `shouldBe` sortOn key (faceOrders ends)
      edgesFoldAngle starts `shouldBe` edgesFoldAngle ends
      endPoints <- right (frameVertices ends)
      startPoints <- right (frameVertices starts)
      length startPoints `shouldBe` length endPoints
      let scale = modelSpan endPoints
      and (zipWith (\p q -> norm (p ^-^ q) <= 1e-12 * scale) endPoints startPoints) `shouldBe` True

  -- Turns red if the moving faces came from the side held still, or the
  -- seed were dropped.
  it "keeps the paper it moved under the seed that picked it out" $
    map recordMoving records `shouldBe` [[(MaterialPoint corner, [FaceId f])] | (corner, f) <- zip corners movingFaces]
  -- 01 §3.3 and D7: each arrow is drawn with its record's kind, which a page
  -- reads from the record, never from the move as written, whose type it may
  -- not import. Each sense is held to the way the record's own checked turn
  -- carried the paper as the reader sees it, so a sense that disagreed with
  -- the turn the runner made turns these red. None of these records leaves a
  -- crease lettered V or M, so a sense read from the crease's letter is
  -- caught by RunSpec's turn-over case, not here.
  describe "the sense a page reads" $ do
    it "gives the quarter fold mountain then valley, and the blintz four mountains then an unfold" $ do
      quarter <- right (runOn (M.singleton "examples/quarter-fold-steps.fold" quarterSheet) quarterFold)
      blintzRun <- right (runOn (M.singleton "examples/blintz-base.fold" source) blintz)
      map recordSense (runRecords quarter) `shouldBe` [Just MountainFold, Just ValleyFold]
      map recordUnfolds (runRecords quarter) `shouldBe` [False, False]
      map recordSense (runRecords blintzRun) `shouldBe` replicate 4 (Just MountainFold) <> [Nothing]
      map recordUnfolds (runRecords blintzRun) `shouldBe` replicate 4 False <> [True]

    it "gives each pre-crease the sense written, and a turn-over none" $ do
      crane <- right (runOn M.empty openingWithAMountain)
      map recordSense (runRecords crane) `shouldBe` [Just ValleyFold, Just ValleyFold, Nothing, Just MountainFold, Just ValleyFold]
      map recordUnfolds (runRecords crane) `shouldBe` replicate 5 False

    it "agrees with the way each record's own turn carried the paper, as the reader sees it" $ do
      quarter <- right (runOn (M.singleton "examples/quarter-fold-steps.fold" quarterSheet) quarterFold)
      blintzRun <- right (runOn (M.singleton "examples/blintz-base.fold" source) blintz)
      crane <- right (runOn M.empty openingWithAMountain)
      let sensed = [r | run <- [quarter, blintzRun, crane], r <- runRecords run, Just _ <- [recordSense r]]
      length sensed `shouldBe` 2 + 4 + 4
      forM_ sensed $ \record -> do
        moved <- towardsReader record
        (recordStep record, recordMoveIndex record, recordSense record, fmap signum moved)
          `shouldBe` (recordStep record, recordMoveIndex record, recordSense record, Just (if recordSense record == Just ValleyFold then 1 else -1))
  -- A record's surfaces under its displays, as a page of steps will draw them
  -- (06 R-06-16), against the states the run writes. 'writtenStates' shows its
  -- states by 'displayedFrame' too, so these hold the pairing, each surface
  -- with its own side's display; the arithmetic inside 'displayedFrame' is held
  -- by RunSpec's tests that compare the written states with literal
  -- coordinates, a rotate's corners, or with another run's ('sameModel'
  -- across a re-anchoring). Every record held here is alone in its step and
  -- creases nothing, so its before is the state written before it; a move
  -- that creases adds its new crease to its before.
  describe "a surface as the reader sees it" $ do
    -- Nothing turns the blintz on the page or re-anchors it, so every display
    -- here is the identity and this cannot tell one display from another. It
    -- holds that a record's before and after are the surfaces its step starts
    -- and ends on: red if the two were swapped, since every blintz record
    -- turns paper. The two tests below hold which display goes with which.
    it "shows each blintz record's before and after exactly as the states either side of its step" $ do
      blintzRun <- right (runOn (M.singleton "examples/blintz-base.fold" source) blintz)
      states <- right (writtenStates blintzRun)
      map recordStep (runRecords blintzRun) `shouldBe` [1 .. 5]
      [(displayBefore r, displayAfter r) | r <- runRecords blintzRun] `shouldBe` replicate 5 (identity, identity)
      [verticesCoords (displayedFrame (recordBefore r) (displayBefore r)) | r <- runRecords blintzRun]
        `shouldBe` map (verticesCoords . stateFrame) (take 5 states)
      [verticesCoords (displayedFrame (recordAfter r) (displayAfter r)) | r <- runRecords blintzRun]
        `shouldBe` map (verticesCoords . stateFrame) (drop 1 states)

    -- The crane's opening turned over left to right, alone in its step: its
    -- before as state 1 was written, and its after as state 2, the paper's
    -- corners swapped across the vertical line through the middle. Literal,
    -- so that a display ignored, or read from the other side, shows here
    -- whatever the written states do. Red if the display were dropped, or the
    -- after paired with the display before.
    it "shows the crane opening's turn-over before and after as states 1 and 2" $ do
      crane <- right (runOn M.empty openingWithAMountain)
      states <- right (writtenStates crane)
      case ([r | r <- runRecords crane, recordKind r == Presentation (TurnedOver LeftRight)], drop 1 states) of
        ([turn], state1 : state2 : _) -> do
          verticesCoords (displayedFrame (recordBefore turn) (displayBefore turn)) `shouldBe` [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0.5, 0.5, 0]]
          verticesCoords (displayedFrame (recordAfter turn) (displayAfter turn)) `shouldBe` [[1, 0, 0], [0, 0, 0], [0, 1, 0], [1, 1, 0], [0.5, 0.5, 0]]
          verticesCoords (displayedFrame (recordBefore turn) (displayBefore turn)) `shouldBe` verticesCoords (stateFrame state1)
          verticesCoords (displayedFrame (recordAfter turn) (displayAfter turn)) `shouldBe` verticesCoords (stateFrame state2)
        _ -> expectationFailure "expected one turn-over and at least three states"

    -- The quarter fold re-anchored onto the corner its first fold turns, so
    -- placed from step 2 by a half turn about the line x = 1/2, then turned an
    -- eighth, over top to bottom, and back three eighths. None of the three
    -- presentations commutes with the half turn, so placed then presented
    -- differs from presented then placed at steps 3 to 5. Red if
    -- 'displayAfter' composed them the other way round.
    it "shows every record's before and after as the states either side of its step, placed then presented" $ do
      run <- right (runOn (M.singleton "examples/quarter-fold-steps.fold" quarterSheet) oddEighths)
      states <- right (writtenStates run)
      let byStep = M.fromList [(k, verticesCoords (stateFrame st)) | st <- states, Just k <- [stateStep st]]
      map recordStep (runRecords run) `shouldBe` [1 .. 5]
      [verticesCoords (displayedFrame (recordBefore r) (displayBefore r)) | r <- runRecords run]
        `shouldBe` map (verticesCoords . stateFrame) (take 5 states)
      [(recordStep r, Just (verticesCoords (displayedFrame (recordAfter r) (displayAfter r)))) | r <- runRecords run]
        `shouldBe` [(recordStep r, M.lookup (recordStep r) byStep) | r <- runRecords run]

  -- 06 §2's turn-over and rotate row: a page draws a turn-over's loop on the
  -- line the turn was about, and a rotate's mark at its middle, from the
  -- record alone. Each case turns the presentation before by the amount
  -- written, about the record's line, and must land exactly on the
  -- presentation after, which the runner computed by its own route.
  describe "the line a presentation turns about" $ do
    -- The quarter fold re-anchors onto (1/4, 1/4) at step 2, a quarter lying
    -- face down, so the model as folded from it is placed by a half turn
    -- about x = 1/2: its middle as folded is (1/4, 1/4), and as shown
    -- (3/4, 1/4), half a sheet away. Red if the line ran through the middle
    -- as folded, or the direction were not the one the move names.
    it "runs through the middle of the model as shown, after re-anchoring, for a turn-over and a rotate" $ do
      forM_ [(turnOver LeftRight, V3 0 1 0), (rotate 2 Anticlockwise, V3 0 0 1)] $ \(turn, along) -> do
        run <- right (runOn (M.singleton "examples/quarter-fold-steps.fold" quarterSheet) (reanchoredQuarter "A quarter fold, presented" (step_ "Present it." turn)))
        case [r | r <- runRecords run, recordStep r == 3] of
          [presenting] -> do
            presentationAxis presenting `shouldBe` Just (V3 0.75 0.25 0, along)
            turnedAbout presenting `shouldBe` Just (snd (recordPresentation presenting))
          found -> expectationFailure ("expected one record at step 3, got " <> show (length found))

    -- After an eighth, a turn-over top to bottom and three eighths back, so
    -- each presentation but the first starts from one already turned, by an
    -- odd eighth whose entries are rounded. Red if a clockwise rotate's line
    -- pointed away from the reader while its amount stayed negative.
    it "turns each presentation before onto the one after, by the amount written" $ do
      run <- right (runOn (M.singleton "examples/quarter-fold-steps.fold" quarterSheet) oddEighths)
      let presentings = [r | r <- runRecords run, Presentation _ <- [recordKind r]]
      map recordKind presentings `shouldBe` [Presentation (Rotated 1 Anticlockwise), Presentation (TurnedOver TopBottom), Presentation (Rotated 3 Clockwise)]
      [turnedAbout r | r <- presentings] `shouldBe` [Just (snd (recordPresentation r)) | r <- presentings]

    -- Red if a fold, a pre-crease, an unfold or an anchor gave a line: the
    -- runs hold each of those kinds, the last from a square anchored afresh
    -- with @anchor P@.
    it "gives no line for a move that is not a change of presentation" $ do
      run <- right (runOn (M.singleton "examples/quarter-fold-steps.fold" quarterSheet) oddEighths)
      blintzRun <- right (runOn (M.singleton "examples/blintz-base.fold" source) blintz)
      crane <- right (runOn M.empty openingWithAMountain)
      held <- right (runOn M.empty (sequenceOf (header "A square" sheetSquare Nothing) (step_ "Hold it here." (anchor (at (1 / 4) (1 / 4))))))
      let others = [r | each <- [run, blintzRun, crane, held], r <- runRecords each, not (isPresentation (recordKind r))]
      length others `shouldBe` 2 + 5 + 4 + 1
      sort (nub [show (recordKind r) | r <- others]) `shouldBe` ["Anchoring", "Precrease", "Turn"]
      map presentationAxis others `shouldBe` map (const Nothing) others

  describe "a pre-crease's folded pose" $ do
    -- 06 §7's pre-crease on sheet square: the moving triangle (0, 0),
    -- (1, 0), (1, 1) has corner mean (2/3, 1/3), and folded flat across
    -- y = x it lies on (1/3, 2/3). Red if the pose were the paper laid flat
    -- again, or the record's after kept the fold's end.
    it "takes the moving triangle's middle across the diagonal, and still ends where it began" $ do
      run <- right (runOn M.empty (sequenceOf (header "A square" sheetSquare Nothing) (step_ "Crease a diagonal." (move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthWest) (CornerOf NorthEast)) FlapOfFirstArgument (Just (CornerOf SouthEast)))))))
      record <- case runRecords run of
        [r] -> pure r
        found -> fail ("expected one record, got " <> show (length found))
      recordKind record `shouldBe` Precrease
      pose <- maybe (fail "a pre-crease with no folded pose") pure (recordFoldedPose record)
      case placedAt pose (V2 (2 / 3) (1 / 3)) of
        Just p -> norm (p ^-^ V3 (1 / 3) (2 / 3) 0) `shouldSatisfy` (< 1e-12)
        Nothing -> expectationFailure "(2/3, 1/3) is in no face of the folded pose"
      recordAfter record `shouldBe` recordBefore record

    -- The crane opening's four pre-creases, two of them after a turn-over,
    -- and every other kind of record. Red if the pose were rebuilt from
    -- anything but the record's own turn, numbered afresh, or given to a
    -- move that is not a pre-crease.
    it "is the end of the pre-crease's own turn, numbered as its before, and only a pre-crease has one" $ do
      quarter <- right (runOn (M.singleton "examples/quarter-fold-steps.fold" quarterSheet) oddEighths)
      blintzRun <- right (runOn (M.singleton "examples/blintz-base.fold" source) blintz)
      crane <- right (runOn M.empty openingWithAMountain)
      held <- right (runOn M.empty (sequenceOf (header "A square" sheetSquare Nothing) (step_ "Hold it here." (anchor (at (1 / 4) (1 / 4))))))
      let found = [r | each <- [quarter, blintzRun, crane, held], r <- runRecords each]
          precreases = [r | r <- found, recordKind r == Precrease]
          others = [r | r <- found, recordKind r /= Precrease]
      (length precreases, length others) `shouldBe` (4, 5 + 5 + 1 + 1)
      forM_ precreases $ \record -> do
        turn <- turnOf record
        pose <- maybe (fail "a pre-crease with no folded pose") pure (recordFoldedPose record)
        Right pose `shouldBe` flapAt turn 1
        facesVertices (surfaceFrame pose) `shouldBe` facesVertices (surfaceFrame (recordBefore record))
      sort (nub [show (recordKind r) | r <- others]) `shouldBe` ["Anchoring", "Presentation (Rotated 1 Anticlockwise)", "Presentation (Rotated 3 Clockwise)", "Presentation (TurnedOver LeftRight)", "Presentation (TurnedOver TopBottom)", "Turn"]
      map recordFoldedPose others `shouldBe` map (const Nothing) others

    -- Red if a second 'asPrecrease' took the paper laid flat as the pose.
    it "keeps the fold's pose when made a pre-crease twice" $
      forM_ records $ \record -> do
        recordFoldedPose record `shouldBe` Nothing
        recordFoldedPose (asPrecrease (asPrecrease record)) `shouldBe` Just (recordAfter record)
  where
    -- The fixture's corners, in the order both blintzes fold them; the
    -- creases that cut each one off (edges 8 to 11 of
    -- examples/blintz-base.fold, between the midpoints of its sides); the
    -- face each crease turns, as the recipe numbers them; and how far.
    corners = [V2 1 0, V2 1 1, V2 0 1, V2 0 0, V2 1 0]
    edges = [8, 9, 10, 11, 8]
    hinges = [segment a b | (a, b) <- [(V2 0.5 0, V2 1 0.5), (V2 1 0.5, V2 0.5 1), (V2 0.5 1, V2 0 0.5), (V2 0 0.5, V2 0.5 0), (V2 0.5 0, V2 1 0.5)]]
    movingFaces = [2, 3, 4, 1, 2]
    travels = [-180, -180, -180, -180, 180]
    segment a b = MaterialSegment (MaterialPoint a) (MaterialPoint b)
    isFold written = case written of
      Fold {} -> True
      _ -> False

-- | A run's record's turn, which this test makes into a record again.
turnOf :: MoveRecord -> IO CheckedFlap
turnOf record = case recordEvidence record of
  SweptHinge turn -> pure turn
  _ -> fail "a blintz move that is not a turn about a hinge"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure

-- | Run a sequence on the sheets it names.
runOn :: M.Map FilePath FoldFile -> Sequence -> Either SequenceError Run
runOn sheets sequence' = checkSequence sequence' >>= runSequence defaultRunSettings sheets . elaborate

-- | The crane's opening on a plain square with one sense changed, so that a
-- pre-crease of each sense follows the turn-over: both diagonals pre-creased
-- in front, a turn-over, then the south-to-north midline behind and the
-- west-to-east one in front. The crane itself creases both midlines in front.
openingWithAMountain :: Sequence
openingWithAMountain = sequenceOf (header "A square" sheetSquare Nothing) $ do
  step_ "Crease both diagonals." $ do
    move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthWest) (CornerOf NorthEast)) FlapOfFirstArgument (Just (CornerOf SouthEast)))
    move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthEast) (CornerOf NorthWest)) FlapOfFirstArgument (Just (CornerOf SouthWest)))
  step_ "Turn the paper over." (turnOver LeftRight)
  step_ "Crease both midlines." $ do
    move (FoldAndUnfold MountainFold (LineOnto (EdgeOf South) (EdgeOf North) Nothing) FlapOfFirstArgument Nothing)
    move (FoldAndUnfold ValleyFold (LineOnto (EdgeOf West) (EdgeOf East) Nothing) FlapOfFirstArgument Nothing)

-- | The quarter fold anchored at (3/4, 3/4), in the quarter its second fold
-- turns, so that the run re-anchors onto (1/4, 1/4) and places the model by a
-- half turn about x = 1/2; then turned on the page by an eighth, over top to
-- bottom, and back by three eighths.
oddEighths :: Sequence
oddEighths = reanchoredQuarter "A quarter fold, turned on the page" $ do
  step_ "Turn the model an eighth." (rotate 1 Anticlockwise)
  step_ "Turn the model over." (turnOver TopBottom)
  step_ "Turn it back three eighths." (rotate 3 Clockwise)

-- | The quarter fold anchored at (3/4, 3/4), so that its second fold turns
-- the anchor's quarter and the run re-anchors onto (1/4, 1/4), placing the
-- model by a half turn about x = 1/2; then the steps given.
reanchoredQuarter :: Text -> Build () -> Sequence
reanchoredQuarter title rest = sequenceOf (header title (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (3 / 4)))) $ do
  step_ "Fold the left half behind." (fold behind (LineOnto (EdgeOf West) (EdgeOf East) Nothing))
  step_ "Fold the top half down in front." (fold inFront (LineOnto (EdgeOf North) (EdgeOf South) Nothing))
  rest

-- | A change of presentation's record, its presentation before turned by
-- the amount the author wrote about the record's line: 180° for a
-- turn-over, and 45° for each eighth, anticlockwise positive, as the reader
-- sees it. 'Nothing' for a record with no line.
turnedAbout :: MoveRecord -> Maybe Rigid
turnedAbout record = case (recordKind record, presentationAxis record) of
  (Presentation turn, Just (point, along)) -> Just (rotationAboutDegrees point along (written turn) `Rigid.after` fst (recordPresentation record))
  _ -> Nothing
  where
    written = \case
      TurnedOver _ -> 180
      Rotated k Anticlockwise -> 45 * fromIntegral k
      Rotated k Clockwise -> -45 * fromIntegral k

-- | Where a point of paper, named by its material coordinates, lies in a
-- surface: in the first face whose corners, on the sheet, hold it, carried
-- by the one affine map that takes three of that face's corners to where
-- they lie. Each face is split into a fan of triangles from its first
-- corner, which covers it when it is convex, as every face of a square
-- creased along straight lines is. 'Nothing' if no face holds the point.
placedAt :: Surface V2 -> V2 -> Maybe V3
placedAt surface point = case [p | face <- facesVertices (surfaceFrame surface), Just p <- map within (fan face)] of
  p : _ -> Just p
  [] -> Nothing
  where
    corners = [(sampleMaterial s, position s) | s <- surfaceSamples surface]
    fan = \case
      a : rest -> [(a, b, c) | (b, c) <- zip rest (drop 1 rest)]
      [] -> []
    within (VertexId a, VertexId b, VertexId c) = case (drop a corners, drop b corners, drop c corners) of
      ((ma, pa) : _, (mb, pb) : _, (mc, pc) : _) ->
        let cross (V2 x1 y1) (V2 x2 y2) = x1 * y2 - y1 * x2
            whole = cross (mb ^-^ ma) (mc ^-^ ma)
            u = cross (point ^-^ ma) (mc ^-^ ma) / whole
            v = cross (mb ^-^ ma) (point ^-^ ma) / whole
            slack = 1e-12
         in if whole /= 0 && u >= -slack && v >= -slack && u + v <= 1 + slack
              then Just (pa ^+^ (u *^ (pb ^-^ pa)) ^+^ (v *^ (pc ^-^ pa)))
              else Nothing
      _ -> Nothing

isPresentation :: MoveKind -> Bool
isPresentation = \case
  Presentation _ -> True
  _ -> False

-- | Which way a record's own checked turn carried the paper, as the reader
-- sees it: the total change in z, under the record's display before, of the
-- paper halfway through the turn. Positive is towards the reader, which a
-- valley fold lifts its paper to, and negative away, behind the paper, where
-- a mountain fold takes it. 'Nothing' for a record with no turn.
towardsReader :: MoveRecord -> IO (Maybe Double)
towardsReader record = case recordEvidence record of
  SweptHinge turn -> do
    start <- right (flapAt turn 0)
    halfway <- right (flapAt turn 0.5)
    let zs surface = [z | [x, y, z0] <- verticesCoords (surfaceFrame surface), let V3 _ _ z = applyRigid (displayBefore record) (V3 x y z0)]
    pure (Just (sum (zipWith (-) (zs halfway) (zs start))))
  _ -> pure Nothing
