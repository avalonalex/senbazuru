-- | Endpoints for opening and reshaping flaps in the material study.
-- A rabbit-ear fold gathers a triangular region into a pointed flap; a petal
-- fold opens a flap and folds its sides inward. The fish base uses two rabbit
-- ears, and the bird base uses two petal folds on a square base.
--
-- These tests deliberately check endpoints, not a motion. Pairwise distances
-- between independently derived landmarks identify the intended shapes without
-- depending on which face the folding engine holds still. Shared vertices and
-- measured angles then distinguish a folded sheet from a plausible silhouette.
-- At 180 degrees the geometry alone cannot distinguish mountain from valley;
-- the flat stacking solver checks that missing information before its orders
-- are passed to the study's separate contact check. See
-- docs/notes/fish-and-bird-endpoints.md for the construction and its limits.
module FlapPatternSpec (spec) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (sort, tails)
import Data.Text qualified as T
import FoldMaterial
import PanelContact
import Senbazuru.Fold.Load (loadFile, loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types (Assignment (..), FaceId (..), FaceOrder (..), Frame (..), Stacking (..), VertexId (..), keyFrame)
import Senbazuru.Geometry.Rigid (applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.FlatFold
import Senbazuru.Origami.Folding
import Senbazuru.Origami.Stacking (defaultBudget, solveStacking, stackingSpace, stateCount)
import StudyCase
import Test.Hspec

spec :: Spec
spec = describe "flap-base endpoints" $ do
  forM_ [("fish", 8, [4, 4], fishLandmarks), ("bird", 16, [4, 4, 4, 4, 6], birdLandmarks)] $ \(name, faceCount, degrees, expected) -> describe name $ do
    source <- runIO $ loadSource name
    result <- runIO $ requireRight (foldFrameWith source)
    let sheet = foldedPattern result
        final = foldedFrame result
    it "has the intended interior crease vertices and consistent target angles" $ do
      report <- requireRight (checkFrame defaultTolerance source)
      reportViolations report `shouldBe` []
      sort (map checkDegree (reportChecked report)) `shouldBe` degrees
      edgesFoldAngle source `shouldBe` map closedAngle (edgesAssignment source)
    it "shares the same material vertex across every incident face" $ do
      original <- vertexMap sheet
      placed <- vertexMap final
      IM.size original `shouldBe` length expected
      IM.size placed `shouldBe` IM.size original
      length (facesVertices sheet) `shouldBe` faceCount
      forM_ (zip [0 ..] (facesVertices sheet)) $ \(i, vertices) -> do
        transform <- requireJust (IM.lookup i (foldedPlacements result))
        forM_ vertices $ \(VertexId v) -> do
          p <- requireJust (IM.lookup v original)
          q <- requireJust (IM.lookup v placed)
          norm (applyRigid transform p ^-^ q) `shouldSatisfy` (< 1e-12)
    it "preserves material lengths and area in a connected refined mesh" $
      forM_ [0, 1, 3] $ \level -> do
        pose <- requireRight (buildPose level source (PoseSpec "closed" (edgesFoldAngle source)))
        let mesh = poseMesh pose
        componentCount mesh `shouldBe` 1
        edgeStrains mesh `shouldSatisfy` all ((< 1e-12) . abs)
        abs (areaRatio mesh - 1) `shouldSatisfy` (< 1e-12)
        resolvedTriangles mesh `shouldSatisfy` all (\(a, b, c) -> norm (polygonNormal (map position [a, b, c])) > 1e-12)
    it "achieves every crease magnitude when measured from the folded panels" $ do
      faces <- requireRight (frameFaces final)
      forM_ (zip (edgesVertices sheet) (edgesFoldAngle sheet)) $ \((a, b), degrees') -> do
        let incident = [face | face <- faces, a `elem` faceVertexIds face, b `elem` faceVertexIds face]
        case incident of
          [_] -> pure () -- A boundary has no second panel and no fold angle.
          [left, right] -> do
            let normal face = let n = polygonNormal (faceCorners face) in (1 / norm n) *^ n
            abs (dot (normal left) (normal right) - cos (degrees' * pi / 180)) `shouldSatisfy` (< 1e-12)
          _ -> expectationFailure "edge must border one or two panels"
    it "matches the intended tips, shoulders and centre independently of camera or fixed face" $ do
      actual <- requireRight (frameVertices final)
      length actual `shouldBe` length expected
      forM_ [((p, p'), (q, q')) | (p, p') : rest <- tails (zip actual expected), (q, q') <- rest] $ \((p, p'), (q, q')) ->
        abs (norm (p ^-^ q) - norm (p' ^-^ q')) `shouldSatisfy` (< 1e-12)
    it "has one complete flat stacking and passes contact for every panel pair" $ do
      space <- requireRight (stackingSpace defaultBudget final)
      stateCount space `shouldBe` (1, False)
      orders <- requireRight (solveStacking final)
      faces <- requireRight (frameFaces final)
      ordered <- mapM (alongZ faces) orders
      let panels = [Panel (nameOf (faceId face)) (faceCorners face) | face <- faces]
      report <- requireRight (checkPanelContact (V3 0 0 1) ordered panels)
      report `shouldBe` ContactCheck (faceCount * (faceCount - 1) `div` 2) [] [] [] []
      -- Coincident zero-thickness faces must not pass just because they do not
      -- cross. Removing their orders must expose the missing information.
      unclassified <- requireRight (checkPanelContact (V3 0 0 1) [] panels)
      unorderedContacts unclassified `shouldSatisfy` (not . null)
    it "rejects independently changing a crease of the closed endpoint" $ do
      let active = [i | (i, assignment) <- zip [0 :: Int ..] (edgesAssignment source), assignment `elem` [Mountain, Valley]]
      active `shouldSatisfy` (not . null)
      forM_ (take 1 active) $ \changed ->
        foldFrame source {edgesFoldAngle = [if i == changed then angle / 2 else angle | (i, angle) <- zip [0 ..] (edgesFoldAngle source)]} `shouldSatisfy` isLeft
  it "adapts the attributed bird CP only at the two petal hinges and four flat guides" $ do
    reference <- keyFrame <$> (loadFile "examples/bird-base.cp" >>= requireRight)
    bird <- loadSource "bird"
    original <- requireRight (frameVertices reference)
    normalized <- requireRight (frameVertices bird)
    let toUnit (V3 x y z) = V3 ((x + 200) / 400) ((y + 200) / 400) (z / 400)
    mapping <- mapM (matchVertex normalized . toUnit) original
    sort mapping `shouldBe` [0 .. length normalized - 1]
    let indexed = IM.fromList (zip [0 ..] mapping)
        canonical a b assignment = (min a b, max a b, assignment)
    converted <-
      mapM
        ( \((VertexId a, VertexId b), assignment) -> do
            a' <- requireJust (IM.lookup a indexed)
            b' <- requireJust (IM.lookup b indexed)
            pure (canonical a' b' assignment)
        )
        (zip (edgesVertices reference) (edgesAssignment reference))
    let outerGuides = [(4, 9), (5, 10), (6, 11), (7, 12)]
        revised = [(a, b, if (a, b) `elem` outerGuides then Flat else assignment) | (a, b, assignment) <- converted]
        petalHinges = [(9, 10, Valley), (11, 12, Valley)]
    sort (revised ++ petalHinges) `shouldBe` sort [canonical a b assignment | ((VertexId a, VertexId b), assignment) <- zip (edgesVertices bird) (edgesAssignment bird)]

-- | In this reference plane the fish's long diagonal has length sqrt 2.
-- Both ear tips are one unit from SW along it. Its shoulders are r above
-- and below the midpoint. Bird's SW/NE corners meet at one tip and SE/NW
-- at the other, one unit apart. Its edge midpoints meet halfway between them,
-- and the original centre is 1/sqrt 2 from the SW/NE tip.
-- The two pairs of shoulders lie sqrt(2)/2 - 1/2 to either side.
fishLandmarks :: [V3]
fishLandmarks =
  let d = 1 / sqrt 2
      r = 1 - d
   in [V3 0 0 0, V3 1 0 0, V3 (sqrt 2) 0 0, V3 1 0 0, V3 d r 0, V3 d (-r) 0, V3 d 0 0, V3 d 0 0]

birdLandmarks :: [V3]
birdLandmarks =
  let d = 1 / sqrt 2
      s = d - 0.5
   in [V3 0 0 0, V3 1 0 0, V3 0 0 0, V3 1 0 0] ++ replicate 4 (V3 0.5 0 0) ++ [V3 d 0 0, V3 0.5 s 0, V3 0.5 (-s) 0, V3 0.5 (-s) 0, V3 0.5 s 0]

closedAngle :: Assignment -> Double
closedAngle Mountain = -180
closedAngle Valley = 180
closedAngle _ = 0

-- | FOLD's Above/Below is relative to the second face's normal, not +z.
-- Reverse a relation when that normal points down, or half the packet's
-- orders would silently change meaning on entering PanelContact.
alongZ :: [Face] -> FaceOrder -> IO (T.Text, T.Text)
alongZ faces (FaceOrder a b stacking) = do
  face <- requireJust (IM.lookup (unFaceId b) (IM.fromList [(unFaceId (faceId f), f) | f <- faces]))
  let V3 _ _ z = polygonNormal (faceCorners face)
  abs z `shouldSatisfy` (> 1e-12)
  stacking `shouldSatisfy` (/= Unordered)
  pure (if (stacking == Above) == (z > 0) then (nameOf b, nameOf a) else (nameOf a, nameOf b))

nameOf :: FaceId -> T.Text
nameOf = T.pack . show . unFaceId

loadSource :: String -> IO Frame
loadSource name = keyFrame <$> (loadFoldFile ("examples/" ++ name ++ "-base.fold") >>= requireRight)

vertexMap :: Frame -> IO (IM.IntMap V3)
vertexMap frame = IM.fromList . zip [0 ..] <$> requireRight (frameVertices frame)

matchVertex :: [V3] -> V3 -> IO Int
matchVertex points p = case [i | (i, q) <- zip [0 ..] points, norm (p ^-^ q) < 1e-12] of
  [i] -> pure i
  _ -> expectationFailure "reference vertex needs exactly one normalized counterpart" >> fail "bad normalization"

requireRight :: (Show e) => Either e a -> IO a
requireRight (Left err) = expectationFailure (show err) >> fail "flap endpoint failed"
requireRight (Right value) = pure value

requireJust :: Maybe a -> IO a
requireJust Nothing = expectationFailure "missing vertex or face" >> fail "flap endpoint failed"
requireJust (Just value) = pure value
