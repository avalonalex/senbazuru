-- | Refinement can change a surface between shared vertices. Exercise that
-- failure directly, including crossed material diagonals and a hidden bump.
module IllustrationComparisonSpec (spec) where

import Data.Either (isLeft)
import IllustrationComparison
import Senbazuru.Geometry (Box (..), V2 (..), applyTransform, fitBox)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera
import Senbazuru.Render.Svg
import Test.Hspec

spec :: Spec
spec = describe "illustration-scale material comparison" $ do
  it "finds a difference at crossing subdivision edges despite identical vertices" $ do
    let a = Mesh [point 0 0 0, point 1 0 0, point 1 1 1, point 0 1 0] [(0, 1, 2), (0, 2, 3)]
        b = a {triangles = [(0, 1, 3), (1, 2, 3)]}
    ds <- right (materialDifferences a b)
    maximum (map norm ds) `shouldSatisfy` close 0.5
    projectedChange topDown ds `shouldSatisfy` close 0
    projectedChange frontOn ds `shouldSatisfy` close 0.5

  it "finds a new-vertex bulge when every coarse vertex still agrees" $ do
    let fine = flat {samples = samples flat ++ [point 0.5 0.5 0.003], triangles = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]}
    ds <- right (materialDifferences flat fine)
    maximum (map norm ds) `shouldSatisfy` close 0.003
    (600 * projectedChange frontOn ds) `shouldSatisfy` close 1.8

  it "keeps a planar sheet unchanged under a different triangulation" $ do
    ds <- right (materialDifferences flat flat {triangles = [(0, 1, 3), (1, 2, 3)]})
    maximum (map norm ds) `shouldSatisfy` close 0

  it "preserves material correspondence when triangle winding is reversed" $ do
    ds <- right (materialDifferences flat flat {triangles = [(2, 1, 0), (3, 2, 0)]})
    maximum (map norm ds) `shouldSatisfy` close 0

  it "refuses missing area, missing vertices and degenerate triangles" $ do
    materialDifferences flat flat {triangles = [(0, 1, 2)]} `shouldSatisfy` isLeft
    materialDifferences flat flat {triangles = [(0, 1, 42)]} `shouldSatisfy` isLeft
    materialDifferences flat flat {triangles = [(0, 1, 1)]} `shouldSatisfy` isLeft

  it "uses exactly 600 page units per sheet unit with the SVG y flip" $ do
    let box = Box (V2 (-0.2) (-0.5)) (V2 0.4 0.6)
        page = illustrationPage "Shared scale" box
        transform = fitBox box (pageContentBox page)
        delta = applyTransform transform (V2 0.1 0.1) ^-^ applyTransform transform (V2 0 0)
    delta `shouldBe` V2 60 (-60)

  it "shares one extent across displaced meshes rather than fitting each" $ do
    let moved = flat {samples = [p {position = position p ^+^ V3 0.01 0 0} | p <- samples flat]}
    sharedExtent topDown [flat, moved] `shouldBe` Right (Box (V2 0 0) (V2 1.01 1))

flat :: MaterialMesh
flat = Mesh [point 0 0 0, point 1 0 0, point 1 1 0, point 0 1 0] [(0, 1, 2), (0, 2, 3)]

point :: Double -> Double -> Double -> MaterialSample
point x y z = materialSample x y (V3 x y z)

close :: Double -> Double -> Bool
close expected actual = abs (expected - actual) < 1e-10

right :: (Show e) => Either e a -> IO a
right = either (\err -> expectationFailure (show err) >> fail "comparison refused") pure
