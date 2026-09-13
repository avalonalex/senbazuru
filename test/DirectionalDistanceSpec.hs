module DirectionalDistanceSpec (spec) where

import Control.Monad (forM_)
import Data.IntMap.Strict qualified as IM
import DirectionalDistance
import FoldContact (ContactRow (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (Mesh (..), Sample (..))
import SurfaceContact
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (choose, forAll)

spec :: Spec
spec = describe "continuous directional contact distance" $ do
  prop "certifies positive distances with a separating plane for every triangle vertex" $
    forAll ((,) <$> triangleAt 0 <*> triangleAt 3) $ \(a, b) ->
      let DistanceSample distance gradient = orderDistance axis a b
          normal = foldr (^+^) (V3 0 0 0) [g | (i, g) <- gradient, i >= 3]
          vertices (x, y, z) = map snd [x, y, z]
          support = minimum [dot normal (q ^-^ p) | p <- vertices a, q <- vertices b]
       in -- Every difference between points on the triangles is a weighted
          -- average of these nine differences. A supporting plane at exactly
          -- the reported distance certifies no other point can be closer.
          distance <= 1e-8 || (abs (norm normal - 1) < 1e-8 && dot axis normal >= -1e-8 && abs (support - distance) < 1e-8)
  it "measures vertical clearance or approach from the forbidden side" $ do
    forM_ [0.01, 0.1, 1] $ \gap -> do
      near gap (distanceValue (orderDistance axis lower (upper 0 gap)))
      near gap (distanceValue (orderDistance axis lower (upper (1 + gap) (-0.05))))
      near 0 (distanceValue (orderDistance axis lower (upper (1 - gap) (-0.05))))

  it "stays continuous as a positive-gap shadow enters and leaves overlap" $ do
    forM_ [-1e-3, -1e-6, 0, 1e-6, 1e-3] $ \offset ->
      near (sqrt (0.05 * 0.05 + max 0 offset ** 2)) (distanceValue (orderDistance axis lower (upper (1 + offset) 0.05)))

  it "distributes the derivative to both triangles on a unique closest feature" $ do
    let a = ((0, V3 0 0 0), (1, V3 1 0.1 0.1), (2, V3 0.2 0.8 (-0.1)))
        b = ((3, V3 1.4 0.3 (-0.1)), (4, V3 1.6 0.4 0.2), (5, V3 1.5 0.9 0.3))
    checkGradient a b
    checkGradient a (mapTriangle (\p -> p ^+^ V3 0 0 0.9) b)

  it "finds an interior edge/edge witness and distributes its force" $ do
    let a = ((0, V3 (-1) 0 0), (1, V3 1 0 0), (2, V3 0 (-1) (-1)))
        b = ((3, V3 0 (-1) 0.2), (4, V3 0 1 0.2), (5, V3 0 0 1))
        DistanceSample distance gradient = orderDistance axis a b
        weights = IM.fromList gradient
    near 0.2 distance
    forM_ [0, 1] $ \i -> near (-0.5) (dot axis (IM.findWithDefault (V3 0 0 0) i weights))
    forM_ [3, 4] $ \i -> near 0.5 (dot axis (IM.findWithDefault (V3 0 0 0) i weights))
    checkGradient a b

  it "handles upright triangles and reports forbidden overlap or intersection" $ do
    let a = ((0, V3 0 0 0), (1, V3 1 0 0), (2, V3 0 0 1))
        b = ((3, V3 0.2 0.1 (-2)), (4, V3 0.8 0.1 (-2)), (5, V3 0.2 0.1 (-1)))
        crossing = ((3, V3 0.25 0.25 (-1)), (4, V3 0.25 0.25 1), (5, V3 0.25 0.5 1))
    near 0.1 (distanceValue (orderDistance axis a b))
    near 0 (distanceValue (orderDistance axis a (mapTriangle (\p -> p ^-^ V3 0 0.1 0) b)))
    near 0 (distanceValue (orderDistance axis lower crossing))
    forM_ (permutations crossing) $ \triangle ->
      forM_ (permutations lower) $ \base -> near 0 (distanceValue (orderDistance axis base triangle))

  it "preserves distance under rigid motion and exchanged order with reversed axis" $ do
    let b = upper 1.02 (-0.05)
        transform (V3 x y z) = V3 (z + 3) (x - 2) (y + 4)
        d = distanceValue (orderDistance axis lower b)
    near d (distanceValue (orderDistance (V3 1 0 0) (mapTriangle transform lower) (mapTriangle transform b)))
    near d (distanceValue (orderDistance (V3 0 0 (-1)) b lower))

  it "activates a finite force before forbidden projected overlap appears" $ do
    let mesh = pairMesh (upper 1.0001 (-0.05))
    model <- right (prepareTriangleContact 1e-6 axis [(0, 1)] mesh)
    orderedContacts model mesh `shouldBe` Right []
    rows <- right (orderedBarrierContacts 0.001 model mesh)
    map contactGap rows `shouldSatisfy` all (< 0)
    concatMap contactGradient rows `shouldSatisfy` any ((> 0) . norm . snd)
    orderedBarrierContacts 0 model mesh `shouldBe` Left InvalidBarrierDistance
    orderedBarrierContacts (0 / 0) model mesh `shouldBe` Left InvalidBarrierDistance
    orderedBarrierContacts (1 / 0) model mesh `shouldBe` Left InvalidBarrierDistance
    orderedBarrierContacts 0.001 model (pairMesh (upper 0.9999 (-0.05))) `shouldBe` Left (OutsideBarrierDomain 0 1)

  it "has zero energy outside activation and vanishing energy at its boundary" $ do
    let mesh = pairMesh (upper 1.1 (-0.05))
    model <- right (prepareTriangleContact 1e-6 axis [(0, 1)] mesh)
    orderedBarrierContacts 0.001 model mesh `shouldBe` Right [ContactRow 0 []]
    rows <- right (orderedBarrierContacts 0.001 model (pairMesh (upper (1 + 1e-6 + 0.001 - 1e-10) (-0.05))))
    sum [contactGap row ** 2 | row <- rows] `shouldSatisfy` (< 1e-20)

  it "differentiates the barrier residual inside its activation range" $ do
    let mesh = pairMesh (upper 1.0003 (-0.05))
        moved amount = pairMesh (upper (1.0003 + amount) (-0.05))
        epsilon = 1e-8
    model <- right (prepareTriangleContact 1e-6 axis [(0, 1)] mesh)
    rows <- right (orderedBarrierContacts 0.001 model mesh)
    plus <- right (orderedBarrierContacts 0.001 model (moved epsilon))
    minus <- right (orderedBarrierContacts 0.001 model (moved (-epsilon)))
    let actual = sum [dot (V3 1 0 0) g | row <- rows, (i, g) <- contactGradient row, i >= 3]
        numerical = (sum (map contactGap plus) - sum (map contactGap minus)) / (2 * epsilon)
    abs (actual - numerical) `shouldSatisfy` (< 1e-7)
  where
    triangleAt i = do
      a <- point
      b <- point
      c <- point
      pure ((i, a), (i + 1, b), (i + 2, c))
    point = V3 <$> choose (-2, 2) <*> choose (-2, 2) <*> choose (-2, 2)

checkGradient :: TrianglePoints -> TrianglePoints -> IO ()
checkGradient a b = do
  let DistanceSample _ gradient = orderDistance axis a b
      derivatives = IM.fromList gradient
      epsilon = 1e-6
      moved i direction = mapIds (\j p -> if i == j then p ^+^ (epsilon *^ direction) else p)
  forM_ [0 .. 5] $ \i -> forM_ [V3 1 0 0, V3 0 1 0, V3 0 0 1] $ \direction -> do
    let plus = distanceValue (orderDistance axis (moved i direction a) (moved i direction b))
        minus = distanceValue (orderDistance axis (moved i ((-1) *^ direction) a) (moved i ((-1) *^ direction) b))
        actual = dot direction (IM.findWithDefault (V3 0 0 0) i derivatives)
    abs ((plus - minus) / (2 * epsilon) - actual) `shouldSatisfy` (< 1e-7)
  norm (foldr ((^+^) . snd) (V3 0 0 0) gradient) `shouldSatisfy` (< 1e-12)

axis :: V3
axis = V3 0 0 1

lower :: TrianglePoints
lower = ((0, V3 0 0 0), (1, V3 1 0 0), (2, V3 0 1 0))

upper :: Double -> Double -> TrianglePoints
upper x z = ((3, V3 x 0 z), (4, V3 (x + 1) 0 z), (5, V3 x 1 z))

mapIds :: (Int -> V3 -> V3) -> TrianglePoints -> TrianglePoints
mapIds f (a, b, c) = (g a, g b, g c) where g (i, p) = (i, f i p)

mapTriangle :: (V3 -> V3) -> TrianglePoints -> TrianglePoints
mapTriangle f = mapIds (const f)

permutations :: TrianglePoints -> [TrianglePoints]
permutations (a, b, c) = [(a, b, c), (b, c, a), (c, a, b), (a, c, b), (b, a, c), (c, b, a)]

pairMesh :: TrianglePoints -> Mesh V2
pairMesh (a, b, c) = Mesh [Sample (V2 (fromIntegral i) (fromIntegral (i * i))) p | (i, p) <- [x, y, z, a, b, c]] [(0, 1, 2), (3, 4, 5)] where (x, y, z) = lower

near :: Double -> Double -> Expectation
near expected actual = abs (expected - actual) `shouldSatisfy` (< 1e-10)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
