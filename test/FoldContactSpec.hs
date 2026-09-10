-- | Known packet order is tested independently of the length solver.
module FoldContactSpec (spec) where

import FoldContact
import FoldMaterial
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Test.Hspec

spec :: Spec
spec = describe "study packet order" $ do
  it "allows the sharp starting examples and coplanar contact" $ do
    violatingPairs (packetCheck Single (sharpMesh 4 Single)) `shouldBe` 0
    violatingPairs (packetCheck Double (sharpMesh 4 Double)) `shouldBe` 0
    packetCheck Single (pair 0) `shouldBe` PacketCheck 0 0 0
    packetCheck Single (pair 0.1) `shouldBe` PacketCheck 0 0 0
  it "detects reversed layers where only their projected edges cross" $ do
    -- Neither triangle contains a vertex of the other; their footprints form
    -- a six-pointed star. A vertex-only check would report no overlap.
    packetCheck Single (pair (-0.1)) `shouldBe` PacketCheck 1 0.1 0
  it "ignores triangle winding when checking spatial height" $ do
    let mesh = pair (-0.1)
    packetCheck Single (mesh {triangles = [(2, 1, 0), (3, 4, 5)]}) `shouldBe` PacketCheck 1 0.1 0
  it "reports edge-on triangles as unchecked" $ do
    let mesh = Mesh [Sample 0 0 (V3 0 0 0), Sample 0.2 0 (V3 0 1 0), Sample 0 0.2 (V3 0 0 1)] [(0, 1, 2)]
    packetCheck Single mesh `shouldBe` PacketCheck 0 0 1
  it "differentiates moving edge intersections and vertex/face contacts" $ do
    let tilted = (pair (-0.2)) {samples = map tilt (samples (pair (-0.2)))}
        contained = tilted {samples = zipWith shrink [0 :: Int ..] (samples tilted)}
        tilt sample = let V3 x y z = position sample in sample {position = V3 x y (z + 0.02 * x + 0.03 * y)}
        shrink i sample
          | i < 3 = sample
          | otherwise = let V3 x y z = position sample in sample {position = V3 (x / 5) (y / 5) z}
    mapM_ checkDerivative [tilted, contained]

-- A numerical derivative of the actual clipped overlap checks the contact
-- normal independently of the solver. The perturbed vertex moves in all three
-- directions; holding the projected intersection fixed gives a wrong answer.
checkDerivative :: Mesh -> Expectation
checkDerivative mesh = do
  let direction = V3 0.7 (-0.2) 0.3
      epsilon = 1e-6
      move amount = mesh {samples = zipWith (\i s -> if i == (3 :: Int) then s {position = position s ^+^ (amount *^ direction)} else s) [0 ..] (samples mesh)}
      energy current = sum [let gap = min 0 (contactGap row) in gap * gap | row <- fst (packetContacts Single current)]
      numerical = (energy (move epsilon) - energy (move (-epsilon))) / (2 * epsilon)
      analytical = sum [2 * min 0 (contactGap row) * dot gradient direction | row <- fst (packetContacts Single mesh), (i, gradient) <- contactGradient row, i == 3]
  abs (numerical - analytical) `shouldSatisfy` (< 1e-7)

pair :: Double -> Mesh
pair upperHeight =
  Mesh
    [ Sample 0 0 (V3 (-2) (-1) 0),
      Sample 0.2 0 (V3 2 (-1) 0),
      Sample 0 0.2 (V3 0 2 0),
      Sample 0.8 0 (V3 (-2) 1 upperHeight),
      Sample 1 0 (V3 0 (-2) upperHeight),
      Sample 1 0.2 (V3 2 1 upperHeight)
    ]
    [(0, 1, 2), (3, 4, 5)]
