-- | Show what contact correction achieves on a small, independently measured
-- fixture. A numerical pass and exact lower/upper order are separate fields.
-- All exported shapes are diagnostic endpoints, never a folding animation.
-- The penetration plots clip away nonnegative gaps BEFORE normalizing their
-- vertical scale, so a tiny residual remains visible beside a large input error.
module CreaseCorrectionGallery (writeCreaseCorrection) where

import ClosedCrease
import Control.Exception (evaluate)
import Control.Monad (forM)
import CreaseCorrection
import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Key qualified as Key
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
import FoldRelaxation
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), num)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Svg
import SparseSolve (LinearReport (..))
import SurfaceContact qualified as Contact
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)

controls :: [(String, Text, CorrectionControl)]
controls = [("touching", "Touching start", ReferenceStart), ("penetrating", "Penetrating start", PenetratingGuess), ("without-contact", "Same start, no contact forces", WithoutContact), ("tiny", "Tiny penetration", TinyPenetration), ("conflicting", "Conflicting hold", ConflictingHold)]

writeCreaseCorrection :: FilePath -> IO ()
writeCreaseCorrection destination = do
  let output = destination </> "crease-correction"
  createDirectoryIfMissing True output
  runs <- forM [(n, entry) | n <- [1, 2], entry <- controls] $ \(n, (key, title, control)) -> do
    fixture <- checked (creaseCorrection n control)
    let stem = key ++ "-" ++ show n
        seed = correctionSeed fixture
        reference = correctionReference fixture
    putStrLn ("Solving " ++ stem)
    hFlush stdout
    start <- getCPUTime
    (result, audit) <- checked (solveCorrection (Settings 40 1e-5) fixture)
    mesh <- checked (finalMesh result)
    _ <- evaluate (maxLengthError mesh + if converged result then 1 else 0)
    finish <- getCPUTime
    stages <- forM [("before", seed), ("after", mesh)] $ \(stage, current) -> do
      (report, gaps) <- measure fixture current
      sheet <- checked (correctionSurface fixture current)
      let name = stem ++ "-" ++ stage
          label = "Diagnostic · " <> title <> " · " <> T.pack stage
      TIO.writeFile (output </> name ++ "-gap.svg") (penetrationSvg gaps)
      BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru crease contact correction") Nothing (Just label) Nothing [] (materialFrame sheet) []))
      -- CompletePaper preserves all triangles, including failed controls.
      -- GLB rounds coordinates for display; the exact gap is measured before
      -- packing and must never be inferred from a clean-looking model.
      bytes <- checked (renderSurfaceGlb defaultBudget CompletePaper (Just label) sheet)
      BS.writeFile (output </> name ++ ".glb") bytes
      pure (stage, report, object ["title" .= (label <> " · " <> T.pack (show (32 * n)) <> " triangles"), "path" .= (name ++ ".glb")])
    (_, finalGap) <- measure fixture mesh
    (angleErrorMax, _) <- creaseAngles fixture mesh
    contact <- checked (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] (closedOwners reference) mesh)
    let within = converged result && maxLengthError mesh <= 1e-5 && heldError fixture mesh == 0 && angleErrorMax <= 1e-5 && contactPassed contact
        report =
          object
            [ "id" .= stem,
              "control" .= key,
              "title" .= title,
              "subdivision" .= n,
              "triangles" .= length (triangles mesh),
              "vertices" .= length (samples mesh),
              "components" .= componentCount mesh,
              "sharedCreaseVertices" .= closedRoot reference,
              "heldVertices" .= IM.keys (correctionPins fixture),
              "contactForcesUsed" .= correctionForces fixture,
              "converged" .= converged result,
              "withinNumericalTolerances" .= within,
              "exactLowerUpperOrder" .= (minimumGap finalGap >= 0),
              "iterations" .= maximum (0 : map completedIterations (checkpoints result)),
              "iterationLimitPerStage" .= (40 :: Int),
              "equilibrium" .= fmap equilibrium (equilibriumCheck result),
              "blockedStages" .= maybe [] (map blocked . blockedStages) audit,
              "rejections" .= maybe [] (map rejection . rejectionSummaries) audit,
              "measurements" .= object [Key.fromString stage .= r | (stage, r, _) <- stages],
              "solveCpuSeconds" .= (fromIntegral (finish - start) / 1e12 :: Double),
              "continuousMotionChecked" .= False
            ]
    putStrLn (stem ++ ": converged " ++ show (converged result) ++ ", within tolerances " ++ show within ++ ", exact minimum gap " ++ show (fromRational (minimumGap finalGap) :: Double))
    hFlush stdout
    pure (report, [m | (_, _, m) <- stages])
  let document = object ["runs" .= map fst runs]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode (concatMap snd runs))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/crease-correction.html"
  TIO.writeFile (destination </> "crease-correction.html") (T.replace "/*CORRECTION_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote crease-correction.html, twenty diagnostic FOLDs/GLBs and exact gap measurements to " ++ destination)

