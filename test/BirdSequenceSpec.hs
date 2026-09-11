-- | The study crosses into production as ordinary FOLD, with one regression
-- fixture shared by the CLI and these geometry/visibility checks.
module BirdSequenceSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (eitherDecode, encode)
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft)
import Data.List (find, tails)
import Data.Maybe (isJust)
import FoldMaterial (position, samples)
import Senbazuru.Diagram (Diagram (..), Shape (..))
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.Polygon (clipConvex, signedArea)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface qualified as Paper
import Senbazuru.Origami.Visible (Region (..), VisibleForm (..))
import Senbazuru.Render.Camera
import Senbazuru.Render.CreasePattern (surfaceDiagram)
import Senbazuru.Render.Projected
import Senbazuru.Render.Steps
import Senbazuru.Render.Svg
import StudyCase
import Test.Golden (goldenText)
import Test.Hspec

spec :: Spec
spec = describe "bird sequence through production SVG" $ do
  cases <- runIO $ BL.readFile "study/fold-material/cases.json" >>= right . eitherDecode
  entry <- runIO $ case find ((== "bird-petal") . caseId) (cases :: [CaseSpec]) of
    Just value -> pure value
    Nothing -> fail "missing bird case"
  source <- runIO $ loadFoldFile (caseSource entry) >>= right
  file <- runIO $ right (buildCaseSequence entry source)
  it "matches the checked-in ordinary FOLD fixture and round-trips it" $ do
    fixture <- loadFoldFile "examples/bird-base-sequence.fold" >>= right
    withoutCoordinates fixture `shouldBe` withoutCoordinates file
    forM_ (zip (keyFrame fixture : otherFrames fixture) (keyFrame file : otherFrames file)) $ \(expected, actual) -> do
      -- The same trigonometry on macOS and Linux differs in the last few
      -- bits. Use the study's 1e-12 unit-sheet tolerance only for coordinates;
      -- frame counts, topology, angles, orders and metadata stay exact above.
      let expectedPoints = verticesCoords expected
          actualPoints = verticesCoords actual
      map length actualPoints `shouldBe` map length expectedPoints
      let differences = zipWith (\a b -> abs (a - b)) (concat actualPoints) (concat expectedPoints)
      differences `shouldSatisfy` all (< 1e-12)
    eitherDecode (encode file) `shouldBe` Right file
  it "requires contact checks and refuses a reversed moving state at export" $ do
    buildCaseSequence entry {caseContact = Nothing} source `shouldSatisfy` isLeft
    forM_ (take 1 (drop 1 (caseSteps entry))) $ \step ->
      buildCaseFrame entry (keyFrame source) step {poseAngles = map negate (poseAngles step)} `shouldSatisfy` isLeft
  forM_ (zip3 [0 :: Int ..] (caseSteps entry) (otherFrames file)) $ \(i, step, fr) -> it ("preserves state " ++ show i ++ " and has nonoverlapping visible paper from both sides") $ do
    pose <- right (buildCasePose 0 entry (keyFrame source) step)
    frameVertices fr `shouldBe` Right (map position (samples (poseMesh pose)))
    edgesFoldAngle fr `shouldBe` poseAngles step
    length (verticesCoords fr) `shouldBe` 13
    length (facesVertices fr) `shouldBe` 16
    forM_ [isometric, topDown, bottomUp] $ \basis -> do
      -- The direct surface entry point takes the same checked geometry; its
      -- material thickness must not shift visible regions in page space.
      surface <- right (Paper.withFaceOrders (faceOrders fr) (poseSurface pose) >>= Paper.withPhysicalThickness (Just 0.001))
      diagram <- right (surfaceDiagram defaultTheme defaultBudget (View (Just basis) 0) surface)
      result <- right (projectedForm basis fr (faceOrders fr))
      result `shouldSatisfy` isJust
      case result of
        Nothing -> pure ()
        Just seen -> do
          let pieces = [map (project basis) piece | region <- formRegions seen, piece <- regionPieces region]
              overlaps = [abs (signedArea (clipConvex a b)) | a : rest <- tails pieces, b <- rest]
          overlaps `shouldSatisfy` all (< 1e-8)
          let drawnArea = sum [abs (signedArea ring) | Fill _ rings <- diagramShapes diagram, ring <- rings]
              visibleArea = sum (map (abs . signedArea) pieces)
          abs (drawnArea - visibleArea) `shouldSatisfy` (< 1e-8)
  forM_ [("iso", isometric), ("bottom", bottomUp)] $ \(name, basis) -> it ("renders a reviewed " ++ name ++ " sequence with one camera and scale") $ do
    result <- right (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) False (allFrames file))
    case result of
      Nothing -> expectationFailure "missing page"
      Just diagram -> do
        length [() | Label {} <- diagramShapes diagram] `shouldBe` 16
        goldenText ("test/golden/bird-sequence-" ++ name ++ ".svg") (renderSvg defaultPage {pageWidth = 1000, pageHeight = 1000} diagram)

withoutCoordinates :: FoldFile -> FoldFile
withoutCoordinates file =
  file
    { keyFrame = clear (keyFrame file),
      otherFrames = map clear (otherFrames file)
    }
  where
    clear fr = fr {verticesCoords = []}

right :: (Show e) => Either e a -> IO a
right (Right value) = pure value
right (Left err) = expectationFailure (show err) >> fail "fixture failed"
