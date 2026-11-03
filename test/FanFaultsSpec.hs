-- | The fan-faults study's measures (S9 of #637), on a frame small enough to
-- work by hand and on the fixtures whose numbers 06 Risks already quotes from
-- the prototype that first measured them.
module FanFaultsSpec (spec) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Map.Strict qualified as M
import FanFaults
import Senbazuru.Fold.Load (decodeFoldFile, loadFoldFile, readSequenceText)
import Senbazuru.Fold.Query (Face (..))
import Senbazuru.Fold.Types
import Senbazuru.Origami.Folding (foldFrame)
import Senbazuru.Origami.Stacking (solveStacking)
import Senbazuru.Render.Camera (topDown, turnedBy)
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Record
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import Test.Hspec

spec :: Spec
spec = do
  describe "a square with a nearer square over one corner" $ do
    -- Face 0 is the unit square; face 1, the square [1/2, 3/2] × [−1/2, 1/2],
    -- lies over its corner (1, 0), so that corner alone counts 1 sheet and
    -- moves 1.5 page units. The square's bottom edge is visible from (0, 0)
    -- to (1/2, 0) and its right edge from (1, 1/2) to (1, 1); both stretches
    -- end at face 1's edge, halfway along, where they move 0.75.
    --
    -- Fanned, the bottom end moves left and down by 0.75 / √2 each way while
    -- face 1 stays put, so it leaves face 1's left edge by 0.75 / √2 and the
    -- edge's faint continuation shows. The right end moves into face 1, which
    -- paints over it. Red if the gap were taken from the true end, which
    -- gives 0 for both, or if the faces painted earlier counted as covering.
    it "finds where a stretch end comes apart from the paper it met" $ do
      fig <- either (fail . show) pure (figureOf topDown cornerCovered)
      let ends = metEnds fig
      map metCovers ends `shouldBe` [[FaceId 1], [FaceId 1]]
      map metSheet ends `shouldBe` [FaceId 0, FaceId 0]
      sort (map (gapAt fig 100) ends) `shouldSatisfy` \case
        [covered, gap] -> covered == 0 && abs (gap - 0.75 / sqrt 2) < 1e-9
        _ -> False

    -- The square's visible boundary runs from (0, 0), which does not move,
    -- through (1/2, 0) and (1, 1/2), which move 0.75, to (1, 1) and (0, 1),
    -- which do not. Face 1 is on top and does not move at all. Red if a
    -- corner of the visible paper inside the face, (1/2, 1/2), were moved,
    -- or if a face whose paper does not move were reported.
    it "measures how far the visible paper moves" $ do
      fig <- either (fail . show) pure (figureOf topDown cornerCovered)
      case movedPaper fig of
        [MovedPaper face most least] -> do
          face `shouldBe` FaceId 0
          most `shouldSatisfy` (\m -> abs (m - 0.75) < 1e-9)
          least `shouldBe` 0
        other -> expectationFailure ("expected one face, got " <> show other)

  beforeAll loadCrane $ do
    describe "the folded crane" $ do
      -- 06 Risks quotes the prototype: on the crane drawn 56.6 page units
      -- per sheet length, face 61 turns inside out; at 33.8, faces 24, 56 and
      -- 61 do and face 27 crosses itself. These are the scales `render
      -- --steps` draws six and ten rows of three figures at. Red if the move
      -- were not capped at 6 sheets, which gives six faces at 56.6, or ran the
      -- other way, which gives nine.
      it "turns the faces inside out that the prototype found" $ \crane -> do
        fig <- either (fail . show) pure (figureOf topDown crane)
        let shapesAt s = [(unFaceId (faceId face), shape) | face <- figureFaces fig, let shape = faceShapeAt fig s face, shape /= Kept]
        shapesAt 56.62 `shouldBe` [(61, InsideOut)]
        sort (shapesAt 33.76) `shouldBe` [(24, InsideOut), (27, CrossesItself), (56, InsideOut), (61, InsideOut)]

      -- The closed form against the shape itself: a hair below the scale
      -- 'insideOutBelow' gives, the face is inside out or crossed; a hair
      -- above, it is not inside out. Red if the threshold's sign or either
      -- area were taken the wrong way.
      it "gives the scale below which each face turns inside out" $ \crane -> do
        fig <- either (fail . show) pure (figureOf topDown crane)
        let thresholds = [(face, s) | face <- figureFaces fig, Just s <- [insideOutBelow fig face]]
        length thresholds `shouldSatisfy` (> 10)
        forM_ thresholds $ \(face, s) -> do
          (faceId face, faceShapeAt fig (s * 0.999) face `elem` [InsideOut, CrossesItself, Collapsed]) `shouldBe` (faceId face, True)
          (faceId face, faceShapeAt fig (s * 1.001) face /= InsideOut) `shouldBe` (faceId face, True)

      -- 06 Risks: 7 faces have visible paper that moves, face 10's by 2.9
      -- page units, the point 0.6488 of the way along edge 0–13, whose ends
      -- count 0 and 3 sheets. Red if the corners of visible paper inside a
      -- face were moved as well, which gives 4.16.
      it "moves the visible paper of seven faces, at most 2.92 page units" $ \crane -> do
        fig <- either (fail . show) pure (figureOf topDown crane)
        let moved = movedPaper fig
        length moved `shouldBe` 7
        maximum (map movedMost moved) `shouldSatisfy` (\m -> abs (m - 2.92) < 0.005)

      -- Of the crane's 99 folds, 15 lie along a border edge, and from above
      -- 4 stretches are drawn at border weight though their named edge is a
      -- fold. The border under one of them moves 9 page units, the fan's
      -- largest move, while the fold above it stays. Red if a stretch's own
      -- assignment were read rather than its named edge's.
      it "finds the folds drawn as a border, and how far apart they move" $ \crane -> do
        fig <- either (fail . show) pure (figureOf topDown crane)
        let folds = borderDrawnFolds fig
            (along, total) = foldsAlongBorder fig
        length folds `shouldBe` 4
        maximum (map borderFoldMismatch folds) `shouldSatisfy` (\m -> abs (m - 9) < 1e-9)
        (length along, total) `shouldBe` (15, 99)

      -- From above, two stretch ends come apart from the paper they met;
      -- turned 180°, the fan runs the other way across the model, and face
      -- 10's mountain edge, which from above runs on under face 1, leaves it
      -- by about 2 page units. Red if the turn were ignored.
      it "finds the ends that come apart, from above and turned round" $ \crane -> do
        above <- either (fail . show) pure (figureOf topDown crane)
        turned <- either (fail . show) pure (figureOf (turnedBy pi topDown) crane)
        let gaps fig = [(unFaceId (metSheet e), g) | e <- metEnds fig, let g = gapAt fig 115 e, g > noticeable]
        map fst (gaps above) `shouldBe` [61, 20]
        case gaps turned of
          [(10, g)] -> g `shouldSatisfy` (\x -> abs (x - 1.98) < 0.005)
          other -> expectationFailure ("expected face 10's end alone, got " <> show other)

  describe "the helmet base's folds" $ do
    -- Step 2 folds about edges 10 and 12 of the state before it. Edge 12 is
    -- drawn and its ends count no sheets; edge 10 is buried and its end at
    -- vertex 4 counts 1, so the paper under it moves 1.5 page units, 1.06 of
    -- them square to the hinge. Red if a drawn edge were taken for buried.
    it "moves only the buried hinge edges, by one sheet's step" $ do
      (run, states) <- helmetRun
      case [r | r <- runRecords run, recordStep r == 2] of
        [r] -> do
          fig <- either (fail . show) pure (figureOf topDown (displayedFrame (recordBefore r) (displayBefore r)))
          length states `shouldBe` 4
          let moves = hingeMoves fig (concatMap snd (recordHinge r))
          [(unEdgeId (hingeEdge m), hingeVisible m) | m <- moves] `shouldBe` [(10, False), (12, True)]
          [hingeMost m | m <- moves] `shouldBe` [1.5, 0]
          [hingeSquare m | m <- moves] `shouldSatisfy` \case
            [square, 0] -> abs (square - 1.5 / sqrt 2) < 1e-9
            _ -> False
        other -> expectationFailure ("expected one record at step 2, got " <> show (length other))

