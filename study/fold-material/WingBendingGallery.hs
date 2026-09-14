-- | Compare held-wing equilibria, not frames of a certified folding motion.
-- The solver owns the positions. This module measures them and sends the same
-- uncreased triangle surface to SVG, FOLD and glTF; HTML only selects results.
module WingBendingGallery (writeWingBending, wingSvg, refinement) where

import Control.Monad (forM)
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending (bendingEnergy)
import FoldMaterial (areaRatio, componentCount, resolvedTriangles)
import FoldRelaxation
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Types (FoldFile (..), Frame (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (checkLocalTriangleContact)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (View (..), basisFrom)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import UncreasedSurface
import WingBending

wingSvg :: [Surface V2] -> Either Text Text
wingSvg sheets = do
  camera <- maybe (Left "invalid wing camera") Right (basisFrom (V3 0 1 (-1)) (V3 0 0 1))
  drawing <- first explain (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = length sheets} (View (Just camera) 0) False (map surfaceFrame sheets))
  diagram <- maybe (Left "wing comparison has no geometry") Right drawing
  pure (renderSvg defaultPage {pageWidth = 1080, pageHeight = 340, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "Held wing shapes"} diagram)

writeWingBending :: FilePath -> IO ()
writeWingBending destination = do
  let output = destination </> "wing-bending"
  createDirectoryIfMissing True output
  groups <- forM [8, 16, 24] $ \count -> do
    runs <- forM [0, 20, 40 :: Int] $ \degrees -> do
      piece <- checked (first explain (wingPiece count (fromIntegral degrees)))
      result <- checked (first explain (solvePiece piece))
      mesh <- checked (first explain (finalMesh result))
      sheet <- checked (first explain (uncreasedSurface mesh))
      let stem = "wing-" ++ show count ++ "-" ++ show degrees
          title = "Wing · " <> tshow count <> " divisions · grip " <> tshow degrees <> "°"
      model <- writeSurface output stem title sheet
      report <- measure stem count degrees piece result mesh
      pure (sheet, model, report)
    drawing <- checked (wingSvg [sheet | (sheet, _, _) <- runs])
    TIO.writeFile (output </> "sequence-" ++ show count ++ ".svg") drawing
    pure runs
  benchmarks <- forM [8, 16, 24] $ \count -> do
    piece <- checked (first explain (stripBenchmark count))
    result <- checked (first explain (solvePiece piece))
    mesh <- checked (first explain (finalMesh result))
    sheet <- checked (first explain (uncreasedSurface mesh))
    let stem = "strip-" ++ show count
    model <- writeSurface output stem ("Strip benchmark · " <> tshow count <> " spans") sheet
    report <- measure stem count 30 piece result mesh
    pure (model, report)
  let runs = concat groups
      bent = [sheet | group <- groups, (sheet, _, _) <- drop 2 group]
      changes = [refinement a b | (a, b) <- zip bent (drop 1 bent)]
      document = object ["wings" .= [r | (_, _, r) <- runs], "benchmarks" .= map snd benchmarks, "refinement" .= changes]
  BL.writeFile (output </> "models.json") (encode ([m | (_, m, _) <- runs] ++ map fst benchmarks))
  BL.writeFile (output </> "checks.json") (encode document)
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/wing-bending.html"
  TIO.writeFile (destination </> "wing-bending.html") (T.replace "/*WING_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote wing-bending.html, three resolution comparisons, twelve GLBs/FOLDs and checks.json to " ++ destination)

writeSurface :: FilePath -> String -> Text -> Surface V2 -> IO Value
writeSurface output stem title sheet = do
  bytes <- checked (first explain (renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet))
  BS.writeFile (output </> stem ++ ".glb") bytes
  let file = FoldFile (Just 1.2) (Just "senbazuru controlled bending study") Nothing (Just title) Nothing [] (materialFrame sheet) []
  BL.writeFile (output </> stem ++ ".fold") (encode file)
  pure (object ["title" .= title, "path" .= (stem ++ ".glb")])

measure :: String -> Int -> Int -> BendingPiece -> Relaxation -> MaterialMesh -> IO Value
measure stem count degrees piece result mesh = do
  contact <- checked (first explain (checkLocalTriangleContact (V3 0 0 1) [] mesh))
  (crease, panel) <- checked (first explain (bendingEnergy (pieceHinges piece) mesh))
  let positions = IM.fromList (zip [0 ..] (map position (samples mesh)))
      heldError = maximum (0 : [norm (actual ^-^ target) | (i, target) <- IM.toList (piecePins piece), Just actual <- [IM.lookup i positions]])
      strains = [s | triangle <- resolvedTriangles mesh, Just s <- [principalStrains triangle]]
      referenceError = fmap (\reference -> maximum (0 : zipWith (\a b -> norm (position a ^-^ position b)) (samples mesh) (samples reference))) (pieceReference piece)
      seedChange = maximum (0 : zipWith (\a b -> norm (position a ^-^ position b)) (samples mesh) (samples (pieceMesh piece)))
  pure
    ( object
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
          "areaRatio" .= areaRatio mesh,
          "maxRelativeEdgeError" .= maxLengthError mesh,
          "heldPositionError" .= heldError,
          "minPrincipalStrain" .= minimum (0 : map fst strains),
          "maxPrincipalStrain" .= maximum (0 : map snd strains),
          "creaseEnergy" .= crease,
          "panelEnergy" .= panel,
          "referencePositionError" .= referenceError,
          "initialGuessChange" .= seedChange,
          "rootVertices" .= pieceRoot piece,
          "gripVertices" .= pieceGrip piece,
          "contact" .= contact,
          "continuousMotionChecked" .= False
        ]
    )

checked :: Either Text a -> IO a
checked = either (die . T.unpack) pure

-- Compare only matching material points: positions at different places on the
-- sheet cannot measure mesh sensitivity. The grids share at least the n=8
-- lattice, even though neither the 16 nor the 24 grid contains the other.
refinement :: Surface V2 -> Surface V2 -> Value
refinement coarse fine =
  object
    [ "fromTriangles" .= length (facesVertices (surfaceFrame coarse)),
      "toTriangles" .= length (facesVertices (surfaceFrame fine)),
      "commonVertices" .= length differences,
      "maxPositionChange" .= maximum (0 : differences)
    ]
  where
    differences = [norm (position a ^-^ position b) | a <- surfaceSamples coarse, b <- surfaceSamples fine, norm (sampleMaterial a ^-^ sampleMaterial b) < 1e-12]
