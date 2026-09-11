-- | One rabbit ear gathers a triangular half-sheet into a pointed flap.
-- Four creases meet at its interior vertex, so choosing their angles
-- independently would tear the sheet. These tests exercise a compatible
-- family, with the opposite half of the fish base held flat. See
-- docs/notes/rabbit-ear-motion.md for the coordinates and angle derivation.
--
-- Landmark positions come from rotating around two fixed crease axes;
-- they independently check which way the flap rises and turns. Contact is
-- checked along sampled states, not certified continuously. The moving panels
-- exchange vertical order during the turn, so only their order above the
-- stationary paper is required throughout. The complete closed stacking is
-- checked separately against the production flat-stacking solver.
module RabbitEarSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (eitherDecode)
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (find)
import FoldMaterial
import PanelContact
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Frame (..), Stacking (..), VertexId (..), keyFrame)
import Senbazuru.Geometry.Rigid (applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding
import Senbazuru.Origami.Stacking (defaultBudget, solveStacking, stackingSpace, stateCount)
import StudyCase
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "rabbit-ear motion" $ do
  cases <- runIO $ BL.readFile "study/fold-material/cases.json" >>= requireRight . eitherDecode
  entry <- runIO $ requireJust (find ((== "rabbit-ear") . caseId) (cases :: [CaseSpec]))
  source <- runIO $ keyFrame <$> (loadFoldFile (caseSource entry) >>= requireRight)
  it "records eight linked states with the opposite ear left flat" $ do
    let magnitudes = [0, 15, 30, 60, 90, 120, 150, 175]
    caseSource entry `shouldBe` "examples/fish-base.fold"
    length (caseSteps entry) `shouldBe` length magnitudes
    forM_ (zip (caseSteps entry) magnitudes) $ \(step, magnitude) -> do
      length (poseAngles step) `shouldBe` 15
      zipWith (-) (poseAngles step) (rabbitAngles magnitude) `shouldSatisfy` all ((< 1e-12) . abs)
  it "preserves connected material and contact at random compatible angles and refinements" $
    forAll (choose (0.1, 179.9)) $ \magnitude ->
      forAll (chooseInt (0, 2)) $ \level ->
        case buildCasePose level entry source (PoseSpec "sample" (rabbitAngles magnitude)) of
          Left err -> counterexample (show err) False
          Right pose ->
            let mesh = poseMesh pose
             in counterexample (show (poseContact pose)) $
                  componentCount mesh == 1
                    && all ((< 1e-12) . abs) (edgeStrains mesh)
                    && abs (areaRatio mesh - 1) < 1e-12
                    && poseContact pose == Just (ContactCheck 28 [] [] [] [])
  it "checks all 28 panel pairs in a half-degree sweep and at both upright configurations" $
    forM_ (uprightMountain : [0, 0.5 .. 179.5]) $ \magnitude -> do
      pose <- requireRight (buildCasePose 0 entry source (PoseSpec "sweep" (rabbitAngles magnitude)))
      poseContact pose `shouldBe` Just (ContactCheck 28 [] [] [] [])
  it "agrees at shared vertices and achieves crease magnitudes measured from panel normals" $
    forM_ [0, 15, uprightMountain, 60, 90, 150, 175, 180] $ \magnitude -> do
      result <- requireRight (foldFrameWith source {edgesFoldAngle = rabbitAngles magnitude})
      let sheet = foldedPattern result
          final = foldedFrame result
      original <- IM.fromList . zip [0 ..] <$> requireRight (frameVertices sheet)
      placed <- IM.fromList . zip [0 ..] <$> requireRight (frameVertices final)
      forM_ (zip [0 ..] (facesVertices sheet)) $ \(i, vertices) -> do
        transform <- requireJust (IM.lookup i (foldedPlacements result))
        forM_ vertices $ \(VertexId v) -> do
          p <- requireJust (IM.lookup v original)
          q <- requireJust (IM.lookup v placed)
          norm (applyRigid transform p ^-^ q) `shouldSatisfy` (< 1e-12)
      faces <- requireRight (frameFaces final)
      forM_ (zip (edgesVertices sheet) (edgesFoldAngle sheet)) $ \((a, b), degrees) ->
        case [face | face <- faces, a `elem` faceVertexIds face, b `elem` faceVertexIds face] of
          [_] -> pure () -- A boundary has no second panel to measure against.
          [left, right] -> do
            let normal face = let n = polygonNormal (faceCorners face) in (1 / norm n) *^ n
            abs (dot (normal left) (normal right) - cos (degrees * pi / 180)) `shouldSatisfy` (< 1e-12)
          _ -> expectationFailure "edge must border one or two panels"
  it "matches independent tip and shoulder positions and leaves the other half still" $
    forM_ [0, 15, uprightMountain, 60, 90, 150, 175, 180] $ \magnitude -> do
      pose <- requireRight (buildPose 2 source (PoseSpec "landmarks" (rabbitAngles magnitude)))
      let mesh = poseMesh pose
          m = magnitude * pi / 180
          v = valleyAngle magnitude * pi / 180
          c = cos (pi / 8)
          s = sin (pi / 8)
          d = 1 / sqrt 2
          r = 1 - d
          expectedTip = V3 (c * c + s * s * cos v) (c * s * (1 - cos v)) (s * sin v)
          expectedShoulder = V3 (0.75 + 0.25 * cos m) (r + (sqrt 2 - 1) / 4 * (1 - cos m)) (r * c * sin m)
      tip <- pointAt (1, 0) mesh
      shoulder <- pointAt (1, r) mesh
      norm (tip ^-^ expectedTip) `shouldSatisfy` (< 1e-12)
      norm (shoulder ^-^ expectedShoulder) `shouldSatisfy` (< 1e-12)
      -- Refinement vertices test whole stationary panels, not only their tips.
      forM_ [p | p <- samples mesh, materialV p >= materialU p] $ \p ->
        norm (position p ^-^ V3 (materialU p) (materialV p) 0) `shouldSatisfy` (< 1e-12)
      fixedCentre <- pointAt (d, r) mesh
      norm (fixedCentre ^-^ V3 d r 0) `shouldSatisfy` (< 1e-12)
  it "requires the remaining three moving-panel orders at the closed endpoint" $ do
    pose <- requireRight (buildCasePose 0 entry source (PoseSpec "closed" (rabbitAngles 180)))
    poseContact pose
      `shouldBe` Just (ContactCheck 28 [] [("south-panel", "ear-tip"), ("south-panel", "east-panel"), ("ear-tip", "east-panel")] [] [])
    closed <- requireRight (buildCasePose 0 (closedCase entry) source (PoseSpec "ordered endpoint" (rabbitAngles 180)))
    poseContact closed `shouldBe` Just (ContactCheck 28 [] [] [] [])
    edgeStrains (poseMesh closed) `shouldSatisfy` all ((< 1e-12) . abs)
  it "agrees with the unique flat stacking when the ear closes" $ do
    result <- requireRight (foldFrameWith source {edgesFoldAngle = rabbitAngles 180})
    pose <- requireRight (buildPose 0 source (PoseSpec "closed" (rabbitAngles 180)))
    -- Level zero retains the cut pattern's vertex indices. Put the solver's
    -- frame in the gallery's fixed plane before interpreting its normals.
    let coords (V3 x y z) = [x, y, z]
        final = (foldedFrame result) {verticesCoords = map (coords . position) (samples (poseMesh pose))}
    space <- requireRight (stackingSpace defaultBudget final)
    stateCount space `shouldBe` (1, False)
    orders <- requireRight (solveStacking final)
    faces <- requireRight (frameFaces final)
    ordered <- mapM (alongZ faces) orders
    -- In fish-base.fold: 7 = centre-south, 0 = south-panel,
    -- 1 = ear-tip, 2 = east-panel. Include all implied pairs of the chain.
    ordered `shouldMatchList` [(7, 0), (7, 1), (7, 2), (0, 1), (0, 2), (1, 2)]
  it "does not impose the closed stacking on the turning panels" $ do
    pose <- requireRight (buildCasePose 0 (closedCase entry) source (PoseSpec "turning" (rabbitAngles 60)))
    report <- requireJust (poseContact pose)
    crossingPanels report `shouldBe` []
    reversedOrders report `shouldSatisfy` (not . null)
  it "rejects scaling all endpoint angles together or perturbing just one valley" $ do
    buildPose 0 source (PoseSpec "uniform half-fold" (map (/ 2) (rabbitAngles 180))) `shouldSatisfy` isLeft
    let perturbed = [if i == (7 :: Int) then angle + 1 else angle | (i, angle) <- zip [0 ..] (rabbitAngles 60)]
    buildPose 0 source (PoseSpec "one wrong valley" perturbed) `shouldSatisfy` isLeft

-- | PB is mountain -m; PC is valley +m. PA and PE share valley +v.
-- The atan2 form remains defined at m = 180 degrees.
rabbitAngles :: Double -> [Double]
rabbitAngles magnitude = replicate 7 0 ++ [valley, magnitude, negate magnitude, valley] ++ replicate 4 0
  where
    valley = valleyAngle magnitude

valleyAngle :: Double -> Double
valleyAngle magnitude =
  let halfAngle = magnitude * pi / 360
   in 360 / pi * atan2 (sin (5 * pi / 16) * sin halfAngle) (sin (pi / 16) * cos halfAngle)

-- The south panel is upright when v = 90 degrees; the east panel when m = 90.
uprightMountain :: Double
uprightMountain = 360 / pi * atan2 (sin (pi / 16)) (sin (5 * pi / 16))

closedCase :: CaseSpec -> CaseSpec
closedCase entry = entry {caseContact = fmap complete (caseContact entry)}
  where
    complete contact = contact {panelOrders = [("centre-south", "south-panel"), ("south-panel", "ear-tip"), ("ear-tip", "east-panel")]}

-- FOLD orders are relative to the second face's normal, so downward normals
-- reverse their meaning along the gallery's fixed +z direction.
alongZ :: [Face] -> FaceOrder -> IO (Int, Int)
alongZ faces (FaceOrder a b stacking) = do
  face <- requireJust (find ((== b) . faceId) faces)
  let V3 _ _ z = polygonNormal (faceCorners face)
  abs z `shouldSatisfy` (> 1e-12)
  stacking `shouldSatisfy` (/= Unordered)
  pure (if (stacking == Above) == (z > 0) then (unFaceId b, unFaceId a) else (unFaceId a, unFaceId b))

pointAt :: (Double, Double) -> Mesh -> IO V3
pointAt (u, v) mesh = position <$> requireJust (find (\p -> abs (materialU p - u) < 1e-12 && abs (materialV p - v) < 1e-12) (samples mesh))

requireRight :: (Show e) => Either e a -> IO a
requireRight (Left err) = expectationFailure (show err) >> fail "rabbit ear failed"
requireRight (Right value) = pure value

requireJust :: Maybe a -> IO a
requireJust Nothing = expectationFailure "missing rabbit-ear fixture element" >> fail "rabbit ear failed"
requireJust (Just value) = pure value
