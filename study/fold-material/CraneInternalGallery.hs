-- | Publish a bounded diagnosis of the two internal body folds. The maps
-- locate material, including buried layers, rather than draw an accepted
-- opened crane. Solver refusals carry their measured energy components so a
-- short rejected correction can be inspected without rerunning a long solve.
module CraneInternalGallery (writeCraneInternal, writeInternalTrial, internalMap) where

import Control.Exception (evaluate)
import Control.Monad (forM, forM_, unless)
import CraneInternal
import CraneRoot
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldContact (ContactRow (..))
import FoldMaterial (meshEdges)
import FoldRelaxation
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..), boxFromPoints)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck (..))
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import SparseSolve (LinearReport (..))
import SurfaceContact qualified as Contact
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)

controls :: [(String, Text, InternalControl)]
controls = [("original", "Original free patch", OriginalPatch), ("held", "Crease lines held", HeldLines), ("internal", "Only internal contact forces", InternalForces), ("held-internal", "Held lines + internal forces", HeldLinesInternalForces), ("fixed", "Whole patch held reference", FixedPatch), ("continued", "Original + 80 final-stage iterations", ContinuedPatch)]

writeCraneInternal :: FilePath -> IO ()
writeCraneInternal destination = do
  reports <- forM controls $ \(key, _, _) -> writeInternalTrial key destination
  let document = object ["runs" .= reports]
  BL.writeFile (destination </> "crane-internal" </> "checks.json") (encode document)
  template <- TIO.readFile "study/fold-material/crane-internal.html"
  TIO.writeFile (destination </> "crane-internal.html") (T.replace "/*INTERNAL_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)

-- | One named control is also an entry point, so profiling need not repeat
-- every unrelated solve. It writes the same report as the complete gallery.
writeInternalTrial :: String -> FilePath -> IO Value
writeInternalTrial key destination = do
  let named = controls ++ [("original-short", "Original patch · short profiling probe", OriginalPatch)]
  (title, control) <- case [(title, control) | (name, title, control) <- named, name == key] of
    [entry] -> pure entry
    _ -> die "internal control must be original, held, internal, held-internal, fixed, continued or original-short"
  let output = destination </> "crane-internal"
  createDirectoryIfMissing True output
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  study <- checked (internalStudy source control)
  let root = internalRoot study
      fixture = rootSpread root
      limit
        | key == "original-short" = 2
        | control == ContinuedPatch = 80
        | otherwise = 40
  initial <-
    if control == ContinuedPatch
      then do
        frame <- keyFrame <$> (loadFoldFile (output </> "original.fold") >>= checked)
        sheet <- checked (surfaceFromFrame frame >>= requireMaterialCoordinates)
        let mesh = spreadMesh fixture
        unless (facesVertices frame == [map VertexId [a, b, c] | (a, b, c) <- triangles mesh]) (die "the continuation needs the original diagnostic's triangle identities")
        pure mesh {samples = surfaceSamples sheet}
      else pure (spreadMesh fixture)
  forM_ [folded | key == "original", folded <- [False, True]] $ \folded -> TIO.writeFile (output </> (if folded then "folded.svg" else "material.svg")) (internalMap folded study)
  putStrLn ("Solving internal control " ++ key)
  hFlush stdout
  start <- getCPUTime
  (result, audit) <- checked (if control == ContinuedPatch then continueInternal (Settings limit 1e-5) study initial else solveInternal (Settings limit 1e-5) study)
  mesh <- checked (finalMesh result)
  _ <- evaluate (maxLengthError mesh + if converged result then 1 else 0)
  settled <- getCPUTime
  contact <- checked (spreadCheck fixture mesh)
  accepted <- checked (internalAccepted study result mesh)
  angles <- checked (originalCreaseError root mesh)
  measured <- snapshot study mesh
  refusals <- forM (rejectionSummaries audit) $ \summary -> do
    firstTrial <- trialReport study (firstRejection summary)
    lastTrial <- trialReport study (lastRejection summary)
    pure (object ["reason" .= explain (trialReason (firstRejection summary)), "count" .= rejectionCount summary, "first" .= firstTrial, "last" .= lastTrial])
  let report =
        object
          [ "id" .= key,
            "title" .= title,
            "accepted" .= accepted,
            "allContactForces" .= fullInternalForces study,
            "iterationLimitPerStage" .= limit,
            "continuedFromOriginal" .= (control == ContinuedPatch),
            "converged" .= converged result,
            "heldVertices" .= IM.size (spreadPins fixture),
            "sourceOrders" .= length (spreadOrders fixture),
            "forceOrders" .= length (internalRequirements study),
            "maxRelativeEdgeError" .= maxLengthError mesh,
            "maxOriginalAngleError" .= angles,
            "heldError" .= spreadHeldError fixture mesh,
            "bodyMovement" .= rootBodyMovement root mesh,
            "contact" .= contact,
            "crossingsBySourcePair" .= groupedCrossings fixture contact,
            "endpoint" .= measured,
            "equilibrium" .= fmap equilibrium (equilibriumCheck result),
            "checkpoints" .= [object ["iteration" .= completedIterations c, "lengthError" .= checkpointError c] | c <- checkpoints result],
            "blockedStages" .= [object ["iteration" .= blockedIteration b, "lengthWeight" .= blockedLengthWeight b] | b <- blockedStages audit],
            "refusals" .= refusals,
            "solveCpuSeconds" .= (fromIntegral (settled - start) / 1e12 :: Double),
            "continuousMotionChecked" .= False
          ]
  BL.writeFile (output </> key ++ "-check.json") (encode report)
  exportMesh fixture (output </> key ++ ".fold") title mesh
  forM_ (rejectionSummaries audit) $ \summary -> do
    let trial = lastRejection summary
        stem = key ++ "-" ++ show (rejectionKind summary)
    exportMesh fixture (output </> stem ++ "-start.fold") "Last rejected correction: start" (trialStart trial)
    exportMesh fixture (output </> stem ++ "-finish.fold") "Last rejected correction: proposal, not accepted" (trialFinish trial)
  putStrLn (key ++ ": accepted " ++ show accepted ++ ", converged " ++ show (converged result) ++ ", length " ++ show (maxLengthError mesh) ++ ", blocked " ++ show (blockedStages audit))
  hFlush stdout
  pure report

exportMesh :: CraneSpread -> FilePath -> Text -> MaterialMesh -> IO ()
exportMesh fixture path title mesh = do
  sheet <- checked (spreadSurface fixture mesh)
  BL.writeFile path (encode (FoldFile (Just 1.2) (Just "senbazuru internal crease diagnosis") Nothing (Just title) Nothing [] (materialFrame sheet) []))

equilibrium :: EquilibriumCheck -> Value
equilibrium check = let linear = equilibriumLinear check in object ["linearConverged" .= linearConverged linear, "linearIterations" .= linearIterations linear, "linearResidual" .= linearResidual linear, "linearThreshold" .= linearThreshold linear, "fullMovement" .= equilibriumMovement check, "factored" .= equilibriumFactored check]

trialReport :: InternalStudy -> RejectedTrial -> IO Value
trialReport study trial = do
  before <- snapshot study (trialStart trial)
  after <- snapshot study (trialFinish trial)
  let movement = maximum (0 : zipWith (\a b -> norm (position a ^-^ position b)) (samples (trialStart trial)) (samples (trialFinish trial)))
  pure (object ["iteration" .= trialIteration trial, "lengthWeight" .= trialLengthWeight trial, "scale" .= trialScale trial, "beforeEnergy" .= trialBeforeEnergy trial, "afterEnergy" .= trialAfterEnergy trial, "maxMovement" .= movement, "before" .= before, "after" .= after])

-- The unweighted length and contact sums reproduce the objective using the
-- recorded penalty weight; angular rows already include their spring weights.
snapshot :: InternalStudy -> MaterialMesh -> IO Value
snapshot study mesh = do
  let fixture = rootSpread (internalRoot study)
      points = IM.fromList (zip [0 ..] (samples mesh))
      vertex i = maybe (die "internal diagnostic lost a material vertex") pure (IM.lookup i points)
  lengths <- forM (meshEdges mesh) $ \(a, b) -> do
    p <- vertex a
    q <- vertex b
    let residual = norm (position p ^-^ position q) - norm (sampleMaterial p ^-^ sampleMaterial q)
    pure (residual * residual)
  angular <- checked (bendingRows (spreadHinges fixture) mesh)
  force <- contactStats fixture mesh (internalRequirements study)
  folds <- forM internalCreases $ \eid -> do
    let hinges = [h | h <- spreadHinges fixture, hingeRole h == SurfaceCrease eid]
        line = internalLineVertices study eid
    values <- mapM (checked . (`hingeAngle` points)) hinges
    pure (object ["crease" .= unEdgeId eid, "sharedVertices" .= S.size line, "heldLineVertices" .= length [i | i <- S.toList line, IM.member i (spreadPins fixture)], "maxAngleError" .= maximum (0 : [abs (angleError a (hingeRest h)) | ((a, _), h) <- zip values hinges])])
  pairs <- forM (internalPairs study) $ \pair -> do
    stats <- contactStats fixture mesh [pair]
    pure (object ["panels" .= [unFaceId (fst pair), unFaceId (snd pair)], "contacts" .= stats])
  pure (object ["lengthSquared" .= sum lengths, "angleSquared" .= sum [r * r | (_, r) <- angular], "forceContacts" .= force, "creases" .= folds, "internalPairs" .= pairs])

contactStats :: CraneSpread -> MaterialMesh -> [(FaceId, FaceId)] -> IO Value
contactStats fixture mesh orders = do
  model <- checked (Contact.prepareContact 0 (V3 0 0 1) orders (refinedPanels (spreadRefined fixture)) mesh)
  rows <- checked (Contact.orderedContacts model mesh)
  pure (object ["rows" .= length rows, "negativeRows" .= length [() | r <- rows, contactGap r < 0], "squaredPenetration" .= sum [let gap = min 0 (contactGap r) in gap * gap | r <- rows], "minGap" .= minimum (0 : map contactGap rows)])

groupedCrossings :: CraneSpread -> ContactCheck -> Value
groupedCrossings fixture contact = toValue (M.fromListWith (+) [(ordered a b, 1 :: Int) | (x, y) <- crossingPanels contact, Just a <- [M.lookup x owners], Just b <- [M.lookup y owners]])
  where
    owners = M.fromList [("triangle-" <> tshow i, unFaceId owner) | (i, owner) <- zip [0 :: Int ..] (refinedPanels (spreadRefined fixture))]
    ordered a b = (min a b, max a b)
    toValue groups = object ["pairs" .= [object ["panels" .= [a, b], "count" .= n] | ((a, b), n) <- M.toAscList groups]]

-- | Original-sheet context and a folded x-ray close-up. Both locate the SAME
-- material lines; the folded view includes buried panels without displacing them.
internalMap :: Bool -> InternalStudy -> Text
internalMap folded study = renderSvg page drawing
  where
    root = internalRoot study
    fixture = rootSpread root
    mesh = refinedMesh (spreadRefined fixture)
    point p = if folded then let V3 x y _ = position p in V2 x y else sampleMaterial p
    points = IM.fromList [(i, point p) | (i, p) <- zip [0 ..] (samples mesh)]
    corners ids = [p | i <- ids, Just p <- [IM.lookup i points]]
    tagged = zip (triangles mesh) (refinedPanels (spreadRefined fixture))
    selected = [(t, owner) | (t, owner) <- tagged, S.member owner (rootNeighbours root)]
    ring (a, b, c) = corners [a, b, c]
    colour eid = Colour (if eid == EdgeId 26 then "#397f88" else "#b35836")
    pale owners = Colour (if FaceId 8 `elem` owners then "#b5d4d5" else "#e7c4b1")
    shapes =
      [Fill (Colour "#e5dfd3") [ring tri | (tri, _) <- if folded then selected else tagged]]
        ++ [Fill (pale [a, b]) [ring tri | (tri, owner) <- selected, owner `elem` [a, b]] | (a, b) <- internalPairs study]
        ++ [Polyline (solid (Colour "#9b968b") 0.5) (corners [a, b]) | (eid, (a, b)) <- refinedEdges (spreadRefined fixture), eid `notElem` internalCreases, not folded || (S.member a patchPoints && S.member b patchPoints)]
        ++ [Polyline (solid (colour eid) 2.4) (corners [a, b]) | (eid, (a, b)) <- refinedEdges (spreadRefined fixture), eid `elem` internalCreases]
        ++ [Offset (V2 (-3) 4) (Label (if IM.member i (spreadPins fixture) then Colour "#242923" else Colour "#77786e") 17 p (if IM.member i (spreadPins fixture) then "+" else "·")) | i <- S.toList linePoints, Just p <- [IM.lookup i points]]
    linePoints = S.unions (map (internalLineVertices study) internalCreases)
    patchPoints = S.fromList [v | ((a, b, c), _) <- selected, v <- [a, b, c]]
    extent = fromMaybe (Box (V2 0 0) (V2 1 1)) (boxFromPoints (if folded then concatMap (ring . fst) selected else IM.elems points))
    drawing = diagramWithExtent extent shapes
    page = defaultPage {pageWidth = 640, pageHeight = 430, pageMargin = 35, pageBackground = Nothing, pageTitle = Just (if folded then "Folded x-ray of internal body creases" else "Material location of internal body creases")}

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
