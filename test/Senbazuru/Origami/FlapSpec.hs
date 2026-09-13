-- | Check the exported angle poses independently of the motion's certificate.
-- The same examples appear in the gallery, but their material lengths, fixed
-- faces, requested angles and failure witnesses are measured here.
module Senbazuru.Origami.FlapSpec (spec) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.List (nub)
import Data.Text qualified as T
import FlapExample
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces)
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), FoldFile (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (View (..), basisFrom)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import Test.Golden (goldenText)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (choose, forAll)

spec :: Spec
spec = describe "checked flap rotation" $ do
  forM_ [FaceId 0, FaceId 1] $ \side ->
    it ("keeps the opposite face still when moving face " ++ show side) $ do
      start <- right (foldFrameWith singleFlap)
      motion <- right (prepareFlap (EdgeId 6) side 150 start >>= checkFlap defaultSweepSettings)
      flapMovingFaces motion `shouldBe` [side]
      sweepOutcome (flapCheck motion) `shouldBe` SweepClear
      original <- right (surfaceFromFolded start)
      forM_ [0, 0.2 .. 1] $ \t -> do
        current <- right (flapAt motion t)
        let fr = surfaceFrame current
        edgesFoldAngle fr `shouldBe` replicate 6 0 ++ [15 + 150 * t]
        facesVertices fr `shouldBe` facesVertices (surfaceFrame original)
        edgesVertices fr `shouldBe` edgesVertices (surfaceFrame original)
        map sampleMaterial (surfaceSamples current) `shouldBe` map sampleMaterial (surfaceSamples original)
        materialError current `shouldSatisfy` (< 1e-12)
        fixed <- right (surfacePanelSamples original)
        actual <- right (surfacePanelSamples current)
        forM_ [(fid, ps) | (fid, ps) <- fixed, fid /= side] $ \(fid, ps) ->
          case lookup fid actual of
            Just qs -> maximum (0 : zipWith (\p q -> norm (position p ^-^ position q)) ps qs) `shouldSatisfy` (< 1e-12)
            Nothing -> expectationFailure "fixed face disappeared"
        -- The dihedral angle measured from material-wound panel normals is
        -- independent of the angle list written to the frame.
        faces <- right (frameFaces fr)
        case faces of
          [a, b] -> abs (angleBetween a b - (15 + 150 * t)) `shouldSatisfy` (< 1e-9)
          _ -> expectationFailure "single fold changed face count"

  prop "preserves material lengths for either direction between open angles" $
    forAll (choose (20, 160)) $ \from -> forAll (choose (20, 160)) $ \to ->
      case do
        start <- either (Left . show) Right (foldFrameWith singleFlap {edgesFoldAngle = replicate 6 0 ++ [from]})
        motion <- either (Left . show) Right (prepareFlap (EdgeId 6) (FaceId 1) (to - from) start >>= checkFlap defaultSweepSettings)
        traverse (either (Left . show) Right . flapAt motion) [0, 0.3, 0.7, 1] of
        Left _ -> False
        Right states -> all ((< 1e-12) . materialError) states

  it "preserves material coordinates and decisions at different model scales" $ do
    forM_ [1e-5, 1, 1e5] $ \scale -> do
      start <- right (foldFrameWith singleFlap {verticesCoords = map (map (* scale)) (verticesCoords singleFlap)})
      motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 150 start >>= checkFlap defaultSweepSettings)
      state <- right (flapAt motion 0.5)
      maximum (map materialU (surfaceSamples state)) `shouldBe` scale
      materialError state `shouldSatisfy` (< 1e-10)

  it "clears the opposing-flap route and refuses a full turn with the same endpoint" $ do
    start <- right (foldFrameWith opposingFlap)
    good <- right (prepareFlap (EdgeId 9) (FaceId 2) 16 start >>= checkFlap defaultSweepSettings)
    end <- right (flapAt good 1)
    materialError end `shouldSatisfy` (< 1e-12)
    bad <- right (prepareFlap (EdgeId 9) (FaceId 2) 360 start)
    returned <- right (foldFrame opposingFlap {edgesFoldAngle = replicate 8 0 ++ [145, 465]})
    let differences = zipWith (-) (concat (verticesCoords returned)) (concat (verticesCoords (foldedFrame start)))
    differences `shouldSatisfy` all ((< 1e-12) . abs)
    case checkFlap defaultSweepSettings bad of
      Left (FlapCollision t pairs) -> do
        t `shouldSatisfy` (\v -> v > 0 && v < 1)
        pairs `shouldContain` [(FaceId 0, FaceId 2)]
        -- Recreate the reported angle state without the flap implementation
        -- and check the named physical panels intersect at that witness.
        witness <- right (foldFrame opposingFlap {edgesFoldAngle = replicate 8 0 ++ [145, 105 + 360 * t]})
        faces <- right (frameFaces witness)
        report <- right (checkPanelContact (V3 0 0 1) [] [Panel (name (faceId f)) (faceCorners f) | f <- faces])
        crossingPanels report `shouldSatisfy` (not . null)
      Left err -> expectationFailure (show err)
      Right _ -> expectationFailure "unsafe full turn was accepted"

  it "moves all faces beyond the crease, including a previously folded flap" $ do
    start <- right (foldFrameWith opposingFlap)
    motion <- right (prepareFlap (EdgeId 8) (FaceId 1) (-10) start >>= checkFlap defaultSweepSettings)
    flapMovingFaces motion `shouldBe` [FaceId 1, FaceId 2]
    forM_ [0, 0.5, 1] $ \t -> do
      current <- right (flapAt motion t)
      edgesFoldAngle (surfaceFrame current) `shouldBe` replicate 8 0 ++ [145 - 10 * t, 105]
      materialError current `shouldSatisfy` (< 1e-12)

  it "uses the folded winding when the original face rings and crease direction are reversed" $ do
    start <- right (foldFrameWith singleFlap {facesVertices = map reverse (facesVertices singleFlap), edgesVertices = [(b, a) | (a, b) <- edgesVertices singleFlap]})
    motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 150 start >>= checkFlap defaultSweepSettings)
    state <- right (flapAt motion 0.5)
    materialError state `shouldSatisfy` (< 1e-12)
    faces <- right (frameFaces (surfaceFrame state))
    case faces of
      [a, b] -> abs (angleBetween a b - 90) `shouldSatisfy` (< 1e-9)
      _ -> expectationFailure "single fold changed face count"

  it "renders a reviewed SVG step page from checked angle states" $ do
    start <- right (foldFrameWith singleFlap)
    motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 150 start >>= checkFlap defaultSweepSettings)
    states <- right (traverse (flapAt motion) [0, 1 / 3, 2 / 3, 1])
    basis <- maybe (fail "invalid camera") pure (basisFrom (V3 (-1) 1 (negate (sqrt 2))) (V3 0 0 1))
    page <- right (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (map materialFrame states))
    diagram <- maybe (fail "no checked states to draw") pure page
    goldenText "test/golden/checked-flap.svg" (renderSvg defaultPage {pageWidth = 1120, pageHeight = 340, pageMargin = 30, pageBackground = Nothing, pageTitle = Just "Single fold"} diagram)

  it "refuses unresolved work without supplying exportable poses" $ do
    start <- right (foldFrameWith opposingFlap)
    motion <- right (prepareFlap (EdgeId 9) (FaceId 2) 360 start)
    case checkFlap (SweepSettings 0 1) motion of
      Left (FlapUnresolved lo hi pairs) -> do
        lo `shouldBe` 0
        hi `shouldBe` 1
        pairs `shouldSatisfy` (not . null)
      Left err -> expectationFailure (show err)
      Right _ -> expectationFailure "exhausted motion was accepted"

  it "refuses the quarter fold's coupled crease without tearing a graph loop" $ do
    file <- loadFoldFile "examples/quarter-fold.fold" >>= right
    let fr = keyFrame file
    start <- right (foldFrameWith fr {edgesFoldAngle = replicate (length (edgesVertices fr)) 0})
    -- Each interior crease in this cross has an alternate route around the
    -- centre. The specific face numbering comes from the returned cut pattern.
    faces <- right (frameFaces (foldedPattern start))
    let owners a b = [faceId f | f <- faces, a `elem` faceVertexIds f, b `elem` faceVertexIds f]
        interior = [(EdgeId i, side) | (i, (a, b)) <- zip [0 ..] (edgesVertices (foldedPattern start)), [side, _] <- [owners a b]]
    interior `shouldSatisfy` (not . null)
    forM_ interior $ \(eid, side) -> case prepareFlap eid side 15 start of
      Left err@(FlapCoupled actual vertices) -> do
        actual `shouldBe` eid
        vertices `shouldSatisfy` (not . null)
        explain err `shouldSatisfy` (not . null . show)
      Left err -> expectationFailure (show err)
      Right _ -> expectationFailure "coupled crease treated as an isolated hinge"

  it "refuses invalid selection, forged starts, nonfinite travel and invalid progress" $ do
    start <- right (foldFrameWith singleFlap)
    prepareFlap (EdgeId 999) (FaceId 1) 10 start `shouldSatisfy` isLeft
    prepareFlap (EdgeId 0) (FaceId 0) 10 start `shouldSatisfy` isLeft
    prepareFlap (EdgeId 6) (FaceId 999) 10 start `shouldSatisfy` isLeft
    forM_ [0 / 0, 1 / 0, 361] $ \angle -> prepareFlap (EdgeId 6) (FaceId 1) angle start `shouldSatisfy` isLeft
    let wrong = (foldedFrame start) {verticesCoords = map (map (* 2)) (verticesCoords (foldedFrame start))}
    prepareFlap (EdgeId 6) (FaceId 1) 10 start {foldedFrame = wrong} `shouldSatisfy` isLeft
    motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 10 start >>= checkFlap defaultSweepSettings)
    forM_ [0 / 0, -0.1, 1.1] $ \t -> flapAt motion t `shouldSatisfy` isLeft

  it "keeps flat touching endpoints outside the accepted scope" $ do
    start <- right (foldFrameWith singleFlap)
    closing <- right (prepareFlap (EdgeId 6) (FaceId 1) 165 start)
    checkFlap defaultSweepSettings closing `shouldSatisfy` isLeft

  it "accepts explicit angles when FOLD leaves assignments unspecified" $ do
    start <- right (foldFrameWith singleFlap {edgesAssignment = []})
    motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 150 start >>= checkFlap defaultSweepSettings)
    state <- right (flapAt motion 1)
    materialError state `shouldSatisfy` (< 1e-12)

materialError :: Surface V2 -> Double
materialError sheet = maximum (0 : errors)
  where
    points = zip (map VertexId [0 ..]) (surfaceSamples sheet)
    edges = nub [(a, b) | ring <- facesVertices (surfaceFrame sheet), a <- ring, b <- ring, a < b]
    errors = [abs (norm (position p ^-^ position q) / norm (sampleMaterial p ^-^ sampleMaterial q) - 1) | (a, b) <- edges, Just p <- [lookup a points], Just q <- [lookup b points]]

angleBetween :: Face -> Face -> Double
angleBetween a b = acos (max (-1) (min 1 (dot (normal a) (normal b)))) * 180 / pi
  where
    normal face = case faceCorners face of
      p : q : r : _ -> let n = cross (q ^-^ p) (r ^-^ p) in (1 / norm n) *^ n
      _ -> V3 0 0 0

name :: FaceId -> T.Text
name = T.pack . show . unFaceId

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
