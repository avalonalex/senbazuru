-- | Inspect 55–93 in the saved final repair-loop attempt; move no paper.
-- Triangle 55's vertex 30 crosses the extended plane of triangle 93 while
-- the projected-overlap gaps stay within tolerance. The declared order is
-- 93 BELOW 55, so a gap is 55's height minus 93's, regardless of id order.
-- Read that order from the existing witnesses, never infer it from the camera.
--
-- Compare contact derivatives along the SAVED direction without adding guards
-- or solving. A hypothetical overlap inequality is a diagnostic prediction,
-- not evidence that a newly constrained direction would pass actual geometry.
-- The shared archive reader validates the entire chain before output. All
-- source paper files are copied verbatim; new drawings only annotate them.
module BodyPairInspectionGallery (writeBodyPairInspection) where

import BodyContactDiagnosis
import BodyContactDirection (contactGuard)
import BodyContactGallery (boxAround)
import BodyCorrectionArchive
import BodyDirectionGallery (pairWitnesses, rowValue)
import BodyLoopArchive
import BodyPatch
import BodyPlaneGuard
import BodyPlaneGuardGallery (trianglePoints, vertexAt, xy)
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
import Senbazuru.Geometry.Polygon (distanceOutside, signedArea)
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

data Inspected = Inspected LoopState PairSection [C.ContactWitness] V3 PlaneMeasure Double