measure :: CreaseCorrection -> MaterialMesh -> IO (Value, GapAudit)
measure fixture mesh = do
  gaps <- checked (auditLowerGap fixture mesh)
  contact <- checked (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] owners mesh)
  rows <- checked (Contact.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1)] owners mesh >>= (`Contact.orderedContacts` mesh))
  (angleErrorMax, angles) <- creaseAngles fixture mesh
  pure (object ["minGap" .= rational (minimumGap gaps), "maxGap" .= rational (maximumGap gaps), "maxRelativeEdgeError" .= maxLengthError mesh, "heldPositionError" .= heldError fixture mesh, "creaseRadians" .= angles, "maxCreaseErrorRadians" .= angleErrorMax, "contact" .= contact, "minForceGap" .= minimum (0 : map contactGap rows), "forceRows" .= length rows, "penetrationPlotScale" .= penetrationScale gaps], gaps)
  where
    owners = closedOwners (correctionReference fixture)
    rational r = object ["exact" .= show r, "value" .= (fromRational r :: Double)]

creaseAngles :: CreaseCorrection -> MaterialMesh -> IO (Double, [Double])
creaseAngles fixture mesh = do
  let vertices = IM.fromList (zip [0 ..] (samples mesh))
  angles <- mapM (checked . (`hingeAngle` vertices)) [h | h <- closedHinges (correctionReference fixture), SurfaceCrease _ <- [hingeRole h]]
  pure (maximum (0 : [abs (angleError a pi) | (a, _) <- angles]), map fst angles)

heldError :: CreaseCorrection -> MaterialMesh -> Double
heldError fixture mesh = maximum (0 : IM.elems (IM.intersectionWith (\a b -> norm (a ^-^ b)) (correctionPins fixture) (IM.fromList (zip [0 ..] (map position (samples mesh))))))

equilibrium :: EquilibriumCheck -> Value
equilibrium check = let linear = equilibriumLinear check in object ["linearConverged" .= linearConverged linear, "linearResidual" .= linearResidual linear, "linearThreshold" .= linearThreshold linear, "linearIterations" .= linearIterations linear, "fullMovement" .= equilibriumMovement check, "movementThreshold" .= (1e-7 :: Double)]

blocked :: BlockedStage -> Value
blocked stage = object ["iteration" .= blockedIteration stage, "lengthWeight" .= blockedLengthWeight stage]

rejection :: RejectionSummary -> Value
rejection summary = object ["kind" .= show (rejectionKind summary), "count" .= rejectionCount summary, "firstReason" .= explain (trialReason (firstRejection summary)), "lastReason" .= explain (trialReason (lastRejection summary))]

penetrationScale :: GapAudit -> Double
penetrationScale gaps = max 1e-12 (abs (fromRational (minimumGap gaps)))

-- The horizontal axis still measures folded x. The vertical axis shows only
-- penetration, enlarged separately per plot. Clip in exact gap coordinates
-- before conversion; clamping the corners alone would invent straight edges.
penetrationSvg :: GapAudit -> Text
penetrationSvg gaps = renderSvg defaultPage {pageWidth = 560, pageHeight = 270, pageMargin = 20, pageBackground = Nothing, pageTitle = Just "Negative gaps only; vertical scale magnified"} (diagramWithExtent extent shapes)
  where
    extent = Box (V2 (-0.03) (-0.19)) (V2 0.54 0.065)
    scale = penetrationScale gaps
    pieces = [map (\(x, g) -> V2 (fromRational x) (0.12 * fromRational g / scale)) clipped | polygon <- gapPolygons gaps, let clipped = negativePart polygon, any ((< 0) . snd) clipped]
    shapes =
      [ Fill (Colour "#ebc7b2") pieces,
        Polyline (solid (Colour "#a49b8b") 1) [V2 0 0, V2 0.5 0],
        Label (Colour "#70685b") 12 (V2 0 0.025) "0 · touching or separated",
        Label (Colour "#b35836") 12 (V2 0 (-0.16)) (if minimumGap gaps < 0 then "minimum −" <> num (abs (fromRational (minimumGap gaps))) <> " sheet lengths" else "No negative gap"),
        Label (Colour "#70685b") 12 (V2 0.4 (-0.16)) "folded x →"
      ]
        ++ [Polyline (solid (Colour "#b35836") 1) (ps ++ take 1 ps) | ps <- pieces]
    negativePart ps = concatMap edge (zip ps (drop 1 ps ++ take 1 ps))
    edge ((x, a), q@(y, b))
      | a <= 0 && b <= 0 = [q]
      | a > 0 && b > 0 = []
      | otherwise = let hit = (x + a * (y - x) / (a - b), 0) in if b <= 0 then [hit, q] else [hit]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
