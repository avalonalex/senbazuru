-- | The helmet base, run as a sequence, against the study's hand-written
-- recipe for it: the second of the two migrations PRDs\/09 §9 plans. The
-- recipe folds by hard-coded edge and face ids; the sequence names its paper
-- by corners and resolves them.
--
-- It tests what the blintz cannot. After the diagonal fold, two different
-- creases of the sheet lie on one line, one on each layer, so a corner fold's
-- line names a hinge of two edges, and the faces it holds still beside them
-- face opposite ways: one turn writes opposite angles on them. The run finds
-- both creases from the one line.
--
-- Both are built once, by 'runIO' at the top, as the recipe's own spec does.
module Senbazuru.Sequence.HelmetRunSpec (spec) where

import Control.Monad (forM_)
import Data.List (sort)
import Data.Map.Strict qualified as M
import HelmetGallery (helmetSvg)
import HelmetSequence (HelmetMove (..), buildHelmetSequence, helmetFile, helmetStates)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (Sample (..), surfaceFrame, surfaceSamples)
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Record
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import Test.Golden (goldenText)
import Test.Hspec
import Test.SequenceExamples (helmet)

spec :: Spec
spec = describe "the helmet base, run as a sequence" $ do
  file <- runIO (loadFoldFile "examples/helmet-base.fold" >>= right)
  recipe <- runIO (right (buildHelmetSequence (keyFrame file)))
  records <- runIO (right (runRecords <$> (checkSequence helmet >>= runSequence defaultRunSettings (M.singleton "examples/helmet-base.fold" file) . elaborate)))

  it "makes the recipe's three turns, one record each" $
    length records `shouldBe` length recipe

  it "ends every move with the recipe's crease angles, exactly" $
    map (snd . recordAngles) records `shouldBe` map (edgesFoldAngle . surfaceFrame . helmetEnd) recipe

  it "ends every move with the recipe's layer orders" $
    forM_ (zip records recipe) $ \(record, move') -> do
      let ours = faceOrders (surfaceFrame (recordAfter record))
          theirs = faceOrders (surfaceFrame (helmetEnd move'))
      length ours `shouldBe` length theirs
      ours `shouldMatchList` theirs

  it "keeps every point of paper where the recipe has it, within 1e-12" $
    forM_ (zip records recipe) $ \(record, move') -> do
      let ours = surfaceSamples (recordAfter record)
          theirs = surfaceSamples (helmetEnd move')
      map sampleMaterial ours `shouldBe` map sampleMaterial theirs
      maximum (0 : zipWith (\p q -> norm (position p ^-^ position q)) ours theirs) `shouldSatisfy` (<= 1e-12)

  -- Each corner fold's line, the line halfway between the corner and the
  -- tip, lies along two creases of the sheet, one on each layer: edges 10
  -- and 12 for the first, 11 and 13 for the second. On the sheet they are
  -- perpendicular, meeting at its centre, so each is a stretch of its own.
  -- Turns red if stretches were joined wherever two creases meet, which made
  -- one stretch along edge 10 claim edge 12 too.
  it "turns each corner about a hinge of two creases, one on each layer" $ do
    map (sort . concatMap snd . recordHinge) records `shouldBe` [[EdgeId 8, EdgeId 9], [EdgeId 10, EdgeId 12], [EdgeId 11, EdgeId 13]]
    let stretches record = [(sort [xy a, xy b], edges) | (MaterialSegment (MaterialPoint a) (MaterialPoint b), edges) <- recordHinge record]
    case drop 1 records of
      [first', second'] -> do
        stretches first' `shouldMatchList` [([(0.5, 0), (0.5, 0.5)], [EdgeId 10]), ([(0, 0.5), (0.5, 0.5)], [EdgeId 12])]
        stretches second' `shouldMatchList` [([(0.5, 0.5), (1, 0.5)], [EdgeId 13]), ([(0.5, 0.5), (0.5, 1)], [EdgeId 11])]
      other -> expectationFailure ("expected two corner folds, got " <> show (length other))

  -- The recipe's page, drawn through the recipe's own page function from the
  -- run's turns: the open square, then each turn's illustration pose and its
  -- end. Byte for byte the golden the recipe's spec keeps.
  it "draws the recipe's page, checked-helmet.svg, byte for byte" $ do
    turns <- mapM turnOf records
    states <- right (helmetStates [move' {helmetMotion = turn, helmetEnd = recordAfter record} | (move', record, turn) <- zip3 recipe records turns])
    svg <- right (helmetSvg (helmetFile states))
    goldenText "test/golden/checked-helmet.svg" svg
  where
    xy (V2 x y) = (x, y)
    turnOf record = case recordEvidence record of
      SweptHinge turn -> pure turn
      Presented -> fail "the helmet turns nothing over"
      NoMotion -> fail "the helmet names no anchor"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
