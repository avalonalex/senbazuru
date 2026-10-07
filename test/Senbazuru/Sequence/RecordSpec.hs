-- | A move record's rules, checked on real turns: the five of the study's
-- blintz recipe, each paired with the move of the language's blintz that asks
-- for it. The two fold the same corners in the same order (south-east,
-- north-east, north-west, south-west, then south-east again to reopen it), so
-- each record's origin is the move that really asks for its turn. The runner
-- will make this pairing itself; until then the test makes it by hand.
module Senbazuru.Sequence.RecordSpec (spec) where

import BlintzSequence (BlintzMove (..), buildBlintzSequence)
import Control.Monad (forM_)
import Data.List (sort, sortOn, zip5)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (modelSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flap (flapAt)
import Senbazuru.Origami.Surface
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate
import Senbazuru.Sequence.Record
import Senbazuru.Sequence.Syntax (Move (..), Name (..))
import Test.Hspec
import Test.SequenceExamples (blintz, blintzCaptions)

spec :: Spec
spec = describe "a move record" $ do
  source <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  turns <- runIO (right (buildBlintzSequence (keyFrame source)))
  elaborated <- runIO (right (elaborate <$> checkSequence blintz))
  let places = [(step, elaboratedName s, elaboratedCaption s, coreOrigin m) | (step, s) <- zip [1 ..] (elaboratedSteps elaborated), m <- elaboratedMoves s]
  records <- runIO . right $ sequence [hingeTurn step 1 name caption origin [(hinge, [EdgeId e])] (MaterialPoint corner) [] (blintzMotion turn) | ((step, name, caption, origin), turn, corner, hinge, e) <- zip5 places turns corners hinges edges]

  -- If the language's blintz or the recipe changed order, every test below
  -- would be about the wrong pairs.
  it "pairs each of the recipe's five turns with the move that asks for it" $ do
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
      Right (recordBefore record) `shouldBe` flapAt (blintzMotion turn) 0
      recordAfter record `shouldBe` blintzEnd turn
      recordEvidence record `shouldBe` SweptHinge (blintzMotion turn)

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
    isFold move = case move of
      Fold {} -> True
      _ -> False

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
