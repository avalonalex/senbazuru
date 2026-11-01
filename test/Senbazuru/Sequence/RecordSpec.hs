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
-- turn moved the paper.
module Senbazuru.Sequence.RecordSpec (spec) where

import Control.Monad (forM_)
import Data.List (sort, sortOn, zip5)
import Data.Map.Strict qualified as M
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Rigid (applyRigid, identity)
import Senbazuru.Geometry.V3 (V3 (..), modelSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flap (CheckedFlap, flapAt)
import Senbazuru.Origami.Surface
import Senbazuru.Sequence.Build (header, move, sequenceOf, sheetSquare, step_, turnOver)
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