writeBodyPairInspection :: FilePath -> FilePath -> IO ()
writeBodyPairInspection source destination = do
  let output = destination </> "body-contact-55-93"
  separateOutput source output
  putStrLn "Validate the saved repair loop, then inspect 55–93 without solving."
  hFlush stdout
  archive <- readLoopArchive source
  let study = loopStudy archive
      fixture = patchSpread study
      pins = spreadPins fixture
      states = sortOn loopScale (loopStates archive)
  before <- case [s | s <- states, loopName s == "before"] of
    [s] -> pure s
    _ -> die "missing start of final attempt"
  proposal <- field "proposal" (loopAttempt archive) >>= traverse vector
  let start = loopMesh before
      delta = IM.fromList (zip [0 ..] (zipWith (\p q -> q ^-^ position p) (samples start) proposal))
      change gradient = sum [dot g (IM.findWithDefault (V3 0 0 0) i delta) | (i, g) <- IM.toList gradient]
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  initial <- pairWitnesses (55, 93) <$> checked (C.contactWitnesses model start)
  initialPlane <- checked (measurePlane start 30 93)
  let initialRows = map (contactGuard pins . C.witnessRow) initial
      witnessIdentity w = (C.witnessTriangles w, map fst (F.contactGradient (C.witnessRow w)))
  unless (length initial == 6 && all ((== (93, 55)) . C.witnessTriangles) initial) (die "expected six ordered corners with 93 below 55")
  inspected <- forM states $ \state -> do
    let mesh = loopMesh state
    cut <- checked (pairSection mesh (55, 93))
    ws <- pairWitnesses (55, 93) <$> checked (C.contactWitnesses model mesh)
    unless (map witnessIdentity initial == map witnessIdentity ws) (die "saved pair changed overlap corner identities")
    vertex <- vertexAt mesh 30
    plane <- checked (measurePlane mesh 30 93)
    points <- trianglePoints mesh 93
    let outline = map xy points
        outside = distanceOutside (if signedArea outline < 0 then reverse outline else outline) (xy vertex)
    pure (Inspected state cut ws vertex plane outside)
  identity <- forM [55, 93] $ \i -> do
    owner <- lookupId "source panel" i (refinedPanels (spreadRefined fixture))
    sourceFace <- lookupId "crane face" (unFaceId owner) (patchFaces study)
    (a, b, c) <- lookupId "triangle" i (triangles start)
    materials <- forM [a, b, c] $ \v -> do
      p <- lookupId "sample" v (samples start)
      let V2 x y = sampleMaterial p
      pure (object ["vertex" .= v, "material" .= [x, y], "held" .= IM.member v pins])
    pure (object ["triangle" .= i, "panel" .= unFaceId owner, "craneFace" .= unFaceId sourceFace, "vertices" .= [a, b, c], "materialVertices" .= materials])
  constraints <- field "constraints" (loopAttempt archive) :: IO [Value]
  oldPairs <- traverse (field "triangles") constraints :: IO [[Int]]
  unless (all (\p -> p /= [55, 93] && p /= [93, 55]) oldPairs) (die "pair is already in the saved quadratic guards")
  points <- concat <$> traverse (trianglePoints start) [55, 93]
  let pairBox = boxAround (map xy points)
      tipBox = boxAround [xy p | Inspected _ cut ws vertex _ _ <- inspected, p <- vertex : intersectionEnds cut ++ [C.witnessLower w | w <- ws, abs (F.contactGap (C.witnessRow w)) < panelTolerance]]
      materialBox = boxAround [sampleMaterial p | i <- [55, 93], Just (a, b, c) <- [IM.lookup i (IM.fromList (zip [0 ..] (triangles start)))], v <- [a, b, c], Just p <- [IM.lookup v (IM.fromList (zip [0 ..] (samples start)))]]
  createDirectoryIfMissing True output
  forM_ (loopFiles archive) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  entries <- forM inspected $ \item@(Inspected state cut ws _ plane outside) -> do
    let name = loopName state
        mesh = loopMesh state
        scale = loopScale state
    -- Paper assets keep the original bytes, not re-serialized equivalents.
    forM_ (".fold" : ["-" ++ view ++ ".svg" | view <- ["side", "top", "underside", "material"]]) $ \suffix -> BL.readFile (source </> loopSource state ++ suffix) >>= BL.writeFile (output </> name ++ suffix)
    forM_ [("pair", pairBox), ("tip", tipBox)] $ \(view, box) -> drawInspection box item >>= TIO.writeFile (output </> name ++ "-" ++ view ++ ".svg")
    let predicted = [F.contactGap (C.witnessRow w) + scale * change (fst row) | (w, row) <- zip initial initialRows]
        margins = [snd row + scale * change (fst row) | row <- initialRows]
        costs = [5e9 * min 0 (F.contactGap (C.witnessRow w)) ^ (2 :: Int) | w <- ws]
    firstIds <- lookupId "triangle" 55 (triangles mesh)
    secondIds <- lookupId "triangle" 93 (triangles mesh)
    pure
      ( object
          [ "id" .= name,
            "title" .= loopTitle state,
            "sourceFile" .= (loopSource state ++ ".fold"),
            "scale" .= scale,
            "record" .= loopRecord state,
            "firstVertices" .= triple firstIds,
            "secondVertices" .= triple secondIds,
            "firstDistances" .= firstDistances cut,
            "secondDistances" .= secondDistances cut,
            "firstStraddles" .= straddles (firstDistances cut),
            "secondStraddles" .= straddles (secondDistances cut),
            "crosses" .= sectionCrosses cut,
            "sectionFirst" .= map xyz (sectionFirst cut),
            "sectionSecond" .= map xyz (sectionSecond cut),
            "intersection" .= map xyz (intersectionEnds cut),
            "intersectionLength" .= intersectionLength cut,
            "vertex30PlaneDistance" .= planeDistance plane,
            "planeThresholdMargin" .= (planeDistance plane + panelTolerance),
            "predictedPlaneDistance" .= (planeDistance initialPlane + scale * change (planeGradient initialPlane)),
            "vertex30OutsideDistance" .= outside,
            "planeDerivative" .= rowValue (planeGradient plane, planeDistance plane),
            "minimumGap" .= minimum (map (F.contactGap . C.witnessRow) ws),
            "predictedMinimumGap" .= minimum predicted,
            "pairContactCost" .= sum costs,
            "hypotheticalGuardsPass" .= all (>= -1e-12) margins,
            "witnesses"
              .= [ object
                     [ "index" .= k,
                       "lower" .= xyz (C.witnessLower w),
                       "upper" .= xyz (C.witnessUpper w),
                       "gap" .= F.contactGap (C.witnessRow w),
                       "predictedGap" .= prediction,
                       "hypotheticalMargin" .= margin,
                       "pairCost" .= cost,
                       "row" .= rowValue (contactGuard pins (C.witnessRow w))
                     ]
                   | (k, (w, (prediction, (margin, cost)))) <- zip [0 :: Int ..] (zip ws (zip predicted (zip margins costs)))
                 ]
          ]
      )
  let flattened = start {samples = [p {position = let V2 x y = sampleMaterial p in V3 x y 0} | p <- samples start]}
  drawMaterial materialBox flattened >>= TIO.writeFile (output </> "material-pair.svg")
  let result =
        object
          [ "gallery" .= ("body-contact-55-93" :: Text),
            "issue" .= (358 :: Int),
            "newSolves" .= (0 :: Int),
            "newRepairs" .= (0 :: Int),
            "sourceAttempt" .= (10 :: Int),
            "validatedStates" .= (137 :: Int),
            "validatedTrials" .= (96 :: Int),
            "validatedRepairs" .= (30 :: Int),
            "identities" .= identity,
            "lowerTriangle" .= (93 :: Int),
            "upperTriangle" .= (55 :: Int),
            "guardedInSource" .= False,
            "initialRows" .= map rowValue initialRows,
            "savedDirection" .= map xyz proposal,
            "startPositions" .= map (xyz . position) (samples start),
            "freeVertices" .= [i | i <- [0 .. length (samples start) - 1], IM.notMember i pins],
            "states" .= entries,
            "contactTolerance" .= panelTolerance,
            "lengthTolerance" .= (1e-5 :: Double),
            "guardResidualTolerance" .= (1e-12 :: Double),
            "drawingScale" .= (600 :: Double),
            "pairBounds" .= boxValue pairBox,
            "tipBounds" .= boxValue tipBox,
            "materialBounds" .= boxValue materialBox,
            "continuousMotionChecked" .= False,
            "wholeCraneChecked" .= False
          ]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile "study/fold-material/body-contact-55-93.html"
  TIO.writeFile (destination </> "body-contact-55-93.html") (T.replace "/*BODY_PAIR_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Inspected 55–93 without solving. Wrote " ++ destination </> "body-contact-55-93.html")

