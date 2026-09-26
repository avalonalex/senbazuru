-- | Compare two saved body poses as static illustrations, never as new solves.
-- The archive reader checks material identity and historical measurements;
-- this module supplies the complete inherited source-panel order in each view.
-- spreadSurface's order list is restricted to world-XY overlaps, which would
-- lose some partners seen by an oblique camera. The temporary visibility
-- frame is never exported as paper. JSON retains projected regions so the
-- reported masks can be checked independently of SVG antialiasing.
module BodyVisibleLayersGallery (writeBodyVisibleLayers) where

import BodyCorrectionArchive (CorrectionArchive (..), checked, readCorrectionArchive, separateOutput)
import BodyPatch (patchSpread)
import BodyPatchSubdivision (seedPassed)
import Control.Monad (forM, forM_)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Map.Strict qualified as M
import Data.Maybe (isJust, isNothing)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import IllustrationComparison (illustrationPage, illustrationViews, sharedExtent)
import IllustrationVisibility
import Senbazuru.Diagram
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Query (Face (..), FoldError, frameFaces)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box, V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, signedArea, subtractConvex)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera (Basis, project)
import Senbazuru.Render.Projected (projectedForm)
import Senbazuru.Render.Svg
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

-- | SOURCE is the original body-subdivision archive, not a regenerated solve.
writeBodyVisibleLayers :: FilePath -> FilePath -> IO ()
writeBodyVisibleLayers source destination = do
  let output = destination </> "body-visible-layers"
  separateOutput source output
  archive <- readCorrectionArchive source
  states <- case archiveStates archive of
    [seed, _, second] -> pure [seed, second]
    _ -> die "expected seed and two saved corrections"
  cameras <- checked illustrationViews
  createDirectoryIfMissing True (output </> "source")
  forM_ (archiveFiles archive) $ \(name, bytes) -> BL.writeFile (output </> "source" </> name) bytes
  let study = archiveStudy archive
      fixture = patchSpread study
      owners = refinedPanels (spreadRefined fixture)
  reports <- forM cameras $ \(viewId, title, basis) -> do
    bounds <- checked (sharedExtent basis [mesh | (_, _, mesh, _) <- states])
    let page = illustrationPage title bounds
    results <- forM states $ \(name, _, mesh, _) -> do
      sheet <- checked (spreadSurface fixture mesh)
      let frame = surfaceFrame sheet
      inherited <- checked (inheritedOrders fixture frame)
      strictGeometry <- checked (seedPassed study mesh)
      let production = case projectedForm basis frame (faceOrders frame) of
            Left err -> "Refused: " <> explain err
            Right Nothing -> "Unsupported; whole-face fallback is not graded"
            Right (Just _) -> "Resolved"
      audits <- forM [("strict", 0), ("illustration", 0.1 / 600)] $ \(policy, allowance) -> do
        audit <- checked (illustrationVisibility allowance basis frame inherited)
        let stem = name ++ "-" ++ T.unpack viewId ++ "-" ++ policy
            polygons = fmap (regions basis owners) (auditForm audit)
            unresolved = unionRings (auditUncovered audit ++ [pairOverlap p | p <- auditPairs audit, isNothing (pairRelation p)])
            wire = [Polyline (solid (Colour "#a6a395") 0.4) (map (project basis) (faceCorners face) ++ take 1 (map (project basis) (faceCorners face))) | Right faces <- [frameFaces frame], face <- faces]
            picture = case (auditForm audit, polygons) of
              (Just seen, Just rs) -> paperShapes basis rs seen ++ [Fill (Colour "#bd4354") unresolved]
              _ -> wire ++ [Fill (Colour "#bd4354") unresolved]
        writeSvg output page bounds (stem ++ "-paper") picture
        writeSvg output page bounds (stem ++ "-unresolved") [Fill (Colour "#bd4354") unresolved]
        forM_ polygons $ \rs -> do
          writeSvg output page bounds (stem ++ "-owners") [Fill (palette owner) (concat [rings | (o, _, rings) <- rs, o == owner]) | owner <- S.toList (S.fromList owners)]
          writeSvg output page bounds (stem ++ "-silhouette") [Fill (Colour "#222222") (concat [rings | (_, _, rings) <- rs])]
        let record = object ["policy" .= policy, "allowancePixels" .= (allowance * 600), "stem" .= stem, "resolved" .= (isJust (auditForm audit) && null unresolved), "hasRegions" .= isJust (auditForm audit), "uncovered" .= map (map xy) (unionRings (auditUncovered audit)), "uncoveredAreaPixelsSquared" .= (360000 * sum (map (abs . signedArea) (unionRings (auditUncovered audit)))), "status" .= auditStatus audit, "inheritedTies" .= length [() | p <- auditPairs audit, pairDecision p == "inherited tie"], "unresolvedPairs" .= length [() | p <- auditPairs audit, isNothing (pairRelation p)], "pairs" .= map pairJson (auditPairs audit), "regions" .= fmap (map regionJson) polygons, "creases" .= fmap (map (map xy) . creaseMasks basis) (auditForm audit)]
        pure (record, audit)
      pure (object ["id" .= name, "strictGeometryPassed" .= strictGeometry, "productionStatus" .= production, "policies" .= map fst audits], map snd audits)
    comparisons <- case results of
      [(_, [strictA, approxA]), (_, [strictB, approxB])] -> do
        movement <- compareForms output page bounds basis owners (T.unpack viewId ++ "-movement") approxA approxB
        sensitivityA <- compareForms output page bounds basis owners (T.unpack viewId ++ "-seed-policy") strictA approxA
        sensitivityB <- compareForms output page bounds basis owners (T.unpack viewId ++ "-second-policy") strictB approxB
        pure (object ["poses" .= movement, "seedPolicy" .= sensitivityA, "secondPolicy" .= sensitivityB])
      _ -> die "incomplete visibility comparison"
    pure (object ["id" .= viewId, "title" .= title, "width" .= pageWidth page, "height" .= pageHeight page, "states" .= map fst results, "comparisons" .= comparisons])
  let report = object ["issue" .= (391 :: Int), "pixelsPerSheetUnit" .= (600 :: Int), "newSolves" .= (0 :: Int), "geometryChanged" .= False, "sourceFiles" .= map fst (archiveFiles archive), "views" .= reports]
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/body-visible-layers.html"
  TIO.writeFile (destination </> "body-visible-layers.html") (T.replace "/*VISIBLE_LAYER_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn ("Compared saved paper. Wrote " ++ destination </> "body-visible-layers.html")

-- A source order names the lower and upper physical panels in world Z.
-- FOLD's sign is relative to the upper triangle's normal. The visibility
-- helper subsequently converts that sign to the camera's near/far convention.
inheritedOrders :: CraneSpread -> Frame -> Either FoldError [FaceOrder]
inheritedOrders fixture frame = do
  faces <- frameFaces frame
  let tagged = zip faces (refinedPanels (spreadRefined fixture))
      reachable = closure (S.fromList (spreadOrders fixture))
  pure [FaceOrder (faceId lower) (faceId upper) (if v3z (polygonNormal (faceCorners upper)) > 0 then Below else Above) | (lower, a) <- tagged, (upper, b) <- tagged, S.member (a, b) reachable]
  where
    closure pairs = let more = S.union pairs (S.fromList [(a, c) | (a, b) <- S.toList pairs, (b', c) <- S.toList pairs, b == b']) in if more == pairs then pairs else closure more

type Regions = [(FaceId, Bool, [[V2]])]

regions :: Basis -> [FaceId] -> VisibleForm -> Regions
regions basis owners seen = [(owner, regionTopSide r, map (ccw . map (project basis)) (regionPieces r)) | r <- formRegions seen, Just owner <- [IM.lookup (unFaceId (regionFace r)) table]]
  where
    table = IM.fromList (zip [0 ..] owners)

ccw :: [V2] -> [V2]
ccw ring = if signedArea ring < 0 then reverse ring else ring

paperShapes :: Basis -> Regions -> VisibleForm -> [Shape]
paperShapes basis rs seen =
  [Fill (Colour colour) (concat [rings | (_, top, rings) <- rs, top == side]) | (side, colour) <- [(True, "#eee6cf"), (False, "#c58440")]]
    ++ [Fill (Colour "#404a44") (creaseMasks basis seen)]
    ++ [Polyline (solid (Colour "#404a44") 0.8) [project basis (visibleFrom edge), project basis (visibleTo edge)] | edge <- formEdges seen, visibleAssignment edge == Border]

-- A declared 0.8 px, square-ended crease ink mask, also used in the paper
-- drawing. J joins are numerical triangulation seams, not physical creases.
creaseMasks :: Basis -> VisibleForm -> [[V2]]
creaseMasks basis seen = unionRings [ring | edge <- formEdges seen, visibleAssignment edge `elem` [Mountain, Valley, Flat, Unassigned], let a = project basis (visibleFrom edge), let b = project basis (visibleTo edge), Just ring <- [ink a b]]
  where
    ink a b = case normalize (b ^-^ a) of
      Nothing -> Nothing
      Just (V2 dx dy) -> let n = (0.4 / 600) *^ V2 (-dy) dx in Just (ccw [a ^+^ n, b ^+^ n, b ^-^ n, a ^-^ n])

-- Polygon differences are computed before rasterization. The tiny clip area
-- tolerance is unchanged by the 0.1 px DEPTH allowance. Union avoids counting
-- a colour switch twice or an overlapping crease twice.
subtractRings :: [[V2]] -> [[V2]] -> [[V2]]
subtractRings = foldl' (\pieces cover -> concatMap (cut cover) pieces)
  where
    cut cover piece
      | abs (signedArea (clipConvex cover piece)) <= 1e-14 = [piece]
      | otherwise = subtractConvex 1e-14 cover piece

unionRings :: [[V2]] -> [[V2]]
unionRings = foldl' (\kept ring -> kept ++ subtractRings [ring] kept) []

difference :: [[V2]] -> [[V2]] -> [[V2]]
difference a b = unionRings (subtractRings a b ++ subtractRings b a)

compareForms :: FilePath -> Page -> Box -> Basis -> [FaceId] -> String -> VisibilityAudit -> VisibilityAudit -> IO Value
compareForms output page bounds basis owners stem a b = case (auditForm a, auditForm b) of
  (Just left, Just right) -> do
    let ra = regions basis owners left
        rb = regions basis owners right
        silhouette rs = concat [rings | (_, _, rings) <- rs]
        classified key rs = M.fromListWith (++) [(key owner side, rings) | (owner, side, rings) <- rs]
        labelDiff key = let x = classified key ra; y = classified key rb in unionRings (concat [difference (M.findWithDefault [] k x) (M.findWithDefault [] k y) | k <- S.toList (M.keysSet x `S.union` M.keysSet y)])
        missing = unionRings (auditUncovered a ++ auditUncovered b)
        uncertainty = 360000 * sum (map (abs . signedArea) missing)
        masks = [("silhouette", difference (silhouette ra) (silhouette rb)), ("colour", labelDiff (\_ side -> side)), ("owners", labelDiff const), ("creases", difference (creaseMasks basis left) (creaseMasks basis right))]
    values <- forM masks $ \(name, rawRings) -> do
      let unknown = if name == "creases" then unionRings (map inkUncertainty missing) else missing
          allowance = 360000 * sum (map (abs . signedArea) unknown)
          rings = subtractRings rawRings unknown
          measured = 360000 * sum (map (abs . signedArea) rings)
      writeSvg output page bounds (stem ++ "-" ++ name) [Fill (Colour "#c72d57") rings]
      pure (object ["kind" .= name, "stem" .= (stem ++ "-" ++ name), "areaPixelsSquared" .= measured, "areaUpperPixelsSquared" .= (measured + allowance), "rings" .= map (map xy) rings, "uncertaintyRings" .= map (map xy) unknown])
    pure (object ["available" .= True, "complete" .= null missing, "uncoveredUnionPixelsSquared" .= uncertainty, "uncovered" .= map (map xy) missing, "masks" .= values])
  _ -> pure (object ["available" .= False, "reason" .= ("One or both views unresolved; no fallback metrics" :: Text)])

-- Ink can extend 0.4 px beyond an unresolved paper patch. Expanding its
-- bounding box is conservative and keeps the uncertainty visible in the
-- reported interval; paper-area uncertainty alone would understate it.
inkUncertainty :: [V2] -> [V2]
inkUncertainty [] = []
inkUncertainty ring =
  let xs = [x | V2 x _ <- ring]
      ys = [y | V2 _ y <- ring]
      r = 0.4 / 600
      x0 = minimum xs - r
      x1 = maximum xs + r
      y0 = minimum ys - r
      y1 = maximum ys + r
   in [V2 x0 y0, V2 x1 y0, V2 x1 y1, V2 x0 y1]

pairJson :: PairAudit -> Value
pairJson p = object ["faces" .= let (a, b) = pairFaces p in [unFaceId a, unFaceId b], "depthRangePixels" .= let (lo, hi) = pairDepthRange p in [600 * lo, 600 * hi], "decision" .= pairDecision p, "overriddenDepthPixels" .= (600 * pairOverriddenDepth p), "overlap" .= map xy (pairOverlap p)]

regionJson :: (FaceId, Bool, [[V2]]) -> Value
regionJson (owner, side, rings) = object ["owner" .= unFaceId owner, "front" .= side, "rings" .= map (map xy) rings]

xy :: V2 -> [Double]
xy (V2 x y) = [x, y]

palette :: FaceId -> Colour
palette (FaceId i) = Colour (M.findWithDefault "#a785b1" (i `mod` 8) (M.fromList (zip [0 ..] ["#a76751", "#5a8d88", "#bc985c", "#718baa", "#98587b", "#899d63", "#be7850", "#8079a4"])))

writeSvg :: FilePath -> Page -> Box -> String -> [Shape] -> IO ()
writeSvg output page bounds name shapes = TIO.writeFile (output </> name ++ ".svg") (renderSvg page (diagramWithExtent bounds shapes))
