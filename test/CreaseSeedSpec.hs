module CreaseSeedSpec (spec) where

import BodyCreaseSeed
import BodyPatch
import CranePocket
import CraneSpread
import CreaseSeed
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FoldRelaxation (maxLengthError)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "crease-coordinate body initialization" $ do
  it "constructs a single hinge without changing its prescribed angle" $ do
    source <- keyFrame <$> (loadFoldFile "examples/diagonal-cp.fold" >>= right)
    result <- right (coordinateCreases 40 source)
    angleClosed result `shouldBe` True
    length (angleHistory result) `shouldBe` 1
    folded <- right (foldFrameWith (angleFrame result))
    paper <- right (surfaceFromFolded folded)
    (mesh, _) <- right (refineSurface 1 paper)
    maxLengthError mesh `shouldSatisfy` (< 1e-10)
    filter (/= 0) (edgesFoldAngle (angleFrame result)) `shouldSatisfy` all (\x -> abs (abs x - 175) < 1e-10)
  it "detects incompatible angles at an interior crease intersection" $ do
    source <- keyFrame <$> (loadFoldFile "examples/square-base.fold" >>= right)
    let angles = [if a == Mountain then -175 else if a == Valley then 175 else 0 | a <- edgesAssignment source]
    rs <- right (creaseResiduals source angles)
    maximum (map abs rs) `shouldSatisfy` (> 1e-4)
    foldFrameWith source {edgesFoldAngle = angles} `shouldSatisfy` isLeft
    result <- right (coordinateCreases 0 source)
    angleClosed result `shouldBe` False
    angleStop result `shouldBe` "correction-budget"
  it "keeps a tree of two hinges within the declared angle bounds" $ do
    source <- keyFrame <$> (loadFoldFile "examples/kite-base.fold" >>= right)
    result <- right (coordinateCreases 40 source)
    angleClosed result `shouldBe` True
    _ <- right (foldFrameWith (angleFrame result))
    pure ()
  it "coordinates a four-crease vertex through multiple angle corrections" $ do
    let r = sqrt 0.5
        source =
          emptyFrame
            { verticesCoords = [[0, 0], [1, 0], [r, r], [-1, 0], [r, -r]],
              edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (0, 2), (0, 3), (0, 4), (1, 2), (2, 3), (3, 4), (4, 1)]],
              edgesAssignment = [Mountain, Valley, Valley, Valley, Border, Border, Border, Border],
              facesVertices = map (map VertexId) [[0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 1]]
            }
    result <- right (coordinateCreases 40 source)
    angleClosed result `shouldBe` True
    length (angleHistory result) `shouldSatisfy` (> 1)
    let costs = map angleStepCost (angleHistory result)
    and (zipWith (>) costs (drop 1 costs)) `shouldBe` True
    map (filter (/= 0) . angleStepDegrees) (angleHistory result)
      `shouldSatisfy` all (all (\x -> abs x >= 150 && abs x <= 179.99))
    _ <- right (foldFrameWith (angleFrame result))
    pure ()
  it "refuses invalid budgets and nonfinite angle arrays" $ do
    source <- keyFrame <$> (loadFoldFile "examples/diagonal-cp.fold" >>= right)
    coordinateCreases 41 source `shouldSatisfy` isLeft
    coordinateCreases (-1) source `shouldSatisfy` isLeft
    creaseResiduals source [] `shouldSatisfy` isLeft
    creaseResiduals source (replicate (length (edgesVertices source)) (0 / 0)) `shouldSatisfy` isLeft
  it "reconstructs the closed body with unchanged shared ids, preferences and grip positions" $ do
    source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)
    atlas <- right (buildCranePocket source)
    original <- right (bodyPatch atlas 1 0)
    folded <- right (foldFrameWith (bodyCreasePattern original))
    installed <- right (installCreaseSeed original folded)
    let old = patchSpread original; new = patchSpread installed
    triangles (spreadMesh new) `shouldBe` triangles (spreadMesh old)
    map sampleMaterial (samples (spreadMesh new)) `shouldBe` map sampleMaterial (samples (spreadMesh old))
    let placementErrors = zipWith (\p q -> norm (position p ^-^ position q)) (samples (spreadMesh new)) (samples (spreadMesh old))
    maximum placementErrors `shouldSatisfy` (< 1e-10)
    spreadOrders new `shouldBe` spreadOrders old
    spreadHinges new `shouldBe` spreadHinges old
    IM.keys (spreadPins new) `shouldBe` IM.keys (spreadPins old)
    maxLengthError (spreadMesh new) `shouldSatisfy` (< 1e-10)
    spreadHeldError new (spreadMesh new) `shouldBe` 0

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