drawInspection :: Box -> Inspected -> IO Text
drawInspection bounds (Inspected state cut ws vertex _ _) = do
  rings <- pairRings (loopMesh state)
  let corners = [Offset (V2 (-4) 4) (Label (Colour "#177970") 12 (xy (C.witnessLower w)) "●") | w <- ws]
      -- The two near-touching corners need separate labels to connect the
      -- drawing to the per-corner table; their material coordinates stay put.
      cornerLabels =
        [ Offset offset (Label (Colour "#177970") 12 (xy (C.witnessLower w)) (T.pack (show k)))
          | (k, w) <- zip [0 :: Int ..] ws,
            (wanted, offset) <- [(4, V2 (-12) (-12)), (5, V2 8 16)],
            k == wanted
        ]
      shapes =
        rings
          ++ [line "#b82643" 3 (map xy (intersectionEnds cut))]
          ++ corners
          ++ cornerLabels
          ++ [ Offset (V2 (-4) 4) (Label (Colour "#235e87") 14 (xy vertex) "●"),
               Offset (V2 8 (-12)) (Label (Colour "#235e87") 13 (xy vertex) "Vertex 30")
             ]
  pure (renderSvg page (diagramWithExtent bounds shapes))

drawMaterial :: Box -> MaterialMesh -> IO Text
drawMaterial bounds mesh = do
  rings <- pairRings mesh
  labels <- forM [55, 93] $ \i -> do
    points <- trianglePoints mesh i
    let centre = (1 / 3) *^ foldr (^+^) (V3 0 0 0) points
    pure (Label (Colour "#303630") 14 (xy centre) (T.pack (show i)))
  pure (renderSvg page {pageTitle = Just "Original material positions of triangles 55 and 93"} (diagramWithExtent bounds (rings ++ labels)))

pairRings :: MaterialMesh -> IO [Shape]
pairRings mesh = forM [(55, "#7056a2"), (93, "#c98225")] $ \(i, colour) -> do
  ps <- trianglePoints mesh i
  pure (line colour 1.4 (map xy (ps ++ take 1 ps)))

page :: Page
page = defaultPage {pageWidth = 560, pageHeight = 440, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "55 purple, 93 orange, vertex 30 blue, overlap corners green, intersection red"}

line :: Text -> Double -> [V2] -> Shape
line colour width = Polyline (solid (Colour colour) width)

straddles :: [Double] -> Bool
straddles ds = any (< -panelTolerance) ds && any (> panelTolerance) ds

lookupId :: String -> Int -> [a] -> IO a
lookupId label i values = maybe (die ("missing " ++ label ++ " " ++ show i)) pure (IM.lookup i (IM.fromList (zip [0 ..] values)))

triple :: (Int, Int, Int) -> [Int]
triple (a, b, c) = [a, b, c]

boxValue :: Box -> [[Double]]
boxValue (Box (V2 a b) (V2 c d)) = [[a, b], [c, d]]

vector :: [Double] -> IO V3
vector [x, y, z] = pure (V3 x y z)
vector _ = die "saved proposal has malformed coordinates"
