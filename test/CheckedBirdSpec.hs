-- | Independently measure the angle-derived three-stage bird route. The exact
-- certificates cover intervals; these measurements check their connection to
-- the actual folding engine, accepted stage joins and exported material.
module CheckedBirdSpec (spec) where

import CheckedBird
import CheckedPetal (checkedPetalAt, preparePetal)
import ContactSpec (ContactSpec (..))
import Control.Monad (forM_)
import Data.Aeson (eitherDecode, encode)
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft, isRight)
import Data.IntMap.Strict qualified as IM
import Data.List (find)
import FoldRelaxation (maxLengthError)
import PetalCertificate
import PetalGallery (birdSvg)
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
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import StudyCase
import Test.Golden (goldenText)
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "continuously checked complete bird base" $ do
  cases <- runIO (BL.readFile "study/fold-material/cases.json" >>= right . eitherDecode)
  entry <- runIO (require "bird case" (find ((== "bird-petal") . caseId) (cases :: [CaseSpec])))
  source <- runIO (keyFrame <$> (loadFoldFile (caseSource entry) >>= right))
  bird <- runIO (right (prepareBird entry source))

  it "checks all 120 pairs and 28 material edges in each of the three stages" $ do
    map fst (birdChecks bird) `shouldBe` [FrontPetal, BackPetal, PressPetals]
    map snd (birdChecks bird) `shouldBe` [PetalCertificate 1 120 71 28, PetalCertificate 1 120 48 28, PetalCertificate 1 120 92 28]
  it "inherits the accepted first petal and preserves every stage join" $ do
    front <- right (preparePetal entry source >>= (`checkedPetalAt` 175))
    second <- right (checkedBirdAt bird BackPetal 0)
    samePose front second
    forM_ [(FrontPetal, BackPetal), (BackPetal, PressPetals)] $ \(earlier, later) -> do
      a <- right (checkedBirdAt bird earlier 1)
      b <- right (checkedBirdAt bird later 0)
      samePose a b
      fa <- right (checkedBirdFrame bird earlier 1)
      fb <- right (checkedBirdFrame bird later 0)
      faceOrders fa `shouldBe` faceOrders fb
      frameExtras fa `shouldBe` frameExtras fb
  it "refuses invalid progress and changed fixture or order inputs" $ do
    forM_ [FrontPetal, BackPetal, PressPetals] $ \stage ->
      forM_ [-0.01, 1.01, 0 / 0, 1 / 0] $ \progress ->
        checkedBirdAt bird stage progress `shouldSatisfy` isLeft
    prepareBird entry source {verticesCoords = [0.01, 0] : drop 1 (verticesCoords source)} `shouldSatisfy` isLeft
    prepareBird entry {caseFixedPanel = Nothing} source `shouldSatisfy` isLeft
    certifySecondPetal True [] `shouldSatisfy` isLeft
    certifyPress True [] `shouldSatisfy` isLeft
  it "requires the new second-petal landing order even when the first petal remains accepted" $ do
    let missing = entry {caseContact = fmap (\contact -> contact {panelOrders = filter (/= ("north-west-side", "second-petal")) (panelOrders contact)}) (caseContact entry)}
    preparePetal missing source `shouldSatisfy` isRight
    prepareBird missing source `shouldSatisfy` isLeft
    start <- right (checkedBirdAt bird FrontPetal 0)
    (_, orders) <- require "orders" (poseOrders start)
    certifySecondPetal True [(b, a) | (a, b) <- orders] `shouldSatisfy` isLeft
    certifyPress True [(b, a) | (a, b) <- orders] `shouldSatisfy` isLeft
  it "holds every front-petal and body vertex fixed during the second turn" $ do
    startPose <- right (checkedBirdAt bird BackPetal 0)
    start <- right (frameVertices (poseFrame startPose))
    forM_ [0, 0.1, 0.5, 0.9, 1] $ \progress -> do
      pose <- right (checkedBirdAt bird BackPetal progress)
      placed <- right (frameVertices (poseFrame pose))
      forM_ [(p, q) | (i, (p, q)) <- zip [0 :: Int ..] (zip start placed), i `notElem` [3, 6, 7]] $ \(p, q) ->
        norm (p ^-^ q) `shouldSatisfy` (< 1e-12)
  it "matches independent circular tip paths at arbitrary stage progress" $
    forAll (elements [FrontPetal, BackPetal, PressPetals]) $ \stage ->
      forAll (choose (0, 1)) $ \progress -> case checkedBirdAt bird stage progress of
        Left err -> counterexample (show err) False
        Right pose ->
          let (t, u) = birdHinges stage progress
              tip degrees side = let r = degrees * pi / 180; d = 1 / sqrt 2 in V3 (1 - d / 2 + d * cos r / 2) (d / 2 - d * cos r / 2) (side * sin r / 2)
              indexed = zip [0 :: Int ..] (map position (samples (poseMesh pose)))
           in counterexample (show (stage, progress)) (all (\(i, expected) -> maybe False (\p -> norm (p ^-^ expected) < 1e-12) (lookup i indexed)) [(1, tip t 1), (3, tip u (-1))])
  it "keeps material lengths, shared vertices and signed achieved angles throughout all stages" $
    forM_ [FrontPetal, BackPetal, PressPetals] $ \stage ->
      forM_ [0, 0.00001, 0.2, 0.5, 0.8, 0.99999, 1] $ \progress -> do
        pose <- right (checkedBirdAt bird stage progress)
        poseContact pose `shouldBe` Just (ContactCheck 120 [] [] [] [])
        maxLengthError (poseMesh pose) `shouldSatisfy` (< 1e-12)
        frame <- right (checkedBirdFrame bird stage progress)
        folded <- right (foldFrameWith source {edgesFoldAngle = edgesFoldAngle frame})
        original <- right (frameVertices (foldedPattern folded))
        placed <- right (frameVertices (foldedFrame folded))
        forM_ (zip [0 ..] (facesVertices (foldedPattern folded))) $ \(i, ids) -> do
          transform <- require "face placement" (IM.lookup i (foldedPlacements folded))
          forM_ ids $ \v -> do
            a <- require "material vertex" (lookup v (zip (map VertexId [0 ..]) original))
            b <- require "placed vertex" (lookup v (zip (map VertexId [0 ..]) placed))
            norm (applyRigid transform a ^-^ b) `shouldSatisfy` (< 1e-12)
        checkAngles frame
  it "finishes at all thirteen independent bird landmarks and the source angle state" $ do
    frame <- right (checkedBirdFrame bird PressPetals 1)
    edgesFoldAngle frame `shouldBe` edgesFoldAngle source
    points <- right (frameVertices frame)
    let d = 1 / sqrt 2
        tip = V3 (1 - d) d 0
        midpoint = V3 (1 - d / 2) (d / 2) 0
        p = V3 0.5 (d - 0.5) 0
        q = V3 (1.5 - d) 0.5 0
        expected = [V3 1 0 0, tip, V3 1 0 0, tip] ++ replicate 4 midpoint ++ [V3 0.5 0.5 0, p, q, q, p]
    length points `shouldBe` 13
    forM_ (zip points expected) $ \(a, b) -> norm (a ^-^ b) `shouldSatisfy` (< 1e-12)
  it "exports sixteen self-contained material frames and stable GLBs including both flat endpoints" $ do
    file <- right (birdFile bird)
    eitherDecode (encode file) `shouldBe` Right file
    length (otherFrames file) `shouldBe` 16
    forM_ (zip birdStates (otherFrames file)) $ \((stage, progress), frame) -> do
      frameInherit frame `shouldBe` False
      faceOrders frame `shouldSatisfy` (not . null)
      paper <- right (surfaceFromFrame frame >>= requireMaterialCoordinates)
      map sampleMaterial (surfaceSamples paper) `shouldBe` [V2 x y | [x, y] <- verticesCoords source]
      surface <- right (checkedBirdSurface bird stage progress)
      renderSurfaceGlb defaultBudget VisiblePaper Nothing surface `shouldSatisfy` isRight
  forM_ [(False, "above"), (True, "below")] $ \(underside, viewName) ->
    it ("renders the complete page from " ++ viewName ++ " with a shared camera and scale") $ do
      file <- right (birdFile bird)
      svg <- right (birdSvg underside file)
      goldenText ("test/golden/checked-bird-" ++ viewName ++ ".svg") svg

