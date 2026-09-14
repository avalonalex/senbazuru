-- | Material identity and unilateral contact in the held two-layer experiment.
-- Endpoint checks are independent of the force rows used by the optimizer.
module WingLayersSpec (spec) where

import Control.Monad (forM_, when)
import Data.Aeson (eitherDecode, encode, toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FoldBending
import FoldMaterial (componentCount, resolvedTriangles)
import FoldRelaxation
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact
import Test.Hspec
import WingBending (finalMesh)
import WingLayers

spec :: Spec
spec = describe "two held touching layers" $ do
  forM_ [8, 16] $ \n -> it ("shares only the real root crease at " ++ show n ++ " divisions") $ do
    fixture <- right (wingLayers n 0)
    let mesh = layersMesh fixture
        vertices = IM.fromList (zip [0 ..] (samples mesh))
    componentCount mesh `shouldBe` 1
    [i | (i, j) <- layersPairs fixture, i == j] `shouldBe` layersRoot fixture
    length (layersRoot fixture) `shouldBe` n + 1
    forM_ (layersPairs fixture) $ \(i, j) -> do
      a <- vertex vertices i
      b <- vertex vertices j
      position a `shouldBe` position b
      sampleMaterial b `shouldBe` V2 (negate (materialU a)) (materialV a)
    result <- right (solveLayers defaultSettings fixture)
    converged result `shouldBe` True
    mesh' <- right (finalMesh result)
    mesh' `shouldBe` mesh
    heldAndClosed fixture result
    unranked <- right (checkTriangleContact up [] (layersOwners fixture) mesh)
    contactPassed unranked `shouldBe` False

  forM_ [("touching", id), ("initially penetrating", perturbUpper (-0.002)), ("upper grip lifted", offsetUpperGrip 0.01)] $ \(name, modify) ->
    beforeAll (settled modify) $ do
      it ("settles " ++ name ++ " without changing material or held vertices") $ \(fixture, result, mesh) -> do
        converged result `shouldBe` True
        triangles mesh `shouldBe` triangles (layersMesh fixture)
        map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples (layersMesh fixture))
        maxLengthError mesh `shouldSatisfy` (< 1e-6)
        forM_ (resolvedTriangles mesh) $ \triangle -> case principalStrains triangle of
          Nothing -> expectationFailure "degenerate material triangle"
          Just (lo, hi) -> max (abs lo) (abs hi) `shouldSatisfy` (< 1e-6)
        heldAndClosed fixture result
        endpoint <- right (checkTriangleContact up order (layersOwners fixture) mesh)
        contactPassed endpoint `shouldBe` True
        checkedPanelPairs endpoint `shouldBe` 128 * 127 `div` 2
        when (name == "initially penetrating") $ do
          initial <- right (checkTriangleContact up order (layersOwners fixture) (layersMesh fixture))
          contactPassed initial `shouldBe` False
        when (name == "upper grip lifted") $ do
          let vertices = IM.fromList (zip [0 ..] (samples mesh))
          distances <- mapM (\(i, j) -> (\a b -> norm (position a ^-^ position b)) <$> vertex vertices i <*> vertex vertices j) (layersPairs fixture)
          maximum distances `shouldSatisfy` (> 0.009)
      it ("exports " ++ name ++ " with original panels, root crease and order") $ \(fixture, _, mesh) -> do
        sheet <- right (layersSurface fixture mesh)
        let frame = materialFrame sheet
        surfaceSamples sheet `shouldBe` samples mesh
        length (filter (== Valley) (edgesAssignment frame)) `shouldBe` 8
        edgesAssignment frame `shouldSatisfy` all (`elem` [Border, Join, Valley])
        edgesFoldAngle frame `shouldBe` []
        KM.lookup "senbazuru:source_panels" (frameExtras frame) `shouldBe` Just (toJSON (map unFaceId (layersOwners fixture)))
        KM.lookup "senbazuru:source_edges" (frameExtras frame) `shouldBe` Just (toJSON [if assignment == Valley then Just (0 :: Int) else Nothing | assignment <- edgesAssignment frame])
        faceOrders frame `shouldSatisfy` (not . null)
        forM_ (faceOrders frame) $ \(FaceOrder (FaceId lower) (FaceId upper) side) -> do
          lower `shouldSatisfy` (< 64)
          upper `shouldSatisfy` (>= 64)
          side `shouldBe` Above -- Upper triangles face down, so Above points down.
        decoded <- right (eitherDecode (encode frame))
        restored <- right (surfaceFromFrame decoded >>= requireMaterialCoordinates)
        surfaceSamples restored `shouldBe` samples mesh

  it "keeps an incompatible grip exact and refuses to call it settled" $ do
    fixture <- offsetUpperGrip (-0.01) <$> right (wingLayers 8 40)
    result <- right (solveLayers (Settings 2 1e-5) fixture)
    converged result `shouldBe` False
    heldAndClosed fixture result
    mesh <- right (finalMesh result)
    contact <- right (checkTriangleContact up order (layersOwners fixture) mesh)
    contactPassed contact `shouldBe` False
    reversedOrders contact `shouldSatisfy` (not . null)
  it "validates grip targets and refuses an export with different material" $ do
    fixture <- right (wingLayers 8 20)
    contact <- right (Contact.prepareContact 0 up order (layersOwners fixture) (layersMesh fixture))
    relaxPinnedContact defaultSettings (IM.singleton (-1) (V3 0 0 0)) (layersHinges fixture) contact (layersMesh fixture) `shouldBe` Left (InvalidPositionConstraint (-1))
    let mesh = layersMesh fixture
    layersSurface fixture mesh {samples = drop 1 (samples mesh)} `shouldSatisfy` isLeft

settled :: (WingLayers -> WingLayers) -> IO (WingLayers, Relaxation, MaterialMesh)
settled modify = do
  fixture <- modify <$> right (wingLayers 8 40)
  result <- right (solveLayers defaultSettings fixture)
  mesh <- right (finalMesh result)
  pure (fixture, result, mesh)

heldAndClosed :: WingLayers -> Relaxation -> IO ()
heldAndClosed fixture result = forM_ (checkpoints result) $ \checkpoint -> do
  let vertices = IM.fromList (zip [0 ..] (samples (checkpointMesh checkpoint)))
  forM_ (IM.toList (layersPins fixture)) $ \(i, target) -> do
    actual <- vertex vertices i
    position actual `shouldBe` target
  forM_ [h | h <- layersHinges fixture, SurfaceCrease _ <- [hingeRole h]] $ \h -> do
    (angle, _) <- right (hingeAngle h vertices)
    abs (angleError angle pi) `shouldSatisfy` (< 1e-12)

vertex :: IM.IntMap a -> Int -> IO a
vertex vertices i = maybe (fail ("missing vertex " ++ show i)) pure (IM.lookup i vertices)

up :: V3
up = V3 0 0 1

order :: [(FaceId, FaceId)]
order = [(FaceId 0, FaceId 1)]

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
