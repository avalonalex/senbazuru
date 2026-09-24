-- | Fast geometry controls for the opt-in body feasibility study. A simple
-- stack has an independently known solution: translate each free layer without
-- changing its edges. Hard length rejection is tested separately from descent.
module FeasibleInitializationSpec (spec) where

import BodyInitialization
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FeasibleInitialization
import FoldContact (ContactRow (..))
import FoldRelaxation (maxLengthError)
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import Test.Hspec

spec :: Spec
spec = describe "constraint-first separated initialization" $ do
  it "separates two free layers together while preserving held paper and lengths" $ do
    let mesh = layers [0, -1e-8, -2e-8]
        pins = IM.fromList (zip [0 .. 2] (take 3 (initialPositions mesh)))
    model <- contact mesh
    run <- right (feasibleInitialization 4 pins model (ready model) mesh)
    feasibleReady run `shouldBe` True
    let final = foldl (\_ q -> q) mesh (feasibleHistory run)
    length (samples final) `shouldBe` 9
    triangles final `shouldBe` triangles mesh
    map sampleMaterial (samples final) `shouldBe` map sampleMaterial (samples mesh)
    mapM_ (\m -> take 3 (samples m) `shouldBe` take 3 (samples mesh)) (feasibleHistory run)
    mapM_ (\m -> maxLengthError m `shouldSatisfy` (<= 1e-5)) (feasibleHistory run)
    rows <- right (C.orderedContacts model final)
    minimum (map contactGap rows) `shouldSatisfy` (> initializationClearance)

  it "refuses actual stretching even when contact clearance improves" $ do
    let mesh = layers [0, -1e-8]
        translated = mesh {samples = [s {position = let V3 x y z = position s in V3 (if i == 4 then x + 2e-5 else x) y (if i >= 3 then z + 2e-6 else z)} | (i, s) <- zip [0 :: Int ..] (samples mesh)]}
    model <- contact mesh
    oldDeficit <- right (clearanceDeficit model mesh)
    newDeficit <- right (clearanceDeficit model translated)
    newDeficit `shouldSatisfy` (< oldDeficit)
    feasibilityRefusal IM.empty mesh translated `shouldBe` Just "length limit"

  it "represents penetration by one auxiliary scalar without waiving a contact" $ do
    let mesh = layers [0, -1e-8]
    model <- contact mesh
    p <- right (feasibilityProblem IM.empty model mesh mesh)
    problemAuxiliary p `shouldBe` length (samples mesh)
    problemDeficit p `shouldSatisfy` (> 1)
    map feasibleOffset (problemConstraints p) `shouldSatisfy` all (>= 0)
    length (samples mesh) `shouldBe` 6

  it "keeps a joined crease connected without demanding a positive gap there" $ do
    let mesh = Mesh [Sample (V2 0 0) (V3 0 0 0), Sample (V2 1 0) (V3 1 0 0), Sample (V2 0 1) (V3 0 1 0), Sample (V2 0 (-1)) (V3 0 1 0)] [(0, 1, 2), (1, 0, 3)]
    model <- right (C.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1)] [FaceId 0, FaceId 1] mesh)
    clearanceDeficit model mesh `shouldBe` Right 0
    run <- right (feasibleInitialization 0 IM.empty model (const (Right False)) mesh)
    feasibleHistory run `shouldBe` [mesh]
    feasibleReady run `shouldBe` False

  it "stops an immovable intersecting stack without accepting fictitious separation" $ do
    let mesh = layers [0, -1e-8]
        pins = IM.fromList (zip [0 ..] (initialPositions mesh))
    model <- contact mesh
    run <- right (feasibleInitialization 20 pins model (const (Right False)) mesh)
    feasibleReady run `shouldBe` False
    feasibleStop run `shouldBe` "line-search-budget"
    feasibleHistory run `shouldBe` [mesh]
    concatMap (map feasibleFraction . feasibleTrials) (feasibleAttempts run) `shouldBe` initializationFractions

  it "does not label a length-preserving improvement as a ready seed" $ do
    let mesh = layers [0, -1e-8]
        pins = IM.fromList (zip [0 .. 2] (take 3 (initialPositions mesh)))
    model <- contact mesh
    run <- right (feasibleInitialization 1 pins model (const (Right False)) mesh)
    feasibleStop run `shouldBe` "correction-budget"
    length (feasibleHistory run) `shouldBe` 2
    feasibleReady run `shouldBe` False

  it "enforces the Euclidean movement cap, not merely each coordinate's box" $ do
    let mesh = layers [0]
        moved = mesh {samples = [s {position = let V3 x y z = position s in V3 (x + 0.0008) (y + 0.0008) z} | s <- samples mesh]}
    feasibilityRefusal IM.empty mesh moved `shouldBe` Just "movement budget"

  it "validates initial lengths, holds and budgets before a zero-step request" $ do
    let mesh = layers [0, 0.01]
        stretched = mesh {samples = [s {position = let V3 x y z = position s in V3 (1.01 * x) y z} | s <- samples mesh]}
    model <- contact mesh
    feasibleInitialization 21 IM.empty model (const (Right True)) mesh `shouldSatisfy` isLeft
    feasibleInitialization 0 (IM.singleton 0 (V3 1 0 0)) model (const (Right True)) mesh `shouldSatisfy` isLeft
    feasibleInitialization 0 IM.empty model (const (Right True)) stretched `shouldSatisfy` isLeft

contact :: MaterialMesh -> IO C.OrderedContact
contact mesh = right (C.prepareContact 0 (V3 0 0 1) [(FaceId i, FaceId j) | i <- [0 .. n - 1], j <- [i + 1 .. n - 1]] (map FaceId [0 .. n - 1]) mesh)
  where
    n = length (triangles mesh)

ready :: C.OrderedContact -> MaterialMesh -> Either InitializationError Bool
ready model mesh = case C.orderedContacts model mesh of
  Left _ -> Right False
  Right rows -> Right (maxLengthError mesh <= 1e-5 && all ((> initializationClearance) . contactGap) rows)

layers :: [Double] -> MaterialMesh
layers zs = Mesh [Sample uv (V3 x y z) | z <- zs, (uv, x, y) <- [(V2 0 0, 0, 0), (V2 1 0, 1, 0), (V2 0 1, 0, 1)]] [(3 * i, 3 * i + 1, 3 * i + 2) | i <- [0 .. length zs - 1]]

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
