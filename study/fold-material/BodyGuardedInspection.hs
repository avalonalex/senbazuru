-- | Locate the saved 14–55 refusal without moving paper or adding a guard.
-- Both triangles already straddle the other's plane in the passing start.
-- Their finite intersection, however, is initially shorter than the crossing
-- tolerance. The refused trial lengthens it past that threshold. A locally
-- active overlap guard predicts no loss, while its actual moving corner does
-- worsen. Show those separate measurements before proposing another policy.
--
-- The source order puts 55 below 14. Triangle ids, physical source panels and
-- contact-corner order all come from the authenticated saved mesh. Paper SVGs
-- and FOLD files retain their bytes; the new drawings are annotations only.
module BodyGuardedInspection (writeBodyGuardedInspection) where

import BodyContactDiagnosis
import BodyContactDirection (contactGuard)
import BodyContactGallery (boxAround)
import BodyCorrectionArchive
import BodyDirectionGallery (pairWitnesses, rowValue)
import BodyFourthArchive
import BodyPatch
import BodyPlaneGuard
import BodyPlaneGuardGallery (trianglePoints, xy)
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact qualified as F
import Senbazuru.Diagram
import Senbazuru.Fold.Types (unFaceId)
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (panelTolerance)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))
import System.IO (hFlush, stdout)

data Inspection = Inspection FourthState PairSection [C.ContactWitness]

