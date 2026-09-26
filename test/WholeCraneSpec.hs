-- | Whole-sheet attachment and drawing controls, without a material solve.
module WholeCraneSpec (spec) where

import BodyPatch
import Control.Monad (when)
import CranePocket
import CraneSpread
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import FoldMaterial (componentCount, meshEdges)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec
import WholeCrane

spec :: Spec
spec = beforeAll load $ describe "one connected whole-crane candidate" $ do
  it "keeps the complete material disk and all original vertices" $ \(_, _, study) -> do
    let fixture = wholeSpread study
        mesh = spreadMesh fixture
        original = refinedMesh (spreadRefined fixture)
    componentCount mesh `shouldBe` 1
    length (samples mesh) `shouldBe` 237
    length (triangles mesh) `shouldBe` 448
    length (samples mesh) - length (meshEdges mesh) + length (triangles mesh) `shouldBe` 1
    triangles mesh `shouldBe` triangles original
    map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples original)
    wholeMappedVertices study `shouldBe` 87
    -- Four originally coincident material points must stay distinct ids.
    let lips = pocketLips (wholeMap study)
    length lips `shouldBe` 4
    S.size (S.fromList lips) `shouldBe` 4

  it "copies the body core exactly and keeps neck and tail unheld" $ \(_, patch, study) -> do
    let mesh = spreadMesh (wholeSpread study)
        body = samples (spreadMesh (patchSpread patch))
        held = spreadPins (wholeSpread study)
    spreadHeldError (wholeSpread study) mesh `shouldBe` 0
    mapM_
      ( \(i, p) ->
          when (S.member i (wholeCore study)) $ [norm (position p ^-^ position q) | q <- body, norm (sampleMaterial p ^-^ sampleMaterial q) < 1e-12] `shouldSatisfy` (\ds -> not (null ds) && all (< 1e-12) ds)
      )
      (zip [0 ..] (samples mesh))
    [IM.member i held | (name, i) <- wholeMarks study, name `elem` ["neck-head", "tail"]] `shouldBe` [False, False]

  it "spreads both tips to opposite sides and reports a fuller body" $ \(_, _, study) -> do
    let mesh = spreadMesh (wholeSpread study)
        points = IM.fromList (zip [0 ..] (map position (samples mesh)))
        tip name = lookup name (wholeMarks study) >>= (`IM.lookup` points)
    case (tip "wing-a", tip "wing-b") of
      (Just a, Just b) -> do
        v3z a `shouldSatisfy` (> 0.1)
        v3z b `shouldSatisfy` (< -0.1)
      _ -> expectationFailure "missing wing tips"
    values <- right (wholeMeasurements study mesh)
    lookup "bodyDepth" values `shouldSatisfy` maybe False (> 0.05)
    lookup "wingTipSeparation" values `shouldSatisfy` maybe False (> 0.3)

  it "refuses changed material and a different patch target" $ \(atlas, patch, _) -> do
    let saved = spreadMesh (patchSpread patch)
    wholeCrane atlas patch {patchDegrees = 5} saved `shouldSatisfy` isLeft
    wholeCrane atlas patch saved {samples = [p {sampleMaterial = sampleMaterial p ^+^ V2 0.01 0} | p <- samples saved]} `shouldSatisfy` isLeft
    wholeCrane atlas patch saved {triangles = drop 1 (triangles saved)} `shouldSatisfy` isLeft

  it "opens a pillow on the same sheet with separate wings and intact tips" $ \(_, _, study) -> do
    mesh <- right (pillowCrane study)
    let base = refinedMesh (spreadRefined (wholeSpread study))
        points = IM.fromList (zip [0 ..] (map position (samples mesh)))
        tip name = lookup name (wholeMarks study) >>= (`IM.lookup` points)
    triangles mesh `shouldBe` triangles base
    map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples base)
    componentCount mesh `shouldBe` 1
    length (samples mesh) - length (meshEdges mesh) + length (triangles mesh) `shouldBe` 1
    all (\p -> all (\v -> not (isNaN v || isInfinite v)) [v3x p, v3y p, v3z p]) (IM.elems points) `shouldBe` True
    case (tip "wing-a", tip "wing-b", tip "neck-head", tip "tail") of
      (Just a, Just b, Just neck, Just tailTip) -> do
        v3z a * v3z b `shouldSatisfy` (< 0)
        norm (a ^-^ b) `shouldSatisfy` (> 0.5)
        v3x neck `shouldSatisfy` (< 1)
        v3x tailTip `shouldSatisfy` (> 1)
      _ -> expectationFailure "missing pillow landmarks"
    -- Negative Y is up: a cushion's centre stands above its rim, while its
    -- width spans both sides of the old flat packet's Z=0 plane.
    case tip "centre" of
      Just centre -> v3y centre `shouldSatisfy` (< 0.44)
      _ -> expectationFailure "missing pillow centre"
    values <- right (wholeMeasurements study mesh)
    lookup "bodyDepth" values `shouldSatisfy` maybe False (> 0.2)

load :: IO (PocketMap, BodyPatch, WholeCrane)
load = do
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)
  atlas <- right (buildCranePocket source)
  patch <- right (bodyPatch atlas 1 10)
  archived <- keyFrame <$> (loadFoldFile "study/fold-material/fixtures/whole-crane-body.fold" >>= right)
  sheet <- right (surfaceFromFrame archived >>= requireMaterialCoordinates)
  let mesh = (spreadMesh (patchSpread patch)) {samples = surfaceSamples sheet}
      savedPatch = patch {patchSpread = (patchSpread patch) {spreadMesh = mesh}}
  _ <- right (spreadSurface (patchSpread patch) mesh)
  study <- right (wholeCrane atlas savedPatch mesh)
  pure (atlas, savedPatch, study)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
