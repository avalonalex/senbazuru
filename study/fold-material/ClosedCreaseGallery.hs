-- | Compare prescribed contact geometry with an exact profile reference.
-- Rendering and contact deliberately have separate jobs: microscopic gaps
-- remain in FOLD and measurements, but cannot survive the GLB packing quantum.
-- The optional crane recheck reads saved endpoints and never reruns their solves.
module ClosedCreaseGallery (writeClosedCrease, writeCraneRecheck) where

import ClosedCrease
import Control.Monad (forM, unless)
import CraneInternal
import CraneRoot (rootSpread)
import CraneSpread
import Data.Aeson (encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldContact (contactGap)
import FoldMaterial (componentCount)
import FoldRelaxation (maxLengthError)
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), num)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Svg
import SurfaceContact qualified as Contact
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

controls :: [(String, Text, CreaseShape)]
controls = [("flat", "Flat, touching", FlatTouching), ("touching", "Bent, touching", BentTouching), ("open", "Small opening", Open), ("open-sliver", "Microscopic opening", OpenSliver), ("crossed", "Crossed panels", Crossed), ("crossed-sliver", "Microscopic crossing", CrossedSliver), ("wrong-side", "Reversed order", WrongSide)]

writeClosedCrease :: FilePath -> IO ()
writeClosedCrease destination = do
  let output = destination </> "closed-crease"
  createDirectoryIfMissing True output
  runs <- forM [(n, entry) | n <- [1, 2], entry <- controls] $ \(n, (key, title, shape)) -> do
    fixture <- checked (closedCrease n shape)
    sheet <- checked (closedSurface fixture)
    let stem = key ++ "-" ++ show n
        mesh = closedMesh fixture
        direction = V3 0 0 1
        orders = [(FaceId 0, FaceId 1)]
        points = IM.fromList (zip [0 ..] (samples mesh))
        gaps = profileGaps fixture
        heights = map snd gaps
        -- A graph normalized in Haskell preserves a microscopic gap that SVG's
        -- ordinary model-coordinate formatting would otherwise round to zero.
        gapScale = maximum (1e-8 : map (abs . fromRational) heights)
        idealOrdered = all (>= 0) heights
    contact <- checked (checkTriangleContact direction orders (closedOwners fixture) mesh)
    rows <- checked (Contact.prepareContact 0 direction orders (closedOwners fixture) mesh >>= (`Contact.orderedContacts` mesh))
    angles <- mapM (checked . (`hingeAngle` points)) [h | h <- closedHinges fixture, SurfaceCrease _ <- [hingeRole h]]
    TIO.writeFile (output </> stem ++ "-profile.svg") (profileSvg fixture)
    TIO.writeFile (output </> stem ++ "-gap.svg") (gapSvg gapScale fixture)
    BL.writeFile (output </> stem ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru closed-crease diagnostic") Nothing (Just title) Nothing [] (materialFrame sheet) []))
    let hasModel = shape `elem` [FlatTouching, BentTouching, Open] && idealOrdered && contactPassed contact
    models <-
      if hasModel
        then do
          bytes <- checked (renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet)
          BS.writeFile (output </> stem ++ ".glb") bytes
          pure [object ["title" .= (title <> " · " <> T.pack (show (32 * n)) <> " triangles"), "path" .= (stem ++ ".glb")]]
        else pure []
    let rational r = object ["exact" .= show r, "value" .= (fromRational r :: Double)]
        report =
          object
            [ "id" .= stem,
              "shape" .= key,
              "title" .= title,
              "subdivision" .= n,
              "vertices" .= length (samples mesh),
              "triangles" .= length (triangles mesh),
              "components" .= componentCount mesh,
              "sharedCreaseVertices" .= closedRoot fixture,
              "maxRelativeEdgeError" .= maxLengthError mesh,
              "creaseDegrees" .= [a * 180 / pi | (a, _) <- angles],
              "minGap" .= rational (minimum heights),
              "maxGap" .= rational (maximum heights),
              "profileCrossings" .= map rational (profileCrossings fixture),
              "idealOrdered" .= idealOrdered,
              "contact" .= contact,
              "minForceGap" .= minimum (0 : map contactGap rows),
              "forceRows" .= length rows,
              "gapPlotScale" .= gapScale,
              "hasModel" .= hasModel,
              "profiles" .= object ["lower" .= [[rational x, rational z] | (x, z) <- lowerProfile fixture], "upper" .= [[rational x, rational z] | (x, z) <- upperProfile fixture]],
              "equilibriumSolved" .= False,
              "continuousMotionChecked" .= False
            ]
    pure (report, models)
  let document = object ["runs" .= map fst runs]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode (concatMap snd runs))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  -- The surrounding page already supplies the introduction. A compact header
  -- and fixed canvas height keep the whole model visible inside its iframe.
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/closed-crease.html"
  TIO.writeFile (destination </> "closed-crease.html") (T.replace "/*CLOSED_CREASE_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote closed-crease.html, fourteen profile/gap comparisons, six GLBs and fourteen diagnostic FOLDs to " ++ destination)

