-- | Closed endpoints for the six remaining traditional bases. The expected
-- landmarks below are material points paired with their positions in a
-- convenient reference plane. Comparing all their distances recognises a
-- base regardless of which face the folding engine holds still. It catches
-- a wrong flap arrangement even when lengths and loop closure both pass.
module BasicBaseSpec (spec) where

import BasicBases
import Control.Monad (forM_)
import Data.IntMap.Strict qualified as IM
import Data.List (sort, tails)
import Data.Text qualified as T
import FoldMaterial
import PanelContact
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, signedArea)
import Senbazuru.Geometry.Rigid (applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.FlatFold
import Senbazuru.Origami.Folding
import Senbazuru.Origami.Stacking (defaultBudget, solveStacking, stackingSpace, stateCount)
import Senbazuru.Origami.Visible (Region (..), VisibleForm (..))
import Senbazuru.Render.Camera
import Senbazuru.Render.Projected (projectedForm)
import StudyCase
import Test.Hspec

spec :: Spec
spec = describe "six basic-base endpoints" $
  forM_ basicBases $ \base -> describe (baseId base) $ do
    source <- runIO $ keyFrame <$> (loadFoldFile ("examples/" ++ baseId base ++ "-base.fold") >>= right)
    result <- runIO $ right (foldFrameWith source)
    let sheet = foldedPattern result
        final = foldedFrame result
        (count, degrees, silhouette, landmarks) = expected (baseId base)
    it "reproduces its fixture from the documented construction" $ do
      constructed <- right (baseFrame base)
      constructed {verticesCoords = []} `shouldBe` source {verticesCoords = []}
      -- Irrational intersections can differ in their last bit across CPUs.
      rebuilt <- right (frameVertices constructed)
      recorded <- right (frameVertices source)
      length rebuilt `shouldBe` length recorded
      zipWith (\p q -> norm (p ^-^ q)) rebuilt recorded `shouldSatisfy` all (< 1e-12)
    it "has consistent target assignments and locally valid crease vertices" $ do
      report <- right (checkFrame defaultTolerance source)
      reportViolations report `shouldBe` []
      sort (map checkDegree (reportChecked report)) `shouldBe` degrees
      edgesFoldAngle source `shouldBe` map closedAngle (edgesAssignment source)
    it "keeps shared material vertices together and recognises every landmark" $ do
      original <- right (frameVertices sheet)
      actual <- right (frameVertices final)
      length original `shouldBe` length landmarks
      length actual `shouldBe` length original
      length (facesVertices sheet) `shouldBe` count
      let originals = IM.fromList (zip [0 ..] original)
          placed = IM.fromList (zip [0 ..] actual)
      forM_ (zip [0 ..] (facesVertices sheet)) $ \(i, vertices) -> do
        transform <- just (IM.lookup i (foldedPlacements result))
        forM_ vertices $ \(VertexId v) -> do
          p <- just (IM.lookup v originals)
          q <- just (IM.lookup v placed)
          norm (applyRigid transform p ^-^ q) `shouldSatisfy` (< 1e-12)
      matched <- mapM (match original actual) landmarks
      forM_ [(a, b) | a : rest <- tails matched, b <- rest] $ \((p, p'), (q, q')) ->
        abs (norm (p ^-^ q) - norm (p' ^-^ q')) `shouldSatisfy` (< 1e-12)
    it "preserves lengths and area through mesh refinement" $
      forM_ [0, 1, 3] $ \level -> do
        pose <- right (buildPose level source (PoseSpec "closed" (edgesFoldAngle source)))
        let mesh = poseMesh pose
        componentCount mesh `shouldBe` 1
        edgeStrains mesh `shouldSatisfy` all ((< 1e-12) . abs)
        abs (areaRatio mesh - 1) `shouldSatisfy` (< 1e-12)
        resolvedTriangles mesh `shouldSatisfy` all (\(a, b, c) -> norm (polygonNormal (map position [a, b, c])) > 1e-12)
    it "achieves every crease magnitude independently of shared-vertex closure" $ do
      faces <- right (frameFaces final)
      forM_ (zip (edgesVertices sheet) (edgesFoldAngle sheet)) $ \((a, b), angle) ->
        case [f | f <- faces, a `elem` faceVertexIds f, b `elem` faceVertexIds f] of
          [_] -> pure ()
          [left, other] -> do
            let normal f = let n = polygonNormal (faceCorners f) in (1 / norm n) *^ n
            abs (dot (normal left) (normal other) - cos (angle * pi / 180)) `shouldSatisfy` (< 1e-12)
          _ -> expectationFailure "each edge must border one or two panels"
    it "has one complete stacking and classifies contact for every panel pair" $ do
      space <- right (stackingSpace defaultBudget final)
      stateCount space `shouldBe` (1, False)
      orders <- right (solveStacking final)
      faces <- right (frameFaces final)
      alongZ <- mapM (orderAlongZ faces) orders
      let panels = [Panel (nameOf (faceId f)) (faceCorners f) | f <- faces]
      report <- right (checkPanelContact (V3 0 0 1) alongZ panels)
      report `shouldBe` ContactCheck (count * (count - 1) `div` 2) [] [] [] []
      unknown <- right (checkPanelContact (V3 0 0 1) [] panels)
      unorderedContacts unknown `shouldSatisfy` (not . null)
    it "covers the expected silhouette once, from above, below and obliquely" $ do
      orders <- right (solveStacking final)
      forM_ [topDown, bottomUp, isometric] $ \basis -> do
        seen <- right (projectedForm basis final orders) >>= just
        let pieces = [map (project basis) ring | region <- formRegions seen, ring <- regionPieces region]
            area = sum (map (abs . signedArea) pieces)
            factor = abs (dot (basisForward basis) (V3 0 0 1))
        abs (area - silhouette * factor) `shouldSatisfy` (< 1e-9)
        forM_ [(a, b) | a : rest <- tails pieces, b <- rest] $ \(a, b) ->
          abs (signedArea (clipConvex a b)) `shouldSatisfy` (< 1e-9)

-- The coordinates use exact constructions, not captured folding output.
-- Organ has two right triangles with legs 1/4 cut from a 1 by 1/2 rectangle;
-- boat and pig have four. Diamond and frog have perpendicular diagonals.
-- See docs/notes/six-more-base-endpoints.md for the flap constructions.
expected :: String -> (Int, [Int], Double, [(V2, V3)])
expected name =
  let d = 1 / sqrt 2
      r = (1 - d) / 2
      h = sqrt 2 - 1
      point (x, y) (u, v) = (V2 x y, V3 u v 0)
      corners = zipWith point [(0, 0), (1, 0), (1, 1), (0, 1)]
   in case name of
        "helmet" -> (6, [6], 0.25, corners (replicate 4 (0, 0)) ++ zipWith point [(0.5, 0), (0.5, 0.5), (0.5, 1), (0, 0.5), (1, 0.5)] [(0.5, 0), (0.5, 0.5), (0, 0.5), (0.5, 0), (0, 0.5)])
        "organ" -> (6, [4, 4], 7 / 16, corners [(0, 0), (1, 0), (0.5, 0), (0.5, 0)] ++ zipWith point [(0.25, 0.5), (0.75, 0.5), (0.25, 1), (0, 0.25), (0, 0.75), (0.75, 1), (1, 0.25), (1, 0.75)] [(0.25, 0.5), (0.75, 0.5), (0.25, 0), (0, 0.25), (0.5, 0.25), (0.75, 0), (1, 0.25), (0.5, 0.25)])
        "boat" -> (9, replicate 4 4, 3 / 8, corners [(0, 0), (0, 0), (1, 0), (1, 0)] ++ zipWith point [(0.25, 0.25), (0.25, 0.75), (0.75, 0.25), (0.75, 0.75), (0.5, 0), (0.5, 1)] [(0.25, 0.25), (0.75, 0.25), (0.25, -0.25), (0.75, -0.25), (0.5, 0), (0.5, 0)])
        "pig" -> (11, replicate 4 4, 3 / 8, corners (replicate 4 (0, 0)) ++ zipWith point [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75), (0, 0.5), (0.25, 0), (0.25, 1), (1, 0.5), (0.75, 0), (0.75, 1)] [(0.25, 0.25), (-0.25, 0.25), (0.25, -0.25), (-0.25, -0.25), (0.5, 0), (0.25, 0), (0.25, 0), (-0.5, 0), (-0.25, 0), (-0.25, 0)])
        "diamond" -> (7, [4, 4], h, corners [(0, 0), (1, 0), (sqrt 2, 0), (1, 0)] ++ zipWith point [(1, h), (h, 1), (1, h * h), (d, 1 - d), (1 - d, d), (h * h, 1)] [(2 * h, 0), (2 * h, 0), (1, h * h), (d, 1 - d), (d, d - 1), (1, -(h * h))])
        "frog" ->
          ( 32,
            replicate 12 4 ++ [14],
            d * r,
            corners (replicate 4 (0, 0))
              ++ [point (0.5, 0.5) (d, 0)]
              ++ [ point (rotate n material) folded
                   | n <- [0 .. 3],
                     let side = if n == 0 || n == 3 then r else -r,
                     (material, folded) <- [((0.5, r), (d / 2, 0)), ((0.5, 0), (0.5, 0)), ((0.5 - r, r), (d / 2, side)), ((0.5 + r, r), (d / 2, side))]
                 ]
          )
        _ -> (0, [], 0, []) -- A new catalog entry must supply expectations.
  where
    rotate :: Int -> (Double, Double) -> (Double, Double)
    rotate 0 p = p
    rotate n (x, y) = rotate (n - 1) (1 - y, x)

