-- | Independent measurements of held-paper equilibria. These checks establish
-- static shapes and material identity; they do not certify a folding route.
module WingBendingSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (eitherDecode, encode, toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (nub)
import Data.Text qualified as T
import FoldBending
import FoldMaterial (componentCount)
import FoldRelaxation
import Senbazuru.Fold.Query (Crease (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Golden (goldenText)
import Test.Hspec
import UncreasedSurface
import WingBending
import WingBendingGallery (wingSvg)

spec :: Spec
spec = describe "controlled wing bending" $ do
  it "refuses missing and nonfinite held-point targets" $ do
    piece <- right (wingPiece 8 0)
    forM_ [(-1, V3 0 0 0), (99, V3 0 0 0), (0, V3 (0 / 0) 0 0), (0, V3 0 (1 / 0) 0)] $ \(i, target) ->
      relaxPinnedHinges defaultSettings (IM.singleton i target) (pieceHinges piece) (pieceMesh piece) `shouldBe` Left (InvalidPositionConstraint i)
  it "does not call an unreachable fully held triangle converged" $ do
    let mesh = Mesh [Sample (V2 0 0) (V3 0 0 0), Sample (V2 1 0) (V3 1 0 0), Sample (V2 0 1) (V3 0 1 0)] [(0, 1, 2)]
        pins = IM.fromList [(0, V3 0 0 0), (1, V3 2 0 0), (2, V3 0 1 0)]
    result <- right (relaxPinnedHinges (Settings 2 1e-5) pins [] mesh)
    converged result `shouldBe` False
    final <- right (finalMesh result)
    map position (samples final) `shouldBe` IM.elems pins
    maxLengthError final `shouldSatisfy` (> 0.9)
  it "retains the old free solve when no positions are held" $ do
    piece <- right (stripBenchmark 8)
    let settings = Settings 2 1e-5
    relaxPinnedHinges settings IM.empty (pieceHinges piece) (pieceMesh piece)
      `shouldBe` relaxHinges settings (pieceHinges piece) (pieceMesh piece)
  it "does not hide an invalid original position behind a finite grip" $ do
    let mesh = Mesh [Sample (V2 0 0) (V3 (0 / 0) 0 0), Sample (V2 1 0) (V3 1 0 0), Sample (V2 0 1) (V3 0 1 0)] [(0, 1, 2)]
    relaxPinnedHinges defaultSettings (IM.singleton 0 (V3 0 0 0)) [] mesh `shouldBe` Left (InvalidSample 0)
  it "rejects unsupported resolutions and nonfinite or out-of-range controls" $ do
    forM_ [-1, 0, 7, 12, 40] $ \n -> wingPiece n 20 `shouldSatisfy` isLeft
    forM_ [-1, 61, 0 / 0, 1 / 0] $ \a -> wingPiece 8 a `shouldSatisfy` isLeft

  -- Only the independent solves run concurrently; the golden below stays serial.
  forM_ [8, 16, 24] $ \n -> parallel $ beforeAll (settled (stripBenchmark n)) $ do
    it ("recovers the known equal-turn strip at " ++ show n ++ " spans") $ \(piece, result, mesh) -> do
      converged result `shouldBe` True
      reference <- maybe (fail "missing strip reference") pure (pieceReference piece)
      maximum (zipWith (\a b -> norm (position a ^-^ position b)) (samples mesh) (samples reference)) `shouldSatisfy` (< 2e-6)
      independentEdgeError mesh `shouldSatisfy` (< 1e-7)
      (_, expectedEnergy) <- right (bendingEnergy (pieceHinges piece) reference)
      (_, actualEnergy) <- right (bendingEnergy (pieceHinges piece) mesh)
      abs (actualEnergy - expectedEnergy) `shouldSatisfy` (< 1e-7)
      heldExactly piece result

  forM_ [(n, a) | n <- [8, 16, 24], a <- [0, 20, 40]] $ \(n, a) -> parallel $ beforeAll (settled (wingPiece n a)) $ do
    it ("preserves material and endpoint contact with " ++ show n ++ " divisions at " ++ show a ++ " degrees") $ \(piece, result, mesh) -> do
      converged result `shouldBe` True
      triangles mesh `shouldBe` triangles (pieceMesh piece)
      map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples (pieceMesh piece))
      componentCount mesh `shouldBe` 1
      independentEdgeError mesh `shouldSatisfy` (< 2e-7)
      heldExactly piece result
      forM_ (pieceHinges piece) $ \hinge -> hingeRole hinge `shouldBe` PanelBend
      report <- right (checkLocalTriangleContact (V3 0 0 1) [] mesh)
      contactPassed report `shouldBe` True
      let count = length (triangles mesh)
      checkedPanelPairs report `shouldBe` count * (count - 1) `div` 2
      if a == 0
        then samples mesh `shouldBe` samples (pieceMesh piece)
        else maximum (zipWith (\p q -> norm (position p ^-^ position q)) (samples mesh) (samples (pieceMesh piece))) `shouldSatisfy` (> 1e-6)
    it ("exports the same curved triangles without new creases at " ++ show n ++ " / " ++ show a) $ \(_, _, mesh) -> do
      sheet <- right (uncreasedSurface mesh)
      surfaceSamples sheet `shouldBe` samples mesh
      let fr = materialFrame sheet
      facesVertices fr `shouldBe` [map VertexId [i, j, k] | (i, j, k) <- triangles mesh]
      KM.lookup "senbazuru:source_panels" (frameExtras fr) `shouldBe` Just (toJSON (replicate (length (triangles mesh)) (0 :: Int)))
      edgesAssignment fr `shouldSatisfy` all (`elem` [Border, Join])
      features <- right (surfaceFeatures sheet)
      map (creaseAssignment . fst) features `shouldSatisfy` all (== Border)
      decoded <- right (eitherDecode (encode fr))
      restored <- right (surfaceFromFrame decoded >>= requireMaterialCoordinates)
      surfaceSamples restored `shouldBe` samples mesh

  it "draws a reviewed known bent strip with no subdivision strokes" $ do
    piece <- right (stripBenchmark 8)
    reference <- maybe (fail "missing strip reference") pure (pieceReference piece)
    sheet <- right (uncreasedSurface reference)
    drawing <- right (wingSvg [sheet])
    drawing `shouldSatisfy` (not . T.isInfixOf "stroke=\"#bdbdbd\"")
    goldenText "test/golden/bent-strip.svg" drawing

heldExactly :: BendingPiece -> Relaxation -> IO ()
heldExactly piece result = forM_ (checkpoints result) $ \checkpoint -> do
  let positions = IM.fromList (zip [0 ..] (map position (samples (checkpointMesh checkpoint))))
  forM_ (IM.toList (piecePins piece)) $ \(i, target) -> IM.lookup i positions `shouldBe` Just target

independentEdgeError :: MaterialMesh -> Double
independentEdgeError mesh = maximum (0 : errors)
  where
    vertices = IM.fromList (zip [0 ..] (samples mesh))
    edges = nub [(min i j, max i j) | (a, b, c) <- triangles mesh, (i, j) <- [(a, b), (b, c), (c, a)]]
    errors = [abs (norm (position a ^-^ position b) / norm (sampleMaterial a ^-^ sampleMaterial b) - 1) | (i, j) <- edges, Just a <- [IM.lookup i vertices], Just b <- [IM.lookup j vertices]]

settled :: Either WingError BendingPiece -> IO (BendingPiece, Relaxation, MaterialMesh)
settled build = do
  piece <- right build
  result <- right (solvePiece piece)
  mesh <- right (finalMesh result)
  pure (piece, result, mesh)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
