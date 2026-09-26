-- | Draw the saved 2–39 crossing in context, with no new solve. The ordinary
-- paper drawing and diagnostic overlays stay separate: a bright locator is
-- not an exposed orange patch. Full-segment coverage and original-plane depth
-- distinguish a buried geometric crossing from a visible drawing defect.
module BodyIntersectionContextGallery (writeIntersectionContext) where

import BodyContactDiagnosis (PairSection (..), pairSection)
import BodyCorrectionArchive (checked, readArchiveBytes, separateOutput, xyz)
import BodyIntersectionContext
import BodyOpeningArchive
import BodyPatch
import BodyPatchCheckpoints (SavedPoint (..))
import BodyVisibleLayersGallery (inheritedOrders, paperShapes, regions, writeSvg)
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as M
import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import IllustrationComparison (illustrationPage, illustrationViews, sharedExtent)
import IllustrationVisibility
import Senbazuru.Diagram
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces)
import Senbazuru.Fold.Types (FaceId (..), keyFrame)
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Origami.Visible (Region (..), VisibleForm (..))
import Senbazuru.Render.Camera (depth, project)
import Senbazuru.Render.Svg (Page (..), defaultPage)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

writeIntersectionContext :: FilePath -> FilePath -> IO ()
writeIntersectionContext source destination = do
  let output = destination </> "body-intersection-context"
  separateOutput source output
  archive <- readOpeningArchive source
  endpoint <- case reverse (openingPoints archive) of
    p : _ | savedIteration p == 40 -> pure p
    _ -> die "expected the saved forty-correction endpoint"
  let study = openingTarget archive
      fixture = patchSpread study
      mesh = savedMesh endpoint
      owners = refinedPanels (spreadRefined fixture)
      ownerMap = M.fromList (zip (map FaceId [0 ..]) owners)
      craneMap = M.fromList (zip (map FaceId [0 ..]) (patchFaces study))
  sheet <- checked (spreadSurface fixture mesh)
  saved <- loadFoldFile (source </> "endpoint.fold") >>= checked
  unless (keyFrame saved == materialFrame sheet) (die "endpoint.fold disagrees with the saved raw checkpoint or material")
  section <- checked (pairSection mesh (2, 39))
  (a, b) <- case intersectionEnds section of
    [x, y] | intersectionLength section > 0 -> pure (x, y)
    _ -> die "expected a nonzero saved 2–39 intersection"
  let frame = surfaceFrame sheet
  faces <- checked (frameFaces frame)
  inherited <- checked (inheritedOrders fixture frame)
  createDirectoryIfMissing True (output </> "source")
  forM_ ["endpoint.fold", "initial.json", "run.json"] $ \name ->
    readArchiveBytes (source </> name) >>= BL.writeFile (output </> "source" </> name)
  cameras <- checked illustrationViews
  views <- forM cameras $ \(viewId, title, basis) -> do
    audit <- checked (illustrationVisibility (0.1 / 600) basis frame inherited)
    seen <- maybe (die "visibility unresolved; cannot claim this crossing is hidden") pure (auditForm audit)
    let p = project basis a
        q = project basis b
        middle = 0.5 *^ (p ^+^ q)
        projectedLength = 600 * norm (q ^-^ p)
        pieces = [(regionFace r, map (project basis) ring) | r <- formRegions seen, ring <- regionPieces r]
        at t = p ^+^ (t *^ (q ^-^ p))
        originalAt t = a ^+^ (t *^ (b ^-^ a))
        faceMap = M.fromList [(faceId f, f) | f <- faces]
    unless (projectedLength > 0) (die "intersection projects to a point; segment coverage is undefined")
    hits <- forM [(fid, ring, interval) | (fid, ring) <- pieces, Just interval <- [segmentInterval (p, q) ring]] $ \(fid, ring, interval@(lo, hi)) -> do
      f <- maybe (die "visible triangle is missing from original frame") pure (M.lookup fid faceMap)
      margins <- forM [lo, hi] $ \t -> do
        coverDepth <- maybe (die "visible triangle has no plane depth") pure (planeDepth basis (faceCorners f) (at t))
        pure (600 * (depth basis (originalAt t) - coverDepth))
      let gap = minimum margins
          other = fid `notElem` [FaceId 2, FaceId 39]
          front = case margins of
            [x, y] | other -> positiveDepthInterval interval (x, y)
            _ -> Nothing
      owner <- maybe (die "triangle has no source panel") pure (M.lookup fid ownerMap)
      craneFace <- maybe (die "source panel has no crane face") pure (M.lookup owner craneMap)
      pure (interval, other, front, gap, object ["triangle" .= unFaceId fid, "sourcePanel" .= unFaceId owner, "craneFace" .= unFaceId craneFace, "interval" .= interval, "ring" .= map xy ring, "depthMarginsPixels" .= margins, "otherPaperDrawnOnTop" .= other, "geometricallyInFrontInterval" .= front])
    let coverage = coveredFraction [interval | (interval, True, _, _, _) <- hits]
        physicalCoverage = coveredFraction [interval | (_, _, Just interval, _, _) <- hits]
        pairCoverage = coveredFraction [interval | (fid, ring) <- pieces, fid `elem` [FaceId 2, FaceId 39], Just interval <- [segmentInterval (p, q) ring]]
        anyCoverage = coveredFraction [interval | (interval, _, _, _, _) <- hits]
        unknown = coveredFraction (mapMaybe (segmentInterval (p, q)) (auditUncovered audit))
        paper = paperShapes basis (regions basis owners seen) seen
        warning = [Fill (Colour "#bd4354") (auditUncovered audit)]
        mark = [Polyline (solid (Colour "#c62858") 1.5) [p, q]]
        stem = T.unpack viewId
        nearby = [f | f <- faces, faceId f `elem` [FaceId 2, FaceId 39]]
        xray =
          [Polyline (solid (Colour "#c9c7be") 0.4) (closed (map (project basis) (faceCorners f))) | f <- faces]
            ++ [Polyline (solid (Colour (if faceId f == FaceId 2 then "#167b94" else "#8e4cad")) 1.5) (closed (map (project basis) (faceCorners f))) | f <- nearby]
    -- Use the same extent as the previous comparison, hence the same ordinary
    -- drawing size. A crop changes the viewport, not the shape or its fitting.
    bounds <- checked (sharedExtent basis [openingSeed archive, openingInitial archive, mesh])
    let page = illustrationPage title bounds
    writeSvg output page bounds (stem ++ "-paper") (paper ++ warning)
    writeSvg output page bounds (stem ++ "-locator") (locator middle)
    writeSvg output page bounds (stem ++ "-xray") (xray ++ mark ++ locator middle)
    forM_ [4 :: Int, 64] $ \zoom -> do
      let z = fromIntegral zoom
          radius = 200 / (600 * z)
          crop = Box (middle ^-^ V2 radius radius) (middle ^+^ V2 radius radius)
          cropPage = defaultPage {pageWidth = 400, pageHeight = 400, pageMargin = 0, pageBackground = Nothing, pageTitle = Just (title <> " · magnified crop")}
          name = stem ++ "-crop-" ++ show zoom
      writeSvg output cropPage crop name (map (magnifyInk z) paper ++ warning)
      writeSvg output cropPage crop (name ++ "-marker") mark
    pure (object ["id" .= viewId, "title" .= title, "width" .= pageWidth page, "height" .= pageHeight page, "projectedEnds" .= map xy [p, q], "projectedLengthPixels" .= projectedLength, "coveredByOtherPaperPixels" .= (coverage * projectedLength), "pairVisiblePixels" .= (pairCoverage * projectedLength), "notCoveredInDrawingPixels" .= ((1 - coverage) * projectedLength), "geometricallyCoveredPixels" .= (physicalCoverage * projectedLength), "notGeometricallyHiddenPixels" .= ((1 - physicalCoverage) * projectedLength), "uncoveredSegmentPixels" .= ((1 - anyCoverage) * projectedLength), "coverageUncertaintyPixels" .= (unknown * projectedLength), "minimumCoverDepthPixels" .= case [gap | (_, True, _, gap, _) <- hits] of [] -> Nothing; gaps -> Just (minimum gaps), "hits" .= [value | (_, _, _, _, value) <- hits], "visibilityStatus" .= auditStatus audit, "visiblePieces" .= [object ["triangle" .= unFaceId fid, "ring" .= map xy ring] | (fid, ring) <- pieces], "uncoveredRings" .= map (map xy) (auditUncovered audit)])
  let report = object ["issue" .= (395 :: Int), "sourceIssue" .= (393 :: Int), "newSolves" .= (0 :: Int), "pair" .= ([2, 39] :: [Int]), "intersectionEnds" .= map xyz [a, b], "intersectionLengthPixels" .= (600 * intersectionLength section), "pixelsPerSheetUnit" .= (600 :: Int), "visibilityDepthAllowancePixels" .= (0.1 :: Double), "strictContactAccepted" .= False, "illustrationAccepted" .= False, "views" .= views]
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/body-intersection-context.html"
  TIO.writeFile (destination </> "body-intersection-context.html") (T.replace "/*INTERSECTION_CONTEXT_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn ("Wrote " ++ destination </> "body-intersection-context.html")

-- The box is 24 drawing pixels wide, deliberately larger than the defect.
locator :: V2 -> [Shape]
locator (V2 x y) = [Polyline (solid (Colour "#c62858") 1.2) (closed [V2 (x - r) (y - r), V2 (x + r) (y - r), V2 (x + r) (y + r), V2 (x - r) (y + r)])]
  where
    r = 12 / 600

closed :: [a] -> [a]
closed ps = ps ++ take 1 ps

-- Magnification is like enlarging a printed drawing: boundary ink grows too.
-- Crease ink is already represented by filled model-space polygons.
magnifyInk :: Double -> Shape -> Shape
magnifyInk zoom (Polyline stroke ps) = Polyline stroke {strokeWidth = zoom * strokeWidth stroke} ps
magnifyInk _ shape = shape

xy :: V2 -> [Double]
xy (V2 x y) = [x, y]
