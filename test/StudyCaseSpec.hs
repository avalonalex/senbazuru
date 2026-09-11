-- | Geometry assertions independent of the viewer and of its chosen camera.
module StudyCaseSpec (spec) where

import Control.Monad (forM_, unless)
import Data.Aeson (eitherDecode)
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft)
import Data.List (find)
import FoldMaterial
import PanelContact
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (Assignment (..), FoldFile (..), Frame (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import StudyCase
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "authored material-study cases" $ do
  cases <- runIO $ BL.readFile "study/fold-material/cases.json" >>= requireRight . eitherDecode
  forM_ (cases :: [CaseSpec]) $ \entry -> describe (caseId entry) $ do
    source <- runIO $ keyFrame <$> (loadFoldFile (caseSource entry) >>= requireRight)
    forM_ (caseSteps entry) $ \step -> it (show (poseLabel step) ++ " preserves material and shared topology") $ do
      pose <- requireRight (buildPose 3 source step)
      let mesh = poseMesh pose
      componentCount mesh `shouldBe` 1
      length (samples mesh) - length (meshEdges mesh) + length (triangles mesh) `shouldBe` 1
      edgeStrains mesh `shouldSatisfy` all ((< 1e-12) . abs)
      abs (areaRatio mesh - 1) `shouldSatisfy` (< 1e-12)
      resolvedTriangles mesh `shouldSatisfy` all (\(a, b, c) -> norm (cross (position b ^-^ position a) (position c ^-^ position a)) > 1e-10)
      length (posePanels pose) `shouldBe` length (triangles mesh)
      -- Flat guides subdivide the material but are omitted from the 3D edges.
      length (poseLines pose) `shouldBe` length (filter (`elem` [Border, Mountain, Valley]) (edgesAssignment source))
    unless (coupledCreases entry) $
      it "preserves lengths for arbitrary independent hinge angles and refinements" $
        forAll (choose (-175, 175)) $ \angle ->
          forAll (chooseInt (0, 3)) $ \level ->
            let angles = if caseId entry == "double" then replicate 8 0 ++ [angle, 0, angle, 0] else [if a == 0 then 0 else angle | a <- edgesFoldAngle source]
             in case buildPose level source (PoseSpec "arbitrary" angles) of
                  Left err -> counterexample (show (explain err)) False
                  Right pose -> property (all ((< 1e-12) . abs) (edgeStrains (poseMesh pose)))
    it "refuses an incomplete angle list instead of truncating it" $
      buildPose 1 source (PoseSpec "missing angles" []) `shouldSatisfy` isLeft
    it "refuses a non-finite crease angle" $ do
      let angles = [if a == 0 then 0 else 0 / 0 | a <- edgesFoldAngle source]
      buildPose 1 source (PoseSpec "NaN" angles) `shouldSatisfy` isLeft
    it "keeps all refinement vertices in one consistent material winding" $ do
      pose <- requireRight (buildPose 2 source (PoseSpec "flat" (replicate (length (edgesVertices source)) 0)))
      resolvedTriangles (poseMesh pose) `shouldSatisfy` all (\(a, b, c) -> let V3 _ _ z = cross (position b ^-^ position a) (position c ^-^ position a) in z > 0)
  forM_ [entry | entry <- cases, Just _ <- [caseContact entry]] $ \entry -> describe (caseId entry ++ " contact") $ do
    source <- runIO $ keyFrame <$> (loadFoldFile (caseSource entry) >>= requireRight)
    forM_ (caseSteps entry) $ \step -> it (show (poseLabel step) ++ " meets contact and order requirements") $ do
      pose <- requireRight (buildCasePose 3 entry source step)
      let panels = length (poseFaces pose)
          expectedPairs = panels * (panels - 1) `div` 2
      poseContact pose `shouldBe` Just (ContactCheck expectedPairs [] [] [] [])
    -- The rabbit ear's moving panels exchange vertical order during the turn.
    -- Its case declares only stable relations to the fixed paper; RabbitEarSpec
    -- checks the complete closed stacking separately, including missing orders.
    unless (caseId entry == "rabbit-ear") $
      it "accepts ordered contact when all flaps close to 180 degrees" $ do
        finalStep <- finalPose entry
        let angles = map (\angle -> signum angle * 180) (poseAngles finalStep)
        pose <- requireRight (buildCasePose 1 entry source (PoseSpec "closed" angles))
        poseContact pose `shouldSatisfy` maybe False contactPassed
    it "reports the wrong folding side even without a panel crossing" $ do
      finalStep <- finalPose entry
      let angles = map negate (poseAngles finalStep)
      pose <- requireRight (buildCasePose 1 entry source (PoseSpec "wrong side" angles))
      poseContact pose `shouldSatisfy` maybe False (not . null . reversedOrders)
      fmap crossingPanels (poseContact pose) `shouldBe` Just []
    it "keeps contact checks independent of mesh refinement and edge numbering" $ do
      finalStep <- finalPose entry
      let angles = poseAngles finalStep
          reordered = source {edgesVertices = reverse (edgesVertices source), edgesAssignment = reverse (edgesAssignment source), edgesFoldAngle = reverse (edgesFoldAngle source)}
      coarse <- requireRight (buildCasePose 0 entry source (PoseSpec "coarse" angles))
      fine <- requireRight (buildCasePose 3 entry reordered (PoseSpec "fine" (reverse angles)))
      poseContact fine `shouldBe` poseContact coarse
    it "refuses missing, repeated or boundary-anchored panel declarations" $ do
      let step = PoseSpec "flat" (replicate (length (edgesVertices source)) 0)
          alter f = entry {caseContact = fmap f (caseContact entry)}
          missing spec' = spec' {namedPanels = drop 1 (namedPanels spec')}
          repeated spec' = spec' {namedPanels = namedPanels spec' ++ take 1 (namedPanels spec')}
          boundary spec' = spec' {namedPanels = [tag {tagAt = V2 0 0} | tag <- namedPanels spec']}
      mapM_ (\change -> buildCasePose 1 (alter change) source step `shouldSatisfy` isLeft) [missing, repeated, boundary]
  it "keeps the left half fixed when opening the controls' first fold" $
    forM_ [("examples/book-base.fold", replicate 6 0 ++ [90]), ("examples/quarter-fold.fold", replicate 8 0 ++ [90, 0, 90, 0])] $ \(path, angles) -> do
      source <- keyFrame <$> (loadFoldFile path >>= requireRight)
      pose <- requireRight (buildPose 1 source (PoseSpec "first fold" angles))
      pointAt (0, 0) (poseMesh pose) `shouldSatisfy` maybe False (near (V3 0 0 0))
      pointAt (1, 0) (poseMesh pose) `shouldSatisfy` maybe False (near (V3 0.5 0 0.5))
  it "folds the kite's two free corners onto its diagonal" $ do
    source <- keyFrame <$> (loadFoldFile "examples/kite-base.fold" >>= requireRight)
    pose <- requireRight (buildPose 2 source (PoseSpec "flat-folded" (replicate 6 0 ++ [180, 180])))
    mapM_ (\uv -> pointAt uv (poseMesh pose) `shouldSatisfy` maybe False (near (V3 (sqrt 0.5) (sqrt 0.5) 0))) [(1, 0), (0, 1)]
    pointAt (1, 1) (poseMesh pose) `shouldSatisfy` maybe False (near (V3 1 1 0))
  it "brings all four blintz corners to the centre at 180 degrees" $ do
    source <- keyFrame <$> (loadFoldFile "examples/blintz-base.fold" >>= requireRight)
    pose <- requireRight (buildPose 2 source (PoseSpec "flat-folded" (replicate 8 0 ++ replicate 4 180)))
    mapM_ (\uv -> pointAt uv (poseMesh pose) `shouldSatisfy` maybe False (near (V3 0.5 0.5 0))) [(0, 0), (1, 0), (1, 1), (0, 1)]
  it "lifts the first blintz corner while the other three stay still" $ do
    source <- keyFrame <$> (loadFoldFile "examples/blintz-base.fold" >>= requireRight)
    pose <- requireRight (buildPose 1 source (PoseSpec "first flap" (replicate 8 0 ++ [90, 0, 0, 0])))
    pointAt (1, 0) (poseMesh pose) `shouldSatisfy` maybe False (near (V3 0.75 0.25 (sqrt 0.125)))
    mapM_ (\uv@(u, v) -> pointAt uv (poseMesh pose) `shouldSatisfy` maybe False (near (V3 u v 0))) [(0, 0), (1, 1), (0, 1)]

requireRight :: (Show e) => Either e a -> IO a
requireRight (Left err) = expectationFailure (show err) >> fail "fixture failed"
requireRight (Right value) = pure value

coupledCreases :: CaseSpec -> Bool
coupledCreases entry = caseId entry `elem` ["square", "waterbomb", "rabbit-ear"]

finalPose :: CaseSpec -> IO PoseSpec
finalPose entry = case reverse (caseSteps entry) of
  step : _ -> pure step
  [] -> expectationFailure "case has no folding states" >> fail "empty case"

pointAt :: (Double, Double) -> Mesh -> Maybe V3
pointAt (u, v) mesh = position <$> find (\s -> materialU s == u && materialV s == v) (samples mesh)

near :: V3 -> V3 -> Bool
near expected actual = norm (expected ^-^ actual) < 1e-12
