-- | Fast fixture and acceptance regressions. The four free-boundary solves
-- belong to the explicit gallery command, not every CI run. Only the already
-- flat equilibrium is solved here, to exercise the real convergence gate.
module BodyPatchSpec (spec) where

import BodyPatch
import Control.Monad (forM_)
import CranePocket
import CraneSpread
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import FoldBending
import FoldMaterial (componentCount, meshEdges)
import FoldRelaxation
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Crease (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Hspec
import WingBending (finalMesh)

spec :: Spec
spec = beforeAll load $ describe "coupled crane body specimen" $ do
  it "extracts the material core and both wing collars without welding touching points" $ \atlas -> do
    study <- right (bodyPatch atlas 0 0)
    let fixture = patchSpread study
        mesh = spreadMesh fixture
        ps = M.fromList (zip (map VertexId [0 ..]) (surfaceSamples (pocketSurface atlas)))
        kept = [p | v <- patchVertices study, Just p <- [M.lookup v ps]]
    length (patchFaces study) `shouldBe` 16
    map (\r -> length (filter (`elem` regionFaces atlas r) (patchFaces study))) regions `shouldBe` [8, 4, 4, 0, 0]
    samples mesh `shouldBe` kept
    length (triangles mesh) `shouldBe` 30
    componentCount mesh `shouldBe` 1
    maxLengthError mesh `shouldSatisfy` (< 1e-10)
    -- These four distinct material points meet in the original flat state.
    marks <- right (patchLandmarks study mesh)
    let tips = [p | (name, _, p) <- marks, name /= "centre"]
    length tips `shouldBe` 4
    maximum [norm (p ^-^ q) | p <- tips, q <- tips] `shouldSatisfy` (< 1e-10)
    contact <- right (spreadCheck fixture mesh)
    contactPassed contact `shouldBe` True

  it "keeps the neck and tail free while both root holds retain their radius" $ \atlas -> do
    coarse <- right (bodyPatch atlas 0 5)
    fine <- right (bodyPatch atlas 1 5)
    forM_ [coarse, fine] $ \study -> do
      let fixture = patchSpread study
          pins = spreadPins fixture
          marks = M.fromList (patchMarks study)
      S.fromList (IM.keys pins) `shouldBe` S.fromList [i | (name, i) <- patchMarks study, name `elem` ["centre", "wing-a", "wing-b"]]
      forM_ ["neck", "tail"] $ \name -> case M.lookup name marks of
        Just i -> IM.member i pins `shouldBe` False
        Nothing -> expectationFailure "missing free attachment landmark"
      positions <- right (patchLandmarks study (spreadMesh fixture))
      case [(p, q) | ("centre", p, q) <- positions] of
        [(c, d)] -> forM_ [(p, q) | (name, p, q) <- positions, name `elem` ["wing-a", "wing-b"]] $ \(p, q) ->
          abs (norm (p ^-^ c) - norm (q ^-^ d)) `shouldSatisfy` (< 1e-12)
        _ -> expectationFailure "missing centre"
    spreadPins (patchSpread fine) `shouldBe` spreadPins (patchSpread coarse)
    length (triangles (spreadMesh (patchSpread fine))) `shouldBe` 120
    patchFaces fine `shouldBe` patchFaces coarse
    patchEdges fine `shouldBe` patchEdges coarse
    -- The finer initial guess is only subdivision of the SAME piecewise-flat
    -- shape. It must not introduce a different opening before the solve.
    let coarseMesh = spreadMesh (patchSpread coarse)
        ps = IM.fromList (zip [0 ..] (samples coarseMesh))
        midpoints = [Sample (0.5 *^ (sampleMaterial p ^+^ sampleMaterial q)) (0.5 *^ (position p ^+^ position q)) | (i, j) <- meshEdges coarseMesh, Just p <- [IM.lookup i ps], Just q <- [IM.lookup j ps]]
        expected = samples coarseMesh ++ midpoints
    forM_ (samples (spreadMesh (patchSpread fine))) $ \p ->
      [norm (position p ^-^ position q) | q <- expected, norm (sampleMaterial p ^-^ sampleMaterial q) < 1e-12] `shouldSatisfy` (\errors -> not (null errors) && all (< 1e-12) errors)

  it "keeps source crease identities and original signed preferences under refinement" $ \atlas -> do
    let candidates = S.fromList [creaseId (pocketCrease e) | e <- pocketEdges atlas, pocketRole e == CandidateOpening]
    forM_ [0, 1] $ \level -> do
      study <- right (bodyPatch atlas level 0)
      angles <- right (patchAngles study (spreadMesh (patchSpread study)))
      angles `shouldSatisfy` (not . null)
      forM_ angles $ \(source, achieved, preferred) -> do
        S.member source candidates `shouldBe` True
        abs preferred `shouldBe` pi
        abs (angleError achieved preferred) `shouldSatisfy` (< 1e-9)
      sheet <- right (spreadSurface (patchSpread study) (spreadMesh (patchSpread study)))
      map sampleMaterial (surfaceSamples sheet) `shouldBe` map sampleMaterial (samples (spreadMesh (patchSpread study)))

  it "accepts the flat equilibrium but rejects unfinished, moved-hold and stretched endpoints" $ \atlas -> do
    study <- right (bodyPatch atlas 0 0)
    let fixture = patchSpread study
    result <- right (solveSpread (Settings 2 1e-5) fixture)
    mesh <- right (finalMesh result)
    right (patchAccepted study result mesh) `shouldReturn` True
    right (patchAccepted study result {converged = False} mesh) `shouldReturn` False
    let moved = mesh {samples = [p {position = position p ^+^ V3 0.01 0 0} | p <- samples mesh]}
        stretched = mesh {samples = [p {position = 1.01 *^ position p} | p <- samples mesh]}
    right (patchAccepted study result moved) `shouldReturn` False
    right (patchAccepted study result stretched) `shouldReturn` False

  it "refuses changed material and controls outside the declared small experiment" $ \atlas -> do
    bodyPatch atlas 2 5 `shouldSatisfy` isLeft
    bodyPatch atlas 0 (0 / 0) `shouldSatisfy` isLeft
    bodyPatch atlas 0 11 `shouldSatisfy` isLeft
    study <- right (bodyPatch atlas 0 0)
    let fixture = patchSpread study
        mesh = spreadMesh fixture
    spreadCheck fixture mesh {triangles = drop 1 (triangles mesh)} `shouldSatisfy` isLeft

load :: IO PocketMap
load = do
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)
  right (buildCranePocket source)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
