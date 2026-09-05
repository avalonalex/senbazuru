-- |
-- Properties of the 3D primitives.
--
-- 'polygonNormal' gets the attention here, because everything layer ordering
-- decides rests on its sign, and because the reason it is Newell's method
-- rather than a cross product of two edges is a claim about polygons that are
-- not quite flat — which is worth pinning rather than asserting in a comment.
module Senbazuru.Geometry.V3Spec (spec) where

import Senbazuru.Geometry.V3
import Senbazuru.Geometry.VectorSpace
import Test.Hspec
import Test.QuickCheck

genCoord :: Gen Double
genCoord = choose (-50, 50)

genPoint :: Gen V3
genPoint = V3 <$> genCoord <*> genCoord <*> genCoord

nearV3 :: V3 -> V3 -> Bool
nearV3 a b = norm (a ^-^ b) < 1e-9 * max 1 (norm a)

-- | A quadrilateral whose fourth corner is lifted out of the plane of the other
-- three, so that no two of its triangulations agree.
skewQuad :: Double -> [V3]
skewQuad lift = [V3 0 0 0, V3 1 0 0, V3 1 1 lift, V3 0 1 0]

-- | The naive alternative: the cross product of the first two edges.
twoEdgeNormal :: [V3] -> V3
twoEdgeNormal (a : b : c : _) = cross (b ^-^ a) (c ^-^ a)
twoEdgeNormal _ = V3 0 0 0

rotations :: [a] -> [[a]]
rotations xs = [drop i xs <> take i xs | i <- [0 .. length xs - 1]]

spec :: Spec
spec = describe "polygonNormal" $ do
  it "points along +z for a counterclockwise polygon in the xy plane" $
    polygonNormal [V3 0 0 0, V3 1 0 0, V3 1 1 0, V3 0 1 0]
      `shouldSatisfy` nearV3 (V3 0 0 2)

  it "negates when the corners are listed the other way round" $
    -- The whole reason the function exists: it is a question about the order,
    -- and faceOrders' signs are read against the answer.
    forAll (vectorOf 5 genPoint) $ \corners ->
      nearV3 (polygonNormal (reverse corners)) ((-1) *^ polygonNormal corners)

  it "agrees with the cross product on a triangle, which is always flat" $
    -- Newell's reduces to the naive version exactly when the naive version is
    -- right, which is what makes it a safe default rather than a different
    -- answer.
    forAll ((,,) <$> genPoint <*> genPoint <*> genPoint) $ \(a, b, c) ->
      nearV3 (polygonNormal [a, b, c]) (twoEdgeNormal [a, b, c])

  it "has twice the area as its length" $
    forAll ((,) <$> choose (0.1, 20) <*> choose (0.1, 20)) $ \(w, h) ->
      abs (norm (polygonNormal [V3 0 0 0, V3 w 0 0, V3 w h 0, V3 0 h 0]) - 2 * w * h) < 1e-9

  it "gives the same answer wherever the ring starts, even when it is not flat" $ do
    -- This is the claim the module header makes and the reason for choosing
    -- Newell's: it averages over every edge, so it cannot depend on which two
    -- edges you happen to pick first.
    let normals = map polygonNormal (rotations (skewQuad 0.5))
    normals `shouldSatisfy` all (nearV3 (head normals))

  it "unlike the cross product of the first two edges, which does" $ do
    -- The comparison that gives the test above its teeth: on the same skew quad
    -- the naive answer changes with the starting corner.
    let naive = map twoEdgeNormal (rotations (skewQuad 0.5))
    naive `shouldNotSatisfy` all (nearV3 (head naive))

  it "still agrees with the naive answer when the quad is genuinely flat" $ do
    let flat = skewQuad 0
    polygonNormal flat `shouldSatisfy` nearV3 ((2 :: Double) *^ twoEdgeNormal flat)
