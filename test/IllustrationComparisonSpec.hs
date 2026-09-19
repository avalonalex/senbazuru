-- | Refinement can change a surface between shared vertices. Exercise that
-- failure directly, including crossed material diagonals and a hidden bump.
module IllustrationComparisonSpec (spec) where

import Data.Either (isLeft)
import IllustrationComparison
import IllustrationDistance
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

  it "measures real subpixel exposure without an alpha threshold" $ do
    let (area, spanPixels) = exposureMeasures [rectangle 0 0 10 0.1]
    area `shouldSatisfy` close 1
    spanPixels `shouldSatisfy` close 0.1

  it "does not double-count a shared vertical subdivision edge" $ do
    exposureMeasures [rectangle 0 0 1 2, rectangle 1 0 2 2] `shouldBe` (4, 2)
    exposureMeasures [[V2 0 0, V2 2 0, V2 2 2], [V2 0 0, V2 2 2, V2 0 2]] `shouldBe` (4, 2)

  it "counts separated intervals without counting the gap between them" $ do
    exposureMeasures [rectangle 0 0 1 1, rectangle 0 5 1 6] `shouldBe` (2, 2)

  it "finds the span at a corner and handles winding and empty exposure" $ do
    let triangle = [V2 0 0, V2 2 0, V2 1 3]
    exposureMeasures [reverse triangle] `shouldBe` (3, 3)
    exposureMeasures [] `shouldBe` (0, 0)

  it "bounds a thin strip translation without thresholding its area" $ do
    BoundedDistance d <- right (regionDistance 0.001 Nothing 100 [rectangle 0 0 10 0.000001] [rectangle 0 3 10 3.000001])
    distanceLower d `shouldSatisfy` close 3
    distanceUpper d `shouldSatisfy` close 3
    norm (witnessFrom d ^-^ witnessTo d) `shouldSatisfy` close 3

  it "covers the filled interior instead of comparing only source corners" $ do
    let surround = [rectangle 0 0 4 1, rectangle 0 3 4 4, rectangle 0 1 1 3, rectangle 3 1 4 3]
    BoundedDistance d <- right (regionDistance 0.01 Nothing 3000 [rectangle 0 0 4 4] surround)
    distanceLower d `shouldSatisfy` (>= 0.99)
    distanceUpper d `shouldSatisfy` (<= 1.01)
    distanceLower d `shouldSatisfy` (<= 1)
    distanceUpper d `shouldSatisfy` (>= 1)

  it "preserves an honest upper bound when subdivision is exhausted" $ do
    let ends = [rectangle 0 0 1 1, rectangle 3 0 4 1]
    BoundedDistance d <- right (regionDistance 0.001 Nothing 0 [rectangle 0 0 4 1] ends)
    distanceLower d `shouldSatisfy` (<= 1)
    distanceUpper d `shouldSatisfy` (>= 1)
    (distanceUpper d - distanceLower d) `shouldSatisfy` (> 0.001)
    distanceSplits d `shouldBe` 0

  it "compares a split region as a union and handles repeated corners and winding" $ do
    let square = rectangle 0 0 2 2
        halves = [rectangle 0 0 1 2, reverse (rectangle 1 0 2 2)]
    BoundedDistance d <- right (regionDistance 0.01 Nothing 3000 [square] halves)
    distanceLower d `shouldSatisfy` close 0
    distanceUpper d `shouldSatisfy` (<= 0.01)
    BoundedDistance same <- right (regionDistance 0.01 Nothing 100 [V2 0 0 : square] [reverse square])
    distanceUpper same `shouldSatisfy` close 0

  it "distinguishes no exposure from a lost layer and refuses invalid controls" $ do
    regionDistance 0.01 Nothing 10 [] [] `shouldBe` Right EmptySource
    regionDistance 0.01 Nothing 10 [] [rectangle 0 0 1 1] `shouldBe` Right EmptySource
    regionDistance 0.01 Nothing 10 [rectangle 0 0 1 1] [] `shouldBe` Right MissingTarget
    regionDistance 0 Nothing 10 [] [] `shouldSatisfy` isLeft
    regionDistance 0.01 Nothing (-1) [] [] `shouldSatisfy` isLeft
    regionDistance 0.01 Nothing 10 [[V2 (0 / 0) 0]] [] `shouldSatisfy` isLeft
    regionDistance 0.01 Nothing 10 [[V2 0 0, V2 2 0, V2 1 0.5, V2 2 2, V2 0 2]] [] `shouldSatisfy` isLeft

  it "stops on a bounded budget decision without claiming a precise maximum" $ do
    let ends = [rectangle 0 0 1 1, rectangle 3 0 4 1]
    BoundedDistance outside <- right (regionDistance 0.001 (Just 0.2) 100 [rectangle 0 0 4 1] ends)
    distanceLower outside `shouldSatisfy` (> 0.2)
    distanceSplits outside `shouldBe` 0
    BoundedDistance inside <- right (regionDistance 0.001 (Just 2) 100 [rectangle 0 0 4 1] ends)
    distanceUpper inside `shouldSatisfy` (<= 2)
    distanceLower inside `shouldSatisfy` (<= 1)
    distanceUpper inside `shouldSatisfy` (>= 1)
    regionDistance 0.01 (Just (-1)) 10 [] [] `shouldSatisfy` isLeft

  it "detects a distant tiny component even when the main region agrees" $ do
    let base = rectangle 0 0 1 1
    BoundedDistance d <- right (regionDistance 0.001 Nothing 100 [base, rectangle 10 0 11 0.000001] [base])
    distanceLower d `shouldSatisfy` close 10
    distanceUpper d `shouldSatisfy` close 10

  it "bounds known area past a straight two-pixel neighbourhood" $ do
    a <- right (areaBeyondBudget 2 0.001 20000 [rectangle 0 0 4 1] [rectangle 0 0 1 1])
    areaTotal a `shouldSatisfy` close 4
    bracketsArea 1 a
    areaUnresolved a `shouldSatisfy` (<= 0.001)

  it "measures area in an interior hole and across a disconnected target" $ do
    let surround = [rectangle 0 0 4 1, rectangle 0 3 4 4, rectangle 0 1 1 3, rectangle 3 1 4 3]
    a <- right (areaBeyondBudget 0.5 0.002 50000 [rectangle 0 0 4 4] surround)
    bracketsArea 1 a
    areaUnresolved a `shouldSatisfy` (<= 0.002)
    b <- right (areaBeyondBudget 0.5 0.002 50000 [rectangle 0 0 4 1] [rectangle 0 0 1 1, rectangle 3 0 4 1])
    bracketsArea 1 b
    areaUnresolved b `shouldSatisfy` (<= 0.002)

  it "bounds area around a round target corner, including the circular boundary" $ do
    a <- right (areaBeyondBudget 0.5 0.001 50000 [rectangle 0 0 1 1] [rectangle (-1) (-1) 0 0])
    bracketsArea (1 - pi / 16) a
    areaUnresolved a `shouldSatisfy` (<= 0.001)

  it "keeps microscopic distant exposure instead of thresholding it away" $ do
    let base = rectangle 0 0 1 1
    a <- right (areaBeyondBudget 2 1e-9 100 [base, rectangle 10 0 11 1e-6] [base])
    areaOutside a `shouldSatisfy` close 1e-6
    areaUnresolved a `shouldSatisfy` close 0

  it "keeps area invariant under winding, subdivision and overlapping targets" $ do
    let source = rectangle 0 0 4 1
        split = [[V2 0 0, V2 4 0, V2 4 1], [V2 0 0, V2 4 1, V2 0 1]]
        target = rectangle 0 0 1 1
    mapM_
      ( \pieces -> do
          a <- right (areaBeyondBudget 2 0.002 20000 pieces [target, reverse target])
          bracketsArea 1 a
          areaTotal a `shouldSatisfy` close 4
          areaUnresolved a `shouldSatisfy` (<= 0.002)
      )
      [split, [reverse source], [V2 0 0 : source]]

  it "reports unresolved area at a work cap and handles empty or lost exposure" $ do
    a <- right (areaBeyondBudget 2 0.001 0 [rectangle 0 0 4 1] [rectangle 0 0 1 1])
    bracketsArea 1 a
    areaUnresolved a `shouldSatisfy` (> 0.001)
    areaSplits a `shouldBe` 0
    areaBeyondBudget 2 0.001 0 [] [] `shouldBe` Right (AreaBounds 0 0 0 0)
    areaBeyondBudget 2 0.001 0 [rectangle 0 0 4 1] [] `shouldBe` Right (AreaBounds 4 4 0 0)
    a0 <- right (areaBeyondBudget 0 0.001 20 [rectangle 0 0 4 1] [rectangle 0 0 4 1])
    a0 `shouldBe` AreaBounds 4 0 0 0
    areaBeyondBudget (-1) 0.001 20 [] [] `shouldSatisfy` isLeft
    areaBeyondBudget 2 0 20 [] [] `shouldSatisfy` isLeft
    areaBeyondBudget 2 0.001 (-1) [] [] `shouldSatisfy` isLeft
    areaBeyondBudget 2 0.001 20 [[V2 (0 / 0) 0]] [] `shouldSatisfy` isLeft

bracketsArea :: Double -> AreaBounds -> Expectation
bracketsArea expected a = do
  areaOutside a `shouldSatisfy` (<= expected + 1e-10)
  (areaOutside a + areaUnresolved a) `shouldSatisfy` (>= expected - 1e-10)

rectangle :: Double -> Double -> Double -> Double -> [V2]
rectangle x0 y0 x1 y1 = [V2 x0 y0, V2 x1 y0, V2 x1 y1, V2 x0 y1]

flat :: MaterialMesh
flat = Mesh [point 0 0 0, point 1 0 0, point 1 1 0, point 0 1 0] [(0, 1, 2), (0, 2, 3)]

point :: Double -> Double -> Double -> MaterialSample
point x y z = materialSample x y (V3 x y z)

close :: Double -> Double -> Bool
close expected actual = abs (expected - actual) < 1e-10

right :: (Show e) => Either e a -> IO a
right = either (\err -> expectationFailure (show err) >> fail "comparison refused") pure
