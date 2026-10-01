-- | Compare held-wing equilibria, not frames of a certified folding motion.
-- The solver owns the positions. This module measures them and sends the same
-- uncreased triangle surface to SVG, FOLD and glTF; HTML only selects results.
-- Every pose carries its paper screen ("SurfaceScreen"), as do the two-layer
-- gallery's, through 'wingScreen'. An 8-division pose takes the same grip
-- solved at 16 divisions as its finer level, where "FinerSolve" shows the two
-- are the same pose (owner decision 29).
module WingBendingGallery (writeWingBending, wingSvg, wingScreen, refinement) where

import Control.Monad (forM)
import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Types (Pair)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FinerSolve (Pending (..), finishReports, samePoint)
import FoldBending (Hinge, bendingEnergy, hingeBends)
import FoldMaterial (areaRatio, componentCount, resolvedTriangles)
import FoldRelaxation
import PaperScreen (Turning, sheetChords)
import ScreenReport (Screen (..), poseScreenKeys, thresholdsJson, writeScreenScript)
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Types (FoldFile (..), Frame (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck, checkLocalTriangleContact)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (Basis, View (..), basisFrom)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import SurfaceScreen (surfaceScreen)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import UncreasedSurface
import WingBending

wingSvg :: [Surface V2] -> Either Text Text
wingSvg sheets = do
  camera <- wingCamera
  drawing <- first explain (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = length sheets} (View (Just camera) 0) False (map surfaceFrame sheets))
  diagram <- maybe (Left "wing comparison has no geometry") Right drawing
  pure (renderSvg defaultPage {pageWidth = 1080, pageHeight = 340, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "Held wing shapes"} diagram)

-- | The camera every wing drawing is taken from, and so the picture a
-- screen's picture floor is measured in.
wingCamera :: Either Text Basis
wingCamera = maybe (Left "invalid wing camera") Right (basisFrom (V3 0 1 (-1)) (V3 0 0 1))

-- | A pose's paper screen ("SurfaceScreen") at the finer level it is given,
-- and the keys its report carries: the screen and, if the gallery draws the
-- pose, its floor in the picture, taken from 'wingCamera'. The finer level is
-- nothing, not measured, or the gallery's own finer solve's turning where
-- "FinerSolve" shows the two are the same pose. @sheet@ is the surface
-- written for the pose, @contact@ its crossing check and @hinges@ its
-- fixture's hinges.
wingScreen :: Surface V2 -> ContactCheck -> [Hinge] -> Bool -> MaterialMesh -> Maybe Turning -> Either Text (Screen, [Pair])
wingScreen sheet contact hinges drawn mesh finer = do
  chords <- first explain (sheetChords mesh)
  bends <- first explain (hingeBends hinges mesh)
  screen <- first explain (surfaceScreen sheet chords contact bends finer mesh)
  camera <- wingCamera
  pure (screen, poseScreenKeys screen chords (if drawn then Just camera else Nothing) mesh)

writeWingBending :: FilePath -> IO ()
writeWingBending destination = do
  let output = destination </> "wing-bending"
  createDirectoryIfMissing True output
  groups <- forM counts $ \count -> do
    runs <- forM grips $ \degrees -> do
      piece <- checked (first explain (wingPiece count (fromIntegral degrees)))
      result <- checked (first explain (solvePiece piece))
      mesh <- checked (first explain (finalMesh result))
      sheet <- checked (first explain (uncreasedSurface mesh))
      let stem = wingId count degrees
          title = "Wing · " <> tshow count <> " divisions · grip " <> tshow degrees <> "°"
      model <- writeSurface output stem title sheet
      -- Every wing is drawn, in its resolution's sequence.
      pending <- measure stem count degrees piece result mesh sheet True
      pure (sheet, model, pending)
    drawing <- checked (wingSvg [sheet | (sheet, _, _) <- runs])
    TIO.writeFile (output </> "sequence-" ++ show count ++ ".svg") drawing
    pure runs
  benchmarks <- forM counts $ \count -> do
    piece <- checked (first explain (stripBenchmark count))
    result <- checked (first explain (solvePiece piece))
    mesh <- checked (first explain (finalMesh result))
    sheet <- checked (first explain (uncreasedSurface mesh))
    let stem = stripId count
    model <- writeSurface output stem ("Strip benchmark · " <> tshow count <> " spans") sheet
    -- A strip is drawn only in 3D, with no camera of its own.
    pending <- measure stem count 30 piece result mesh sheet False
    pure (model, pending)
  let runs = concat groups
      bent = [sheet | group <- groups, (sheet, _, _) <- drop 2 group]
      changes = [refinement a b | (a, b) <- zip bent (drop 1 bent)]
  -- Owner decision 29: an 8-division wing's finer level may be the same grip
  -- solved at 16, on its mesh split into four. A strip holds its first and
  -- last span, which shorten as spans are added, so no two strips solve the
  -- same control.
  wingReports <- checked (finishReports [(wingId 8 g, wingId 16 g, "16 divisions") | g <- grips] [p | (_, _, p) <- runs])
  stripReports <- checked (finishReports [] (map snd benchmarks))
  let document = object ["wings" .= wingReports, "benchmarks" .= stripReports, "refinement" .= changes, "screenThresholds" .= thresholdsJson]
  BL.writeFile (output </> "models.json") (encode ([m | (_, m, _) <- runs] ++ map fst benchmarks))
  BL.writeFile (output </> "checks.json") (encode document)
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  writeScreenScript destination
  template <- TIO.readFile "study/fold-material/wing-bending.html"
  TIO.writeFile (destination </> "wing-bending.html") (T.replace "/*WING_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote wing-bending.html, three resolution comparisons, twelve GLBs/FOLDs and checks.json to " ++ destination)

