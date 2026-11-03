-- | The fan-faults study's measures (S9 of #637), on frames small enough to
-- work by hand and on the fixtures whose numbers 06 Risks quoted from the
-- prototype that first measured them, before S9 replaced them with its own.
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
import Senbazuru.Render.Camera (bottomUp, topDown, turnedBy)
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
    -- Drawn at 100 page units per model unit, the bottom end moves left and
    -- down by c = 0.75 / √2 each way while face 1 stays put. The edge from it
    -- to the fanned corner (1, 0) runs 50 − c across and c down, and reaches
    -- face 1's left side after c across, so the line stops c √(1 + (c / (50 −
    -- c))²) short, about 3 × 10⁻⁵ more than c. The right end moves into face 1, which
    -- paints over it. Red if the gap were taken from the true end, which
    -- gives 0 for both, or if only faces painted earlier counted as covering,
    -- which finds no end at all.
    it "finds where a line stops short of the paper it met" $ do
      fig <- either (fail . show) pure (figureOf topDown cornerCovered)
      let ends = metEnds fig
          c = 0.75 / sqrt 2
      map metCovers ends `shouldBe` [[FaceId 1], [FaceId 1]]
      map metSheet ends `shouldBe` [FaceId 0, FaceId 0]
      sort (map (gapAt fig 100) ends) `shouldSatisfy` \case
        [covered, gap] -> covered == 0 && abs (gap - c * sqrt (1 + (c / (50 - c)) ^ (2 :: Int))) < 1e-9
        _ -> False

    -- A third face, below the square and sharing its bottom edge, with a
    -- fourth small face under the square so that the square is painted in a
    -- later layer than it. The third face's stretch along that edge ends under
    -- face 1, and its line runs on along the square's side, which only
    -- borders it. Red if a face on the edge's other side counted as covering
    -- it: with no clearance, rounding then decides which side of that edge
    -- the line falls on, and the gap comes out 0 for some placements of the
    -- same frame and 0.53 for others.
    it "measures a line stopping short the same wherever the paper lies" $ do
      let gapsAt (dx, dy) = do
            fig <- either (fail . show) pure (figureOf topDown (bordered dx dy))
            pure (sort (map (gapAt fig 100) (metEnds fig)))
      here <- gapsAt (0, 0)
      here `shouldSatisfy` any (> 0.5)
      forM_ [(dx, dy) | dx <- [0, 0.1 .. 0.7], dy <- [0, 1.1 .. 5.5]] $ \shift -> do
        there <- gapsAt shift
        (shift, and (zipWith (\a b -> abs (a - b) < 1e-9) here there) && length here == length there) `shouldBe` (shift, True)

    -- The square's visible boundary runs from (0, 0), which does not move,
    -- through (1/2, 0) and (1, 1/2), which move 0.75, to (1, 1) and (0, 1),
    -- which do not. Face 1 is on top and does not move at all. Red if a
    -- corner were measured along a side it does not lie on, which moves (0, 0)
    -- by corner (1, 0)'s 1.5, or if a face whose paper does not move were
    -- reported.
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
      -- 06 Risks quoted the prototype before S9: on the crane drawn 56.6 page
      -- units per sheet length, face 61 turns inside out; at 33.8, three faces
      -- do and one crosses itself, here faces 24, 56 and 61, and 27. These
      -- are the scales `render --steps` draws six and ten rows of three
      -- figures at. Red if the move were not capped at 6 sheets, which gives
      -- six faces at 56.6, or ran the other way, which gives nine.
      it "turns the faces inside out that the prototype found" $ \crane -> do
        fig <- either (fail . show) pure (figureOf topDown crane)
        let shapesAt s = [(unFaceId (faceId face), shape) | face <- figureFaces fig, let shape = faceShapeAt fig s face, shape /= Kept]
        shapesAt 56.62 `shouldBe` [(61, InsideOut)]
        sort (shapesAt 33.76) `shouldBe` [(24, InsideOut), (27, CrossesItself), (56, InsideOut), (61, InsideOut)]

      -- The closed form against the shape itself: 0.1% below the scale
      -- 'insideOutBelow' gives, the face is inside out or crossed; 0.1%
      -- above, it is not inside out. Red if the threshold's sign, A₀ or B
      -- were taken the wrong way.
      it "gives the scale below which each face's outline winds the other way" $ \crane -> do
        fig <- either (fail . show) pure (figureOf topDown crane)
        let thresholds = [(face, s) | face <- figureFaces fig, Just s <- [insideOutBelow fig face]]
        length thresholds `shouldSatisfy` (> 10)
        forM_ thresholds $ \(face, s) -> do
          (faceId face, faceShapeAt fig (s * 0.999) face `elem` [InsideOut, CrossesItself, Collapsed]) `shouldBe` (faceId face, True)
          (faceId face, faceShapeAt fig (s * 1.001) face /= InsideOut) `shouldBe` (faceId face, True)

      -- 06 Risks quoted the prototype: 7 faces have visible paper that moves,
      -- one by 2.9 page units. Here that is face 10's, the point 0.6488 of the
      -- way along edge 0–13, whose ends count 0 and 3 sheets. Red if a corner were measured along a side of
      -- its face it does not lie on, which gives 4.16, face 10's vertex 15
      -- along its side 13–0.
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

      -- From above, two lines stop short of the paper they met; turned 180°,
      -- the fan runs the other way across the model, and face 10's mountain
      -- edge, which from above runs on under face 1, stops 3.67 page units
      -- short of it. Red if the turn were ignored, or if the gap were the end's
      -- distance from that paper rather than the length along the edge, which
      -- gives 1.98 where the edge meets face 1's side at a slant.
      it "finds the lines that stop short, from above and turned round" $ \crane -> do
        above <- either (fail . show) pure (figureOf topDown crane)
        turned <- either (fail . show) pure (figureOf (turnedBy pi topDown) crane)
        let gaps fig = [(unFaceId (metSheet e), g) | e <- metEnds fig, let g = gapAt fig 115 e, g > noticeable]
        map fst (gaps above) `shouldBe` [61, 20]
        case gaps turned of
          [(10, g)] -> g `shouldSatisfy` (\x -> abs (x - 3.67) < 0.005)
          other -> expectationFailure ("expected face 10's end alone, got " <> show other)

      -- Seen from below, the counts and the visible paper are the other
      -- side's: face 20 crosses itself at 115, and 8 faces' visible paper
      -- moves, by up to 2.75. Sheet 11's fold on edge 0–19 is drawn as the
      -- borders 0–1 and 0–20 lying along it, which move 3 page units more; of
      -- the six borders that only end there, at an angle, the two meeting at
      -- vertex 55 move 9. And no face gets a scale from rounding: the moves
      -- add no area to a face that only slides, or whose one moving corner
      -- travels along the line through its neighbours. Red if the counts or
      -- the visible paper were read from above whatever the camera, if every
      -- border meeting a stretch's end counted, or if a rounding B gave a face
      -- a scale, which gives six faces scales from 1e-14 to 1.3e-11.
      it "reads the side the camera sees, the border the fold lies on, and no rounding" $ \crane -> do
        below <- either (fail . show) pure (figureOf bottomUp crane)
        [(unFaceId (faceId face), shape) | face <- figureFaces below, let { shape = faceShapeAt below 115 face }, shape /= Kept] `shouldBe` [(20, CrossesItself)]
        length (movedPaper below) `shouldBe` 8
        maximum (map movedMost (movedPaper below)) `shouldSatisfy` (\m -> abs (m - 2.75) < 0.005)
        [borderFoldMismatch b | b <- borderDrawnFolds below, borderFoldSheet b == Just (FaceId 11)] `shouldSatisfy` \case
          [m] -> abs (m - 3) < 1e-9
          _ -> False
        [s | face <- figureFaces below, Just s <- [insideOutBelow below face]] `shouldSatisfy` all (> 1)

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

-- | 'cornerCovered' with a third face, the square [0, 1] × [−1, 0], sharing
-- the unit square's bottom edge, and a fourth, small, under the unit square,
-- the whole moved by (dx, dy).
bordered :: Double -> Double -> Frame
bordered dx dy =
  emptyFrame
    { verticesCoords = [[x + dx, y + dy] | (x, y) <- [(0, 0), (1, 0), (1, 1), (0, 1), (0.5, -0.5), (1.5, -0.5), (1.5, 0.5), (0.5, 0.5), (1, -1), (0, -1), (0.1, 0.6), (0.2, 0.6), (0.2, 0.7), (0.1, 0.7)]],
      facesVertices = [map VertexId [0, 1, 2, 3], map VertexId [4, 5, 6, 7], map VertexId [9, 8, 1, 0], map VertexId [10, 11, 12, 13]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (9, 8), (8, 1), (0, 9), (10, 11), (11, 12), (12, 13), (13, 10)]],
      edgesAssignment = replicate 15 Border,
      faceOrders = [FaceOrder (FaceId 1) (FaceId 0) Above, FaceOrder (FaceId 1) (FaceId 2) Above, FaceOrder (FaceId 0) (FaceId 3) Above]
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
