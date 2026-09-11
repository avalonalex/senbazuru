-- | Check the selected symmetric collapse of the square and waterbomb bases.
-- These have six active creases around one centre; their angles cannot be
-- chosen independently. The manifest records samples of a geometric family,
-- not a numerical simulation or a prediction of paper's spring-back.
--
-- For mountain magnitude m, the valley angle is
-- 2 atan (sqrt 2 * tan (m/2)). The atan2 form below also handles the closed
-- endpoint. Independent distances between material points check the resulting
-- shape, rather than only comparing that formula with its recorded samples.
-- The derivation is in docs/notes/symmetric-base-collapse.md.
module BaseCollapseSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (eitherDecode)
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft)
import Data.List (find)
import FoldMaterial
import PanelContact
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (Assignment (..), Frame (..), keyFrame)
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Geometry.VectorSpace
import StudyCase
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "symmetric base collapse" $ do
  cases <- runIO $ BL.readFile "study/fold-material/cases.json" >>= requireRight . eitherDecode
  it "includes both meeting-crease bases in the gallery" $
    [caseId entry | entry <- cases, caseId entry `elem` ["square", "waterbomb"]] `shouldMatchList` ["square", "waterbomb"]
  forM_ [entry | entry <- cases, caseId entry `elem` ["square", "waterbomb"]] $ \entry -> describe (caseId entry) $ do
    source <- runIO $ keyFrame <$> (loadFoldFile (caseSource entry) >>= requireRight)
    it "records seven compatible states, keeping the two guides flat" $ do
      let magnitudes = [0, 30, 60, 90, 120, 150, 175]
      length (caseSteps entry) `shouldBe` length magnitudes
      forM_ (zip (caseSteps entry) magnitudes) $ \(step, magnitude) -> do
        let expected = symmetricAngles source magnitude
        length (poseAngles step) `shouldBe` length expected
        zipWith (-) (poseAngles step) expected `shouldSatisfy` all ((< 1e-12) . abs)
    it "closes the centre and preserves material at random angles and refinements" $
      forAll (choose (0.1, 179.9)) $ \magnitude ->
        forAll (chooseInt (0, 2)) $ \level ->
          case buildCasePose level entry source (PoseSpec "sample" (symmetricAngles source magnitude)) of
            Left err -> counterexample (show err) False
            Right pose ->
              let mesh = poseMesh pose
               in counterexample (show (poseContact pose)) $
                    componentCount mesh == 1
                      && all ((< 1e-12) . abs) (edgeStrains mesh)
                      && abs (areaRatio mesh - 1) < 1e-12
                      && maybe False contactPassed (poseContact pose)
    it "checks all panel pairs along a one-degree sweep, including both endpoints" $
      forM_ [0 .. 180 :: Int] $ \degree -> do
        pose <- requireRight (buildCasePose 0 entry source (PoseSpec "sweep" (symmetricAngles source (fromIntegral degree))))
        poseContact pose `shouldBe` Just (ContactCheck 28 [] [] [] [])
    it "matches independently derived distances between opposite parts of the sheet" $
      forM_ [30, 60, 90, 120, 150, 175] $ \magnitude -> do
        pose <- requireRight (buildPose 0 source (PoseSpec "distance" (symmetricAngles source magnitude)))
        let halfAngle = magnitude * pi / 360
            c = cos halfAngle
            s = sin halfAngle
            inward = c * c / (1 + s * s)
            pairs =
              if caseId entry == "waterbomb"
                then [((1, 0), (1, 1), c), ((0, 0.5), (1, 0.5), inward)]
                else [((0.5, 1), (1, 0.5), c / sqrt 2), ((0, 0), (1, 1), sqrt 2 * inward)]
        forM_ pairs $ \(uv, uv', expected) -> do
          p <- pointAt uv (poseMesh pose)
          q <- pointAt uv' (poseMesh pose)
          abs (norm (p ^-^ q) - expected) `shouldSatisfy` (< 1e-12)
    it "rejects a half-collapse obtained by scaling all final angles equally" $
      buildPose 0 source (PoseSpec "incompatible" (map (/ 2) (edgesFoldAngle source))) `shouldSatisfy` isLeft
    it "rejects perturbing just one crease of a compatible intermediate state" $ do
      let perturbed = case splitAt 8 (symmetricAngles source 90) of
            (boundary, angle : rest) -> boundary ++ (angle + 1) : rest
            (boundary, []) -> boundary
      buildPose 0 source (PoseSpec "one wrong angle" perturbed) `shouldSatisfy` isLeft

symmetricAngles :: Frame -> Double -> [Double]
symmetricAngles source magnitude = map angle (edgesAssignment source)
  where
    halfAngle = magnitude * pi / 360
    valley = 360 / pi * atan2 (sqrt 2 * sin halfAngle) (cos halfAngle)
    angle Mountain = negate magnitude
    angle Valley = valley
    angle _ = 0

pointAt :: (Double, Double) -> Mesh -> IO V3
pointAt (u, v) mesh = case find (\p -> materialU p == u && materialV p == v) (samples mesh) of
  Just p -> pure (position p)
  Nothing -> expectationFailure "missing original material point" >> fail "invalid mesh"

requireRight :: (Show e) => Either e a -> IO a
requireRight (Left err) = expectationFailure (show err) >> fail "collapse failed"
requireRight (Right value) = pure value
