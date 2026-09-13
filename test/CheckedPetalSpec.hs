-- | Continuous ideal-path checks plus independent measurements of the actual
-- angle-derived/exported paper. Dense samples support the implementation and
-- rendering boundary; they are not the continuous separation certificate.
module CheckedPetalSpec (spec) where

import CheckedPetal
import ContactSpec
import Control.Monad (forM_)
import Data.Aeson (eitherDecode, encode)
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft, isRight)
import Data.IntMap.Strict qualified as IM
import Data.List (find)
import PetalCertificate
import PetalGallery (petalSvg)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Rigid (applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Folding
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface (requireMaterialCoordinates, sampleMaterial, surfaceFromFrame, surfaceSamples)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import StudyCase
import Test.Golden (goldenText)
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "continuously checked bird petal" $ do
  cases <- runIO (BL.readFile "study/fold-material/cases.json" >>= right . eitherDecode)
  entry <- runIO (require "bird petal case" (find ((== "bird-petal") . caseId) (cases :: [CaseSpec])))
  source <- runIO (keyFrame <$> (loadFoldFile (caseSource entry) >>= right))
  motion <- runIO (right (preparePetal entry source))
  start <- runIO (right (checkedPetalAt motion 0))
  (_, orders) <- runIO (require "orders" (poseOrders start))

  it "certifies all pairs, edge lengths and both flat endpoint orders over one whole interval" $
    petalCheck motion `shouldBe` PetalCertificate 1 120 71 28
  it "certifies the held first petal while the second moves, then both pressing" $ do
    certifySecondPetal True orders `shouldSatisfy` isRight
    certifyPress True orders `shouldSatisfy` isRight
  it "refuses the second petal moving to the front side of the packet" $ do
    certifySecondPetal False orders `shouldSatisfy` isLeft
    certifyPress False orders `shouldSatisfy` isLeft
  it "rejects a length-preserving route below the packet" $
    certifyPetal False orders `shouldSatisfy` isLeft
  it "rejects missing and cyclic orders rather than treating coincidence as clear" $ do
    certifyPetal True [] `shouldSatisfy` isLeft
    certifyPetal True ((1, 0) : orders) `shouldSatisfy` isLeft
  it "rejects a reversed endpoint order that the static square geometry cannot resolve" $ do
    let reversed = [if pair == (0, 1) then (1, 0) else pair | pair <- orders]
    certifyPetal True reversed `shouldSatisfy` isLeft
  it "binds the certificate to its material, topology, stationary anchor and orders" $ do
    preparePetal entry source {verticesCoords = [0.01, 0] : drop 1 (verticesCoords source)} `shouldSatisfy` isLeft
    preparePetal entry source {edgesVertices = reverse (edgesVertices source)} `shouldSatisfy` isLeft
    preparePetal entry {caseFixedPanel = Nothing} source `shouldSatisfy` isLeft
    preparePetal entry {caseContact = fmap (\c -> c {panelOrders = []}) (caseContact entry)} source `shouldSatisfy` isLeft
  it "rejects invalid requested angles before evaluating the exact path" $
    forM_ [-1, 181, 0 / 0, 1 / 0] $
      \t -> checkedPetalAt motion t `shouldSatisfy` isLeft
  it "matches the original independent angle-state implementation at arbitrary progress" $
    forAll (choose (0, 180)) $ \t -> case (checkedPetalAt motion t, buildCasePose 0 entry source (PoseSpec "independent" (independentAngles t))) of
      (Right actual, Right reference) -> counterexample (show t) (close (verticesCoords (poseFrame actual)) (verticesCoords (poseFrame reference)))
      other -> counterexample (show other) False

  it "keeps one set of shared vertices, material lengths and signed crease angles throughout the move" $
    forM_ [0, 0.001, 15, 30, 60, 90, 120, 150, 175, 179.999, 180] $ \t -> do
      pose <- right (checkedPetalAt motion t)
      poseContact pose `shouldBe` Just (ContactCheck 120 [] [] [] [])
      frame <- right (checkedPetalFrame motion t)
      map (map unVertexId) (facesVertices frame) `shouldBe` petalFaces
      length (verticesCoords frame) `shouldBe` 13
      material <- right (frameVertices source)
      points <- right (frameVertices frame)
      let original = zip (map VertexId [0 ..]) material
          placed = zip (map VertexId [0 ..]) points
      forM_ (edgesVertices frame) $ \(a, b) -> do
        ma <- require "material a" (lookup a original)
        mb <- require "material b" (lookup b original)
        pa <- require "posed a" (lookup a placed)
        pb <- require "posed b" (lookup b placed)
        abs (norm (ma ^-^ mb) - norm (pa ^-^ pb)) `shouldSatisfy` (< 1e-12)
      folded <- right (foldFrameWith source {edgesFoldAngle = edgesFoldAngle frame})
      originals <- right (frameVertices (foldedPattern folded))
      final <- right (frameVertices (foldedFrame folded))
      forM_ (zip [0 ..] (facesVertices (foldedPattern folded))) $ \(i, ids) -> do
        transform <- require "placement" (IM.lookup i (foldedPlacements folded))
        forM_ ids $ \v -> do
          a <- require "shared material vertex" (lookup v (zip (map VertexId [0 ..]) originals))
          b <- require "shared placed vertex" (lookup v (zip (map VertexId [0 ..]) final))
          norm (applyRigid transform a ^-^ b) `shouldSatisfy` (< 1e-12)
      faces <- right (frameFaces frame)
      forM_ (drop 8 (zip (edgesVertices frame) (edgesFoldAngle frame))) $ \((a, b), requested) -> do
        let incident = [f | f <- faces, a `elem` faceVertexIds f, b `elem` faceVertexIds f]
        case incident of
          [leftFace, rightFace] -> do
            pa <- require "crease start" (lookup a placed)
            pb <- require "crease end" (lookup b placed)
            let axis = unit (if (a, b) `elem` ringEdges (faceVertexIds leftFace) then pb ^-^ pa else pa ^-^ pb)
                n = unit (polygonNormal (faceCorners leftFace))
                m = unit (polygonNormal (faceCorners rightFace))
                actual = negate (180 / pi * atan2 (dot axis (cross n m)) (dot n m))
                difference = actual - requested
            minimum (map abs [difference, difference - 360, difference + 360]) `shouldSatisfy` (< 1e-8)
          _ -> expectationFailure "crease must have two incident panels"

  it "keeps the lower packet still and lifts exactly one original corner" $ do
    end <- right (checkedPetalAt motion 180)
    a <- right (frameVertices (poseFrame start))
    b <- right (frameVertices (poseFrame end))
    forM_ [(i, p, q) | (i, (p, q)) <- zip [0 :: Int ..] (zip a b), i `notElem` [1, 4, 5]] $ \(_, p, q) -> norm (p ^-^ q) `shouldSatisfy` (< 1e-12)
    tip <- require "tip" (lookup 1 (zip [0 :: Int ..] b))
    norm (tip ^-^ V3 (1 - 1 / sqrt 2) (1 / sqrt 2) 0) `shouldSatisfy` (< 1e-12)

  it "exports eight self-contained ordinary FOLD frames, including the exact landing" $ do
    file <- right (petalFile motion)
    eitherDecode (encode file) `shouldBe` Right file
    length (otherFrames file) `shouldBe` 8
    map edgesFoldAngle (otherFrames file) `shouldBe` map petalAngles petalStates
    forM_ (otherFrames file) $ \frame -> do
      length (verticesCoords frame) `shouldBe` 13
      frameInherit frame `shouldBe` False
      faceOrders frame `shouldSatisfy` (not . null)
      loaded <- right (surfaceFromFrame frame >>= requireMaterialCoordinates)
      map sampleMaterial (surfaceSamples loaded) `shouldBe` [V2 x y | [x, y] <- verticesCoords source]
  it "exports stable glTF at every illustration, including buried coplanar packet layers" $
    forM_ petalStates $ \t -> do
      surface <- right (checkedPetalSurface motion t)
      renderSurfaceGlb defaultBudget VisiblePaper Nothing surface `shouldSatisfy` isRight
  it "renders the complete first-petal page with a common side camera and scale" $ do
    file <- right (petalFile motion)
    svg <- right (petalSvg file)
    goldenText "test/golden/checked-petal.svg" svg

independentAngles :: Double -> [Double]
independentAngles t =
  let s = 360 / pi * atan2 (sin (pi / 8) * sin (t * pi / 360)) (cos (t * pi / 360))
   in replicate 8 0 ++ [180, 180, -180, t - 180, -s, -s, -180, t - 180, -s, -s, -180, -180, 0, 0, -180, -180, 0, 0, t, 0]

close :: [[Double]] -> [[Double]] -> Bool
close xs ys = length xs == length ys && and (zipWith (\a b -> length a == length b && and (zipWith (\x y -> abs (x - y) < 1e-12) a b)) xs ys)

unit :: V3 -> V3
unit v = (1 / norm v) *^ v

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure

require :: String -> Maybe a -> IO a
require description = maybe (fail description) pure
