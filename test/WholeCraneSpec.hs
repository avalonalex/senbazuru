-- | Whole-sheet attachment and drawing controls, without a material solve.
module WholeCraneSpec (spec) where

import BodyPatch
import Control.Monad (forM_, when)
import CranePocket
import CraneSpread
import Data.Aeson (Value (..))
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
import Test.Glb (Glb (..), at, items, parseGlb)
import Test.Hspec
import WholeCrane
import WholeCraneExport

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

  it "changes wing spread while preserving the cushion, material and arch lengths" $ \(_, _, study) -> do
    middle <- right (narrowPillowCrane study)
    poses <- traverse (\amount -> right (pillowCraneAtSpread amount study)) [0, 0.25, 0.5, 0.75, 1]
    midpoint <- right (pillowCraneAtSpread 0.5 study)
    map position (samples midpoint) `shouldBe` map position (samples middle)
    let base = refinedMesh (spreadRefined (wholeSpread study))
        core mesh = [position p | (i, p) <- zip [0 ..] (samples mesh), S.member i (wholeCore study)]
        -- Exclusive outer-wing triangles keep their shape when the arch
        -- turns. The body-to-wing collar is deliberately free to distort.
        outerEdges = [(a, b) | (a, b) <- meshEdges base, Just p <- [IM.lookup a originals], v3y (position p) < 0.25, Just q <- [IM.lookup b originals], v3y (position q) < 0.25]
        originals = IM.fromList (zip [0 ..] (samples base))
        lengths mesh = let points = IM.fromList (zip [0 ..] (map position (samples mesh))) in [norm (p ^-^ q) | (a, b) <- outerEdges, Just p <- [IM.lookup a points], Just q <- [IM.lookup b points]]
    outerEdges `shouldSatisfy` (not . null)
    forM_ poses $ \mesh -> do
      core mesh `shouldBe` core middle
      triangles mesh `shouldBe` triangles base
      map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples base)
      zipWith (\a b -> abs (a - b)) (lengths mesh) (lengths middle) `shouldSatisfy` all (< 1e-12)
    measurements <- traverse (right . wholeMeasurements study) poses
    let spans = [spanValue | values <- measurements, Just spanValue <- [lookup "wingTipSeparation" values]]
    length spans `shouldBe` 5
    and (zipWith (<) spans (drop 1 spans)) `shouldBe` True

  it "refuses a non-finite or out-of-range wing spread" $ \(_, _, study) ->
    forM_ [-0.1, 1.1, 0 / 0, 1 / 0, -(1 / 0)] $ \amount ->
      pillowCraneAtSpread amount study `shouldSatisfy` isLeft

  forM_ [("a wide pillow", pillowCrane), ("a less spread pillow", compactPillowCrane), ("a narrower pillow", narrowPillowCrane)] $ \(description, makePillow) ->
    it ("opens " ++ description ++ " on the same sheet with separate wings and intact tips") $ \(_, _, study) -> do
      mesh <- right (makePillow study)
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

  -- The complete scene alone leaves a viewer to pick between coincident
  -- layers by its depth buffer (PRD 11, R-11-10). Exporting it alone, or
  -- leading with it, turns this red.
  it "gives the viewers visible paper first and every layer second" $ \(_, _, study) -> do
    let fixture = wholeSpread study
    sheet <- right (spreadSurface fixture (refinedMesh (spreadRefined fixture)))
    glb <- right (viewerGlb "Closed crane" sheet) >>= parseGlb
    map (at "name") (items (at "scenes" (glbJson glb))) `shouldBe` [String "Visible paper", String "Complete paper"]
    at "scene" (glbJson glb) `shouldBe` Number 0

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
