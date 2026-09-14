-- | A flexible wing must remain part of the original crane, including its
-- tucked tail. Test material and contacts independently of solver convergence.
module CraneSpreadSpec (spec) where

import Control.Monad (forM_)
import CraneSpread
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import FoldMaterial (componentCount)
import FoldRelaxation
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Hspec
import WingBending (finalMesh)

spec :: Spec
spec = beforeAll load $ describe "spreading the connected crane wing" $ do
  it "bends the four wing panels while keeping the body, tail and crease angles fixed" $ \source -> do
    fixture <- right (craneSpread source 3 20)
    result <- right (solveSpread (Settings 20 1e-5) fixture)
    mesh <- right (finalMesh result)
    accepted <- right (spreadAccepted fixture result mesh)
    accepted `shouldBe` True
    S.size (spreadMoving fixture) `shouldBe` 4
    componentCount mesh `shouldBe` 1
    maxLengthError mesh `shouldSatisfy` (< 1e-6)
    spreadHeldError fixture mesh `shouldBe` 0
    angle <- right (spreadAngleError fixture mesh)
    angle `shouldSatisfy` (< 1e-5)
    let original = refinedMesh (spreadRefined fixture)
        initial = IM.fromList (zip [0 ..] (samples original))
        changed = IM.fromList (zip [0 ..] (samples mesh))
    map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples original)
    triangles mesh `shouldBe` triangles original
    forM_ (S.toList (spreadBody fixture)) $ \i -> IM.lookup i changed `shouldBe` IM.lookup i initial
    length (spreadOrders fixture) `shouldBe` length (faceOrders (surfaceFrame (spreadSource fixture)))
    exported <- right (spreadSurface fixture mesh)
    surfaceSamples exported `shouldBe` samples mesh
    -- Exported orders refer to TRIANGLE faces, but must still pass the same
    -- directional check when interpreted relative to each upper normal.
    faces <- right (frameFaces (surfaceFrame exported))
    let normals = M.fromList [(faceId face, polygonNormal (faceCorners face)) | face <- faces]
        worldOrder order = case M.lookup (orderRelativeTo order) normals of
          Just (V3 _ _ z) -> let a = unFaceId (orderFace order); b = unFaceId (orderRelativeTo order) in if (orderStacking order == Above) == (z > 0) then [(b, a)] else [(a, b)]
          Nothing -> []
    exportedCheck <- right (checkLocalTriangleContact (V3 0 0 1) (concatMap worldOrder (faceOrders (surfaceFrame exported))) mesh)
    contactPassed exportedCheck `shouldBe` True
    rigid <- right (craneSpread source 3 0)
    let paired = zip (samples mesh) (samples (spreadMesh rigid))
    maximum (0 : [norm (position a ^-^ position b) | (a, b) <- paired]) `shouldSatisfy` (> 0.02)

  it "recovers the rigid 30-degree baseline without adding curvature" $ \source -> do
    fixture <- right (craneSpread source 3 0)
    result <- right (solveSpread (Settings 20 1e-5) fixture)
    mesh <- right (finalMesh result)
    right (spreadAccepted fixture result mesh) `shouldReturn` True
    maximum (0 : zipWith (\a b -> norm (position a ^-^ position b)) (samples mesh) (samples (spreadMesh fixture))) `shouldSatisfy` (< 1e-8)

  it "refuses an upper grip pushed through its partner even if the linear solve succeeds" $ \source -> do
    fixture <- crossedGrip <$> right (craneSpread source 3 20)
    initial <- right (spreadCheck fixture (spreadMesh fixture))
    reversedOrders initial `shouldSatisfy` (not . null)
    result <- right (solveSpread (Settings 2 1e-5) fixture)
    mesh <- right (finalMesh result)
    right (spreadAccepted fixture result mesh) `shouldReturn` False
    spreadHeldError fixture mesh `shouldBe` 0

  it "keeps source crease ids during local refinement and rejects changed material" $ \source -> do
    fixture <- right (craneSpread source 3 20)
    let refined = spreadRefined fixture
        mesh = refinedMesh refined
        ids = S.fromList (map fst (refinedEdges refined))
    S.size ids `shouldBe` length (edgesVertices (surfaceFrame (spreadSource fixture)))
    length (triangles mesh) `shouldSatisfy` (< 500)
    spreadSurface fixture mesh {triangles = reverse (triangles mesh)} `shouldSatisfy` isLeft
    forM_ [-1, 21, 0 / 0, 1 / 0] $ \angle -> craneSpread source 3 angle `shouldSatisfy` isLeft
    craneSpread source 2 20 `shouldSatisfy` isLeft

load :: IO Frame
load = keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