-- Both profile axes have the same physical scale. Dashed upper strokes let
-- the lower remain visible when the two profiles coincide exactly.
profileSvg :: ClosedCrease -> Text
profileSvg fixture =
  plot
    (Box (V2 (-0.03) (-0.04)) (V2 0.54 0.24))
    "Side profile, equal x and z scales"
    [ Polyline (solid (Colour "#d3cbbb") 1) [V2 0 0, V2 0.5 0],
      Polyline (solid (Colour "#397f88") 4) (points (lowerProfile fixture)),
      Polyline (Stroke (Colour "#b35836") 2 (Dash [6, 4])) (points (upperProfile fixture)),
      Polyline (solid (Colour "#292d28") 1.5) [V2 0 (-0.01), V2 0 0.01],
      Label (Colour "#70685b") 12 (V2 0 (-0.025)) "crease",
      Label (Colour "#70685b") 12 (V2 0.43 (-0.025)) "x = 0.5"
    ]
  where
    points = map (\(x, z) -> V2 (fromRational x) (fromRational z))

gapSvg :: Double -> ClosedCrease -> Text
gapSvg scale fixture =
  plot
    (Box (V2 (-0.03) (-0.17)) (V2 0.54 0.17))
    "Upper minus lower height, magnified vertical scale"
    [ Polyline (solid (Colour "#a49b8b") 1) [V2 0 0, V2 0.5 0],
      Polyline (solid (Colour "#b35836") 2) [V2 (fromRational x) (0.12 * fromRational gap / scale) | (x, gap) <- profileGaps fixture],
      Label (Colour "#70685b") 12 (V2 0 0.145) ("+" <> num scale),
      Label (Colour "#70685b") 12 (V2 0 (-0.145)) ("−" <> num scale),
      Label (Colour "#70685b") 12 (V2 0.51 0) "0"
    ]

plot :: Box -> Text -> [Shape] -> Text
plot extent title shapes = renderSvg defaultPage {pageWidth = 560, pageHeight = 300, pageMargin = 18, pageBackground = Nothing, pageTitle = Just title} (diagramWithExtent extent shapes)

-- | Recheck the six archived #215 endpoint FOLDs without changing positions,
-- holds or solver history. Failure to find an input is an error, never a skip.
writeCraneRecheck :: FilePath -> FilePath -> IO ()
writeCraneRecheck sourceDirectory destination = do
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  reports <- forM [("original", OriginalPatch), ("held", HeldLines), ("internal", InternalForces), ("held-internal", HeldLinesInternalForces), ("fixed", FixedPatch), ("continued", ContinuedPatch)] $ \(key, control) -> do
    fixture <- rootSpread . internalRoot <$> checked (internalStudy source control)
    frame <- keyFrame <$> (loadFoldFile (sourceDirectory </> key ++ ".fold") >>= checked)
    sheet <- checked (surfaceFromFrame frame >>= requireMaterialCoordinates)
    let reference = spreadMesh fixture
        mesh = reference {samples = surfaceSamples sheet}
    unless (facesVertices frame == [map VertexId [a, b, c] | (a, b, c) <- triangles reference] && map sampleMaterial (samples mesh) == map sampleMaterial (samples reference)) (die "crane recheck requires the saved diagnostic's unchanged material and triangle identities")
    contact <- checked (spreadCheck fixture mesh)
    putStrLn (key ++ ": " ++ show (length (crossingPanels contact)) ++ " crossings, " ++ show (length (reversedOrders contact)) ++ " reversed orders, " ++ show (length (unorderedContacts contact)) ++ " unordered pairs")
    pure (object ["id" .= key, "source" .= (sourceDirectory </> key ++ ".fold"), "contact" .= contact, "maxRelativeEdgeError" .= maxLengthError mesh, "solveRepeated" .= False])
  createDirectoryIfMissing True (destination </> "closed-crease")
  BL.writeFile (destination </> "closed-crease" </> "crane-recheck.json") (encode (object ["runs" .= reports]))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
