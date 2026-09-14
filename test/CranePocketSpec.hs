-- | The anatomy labels are a material partition, not a new geometry or a
-- claim that the central patch bounds an air cavity. Build the fixture once:
-- the map tests need topology, not repeated nonlinear material solves.
module CranePocketSpec (spec) where

import Control.Monad (forM_, when)
import CranePocket
import CranePocketGallery (pocketSvg)
import Data.Either (isLeft)
import Data.List (sort)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text qualified as T
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Crease (..), edgeKey, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = beforeAll load $ describe "the crane pocket material map" $ do
  it "partitions the whole sheet without mistaking its sectors for separate flaps" $ \study -> do
    map (length . regionFaces study) regions `shouldBe` [8, 14, 10, 18, 26]
    sort (concatMap (regionFaces study) regions) `shouldBe` map FaceId [0 .. 75]
    sum (map (regionArea study) regions) `shouldSatisfy` (\area -> abs (area - 1) < 1e-9)
    materialError study `shouldSatisfy` (< 1e-9)
    let pairs = S.fromList [S.fromList [r | fid <- pocketOwners e, Just r <- [M.lookup fid (pocketRegions study)]] | e <- pocketEdges study]
    forM_ [WingA, WingB] $ \wing -> forM_ [Tail, NeckHead, BodyCore] $ \other ->
      S.member (S.fromList [wing, other]) pairs `shouldBe` True

  it "checks edge ownership and keeps flat connections out of the opening crease set" $ \study -> do
    let frame = surfaceFrame (pocketSurface study)
        incidence = M.fromListWith (++) [(edgeKey a b, [FaceId i]) | (i, ring) <- zip [0 ..] (facesVertices frame), (a, b) <- ringEdges ring]
    forM_ (pocketEdges study) $ \e -> do
      let c = pocketCrease e
      sort (pocketOwners e) `shouldBe` sort (M.findWithDefault [] (edgeKey (creaseFrom c) (creaseTo c)) incidence)
      when (pocketRole e == CandidateOpening) $ creaseAssignment c `shouldSatisfy` (`elem` [Mountain, Valley])
    map (\role -> length [e | e <- pocketEdges study, pocketRole e == role]) [CandidateOpening, UncreasedConnection, AuthoredRoot, RetainedPreference, SheetBoundary] `shouldBe` [22, 21, 4, 79, 12]

  it "keeps the core perimeter internal and coincident underside landmarks distinct" $ \study -> do
    length (pocketCoreBoundary study) `shouldBe` 16
    forM_ [e | e <- pocketEdges study, creaseId (pocketCrease e) `elem` pocketCoreBoundary study] $ \e ->
      length (pocketOwners e) `shouldBe` 2
    S.size (S.fromList (pocketLips study)) `shouldBe` 4
    let points = M.fromList (zip (map VertexId [0 ..]) (surfaceSamples (pocketSurface study)))
        lips = [p | v <- pocketLips study, Just p <- [M.lookup v points]]
    length lips `shouldBe` 4
    maximum [norm (position a ^-^ position b) | a <- lips, b <- lips] `shouldSatisfy` (< 1e-9)
    minimum [norm (sampleMaterial a ^-^ sampleMaterial b) | (i, a) <- zip [0 :: Int ..] lips, (j, b) <- zip [0 ..] lips, i < j] `shouldSatisfy` (> 0.7)

  it "survives face renumbering and refuses changed material or missing faces" $ \study -> do
    let sheet = pocketSurface study
        frame = materialFrame sheet
        reverseId (FaceId i) = FaceId (75 - i)
        reordered = frame {facesVertices = reverse (facesVertices frame), faceOrders = [o {orderFace = reverseId (orderFace o), orderRelativeTo = reverseId (orderRelativeTo o)} | o <- faceOrders frame]}
    again <- right (surfaceFromFrame reordered >>= requireMaterialCoordinates)
    mapped <- right (mapCranePocket again)
    forM_ regions $ \r -> sort (regionFaces mapped r) `shouldBe` sort (map reverseId (regionFaces study r))
    incomplete <- right (surfaceFromFrame frame {facesVertices = take 75 (facesVertices frame), faceOrders = []} >>= requireMaterialCoordinates)
    mapCranePocket incomplete `shouldSatisfy` isLeft
    let stretch coords = case coords of x : rest -> (x * 1.1) : rest; [] -> []
    stretched <- right (surfaceFromFrame frame {verticesCoords = map stretch (verticesCoords frame)} >>= requireMaterialCoordinates)
    mapCranePocket stretched `shouldSatisfy` isLeft

  it "exports highlight drawings without changing the inspected surface" $ \study -> do
    let sheet = pocketSurface study
    forM_ regions $ \r -> do
      pocketSvg False (Just r) study `shouldSatisfy` T.isInfixOf "<svg"
      pocketSvg True (Just r) study `shouldSatisfy` T.isInfixOf "Folded x-ray"
    remapped <- right (mapCranePocket sheet)
    materialFrame (pocketSurface remapped) `shouldBe` materialFrame sheet

load :: IO PocketMap
load = loadFoldFile "examples/crane.fold" >>= right >>= right . buildCranePocket . keyFrame

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