writeBodyGuardedInspection :: FilePath -> FilePath -> IO ()
writeBodyGuardedInspection source destination = do
  let output = destination </> "body-contact-14-55"
  separateOutput source output
  putStrLn "Authenticate both saved directions, then inspect 14–55 without solving."
  hFlush stdout
  archive <- readFourthArchive source
  initialState <- case [s | s <- fourthStates archive, fourthName s == "start"] of [s] -> pure s; _ -> die "missing saved start"
  let study = fourthStudy archive
      fixture = patchSpread study
      start = fourthMesh initialState
      pins = spreadPins fixture
      direction = fourthDirection archive
  proposal <- field "proposal" direction >>= traverse vector
  let delta = IM.fromList (zip [0 ..] (zipWith (\p q -> q ^-^ position p) (samples start) proposal))
      change g = sum [dot v (IM.findWithDefault (V3 0 0 0) i delta) | (i, v) <- IM.toList g]
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  initial <- pairWitnesses (14, 55) <$> checked (C.contactWitnesses model start)
  let rows = map (contactGuard pins . C.witnessRow) initial
      identity w = (C.witnessTriangles w, map fst (F.contactGradient (C.witnessRow w)))
  savedGuards <- field "guards" direction :: IO [Value]
  unless (length initial == 4 && all ((== (55, 14)) . C.witnessTriangles) initial && take 4 (drop 4 savedGuards) == map rowValue rows) (die "expected four saved 55-below-14 guards in rows 4–7")
  inspected <- forM (sortOn fourthScale (fourthStates archive)) $ \s -> do
    cut <- checked (pairSection (fourthMesh s) (14, 55))
    ws <- pairWitnesses (14, 55) <$> checked (C.contactWitnesses model (fourthMesh s))
    unless (map identity initial == map identity ws) (die "saved overlap corner identities changed")
    pure (Inspection s cut ws)
  trianglesIds <- traverse (lookupId "triangle" (triangles start)) [14, 55]
  let ids = zip [14, 55 :: Int] (map triple trianglesIds)
  identities <- forM ids $ \(t, vs) -> do
    owner <- lookupId "panel" (refinedPanels (spreadRefined fixture)) t
    original <- lookupId "crane face" (patchFaces study) (unFaceId owner)
    materials <- forM vs $ \v -> do
      p <- lookupId "sample" (samples start) v
      let V2 u w = sampleMaterial p
      pure (object ["vertex" .= v, "material" .= [u, w], "held" .= IM.member v pins])
    pure (object ["triangle" .= t, "vertices" .= vs, "panel" .= unFaceId owner, "craneFace" .= unFaceId original, "materialVertices" .= materials])
  points <- concat <$> traverse (trianglePoints start) [14, 55]
  let pairBox = boxAround (map xy points)
      -- Only corner zero and the finite intersections set this close-up. Other
      -- corners are far away and would hide the tiny segment change.
      tipBox = boxAround [xy p | Inspection _ cut ws <- inspected, p <- intersectionEnds cut ++ map C.witnessLower (take 1 ws)]
      materialBox = boxAround [sampleMaterial p | (_, vs) <- ids, v <- vs, Just p <- [IM.lookup v (IM.fromList (zip [0 ..] (samples start)))]]
  createDirectoryIfMissing True output
  forM_ (fourthFiles archive) $ \(n, b) -> do
    let path = output </> "source" </> n
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path b
  entries <- forM inspected $ \(Inspection s cut ws) -> do
    let name = fourthName s
        mesh = fourthMesh s
        scale = fourthScale s
    forM_ (".fold" : ["-" ++ v ++ ".svg" | v <- ["side", "top", "underside", "material"]]) $ \suffix ->
      readArchiveBytes (source </> fourthSource s ++ suffix) >>= BL.writeFile (output </> name ++ suffix)
    forM_ [("pair", pairBox), ("tip", tipBox)] $ \(view, bounds) -> drawInspection bounds mesh cut ws >>= TIO.writeFile (output </> name ++ "-" ++ view ++ ".svg")
    planes <- forM [(v, other) | (t, vs) <- ids, let { other = if t == 14 then 55 else 14 }, v <- vs] $ \(v, t) -> do
      a <- checked (measurePlane start v t)
      b <- checked (measurePlane mesh v t)
      let predicted = planeDistance a + scale * change (planeGradient a)
      pure (object ["vertex" .= v, "triangle" .= t, "distance" .= planeDistance b, "predicted" .= predicted, "remainder" .= (planeDistance b - predicted), "derivative" .= rowValue (planeGradient b, planeDistance b), "initialDerivative" .= rowValue (planeGradient a, planeDistance a)])
    let corners =
          [ let gap0 = F.contactGap (C.witnessRow w0)
                gap = F.contactGap (C.witnessRow w)
                predicted = gap0 + scale * change (fst row)
                predictedMargin = snd row + scale * change (fst row)
                actualMargin = gap - min 0 gap0
                remainder = gap - predicted
             in object ["index" .= k, "guardIndex" .= (k + 4), "gap" .= gap, "initialGap" .= gap0, "predictedGap" .= predicted, "predictedMargin" .= predictedMargin, "actualMargin" .= actualMargin, "remainder" .= remainder, "remainderPerScaleSquared" .= (if scale == 0 then Nothing else Just (remainder / (scale * scale))), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "derivative" .= rowValue (contactGuard pins (C.witnessRow w)), "predictedGuardPasses" .= (predictedMargin >= -1e-12), "actualFloorPreserved" .= (actualMargin >= -1e-12)]
            | (k, (w0, row, w)) <- zip [0 :: Int ..] (zip3 initial rows ws)
          ]
    pure (object ["id" .= name, "title" .= fourthTitle s, "sourceFile" .= (fourthSource s ++ ".fold"), "scale" .= scale, "record" .= fourthRecord s, "planes" .= planes, "firstDistances" .= firstDistances cut, "secondDistances" .= secondDistances cut, "firstStraddles" .= straddles (firstDistances cut), "secondStraddles" .= straddles (secondDistances cut), "crosses" .= sectionCrosses cut, "intersection" .= map xyz (intersectionEnds cut), "intersectionLength" .= intersectionLength cut, "intersectionMargin" .= (intersectionLength cut - panelTolerance), "corners" .= corners])
  let flat = start {samples = [p {position = let V2 u v = sampleMaterial p in V3 u v 0} | p <- samples start]}
  drawMaterial materialBox flat >>= TIO.writeFile (output </> "material-pair.svg")
  let result = object ["gallery" .= ("body-contact-14-55" :: Text), "issue" .= (366 :: Int), "newSolves" .= (0 :: Int), "newRepairs" .= (0 :: Int), "sourceStart" .= ("start.fold" :: Text), "startPositions" .= map (xyz . position) (samples start), "savedDirection" .= map xyz proposal, "initialGuards" .= map rowValue rows, "identities" .= identities, "lowerTriangle" .= (55 :: Int), "upperTriangle" .= (14 :: Int), "contactTolerance" .= panelTolerance, "guardResidualTolerance" .= (1e-12 :: Double), "drawingScale" .= (600 :: Double), "tipBounds" .= boxValue tipBox, "pairBounds" .= boxValue pairBox, "states" .= entries, "continuousMotionChecked" .= False, "wholeCraneChecked" .= False]
      bytes = encode result
  BL.writeFile (output </> "checks.json") bytes
  template <- TIO.readFile "study/fold-material/body-contact-14-55.html"
  TIO.writeFile (destination </> "body-contact-14-55.html") (T.replace "/*BODY_GUARDED_DATA*/null" (TE.decodeUtf8 (BL.toStrict bytes)) template)
  putStrLn ("Wrote " ++ destination </> "body-contact-14-55.html")

