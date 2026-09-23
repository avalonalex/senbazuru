-- | The guard preserves a tolerated starting gap without attracting layers or
-- moving holds. Analytic coordinate examples need no body-patch solves.
module BodyContactDirectionSpec (spec) where

import BodyContactDirection
import ContactQuadratic
import Data.IntMap.Strict qualified as IM
import FoldContact qualified as C
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Test.Hspec

spec :: Spec
spec = describe "incremental body contact guard" $ do
  it "prevents further penetration without pretending to repair a negative gap" $ do
    let guard = contactGuard IM.empty (C.ContactRow (-1e-8) [(0, V3 1 0 0)])
    (step, report) <- right (constrainedStep 20 1 [0] [(IM.singleton 0 (V3 1 0 0), 2)] [guard])
    IM.lookup 0 step `shouldBe` Just (V3 0 0 0)
    quadraticConverged report `shouldBe` True
    snd guard `shouldBe` 0

  it "permits closing a positive gap and separates without attraction" $ do
    let guard = contactGuard IM.empty (C.ContactRow 0.25 [(0, V3 1 0 0)])
    (closing, _) <- right (constrainedStep 20 1 [0] [(IM.singleton 0 (V3 1 0 0), 2)] [guard])
    (opening, report) <- right (constrainedStep 20 1 [0] [(IM.singleton 0 (V3 1 0 0), -2)] [guard])
    IM.lookup 0 closing `shouldBe` Just (V3 (-0.25) 0 0)
    IM.lookup 0 opening `shouldBe` Just (V3 1 0 0)
    quadraticActive report `shouldBe` 0

  it "uses a second guard without losing the first contact requirement" $ do
    let x = IM.singleton 0 (V3 1 0 0)
        y = IM.singleton 0 (V3 0 1 0)
        first = contactGuard IM.empty (C.ContactRow 0 [(0, V3 1 0 0)])
        second = contactGuard IM.empty (C.ContactRow 0 [(0, V3 (-1) 1 0)])
        rows = [(x, 1), (y, 2)]
    (single, _) <- right (constrainedStep 20 1 [0] rows [first])
    (both, report) <- right (constrainedStep 20 1 [0] rows [first, second])
    -- Guarding x alone leaves y - x negative. Together the inequalities
    -- require x >= 0 and y >= x, whose minimum here is the origin.
    IM.lookup 0 single `shouldSatisfy` maybe False (\v -> norm (v ^-^ V3 0 (-1) 0) < 1e-12)
    IM.lookup 0 both `shouldSatisfy` maybe False (\v -> norm v < 1e-12)
    quadraticConverged report `shouldBe` True
    quadraticActive report `shouldBe` 2

  it "combines shared-vertex derivatives and removes exact holds" $ do
    let pins = IM.singleton 0 (V3 9 8 7)
        guard = contactGuard pins (C.ContactRow 0 [(0, V3 (-1) 0 0), (1, V3 1 0 0), (1, V3 0 2 0)])
    fst guard `shouldBe` IM.singleton 1 (V3 1 2 0)

right :: (Show e) => Either e a -> IO a
right (Right x) = pure x
right (Left e) = expectationFailure (show e) >> fail "expected Right"