-- | Face 0, the unit square, and face 1, the square [1/2, 3/2] × [−1/2, 1/2],
-- lying over its corner (1, 0).
cornerCovered :: Frame
cornerCovered =
  emptyFrame
    { verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1], [0.5, -0.5], [1.5, -0.5], [1.5, 0.5], [0.5, 0.5]],
      facesVertices = [map VertexId [0, 1, 2, 3], map VertexId [4, 5, 6, 7]],
      edgesVertices = [(VertexId (4 * k + a), VertexId (4 * k + b)) | k <- [0, 1], (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 0)]],
      edgesAssignment = replicate 8 Border,
      faceOrders = [FaceOrder (FaceId 1) (FaceId 0) Above]
    }

-- | The crane folded along its own angles, with the first stacking the solver
-- finds, as the study measures it.
loadCrane :: IO Frame
loadCrane = do
  bytes <- BS.readFile "test/fixtures/crane.fold"
  file <- either fail pure (decodeFoldFile bytes)
  folded <- either (fail . show) pure (foldFrame (keyFrame file))
  orders <- either (fail . show) pure (solveStacking folded)
  pure folded {faceOrders = orders}

-- | The run of @helmet.foldseq@ and the states it writes.
helmetRun :: IO (Run, [WrittenState])
helmetRun = do
  sheet <- loadFoldFile "examples/helmet-base.fold" >>= either (fail . show) pure
  source <- readSequenceText "helmet.foldseq" >>= either (fail . show) pure
  run <- either (fail . show) pure (parseSequence "helmet.foldseq" source >>= checkSequence >>= runSequence defaultRunSettings (M.singleton "examples/helmet-base.fold" sheet) . elaborate)
  states <- either (fail . show) pure (writtenStates run)
  pure (run, states)
