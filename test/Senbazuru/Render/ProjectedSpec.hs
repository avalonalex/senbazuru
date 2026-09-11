-- | Small spatial fixtures whose visible areas can be calculated by hand.
module Senbazuru.Render.ProjectedSpec (spec) where

import Data.Either (isLeft)
import Data.Maybe (isJust)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera
import Senbazuru.Render.Projected
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "projected open-fold visibility" $ do
  it "orders sloping faces over their overlap, not by their centres" $ do
    let fr = panels [rectangle 0 10 0 1 const, rectangle 0 1 0 1 (\_ _ -> 2)]
    seen <- visible topDown fr []
    areaOf 0 seen `shouldSatisfy` near 9
    areaOf 1 seen `shouldSatisfy` near 1
  it "gets separated depths from geometry even if a stale order disagrees" $ do
    let fr = panels [rectangle 0 1 0 1 (\_ _ -> 0), rectangle 0 1 0 1 (\_ _ -> 1)]
    seen <- visible topDown fr [FaceOrder (FaceId 0) (FaceId 1) Above]
    map regionFace (formRegions seen) `shouldBe` [FaceId 1]
  it "uses declared order for touching faces and reverses it from underneath" $ do
    let fr = panels [rectangle 0 1 0 1 (\_ _ -> 0), reverse (rectangle 0 1 0 1 (\_ _ -> 0))]
        orders = [FaceOrder (FaceId 0) (FaceId 1) Above]
    above <- visible topDown fr orders
    below <- visible bottomUp fr orders
    map (\r -> (regionFace r, regionTopSide r)) (formRegions above) `shouldBe` [(FaceId 1, False)]
    map (\r -> (regionFace r, regionTopSide r)) (formRegions below) `shouldBe` [(FaceId 0, False)]
  it "declines unresolved touching faces and intersecting panels" $ do
    let flat = rectangle 0 1 0 1 (\_ _ -> 0)
    projectedForm topDown (panels [flat, flat]) [] `shouldBe` Right Nothing
    projectedForm topDown (panels [flat, rectangle 0 1 0 1 (\x _ -> x - 0.5)]) [] `shouldBe` Right Nothing
  it "refuses contradictory pair declarations and invalid indices" $ do
    let flat = rectangle 0 1 0 1 (\_ _ -> 0)
        fr = panels [flat, flat]
    projectedForm topDown fr [FaceOrder (FaceId 0) (FaceId 1) Above, FaceOrder (FaceId 0) (FaceId 1) Below] `shouldSatisfy` isLeft
    projectedForm topDown fr [FaceOrder (FaceId 0) (FaceId 2) Above] `shouldSatisfy` isLeft
  it "declines nonplanar faces and free edge-on paper" $ do
    projectedForm topDown (panels [[[0, 0, 0], [1, 0, 0], [1, 1, 1], [0, 1, 0]]]) [] `shouldBe` Right Nothing
    projectedForm topDown (panels [[[0, 0, 0], [1, 0, 0], [0, 0, 1]]]) [] `shouldBe` Right Nothing
  it "refuses a three-face cycle that would remove a shared patch from every face" $ do
    let flat = rectangle 0 1 0 1 (\_ _ -> 0)
        orders = [FaceOrder (FaceId 0) (FaceId 1) Above, FaceOrder (FaceId 1) (FaceId 2) Above, FaceOrder (FaceId 2) (FaceId 0) Above]
    projectedForm topDown (panels [flat, flat, flat]) orders `shouldBe` Left (ImpossibleStacking (FaceId 0))
  it "clips a buried crease to the exposed ends" $ do
    let fr = panels [rectangle 0 0.5 0 1 (\_ _ -> 0), rectangle 0.5 1 0 1 (\_ _ -> 0), rectangle 0.25 0.75 0.25 0.75 (\_ _ -> 1)]
    seen <- visible topDown fr []
    let centreEdges = [(a, b) | edge <- formEdges seen, let a@(V3 x _ _) = visibleFrom edge, let b@(V3 u _ _) = visibleTo edge, abs (x - 0.5) < 1e-9, abs (u - 0.5) < 1e-9]
    length centreEdges `shouldBe` 2
    sum [abs (v3y b - v3y a) | (a, b) <- centreEdges] `shouldSatisfy` near 0.5
  it "preserves the visible area for arbitrary separated inset panels" $
    forAll (choose (0.1, 0.4)) $ \inset ->
      forAll (choose (0.1, 10)) $ \height ->
        let fr = panels [rectangle 0 1 0 1 (\_ _ -> 0), rectangle inset (1 - inset) inset (1 - inset) (\_ _ -> height)]
         in case projectedForm topDown fr [] of
              Right (Just seen) -> near 1 (areaOf 0 seen + areaOf 1 seen) && near ((1 - 2 * inset) * (1 - 2 * inset)) (areaOf 1 seen)
              _ -> False
  it "works through an oblique viewing basis" $ do
    let fr = panels [rectangle 0 1 0 1 (\_ _ -> 0), rectangle 0 1 0 1 (\_ _ -> 1)]
    projectedForm isometric fr [] `shouldSatisfy` either (const False) isJust

rectangle :: Double -> Double -> Double -> Double -> (Double -> Double -> Double) -> [[Double]]
rectangle x0 x1 y0 y1 z = [[x, y, z x y] | (x, y) <- [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]]

panels :: [[[Double]]] -> Frame
panels rings =
  emptyFrame
    { frameClasses = ["foldedForm"],
      verticesCoords = concat rings,
      facesVertices = ids,
      edgesVertices = concat [zip vs (drop 1 vs ++ take 1 vs) | vs <- ids],
      edgesAssignment = replicate (sum (map length rings)) Border
    }
  where
    ids = [map VertexId [offset .. offset + length ring - 1] | (offset, ring) <- zip (scanl (+) 0 (map length rings)) rings]

visible :: Basis -> Frame -> [FaceOrder] -> IO VisibleForm
visible basis fr orders = case projectedForm basis fr orders of
  Right (Just seen) -> pure seen
  result -> expectationFailure (show result) >> fail "expected visible paper"

areaOf :: Int -> VisibleForm -> Double
areaOf i seen = sum [abs (signedArea [V2 x y | V3 x y _ <- piece]) | r <- formRegions seen, regionFace r == FaceId i, piece <- regionPieces r]

near :: Double -> Double -> Bool
near expected actual = abs (expected - actual) < 1e-8
