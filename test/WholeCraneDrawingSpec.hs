-- | Crossings must change the visible surface, not be painted in one order.
module WholeCraneDrawingSpec (spec) where

import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera (topDown)
import Test.Hspec
import WholeCraneDrawing

spec :: Spec
spec = describe "static nearest-surface preview" $ do
  it "splits a crossing overlap along equal camera depth" $ do
    let square = [V2 0 0, V2 1 0, V2 1 1, V2 0 1]
        rightHalf = nearerPart (\(V2 x _) -> x - 0.5) square
        leftHalf = nearerPart (\(V2 x _) -> 0.5 - x) square
    abs (signedArea rightHalf - 0.5) `shouldSatisfy` (< 1e-12)
    abs (signedArea leftHalf - 0.5) `shouldSatisfy` (< 1e-12)
  it "does not let almost repeated clipping corners invent a cutting plane" $ do
    let ring = [V2 0 0, V2 1 0, V2 (1 + 4e-16) 1e-16, V2 1 1, V2 0 1]
        kept = nearerPart (const 1) ring
    length kept `shouldBe` 4
    abs (signedArea kept - 1) `shouldSatisfy` (< 1e-12)
  it "draws both sides of intersecting triangles without a silhouette hole" $ do
    result <- either (fail . show) pure (depthDrawing topDown crossing [])
    map regionFace (formRegions (depthForm result)) `shouldBe` [FaceId 0, FaceId 1]
    depthMissing result `shouldBe` []
    depthIdTies result `shouldBe` 0
  it "honours an inherited order on coincident paper" $ do
    let flat = crossing {verticesCoords = [[x, y, 0] | [x, y, _] <- verticesCoords crossing]}
    result <- either (fail . show) pure (depthDrawing topDown flat [FaceOrder (FaceId 1) (FaceId 0) Above])
    map regionFace (formRegions (depthForm result)) `shouldBe` [FaceId 1]
    depthMissing result `shouldBe` []
    depthIdTies result `shouldBe` 0
  it "records missing coplanar order rather than calling the preview certified" $ do
    let flat = crossing {verticesCoords = [[x, y, 0] | [x, y, _] <- verticesCoords crossing]}
    result <- either (fail . show) pure (depthDrawing topDown flat [])
    depthIdTies result `shouldBe` 1
    length (formRegions (depthForm result)) `shouldBe` 1

crossing :: Frame
crossing = emptyFrame {verticesCoords = [[0, 0, -0.5], [1, 0, 0.5], [0, 1, -0.5], [0, 0, 0], [1, 0, 0], [0, 1, 0]], facesVertices = map (map VertexId) [[0, 1, 2], [3, 4, 5]]}