samePose :: StudyPose -> StudyPose -> Expectation
samePose a b = do
  verticesCoords (poseFrame a) `shouldBe` verticesCoords (poseFrame b)
  edgesFoldAngle (poseFrame a) `shouldBe` edgesFoldAngle (poseFrame b)
  facesVertices (poseFrame a) `shouldBe` facesVertices (poseFrame b)
  poseOrders a `shouldBe` poseOrders b
  map sampleMaterial (surfaceSamples (poseSurface a)) `shouldBe` map sampleMaterial (surfaceSamples (poseSurface b))

checkAngles :: Frame -> Expectation
checkAngles frame = do
  faces <- right (frameFaces frame)
  points <- right (frameVertices frame)
  let indexed = zip (map VertexId [0 ..]) points
      unit v = (1 / norm v) *^ v
  forM_ (drop 8 (zip (edgesVertices frame) (edgesFoldAngle frame))) $ \((a, b), requested) ->
    case [f | f <- faces, a `elem` faceVertexIds f, b `elem` faceVertexIds f] of
      [leftFace, rightFace] -> do
        pa <- require "crease start" (lookup a indexed)
        pb <- require "crease end" (lookup b indexed)
        let axis = unit (if (a, b) `elem` ringEdges (faceVertexIds leftFace) then pb ^-^ pa else pa ^-^ pb)
            n = unit (polygonNormal (faceCorners leftFace))
            m = unit (polygonNormal (faceCorners rightFace))
            actual = negate (180 / pi * atan2 (dot axis (cross n m)) (dot n m))
            difference = actual - requested
        minimum (map abs [difference, difference - 360, difference + 360]) `shouldSatisfy` (< 1e-8)
      _ -> expectationFailure "crease must have two incident panels"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure

require :: String -> Maybe a -> IO a
require description = maybe (fail description) pure
