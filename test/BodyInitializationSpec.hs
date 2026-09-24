-- | Small independent geometry checks keep the full archived initialization
-- opt-in. A translated triangle has exactly unchanged material edge lengths;
-- these fixtures distinguish joint clearance from tearing a shared hinge.
module BodyInitializationSpec (spec) where

import BodyInitialization
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FoldContact (ContactRow (..))
import FoldRelaxation (maxLengthError)
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import Test.Hspec

spec :: Spec
spec = describe "bounded separated initialization" $ do
  it "separates both upper layers together without moving held material" $ do
    let mesh = layers [0, -1e-8, -2e-8]
        pins = IM.fromList (zip [0 .. 2] (take 3 (initialPositions mesh)))
    model <- right (C.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1), (FaceId 1, FaceId 2)] (map FaceId [0, 1, 2]) mesh)
    result <- right (initializeSeparated 4 pins model (ready model) mesh)
    initialReady result `shouldBe` True
    length (initialAttempts result) `shouldSatisfy` (<= 4)
    mapM_ (\m -> take 3 (samples m) `shouldBe` take 3 (samples mesh)) (initialHistory result)
    let final = foldl (\_ q -> q) mesh (initialHistory result)
    triangles final `shouldBe` triangles mesh
    map sampleMaterial (samples final) `shouldBe` map sampleMaterial (samples mesh)
    maxLengthError final `shouldSatisfy` (< 1e-5)
    rows <- right (C.orderedContacts model final)
    minimum (map contactGap rows) `shouldSatisfy` (> initializationClearance)

  it "does not demand clearance at a joined material crease" $ do
    let mesh = Mesh [Sample (V2 0 0) (V3 0 0 0), Sample (V2 1 0) (V3 1 0 0), Sample (V2 0 1) (V3 0 1 0), Sample (V2 0 (-1)) (V3 0 1 0)] [(0, 1, 2), (1, 0, 3)]
    model <- right (C.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1)] [FaceId 0, FaceId 1] mesh)
    initializationCost IM.empty model mesh mesh `shouldBe` Right 0

  it "records exhaustion without accepting a cheaper but unready construction" $ do
    let mesh = layers [0, -1e-8]
        pins = IM.fromList (zip [0 .. 2] (take 3 (initialPositions mesh)))
    model <- twoLayerModel mesh
    result <- right (initializeSeparated 1 pins model (const (Right False)) mesh)
    initialReady result `shouldBe` False
    initialStop result `shouldBe` "correction-budget"
    length (initialAttempts result) `shouldBe` 1
    length (initialHistory result) `shouldBe` 2

  it "stops a non-improving held construction after thirteen fractions" $ do
    let mesh = layers [0, -1e-8]
        pins = IM.fromList (zip [0 ..] (initialPositions mesh))
    model <- twoLayerModel mesh
    result <- right (initializeSeparated 20 pins model (const (Right False)) mesh)
    initialStop result `shouldBe` "line-search-budget"
    length (initialHistory result) `shouldBe` 1
    concatMap (map initialFraction . initialTrials) (initialAttempts result) `shouldBe` initializationFractions

  it "retains only candidates inside the total displacement budget" $ do
    let mesh = layers [0, -0.1]
        pins = IM.fromList (zip [0 .. 2] (take 3 (initialPositions mesh)))
    model <- twoLayerModel mesh
    result <- right (initializeSeparated 2 pins model (const (Right False)) mesh)
    mapM_ (\m -> initializationMovement mesh m `shouldSatisfy` (<= initializationMovementLimit)) (initialHistory result)
    concatMap initialTrials (initialAttempts result) `shouldSatisfy` any ((== Just "movement budget") . initialRefusal)

  it "validates the budget and exact holds before even a zero-step request" $ do
    let mesh = layers [0, 0.01]
    model <- twoLayerModel mesh
    initializeSeparated 21 IM.empty model (const (Right True)) mesh `shouldSatisfy` isLeft
    initializeSeparated 0 (IM.singleton 0 (V3 1 0 0)) model (const (Right True)) mesh `shouldSatisfy` isLeft
    result <- right (initializeSeparated 0 IM.empty model (const (Right False)) mesh)
    initialHistory result `shouldBe` [mesh]
    initialAttempts result `shouldBe` []
    initialReady result `shouldBe` False

ready :: C.OrderedContact -> MaterialMesh -> Either InitializationError Bool
ready model mesh = case C.orderedContacts model mesh of
  Left _ -> Right False
  Right rows -> Right (maxLengthError mesh <= 1e-5 && all ((> initializationClearance) . contactGap) rows)

twoLayerModel :: MaterialMesh -> IO C.OrderedContact
twoLayerModel mesh = right (C.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1)] [FaceId 0, FaceId 1] mesh)

layers :: [Double] -> MaterialMesh
layers zs = Mesh [Sample uv (V3 x y z) | z <- zs, (uv, x, y) <- [(V2 0 0, 0, 0), (V2 1 0, 1, 0), (V2 0 1, 0, 1)]] [(3 * i, 3 * i + 1, 3 * i + 2) | i <- [0 .. length zs - 1]]

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