match :: [V3] -> [V3] -> (V2, V3) -> IO (V3, V3)
match original actual (V2 x y, expectedPoint) =
  case [q | (p, q) <- zip original actual, norm (p ^-^ V3 x y 0) < 1e-12] of
    [q] -> pure (q, expectedPoint)
    _ -> expectationFailure "landmark must match exactly one material vertex" >> fail "bad landmark"

closedAngle :: Assignment -> Double
closedAngle Mountain = -180
closedAngle Valley = 180
closedAngle _ = 0

-- FOLD signs refer to the second face's normal, which may point down.
orderAlongZ :: [Face] -> FaceOrder -> IO (T.Text, T.Text)
orderAlongZ faces (FaceOrder a b stacking) = do
  face <- just (lookup b [(faceId f, f) | f <- faces])
  let V3 _ _ z = polygonNormal (faceCorners face)
  abs z `shouldSatisfy` (> 1e-12)
  stacking `shouldSatisfy` (/= Unordered)
  pure (if (stacking == Above) == (z > 0) then (nameOf b, nameOf a) else (nameOf a, nameOf b))

nameOf :: FaceId -> T.Text
nameOf = T.pack . show . unFaceId

right :: (Show e) => Either e a -> IO a
right = either (\err -> expectationFailure (show err) >> fail "base check failed") pure

just :: Maybe a -> IO a
just = maybe (expectationFailure "missing geometry or visibility" >> fail "base check failed") pure
