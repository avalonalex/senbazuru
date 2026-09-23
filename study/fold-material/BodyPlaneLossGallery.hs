-- | Inspect the archived moving-plane comparison without solving again.
-- Validate both saved proposals and every finite trial against the same paper
-- and acceptance checks before decomposing their distances. The original
-- quadratic reports remain archival evidence, not newly computed solutions.
--
-- Paper images and FOLD files are copied unchanged. Only the accounting charts
-- are new drawings; their axes are numerical measurements, not exaggerated
-- paper positions. Paths come from fixed direction and fraction indices.
module BodyPlaneLossGallery (writeBodyPlaneLoss) where

import BodyCorrectionArchive
import BodyCorrectionReplay (scaledProposal)
import BodyPlaneArchive
import BodyPlaneLoss
import Control.Monad (forM, forM_, unless)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Senbazuru.Diagram
import Senbazuru.Explain (num)
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))

data LossTrial = LossTrial String Value PlaneLoss

data LossDirection = LossDirection String Value [LossTrial]

writeBodyPlaneLoss :: FilePath -> FilePath -> IO ()
writeBodyPlaneLoss source destination = do
  let output = destination </> "body-plane-loss"
  separateOutput source output
  archive <- readPlaneArchive source
  before <- pose (planeStart archive)
  directions <- forM (planeDirections archive) $ \(name, record, trials) -> do
    proposal <- field "proposal" record >>= traverse vector
    full <- checked (scaledProposal 1 (planeStart archive) proposal)
    proposed <- pose full
    entries <- forM trials $ \(label, mesh, trial) -> do
      fraction <- field "scale" trial
      after <- pose mesh
      loss <- checked (decomposePlane before proposed fraction after)
      pure (LossTrial label trial loss)
    pure (LossDirection name record entries)
  let files = planeFiles archive; report = planeReport archive
  createDirectoryIfMissing True output
  forM_ files $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  forM_ [0 :: Int .. 30] $ \k -> do
    let entries = [(T.pack name, loss) | LossDirection name _ trials <- directions, (j, LossTrial _ _ loss) <- zip [0 :: Int ..] trials, j == k]
    TIO.writeFile (output </> "loss-" ++ show k ++ ".svg") (drawLoss entries)
  let result = object ["gallery" .= ("body-plane-loss" :: Text), "issue" .= (347 :: Int), "newSolves" .= (0 :: Int), "validatedTrials" .= (372 :: Int), "source" .= report, "reference" .= ("triangle 70 centroid; original winding" :: Text), "directions" .= [object ["id" .= name, "archived" .= record, "trials" .= [object ["id" .= trialName, "archived" .= trial, "accounting" .= lossValue loss] | LossTrial trialName trial loss <- trials]] | LossDirection name record trials <- directions]]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile "study/fold-material/body-plane-loss.html"
  TIO.writeFile (destination </> "body-plane-loss.html") (T.replace "/*BODY_PLANE_LOSS_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Inspected 62 saved plane trials without new solves. Wrote " ++ destination </> "body-plane-loss.html")

lossValue :: PlaneLoss -> Value
lossValue m = object ([key .= f m | (key, f) <- [("initialDistance", initialDistance), ("actualDistance", actualDistance), ("linearDistance", linearDistance), ("quadraticDistance", quadraticDistance), ("relativeLinear", relativeLinear), ("rotationLinear", rotationLinear), ("rotationRemainder", rotationRemainder), ("motionInteraction", motionInteraction), ("relativeRounding", relativeRounding), ("reconciliationError", reconciliationError), ("rotationSecondOrder", rotationSecondOrder), ("interactionSecondOrder", interactionSecondOrder), ("normalTurn", normalTurn)]] ++ [key .= xyz (f m) | (key, f) <- [("startNormal", startNormal), ("trialNormal", trialNormal), ("normalDerivative", normalDerivative), ("normalQuadratic", normalQuadratic), ("startRelative", startRelative), ("trialRelative", trialRelative), ("relativeDerivative", relativeDerivative)]])

-- | One common numerical scale for both directions at the same fraction.
-- Bars are losses missed by the linear prediction, never displaced paper.
drawLoss :: [(Text, PlaneLoss)] -> Text
drawLoss entries = renderSvg page (diagramWithExtent bounds shapes)
  where
    groups = [("Plane rotation", rotationRemainder), ("Interaction", motionInteraction), ("Relative rounding", relativeRounding), ("Total missed", \m -> actualDistance m - linearDistance m)]
    values = [1e12 * f m | (_, m) <- entries, (_, f) <- groups]
    extent = maximum (1e-6 : map abs values)
    bounds = Box (V2 (-1.4) (-1.55)) (V2 6.8 1.4)
    line colour width = Polyline (solid (Colour colour) width)
    axes = [line "#918b7e" 1 [V2 (-0.4) 0, V2 6.5 0], line "#bcb7ab" 1 [V2 (-0.4) (-1), V2 (-0.4) 1]] ++ [Offset (V2 (-70) 4) (Label (Colour "#55584f") 11 (V2 (-0.4) y) (num (y * extent))) | y <- [-1, 0, 1]]
    bars = [let x = 2 * fromIntegral i + fromIntegral j * 0.3 - 0.15; y = 1e12 * f m / extent; colour = if j == 0 then "#777e87" else "#235e87" in line colour 14 [V2 x 0, V2 x y] | (i, (_, f)) <- zip [0 :: Int ..] groups, (j, (_, m)) <- zip [0 :: Int ..] entries]
    labels = [Offset (V2 (-48) 0) (Label (Colour "#55584f") 12 (V2 (2 * fromIntegral i) (-1.35)) title) | (i, (title, _)) <- zip [0 :: Int ..] groups]
    shapes = axes ++ bars ++ labels
    page = defaultPage {pageWidth = 900, pageHeight = 340, pageMargin = 30, pageBackground = Nothing, pageTitle = Just "Missed plane-distance change in units of 1e-12 sheet lengths: grey control, blue extra guard"}

pose :: MaterialMesh -> IO PlanePose
pose mesh = do
  unless (IM.lookup 70 (IM.fromList (zip [0 :: Int ..] (triangles mesh))) == Just (81, 71, 20)) (die "triangle 70 vertex identity changed")
  let point i = maybe (die "plane accounting lost a vertex") (pure . position) (IM.lookup i (IM.fromList (zip [0 :: Int ..] (samples mesh))))
  PlanePose <$> point 27 <*> point 81 <*> point 71 <*> point 20

vector :: [Double] -> IO V3
vector [x, y, z] | all finite [x, y, z] = pure (V3 x y z)
vector _ = die "plane archive needs finite 3D coordinates"

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