drawInspection :: Box -> MaterialMesh -> PairSection -> [C.ContactWitness] -> IO Text
drawInspection bounds mesh cut ws = do
  rings <- pairRings mesh
  let marks = [Offset (V2 (-4) 4) (Label (Colour "#177970") 12 (xy (C.witnessLower w)) "●") | w <- ws]
      label = [Offset (V2 8 (-10)) (Label (Colour "#177970") 13 (xy (C.witnessLower w)) "Corner 0") | w <- take 1 ws]
  pure (renderSvg page (diagramWithExtent bounds (rings ++ [line "#b82643" 3 (map xy (intersectionEnds cut))] ++ marks ++ label)))

drawMaterial :: Box -> MaterialMesh -> IO Text
drawMaterial bounds mesh = do
  rings <- pairRings mesh
  labels <- forM [14, 55] $ \t -> do
    ps <- trianglePoints mesh t
    let centre = (1 / 3) *^ foldr (^+^) (V3 0 0 0) ps
    pure (Label (Colour "#303630") 14 (xy centre) (T.pack (show t)))
  pure (renderSvg page (diagramWithExtent bounds (rings ++ labels)))

pairRings :: MaterialMesh -> IO [Shape]
pairRings mesh = forM [(14, "#7056a2"), (55, "#c98225")] $ \(t, c) -> do
  ps <- trianglePoints mesh t
  pure (line c 1.4 (map xy (ps ++ take 1 ps)))

page :: Page
page = defaultPage {pageWidth = 560, pageHeight = 440, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "14 purple, 55 orange, overlap corners green, intersection red"}

line :: Text -> Double -> [V2] -> Shape
line c width = Polyline (solid (Colour c) width)

straddles :: [Double] -> Bool
straddles ds = any (< -panelTolerance) ds && any (> panelTolerance) ds

lookupId :: String -> [a] -> Int -> IO a
lookupId label values i = maybe (die ("missing " ++ label ++ " " ++ show i)) pure (IM.lookup i (IM.fromList (zip [0 ..] values)))

triple :: (Int, Int, Int) -> [Int]
triple (a, b, c) = [a, b, c]

boxValue :: Box -> [[Double]]
boxValue (Box (V2 a b) (V2 c d)) = [[a, b], [c, d]]

vector :: [Double] -> IO V3
vector [x, y, z] = pure (V3 x y z)
vector _ = die "saved proposal needs three coordinates"
