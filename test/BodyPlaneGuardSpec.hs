-- | Small coordinate fixtures check the moving-plane derivative independently
-- of a body solve. In particular, an outside vertex still responds to tilting
-- the triangle: its plane must not accidentally be treated as fixed.
module BodyPlaneGuardSpec (spec) where

import BodyPlaneGuard
import ContactQuadratic
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "local vertex-to-plane guard" $ do
  it "differentiates the outside vertex and every point of a horizontal plane" $ do
    m <- right (measurePlane horizontal 3 0)
    planeDistance m `shouldBe` (-0.01)
    planeGradient m `shouldBe` IM.fromList [(0, V3 0 0 1.25), (1, V3 0 0 (-2)), (2, V3 0 0 (-0.25)), (3, V3 0 0 1)]

  it "matches finite differences for a tilted, changing triangle" $ do
    m <- right (measurePlane tilted 3 0)
    mapM_
      ( \(i, g) ->
          mapM_
            ( \axis -> do
                plus <- right (measurePlane (move i (1e-6 *^ axis) tilted) 3 0)
                minus <- right (measurePlane (move i ((-1e-6) *^ axis) tilted) 3 0)
                abs ((planeDistance plus - planeDistance minus) / 2e-6 - dot g axis) `shouldSatisfy` (< 1e-8)
            )
            axes
      )
      (IM.toList (planeGradient m))

  it "has no response to rigid translation or rotation of the whole fixture" $ do
    m <- right (measurePlane tilted 3 0)
    norm (sumV (IM.elems (planeGradient m))) `shouldSatisfy` (< 1e-12)
    mapM_ (\axis -> abs (sum [dot g (cross axis (position p)) | (i, p) <- zip [0 ..] (samples tilted), Just g <- [IM.lookup i (planeGradient m)]]) `shouldSatisfy` (< 1e-12)) axes

  it "reverses distance and derivatives when the triangle winding reverses" $ do
    forward <- right (measurePlane tilted 3 0)
    backward <- right (measurePlane tilted {triangles = [(0, 2, 1)]} 3 0)
    abs (planeDistance forward + planeDistance backward) `shouldSatisfy` (< 1e-12)
    mapM_ (\v -> norm v `shouldSatisfy` (< 1e-12)) (IM.elems (IM.unionWith (^+^) (planeGradient forward) (planeGradient backward)))

  it "removes holds and prevents worsening the starting negative distance" $ do
    m <- right (measurePlane horizontal 3 0)
    let pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples horizontal), i < 3]
        guard = planeGuardRow pins m
    guard `shouldBe` (IM.singleton 3 (V3 0 0 1), 0)
    (delta, report) <- right (constrainedStep 20 1 [3] [(IM.singleton 3 (V3 0 0 1), 1)] [guard])
    quadraticConverged report `shouldBe` True
    maybe 1 norm (IM.lookup 3 delta) `shouldSatisfy` (< 1e-12)
    planeDistance m `shouldBe` (-0.01)

  it "rejects missing ids, incident vertices and degenerate or nonfinite planes" $ do
    measurePlane horizontal 9 0 `shouldBe` Left (MissingPlaneVertex 9)
    measurePlane horizontal 3 9 `shouldBe` Left (MissingPlaneTriangle 9)
    measurePlane horizontal 0 0 `shouldBe` Left (IncidentPlaneVertex 0 0)
    measurePlane horizontal {triangles = [(0, 0, 1)]} 3 0 `shouldBe` Left (DegeneratePlane 0)
    measurePlane (move 1 (V3 (0 / 0) 0 0) horizontal) 3 0 `shouldSatisfy` isLeft

horizontal, tilted :: MaterialMesh
horizontal = fixture [V3 0 0 0, V3 1 0 0, V3 0 1 0, V3 2 0.25 (-0.01)]
tilted = fixture [V3 0 0 0.02, V3 1 0.1 0.3, V3 0.1 1 (-0.1), V3 1.5 0.3 (-0.2)]

fixture :: [V3] -> MaterialMesh
fixture ps = Mesh [Sample (V2 (fromIntegral i) 0) p | (i, p) <- zip [0 :: Int ..] ps] [(0, 1, 2)]

move :: Int -> V3 -> MaterialMesh -> MaterialMesh
move vertex delta mesh = mesh {samples = [if i == vertex then s {position = position s ^+^ delta} else s | (i, s) <- zip [0 ..] (samples mesh)]}

axes :: [V3]
axes = [V3 1 0 0, V3 0 1 0, V3 0 0 1]

sumV :: [V3] -> V3
sumV = foldr (^+^) (V3 0 0 0)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
