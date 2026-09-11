-- | Check the solver against material distances, not a preferred silhouette.
module FoldRelaxationSpec (spec) where

import FoldContact
import FoldMaterial
import FoldRelaxation
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Test.Hspec

spec :: Spec
spec = describe "fold-length relaxation" $ do
  it "leaves an isometric single fold unchanged without doing an iteration" $ do
    let mesh = sharpMesh 4 Single
    relaxLengths defaultSettings mesh `shouldBe` Right (Relaxation [Checkpoint 0 mesh (maxLengthError mesh)] True)
  it "reports exhausted work as unconverged, including the unchanged starting mesh" $ do
    let mesh = sharpMesh 4 Double
    relaxLengths (Settings 0 1e-8) mesh `shouldBe` Right (Relaxation [Checkpoint 0 mesh (maxLengthError mesh)] False)
  it "reduces the double fold's material error and preserves its shared topology" $ do
    let mesh = sharpMesh 4 Double
    case relaxLengths defaultSettings mesh of
      Left err -> expectationFailure (show err)
      Right result -> case reverse (checkpoints result) of
        [] -> expectationFailure "the solver omitted its final measurement"
        final : _ -> do
          let relaxed = checkpointMesh final
          checkpointError final `shouldSatisfy` (< maxLengthError mesh / 50)
          checkpointError final `shouldBe` maxLengthError relaxed
          converged result `shouldBe` (checkpointError final <= lengthTolerance defaultSettings)
          triangles relaxed `shouldBe` triangles mesh
          map (\s -> (materialU s, materialV s)) (samples relaxed) `shouldBe` map (\s -> (materialU s, materialV s)) (samples mesh)
          componentCount relaxed `shouldBe` 1
          norm (meanPosition relaxed ^-^ meanPosition mesh) `shouldSatisfy` (< 1e-12)
  it "meets the declared length tolerance on the full viewer mesh" $ do
    case relaxLengths defaultSettings (sharpMesh 16 Double) of
      Left err -> expectationFailure (show err)
      Right result -> do
        converged result `shouldBe` True
        case reverse (checkpoints result) of
          [] -> expectationFailure "no final checkpoint"
          final : _ -> do
            checkpointError final `shouldSatisfy` (<= lengthTolerance defaultSettings)
            abs (areaRatio (checkpointMesh final) - 1) `shouldSatisfy` (< 1e-5)
            -- Meeting the length target does not prevent layers crossing.
            let contact = packetCheck Double (checkpointMesh final)
            uncheckedTriangles contact `shouldBe` 0
            violatingPairs contact `shouldSatisfy` (> 0)
  it "also keeps the full viewer packet in order when contact is enabled" $ do
    let mesh = sharpMesh 16 Double
    case relaxPacket defaultSettings Double mesh of
      Left err -> expectationFailure (show err)
      Right result -> do
        converged result `shouldBe` True
        case reverse (checkpoints result) of
          [] -> expectationFailure "no final checkpoint"
          final : _ -> do
            let fitted = checkpointMesh final
                contact = packetCheck Double fitted
            checkpointError final `shouldSatisfy` (<= lengthTolerance defaultSettings)
            violatingPairs contact `shouldBe` 0
            maxOrderViolation contact `shouldSatisfy` (<= contactTolerance)
            uncheckedTriangles contact `shouldBe` 0
            triangles fitted `shouldBe` triangles mesh
            map (\s -> (materialU s, materialV s)) (samples fitted) `shouldBe` map (\s -> (materialU s, materialV s)) (samples mesh)
            componentCount fitted `shouldBe` 1
            abs (areaRatio fitted - 1) `shouldSatisfy` (< 1e-5)
    relaxPacket defaultSettings Single (sharpMesh 4 Single) `shouldBe` relaxLengths defaultSettings (sharpMesh 4 Single)
  it "measures stretches in directions other than triangle edges" $ do
    let a = materialSample 0 0 (V3 0 0 0)
        b = materialSample 1 0 (V3 2 0 0)
        c = materialSample 0 1 (V3 0 0.5 0)
    principalStrains (a, b, c) `shouldBe` Just (-0.5, 1)
  it "measures zero strain after a rigid rotation and translation" $ do
    let a = materialSample 0 0 (V3 3 4 5)
        b = materialSample 1 0 (V3 3 5 5)
        c = materialSample 0 1 (V3 3 4 6)
    principalStrains (a, b, c) `shouldBe` Just (0, 0)
  it "rejects malformed meshes and numerical settings before projecting" $ do
    let a = materialSample 0 0 (V3 0 0 0)
        b = materialSample 1 0 (V3 1 0 0)
        c = materialSample 0 1 (V3 0 1 0)
        triangle = Mesh [a, b, c] [(0, 1, 2)]
    relaxLengths (Settings (-1) 1e-5) triangle `shouldBe` Left InvalidSettings
    relaxLengths (Settings 10 (0 / 0)) triangle `shouldBe` Left InvalidSettings
    relaxLengths defaultSettings (Mesh [] []) `shouldBe` Left EmptyMesh
    relaxLengths defaultSettings (triangle {triangles = [(0, 1, 3)]}) `shouldBe` Left (MissingVertex 0 3)
    relaxLengths defaultSettings (Mesh [a, b, b] [(0, 1, 2)]) `shouldBe` Left (DegenerateMaterialTriangle 0)
    relaxLengths defaultSettings (Mesh [a, b {position = position a}, c] [(0, 1, 2)]) `shouldBe` Left (CollapsedEdge 0 1)
    relaxLengths defaultSettings (Mesh [a {position = V3 (0 / 0) 0 0}, b, c] [(0, 1, 2)]) `shouldBe` Left (InvalidSample 0)

meanPosition :: MaterialMesh -> V3
meanPosition mesh = (1 / fromIntegral (length (samples mesh))) *^ foldr ((^+^) . position) (V3 0 0 0) (samples mesh)
