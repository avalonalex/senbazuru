-- | Exact prescribed profiles and a moving edge intersection check the new
-- current-triangle audit without sharing its overlap construction.
module CreasePairContactSpec (spec) where

import ClosedCrease
import Control.Monad (forM_)
import CreaseCorrection
import CreasePairContact
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "contact between two current crease panels" $ do
  it "agrees with prescribed rational profiles at both resolutions" $
    forM_ [(n, c) | n <- [1, 2], c <- [FlatTouching, BentTouching, Open, OpenSliver, Crossed, CrossedSliver, WrongSide]] $ \(n, shape) -> do
      fixture <- right (closedCrease n shape)
      audit <- right (auditPairContact (closedOwners fixture) (closedMesh fixture))
      let ideal = minimum (map snd (profileGaps fixture))
      abs (fromRational (pairMinimum audit - ideal) :: Double) `shouldSatisfy` (< 1e-15)
      forM_ (pairWitnesses audit) $ \w -> sum (pairWeights w) `shouldBe` 0

  it "matches the fixed-lower audit but observes a newly moved lower interior" $ do
    old <- right (creaseCorrection 1 ReferenceStart)
    let mesh = correctionSeed old
        owners = closedOwners (correctionReference old)
        shift dz = mesh {samples = [if materialU p == 0.25 && materialV p == 0 then let V3 x y z = position p in p {position = V3 x y (z + dz)} else p | p <- samples mesh]}
    fixed <- right (auditLowerGap old mesh)
    pair <- right (auditPairContact owners mesh)
    pairMinimum pair `shouldBe` minimumGap fixed
    raised <- right (auditPairContact owners (shift 0.001))
    pairMinimum raised `shouldSatisfy` (< -(1 / 10000))
    lowered <- right (auditPairContact owners (shift (-0.001)))
    pairMinimum lowered `shouldBe` 0
    pairMaximum lowered `shouldSatisfy` (> 1 / 10000)
    auditLowerGap old (shift 0.001) `shouldSatisfy` isLeft

  it "differentiates an overlap corner moving with a lower edge" $ do
    original <- edgeWitness (pairMesh 0)
    let epsilon = 1e-6
    positive <- edgeWitness (pairMesh epsilon)
    negative <- edgeWitness (pairMesh (-epsilon))
    let measured = fromRational (pairGap positive - pairGap negative) / (2 * epsilon)
        (nx, _, _) = pairNormal original
        predicted = fromRational (IM.findWithDefault 0 1 (pairWeights original) * nx)
    abs (measured - predicted) `shouldSatisfy` (< 1e-8)
    pairLocation original `shouldBe` (1 / 2, 3 / 2)

  it "refuses lost owners, vertices, facing directions and nonfinite coordinates" $ do
    f <- right (closedCrease 1 BentTouching)
    let m = closedMesh f
        change q = m {samples = [p {position = q} | p <- samples m]}
    auditPairContact [] m `shouldSatisfy` isLeft
    auditPairContact (closedOwners f) m {triangles = (0, 1, 999) : drop 1 (triangles m)} `shouldSatisfy` isLeft
    auditPairContact (closedOwners f) (change (V3 0 0 0)) `shouldSatisfy` isLeft
    auditPairContact (closedOwners f) (change (V3 0 0 (0 / 0))) `shouldSatisfy` isLeft

pairMesh :: Double -> MaterialMesh
pairMesh offset = Mesh [materialSample (fromIntegral i) 0 p | (i, p) <- zip [0 :: Int ..] [V3 0 0 0, V3 (2 + offset) 0 0, V3 0 2 0, V3 0.5 0.5 0.25, V3 0.5 1.75 0.5, V3 1.75 0.5 0.75]] [(0, 1, 2), (3, 4, 5)]

edgeWitness :: MaterialMesh -> IO PairWitness
edgeWitness mesh = do
  audit <- right (auditPairContact [FaceId 0, FaceId 1] mesh)
  case [w | w <- pairWitnesses audit, IM.keys (pairWeights w) == [1, 2, 3, 4]] of
    [w] -> pure w
    ws -> fail ("expected one moving edge intersection, got " ++ show ws)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