-- | The wing studies' mesh divisions and grips, in degrees.
counts, grips :: [Int]
counts = [8, 16, 24]
grips = [0, 20, 40]

wingId :: Int -> Int -> Text
wingId count degrees = "wing-" <> tshow count <> "-" <> tshow degrees

stripId :: Int -> Text
stripId count = "strip-" <> tshow count

writeSurface :: FilePath -> Text -> Text -> Surface V2 -> IO Value
writeSurface output stem title sheet = do
  bytes <- checked (first explain (renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet))
  BS.writeFile (output </> T.unpack stem ++ ".glb") bytes
  let file = FoldFile (Just 1.2) (Just "senbazuru controlled bending study") Nothing (Just title) Nothing [] (materialFrame sheet) []
  BL.writeFile (output </> T.unpack stem ++ ".fold") (encode file)
  pure (object ["title" .= title, "path" .= (stem <> ".glb")])

-- | A pose's measurements, as a report that waits for its finer level. The
-- pose is screened here with that level not measured, for its own turning and
-- so that a pose the screen cannot read stops the gallery at once; its report
-- screens it again at the level 'finishReports' settles.
measure :: Text -> Int -> Int -> BendingPiece -> Relaxation -> MaterialMesh -> Surface V2 -> Bool -> IO Pending
measure stem count degrees piece result mesh sheet drawn = do
  contact <- checked (first explain (checkLocalTriangleContact (V3 0 0 1) [] mesh))
  (crease, panel) <- checked (first explain (bendingEnergy (pieceHinges piece) mesh))
  let screenAt = wingScreen sheet contact (pieceHinges piece) drawn mesh
  (own, _) <- checked (screenAt Nothing)
  let positions = IM.fromList (zip [0 ..] (map position (samples mesh)))
      heldError = maximum (0 : [norm (actual ^-^ target) | (i, target) <- IM.toList (piecePins piece), Just actual <- [IM.lookup i positions]])
      referenceError = fmap (\reference -> maximum (0 : zipWith (\a b -> norm (position a ^-^ position b)) (samples mesh) (samples reference))) (pieceReference piece)
      seedChange = maximum (0 : zipWith (\a b -> norm (position a ^-^ position b)) (samples mesh) (samples (pieceMesh piece)))
      -- FoldMaterial's areaRatio assumes a unit square. The wing and the
      -- strip each have area 0.3, so normalize by their actual material
      -- triangles instead, as the wing-layers gallery does.
      restArea = sum [abs (signedArea [sampleMaterial a, sampleMaterial b, sampleMaterial c]) | (a, b, c) <- resolvedTriangles mesh]
      report finer keys = do
        (screen, screenKeys) <- screenAt finer
        pure . object $
          [ "id" .= stem,
            "divisions" .= count,
            "gripDegrees" .= degrees,
            "converged" .= converged result,
            "iterations" .= maximum (0 : map completedIterations (checkpoints result)),
            "vertices" .= length (samples mesh),
            "triangles" .= length (triangles mesh),
            "sourcePanels" .= (1 :: Int),
            "materialCreases" .= (0 :: Int),
            "components" .= componentCount mesh,
            "areaRatio" .= (areaRatio mesh / restArea),
            "maxRelativeEdgeError" .= maxLengthError mesh,
            "heldPositionError" .= heldError,
            "minPrincipalStrain" .= negate (screenSquash screen),
            "maxPrincipalStrain" .= screenStretch screen,
            "creaseEnergy" .= crease,
            "panelEnergy" .= panel,
            "referencePositionError" .= referenceError,
            "initialGuessChange" .= seedChange,
            "rootVertices" .= pieceRoot piece,
            "gripVertices" .= pieceGrip piece,
            "contact" .= contact,
            "continuousMotionChecked" .= False
          ]
            ++ screenKeys
            ++ keys
  pure (Pending stem (piecePins piece) mesh (screenTurning own) report)

checked :: Either Text a -> IO a
checked = either (die . T.unpack) pure

-- Compare only matching material points, within the 'samePoint' the finer
-- solve's check matches by: positions at different places on the sheet cannot
-- measure mesh sensitivity. The grids share at least the n=8 lattice, even
-- though neither the 16 nor the 24 grid contains the other.
refinement :: Surface V2 -> Surface V2 -> Value
refinement coarse fine =
  object
    [ "fromTriangles" .= length (facesVertices (surfaceFrame coarse)),
      "toTriangles" .= length (facesVertices (surfaceFrame fine)),
      "commonVertices" .= length differences,
      "maxPositionChange" .= maximum (0 : differences)
    ]
  where
    differences = [norm (position a ^-^ position b) | a <- surfaceSamples coarse, b <- surfaceSamples fine, norm (sampleMaterial a ^-^ sampleMaterial b) <= samePoint]
