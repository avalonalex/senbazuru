-- | The paper screen's measures on small shapes whose answers can be worked
-- out by hand. Each example names the mistake it would catch.
module PaperScreenSpec (spec) where

import Data.Either (isLeft, isRight)
import PaperScreen
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Test.Hspec

spec :: Spec
spec = describe "the paper screen" $ do
  it "halves the excess of the pair furthest apart" $ do
    -- Material distance 1, placed 1.2: the pair can share 0.2, so one of the
    -- two points moves at least 0.1. Dropping the halving gives 0.2.
    noStretchFloor 0 distance3 [(V2 0 0, V3 0 0 0), (V2 1 0, V3 1.2 0 0)]
      `shouldBe` Just (FloorPair ((1.2 - 1) / 2) (0, 1))

  it "lets the declared strain absorb its share of the excess" $ do
    -- At 1% the pair may be 1.01 apart, so only 0.19 remains to share.
    fmap floorDistance (noStretchFloor 0.01 distance3 [(V2 0 0, V3 0 0 0), (V2 1 0, V3 1.2 0 0)])
      `shouldSatisfy` maybe False (\d -> abs (d - (1.2 - 1.01) / 2) < 1e-12)

  it "reports how much room is left when no pair is too far apart" $
    -- A negative floor: every pair is closer than the flat sheet allows.
    fmap floorDistance (noStretchFloor 0 distance3 [(V2 0 0, V3 0 0 0), (V2 1 0, V3 0.5 0 0)])
      `shouldBe` Just (-0.25)

  it "accepts a square sheet and refuses one with a notch" $ do
    sheetIsConvex square `shouldSatisfy` isRight
    -- An L: its hull is larger than the paper, so a chord can leave it.
    sheetIsConvex ell `shouldSatisfy` isLeft

  it "takes the smaller reach, so a card resting on a table is barely in it" $ do
    -- The table is huge and flat; the card stands on it with one corner
    -- 0.001 below the top. Taking the larger reach would give the table's
    -- extent past the card's plane, 5.
    let table = (V3 (-5) (-5) 0, V3 5 (-5) 0, V3 0 5 0)
        card = (V3 (-1) 0 (-0.001), V3 1 0 1, V3 (-1) 0 1)
    fmap (\d -> abs (d - 0.001) < 1e-12) (reachThrough card table) `shouldBe` Just True
    fmap (\d -> abs (d - 0.001) < 1e-12) (reachThrough table card) `shouldBe` Just True

  it "gives no reach for a pair on one side of each other's plane" $
    reachThrough (V3 0 0 1, V3 1 0 1, V3 0 1 1) (V3 0 0 0, V3 1 0 0, V3 0 1 0) `shouldBe` Just 0

  it "sums length times angle over joins past the threshold, either way bent" $ do
    -- 0.1 x 50 + 0.1 x 60 = 11 over two joins. Counting every join gives 3;
    -- dropping the absolute value loses the join bent -60.
    let turning = falseCreaseTurning 45 [(0.1, 50), (0.2, 30), (0.1, -60)]
    turningJoins turning `shouldBe` 2
    abs (turningTotal turning - 11) `shouldSatisfy` (< 1e-12)

  it "splits centre creases into midlines and diagonals and takes each median" $ do
    let centre = V2 0.5 0.5
        segments =
          [ (V2 0.5 0.5, V2 0.5 0.75, 170),
            (V2 0.5 0.25, V2 0.5 0.5, -10),
            (V2 0.25 0.5, V2 0.5 0.5, 90),
            (V2 0.5 0.5, V2 0.75 0.75, 20),
            -- Not through the centre: ignored.
            (V2 0.1 0.2, V2 0.2 0.1, 180)
          ]
    centreFolds centre segments `shouldBe` (Just 90, Just 20)

distance3 :: V3 -> V3 -> Double
distance3 p q = norm (p ^-^ q)

sheet :: [(Double, Double)] -> [(Int, Int, Int)] -> MaterialMesh
sheet points = Mesh [Sample (V2 u v) (V3 u v 0) | (u, v) <- points]

square :: MaterialMesh
square = sheet [(0, 0), (1, 0), (1, 1), (0, 1)] [(0, 1, 2), (0, 2, 3)]

ell :: MaterialMesh
ell = sheet [(0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)] [(0, 1, 2), (0, 2, 3), (0, 3, 5), (3, 4, 5)]
